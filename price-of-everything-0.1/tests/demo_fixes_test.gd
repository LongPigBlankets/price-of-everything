extends Node
const Buildings := preload("res://scenes/building_visuals.gd")
const Layout := preload("res://scripts/start_layout_baked.gd")
const AM := preload("res://scripts/authored_map.gd")
const Shapes := preload("res://scripts/authored_special_shapes.gd")
var failures := 0
var checks := 0

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	check(MatchState.construct_auto_buy_land, "Automatic land buying defaults on")
	MatchState.set_construct_auto_buy_land(false)
	check(not MatchState.construct_auto_buy_land, "User can switch automatic land buying off")
	MatchState.set_construct_auto_buy_land(true)
	var bv := Buildings.new()
	# Relayout can move a quad without changing its vertex count. Both zoom tiers must move.
	var first := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var moved := PackedVector2Array([Vector2(30, 0), Vector2(40, 0), Vector2(40, 10), Vector2(30, 10)])
	bv._add_silhouette(PackedVector2Array(), PackedColorArray(), "relayout", first, Color.WHITE)
	var pts := PackedVector2Array()
	bv._add_silhouette(pts, PackedColorArray(), "relayout", moved, Color.WHITE)
	for point in pts:
		check(point.x >= 30, "Far silhouette follows a moved building")
	var layout := Layout.layout()
	check(not layout.is_empty(), "Starting layout is current")
	check((layout.get("_placements", []) as Array).size() == 417, "All 417 starting placements survive")
	var farms := 0
	var vandel := 0
	for p in layout.get("_placements", []):
		if p.tile_id == "tile_6_9" and p.cat == "farm":
			farms += 1
			var clipped: PackedVector2Array = bv._farm_on_land(p.verts)
			check(absf(BuildingShapes.polygon_area(clipped) - BuildingShapes.polygon_area(p.verts)) < 1.0,
				"Stoneshore farm footprint stays inside the coastline")
			var render: Dictionary = layout._farm_render.get(p.instance_id, {})
			check(not render.is_empty() and render.verts.size() >= 3, "Coastal farm remains visible")
		if p.tile_id == "tile_22_16" and p.get("hijack_id", "") != "":
			vandel += 1
			for other in AM.settlements()["procedural-vandel"].specials:
				if other.id == p.hijack_id:
					continue
				var area := 0.0
				for piece in Geometry2D.intersect_polygons(p.verts, Shapes.render_polygon(other)):
					area += BuildingShapes.polygon_area(piece)
				check(area <= maxf(1.0, BuildingShapes.polygon_area(p.verts) * 0.01), "Vandel claim clears neighbouring decor")
	check(farms == 2, "Both Stoneshore coast farms are retained")
	check(vandel == 7, "Six Vandel industries and the port office use separate decorative footprints")
	for sc in layout.get("_subcomponents", []):
		check(sc.get("iid", "") != "inst_b_004_0003f0", "Vandel port has no generated NPC wing over the town")
	bv.free()
	await get_tree().process_frame
	print("[demo_fixes] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
