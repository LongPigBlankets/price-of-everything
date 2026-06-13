extends Node
## Benchmarks the PRODUCTION RoadRealizer (hierarchical, corridor-local) over
## the baked navgrid — the Phase-0 harness measured the single-level prototype;
## this measures what Phase 2 actually ships. Run:
##     <godot> --headless res://tools/bench_realizer.tscn

const BANDS := [
	{"name": "local", "dist": 500.0},
	{"name": "regional", "dist": 2000.0},
	{"name": "trunk", "dist": 6500.0},
]
const JOBS_PER_BAND := 20

@onready var terrain: HexMap = %TerrainLayer

func _ready() -> void:
	await get_tree().process_frame
	var nav := NavGrid.instance()
	if not nav.is_ready():
		push_error("bench_realizer: navgrid missing — bake first")
		get_tree().quit(1)
		return
	RoadCrossings.build(terrain)
	var land: Array[Vector2] = []
	for coord in terrain.tiles:
		var t := str(terrain.tiles[coord].get("type", ""))
		if t == "rural" or t == "hill" or t == "urban":
			land.append(terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)))
	var realizer := RoadRealizer.new()
	var network := RoadNetwork.new()
	print("\n==== roads-v2 realizer benchmark (hierarchical) ====")
	for band in BANDS:
		var target: float = band.dist
		var times: Array[float] = []
		var exps: Array[int] = []
		var fails := 0
		var done := 0
		var attempt := 0
		while done < JOBS_PER_BAND and attempt < 600:
			attempt += 1
			var i := RoadHash.pick("bench|%s|%d|a" % [band.name, attempt], land.size())
			var best := -1
			var best_err := 1e30
			for j in range(0, land.size(), 3):
				var err: float = absf(land[i].distance_to(land[j]) - target)
				if err < best_err and j != i:
					best_err = err
					best = j
			if best < 0 or best_err > target * 0.4:
				continue
			var started := Time.get_ticks_usec()
			var result := realizer.route(nav, network, land[i], land[best], {
				"identity": "sparse_rural", "salt": attempt})
			var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
			done += 1
			if result.ok:
				times.append(elapsed)
				exps.append(int(result.expansions))
			else:
				fails += 1
		times.sort()
		exps.sort()
		if times.is_empty():
			print("bench_realizer: %-8s no successful jobs (fails=%d)" % [band.name, fails])
			continue
		print("bench_realizer: %-8s ok=%d/%d p50=%8.1fms p95=%8.1fms exp_p50=%7d exp_p95=%7d" % [
			band.name, times.size(), done,
			times[times.size() / 2], times[mini(int(times.size() * 0.95), times.size() - 1)],
			exps[exps.size() / 2], exps[mini(int(exps.size() * 0.95), exps.size() - 1)]])
	get_tree().quit(0)
