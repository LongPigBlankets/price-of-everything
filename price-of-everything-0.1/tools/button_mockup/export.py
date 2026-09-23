#!/usr/bin/env python3
"""Serve the building-panel control study and save the layers its export mode posts.

Run this from the Godot project root, then open http://127.0.0.1:8771/cluster.html?export in a
browser. The page renders every layer of the v3 panel parts and posts them here; they are written
into assets/ui/bdp_v3/ with layout.json. The tab title changes to "export done" when it has finished.
Add &only=lamp,scroll (any of block, footer, backing, section, keys, lamp, scroll, seam, title, enamel) to render just
those sets; the page then reads the current layout.json from here and updates only their entries.
An optional argument sets the port (default 8771).
"""
import http.server
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "assets" / "ui" / "bdp_v3"
LAYER = re.compile(r"^/layers/([a-z0-9_]+\.(?:png|json))$")
FONT = re.compile(r"^/fonts/([A-Za-z0-9_-]+\.ttf)$")   # the game's fonts, for lettering that matches it


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

    def do_GET(self):
        font = FONT.match(self.path)
        if font:
            path = HERE.parents[1] / "assets" / "fonts" / font.group(1)
            if not path.exists():
                self.send_error(404)
                return
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "font/ttf")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        if self.path == "/layers/layout.json":
            path = OUT / "layout.json"
            if not path.exists():
                self.send_error(404)
                return
            data = path.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return
        super().do_GET()

    def do_POST(self):
        match = LAYER.match(self.path)
        if not match:
            self.send_error(404)
            return
        data = self.rfile.read(int(self.headers["Content-Length"]))
        name = match.group(1)
        if name.endswith(".png") and not data.startswith(b"\x89PNG"):
            self.send_error(400, "expected a PNG body")
            return
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / name).write_bytes(data)
        print(f"saved {OUT / name}", flush=True)
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8771
    print(f"http://127.0.0.1:{port}/cluster.html?export -> {OUT}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
