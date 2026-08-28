extends Node2D
## Diagnostic: does each bird course actually pass over a port tile, and how close?
## Aiming a skein by eye put three of them nowhere near the harbours; this measures it.
##   <godot> --headless --path . res://tools/bird_course_probe.tscn --quit-after 600

const ShotHarness := preload("res://tools/shot_harness.gd")
const BirdVisuals := preload("res://scripts/bird_visuals.gd")

const PORT_TILES := ["tile_11_17", "tile_22_16", "tile_24_7"]


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 300.0)
	var wm: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(wm)
	for _i in 200:
		await get_tree().process_frame
	var terrain: TileMapLayer = wm.get_node("%TerrainLayer")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ports: Dictionary = {}
	for coord in terrain.tiles:
		var world: Vector2 = terrain.map_to_local(
			terrain.map_coord_for_tile_coord(coord as Vector2i))
		lo = lo.min(world)
		hi = hi.max(world)
	# Harbour positions from the ship layer's own berths -- the same geometry the ships use,
	# so the answer is about where the player actually looks.
	var ships: Node = wm.find_child("PortShipVisuals", true, false)
	for berth_value in (ships.get("_berths") as Array):
		var berth: Dictionary = berth_value
		ports[str(berth.get("tile_id", ""))] = berth["berth"]
	print("[BIRD] world %.0f,%.0f .. %.0f,%.0f" % [lo.x, lo.y, hi.x, hi.y])
	for tid in PORT_TILES:
		if ports.has(tid):
			var w: Vector2 = ports[tid]
			print("[BIRD] port %s at %.0f,%.0f  = frac %.2f,%.2f"
				% [tid, w.x, w.y, (w.x - lo.x) / (hi.x - lo.x), (w.y - lo.y) / (hi.y - lo.y)])
	var birds: Node = wm.find_child("BirdVisuals", true, false)
	for s in BirdVisuals.SETS:
		var course: Vector3 = BirdVisuals.COURSES[s]
		var start := Vector2(lerpf(lo.x, hi.x, course.x), lerpf(lo.y, hi.y, course.y))
		var line := "[BIRD] set %d:" % s
		for tid in PORT_TILES:
			if not ports.has(tid):
				continue
			var best := INF
			var best_u := 0.0
			for k in 401:
				var u := float(k) / 400.0
				var at := start + Vector2.RIGHT.rotated(course.z) * BirdVisuals.RUN * u
				var gap: float = at.distance_to(ports[tid] as Vector2)
				if gap < best:
					best = gap
					best_u = u
			line += "  %s %.0fu@u=%.2f" % [tid, best, best_u]
		print(line)
	print("[BIRD] done")
	get_tree().quit(0)
