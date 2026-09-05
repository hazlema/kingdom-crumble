#!/usr/bin/env python3
"""Plain static server, deliberately NO COI headers -- simulates itch.io
hosting for the threadless build."""
import http.server, os, sys
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8898
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "itch"))
class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()
    def log_message(self, f, *a): pass
print(f"plain server (no COI) on :{PORT}")
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
