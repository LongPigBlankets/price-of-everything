#!/usr/bin/env python3
"""Serve the building-panel control study and save the layers its export mode posts.

Run this from the Godot project root, then open http://127.0.0.1:8771/cluster.html?export in a
browser. The page renders every layer of the v3 control block, the Sell / Demolish footer and the
Close / Back keycaps, and posts them here; they are written into assets/ui/bdp_v3/ with layout.json.
The tab title changes to "export done" when it has finished.
"""
import http.server
import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[1] / "assets" / "ui" / "bdp_v3"
LAYER = re.compile(r"^/layers/([a-z0-9_]+\.(?:png|json))$")


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(HERE), **kwargs)

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
    print(f"http://127.0.0.1:8771/cluster.html?export -> {OUT}", flush=True)
    http.server.ThreadingHTTPServer(("127.0.0.1", 8771), Handler).serve_forever()
