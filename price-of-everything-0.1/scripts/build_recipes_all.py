#!/usr/bin/env python3
"""Build data/recipes_all.csv (the canonical recipe pool) from the maximalist
master list, merged with the current game's hand-balanced recipes.

Transform:
  * Strip `co2` from every input/output slot; DROP any recipe that uses co2 as
    an input (co2 is not a tracked good).
  * Fix obvious blocker name mismatches (copper_wire -> copper_wiring).
  * Drop incomplete master rows (no output).
  * Keep the 12 current production recipes verbatim (preserved quantities /
    energy) so existing chains never break; tag them with a recipe_type
    (`category`).
  * Drop master rows whose normalized display_name duplicates a current recipe.
  * Renumber: current -> r_001..r_012, kept master rows -> r_013+.

The runtime promotion gate (Catalog) decides which of these are *active* (all
inputs + outputs are existing goods and the building resolves). Run:
    python scripts/build_recipes_all.py
"""
import csv
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SRC = os.path.join(ROOT, "data", "recipes_master_source.csv")
OUT = os.path.join(ROOT, "data", "recipes_all.csv")

HEADER = [
    "recipe_id", "display_name", "building_id",
    "input_1", "qty_1", "input_2", "qty_2", "input_3", "qty_3",
    "input_4", "qty_4", "input_5", "qty_5", "input_6", "qty_6",
    "energy_req",
    "output_1", "output_qty_1", "output_2", "output_qty_2", "output_3", "output_qty_3",
    "output_4", "output_qty_4", "output_5", "output_qty_5",
    "requirements", "pollution_output", "pollution_sensitivity", "category", "terminal_turns",
]

NAME_FIX = {"copper_wire": "copper_wiring", "plasticss": "plastics"}

# Current hand-balanced recipes: (name, building, inputs, energy, outputs, requirements, category)
CURRENT = [
    ("Coal Mining", "mine", [], 4, [("coal", 20)], "deposit:coal", "extraction"),
    ("Iron Mining", "mine", [], 4, [("iron_ore", 20)], "deposit:iron_ore", "extraction"),
    ("Steelmaking", "furnace", [("iron_ingots", 20), ("coal", 10)], 14, [("steel", 30)], "", "smelting"),
    ("Power Production", "coal_power", [("coal", 20), ("pure_water", 6)], 0, [("power", 100)], "", "power"),
    ("Pig Iron Smelting", "furnace", [("iron_ore", 30), ("coal", 10)], 14, [("iron_ingots", 30)], "", "smelting"),
    ("Copper Mining", "mine", [], 4, [("copper_ore", 20)], "deposit:copper_ore", "extraction"),
    ("Copper Blistering", "furnace", [("copper_ore", 30)], 10, [("copper_ingots", 30)], "", "smelting"),
    ("Copper Wire Drawing", "industrial_factory", [("copper_ingots", 20)], 13, [("copper_wiring", 20)], "", "manufacturing"),
    ("Motor Manufacture", "industrial_factory", [("steel", 15), ("copper_wiring", 12)], 6, [("motor", 15)], "", "manufacturing"),
    ("Salt Mining", "mine", [], 4, [("basic_salt", 40)], "deposit:basic_salt", "extraction"),
    ("Water Pumping", "water_pump", [], 3, [("pure_water", 40)], "", "water"),
    ("Chlor-Alkali Process", "chem_plant", [("basic_salt", 20), ("pure_water", 20)], 10,
        [("chlorine", 24), ("sodium_hydroxide", 18), ("hydrogen", 6)], "", "electrochemistry"),
]


def norm(name):
    return re.sub(r"[^a-z0-9]", "", name.lower())


def fix(good):
    return NAME_FIX.get(good, good)


def make_row(rid, name, building, inputs, energy, outputs, req, cat,
             poll_out="", poll_sens="", terminal=""):
    row = {h: "" for h in HEADER}
    row["recipe_id"] = rid
    row["display_name"] = name
    row["building_id"] = building
    for i, (g, q) in enumerate(inputs[:6], start=1):
        row["input_%d" % i] = g
        row["qty_%d" % i] = q
    row["energy_req"] = energy
    for i, (g, q) in enumerate(outputs[:5], start=1):
        row["output_%d" % i] = g
        row["output_qty_%d" % i] = q
    row["requirements"] = req
    row["pollution_output"] = poll_out
    row["pollution_sensitivity"] = poll_sens
    row["category"] = cat
    row["terminal_turns"] = terminal
    return row


def parse_master(path):
    out = []
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for raw in reader:
            if not (raw.get("recipe_id") or "").strip():
                continue
            inputs, drop = [], False
            for i in range(1, 7):
                g = (raw.get("input_%d" % i) or "").strip()
                q = (raw.get("qty_%d" % i) or "").strip()
                if not g:
                    continue
                if g == "co2":          # recipe relies on co2 -> drop entirely
                    drop = True
                    break
                inputs.append((fix(g), q))
            if drop:
                continue
            outputs = []
            for i in range(1, 6):
                g = (raw.get("output_%d" % i) or "").strip()
                q = (raw.get("output_qty_%d" % i) or "").strip()
                if not g or g == "co2":  # strip co2 byproducts
                    continue
                outputs.append((fix(g), q))
            if not outputs:              # incomplete master row
                continue
            out.append(make_row(
                raw["recipe_id"].strip(),
                (raw.get("display_name") or "").strip(),
                (raw.get("building_id") or "").strip(),
                inputs,
                (raw.get("energy_req") or "0").strip() or "0",
                outputs,
                (raw.get("requirements") or "").strip(),
                (raw.get("category") or "").strip(),
                (raw.get("pollution_output") or "").strip(),
                (raw.get("pollution_sensitivity") or "").strip(),
                (raw.get("terminal_turns") or "").strip(),
            ))
    return out


def main():
    rows = []
    current_names = set()
    for i, (name, bld, ins, e, outs, req, cat) in enumerate(CURRENT, start=1):
        rows.append(make_row("r_%03d" % i, name, bld, ins, e, outs, req, cat))
        current_names.add(norm(name))

    next_id = len(CURRENT) + 1
    kept = dropped = 0
    for row in parse_master(SRC):
        if norm(row["display_name"]) in current_names:
            dropped += 1
            continue
        row["recipe_id"] = "r_%03d" % next_id
        next_id += 1
        rows.append(row)
        kept += 1

    with open(OUT, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=HEADER)
        w.writeheader()
        w.writerows(rows)

    print("current=%d  master_kept=%d  master_dropped(name-dup)=%d  total=%d"
          % (len(CURRENT), kept, dropped, len(rows)))
    print("wrote", OUT)


if __name__ == "__main__":
    main()
