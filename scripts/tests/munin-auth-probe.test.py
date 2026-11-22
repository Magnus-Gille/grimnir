#!/usr/bin/env python3
"""Hermetic tests for scripts/munin-auth-probe.py against a local fake /mcp (GRIM-249)."""
import http.server, json, os, subprocess, sys, tempfile, threading, unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SCRIPT = os.path.join(ROOT, "scripts/munin-auth-probe.py")
GOOD = "goodTOKEN0123456789abcdef"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        ok = self.headers.get("Authorization") == f"Bearer {GOOD}"
        self.send_response(200 if ok else 401)
        self.end_headers()
    def log_message(self, *a):
        pass


class Redirector(http.server.BaseHTTPRequestHandler):
    seen = []
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(302)
        self.send_header("Location", f"http://127.0.0.1:{Target.srv.server_port}/x")
        self.end_headers()
    def log_message(self, *a):
        pass


class Target(http.server.BaseHTTPRequestHandler):
    hits = []
    def _h(self):
        Target.hits.append(self.headers.get("Authorization"))
        self.send_response(200); self.end_headers()
    do_GET = do_POST = _h
    def log_message(self, *a):
        pass


class T(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.srv = http.server.HTTPServer(("127.0.0.1", 0), Handler)
        cls.url = f"http://127.0.0.1:{cls.srv.server_port}/mcp"
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()

    def setUp(self):
        self.d = tempfile.mkdtemp()

    def mk(self, name, text, mode=0o600):
        p = os.path.join(self.d, name)
        with open(p, "w") as fh:
            fh.write(text)
        os.chmod(p, mode)
        return p

    def run_probe(self, *args):
        p = subprocess.run([sys.executable, "-B", "-I", SCRIPT, *args], capture_output=True, text=True)
        return p.returncode, p.stdout + p.stderr

    def test_good_env_token_ok_and_never_printed(self):
        f = self.mk("a.env", f"X=1\nMUNIN_API_KEY={GOOD}\n")
        code, out = self.run_probe("--url", self.url, "--file", f, "--format", "env", "--key", "MUNIN_API_KEY")
        self.assertEqual(code, 0); self.assertIn("HTTP 200", out); self.assertNotIn(GOOD, out)

    def test_good_json_token_ok(self):
        f = self.mk("c.json", json.dumps({"auth_token": GOOD}))
        self.assertEqual(self.run_probe("--url", self.url, "--file", f, "--format", "json", "--key", "auth_token")[0], 0)

    def test_redirect_not_followed_and_token_not_leaked(self):
        Target.srv = http.server.HTTPServer(("127.0.0.1", 0), Target)
        threading.Thread(target=Target.srv.serve_forever, daemon=True).start()
        red = http.server.HTTPServer(("127.0.0.1", 0), Redirector)
        threading.Thread(target=red.serve_forever, daemon=True).start()
        try:
            f = self.mk("r.env", f"MUNIN_API_KEY={GOOD}\n")
            code, out = self.run_probe("--url", f"http://127.0.0.1:{red.server_port}/mcp", "--file", f,
                                       "--format", "env", "--key", "MUNIN_API_KEY")
        finally:
            red.shutdown(); Target.srv.shutdown()
        self.assertEqual(code, 3); self.assertIn("HTTP 302", out)
        self.assertEqual(Target.hits, [])

    def test_host_guard_rejects_lookalikes_and_userinfo(self):
        f = self.mk("g.env", f"MUNIN_API_KEY={GOOD}\n")
        for u in ("http://127.0.0.1.example.invalid/mcp", "http://localhost.evil.tld/mcp",
                  "http://127.0.0.1@evil.tld/mcp", "https://user:pw@example.com/mcp"):
            code, _ = self.run_probe("--url", u, "--file", f, "--format", "env", "--key", "MUNIN_API_KEY")
            self.assertEqual(code, 2, u)

    def test_non_object_json_is_clean_error(self):
        f = self.mk("n.json", "[1]")
        code, out = self.run_probe("--url", self.url, "--file", f, "--format", "json", "--key", "k")
        self.assertEqual(code, 2); self.assertNotIn("Traceback", out)

    def test_wrong_token_denied(self):
        f = self.mk("b.env", "MUNIN_API_KEY=wrongTOKEN\n")
        code, out = self.run_probe("--url", self.url, "--file", f, "--format", "env", "--key", "MUNIN_API_KEY")
        self.assertEqual(code, 3); self.assertIn("HTTP 401", out); self.assertNotIn("wrongTOKEN", out)

    def test_loose_file_missing_key_and_plain_http_remote_refused(self):
        loose = self.mk("l.env", f"MUNIN_API_KEY={GOOD}\n", 0o644)
        self.assertEqual(self.run_probe("--url", self.url, "--file", loose, "--format", "env", "--key", "MUNIN_API_KEY")[0], 2)
        f = self.mk("m.env", "OTHER=1\n")
        self.assertEqual(self.run_probe("--url", self.url, "--file", f, "--format", "env", "--key", "MUNIN_API_KEY")[0], 2)
        ok = self.mk("o.env", f"MUNIN_API_KEY={GOOD}\n")
        code, out = self.run_probe("--url", "http://192.0.2.1/mcp", "--file", ok, "--format", "env", "--key", "MUNIN_API_KEY")
        self.assertEqual(code, 2); self.assertNotIn(GOOD, out)

    def test_unreachable(self):
        f = self.mk("u.env", f"MUNIN_API_KEY={GOOD}\n")
        self.assertEqual(self.run_probe("--url", "http://127.0.0.1:9/mcp", "--file", f, "--format", "env", "--key", "MUNIN_API_KEY")[0], 4)


if __name__ == "__main__":
    unittest.main()
