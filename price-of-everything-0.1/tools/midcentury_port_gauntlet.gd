extends Node2D
## Port-only deterministic audit and UI-hidden normal/diagnostic capture set.

const AuthoredMapRef := preload("res://scripts/authored_map.gd")

const PORTS := [
	{"name": "stoneshore", "tile_id": "tile_5_10"},
	{"name": "arin", "tile_id": "tile_11_17"},
	{"name": "capital", "tile_id": "tile_24_7"},
	{"name": "vandel", "tile_id": "tile_22_16"},
]

var _game: Node
var _terrain: TileMapLayer
var _camera: Camera2D
var _ports: Node2D
var _buildings: Node
var _diagnostic := false
## Where captures go. `/tmp` does not exist on Windows, so the default is a path that is
## writable on every platform; `--out=<prefix>` overrides it.
var _out_prefix := "user://poe_port_"

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with("--out="):
			_out_prefix = str(argument).substr(6)
	get_viewport().set_disable_input(true)
	z_index = 1000
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	for _i in 165:
		await get_tree().process_frame
	_terrain = _game.get_node("%TerrainLayer") as TileMapLayer
	_camera = get_viewport().get_camera_2d()
	_ports = _game.find_child("PortVisuals", true, false) as Node2D
	_buildings = _game.find_child("BuildingVisuals", true, false)
	var ui := _game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	var grid := _game.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	_camera.set_process(false)
	_camera.set_physics_process(false)
	if "edge_pan_enabled" in _camera:
		_camera.set("edge_pan_enabled", false)
	MapStyle.set_midcentury(true)
	for _i in 24:
		await get_tree().process_frame
	var plans: Array = _ports.midcentury_plans()
	var by_tile: Dictionary = {}
	for plan_value in plans:
		var plan: Dictionary = plan_value
		by_tile[str(plan.tile_id)] = plan
	var audits: Array = []
	var failures: Array[String] = []
	for spec_value in PORTS:
		var spec: Dictionary = spec_value
		var plan: Dictionary = by_tile.get(str(spec.tile_id), {})
		if plan.is_empty():
			failures.append("%s has no valid plan" % str(spec.tile_id))
			continue
		await _capture(plan.position, 1.42,
			"%s%s.png" % [_out_prefix, str(spec.name)])
		_diagnostic = true
		_ports.set_diagnostic_overlay(true)
		await _capture(plan.position, 1.42,
			"%s%s_diagnostic.png" % [_out_prefix, str(spec.name)])
		_diagnostic = false
		_ports.set_diagnostic_overlay(false)
		var audit := _audit(plan)
		audits.append(audit)
		failures.append_array(_failures(audit))
	if not plans.is_empty():
		var first: Dictionary = plans[0]
		await _capture(first.position - first.seaward * 105.0, 0.78,
			"%scontext.png" % _out_prefix, Vector2i(1100, 650))
	var collision := _port_decorative_collision(plans)
	if int(collision.overlap_count) > 0:
		failures.append("%s decor overlaps port envelopes: %d mass(es), %.0f u2 %s"
			% [str(collision.get("source", "?")), int(collision.overlap_count),
				float(collision.get("overlap_area", 0.0)),
				str(collision.get("offenders", []))])
	var result := {
		"catalog_port_count": Catalog.all_ports().size(),
		"valid_plan_count": plans.size(),
		"ports": audits,
		"decorative_collision": collision,
		"failures": failures,
		"hard_gate_passes": plans.size() == 4 and failures.is_empty(),
	}
	var out := FileAccess.open("%smetrics.json" % _out_prefix, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(result, "  "))
		out.close()
	print("[PORT GAUNTLET] valid=%d/4 failures=%s" % [plans.size(), str(failures)])
	MapStyle.set_midcentury(false)
	get_tree().quit(0 if failures.is_empty() else 2)

func _draw() -> void:
	if not _diagnostic or _ports == null:
		return
	var canvas_xform := _terrain.get_global_transform()
	for plan_value in _ports.midcentury_plans():
		var plan: Dictionary = plan_value
		var basin := _transformed(plan.basin_polygon, canvas_xform)
		draw_colored_polygon(basin, Color(0.12, 0.48, 0.83, 0.20))
		draw_polyline(_closed(basin), Color("2472ae"), 2.2, true)
		var corridor := _transformed(plan.open_water_corridor, canvas_xform)
		draw_colored_polygon(corridor, Color(0.18, 0.78, 0.92, 0.16))
		draw_polyline(_closed(corridor), Color("2ca5b8"), 1.7, true)
		for poly_value in plan.land_polygons:
			draw_polyline(_closed(_transformed(poly_value, canvas_xform)),
				Color("f4c542"), 2.6, true)
		for poly_value in plan.left_arm_polygons:
			draw_polyline(_closed(_transformed(poly_value, canvas_xform)),
				Color("e05353"), 2.4, true)
		for poly_value in plan.right_arm_polygons:
			draw_polyline(_closed(_transformed(poly_value, canvas_xform)),
				Color("a34ed4"), 2.4, true)
		for poly_value in plan.river_exclusions:
			draw_polyline(_closed(_transformed(poly_value, canvas_xform)),
				Color(0.92, 0.20, 0.20, 0.82),
				2.0, true)
		var coast := _transformed(plan.coastline_samples, canvas_xform)
		for point in coast:
			draw_circle(point, 2.2, Color("f4c542"))
		var access := _transformed(plan.road_access, canvas_xform)
		if access.size() >= 2:
			draw_polyline(access, Color("f7f7f7"), 5.4, true)
			draw_polyline(access, Color("5b35d5"), 2.0, true)

func _audit(plan: Dictionary) -> Dictionary:
	var d: Dictionary = plan.diagnostics
	return {
		"tile_id": str(plan.tile_id), "valid_plan_present": bool(plan.valid),
		"basin_area": float(d.basin_area),
		"basin_sea_water_coverage": float(d.basin_sea_water_coverage),
		"open_sea_connectivity": bool(d.open_sea_connectivity),
		"open_water_corridor_coverage": float(d.open_water_corridor_coverage),
		"harbour_mouth_width": float(d.harbour_mouth_width),
		"landward_dry_land_coverage": float(d.landward_dry_land_coverage),
		"left_arm_length": float(d.left_arm_length),
		"right_arm_length": float(d.right_arm_length),
		"left_arm_water_coverage": float(d.left_arm_water_coverage),
		"right_arm_water_coverage": float(d.right_arm_water_coverage),
		"river_overlap_area": float(d.river_overlap_area),
		"basin_opaque_overlap_area": float(d.basin_opaque_overlap_area),
		"interarm_open_area": float(d.interarm_open_area),
		"interarm_sea_area": float(d.interarm_sea_area),
		"interarm_sea_coverage": float(d.interarm_sea_coverage),
		"max_arm_bend_deg": float(d.max_arm_bend_deg),
		"container_count": int(d.container_count),
		"crane_count": int(d.crane_count), "crane_arms": d.crane_arms,
		"road_access_length": float(d.road_access_length),
		"road_access_valid": bool(d.road_access_valid),
		"gameplay_overlap_area": float(d.gameplay_overlap_area),
		"plan_hash": str(plan.plan_hash),
		"planner_msec": int(d.planner_msec),
	}

func _failures(audit: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var tile := str(audit.tile_id)
	if float(audit.basin_sea_water_coverage) < 0.999:
		out.append("%s basin is not sea water" % tile)
	if not bool(audit.open_sea_connectivity) or \
			float(audit.open_water_corridor_coverage) < 0.999:
		out.append("%s lacks open-sea corridor" % tile)
	# THE HEAD IS A RECLAIMED QUAY, NOT A TRACING OF THE BEACH (owner, 2026-08-21). It is a
	# straight block that is deliberately allowed to sit over the water line at its face, so
	# the old "100% dry" assertion now describes a shape the planner no longer produces. The
	# gate that still matters is the one the planner enforces: enough of the block is real
	# ground that the quay is built on the shore rather than floating off it.
	if float(audit.landward_dry_land_coverage) < MidcenturyPortPlan.HEAD_MIN_LAND:
		out.append("%s head is mostly water (%.2f%% land)" % [tile,
			float(audit.landward_dry_land_coverage) * 100.0])
	if float(audit.river_overlap_area) > 0.01:
		out.append("%s obstructs river/channel" % tile)
	if float(audit.basin_opaque_overlap_area) > 0.01:
		out.append("%s has opaque basin overlap" % tile)
	if float(audit.gameplay_overlap_area) > 0.01:
		out.append("%s overlaps gameplay building" % tile)
	if int(audit.crane_count) != 2 or audit.crane_arms != ["left", "right"]:
		out.append("%s crane assignment invalid" % tile)
	if int(audit.container_count) < 8:
		out.append("%s lacks container activity" % tile)
	if not bool(audit.road_access_valid):
		out.append("%s lacks road access" % tile)
	# Addendum section 5. The basin gate above cannot see this: the basin polygon
	# is constructed to sit in water, while the space the viewer reads as
	# "between the arms" is bounded by the arms themselves.
	# Threshold calibrated from measurement, and the calibration is on the record.
	# v0 measured 82.92 / 83.28 / 84.94 / 90.36 % sea inside the U. The straight-
	# quay plan measures 95.08 / 95.71 / 96.86 / 97.80 %. The residual is a 6-10u
	# strip of foreshore between the apron and the water: the apron is clipped to
	# the RENDERED coastline and then eroded until the 12u NavGrid dry-land gate
	# reads 100%, and that erosion is what the strip is. Drawing the apron to the
	# coastline would close it, at the cost of putting the drawn geometry outside
	# the instrument that certifies it as dry. The gate sits below the measured
	# floor, not at it, so ordinary coastline variation cannot flip a green run.
	if float(audit.interarm_sea_coverage) < 0.94:
		out.append("%s shows land between the arms (%.2f%% sea)" % [tile,
			float(audit.interarm_sea_coverage) * 100.0])
	if float(audit.max_arm_bend_deg) > 0.01:
		out.append("%s has a kinked arm (%.2f deg)" % [tile,
			float(audit.max_arm_bend_deg)])
	return out

## Does any decorative building still stand inside a harbour envelope?
##
## THIS ASKS THE AUTHORED FABRIC, NOT THE PROCEDURAL ONE. It used to read
## `UrbanFabricVisuals.gameplay_collision_snapshot()`, but that layer is HIDDEN whenever an
## authored document is active — so on the authored map it was auditing an invisible
## generator while the decor the player could actually see went unchecked, and reported an
## overlap that had nothing to do with the ports. The procedural read is kept for maps with
## no authored document, where it is still the right source.
##
## The authored side measures real geometry: each plan's compound envelope against every mass
## the fabric layer is currently DRAWING (evicted ones are already gone from that list), so a
## pass here means nothing is standing on a quay, not merely that a counter was zero.
func _port_decorative_collision(plans: Array) -> Dictionary:
	var missing_plan_count := 0
	for plan_value in plans:
		var plan: Dictionary = plan_value
		if (plan.total_compound_envelope as PackedVector2Array).size() < 3:
			missing_plan_count += 1
	var authored := get_tree().get_first_node_in_group("authored_fabric")
	var has_authored := authored != null and authored.has_method("visible_mass_polygons")
	if has_authored and AuthoredMapRef.is_active():
		var masses: Array = authored.call("visible_mass_polygons")
		var count := 0
		var area := 0.0
		var offenders: Array[String] = []
		for plan_value in plans:
			var envelope: PackedVector2Array = (plan_value as Dictionary).total_compound_envelope
			if envelope.size() < 3:
				continue
			var envelope_bb := _poly_bb(envelope)
			for record_value in masses:
				var record: Dictionary = record_value
				if not envelope_bb.intersects(record.bb):
					continue
				var overlap := _overlap_area(envelope, record.poly as PackedVector2Array)
				if overlap <= 0.5:
					continue   # a shared edge is not an occupied quay
				count += 1
				area += overlap
				if offenders.size() < 6:
					offenders.append("%s on %s" % [str(record.id),
						str((plan_value as Dictionary).tile_id)])
		return {"source": "authored", "overlap_count": count, "overlap_area": area,
			"offenders": offenders, "missing_plan_count": missing_plan_count}
	var fabric := _game.find_child("UrbanFabricVisuals", true, false)
	if fabric == null or not fabric.has_method("gameplay_collision_snapshot"):
		return {"source": "none", "overlap_count": -1, "overlap_area": -1.0,
			"missing_plan_count": missing_plan_count}
	var guard: Dictionary = fabric.gameplay_collision_snapshot()
	return {"source": "procedural",
		"overlap_count": int(guard.get("opaque_overlap_count", -1)),
		"overlap_area": 0.0,
		"sanitized_footprint_count": int(guard.get("footprints_checked", -1)),
		"missing_plan_count": missing_plan_count}


func _poly_bb(poly: PackedVector2Array) -> Rect2:
	var bb := Rect2(poly[0], Vector2.ZERO)
	for point in poly:
		bb = bb.expand(point)
	return bb


func _capture(position: Vector2, zoom: float, path: String,
		size: Vector2i = Vector2i(960, 540)) -> void:
	_camera.position = position
	_camera.zoom = Vector2(zoom, zoom)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	for _i in 16:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var crop_size := Vector2i(mini(size.x, image.get_width()),
		mini(size.y, image.get_height()))
	var origin := Vector2i((image.get_width() - crop_size.x) / 2,
		(image.get_height() - crop_size.y) / 2)
	var err := image.get_region(Rect2i(origin, crop_size)).save_png(path)
	print("[PORT GAUNTLET] %s%s" % [path, "" if err == OK else "  !! WRITE FAILED (%d)" % err])

func _overlap_area(a: PackedVector2Array, b: PackedVector2Array) -> float:
	var area := 0.0
	for piece_value in Geometry2D.intersect_polygons(a, b):
		var piece: PackedVector2Array = piece_value
		var signed := 0.0
		for i in piece.size():
			var p := piece[i]
			var q := piece[(i + 1) % piece.size()]
			signed += p.x * q.y - q.x * p.y
		area += absf(signed) * 0.5
	return area

func _closed(poly_value: Variant) -> PackedVector2Array:
	var poly: PackedVector2Array = poly_value
	var out := poly.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out

func _transformed(poly_value: Variant, xform: Transform2D) -> PackedVector2Array:
	var poly: PackedVector2Array = poly_value
	var out := PackedVector2Array()
	for point in poly:
		out.append(xform * point)
	return out
