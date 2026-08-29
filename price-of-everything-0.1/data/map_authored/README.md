# Authored map documents

Hand-drawn map data for the map editor (`tools/map_editor/map_editor.tscn`, editor-only) and
for the shipped renderer (`scripts/authored_map.gd`). **This is source.** A document here is
someone's drawing; there is no other copy and no way to regenerate one that was hand-made.

`active.txt` names the document the game loads, without the `.json`. One line, nothing else.
It is a *choice*, not part of any document, which is why it lives outside all of them.

## What is here

| File | What it is |
|---|---|
| `stoneshore-alpha.json` | Hand-drawn. The first authored settlement. |
| `stoneshore-procedural.json` | The working document: the five region imports below, merged, then edited by hand. **Currently active.** |
| `stoneshore-{core,north,south,inland,frontier}.json` | The five region imports, before merging. Kept because the merge is not reversible and the exact tile lists that produced them are not recorded anywhere else. |

## What is NOT here (gitignored)

`procedural.json` — the whole live map imported in one pass, ~2 MB: building masses,
roads, ports, parks, plazas and building slots. It is the SOURCE the editor's
`enable procedural <region>` cheats cut from (see below). Regenerate after any change to
the procedural generators:

```bash
godot --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 -- --name=procedural
```

Add `--tiles=tile_10_16,tile_23_8` to import a subset instead. Shapes over TEN corners are
simplified on import (owner ruling 2026-08-29, superseding the five-corner ruling: imports
stay as faithful to the generated shape as an editable outline allows). The importer reads
the world BLIND to the active document — without that, an active `stoneshore-procedural`
stands the whole procedural fabric down and the import comes back empty. Trees are not
imported: the map's woods are already authored (`forests_imported`), and no other
procedural trees exist.

`_*.json` — scratch documents written by `authored_unlock_check` and `authored_slot_check`.
Both point `active.txt` at their own fixture and restore it afterwards. If you ever find
`active.txt` naming a `_`-prefixed document, a check died mid-run; put the real name back.

## Showing the rest of the map: `enable procedural <region>`

The land the authored look has not touched yet is split FOUR WAYS by which city each tile
is closest to: **north** (Port Lightning, `tile_14_2`), **arin** (Arin City,
`tile_11_17`), **vandel** (Vandel Port, `tile_22_16`) and **capital** (Capital Port,
`tile_25_9`). In the editor, open the debug terminal (the backtick ` key — cheats must be
unlocked with `debug CandC`) and:

```
enable procedural north        # or arin | vandel | capital | all
disable procedural north
```

`enable` cuts that region's share of `procedural.json` into the working document as a
settlement named `procedural-<region>`: decorative buildings as up-to-ten-corner polygons,
roads as strokes, parks and plazas as outlines, gameplay buildings as slots. Everything is
then editable exactly like hand-drawn content (the map's trees are already there — every
wood is an authored `forests` area). `disable` removes that settlement again. Both are
ordinary edits: undoable, and nothing touches disk until you save.

A road that crosses into tiles a real settlement already authors is NOT imported — the
Stoneshore imports already took every edge touching their tiles, and a deletion made there
stays deleted. Records land in exactly one region (by the tile under their centroid; roads
by their centroid's nearest city), so enabling two neighbouring regions never doubles
anything.

## Authoring the next settlement: Arin

The Stoneshore recipe, generalised. Arin's tiles (from `tile_properties.csv`):
the city proper is `tile_9_16` Highgate, `tile_9_18` Millgate, `tile_10_16` Old Quarter,
`tile_10_17` Docks, `tile_10_18` The Wharf, `tile_11_16` Industrial Zone, `tile_11_17` Arin
City, `tile_12_16` Foundry, `tile_12_17` Market Row; the hold is `tile_8_14` / `tile_8_15`
on the hills. (`tile_14_5` Arinnal Commons is a different place.)

**1. Import region by region, not the whole city at once.** A region of 10-25 tiles keeps
each editing session small enough to finish. Include the RING of neighbouring tiles around
each group, so roads that cross the boundary import whole instead of being cut at the edge:

```bash
godot --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 -- \
    --name=arin-city --tiles=tile_9_16,tile_10_16,tile_10_17,tile_11_16,tile_11_17,tile_12_16,tile_12_17

godot --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 -- \
    --name=arin-wharf --tiles=tile_9_18,tile_10_18,tile_9_17,tile_11_18

godot --path . res://tools/map_editor/import_live_map.tscn --quit-after 30000 -- \
    --name=arin-hold --tiles=tile_8_14,tile_8_15,tile_7_14,tile_7_15,tile_8_16,tile_9_15
```

Shapes over five corners are simplified on import (owner ruling); the run prints how many.
Imported roads should be AUDITED for water immediately — `authored_render_check.tscn` lists
strokes over sea or lake, and Stoneshore's import brought 8 of them that still need redrawing.

**2. Edit each region in the editor** (`debug CandC` → Map editor → Load…). Draw the zones
first — default industrial (blue), reserve (red), extraction (black) over the deposits shown
by *Visibility → Extraction resources* — then fabric. Save under the region's own name.

**3. Merge into one document** once the regions are done:

```bash
python3 - <<'EOF'
import json
out = {"version": 1, "settlements": {}}
for name in ["arin-city", "arin-wharf", "arin-hold"]:
    d = json.load(open(f"data/map_authored/{name}.json"))
    for key, s in d["settlements"].items():
        out["settlements"][f"{name}:{key}"] = s
json.dump(out, open("data/map_authored/arin-procedural.json", "w"), indent=2)
EOF
```

Settlement keys are namespaced by region so ids cannot collide. Validate before pointing the
game at it — `validate_documents.tscn` runs the loader's own validator over everything on
disk — and only then write the new name into `active.txt` (or Save As from the editor, which
updates the pointer itself). Keep the per-region files: the merge is not reversible.

**4. One map, many settlements.** To play Stoneshore AND Arin together, merge the Arin
regions into the EXISTING active document the same way — the settlements dictionary holds any
number of entries, and each tile belongs to whichever settlement lists it.
