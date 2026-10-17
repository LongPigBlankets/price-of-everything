extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Rail := preload("res://scripts/supply_chain_3d/railway.gd")
const Board := preload("res://scripts/supply_chain_3d/board.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")
const Reveal := preload("res://scripts/supply_chain_3d/tile_reveal.gd")

func _test_stream_ready_waits_for_infrastructure_and_detail() -> void:
	var board := Board.new()
	var builder := Builder.new()
	builder.progressive_tiles = true
	builder.loading_reveal = Reveal.new()
	builder.loading_reveal.active = true
	builder._overview = false
	builder.backdrop_pending = true
	builder.local_tiles["t"] = {}
	builder.ready_tiles["t"] = true
	board._start_tile_reveal(builder,"t")
	_check(builder.loading_reveal.elapsed.is_empty(), "Reveal waits for shared rail/infrastructure even when terrain is ready")
	builder.backdrop_pending = false
	builder.ready_tiles.clear()
	board._start_tile_reveal(builder,"t")
	_check(builder.loading_reveal.elapsed.is_empty(), "Far backdrop cannot reveal a tile without its requested local detail")
	builder.ready_tiles["t"] = true
	board._start_tile_reveal(builder,"t")
	_check(builder.loading_reveal.elapsed.has("t"), "Ready local detail starts the ink-to-colour animation")
	board.free()

func _test_rail_display_turnouts_connect_without_all_pair_fan() -> void:
	for degree in [3,4]:
		var lines := []
		for i in degree:
			var p := Vector2.RIGHT.rotated(TAU*i/degree)*300.0
			lines.append({"mode":"rails","pts":[{"p":Vector2.ZERO},{"p":p}]})
		var logical := Rail.network(lines)
		var visual := Rail.network(lines,true)
		var count := 0
		for path in visual.corridors:
			if path.has("junction"): count += 1
		_check(count == degree-1,"Rail display has one trunk and one turnout per extra arm")
		_check(logical.junctions[0].movements.size()==degree*(degree-1)/2,"Engineering retains every logical junction movement")
		var unmatched := 0
		for path in visual.paths:
			for end in [path.points[0],path.points[-1]]:
				if end.length()>290: continue # real line ends
				var gap := INF
				for other in visual.paths:
					if path==other: continue
					for j in range(1,other.points.size()):
						gap=minf(gap,end.distance_to(Geometry2D.get_closest_point_to_segment(end,other.points[j-1],other.points[j])))
				if gap>.15: unmatched+=1
		_check(unmatched==0,"Each displayed track end meets an outgoing rail or trunk without a gap")

func _test_stream_ready_reuse_rejects_changed_heights_and_topology() -> void:
	var reuse=preload("res://tools/supply_chain_3d/reuse_scenery_terrain_bakes.gd")
	_check(reuse.equivalent([Vector2(1,2),34.0,true],[Vector2(1,2),34.00001,true]),"Offline reuse tolerates only insignificant height roundoff")
	_check(not reuse.equivalent([34.0],[34.01]),"Offline reuse rejects a changed terrain height")
	_check(not reuse.equivalent([false],[true]),"Offline reuse rejects changed visibility/cutting state")
	_check(not reuse.equivalent([Vector2(1,2)],[Vector2(1.1,2)]),"Offline reuse rejects moved track geometry")
