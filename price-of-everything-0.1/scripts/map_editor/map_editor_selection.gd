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
const AuthoredRoadStyle := preload("res://scripts/authored_road_style.gd")
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")

## Content kinds a marquee can pick up, and where they live in a settlement. Extending this
## is how P2's masses and parks become selectable.
const SELECTABLE := ["roads", "decor", "specials", "farms", "forests", "parks"]

## Kinds whose geometry is an explicit outline, and which can therefore have their corners
## dragged. A road is a centreline and a mass is generated from a form, so neither qualifies.
const OUTLINE_KINDS := ["specials", "farms", "forests", "parks"]

## A drag shorter than this on screen is a click, not a marquee — without it, every stray
## click would clear the selection by "selecting" a zero-area box.
const MIN_DRAG := 4.0


## The topmost record under a point, as `{kind, settlement, index, id, record}` — or {}.
##
## Searched in REVERSE draw order, so the thing drawn last (and therefore on top) is the
## thing you grab. Anything else means clicking a mass that sits over a park picks the park.
static func at_point(document: Dictionary, world: Vector2) -> Dictionary:
	var settlements_value: Variant = document.get("settlements", {})
	if typeof(settlements_value) != TYPE_DICTIONARY:
		return {}
	var settlements: Dictionary = settlements_value
	var keys := settlements.keys()
	keys.sort()
	keys.reverse()
	for key in keys:
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		# Reverse of the painter's order: specials and masses sit above ground, ground above
		# roads only in the sense that a road is a line you must click precisely.
		for kind in ["specials", "decor", "parks", "forests", "farms", "roads"]:
			var items: Array = settlement.get(kind, []) as Array
			for index in range(items.size() - 1, -1, -1):
				var item_value: Variant = items[index]
				if typeof(item_value) != TYPE_DICTIONARY:
					continue
				if _contains(item_value as Dictionary, world):
					return {"kind": kind, "settlement": str(key), "index": index,
						"id": str((item_value as Dictionary).get("id", "")),
						"record": item_value}
	return {}


## Is `world` on this record? Outlines by containment, masses by their box, roads by distance
## to the centreline — a road is a line, and demanding a click inside its carriageway would
## make a minor road nearly ungrabbable.
static func _contains(item: Dictionary, world: Vector2) -> bool:
	if item.has("outline"):
		var outline := _outline_of(item)
		return outline.size() >= 3 and Geometry2D.is_point_in_polygon(world, outline)
	if item.has("form"):
		var parcel: PackedVector2Array = AuthoredFabricPainter.mass_parcel(item)
		return parcel.size() >= 3 and Geometry2D.is_point_in_polygon(world, parcel)
	var points := AuthoredRoadGeometry.sample(item)
	if points.size() < 2:
		return false
	var tolerance := maxf(AuthoredRoadStyle.bed_width(str(item.get("class", "mid"))), 12.0)
	for i in range(1, points.size()):
		if world.distance_to(Geometry2D.get_closest_point_to_segment(
				world, points[i - 1], points[i])) <= tolerance:
			return true
	return false


## Move a record by `delta`. Every kind stores its position differently, so this is the one
## place that knows how — a caller should never have to ask what shape of thing it is holding.
static func translate(item: Dictionary, delta: Vector2) -> void:
	if item.has("outline"):
		var moved: Array = []
		for entry in (item.get("outline", []) as Array):
			var values: Array = entry as Array
			if values != null and values.size() >= 2:
				moved.append([float(values[0]) + delta.x, float(values[1]) + delta.y])
		item["outline"] = moved
		return
	if item.has("form"):
		var pos: Array = item.get("pos", [0, 0]) as Array
		if pos.size() >= 2:
			item["pos"] = [float(pos[0]) + delta.x, float(pos[1]) + delta.y]
		return
	# A road: every control point AND its handles' anchors move together. Handles are stored
	# relative to their point, so they need no adjustment.
	var points: Array = []
	for entry in (item.get("points", []) as Array):
		var values: Array = (entry as Array).duplicate()
		if values.size() >= 2:
			values[0] = float(values[0]) + delta.x
			values[1] = float(values[1]) + delta.y
		points.append(values)
	item["points"] = points
	# Bridges are absolute positions on the stroke, so they travel with it.
	var bridges: Array = []
	for entry in (item.get("bridges", []) as Array):
		var values: Array = (entry as Array).duplicate()
		if values.size() >= 4:
			values[0] = float(values[0]) + delta.x
			values[1] = float(values[1]) + delta.y
		bridges.append(values)
	if not bridges.is_empty():
		item["bridges"] = bridges


static func _outline_of(item: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for entry in (item.get("outline", []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


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
## The single outline-shaped record in a selection, or {} when the answer is ambiguous.
static func single_outline(document: Dictionary, selection: Array) -> Dictionary:
	var found := {}
	for entry_value in selection:
		var entry: Dictionary = entry_value
		if not OUTLINE_KINDS.has(str(entry.get("kind", ""))):
			continue
		if not found.is_empty():
			return {}   # more than one: no unambiguous subject to reshape
		var settlements: Dictionary = document.get("settlements", {})
		var settlement: Dictionary = settlements.get(str(entry["settlement"]), {})
		var items: Array = settlement.get(str(entry["kind"]), []) as Array
		var index := int(entry["index"])
		if index >= 0 and index < items.size():
			found = items[index]
	return found


static func _meets_rect(item: Dictionary, rect: Rect2) -> bool:
	# An outline-shaped thing is tested by its own polygon; a road by its centreline.
	if item.has("outline"):
		var outline := PackedVector2Array()
		for entry in (item.get("outline", []) as Array):
			var values: Array = entry as Array
			if values != null and values.size() >= 2:
				outline.append(Vector2(float(values[0]), float(values[1])))
		for point in outline:
			if rect.has_point(point):
				return true
		return outline.size() >= 3 and Geometry2D.is_point_in_polygon(rect.get_center(), outline)
	if item.has("form"):
		# A stamped mass: its box is enough, and cheaper than rebuilding the form.
		var pos: Array = item.get("pos", [0, 0]) as Array
		if pos.size() >= 2:
			return rect.has_point(Vector2(float(pos[0]), float(pos[1])))
		return false
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
