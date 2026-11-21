#!/usr/bin/env python3
"""Hermetic tests for scripts/rotate-credential.py (GRIM-249). Fake commands only."""
import importlib.util, json, os, stat, sys, tempfile, unittest
from io import StringIO
from contextlib import redirect_stdout, redirect_stderr

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
spec = importlib.util.spec_from_file_location("rc", os.path.join(ROOT, "scripts/rotate-credential.py"))
rc = importlib.util.module_from_spec(spec); spec.loader.exec_module(rc)

SECRET = "s3cr3t-TOKEN-0123456789abcdef"


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        self.sink = os.path.join(self.d, "installed")
        self.audit = os.path.join(self.d, "audit.jsonl")
        self.py = sys.executable
        self.cfg = os.path.join(self.d, "cfg.json")

    def write(self, **over):
        e = {
            "preflight": [self.py, "-c", "pass"],
            "issue": [self.py, "-c", f"print('{SECRET}')"],
            "install": [self.py, "-c", f"import sys;open({self.sink!r},'w').write(sys.stdin.read())"],
            "verify": [self.py, "-c", "pass"],
            "reversal": "restore backup and restart",
            "audit_log": self.audit,
        }
        e.update(over)
        with open(self.cfg, "w") as fh:
            json.dump({"credentials": {"c1": e}}, fh)
        os.chmod(self.cfg, 0o600)

    def run_main(self, mode, confirm=lambda i, e: True):
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc_ = rc.main([mode, "c1", "--config", self.cfg], confirm=confirm)
        return rc_, out.getvalue() + err.getvalue()

    def events(self):
        if not os.path.exists(self.audit):
            return []
        with open(self.audit) as fh:
            return [json.loads(l)["event"] for l in fh]

    def test_plan_runs_nothing(self):
        self.write()
        code, out = self.run_main("plan")
        self.assertEqual(code, 0); self.assertIn("PLAN", out)
        self.assertFalse(os.path.exists(self.sink)); self.assertEqual(self.events(), [])

    def test_execute_pipes_secret_to_installer_only(self):
        self.write()
        code, out = self.run_main("execute")
        self.assertEqual(code, 0)
        with open(self.sink) as fh:
            self.assertEqual(fh.read().strip(), SECRET)
        self.assertNotIn(SECRET, out)
        with open(self.audit) as fh:
            self.assertNotIn(SECRET, fh.read())
        self.assertEqual(self.events(), ["start", "ok"])
        self.assertEqual(stat.S_IMODE(os.stat(self.audit).st_mode), 0o600)

    def test_confirmation_required(self):
        self.write()
        code, _ = self.run_main("execute", confirm=lambda i, e: False)
        self.assertEqual(code, rc.EXIT_REFUSED); self.assertFalse(os.path.exists(self.sink))

    def test_non_tty_default_refuses(self):
        self.write()
        out, err = StringIO(), StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = rc.main(["execute", "c1", "--config", self.cfg])
        self.assertEqual(code, rc.EXIT_REFUSED); self.assertFalse(os.path.exists(self.sink))

    def test_preflight_failure_issues_nothing(self):
        self.write(preflight=[self.py, "-c", "import sys;sys.exit(1)"],
                   issue=[self.py, "-c", f"open({self.sink!r},'w');print('x')"])
        code, _ = self.run_main("execute")
        self.assertEqual(code, rc.EXIT_FAILED); self.assertFalse(os.path.exists(self.sink))
        self.assertIn("preflight-failed", self.events())

    def test_install_failure_reports_not_delivered(self):
        self.write(install=[self.py, "-c", "import sys;sys.stdin.read();sys.exit(5)"])
        code, out = self.run_main("execute")
        self.assertEqual(code, rc.EXIT_NOT_DELIVERED); self.assertIn("issue-or-install-failed", self.events())
        with open(self.audit) as fh:
            self.assertNotIn(SECRET, out + fh.read())

    def test_issue_failure(self):
        self.write(issue=[self.py, "-c", "import sys;sys.exit(7)"])
        code, _ = self.run_main("execute")
        self.assertEqual(code, rc.EXIT_NOT_DELIVERED); self.assertIn("issue-or-install-failed", self.events())

    def test_installer_exits_without_reading_is_not_exit_1(self):
        self.write(install=[self.py, "-c", "import sys;sys.exit(5)"])
        self.assertEqual(self.run_main("execute")[0], rc.EXIT_NOT_DELIVERED)

    def test_issuer_fails_after_emitting(self):
        self.write(issue=[self.py, "-c", f"print('{SECRET}');import sys;sys.exit(9)"])
        self.assertEqual(self.run_main("execute")[0], rc.EXIT_NOT_DELIVERED)

    def test_missing_binary_rejected_before_issuing(self):
        self.write(install=["/nonexistent/installer"])
        self.assertEqual(self.run_main("execute")[0], rc.EXIT_INVALID)
        self.assertEqual(self.events(), [])

    def test_loose_config_rejected(self):
        self.write(); os.chmod(self.cfg, 0o644)
        self.assertEqual(self.run_main("plan")[0], rc.EXIT_INVALID)

    def test_symlink_audit_log_rejected(self):
        real = os.path.join(self.d, "real"); open(real, "w").close()
        os.symlink(real, self.audit)
        self.write()
        with self.assertRaises(OSError):
            self.run_main("execute")

    def test_plan_does_not_print_commands(self):
        self.write(preflight=[self.py, "-c", "pass", "secret-host.example"])
        self.assertNotIn("secret-host", self.run_main("plan")[1])

    def test_verify_failure(self):
        self.write(verify=[self.py, "-c", "import sys;sys.exit(1)"])
        code, _ = self.run_main("execute")
        self.assertEqual(code, rc.EXIT_VERIFY_FAILED); self.assertIn("verify-failed", self.events())

    def test_invalid_config(self):
        self.write(issue="not-a-list")
        code, _ = self.run_main("plan")
        self.assertEqual(code, rc.EXIT_INVALID)
        self.write(audit_log="relative.jsonl")
        self.assertEqual(self.run_main("plan")[0], rc.EXIT_INVALID)


if __name__ == "__main__":
    unittest.main()
