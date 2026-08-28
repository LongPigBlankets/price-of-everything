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
				var spur: PackedVector2Array = route[key]
				var bad := 0
				var first := ""
				for k in 200:
					var at: Array = ships.call("_along", spur, float(route[key + "_len"]),
						float(route[key + "_len"]) * float(k) / 200.0)
					var cell := nav.cell_of(at[0] as Vector2)
					if nav.water(cell.x, cell.y) == 0:
						bad += 1
						if first == "":
							first = "%.0f,%.0f" % [(at[0] as Vector2).x, (at[0] as Vector2).y]
				print("[BERTH]   route %d %s: %d/200 ON LAND %s"
					% [ri, key, bad, first])
	print("[BERTH] done")
	get_tree().quit(0)
