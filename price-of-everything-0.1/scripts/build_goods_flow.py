#!/usr/bin/env python3
"""Build the goods production-flow graph as data (+ an HTML visualisation).

Reads the in-game goods and recipe tables and derives the directed graph of
"which good feeds into which good". Where a good can be produced by more than
one recipe, the *least-efficient* recipe is selected to define its inputs:

    1. most distinct inputs            (more ingredients  = less efficient)
    2. then highest power (energy_req) (more power        = less efficient)
    3. then largest total input qty    (final tie-breaker)

A recipe is treated as a producer of good X when X is its primary output
(output_1); a good that is only ever a by-product falls back to any recipe
that lists it as an output.

Two outputs are written from the single computed model:

  * goods_flow.json        structured data: nodes (with their defining recipe,
                           inputs, the goods they feed, hierarchy tier, and the
                           recipe alternatives that were *not* chosen), the edge
                           list, the tier groupings, and run metadata.
  * goods_flow_chart.html  a wide left-to-right flow chart (raw materials on the
                           left, finished goods on the right). Arrows carry a
                           white outline so overlapping arrows read clearly as
                           over/under. No quantities are drawn on the chart.

Usage:
    python3 build_goods_flow.py                 # default repo paths
    python3 build_goods_flow.py --data DIR --out DIR

The goods table (Goods - goodsMVP.csv) and the recipe table (recipes_all.csv)
are the files the Godot client loads (see scripts/catalog.gd).
"""

from __future__ import annotations

import argparse
import csv
import html
import json
import math
import os
from collections import defaultdict

# --------------------------------------------------------------------------- #
# Paths
# --------------------------------------------------------------------------- #
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)              # price-of-everything-0.1
DEFAULT_DATA_DIR = os.path.join(PROJECT_DIR, "data")
DEFAULT_OUT_DIR = os.path.join(PROJECT_DIR, "docs")

GOODS_CSV = "Goods - goodsMVP.csv"   # node universe (loaded by catalog.gd)
RECIPES_CSV = "recipes_all.csv"      # recipe set (loaded by catalog.gd)

# Reconcile the two divergent data sets: a handful of recipe goods are alternate
# spellings/casings of goods that already exist in the goods table. Collapse the
# unambiguous duplicates so they map onto the goods-table node instead of
# appearing twice.
ALIAS = {"CPU": "cpu", "tires": "tyres", "copper_piping": "copper_pipe"}

SELECTION_RULE = (
    "least efficient = most distinct inputs, then highest energy_req, then "
    "largest total input quantity; a recipe produces a good when it is the "
    "primary output (output_1), with a by-product fallback"
)

# Category -> accent colour, used for nodes and the arrows leaving them.
CAT_COLOR = {
    "metals": "#d98a4b", "chems": "#7bb0e0", "construction": "#9ac26a",
    "energy": "#e0635e", "water": "#4fc7d4", "agribio": "#7ed0a0",
    "consumer": "#c98ad9", "hightech": "#e0c44f", "component": "#b0b0c0",
    "power": "#f2c14e", "waste": "#8a8a8a", "": "#9aa0a8",
}
EXTERNAL_COLOR = "#5a6472"


def norm(good: str) -> str:
    """Normalise a good id to its canonical goods-table name."""
    return ALIAS.get(good, good)


# --------------------------------------------------------------------------- #
# Loading
# --------------------------------------------------------------------------- #
def load_goods(path):
    """Return {internal_name: {display, category, good_type}} in file order."""
    goods, order = {}, []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            name = (row.get("internal_name") or "").strip()
            if not row.get("ID") or not name:
                continue
            goods[name] = {
                "display": (row.get("display_name") or name).strip(),
                "category": (row.get("category") or "").strip(),
                "good_type": (row.get("good_type") or "").strip(),
            }
            order.append(name)
    return goods, order


def _io_pairs(row, good_key, qty_key, count):
    """Read input_i/qty_i (or output_i/output_qty_i) pairs from a recipe row."""
    pairs = []
    for i in range(1, count + 1):
        good = (row.get(f"{good_key}{i}") or "").strip()
        if not good:
            continue
        qty_raw = (row.get(f"{qty_key}{i}") or "").strip()
        try:
            qty = float(qty_raw) if qty_raw else None
        except ValueError:
            qty = None
        pairs.append({"good": norm(good), "qty": qty})
    return pairs


def load_recipes(path):
    """Return a list of recipe dicts with normalised input/output good ids."""
    recipes = []
    with open(path, newline="") as f:
        for row in csv.DictReader(f):
            rid = (row.get("recipe_id") or "").strip()
            if not rid:
                continue
            inputs = _io_pairs(row, "input_", "qty_", 6)
            outputs = _io_pairs(row, "output_", "output_qty_", 5)
            if not outputs:
                continue
            try:
                energy = float(row.get("energy_req") or 0)
            except ValueError:
                energy = 0.0
            recipes.append({
                "id": rid,
                "name": (row.get("display_name") or "").strip(),
                "building": (row.get("building_id") or "").strip(),
                "energy_req": energy,
                "inputs": inputs,
                "outputs": outputs,
                "primary_output": outputs[0]["good"],
                "requirements": (row.get("requirements") or "").strip(),
                "tag": (row.get("category") or "").strip(),
            })
    return recipes


# --------------------------------------------------------------------------- #
# Recipe selection
# --------------------------------------------------------------------------- #
def _total_input_qty(recipe):
    return sum(p["qty"] or 0 for p in recipe["inputs"])


def _least_efficient(recipes):
    """Pick the least efficient recipe (see SELECTION_RULE)."""
    return sorted(
        recipes,
        key=lambda r: (len(r["inputs"]), r["energy_req"], _total_input_qty(r)),
    )[-1]


def choose_recipes(goods, recipes):
    """Map each producible good to its defining (least-efficient) recipe.

    Returns (chosen, primary_index, anyout_index) where chosen also covers the
    external feedstock goods that the goods-table recipes pull in.
    """
    primary, anyout = defaultdict(list), defaultdict(list)
    for r in recipes:
        primary[r["primary_output"]].append(r)
        for out in r["outputs"]:
            anyout[out["good"]].append(r)

    def define(good):
        if good in primary:
            return _least_efficient(primary[good])
        if good in anyout:
            return _least_efficient(anyout[good])
        return None

    chosen = {}
    for good in goods:
        rec = define(good)
        if rec:
            chosen[good] = rec

    # External feedstocks: goods referenced by the chosen recipes that are not
    # in the goods table. Give them a defining recipe too so they are not dangling.
    external = set()
    for rec in list(chosen.values()):
        for p in rec["inputs"]:
            if p["good"] not in goods:
                external.add(p["good"])
    for good in external:
        rec = define(good)
        if rec:
            chosen[good] = rec

    return chosen, primary, anyout, external


# --------------------------------------------------------------------------- #
# Graph + hierarchy
# --------------------------------------------------------------------------- #
def build_graph(goods, chosen, external):
    """Return (nodes, edges, adj, radj). Edges go input_good -> output_good."""
    nodeset = set(goods) | external
    edges = set()
    for good, rec in chosen.items():
        if good not in nodeset:
            continue
        for p in rec["inputs"]:
            if p["good"] in nodeset:
                edges.add((p["good"], good))

    adj, radj = defaultdict(list), defaultdict(list)
    for a, b in edges:
        adj[a].append(b)
        radj[b].append(a)
    return sorted(nodeset), sorted(edges), adj, radj


def assign_tiers(nodes, radj):
    """Longest-path depth from a raw source (cycles broken at back-edges)."""
    depth = {}
    GREY, BLACK = 1, 2
    state = defaultdict(int)

    def visit(u):
        state[u] = GREY
        best = 0
        for p in radj[u]:
            if state[p] == GREY:        # back-edge inside a cycle: ignore
                continue
            if p not in depth:
                visit(p)
            best = max(best, depth[p] + 1)
        depth[u] = best
        state[u] = BLACK

    for n in nodes:
        if n not in depth:
            visit(n)
    return depth


def order_columns(depth, adj, radj, goods, passes=8):
    """Order nodes within each tier with a barycentre sweep to reduce crossings."""
    cols = defaultdict(list)
    for n, d in depth.items():
        cols[d].append(n)
    maxd = max(depth.values())
    order = {d: sorted(cols[d], key=lambda n: goods.get(n, {}).get("display", n))
             for d in cols}

    def positions():
        return {n: i for d in order for i, n in enumerate(order[d])}

    for _ in range(passes):
        pos = positions()
        for d in range(1, maxd + 1):
            order[d].sort(key=lambda n: (sum(pos[p] for p in radj[n]) / len(radj[n]))
                          if radj[n] else pos[n])
        pos = positions()
        for d in range(maxd - 1, -1, -1):
            order[d].sort(key=lambda n: (sum(pos[c] for c in adj[n]) / len(adj[n]))
                          if adj[n] else pos[n])
    return order, maxd


def tier_label(d, maxd):
    if d == 0:
        return "Raw / ores"
    if d == maxd:
        return "Finished"
    return f"Tier {d}"


# --------------------------------------------------------------------------- #
# JSON export
# --------------------------------------------------------------------------- #
def display_of(good, goods):
    if good in goods:
        return goods[good]["display"]
    return good.replace("_", " ").title()


def build_data(goods, chosen, primary, anyout, external, nodes, edges,
               adj, radj, depth, maxd):
    """Assemble the structured JSON document."""
    def recipe_ref(rec):
        if not rec:
            return None
        return {
            "id": rec["id"],
            "name": rec["name"],
            "building": rec["building"],
            "energy_req": rec["energy_req"],
            "inputs": rec["inputs"],
            "outputs": rec["outputs"],
            "requirements": rec["requirements"] or None,
            "tag": rec["tag"] or None,
        }

    node_records = []
    for n in nodes:
        meta = goods.get(n, {})
        in_csv = n in goods
        rec = chosen.get(n)
        producers = primary.get(n) or anyout.get(n) or []
        alternatives = sorted(
            {r["id"] for r in producers} - ({rec["id"]} if rec else set())
        )
        node_records.append({
            "id": n,
            "display_name": display_of(n, goods),
            "category": meta.get("category", "") or None,
            "good_type": meta.get("good_type", "") or None,
            "source": "goods_csv" if in_csv else "recipe_feedstock",
            "in_goods_csv": in_csv,
            "tier": depth[n],
            "tier_label": tier_label(depth[n], maxd),
            "is_raw": depth[n] == 0,
            "recipe": recipe_ref(rec),
            "recipe_options": len(producers),
            "alternative_recipe_ids": alternatives,
            "inputs": sorted(radj[n]),       # goods feeding into this good
            "feeds_into": sorted(adj[n]),     # goods this good feeds
        })
    node_records.sort(key=lambda r: (r["tier"], r["display_name"]))

    tiers = []
    for d in range(maxd + 1):
        members = sorted((n for n in nodes if depth[n] == d),
                         key=lambda n: display_of(n, goods))
        tiers.append({
            "tier": d,
            "label": tier_label(d, maxd),
            "goods": members,
        })

    in_csv_nodes = [n for n in nodes if n in goods]
    multi = sum(1 for g in in_csv_nodes if len(primary.get(g, [])) > 1)
    unmade = sorted(g for g in goods if g not in chosen)

    return {
        "meta": {
            "description": "Goods production-flow graph for Price of Everything.",
            "source_goods_csv": GOODS_CSV,
            "source_recipes_csv": RECIPES_CSV,
            "selection_rule": SELECTION_RULE,
            "aliases": ALIAS,
            "counts": {
                "goods_in_csv": len(goods),
                "external_feedstocks": len(external),
                "nodes_total": len(nodes),
                "edges": len(edges),
                "tiers": maxd + 1,
                "goods_with_multiple_recipes": multi,
                "goods_never_produced": unmade,
            },
        },
        "tiers": tiers,
        "nodes": node_records,
        "edges": [{"from": a, "to": b} for a, b in edges],
    }


# --------------------------------------------------------------------------- #
# HTML / SVG export
# --------------------------------------------------------------------------- #
# Geometry
COLW, ROWH = 300, 58
NODE_W, NODE_H = 176, 34
MARGIN_X, MARGIN_TOP, MARGIN_BOT = 40, 96, 40


def node_color(n, external):
    if n in external:
        return EXTERNAL_COLOR
    return CAT_COLOR.get("", "#9aa0a8")  # placeholder, overridden below


def build_svg(goods, external, nodes, edges, order, maxd, depth):
    def color_of(n):
        if n in external:
            return EXTERNAL_COLOR
        return CAT_COLOR.get(goods.get(n, {}).get("category", ""), "#9aa0a8")

    maxrows = max(len(order[d]) for d in order)
    xy = {}
    for d in order:
        offset = (maxrows - len(order[d])) / 2.0
        for i, n in enumerate(order[d]):
            xy[n] = (MARGIN_X + d * COLW, MARGIN_TOP + (offset + i) * ROWH)
    W = MARGIN_X + maxd * COLW + NODE_W + MARGIN_X + 20
    H = MARGIN_TOP + maxrows * ROWH + MARGIN_BOT

    out = [
        f'<svg id="flow" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
        f'xmlns="http://www.w3.org/2000/svg" '
        f'font-family="-apple-system,Segoe UI,Roboto,sans-serif">',
        f'<rect x="0" y="0" width="{W}" height="{H}" fill="#11151c"/>',
    ]

    # Tier bands + headers
    for d in range(maxd + 1):
        x = MARGIN_X + d * COLW
        if d % 2 == 1:
            out.append(f'<rect x="{x-30}" y="0" width="{COLW}" height="{H}" '
                       f'fill="#ffffff" opacity="0.018"/>')
        out.append(f'<text x="{x+NODE_W/2}" y="34" fill="#5f6b7a" font-size="13" '
                   f'font-weight="600" text-anchor="middle" letter-spacing="0.5">'
                   f'{tier_label(d, maxd).upper()}</text>')
    out.append(f'<text x="{MARGIN_X}" y="66" fill="#39424e" font-size="12">'
               f'flow: left = raw → right = advanced</text>')

    # Edges: colour body + white outline. Painted in tier order so a later
    # arrow's white casing cleanly breaks whichever arrow passes underneath.
    edge_list = sorted(edges, key=lambda e: (depth[e[0]], xy[e[0]][1], xy[e[1]][1]))
    out.append('<g id="edges" fill="none">')
    for a, b in edge_list:
        x1, y1 = xy[a]
        x2, y2 = xy[b]
        sx, sy = x1 + NODE_W, y1 + NODE_H / 2
        tx, ty = x2, y2 + NODE_H / 2
        dx = max(40, (tx - sx) * 0.45)
        d = f"M {sx:.1f},{sy:.1f} C {sx+dx:.1f},{sy:.1f} {tx-dx:.1f},{ty:.1f} {tx:.1f},{ty:.1f}"
        col = color_of(a)
        out.append(f'<path d="{d}" stroke="#ffffff" stroke-width="8.5" opacity="0.92"/>')
        out.append(f'<path d="{d}" stroke="{col}" stroke-width="4.2" opacity="1"/>')
        ah = 8.5
        head = (f"M {tx:.1f},{ty:.1f} L {tx-ah:.1f},{ty-ah*0.72:.1f} "
                f"L {tx-ah:.1f},{ty+ah*0.72:.1f} Z")
        out.append(f'<path d="{head}" fill="{col}" stroke="#ffffff" stroke-width="1.6"/>')
    out.append('</g>')

    # Nodes on top
    out.append('<g id="nodes">')
    for n in nodes:
        x, y = xy[n]
        col = color_of(n)
        is_ext = n in external
        fill = "#181c22" if is_ext else "#1b2230"
        op = ' opacity="0.72"' if is_ext else ""
        label = html.escape(display_of(n, goods))
        fs = 13 if len(label) <= 18 else (11 if len(label) <= 24 else 10)
        out.append(f"<g{op}>")
        out.append(f'<rect x="{x}" y="{y}" rx="7" ry="7" width="{NODE_W}" '
                   f'height="{NODE_H}" fill="{fill}" stroke="{col}" stroke-width="2"/>')
        out.append(f'<rect x="{x}" y="{y}" rx="7" ry="7" width="6" '
                   f'height="{NODE_H}" fill="{col}"/>')
        out.append(f'<text x="{x+14}" y="{y+NODE_H/2+4}" fill="#e6ebf2" '
                   f'font-size="{fs}" font-weight="500">{label}</text>')
        out.append("</g>")
    out.append("</g></svg>")
    return "".join(out), W, H


def build_html(data, svg):
    c = data["meta"]["counts"]
    legend = "".join(
        f'<span class="lg"><i style="background:{col}"></i>{name.title()}</span>'
        for name, col in CAT_COLOR.items() if name
    )
    rows = []
    for node in sorted(data["nodes"], key=lambda n: n["id"]):
        if not node["in_goods_csv"]:
            continue
        rec = node["recipe"]
        if rec:
            reccell = f'{rec["id"]}  {rec["name"]}'
            nin, energy = len(rec["inputs"]), rec["energy_req"]
        else:
            reccell, nin, energy = "(none — raw/unmade)", "", ""
        rows.append(
            f'<tr><td class="mono">{html.escape(node["id"])}</td>'
            f'<td>{html.escape(node["display_name"])}</td>'
            f'<td>{html.escape(reccell)}</td>'
            f'<td class="num">{nin}</td><td class="num">{energy}</td></tr>'
        )
    table = "".join(rows)

    return f"""<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<title>Price of Everything — Goods Flow Chart</title>
<style>
 :root{{--bg:#0c0f14;--panel:#11151c;--ink:#e6ebf2;--dim:#7a8696;--line:#222a35;}}
 *{{box-sizing:border-box}}
 body{{margin:0;background:var(--bg);color:var(--ink);font:14px/1.5 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}}
 header{{padding:18px 26px 12px;border-bottom:1px solid var(--line);position:sticky;left:0}}
 h1{{margin:0 0 4px;font-size:20px;letter-spacing:.2px}}
 .sub{{color:var(--dim);font-size:13px;max-width:1100px}}
 .meta{{margin-top:10px;display:flex;gap:18px;flex-wrap:wrap;color:var(--dim);font-size:12.5px}}
 .meta b{{color:var(--ink)}}
 .legend{{margin:12px 0 2px;display:flex;gap:14px;flex-wrap:wrap;align-items:center}}
 .lg{{display:inline-flex;align-items:center;gap:6px;color:var(--dim);font-size:12px}}
 .lg i{{width:12px;height:12px;border-radius:3px;display:inline-block}}
 .lg.dash i{{background:transparent;border:2px dashed #5a6472}}
 .scroll{{overflow:auto;padding:8px 0 22px}}
 svg{{display:block}}
 details{{margin:0 26px 40px;border:1px solid var(--line);border-radius:8px;background:var(--panel);max-width:980px}}
 summary{{padding:12px 16px;cursor:pointer;font-weight:600;color:var(--ink)}}
 table{{border-collapse:collapse;width:100%;font-size:12.5px}}
 th,td{{text-align:left;padding:6px 12px;border-top:1px solid var(--line)}}
 th{{color:var(--dim);font-weight:600;position:sticky;top:0;background:var(--panel)}}
 td.num,th.num{{text-align:right;font-variant-numeric:tabular-nums}}
 .mono{{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:#9fb4cf}}
 .hint{{padding:0 16px 14px;color:var(--dim);font-size:12px}}
</style></head>
<body>
<header>
 <h1>Goods Flow Chart — <span style="color:#7bb0e0">Price of Everything</span></h1>
 <div class="sub">Each good points to the goods it is consumed by. Inputs come from the in-game recipe set
 (<span class="mono">{RECIPES_CSV}</span>); when a good has several recipes, the <b>least-efficient</b> one
 (most distinct inputs, then highest power) defines its inputs. Raw materials &amp; ores sit on the left; each
 column moves one production step further right toward finished goods. Generated by
 <span class="mono">scripts/build_goods_flow.py</span> — see <span class="mono">{os.path.relpath(os.path.join(DEFAULT_DATA_DIR,'goods_flow.json'), PROJECT_DIR)}</span> for the data.</div>
 <div class="meta">
  <span><b>{c['goods_in_csv']}</b> goods from goods.csv</span>
  <span><b>{c['external_feedstocks']}</b> external feedstocks (dashed — referenced by recipes but not in goods.csv)</span>
  <span><b>{c['edges']}</b> flow links</span>
  <span><b>{c['goods_with_multiple_recipes']}</b> goods had multiple recipes (least-efficient chosen)</span>
  <span><b>{c['tiers']}</b> tiers</span>
 </div>
 <div class="legend">{legend}<span class="lg dash"><i></i>External feedstock</span></div>
</header>
<div class="scroll">{svg}</div>
<details>
 <summary>Chosen least-efficient recipe per good ({c['goods_in_csv']} goods)</summary>
 <div class="hint">For goods with multiple recipes, the row shows the one selected as least efficient: most distinct inputs first, ties broken by highest power (energy_req), then largest total input quantity.</div>
 <table><thead><tr><th>internal_name</th><th>display</th><th>defining recipe</th><th class="num"># inputs</th><th class="num">power</th></tr></thead>
 <tbody>{table}</tbody></table>
</details>
</body></html>"""


# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--data", default=DEFAULT_DATA_DIR,
                    help="directory containing the goods/recipes CSVs")
    ap.add_argument("--out", default=DEFAULT_OUT_DIR,
                    help="directory for goods_flow_chart.html")
    ap.add_argument("--json", default=os.path.join(DEFAULT_DATA_DIR, "goods_flow.json"),
                    help="path for the goods_flow.json data file")
    args = ap.parse_args()

    goods, _ = load_goods(os.path.join(args.data, GOODS_CSV))
    recipes = load_recipes(os.path.join(args.data, RECIPES_CSV))

    chosen, primary, anyout, external = choose_recipes(goods, recipes)
    nodes, edges, adj, radj = build_graph(goods, chosen, external)
    depth = assign_tiers(nodes, radj)
    order, maxd = order_columns(depth, adj, radj, goods)

    data = build_data(goods, chosen, primary, anyout, external,
                      nodes, edges, adj, radj, depth, maxd)
    svg, W, H = build_svg(goods, external, nodes, edges, order, maxd, depth)
    doc = build_html(data, svg)

    os.makedirs(os.path.dirname(args.json), exist_ok=True)
    os.makedirs(args.out, exist_ok=True)
    with open(args.json, "w") as f:
        json.dump(data, f, indent=2, sort_keys=False)
        f.write("\n")
    html_path = os.path.join(args.out, "goods_flow_chart.html")
    with open(html_path, "w") as f:
        f.write(doc)

    c = data["meta"]["counts"]
    print(f"goods_flow.json  -> {args.json}")
    print(f"goods_flow_chart.html -> {html_path}  ({W}x{H})")
    print(f"  {c['goods_in_csv']} goods + {c['external_feedstocks']} external feedstocks, "
          f"{c['edges']} edges, {c['tiers']} tiers, "
          f"{c['goods_with_multiple_recipes']} multi-recipe goods")


if __name__ == "__main__":
    main()
