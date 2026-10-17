#!/usr/bin/env python3
"""Build local visual-review contact sheets and an HTML gallery from captures."""
import html
import json
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

def build(folder, pending=False):
    report = json.loads((folder / "report.json").read_text())
    notes_path = folder / "visual-notes.json"
    notes = json.loads(notes_path.read_text()) if notes_path.exists() else {}
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 20)
    groups = list(report["regions"].items())
    if pending:
        groups = [(key, value) for key, value in groups if key not in notes]
    files = []
    for start in range(0, len(groups), 4):
        canvas = Image.new("RGB", (1560, 1252), (245, 243, 235))
        draw = ImageDraw.Draw(canvas)
        for row, (key, region) in enumerate(groups[start:start+4]):
            for col, zoom in enumerate(["region", "medium", "near"]):
                im = Image.open(folder / f"{key}-{zoom}.png")
                im.thumbnail((520, 283))
                canvas.paste(im, (col * 520, row * 313 + 30))
                draw.text((col * 520 + 6, row * 313 + 4), f"{region['name']} · {zoom}", fill=(28, 37, 40), font=font)
        name = f"{'pending' if pending else 'contact'}-{start//4+1:02d}.png"
        canvas.save(folder / name)
        files.append(name)
    if pending:
        print(json.dumps({'contact_sheets': files, 'regions': [key for key, _ in groups]}))
        return
    chunks = ["<!doctype html><meta charset='utf-8'><title>Continent visual review</title><style>body{background:#f4f1e7;color:#253a41;font:16px system-ui;margin:24px}article{margin:24px 0}h2{margin-bottom:8px}section{display:grid;grid-template-columns:repeat(3,1fr);gap:8px}img{width:100%}a{color:inherit}small{color:#526164}</style><h1>Continent visual review</h1><p>Regional, medium and near captures of the current layout, with the same content keys as the installed package. Click an image for full resolution. Capture-time generation is separate from the fresh installed-package loading verification.</p>"]
    for key, region in groups:
        chunks.append(f"<article id='{html.escape(key)}'><h2>{html.escape(region['name'])}</h2><small>{html.escape(region['identity'])} · {len(region['tiles'])} tiles</small>")
        if key in notes:
            chunks.append(f"<p>{html.escape(notes[key])}</p>")
        chunks.append("<section>")
        for zoom in ["region", "medium", "near"]:
            name = f"{key}-{zoom}.png"
            chunks.append(f"<a href='{name}'><img loading='lazy' src='{name}' alt='{html.escape(region['name'])} {zoom}'>{zoom}</a>")
        chunks.append("</section></article>")
    chunks.append("<h1>Crossing and clearance candidates</h1><p>Conservative geometric candidates, checked visually; a flag alone does not prove a clash.</p><section>")
    mapping_path = folder / "issue-image-map.json"
    mapping = json.loads(mapping_path.read_text()) if mapping_path.exists() else {
        item["file"]: [item] for item in report.get("issue_views", [])
    }
    verdict_path = folder / "issue-verdicts.json"
    verdicts = json.loads(verdict_path.read_text()) if verdict_path.exists() else {}
    for name, issues in mapping.items():
        label = html.escape("; ".join(item["region"] + " · " + item["kind"] + " · " + item["tile"] for item in issues))
        verdict = html.escape(verdicts.get(name, "Geometric candidate; this capture alone does not establish a physical collision."))
        chunks.append(f"<article><a href='{name}'><img loading='lazy' src='{name}' alt='{label}'>{label}</a><p>{verdict}</p></article>")
    chunks.append("</section>")
    (folder / "gallery.html").write_text("".join(chunks))
    print(json.dumps({"contact_sheets": files, "regions": len(groups), "issue_views": len(mapping)}))

if __name__ == "__main__":
    build(Path(sys.argv[1]), '--pending' in sys.argv[2:])
