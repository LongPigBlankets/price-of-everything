extends "res://tools/supply_chain_3d/capture.gd"
const Region := preload("res://scripts/supply_chain_3d/authored_region.gd")
var output := "res://../outputs/supply-chain-3d/stoneshore/"

func _ready() -> void:
	PlayerProfile.supply_chain_all_tiles = false
	await super._ready()

func _continent_review(board: Control, home: Dictionary) -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--region-output="): output = arg.trim_prefix("--region-output=")
	DirAccess.make_dir_recursive_absolute(output)
	var started := Time.get_ticks_usec()
	await board.set_all_tiles(true, false)
	await board._stream_visible()
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	var ready_ms := (Time.get_ticks_usec() - started) / 1000.0
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var builder: RefCounted = board._builder
	var report := {"ready_ms": ready_ms, "load": board.load_profile.duplicate(), "region": board._model.authored_region.duplicate(true),
		"crossings": builder.authored_profile.crossings, "unresolved_crossings": builder.authored_profile.unresolved, "npcs": [], "views": []}
	report.civic = board._model.standing.filter(func(s: Dictionary) -> bool: return s.has("decor_family"))
	if "--junction-review" in OS.get_cmdline_user_args():
		var flags := {}
		for tile in board._last_terrain.tiles.values():
			if "roads" in tile.get("infrastructure_present", []): flags[str(tile.id)] = true
		var raw := Region.source_paths(board._last_terrain, flags)
		report.junctions = {"source": Region.Index.audit(raw, builder.surface_height),
			"authored": Region.Index.audit(board._layout_queries.data.authored_network.paths, builder.surface_height),
			"with_access": Region.Index.audit(board._model.authored_region.paths, builder.surface_height)}
		print("[JUNCTIONS] raw=", report.junctions.source.near_endpoints_within_3u, "/", report.junctions.source.stubs_under_3u,
			" authored=", report.junctions.authored.near_endpoints_within_3u, "/", report.junctions.authored.stubs_under_3u,
			" with_access=", report.junctions.with_access.near_endpoints_within_3u, "/", report.junctions.with_access.stubs_under_3u)
	if "--load-only" in OS.get_cmdline_user_args():
		FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
		print("[ROAD LOAD] ready_ms=", ready_ms, " bridges=", report.crossings.size(), " unresolved=", report.unresolved_crossings.size())
		return
	report.harbour_poses = []
	for s in board._model.standing:
		if s.get("npc", false): report.npcs.append(s)
		if s.has("harbour"):
			var frame: Dictionary = builder.standing_frame(s)
			var harbour_tools := preload("res://scripts/supply_chain_3d/harbour.gd")
			var assets := preload("res://scripts/supply_chain_3d/assets.gd")
			var afloat := harbour_tools.ships_afloat(assets.harbour_for(frame.harbour_asset), frame.harbour_transform, s.pos, builder.surface_height)
			if not afloat:
				push_error("Authored harbour ships must remain in water: " + str(s.tile))
				get_tree().quit(1)
				return
			report.harbour_poses.append({"tile": s.tile, "shore_shift": frame.harbour_shore_shift, "deck": frame.harbour_deck, "ships_afloat": afloat})
	for road in board._model.roads:
		if road.tile in Region.tile_ids(): assert(road.kind == "authored")
	var footprints := get_tree().get_first_node_in_group("building_footprints")
	for s in report.npcs:
		if s.has("harbour"): continue
		var iid := str(s.get("port_iid", s.iid))
		var expected: Vector2 = footprints.footprint_center_for(iid, board._last_terrain.id_to_coord(s.tile))
		assert((s.pos as Vector2).distance_to(expected) < 0.01)
	var state := home.duplicate()
	var c := Vector2.ZERO
	for tid in Region.tile_ids(): c += board._model.tiles[tid].center
	c /= Region.tile_ids().size()
	var views := [
		{"name": "region-far", "point": c, "span": board.size.y / 0.24, "pitch": 0.85, "yaw": 0.0},
		{"name": "region-overview", "point": c, "span": 1450.0, "pitch": 1.35, "yaw": 0.0},
		{"name": "town-medium", "point": board._model.tiles.tile_4_9.center, "span": board.size.y / 1.1, "pitch": 0.85, "yaw": 0.0},
		{"name": "town-near", "point": board._model.tiles.tile_4_9.center, "span": 370.0, "pitch": 0.75, "yaw": 0.5},
		{"name": "coast-medium", "point": board._model.tiles.tile_6_9.center, "span": board.size.y / 1.1, "pitch": 0.85, "yaw": 0.0}]
	views.append_array([
		{"name": "old-quarter-west", "point": Vector2(2150, 5820), "span": 570.0, "pitch": 1.2, "yaw": 0.0},
		{"name": "harbour-medium", "point": Vector2(2640, 5840), "span": board.size.y / 1.1, "pitch": 0.85, "yaw": 0.0},
		{"name": "harbour-near", "point": Vector2(2640, 5840), "span": 370.0, "pitch": 0.85, "yaw": 0.0},
		{"name": "harbour-reverse", "point": Vector2(2640, 5840), "span": 370.0, "pitch": 0.70, "yaw": 2.8}])
	if "--road-rollout" in OS.get_cmdline_user_args():
		views.clear()
		for tid in ["tile_4_9", "tile_23_8", "tile_11_17", "tile_22_3"]:
			for lod in 3:
				views.append({"name": "%s-lod%d" % [tid, lod], "point": board._model.tiles[tid].center,
					"span": [board.size.y / 0.24, board.size.y / 1.1, 370.0][lod], "pitch": 0.95, "yaw": 0.0})
	if "--junction-review" in OS.get_cmdline_user_args():
		views = [
			{"name": "trimmed-arin", "point": Vector2(6812, 7559), "span": 145.0, "pitch": 1.3, "yaw": 0.0},
			{"name": "trimmed-branch", "point": Vector2(4170, 5918), "span": 145.0, "pitch": 1.3, "yaw": 0.0},
			{"name": "joined-capital", "point": Vector2(10804, 5224), "span": 145.0, "pitch": 1.3, "yaw": 0.0}]
		for lod in 3:
			views.append({"name": "stoneshore-lod%d" % lod, "point": board._model.tiles.tile_4_9.center,
				"span": [board.size.y / 0.24, board.size.y / 1.1, 370.0][lod], "pitch": 0.95, "yaw": 0.0})
	if "--all-harbours" in OS.get_cmdline_user_args():
		for s in board._model.standing:
			if s.has("harbour") and s.tile != "tile_5_10":
				views.append({"name": "harbour-" + str(s.tile), "point": s.pos, "span": 600.0, "pitch": 0.90, "yaw": 0.0})
	if "--farm-review" in OS.get_cmdline_user_args():
		views.clear()
		for tid in ["tile_9_15", "tile_14_5", "tile_18_18"]:
			var center: Vector2 = board._model.tiles[tid].center
			for s in board._model.standing:
				if s.tile == tid and s.get("internal_name", "") == "farm": center = s.pos; break
			for lod in 3:
				views.append({"name": "farm-%s-lod%d" % [tid, lod], "point": center,
					"span": [board.size.y / 0.24, board.size.y / 1.1, 240.0][lod], "pitch": 1.05, "yaw": 0.0})
		views.append({"name": "farm-orbit", "point": Vector2(4529.89, 7941.78), "span": 160.0, "pitch": 0.65, "yaw": 1.7})
	if "--civic-review" in OS.get_cmdline_user_args():
		views.clear()
		for lod in 3:
			views.append({"name": "stoneshore-lod%d" % lod, "point": board._model.tiles.tile_4_9.center,
				"span": [board.size.y / 0.24, board.size.y / 1.1, 370.0][lod], "pitch": 0.95, "yaw": 0.0})
		views.append({"name": "old-quarter", "point": board._model.tiles.tile_4_10.center, "span": 480.0, "pitch": 1.05, "yaw": 0.35})
		var seen := {}
		for s in report.civic:
			if seen.has(s.decor_family): continue
			seen[s.decor_family] = true
			views.append({"name": str(s.decor_family), "point": s.pos, "span": 150.0, "pitch": 0.80, "yaw": 0.5})
		if "--modular-review" in OS.get_cmdline_user_args():
			for shape in ["long", "l"]:
				var examples: Array = report.civic.filter(func(s: Dictionary) -> bool:
					return s.has("decor_asset") and preload("res://scripts/supply_chain_3d/civic_layout.gd").modular_shape(s) == shape)
				examples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.civic_bays.x + a.civic_bays.y < b.civic_bays.x + b.civic_bays.y)
				if examples.is_empty(): continue
				for selection in [{"name": "short", "s": examples.front()}, {"name": "extended", "s": examples.back()}]:
					views.append({"name": "modular-%s-%s" % [shape, selection.name], "point": selection.s.pos,
						"span": 175.0, "pitch": 0.85, "yaw": 0.5})
	for crossing in ([] if "--road-rollout" in OS.get_cmdline_user_args() or "--junction-review" in OS.get_cmdline_user_args() or "--farm-review" in OS.get_cmdline_user_args() or "--civic-review" in OS.get_cmdline_user_args() else builder.authored_profile.crossings):
		var middle: Vector2 = (crossing.a + crossing.b) * 0.5
		if builder.tile_at(builder.point(middle)) not in Region.tile_ids(): continue
		views.append({"name": "bridge-" + str(views.size()), "point": middle, "span": 120.0, "pitch": 0.25, "yaw": 2.00})
	for view in views:
		if "--all-harbours" in OS.get_cmdline_user_args() and not str(view.name).begins_with("harbour-"): continue
		if "--port-pick-only" in OS.get_cmdline_user_args() and view.name != "harbour-near": continue
		state.target = builder.point(view.point)
		state.span = view.span
		state.pitch = view.pitch
		state.yaw = view.yaw
		board.restore_camera(state)
		await board._stream_visible()
		while not board.detail_ready():
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		for i in 5:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		board._viewport.get_texture().get_image().save_png(output.path_join(view.name + ".png"))
		if view.name == "harbour-near":
			var harbour: Dictionary = {}
			for s in board._model.standing:
				if s.has("harbour") and s.tile == "tile_5_10": harbour = s; break
			assert(not harbour.is_empty())
			var frame: Dictionary = builder.standing_frame(harbour)
			# The end of the left pier is outside its owning hex. It must still
			# activate that harbour's exact collider, not the adjacent water tile.
			var screen: Vector2 = board.screen_point(frame.position + frame.harbour_pier_tip)
			board.pick_at(screen)
			await get_tree().physics_frame
			var hit: Dictionary = board.pick_at(screen)
			assert(not hit.is_empty() and str(hit.collider.get_meta("standing", {}).get("iid", "")) == str(harbour.iid))
			report.cross_tile_port_pick = str(harbour.iid)
			var water_screen: Vector2 = board.screen_point(frame.position + frame.harbour_basin)
			board.pick_at(water_screen)
			await get_tree().physics_frame
			var water_hit: Dictionary = board.pick_at(water_screen)
			assert(not water_hit.is_empty() and not water_hit.collider.has_meta("standing"))
			report.port_basin_selects_water = true
			var host := get_tree().current_scene
			host.find_child("EmpireView", true, false)._on_building_picked(str(harbour.iid))
			assert(str(host._last_detail_building.get("instance_id", "")) == str(harbour.iid))
			host.building_panel_v2.hide()
			report.port_panel_instance = str(harbour.iid)



		report.views.append({"name": view.name, "lod": board._detail})
	# NPC selection opens its real building panel without switching to a missing
	# player-only supply graph. The normal projected-size/LOD picking gates remain.
	var main := get_tree().current_scene
	var view := main.find_child("EmpireView", true, false)
	for npc in report.npcs:
		if str(npc.kind) != "building": continue
		view._on_building_picked(str(npc.iid))
		assert(str(main._last_detail_building.get("instance_id", "")) == str(npc.iid))
		main.building_panel_v2.hide()
		report.npc_selection_checked = str(npc.iid)
		break
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("[STONESHORE] ", output, " npcs=", report.npcs.size(), " bridges=", report.crossings.size(), " joined=", report.region.joined)
