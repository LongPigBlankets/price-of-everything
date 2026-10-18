extends "res://tools/supply_chain_3d/trials/works_tile_shot.gd"
## One clean company tile holding the industrial goods factory, power plant, furnace and
## polymerisation refinery at level 3, built through the game's construct flow (land bought,
## kit on the tile, project completed as a turn would), each turned to its own angle and set beside the tile's
## roads (never on them), shot in daylight with pollution hidden from the regular camera.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/tile_yaw_shot.tscn -- --no-telemetry --out=<dir> [--tile=tile_6_9] [--scale=1.25] [--no-fit] [--spans=350,220]
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Placement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
## [building, recipe, turn in degrees]. 0 is the regular grid angle.
const TILE_WORKS := [["b_007", "r_008", 0.0], ["b_003", "r_038", 15.0], ["b_002", "r_005", 35.0], ["b_013", "r_024", 50.0]]
## Clear distance from the road's paved edge (and its footway) to the building's mass.
const ROAD_GAP := 2.5
## Clear distance between two works.
const WORK_GAP := 8.0
var turns := {}
## Presentation trial: the works drawn this many times larger again, on top of the game's
## own building_scale.gd BUILDINGS_SCALE.
var work_scale := 1.0
var rejects := {}
var board: Control

func _ready() -> void:
	var spans := [350.0, 220.0]
	var tile := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tile="): tile = arg.trim_prefix("--tile=")
		if arg.begins_with("--scale="): work_scale = float(arg.trim_prefix("--scale="))
		if arg.begins_with("--out="): out = arg.trim_prefix("--out=")
		if arg.begins_with("--spans="): spans = Array(arg.trim_prefix("--spans=").split(",")).map(func(v: String) -> float: return float(v))
	DirAccess.make_dir_recursive_absolute(out)
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	Harness.arm_watchdog(self, 1200.0)
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	AudioServer.set_bus_mute(0, true)
	var menu: Control = load("res://scenes/main_menu.tscn").instantiate()
	get_tree().root.add_child.call_deferred(menu)
	await get_tree().process_frame
	get_tree().current_scene = menu
	menu.call("_on_new_game_pressed")
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json")
	var loading := LoadingScreen.show_global(get_tree())
	loading.begin_load(SaveLoad.MAIN_SCENE)
	var main: Node
	while true:
		main = get_tree().current_scene
		if main != menu and main != null and bool(main.get("build_complete")): break
		await get_tree().process_frame
	while not bool(loading.call("_ready_to_begin")): await get_tree().process_frame
	loading.call("_on_begin_pressed")
	while is_instance_valid(loading): await get_tree().process_frame
	for i in 3: await get_tree().process_frame
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	DecisionState.enabled = false
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script := layer.get_script() as Script
		if script != null and script.resource_path.ends_with("_intro.gd"):
			if layer.has_method("_on_begin"): layer.call("_on_begin")
			else: layer.queue_free()
	for i in 3: await get_tree().process_frame
	if tile == "": tile = _clean_tiles(1)[0]
	print("[TILE] ", tile, " type=", Catalog.tile_type(tile), " label=", Catalog.tile_label(tile),
		" land owned=", BuildingState.get_tile_land_owned(tile), " for sale=", BuildingState.get_tile_land_units_available(tile, BuildingState.max_tile_land(tile)),
		" used=", BuildingState.get_tile_space_used(tile), " max=", BuildingState.max_tile_land(tile))
	_build_works(main, tile)
	# The layout hook runs inside every solve, before the frontage pass reserves plots and
	# draws the driveways, so the works it moves get their access roads from the game.
	# --no-fit: the game's own placement, unturned, for an honest in-game picture.
	if "--no-fit" not in OS.get_cmdline_user_args(): Board.offline_layout_reuse = _fit_works
	var view: Control = main.find_child("EmpireView", true, false)
	# Bound before the first solve: the overlay memoises each changed tile's layout.
	board = view.find_child("Board", true, false)
	await view.call("prepare")
	Harness.prepare_window(get_window(), Vector2i(1920, 1080))
	for i in 5: await get_tree().process_frame
	view.call("toggle")
	await get_tree().physics_frame
	await board.call("set_all_tiles", false, false)
	await _settle(board)
	Legacy.show.pollution = false
	await board.call("build_async", board.get("_last_graph"), board.get("_last_terrain"))
	await _settle(board)
	var points := []
	for item in board.get("_builder").pickables:
		if turns.has(str(item.iid)): points.append(item.point)
	var centre: Vector3 = board.get("_builder").point(board.get("_model").tiles[tile].center)
	if not points.is_empty():
		centre = points.reduce(func(sum: Vector3, p: Vector3) -> Vector3: return sum + p, Vector3.ZERO) / points.size()
	_audit(board.get("_model"))
	var first := true
	for span in spans:
		var state: Dictionary = board.call("capture_camera")
		state.target = centre
		state.span = span
		board.call("restore_camera", state)
		await _settle(board)
		# The first frame after a rebuild can be refitted by the board; settle it twice.
		if first:
			board.call("restore_camera", state)
			await _settle(board)
			first = false
		RenderingServer.force_draw(false)
		var name := "turned_%d.png" % int(span)
		board.get("_viewport").get_texture().get_image().save_png(out.path_join(name))
		print("[COLOUR] ", name, " detail=", board.get("_detail"))
	# One close frame per work, to show where it meets the street.
	for item in board.get("_builder").pickables:
		if not turns.has(str(item.iid)): continue
		var state: Dictionary = board.call("capture_camera")
		state.target = item.point
		state.span = 230.0
		# A background load finishing meanwhile can move the camera: apply it until it holds.
		for attempt in 4:
			board.call("restore_camera", state)
			await _settle(board)
			var now: Dictionary = board.call("capture_camera")
			if (now.target as Vector3).distance_to(state.target) < 1.0 and absf(float(now.span) - float(state.span)) < 1.0: break
		board.call("restore_camera", state)
		for i in 3:
			RenderingServer.force_draw(false)
			await get_tree().process_frame
		RenderingServer.force_draw(false)
		print("[CAMERA] ", board.call("capture_camera"))
		var name := "close_%s_%d.png" % [str(item.iid).get_slice("_", 2), int(rad_to_deg(turns[str(item.iid)]))]
		board.get("_viewport").get_texture().get_image().save_png(out.path_join(name))
		print("[COLOUR] ", name)
	Board.offline_layout_reuse = Callable()
	await _finish(main, board)

## Turn each work to its angle and stand it beside a road on its tile: the paved road and its
## footway stay clear, and a road segment parallel to the work's walls is preferred, so the
## work sits square to the street where the street allows.
func _fit_works(model: Dictionary, _queries, rivers: Dictionary, key_for: Callable) -> void:
	var works: Array = model.get("standing", []).filter(func(s: Dictionary) -> bool: return turns.has(str(s.iid)))
	if works.is_empty(): return
	if board == null: board = get_tree().root.find_child("Board", true, false) as Control
	if board == null or board.get("_builder") == null:
		print("[FIT] no board yet; works keep their slots")
		return
	var tid := str(works[0].tile)
	var centre: Vector2 = model.tiles[tid].center
	# A changed tile is laid out against the shipped roads it keeps (tile_overlay.gd).
	var shipped: Dictionary = Board._shipped_model
	var roads: Array = (shipped if not shipped.is_empty() else model).get("roads", []).filter(
		func(r: Dictionary) -> bool: return Index.contains(centre, r.a) or Index.contains(centre, r.b))
	var builder: RefCounted = board.get("_builder")
	rejects.clear()
	var lengths: Array = roads.map(func(r: Dictionary) -> float: return (r.a as Vector2).distance_to(r.b))
	lengths.sort()
	print("[FIT] lengths min/median/max ", lengths[0] if lengths else 0, " ", lengths[lengths.size() / 2] if lengths else 0, " ", lengths[-1] if lengths else 0, " keys ", roads[0].keys() if roads else [])
	print("[FIT] tile=", tid, " roads=", roads.size(), " shipped=", not shipped.is_empty(), " standing on tile=", model.standing.filter(func(s: Dictionary) -> bool: return str(s.tile) == tid).map(func(s: Dictionary) -> String: return str(s.kind)))
	var taken: Array = []
	for s in model.standing:
		if str(s.tile) != tid or turns.has(str(s.iid)): continue
		# Houses give way: the frontage pass after this hook refits them around the plots taken
		# here, or leaves them out, as a real build clears town fabric. A warehouse or depot that finds no new frontage keeps its slot, so it is kept
		# clear. Harbours keep their quays.
		if s.has("harbour"):
			taken.append(s.harbour.main_quay)
			taken.append_array(s.harbour.quays)
		elif str(s.kind) == "house":
			continue
		elif str(s.kind) != "pylon":
			taken.append_array(Footprints.reserved(str(key_for.call(s)), s))
	var wet_lines: Array = []
	for records in rivers.values():
		for rec in records:
			for i in range(1, rec.points.size()):
				wet_lines.append([rec.points[i - 1], rec.points[i], maxf(float(rec.start_width), float(rec.end_width)) * 0.5 + 3.0])
	# Largest first: the big plots choose before the small ones fill in.
	works.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var da: Vector3 = Assets.dimensions(str(key_for.call(a))) * float(a.side)
		var db: Vector3 = Assets.dimensions(str(key_for.call(b))) * float(b.side)
		return da.x * da.z > db.x * db.z)
	for s in works:
		s.yaw = turns[str(s.iid)]
		# Scaled once per solve: the layout memo hands back the fitted copy, already scaled.
		if work_scale != 1.0 and not s.get("trial_scaled", false):
			s.pad = float(s.get("pad", s.side)) * work_scale
			s.side = float(s.side) * work_scale
			s.trial_scaled = true
		var key := str(key_for.call(s))
		var best := {}
		var best_score := INF
		for road in roads:
			var a: Vector2 = road.a
			var b: Vector2 = road.b
			if a.distance_to(b) < 0.5: continue
			var tangent := (b - a).normalized()
			var half := float(road.get("widths", [5.0])[0])
			var mismatch := fposmod(float(s.yaw) + tangent.angle(), PI * 0.5)
			mismatch = minf(mismatch, PI * 0.5 - mismatch)
			for k in range(1, 4):
				var point := a.lerp(b, k / 4.0)
				for direction in [1.0, -1.0]:
					var normal: Vector2 = tangent.orthogonal() * direction
					var trial: Dictionary = s.duplicate()
					trial.erase("footprint")
					trial.pos = point
					var reach := 0.0
					for shape in Footprints.rendered(key, trial):
						for corner in shape: reach = maxf(reach, -(corner - point).dot(normal))
					trial.pos = point + normal * (half + Sidewalks.width(road) + ROAD_GAP + reach)
					var shapes := Footprints.rendered(key, trial)
					if not _clear(shapes, centre, roads, taken, wet_lines, builder): continue
					var score := rad_to_deg(mismatch) * 4.0 + (trial.pos as Vector2).distance_to(centre) * 0.05
					if score < best_score:
						best_score = score
						best = {"pos": trial.pos, "shapes": shapes}
		if best.is_empty():
			print("[FIT] ", s.iid, " found no clear frontage; left on its slot. rejects=", rejects)
			continue
		s.pos = best.pos
		# The slot square no longer describes the plot: the turned mass is the plot.
		s.footprint = best.shapes[0]
		taken.append_array(best.shapes)
		print("[FIT] ", s.iid, " yaw=", rad_to_deg(float(s.yaw)), " pos=", s.pos, " score=", snappedf(best_score, 0.1))

func _clear(shapes: Array, centre: Vector2, roads: Array, taken: Array, wet_lines: Array, builder: RefCounted) -> bool:
	for poly in shapes:
		var low := INF
		var high := -INF
		for i in poly.size():
			var p: Vector2 = poly[i]
			var q: Vector2 = poly[(i + 1) % poly.size()]
			for t in [0.0, 0.5]:
				var m := p.lerp(q, t)
				if not Index.contains(centre, m): return _reject("outside")
				if bool(builder.open_water(m)): return _reject("water")
				for line in wet_lines:
					if m.distance_to(Geometry2D.get_closest_point_to_segment(m, line[0], line[1])) < float(line[2]): return _reject("river")
				var height := float(builder.surface_height(m))
				low = minf(low, height); high = maxf(high, height)
			for other in taken:
				if Placement.distance_to_polygon(p, q, other) < WORK_GAP: return _reject("lot")
		if high - low > 12.0: return _reject("relief")
		for road in roads:
			var clearance := float(road.get("widths", [5.0])[0]) + Sidewalks.width(road) + ROAD_GAP - 0.01
			if Placement.distance_to_polygon(road.a, road.b, poly) < clearance: return _reject("road")
	return true

func _reject(reason: String) -> bool:
	rejects[reason] = int(rejects.get(reason, 0)) + 1
	return false

## The finished layout, measured: each work's clearance from every road's paved edge and
## footway, and from every other thing standing on its tile.
func _audit(model: Dictionary) -> void:
	var key_for: Callable = preload("res://scripts/supply_chain_3d/world_builder.gd").standing_key
	for s in model.standing:
		if not turns.has(str(s.iid)): continue
		var shapes := Footprints.rendered(str(key_for.call(s)), s)
		var road_gap := INF
		for road in model.roads:
			if not Index.contains(model.tiles[str(s.tile)].center, road.a): continue
			if str(road.get("source", "")) == "access:" + str(s.iid): continue
			var edge := float(road.get("widths", [5.0])[0]) + Sidewalks.width(road)
			for poly in shapes: road_gap = minf(road_gap, Placement.distance_to_polygon(road.a, road.b, poly) - edge)
		var clashes: Array = []
		for other in model.standing:
			if other == s or str(other.tile) != str(s.tile) or str(other.kind) == "pylon": continue
			for mine in shapes:
				for theirs in Footprints.rendered(str(key_for.call(other)), other):
					if not Geometry2D.intersect_polygons(mine, theirs).is_empty(): clashes.append("%s:%s" % [other.kind, other.iid])
		print("[AUDIT] ", s.iid, " yaw=", rad_to_deg(float(s.get("yaw", 0.0))), " road_gap=", snappedf(road_gap, 0.1), " access=", s.has("entrance"), " overlaps=", clashes)

## Make room as a player would: buy the NPC works that stand on the tile (their land comes with
## them) and demolish them. Town houses are not land in the sim; the 3D layout refits them.
func _clear_room(tile: String) -> void:
	var need := 0.0
	for work in TILE_WORKS:
		need += float(Catalog.get_building(work[0]).get("tile_size_used", 1.0)) * BuildingLevels.mult("size", 3)
	var removing: Array = []
	var free := BuildingState.max_tile_land(tile) - BuildingState.get_tile_space_used(tile)
	for instance in BuildingState.get_buildings_on_tile(tile):
		if free >= need: break
		# Only works make way: the port, rail hub and other infrastructure stay.
		if BuildingState.is_player_owned(instance) or str(Catalog.get_building(str(instance.building_id)).get("building_category", "")) == "infrastructure": continue
		removing.append(instance)
		free += BuildingState.space_used(instance)
	if free < need: print("[CLEAR] ", tile, " cannot hold all the works: ", free, " land free after clearing its works, ", need, " needed")
	for instance in removing:
		var iid := str(instance.instance_id)
		var price := Construction.market_value(str(instance.building_id))
		MatchState.deduct_money(price)
		BuildingState.set_building_owner(iid, MatchState.LOCAL_PLAYER)
		var started: Dictionary = BuildingWorks.start_demolish(iid)
		print("[CLEAR] bought ", instance.building_id, " ", iid, " level=", instance.get("level", 1), " for ", snappedf(price, 1.0), " demolish=", started)
	while not BuildingWorks.demolish_queue.is_empty():
		BuildingWorks.tick_demolish()
	print("[CLEAR] ", tile, " used=", BuildingState.get_tile_space_used(tile), " owned=", BuildingState.get_tile_land_owned(tile), " need=", need)

## Build each work the way the construct flow does: the recipe chosen, level 3, the land it needs
## bought on the way, its kit on the tile, then the project finished as the turn would finish it.
func _build_works(main: Node, tile: String) -> void:
	MatchState.money = maxf(MatchState.money, 1.0e7)
	_clear_room(tile)
	for work in TILE_WORKS:
		var internal := str(Catalog.get_building(work[0]).get("internal_name", ""))
		var gate := BuildingLevels.research_gate(internal, 3)
		if gate != "" and not ResearchState.is_unlocked(gate): ResearchState.grant_unlock(gate)
		for good in Construction.requirements_for(work[0], 3):
			var short := int(Construction.requirements_for(work[0], 3)[good]) - Stockpile.get_at_tile(tile, good)
			if short > 0: Stockpile.add(tile, good, short)
		var before: Array = Construction.projects_on_tile(tile).map(func(p: Dictionary) -> String: return str(p.instance_id))
		BuildMode.current_building_id = work[0]
		BuildMode.current_recipe_id = work[1]
		BuildMode.attempt_level = 3
		BuildMode.attempt_buy_land = true
		main.call("_on_build_attempted", work[0], tile)
		BuildMode.attempt_buy_land = false
		BuildMode.attempt_level = 1
		var started: Array = Construction.projects_on_tile(tile).filter(func(p: Dictionary) -> bool: return not before.has(str(p.instance_id)))
		if started.is_empty():
			print("[BUILD] ", work[0], " refused on ", tile, " (placed=", BuildMode.last_attempt_placed, ")")
			continue
		var iid := str(started[0].instance_id)
		Construction._promote(iid)
		turns[iid] = deg_to_rad(float(work[2]))
		print("[BUILD] ", work[0], " -> ", iid, " level=", BuildingState.buildings.get(iid, {}).get("level", "?"), " turn=", work[2],
			" land owned=", BuildingState.get_tile_land_owned(tile))
