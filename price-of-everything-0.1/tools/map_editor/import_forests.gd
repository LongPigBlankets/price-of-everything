extends Node2D
## Convert the map's PROCEDURAL forests into authored ones (owner, 2026-08-28).
##
## The map draws woods two ways. `ForestVisuals` renders the b_015/b_016 forest buildings as
## lobed canopy discs; the authored document renders a `forests` area as individual trees from
## the shared `TreeShapes` vocabulary. On an authored tile both were drawing — the procedural
## canopy AND whatever the document said — which is why the varied trees were nowhere to be
## seen: they were under a disc.
##
## This writes the discs out as authored areas so the trees take over. The outline is the
## CONVEX HULL of a forest's own circle rims, so an imported wood keeps the footprint the
## procedural one had rather than becoming a box; `density` is set high, which is what turns
## a scatter into a dense wood (`AuthoredFabricPainter.woodland_points` divides its spacing
## by it).
##
## NO TILE IS ADDED TO A SETTLEMENT. A forest area draws wherever its outline is; a
## settlement's `tiles` list is a different thing entirely -- the SUPPRESSION key, which makes
## a tile's procedural fabric, accommodation and road geometry all stand down
## (`AuthoredMap.covers`). Most of the map's woods sit on tiles the document does not cover,
## and authoring a hundred tiles to import their trees would strip the roads and fabric off
## every one of them. So the areas go in and the tile lists are left exactly as they were.
##
## Instead the document gets `forests_imported`, and ForestVisuals stands down when it sees
## it: the discs have become areas, so drawing both would be drawing every wood twice.
##
##   <godot> --path . res://tools/map_editor/import_forests.tscn --quit-after 900000
##   <godot> --headless --path . res://tools/bake_authored_map.tscn   # re-bake after

const ShotHarness := preload("res://tools/shot_harness.gd")
const AuthoredMapData := preload("res://scripts/authored_map.gd")

## Points sampled round each canopy circle before hulling. Enough that a lobe reads as round.
const RIM_SAMPLES := 10
## Trees are laid at TREE_SPACING / density, and density is clamped to 2.0 — so this is as
## dense as an authored wood goes, which is what "dense" was asked for.
const DENSITY := 2.0
## An authored area may carry at most eight corners — see AuthoredMap._validate_area.
const MAX_CORNERS := 8


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 600.0)
	var wm: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(wm)
	for _i in 220:
		await get_tree().process_frame

	var forests: Node = wm.find_child("ForestVisuals", true, false)
	if forests == null:
		push_error("import_forests: no ForestVisuals")
		get_tree().quit(1)
		return
	var doc: Dictionary = AuthoredMapData.data().duplicate(true)
	var settlements: Dictionary = doc.get("settlements", {})
	if settlements.is_empty():
		push_error("import_forests: the active document has no settlements")
		get_tree().quit(1)
		return

	# tile_id -> settlement key, from the document itself rather than AuthoredMap.tile_index(),
	# which keeps whichever settlement it saw first. A wood belongs to the settlement that
	# actually lists its tile.
	var owner_of: Dictionary = {}
	for key in settlements:
		for tile_value in (settlements[key] as Dictionary).get("tiles", []):
			owner_of[str(tile_value)] = str(key)
	# A wood on a tile no settlement lists still has to live somewhere: it goes to the first
	# settlement, which changes where the record is STORED and nothing about where it draws.
	var fallback := str(settlements.keys()[0])

	var registry: Dictionary = forests.get("_forests")
	var added := 0
	var skipped := 0
	var per_settlement: Dictionary = {}
	for instance_id in registry:
		var entry: Dictionary = registry[instance_id]
		var tile_id := str(entry.get("tile_id", ""))
		var data: Dictionary = forests.call("_forest_draw_data", str(instance_id), tile_id,
			entry.get("coord", Vector2i.ZERO))
		var outline := _hull_of(data.get("circles", []))
		if outline.size() < 3:
			skipped += 1
			continue
		var key: String = str(owner_of.get(tile_id, fallback))
		var settlement: Dictionary = settlements[key]
		if not settlement.has("forests"):
			settlement["forests"] = []
		var points: Array = []
		for point in outline:
			points.append([snappedf(point.x, 0.01), snappedf(point.y, 0.01)])
		(settlement["forests"] as Array).append({
			"id": "fo:%s:imported:%s" % [key, str(instance_id)],
			"outline": points,
			"density": DENSITY,
		})
		per_settlement[key] = int(per_settlement.get(key, 0)) + 1
		added += 1

	doc["forests_imported"] = true
	print("[FORESTS] converted %d, skipped %d (no drawable outline)" % [added, skipped])
	for key in per_settlement:
		print("[FORESTS]   %s: +%d" % [key, int(per_settlement[key])])
	var problems := AuthoredMapData.validate(doc)
	if not problems.is_empty():
		for line in problems:
			push_error("import_forests: %s" % line)
		get_tree().quit(1)
		return
	var path := AuthoredMapData.active_path()
	var written := AuthoredMapData.save_to(doc, path)
	print("[FORESTS] wrote %s" % written)
	print("[FORESTS] done — now re-bake: tools/bake_authored_map.tscn")
	get_tree().quit(0)


## The convex hull of every canopy circle's rim. A wood's discs overlap, so hulling their rims
## gives the silhouette the player already sees; hulling their CENTRES would pull the outline
## inside the canopy and plant the outermost trees off the edge of the wood.
func _hull_of(circles: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for circle_value in circles:
		var circle: Dictionary = circle_value
		var centre: Vector2 = circle.get("pos", Vector2.ZERO)
		var r := float(circle.get("r", 0.0))
		if r <= 0.0:
			continue
		var aspect := float(circle.get("aspect", 1.0))
		var rot := float(circle.get("rot", 0.0))
		for i in RIM_SAMPLES:
			var a := TAU * float(i) / float(RIM_SAMPLES)
			pts.append(centre + Vector2(cos(a) * r, sin(a) * r * aspect).rotated(rot))
	if pts.size() < 3:
		return PackedVector2Array()
	return _octagon(Geometry2D.convex_hull(pts))


## An area may carry at most eight corners (`AuthoredMap._validate_area`), and a hull of a
## dozen overlapping lobes has twenty. Reduced by SUPPORT POINTS: for each of eight evenly
## spaced directions, keep the hull vertex that reaches furthest that way. That is the widest
## convex octagon inside the hull's own extent, so the wood keeps its shape and its size
## rather than being replaced by a bounding box.
func _octagon(hull: PackedVector2Array) -> PackedVector2Array:
	if hull.size() <= MAX_CORNERS:
		return hull
	var kept: Array[int] = []
	for i in MAX_CORNERS:
		var dir := Vector2.RIGHT.rotated(TAU * float(i) / float(MAX_CORNERS))
		var best := 0
		var best_dot := -INF
		for k in hull.size():
			var d: float = hull[k].dot(dir)
			if d > best_dot:
				best_dot = d
				best = k
		if not kept.has(best):
			kept.append(best)
	kept.sort()   # keep the hull's winding
	var out := PackedVector2Array()
	for index in kept:
		out.append(hull[index])
	return out
