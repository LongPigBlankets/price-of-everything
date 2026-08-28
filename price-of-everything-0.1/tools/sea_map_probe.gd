extends Node2D
## Diagnostic: print a coarse ASCII land/water map with world bounds, so shipping lanes can be
## placed on water that is actually there instead of on a guess.
##   <godot> --path . res://tools/sea_map_probe.tscn --quit-after 4000

const ShotHarness := preload("res://tools/shot_harness.gd")

const COLS := 78
const ROWS := 30


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 240.0)
	var wm: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(wm)
	for _i in 170:
		await get_tree().process_frame
	var terrain: TileMapLayer = wm.get_node("%TerrainLayer")
	var nav := NavGrid.instance()
	if not nav.is_ready():
		push_error("sea_map_probe: NavGrid not ready")
		get_tree().quit(1)
		return

	# World extent from the tiles themselves, not from the camera limits (which are stale).
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for coord in terrain.tiles:
		var p: Vector2 = terrain.map_to_local(terrain.map_coord_for_tile_coord(coord as Vector2i))
		lo = lo.min(p)
		hi = hi.max(p)
	print("[SEA] world bounds  x %.0f..%.0f   y %.0f..%.0f   (%.0f x %.0f)"
		% [lo.x, hi.x, lo.y, hi.y, hi.x - lo.x, hi.y - lo.y])
	print("[SEA] '.' = water, '#' = land. Columns are x, rows are y (south is DOWN).")

	for r in ROWS:
		var line := ""
		for c in COLS:
			var world := Vector2(
				lerpf(lo.x, hi.x, float(c) / float(COLS - 1)),
				lerpf(lo.y, hi.y, float(r) / float(ROWS - 1)))
			var cell := nav.cell_of(world)
			line += "." if nav.water(cell.x, cell.y) != 0 else "#"
		print("[SEA] %2d %s" % [r, line])
	# LANE CHECK: sample the real lanes the ship layer will use and report any point that
	# lands on ground. A decorative lane still has to be at sea.
	var ships := wm.find_child("PortShipVisuals", true, false)
	if ships != null:
		for _i in 5:
			await get_tree().process_frame
		var lanes: Variant = ships.get("_lanes")
		if lanes is Array:
			for li in (lanes as Array).size():
				var lane: Dictionary = (lanes as Array)[li]
				var pts: PackedVector2Array = lane["points"]
				var total: float = lane["length"]
				var bad := 0
				var worst := ""
				var samples := 240
				for k in samples:
					var at: Array = ships.call("_along", pts, total, total * float(k) / float(samples))
					var pos: Vector2 = at[0]
					var cell := nav.cell_of(pos)
					if nav.water(cell.x, cell.y) == 0:
						bad += 1
						if worst == "":
							worst = "%.0f,%.0f" % [pos.x, pos.y]
				print("[SEA] lane %d: length %.0f, %d/%d samples ON LAND%s"
					% [li, total, bad, samples, "" if worst == "" else "  first at " + worst])
	print("[SEA] done")
	get_tree().quit(0)
