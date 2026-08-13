extends Node2D
## Non-saving Phase-C oracle. Representative gameplay-sized hypothetical
## footprints consume whole draw-only sites while the surrounding accepted
## decorative masses and MatchState remain untouched.

class ProbeOverlay:
	extends Node2D
	var poly := PackedVector2Array()
	func _draw() -> void:
		if poly.size() < 3:
			return
		draw_colored_polygon(poly, Color("b85b43a8"))
		draw_polyline(poly, Color("3e3028"), 2.4, true)
		draw_line(poly[0], poly[2], Color("f1dfb8"), 1.2, true)
		draw_line(poly[1], poly[3], Color("f1dfb8"), 1.2, true)

var _camera: Camera2D

func _ready() -> void:
	get_viewport().set_disable_input(true)
	var game := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 150:
		await get_tree().process_frame
	# Main scene setup loads the fixed prototype-world buildings. Snapshot only
	# after that legitimate initialization, then prove this probe performs no
	# placement or save-state mutation of its own.
	var buildings_before := JSON.stringify(MatchState.buildings)
	var building_count_before := MatchState.buildings.size()
	var ui := game.get_node_or_null("UILayer") as CanvasLayer
	if ui != null:
		ui.visible = false
	var grid := game.find_child("HexGridOverlay", true, false) as CanvasItem
	if grid != null:
		grid.visible = false
	_camera = get_viewport().get_camera_2d()
	_camera.set_process(false)
	_camera.set_physics_process(false)
	MapStyle.set_midcentury(true)
	for _i in 30:
		await get_tree().process_frame
	var fabric := game.get_node("UrbanFabricVisuals") as UrbanFabricVisuals
	var snapshot := fabric.accommodation_planning_snapshot()
	var selected := _representative_sites(snapshot.sites)
	var errors := PackedStringArray()
	if selected.size() < 3:
		errors.append("fewer than three representative accommodation uses")
	var overlays: Array[ProbeOverlay] = []
	var cases: Array = []
	for i in selected.size():
		var site: Dictionary = selected[i]
		var footprint := {"poly": (site.poly as PackedVector2Array).duplicate()}
		var result := AccommodationSitePlanner.yield_for_hypothetical_footprints(
			snapshot.sites, [footprint], snapshot.decorative_masses)
		if int(result.removed_site_count) < 1:
			errors.append("case %d did not yield a reservation" % (i + 1))
		for key in ["releasable_fragment_count",
				"retained_site_hypothetical_overlap_count",
				"hypothetical_decorative_mass_overlap_count"]:
			if int(result[key]) != 0:
				errors.append("case %d %s=%s" % [i + 1, key, result[key]])
		if int(result.surrounding_mass_count_before) != int(
				result.surrounding_mass_count_after):
			errors.append("case %d changed surrounding mass count" % (i + 1))
		cases.append({
			"site_key": str(site.key),
			"tile_id": str(site.tile_id),
			"visual_use": str(site.visual_use),
			"size_class": str(site.size_class),
			"result": _result_metrics(result),
		})
		var overlay := ProbeOverlay.new()
		overlay.poly = site.poly
		overlay.z_index = 100
		overlay.visible = false
		add_child(overlay)
		overlays.append(overlay)
	for i in overlays.size():
		(overlays[i] as ProbeOverlay).visible = true
		(overlays[i] as ProbeOverlay).queue_redraw()
		await _capture((selected[i] as Dictionary).center,
			"/tmp/poe_accommodation_hypothetical_%d.png" % (i + 1))
		(overlays[i] as ProbeOverlay).visible = false
	var signature_on := _site_signature(snapshot.sites)
	MapStyle.set_midcentury(false)
	for _i in 8:
		await get_tree().process_frame
	var snapshot_off := fabric.accommodation_planning_snapshot()
	var signature_off := _site_signature(snapshot_off.sites)
	if signature_on != signature_off:
		errors.append("planning snapshot changed when mid-century style was disabled")
	if buildings_before != JSON.stringify(MatchState.buildings) or \
			building_count_before != MatchState.buildings.size():
		errors.append("non-saving probe mutated MatchState buildings")
	var record := {
		"site_count": (snapshot.sites as Array).size(),
		"representative_cases": cases,
		"style_on_signature": signature_on,
		"style_off_signature": signature_off,
		"style_independent": signature_on == signature_off,
		"match_state_unchanged": buildings_before == JSON.stringify(MatchState.buildings),
		"errors": Array(errors),
	}
	var file := FileAccess.open("/tmp/poe_accommodation_probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "  "))
	file.close()
	print("[ACCOMMODATION PROBE] wrote /tmp/poe_accommodation_probe.json")
	if not errors.is_empty():
		push_error("accommodation_site_probe: %s" % "; ".join(errors))
	game.queue_free()
	for _i in 4:
		await get_tree().process_frame
	get_tree().quit(0 if errors.is_empty() else 2)

func _representative_sites(sites: Array) -> Array:
	var wanted := ["releasable_park", "releasable_yard", "industrial_growth"]
	var selected: Array = []
	var used_tiles: Dictionary = {}
	for use_value in wanted:
		var use := str(use_value)
		var best: Dictionary = {}
		for site_value in sites:
			var site: Dictionary = site_value
			if str(site.visual_use) != use or used_tiles.has(str(site.tile_id)):
				continue
			if best.is_empty() or _size_rank(str(site.size_class)) > \
					_size_rank(str(best.size_class)) or (
					_size_rank(str(site.size_class)) == _size_rank(str(best.size_class))
					and str(site.key) < str(best.key)):
				best = site
		if not best.is_empty():
			selected.append(best)
			used_tiles[str(best.tile_id)] = true
	return selected

func _size_rank(size_class: String) -> int:
	return {"small": 0, "medium": 1, "large": 2}.get(size_class, -1)

func _result_metrics(result: Dictionary) -> Dictionary:
	return {
		"removed_site_count": int(result.removed_site_count),
		"retained_site_count": int(result.retained_site_count),
		"releasable_fragment_count": int(result.releasable_fragment_count),
		"retained_site_hypothetical_overlap_count": int(
			result.retained_site_hypothetical_overlap_count),
		"hypothetical_decorative_mass_overlap_count": int(
			result.hypothetical_decorative_mass_overlap_count),
		"surrounding_mass_count_before": int(result.surrounding_mass_count_before),
		"surrounding_mass_count_after": int(result.surrounding_mass_count_after),
	}

func _site_signature(sites: Array) -> String:
	var keys := PackedStringArray()
	for site_value in sites:
		var site: Dictionary = site_value
		keys.append("%s|%s|%s|%s" % [site.key, site.tile_id,
			site.size_class, site.visual_use])
	keys.sort()
	return "\n".join(keys).sha256_text()

func _capture(position: Vector2, path: String) -> void:
	_camera.position = position
	_camera.zoom = Vector2(2.15, 2.15)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	for _i in 18:
		await get_tree().process_frame
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var size := Vector2i(mini(640, image.get_width()), mini(480, image.get_height()))
	var origin := Vector2i((image.get_width() - size.x) / 2,
		(image.get_height() - size.y) / 2)
	image.get_region(Rect2i(origin, size)).save_png(path)
	print("[ACCOMMODATION PROBE] captured %s" % path)
