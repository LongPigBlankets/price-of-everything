extends Node2D
# Dev-only: place buildings on several URBAN tiles, each anchored to a DIAGONAL built road at a different
# tilt, force block mode, fire a block enclosure on each, and render — to eyeball that the lot grid +
# buildings snap their LONG side to the road and the enclosure ring follows the road angle (±45 tilt),
# with the frontage road forming one side. headless tests can't catch the draw clip.
#   Godot --path . res://tools/enclosure_shot.tscn --quit-after 600
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
	RoadWorks.reset()
	_bv = preload("res://scenes/building_visuals.gd").new()
	add_child(_bv)
	var rnv := Node2D.new()
	rnv.set_script(load("res://scripts/road_network_visuals.gd"))
	add_child(rnv)
	var offs := Node2D.new()
	offs.set_script(load("res://scripts/road_offshoots.gd"))
	add_child(offs)
	await get_tree().process_frame
	_bv.terrain_layer = terrain
	# [tile, building count, road tilt in degrees] — varied tilts to show the ±45 alignment
	var specs := [["tile_9_10", 9, 24.0], ["tile_10_10", 12, -22.0], ["tile_11_10", 14, 38.0], ["tile_9_11", 7, -41.0]]
	var net := RoadNetwork.instance()
	var sum_c := Vector2.ZERO
	var nt := 0
	for spec in specs:
		var tid: String = spec[0]
		var count: int = spec[1]
		var deg: float = spec[2]
		var coord: Vector2i = terrain.id_to_coord(tid)
		if not terrain.tiles.has(coord):
			continue
		terrain.tiles[coord]["type"] = "urban"
		terrain.tiles[coord]["infrastructure_present"] = ["roads"]   # so the frontage road draws
		# a straight diagonal BUILT road across the tile to anchor the block to — FINELY sampled
		# (~12u/segment, like real roads) so _longest_straight_road sees many in-hex points.
		var center: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord))
		var dir := Vector2.RIGHT.rotated(deg_to_rad(deg))
		var a := center - dir * 190.0
		var b := center + dir * 190.0
		var geo := PackedVector2Array()
		var steps := int(a.distance_to(b) / 12.0)
		for s in range(steps + 1):
			geo.append(a.lerp(b, float(s) / float(steps)))
		var na: Dictionary = net.ensure_node("rd:%s:a" % tid, RoadNetwork.KIND_JUNCTION, a, coord)
		var nb: Dictionary = net.ensure_node("rd:%s:b" % tid, RoadNetwork.KIND_JUNCTION, b, coord)
		net.add_edge(str(na.id), str(nb.id), RoadNetwork.TIER_LOCAL, geo, [coord], [], 1, RoadNetwork.STATE_BUILT)
		_bv._tile_block_mode[tid] = true   # force block mode
		var last := ""
		for i in count:
			var iid: String = MatchState.add_building("b_007", "", tid, "player_1", "es_%s_%d" % [tid, i])
			_bv.on_building_placed(tid, "b_007", "", iid, coord)
			last = iid
		# DEV river test: uncomment to inject a synthetic river (rel-to-centre) and watch the enclosure
		# budge to the anchor's bank + drop far-bank buildings.
		#_bv._tile_rivers[tid] = [[Vector2(40.0, -260.0), Vector2(-40.0, 260.0)]]
		# FORCE the enclosure for the demo (bypass the ~40% seed): build the template + emit directly.
		_bv.ensure_block_template_for(tid, coord)
		if RoadWorks._emit_enclosure(tid, coord, last):
			RoadWorks._enclosure_bands[tid] = 1
		sum_c += center
		nt += 1
	print("enclosed tiles=", nt)
	# RELOAD SIM: rebuild every template with the enclosure rings ALREADY in the network — the path that
	# broke (the ring poisoned the block anchor + cleared the lots it wraps). Templates must survive intact.
	_bv.relayout()
	var cam := Camera2D.new()
	cam.position = sum_c / maxf(1.0, float(nt))
	cam.zoom = Vector2(1.5, 1.5)
	add_child(cam)
	cam.make_current()

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 10:
		# count AFTER the deferred enclosure pass has flushed (it fires call_deferred from _ready)
		var net := RoadNetwork.instance()
		var encl := 0
		for eid in net.edges:
			var e: Dictionary = net.edges[eid]
			if str(e.a).begins_with("encl:") or str(e.b).begins_with("encl:"):
				encl += 1
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://enclosure.png")
		print("encl: edges=", encl, "  SAVED enclosure.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
