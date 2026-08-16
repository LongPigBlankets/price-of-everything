extends RefCounted
## Marquee selection and deletion.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## Drag a box, and everything it touches is selected; delete removes the lot behind a
## confirmation. Written against a generic list of `{kind, settlement, index}` records rather
## than against roads specifically, because the same box will have to pick up decorative
## masses, parks and farm/forest polygons in P2 — only `roads` exists today, and the other
## kinds join by adding a line to [constant SELECTABLE].
##
## THE TILE LIST IS REBUILT AFTER EVERY DELETION, and that is not bookkeeping. A settlement's
## `tiles` array is the suppression key: while a tile is in it, the procedural roads, fabric
## and forest discs stand down for that tile. Delete the last authored stroke on a tile and
## leave the tile listed, and the map has a hole — nothing authored drawn, and the procedural
## content that would have covered it still suppressed.

const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")

## Content kinds a marquee can pick up, and where they live in a settlement. Extending this
## is how P2's masses and parks become selectable.
const SELECTABLE := ["roads"]

## A drag shorter than this on screen is a click, not a marquee — without it, every stray
## click would clear the selection by "selecting" a zero-area box.
const MIN_DRAG := 4.0


## Everything of a selectable kind whose geometry meets `rect` (world units).
static func in_rect(document: Dictionary, rect: Rect2) -> Array:
	var out: Array = []
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return out
	var settlements: Dictionary = settlements_value
	var keys := settlements.keys()
	keys.sort()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		for kind in SELECTABLE:
			var items: Array = (settlement_value as Dictionary).get(kind, []) as Array
			for index in items.size():
				var item_value: Variant = items[index]
				if typeof(item_value) != TYPE_DICTIONARY:
					continue
				if _meets_rect(item_value as Dictionary, rect):
					out.append({"kind": kind, "settlement": str(key), "index": index,
						"id": str((item_value as Dictionary).get("id", ""))})
	return out


## Does a stroke's centreline touch the rect? Endpoint containment alone is not enough: a
## straight road is stored as two corners, so a run crossing a small box has NO point inside
## it and would be missed entirely. Every segment is tested against the box's edges too.
static func _meets_rect(item: Dictionary, rect: Rect2) -> bool:
	var points := AuthoredRoadGeometry.sample(item)
	if points.is_empty():
		return false
	for point in points:
		if rect.has_point(point):
			return true
	var corners := [
		rect.position,
		rect.position + Vector2(rect.size.x, 0.0),
		rect.position + rect.size,
		rect.position + Vector2(0.0, rect.size.y),
	]
	for i in range(1, points.size()):
		for c in 4:
			var from: Vector2 = corners[c]
			var to: Vector2 = corners[(c + 1) % 4]
			if Geometry2D.segment_intersects_segment(points[i - 1], points[i], from, to) != null:
				return true
	return false


## Remove the selected records. Deletes from the highest index down so earlier removals
## cannot shift the indices of later ones — the classic way this kind of code corrupts a
## list. Returns how many were removed.
static func delete(document: Dictionary, selection: Array) -> int:
	if selection.is_empty():
		return 0
	var by_list: Dictionary = {}
	for entry_value in selection:
		var entry: Dictionary = entry_value
		var list_key := "%s|%s" % [entry["settlement"], entry["kind"]]
		if not by_list.has(list_key):
			by_list[list_key] = []
		(by_list[list_key] as Array).append(int(entry["index"]))
	var removed := 0
	var settlements: Dictionary = document.get("settlements", {})
	for list_key in by_list:
		var parts := str(list_key).split("|")
		var settlement_value: Variant = settlements.get(parts[0], {})
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		var items: Array = settlement.get(parts[1], []) as Array
		var indices: Array = by_list[list_key]
		indices.sort()
		indices.reverse()
		for index in indices:
			if index >= 0 and index < items.size():
				items.remove_at(index)
				removed += 1
		settlement[parts[1]] = items
	_rebuild_coverage(settlements)
	return removed


## Recompute every settlement's tile list from what it still contains, and drop settlements
## that no longer contain anything. See the header for why a stale tile list is worse than a
## missing one.
static func _rebuild_coverage(settlements: Dictionary) -> void:
	for key in settlements.keys():
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		var tiles: Dictionary = {}
		var total := 0
		for kind in SELECTABLE:
			var items: Array = settlement.get(kind, []) as Array
			total += items.size()
			for item_value in items:
				if typeof(item_value) != TYPE_DICTIONARY:
					continue
				for tile_id in ((item_value as Dictionary).get("tiles", []) as Array):
					tiles[str(tile_id)] = true
		if total == 0:
			# An empty settlement would keep suppressing procedural content on tiles it no
			# longer draws anything on.
			settlements.erase(key)
			continue
		var list := tiles.keys()
		list.sort()
		settlement["tiles"] = list
