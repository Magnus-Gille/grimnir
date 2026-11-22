#!/usr/bin/env python3
"""Hermetic tests for scripts/install-secret-stdin.py (GRIM-249)."""
import json, os, stat, subprocess, sys, tempfile, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts/install-secret-stdin.py")
NEW = "newTOKEN0123456789abcdefghijklmnop"
OLD = "oldTOKEN9876543210zyxwvutsrqponmlk"


def run(args, stdin):
    p = subprocess.run([sys.executable, "-B", "-I", SCRIPT, *args], input=stdin, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp()
        os.chmod(self.d, 0o700)
        self.env = os.path.join(self.d, "app.env")
        self.js = os.path.join(self.d, "cred.json")
        self.write(self.env, f"A=1\nMUNIN_API_KEY={OLD}\nB=2\n")
        self.write(self.js, json.dumps({"auth_token": OLD, "keep": "x"}))

    def write(self, path, text, mode=0o600):
        with open(path, "w") as fh:
            fh.write(text)
        os.chmod(path, mode)

    def read(self, path):
        with open(path) as fh:
            return fh.read()

    def test_env_replaces_only_the_key_and_keeps_prev(self):
        code, out = run(["--file", self.env, "--format", "env", "--key", "MUNIN_API_KEY"], NEW + "\n")
        self.assertEqual(code, 0); self.assertNotIn(NEW, out)
        self.assertEqual(self.read(self.env), f"A=1\nMUNIN_API_KEY={NEW}\nB=2\n")
        self.assertIn(OLD, self.read(self.env + ".prev"))
        for p in (self.env, self.env + ".prev"):
            self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o600)

    def test_json_sets_field_and_preserves_others(self):
        code, _ = run(["--file", self.js, "--format", "json", "--key", "auth_token"], NEW)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(self.read(self.js)), {"auth_token": NEW, "keep": "x"})

    def test_missing_or_duplicate_key_refused_and_file_untouched(self):
        self.assertEqual(run(["--file", self.env, "--format", "env", "--key", "NOPE"], NEW)[0], 2)
        self.write(self.env, "K=1\nK=2\n")
        self.assertEqual(run(["--file", self.env, "--format", "env", "--key", "K"], NEW)[0], 2)
        self.assertEqual(self.read(self.env), "K=1\nK=2\n")

    def test_loose_mode_symlink_and_relative_refused(self):
        os.chmod(self.env, 0o644)
        self.assertEqual(run(["--file", self.env, "--format", "env", "--key", "MUNIN_API_KEY"], NEW)[0], 2)
        link = os.path.join(self.d, "link.env"); os.symlink(self.js, link)
        self.assertEqual(run(["--file", link, "--format", "json", "--key", "auth_token"], NEW)[0], 2)
        self.assertEqual(run(["--file", "rel.env", "--format", "env", "--key", "X"], NEW)[0], 2)

    def test_bad_stdin_writes_nothing(self):
        before = self.read(self.env)
        for bad in ("", "two words", "a=b", 'q"uote', "x" * 5000, "é"):
            code, out = run(["--file", self.env, "--format", "env", "--key", "MUNIN_API_KEY"], bad)
            self.assertEqual(code, 3, bad[:10]); self.assertNotIn("x" * 50, out)
        self.assertEqual(self.read(self.env), before)
        self.assertFalse(os.path.exists(self.env + ".prev"))

    def test_no_temp_files_left(self):
        run(["--file", self.env, "--format", "env", "--key", "MUNIN_API_KEY"], NEW)
        self.assertEqual([f for f in os.listdir(self.d) if f.startswith(".tmp-install-")], [])


if __name__ == "__main__":
    unittest.main()
