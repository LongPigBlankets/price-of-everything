extends Node2D
## Load the REAL main scene and verify the match-start sequence is now roads -> enclosures -> buildings:
## urban tiles should carry a cosmetic street, ~40% of them an enclosure ring + cached chunk template formed
## BEFORE any building, and the game-start NPC/start buildings should have dropped INTO those chunk grids.
##   Godot --path . res://tools/real_tile_shot.tscn --quit-after 800
var _wm
var _bv
var _terrain
var _frame := 0
const TARGETS := ["tile_5_10", "tile_11_17"]   # Stoneshore port, Arin docks
const RENDER := "tile_5_10"

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	for _i in 12:
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	_bv = _wm.get_node("%BuildingVisuals")
	var urban := 0
	for coord in _terrain.tiles:
		if str((_terrain.tiles[coord] as Dictionary).get("type", "")).to_lower() == "urban":
			urban += 1
	var enclosed := 0
	for tid in RoadWorks._enclosure_edges:
		if (RoadWorks._enclosure_edges[tid] as Array).size() > 0:
			enclosed += 1
	print("[AUTO] urban_tiles=%d enclosed_at_start=%d (before any building)" % [urban, enclosed])
	var render_center := Vector2.ZERO
	for tid in TARGETS:
		var coord: Vector2i = _terrain.id_to_coord(tid)
		var t: Dictionary = _bv._tile_block_templates.get(tid, {})
		var td2: Dictionary = _terrain.tiles.get(coord, {})
		print("[AUTO] %s template=%d lots cell=%s encl_edges=%d buildings=%d infra=%s" % [tid, (t.get("lots", []) as Array).size(), str(t.get("cell", Vector2.ZERO)), (RoadWorks._enclosure_edges.get(tid, []) as Array).size(), MatchState.get_buildings_on_tile(tid).size(), str(td2.get("infrastructure_present", []))])
		if tid == RENDER:
			render_center = _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
			# Simulate the "future player buildings at game start" the user mentioned — they should FILL the
			# enclosure's ready chunk grid (template already cached by seed_urban_enclosures).
			for i in 6:
				var iid: String = MatchState.add_building("b_007", "", tid, "player_1", "pf_%s_%d" % [tid, i])
				_bv.on_building_placed(tid, "b_007", "", iid, coord)
	var cam := Camera2D.new()
	cam.position = render_center
	cam.zoom = Vector2(1.7, 1.7)
	add_child(cam)
	cam.make_current()

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 16:
		get_viewport().get_texture().get_image().save_png("res://real_tile.png")
		print("SAVED real_tile.png")
		get_tree().quit()
