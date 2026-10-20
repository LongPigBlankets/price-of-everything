extends "res://tools/supply_chain_3d/capture.gd"
## The supply chain view's look, side by side on one company town: as painted, the ink and paper
## print, and the print with decorative scenery calmed. Daylight and evening, at three zooms, and
## the time to draw a medium frame for each look.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/print_look_ab.tscn -- \
##   --continent-review --no-telemetry --trial-output=<dir> [--own-furnace=<tile>]
## --own-furnace: the company buys the NPC furnace on that tile first, at level III, making steel.
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const RoadPlacement := preload("res://scripts/supply_chain_3d/road_placement.gd")
const LOOKS := {"painted": [false, false], "print": [true, false], "calm": [true, true]}
var output := ""
var report := {}
var _town := ""
var _own_furnace := ""
var _looks := PackedStringArray(["painted", "print", "calm"])

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--trial-output="): output = arg.trim_prefix("--trial-output=")
		if arg.begins_with("--own-furnace="): _own_furnace = arg.trim_prefix("--own-furnace=")
		if arg.begins_with("--looks="): _looks = arg.trim_prefix("--looks=").split(",")
		if arg == "--no-clearance": preload("res://scripts/supply_chain_3d/building_clearance.gd").enabled = false
	DirAccess.make_dir_recursive_absolute(output)
	# The first build is the look as painted, so the calming starts off.
	Board.print_look = false
	Board.calm_scenery = false
	await super._ready()

func _open_supply_view(view: Control) -> void:
	if _own_furnace != "":
		for iid in BuildingState.buildings:
			var live: Dictionary = BuildingState.buildings[iid]
			if str(live.get("tile_id", "")) != _own_furnace or str(live.get("building_id", "")) != "b_002": continue
			if BuildingState.is_player_owned(live): continue
			BuildingState.set_building_owner(str(iid), MatchState.LOCAL_PLAYER)
			live.level = 3
			live.recipe_id = "r_003"
			report.owned_furnace = str(iid)
			break
	await super._open_supply_view(view)

func _settle(board: Control, seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until or bool(board.get("_building")) or not bool(board.call("detail_ready")):
		RenderingServer.force_draw(false); await get_tree().process_frame
		if Time.get_ticks_msec() > until + 90000: break

## The company tile with the most homes and works on it, NPC works counting most.
func _busiest_tile(board: Control) -> String:
	var score := {}
	for pair in board._builder.sprite_pairs:
		if not pair.get("standing") is Dictionary: continue
		var kind := str(pair.standing.kind)
		var tid := str(pair.get("tile", ""))
		var npc: bool = float(pair.get("role", 0.0)) == board._builder.ROLE_NPC
		score[tid] = int(score.get(tid, 0)) + (1 if kind == "house" else 12 if npc else 4 if kind == "building" else 0)
		if npc: report.npc_works = int(report.get("npc_works", 0)) + 1
	var best := ""
	for tid in score:
		if best == "" or int(score[tid]) > int(score[best]): best = tid
	return best

func _frame(board: Control, zoom: String) -> void:
	var camera: Dictionary = board.capture_camera()
	camera.target = board._builder.point(board._builder.tiles[_town].center)
	camera.yaw = board.Rig.HOME_YAW
	camera.pitch = board.Rig.HOME_PITCH
	camera.span = {"close": board.Rig.MIN_SIZE * 1.6, "medium": 900.0, "far": 2400.0}[zoom]
	board.restore_camera(camera)

## Frames drawn back to back, each waited out on the GPU: the whole frame, CPU and GPU.
func _frame_ms() -> float:
	for i in 10: RenderingServer.force_draw(false); RenderingServer.force_sync()
	var started := Time.get_ticks_usec()
	for i in 60: RenderingServer.force_draw(false); RenderingServer.force_sync()
	return snappedf((Time.get_ticks_usec() - started) / 60000.0, 0.01)

func _shots(board: Control, light: String, look: String, zooms: Array) -> void:
	for zoom in zooms:
		# Framed twice: a build can refit the camera after the first settle.
		_frame(board, zoom)
		await _settle(board, 1.5)
		_frame(board, zoom)
		await _settle(board, 1.0)
		board._viewport.get_texture().get_image().save_png(output.path_join("%s_%s_%s.png" % [light, zoom, look]))
		if zoom == "medium" and light == "day": report["frame_ms_" + look] = _frame_ms()
	print("[PRINT AB] ", light, " ", look, " done")

func _look(board: Control, look: String) -> void:
	var setting: Array = LOOKS[look]
	await board.set_look(setting[0], setting[1])
	await _settle(board, 3.0)

## Where a standing thing's drawn base lies on the map: a works' foundation outline, a home's footprint.
func _drawn_base(builder: RefCounted, s: Dictionary) -> Array:
	var frame: Dictionary = builder.standing_frame(s)
	var shapes: Array = []
	for shape in builder._foundation_shapes(s, str(frame.key), frame.dimension):
		var poly := PackedVector2Array()
		for q in shape: poly.append((s.pos as Vector2) + (q as Vector2).rotated(-float(s.get("yaw", 0.0))))
		shapes.append(poly)
	return shapes

## Every works whose drawn base runs onto a road or into another building, and by how much.
func _clash_report(board: Control) -> Array:
	var builder: RefCounted = board._builder
	var clashes: Array = []
	var bases := {}
	for pair in builder.sprite_pairs:
		if not pair.get("standing") is Dictionary or pair.standing.has("harbour"): continue
		if str(pair.standing.kind) == "pylon": continue
		bases[str(pair.standing.iid)] = {"s": pair.standing, "shapes": _drawn_base(builder, pair.standing), "role": float(pair.get("role", 0.0))}
	for iid in bases:
		var entry: Dictionary = bases[iid]
		var s: Dictionary = entry.s
		if str(s.kind) not in ["building", "warehouse", "suppliers", "site", "port"]: continue
		var who := "%s %s L%d (%s)" % [str(s.kind), str(s.get("internal_name", "")), int(s.get("level", 1)), "npc" if entry.role == 3.0 else "player"]
		var lot: PackedVector2Array = s.get("footprint", PackedVector2Array())
		if not lot.is_empty():
			var outside := 0.0
			for poly in entry.shapes:
				for part in Geometry2D.clip_polygons(poly, lot): outside += absf(_area(part))
			var lot_gap := INF
			for road in builder.roads:
				if road.get("tunnel", false) or _driveway(road, s): continue
				lot_gap = minf(lot_gap, RoadPlacement.distance_to_polygon(road.a, road.b, lot) - float(road.get("widths", Legacy._road_widths(int(road.get("level", 1))))[0]))
			clashes.append({"works": who, "iid": str(iid), "base_outside_lot": snappedf(outside, 1), "base_area": snappedf(absf(_area(entry.shapes[0])), 1), "lot_kerb_gap": snappedf(lot_gap, 0.1), "side": snappedf(float(s.side), 0.1), "entrance": str(s.get("entrance", "")), "pos": str(s.pos), "lot_pos": str(s.get("lot_pos", ""))})
		for road in builder.roads:
			if road.get("tunnel", false) or _driveway(road, s): continue
			var widths: Array = road.get("widths", Legacy._road_widths(int(road.get("level", 1))))
			for poly in entry.shapes:
				var distance: float = RoadPlacement.distance_to_polygon(road.a, road.b, poly)
				# Kerb to kerb: the base on the carriageway, not just over the pavement.
				if distance - float(widths[0]) < 2.0:
					clashes.append({"works": who, "iid": str(iid), "with": "road L%d" % int(road.get("level", 1)), "road": str(road.get("id", road.get("path", ""))),
						"keys": road.keys(), "kerb_gap": snappedf(distance - float(widths[0]), 0.1), "carriageway_gap": snappedf(distance - float(widths[widths.size() - 1]), 0.1),
						"a": [snappedf(road.a.x, 0.1), snappedf(road.a.y, 0.1)], "b": [snappedf(road.b.x, 0.1), snappedf(road.b.y, 0.1)]})
		for other in bases:
			if other == iid: continue
			for poly in entry.shapes:
				for theirs in bases[other].shapes:
					var area := 0.0
					for part in Geometry2D.intersect_polygons(poly, theirs):
						area += absf(_area(part))
					if area > 1.0:
						var o: Dictionary = bases[other].s
						clashes.append({"works": who, "iid": str(iid), "with": "%s %s" % [str(o.kind), str(o.get("decor_asset", o.get("internal_name", "")))], "overlap": snappedf(area, 1)})
	return clashes

## A works' own driveway ends at its entrance.
static func _driveway(road: Dictionary, s: Dictionary) -> bool:
	if not s.has("entrance"): return false
	var door: Vector2 = s.entrance
	return (road.a as Vector2).distance_to(door) < 1.5 or (road.b as Vector2).distance_to(door) < 1.5

static func _area(poly: PackedVector2Array) -> float:
	var total := 0.0
	for i in poly.size(): total += poly[i].cross(poly[(i + 1) % poly.size()])
	return total * 0.5

func _continent_review(board: Control, _home: Dictionary) -> void:
	await _settle(board, 3.0)
	if "--clash-report" in OS.get_cmdline_user_args():
		report.clashes = _clash_report(board)
		report.held_back = board.load_profile.get("buildings_held_back")
		report.clearance_ms = board.load_profile.get("clearance_ms")
		print("[CLEARANCE] held back ", report.held_back, " in ", report.clearance_ms, " ms")
		print("[CLASH] ", report.clashes.size())
		FileAccess.open(output.path_join("clashes.json"), FileAccess.WRITE).store_string(JSON.stringify(report.clashes, "\t"))
		if "--clash-only" in OS.get_cmdline_user_args(): return
	_town = _busiest_tile(board)
	report.town = _town
	report.viewport = board._viewport.size
	for look in _looks:
		await _look(board, look)
		await _shots(board, "day", look, ["close", "medium", "far"])
	await board.set_evening(true)
	await _settle(board, 3.0)
	var evening_order := _looks.duplicate()
	evening_order.reverse()
	for look in evening_order:
		await _look(board, look)
		await _shots(board, "evening", look, ["close", "medium"])
	print("[PRINT AB] ", JSON.stringify(report))
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
