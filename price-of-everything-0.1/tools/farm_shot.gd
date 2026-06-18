extends Node2D
# Dev-only: set up a few farms on a tile and capture the BuildingVisuals render to a PNG so changes
# to the farm-lane visuals can be eyeballed. Run (windowed, NOT --headless, so it actually renders):
#   Godot --path . res://tools/farm_shot.tscn --quit-after 600
var _bv
var _frame := 0

func _ready() -> void:
	var terrain := TileMapLayer.new()
	terrain.tile_set = load("res://assets/main_tileset.tres")
	terrain.set_script(load("res://scripts/hex_map.gd"))
	add_child(terrain)
	await get_tree().process_frame
	await get_tree().process_frame
	RoadNetwork.reset()
	_bv = preload("res://scenes/building_visuals.gd").new()
	add_child(_bv)
	await get_tree().process_frame
	_bv.terrain_layer = terrain
	var tile_id := "tile_9_10"   # tile_7_9 has a river through it (per-bank split); 9_10 is a clean cluster
	var coord: Vector2i = terrain.id_to_coord(tile_id)
	for i in 10:
		var iid: String = MatchState.add_building("b_014", "", tile_id, "npc", "shot_%d" % i)
		_bv.on_building_placed(tile_id, "b_014", "", iid, coord)
	_bv._rebuild_subcomponents(tile_id)
	var c: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
	# Draw the river arms (cyan) so a per-bank split is visible.
	for r in (_bv._tile_rivers.get(tile_id, []) as Array):
		var rl := Line2D.new()
		rl.points = PackedVector2Array([c + (r[0] as Vector2), c + (r[1] as Vector2)])
		rl.width = 12.0
		rl.default_color = Color(0.15, 0.45, 0.95, 0.95)
		add_child(rl)
	# Route a road ACROSS the cluster and draw its path (Stage 2 routing bias — it should thread the web).
	var realizer = preload("res://scripts/road_realizer.gd").new()
	var res: Dictionary = realizer.route(NavGrid.instance(), RoadNetwork.instance(), c + Vector2(-360, 40), c + Vector2(360, -40), {"thorough": true})
	if bool(res.get("ok", false)):
		RoadWorks._snap_route_to_web(res)   # borrow the web: follow the ring around the cluster
		var line := Line2D.new()
		line.points = res.geometry
		line.width = 7.0
		line.default_color = Color(0.85, 0.2, 0.15, 0.9)   # red road path over the brown web
		add_child(line)
	var cam := Camera2D.new()
	cam.position = c
	cam.zoom = Vector2(2.5, 2.5)
	add_child(cam)
	cam.make_current()
	_bv.queue_redraw()

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://farm_shot.png")
		print("SAVED farm_shot.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
