#!/usr/bin/env python3
"""Serve the gauge renderer and save the layers it posts.

Run this, open http://127.0.0.1:8765/index.html?export in a browser, and the page renders
every gauge layer into assets/ui/gauge/. The tab title shows "export done" plus the layout
numbers (pixels per unit, needle shadow offset) that scripts/panel_gauge.gd uses.
"""
import http.server
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "assets" / "ui" / "gauge"
LAYER = re.compile(r"^/layers/(gauge_[a-z_]+\.png)$")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

    def do_POST(self):
        match = LAYER.match(self.path)
        if not match:
            self.send_error(404)
            return
        data = self.rfile.read(int(self.headers["Content-Length"]))
        if not data.startswith(b"\x89PNG"):
            self.send_error(400, "expected a PNG body")
            return
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / match.group(1)).write_bytes(data)
        print(f"saved {OUT / match.group(1)}")
        self.send_response(204)
        self.end_headers()


if __name__ == "__main__":
    print(f"http://127.0.0.1:8765/index.html?export -> {OUT}")
    http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
