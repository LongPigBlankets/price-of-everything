#!/usr/bin/env python3
"""Serve the knob renderer and save the frames it posts.

Run this, open http://127.0.0.1:8765/index.html?export in a browser, and the page
renders the seven detent frames (9 o'clock -> 3 o'clock) into assets/ui/knob/.
Add &variant=clean for the glossy clean variant, which goes to assets/ui/knob_clean/.
"""
import http.server
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
UI = HERE.parents[1] / "assets" / "ui"
FRAME = re.compile(r"^/frames/(?:([a-z]+)/)?(knob_\d\.png)$")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

    def do_POST(self):
        match = FRAME.match(self.path)
        if not match:
            self.send_error(404)
            return
        data = self.rfile.read(int(self.headers["Content-Length"]))
        if not data.startswith(b"\x89PNG"):
            self.send_error(400, "expected a PNG body")
            return
        variant, name = match.groups()
        out = UI / (f"knob_{variant}" if variant else "knob")
        out.mkdir(parents=True, exist_ok=True)
        (out / name).write_bytes(data)
        print(f"saved {out / name}")
        self.send_response(204)
        self.end_headers()


if __name__ == "__main__":
    print(f"http://127.0.0.1:8765/index.html?export -> {UI}")
    http.server.ThreadingHTTPServer(("127.0.0.1", 8765), Handler).serve_forever()
