extends Node
const Buildings := preload("res://scenes/building_visuals.gd")
const ConstructPanelScript := preload("res://scripts/construct_panel_v2.gd")
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
	var panel := ConstructPanelScript.new()
	panel._selected_recipe = {"inputs": [{"good_id": "g_010", "qty": 1}, {"good_id": "g_009", "qty": 1}, {"good_id": "g_012", "qty": 1}], "outputs": [{"good_id": "g_010", "qty": 1}], "energy_req": 1}
	panel._selected_building = Catalog.get_building_by_internal_name("solar_farm")
	panel._locked_tile_id = "tile_6_9"
	panel._v3_land = {"needed": 10, "free": 20, "short": 0, "covered": true}
	var rows: Array = panel._v3_requirement_rows()
	var grid: Control = rows[0]
	add_child(grid)
	check(grid.find_children("Requirement_cables", "Button", true, false).size() == 1, "Input and output power share one requirement icon")
	var cable: Button = grid.find_child("Requirement_cables", true, false)
	var land: Button = grid.find_child("Requirement_land", true, false)
	var cable_detail: Control = grid.find_child("RequirementDetail_cables", true, false)
	var land_detail: Control = grid.find_child("RequirementDetail_land", true, false)
	check(not cable_detail.visible and not land_detail.visible, "Requirements start collapsed")
	cable.pressed.emit()
	check(cable_detail.visible and not land_detail.visible, "Click opens requirement explanation")
	land.pressed.emit()
	check(land_detail.visible and not cable_detail.visible, "Selecting another icon switches explanation")
	land.pressed.emit()
	check(not land_detail.visible, "Second click collapses explanation")
	check(grid.get_child_count() == 4, "Five requirements use two icon rows and two disclosure rows")
	check(grid.get_child(0).get_child_count() == 3 and grid.get_child(2).get_child_count() == 3,
		"Both rows have three equal-width slots")
	check(land_detail.get_parent() == grid.get_child(3), "Second-row requirement expands below the second row")
	await get_tree().process_frame
	await get_tree().process_frame
	for button in grid.find_children("Requirement_*", "Button", true, false):
		check(button.size == Vector2(116, 106), "Requirement control is 116px wide and 106px high")
		var icon: Control = button.find_child("RequirementIcon", true, false)
		var caption: Control = button.find_child("RequirementCaption", true, false)
		check(icon.size == Vector2(80, 80), "Requirement icon uses the full 80px square")
		check(caption.FONT.get_string_size(caption.text, HORIZONTAL_ALIGNMENT_LEFT, -1, DS.FS.BODY).x + 20 <= caption.size.x, "Caption and status swatch fit without clipping")
		check(button.get_theme_stylebox("normal").get_border_width(SIDE_LEFT) == 0, "Requirement control has no outline")
		check(caption.position.y == 83 and caption.size.y == 20, "Caption has a 3px gap below the icon")
	grid.queue_free()
	panel.free()
	await get_tree().process_frame
	print("[demo_fixes] %d checks, %d failures" % [checks, failures])
	get_tree().quit(0 if failures == 0 else 1)
