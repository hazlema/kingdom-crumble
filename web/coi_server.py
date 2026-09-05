#!/usr/bin/env python3
"""Dev server for the web build: static files + the COOP/COEP headers
WASM threads demand (same pair Netlify's _headers file provides)."""
import http.server
import os
import sys

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8899
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web"))


class COIHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):
        sys.stderr.write("%s\n" % (fmt % args))


print(f"serving build/web with COI headers on :{PORT}")
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), COIHandler).serve_forever()
