extends Node2D
## Diagnostic: what berths does the ship layer actually have, and is each one's water real?
##   <godot> --headless --path . res://tools/berth_probe.tscn --quit-after 600

const ShotHarness := preload("res://tools/shot_harness.gd")


func _ready() -> void:
	ShotHarness.prepare_window(get_window())
	ShotHarness.arm_watchdog(self, 300.0)
	var wm: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(wm)
	for _i in 200:
		await get_tree().process_frame
	var ports: Node = wm.find_child("PortVisuals", true, false)
	if ports != null:
		var plans: Variant = ports.get("_midcentury_plans")
		if plans is Array:
			print("[BERTH] harbour plans: %d" % (plans as Array).size())
			for plan_value in (plans as Array):
				var plan: Dictionary = plan_value
				print("[BERTH]   tile %s valid=%s basin=%d left=%d right=%d" % [
					str(plan.get("tile_id", "?")), str(plan.get("valid", false)),
					(plan.get("basin_polygon", PackedVector2Array()) as PackedVector2Array).size(),
					(plan.get("left_arm_polygons", []) as Array).size(),
					(plan.get("right_arm_polygons", []) as Array).size()])
	var ships: Node = wm.find_child("PortShipVisuals", true, false)
	if ships == null:
		print("[BERTH] no PortShipVisuals")
		get_tree().quit(1)
		return
	var berths: Variant = ships.get("_berths")
	if berths is Array:
		print("[BERTH] berths: %d" % (berths as Array).size())
		for b_value in (berths as Array):
			var b: Dictionary = b_value
			print("[BERTH]   tile %s at %.0f,%.0f  len %.1f  clear %.1f  away %.1f" % [
				str(b.get("tile_id", "?")), (b["berth"] as Vector2).x, (b["berth"] as Vector2).y,
				float(b["length"]), float(b["clear"]), float(b["away"])])
	# How long the sea grid costs to build -- it runs once on a load frame, so it has to be
	# a hitch nobody notices rather than a stall.
	var t0 := Time.get_ticks_msec()
	ships.set("_sea_navigable", PackedByteArray())
	ships.call("_build_sea_grid", ships.get("_world_lo"), ships.get("_world_hi"))
	print("[BERTH] sea grid: %d x %d cells, built in %d ms"
		% [ships.get("_sea_cols"), ships.get("_sea_rows"), Time.get_ticks_msec() - t0])
	var callers: Variant = ships.get("_callers")
	if callers is Array:
		print("[BERTH] caller routes: %d" % (callers as Array).size())
		var nav := NavGrid.instance()
		for ri in (callers as Array).size():
			var route: Dictionary = (callers as Array)[ri]
			for key in ["spur_in", "spur_out"]:
				var track: Dictionary = route[key + "_track"]
				var bad := 0
				var first := ""
				for k in 200:
					var at: Array = ships.call("_at_time", track,
						float(track["duration"]) * float(k) / 200.0)
					var cell := nav.cell_of(at[0] as Vector2)
					if nav.water(cell.x, cell.y) == 0:
						bad += 1
						if first == "":
							first = "%.0f,%.0f" % [(at[0] as Vector2).x, (at[0] as Vector2).y]
				print("[BERTH]   route %d %s: %d/200 ON LAND %s"
					% [ri, key, bad, first])
			print("[BERTH]   route %d tile %s window %.1f period %.1f laps %d arrivals %s"
				% [ri, str((route["berth"] as Dictionary).get("tile_id", "?")),
					float(route["window"]), float(route["period"]), int(route["laps"]),
					str(route["arrivals"])])
	# DO THE APPROACHES CROSS? A ship leaving a harbour must not cut across one arriving at
	# it, which is a question about the two spur polylines of the SAME route and about the
	# in-spur of one route against the out-spur of the other at the same tile.
	if callers is Array:
		var by_tile: Dictionary = {}
		for route_value in (callers as Array):
			var route: Dictionary = route_value
			var tile := str((route["berth"] as Dictionary).get("tile_id", "?"))
			if not by_tile.has(tile):
				by_tile[tile] = []
			(by_tile[tile] as Array).append(route)
		for tile in by_tile:
			var routes: Array = by_tile[tile]
			# SAME ROUTE is the one that matters: a ship leaving by the way it came in. Two
			# routes of OPPOSITE directions must meet somewhere near the harbour mouth --
			# inbound from the north and outbound to the south share one entrance -- so
			# counting those together said "18 crossings" about geometry that is correct.
			var same := 0
			var cross := 0
			var where := ""
			for a in routes:
				for b in routes:
					var ra: Dictionary = a
					var rb: Dictionary = b
					var pa: PackedVector2Array = ra["spur_in"]
					var pb: PackedVector2Array = rb["spur_out"]
					var hits := 0
					for i in range(1, pa.size()):
						for j in range(1, pb.size()):
							var hit: Variant = Geometry2D.segment_intersects_segment(
								pa[i - 1], pa[i], pb[j - 1], pb[j])
							if hit != null:
								hits += 1
								if where == "":
									where = "%.0f,%.0f" % [(hit as Vector2).x, (hit as Vector2).y]
					if ra.get("lane_track") == rb.get("lane_track"):
						same += hits
					else:
						cross += hits
			print("[BERTH] %s: same-route crossings = %d (opposite-direction = %d) %s"
				% [tile, same, cross, where])
	var total_ships := 0
	if callers is Array:
		for route_value in (callers as Array):
			var route: Dictionary = route_value
			total_ships += int(route["laps"]) * (route["arrivals"] as Array).size()
	print("[BERTH] caller ships: %d (plus %d in the stream)"
		% [total_ships, 2 * ships.LANE_SHIPS])
	print("[BERTH] done")
	get_tree().quit(0)
