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

`procedural.json` — the whole live map imported in one pass, ~2 MB. Regenerate with:

```bash
godot --path . res://tools/map_editor/import_live_map.tscn --quit-after 6000 -- --name=procedural
```

Add `--tiles=tile_10_16,tile_23_8` to import a subset instead. Shapes over five corners are
simplified on import (owner ruling, 2026-08-16).

`_*.json` — scratch documents written by `authored_unlock_check` and `authored_slot_check`.
Both point `active.txt` at their own fixture and restore it afterwards. If you ever find
`active.txt` naming a `_`-prefixed document, a check died mid-run; put the real name back.
