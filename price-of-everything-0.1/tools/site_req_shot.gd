extends Node2D
## Verification shots for the confirm screen's SITE REQUIREMENTS rows (the pipe/cable
## prerequisites a recipe needs before it can run) and for single-select build filters.
##   Godot --path . res://tools/site_req_shot.tscn --quit-after 1800
## Writes /tmp/poe_sitereq_*.png.
##
## Cases, chosen to cover every branch of _site_requirement_rows():
##   r_012 Chlor-Alkali — safe_liquid IN (pipes) + 200 energy (cables) + three
##         hazard_liquid OUT (reinf_pipes). The multi-good, multi-row worst case.
##   r_053 Industrial Glassmaking — the tutorial's own stall: hazard_liquid IN.
##   tile_2_4 carries `cables` and nothing else, so one row resolves satisfied
##         (green) while its neighbours stay unmet (gold) in the same shot.

const CHEM_PLANT := "b_012"
const FURNACE := "b_002"
const CABLED_TILE := "tile_2_4"     # infrastructure_present = cables
const BARE_TILE := "tile_5_9"       # no infrastructure at all

var _wm
var _panel: Control

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	MatchState.money = 500000.0

	_panel = _wm.find_child("ConstructPanelV2", true, false) as Control
	if _panel == null:
		print("[SITEREQ] ConstructPanelV2 not found — aborting")
		get_tree().quit(1)
		return
	print("[SITEREQ] use_construct_panel_v2=%s" % str(MatchState.use_construct_panel_v2))

	# 1) Tile-independent flow: requirements stated, no verdict, INPUT rows only.
	_panel.open_browser()
	await _settle(6)
	_panel._on_recipe_pressed(CHEM_PLANT, "r_012")
	await _settle(8)
	_report("browse/chlor-alkali")
	_shot("browse_chloralkali")

	# ... and the same screen mid-flash (delay 1.0s + 0.3s ramp → peak at ~1.3s).
	await _seconds(1.3)
	_shot("browse_chloralkali_flash")
	await _seconds(1.0)
	_shot("browse_chloralkali_after")

	# 2) Tile-locked on a cabled tile: cables satisfied, pipes unmet, and the
	#    hazard-liquid OUTPUT row appears because the site is now known.
	_open_on_tile(CABLED_TILE, CHEM_PLANT, "r_012")
	await _settle(8)
	_report("tile_2_4/chlor-alkali")
	# Sweep the flash so its true peak is measured rather than guessed at: saving a
	# 1080p PNG costs real milliseconds, so a single timed capture lands late.
	var elapsed := 0.0
	for step in 9:
		var target := 0.9 + float(step) * 0.12
		await _seconds(maxf(0.0, target - elapsed))
		elapsed = target
		_shot("flashsweep_%02d" % step)
	await _seconds(1.2)
	_shot("tile_cabled_chloralkali")

	# 3) The tutorial's own case on a bare tile: reinforced pipe + cables, both unmet.
	_open_on_tile(BARE_TILE, FURNACE, "r_053")
	await _settle(8)
	_report("tile_5_9/glassmaking")
	_shot("tile_bare_glassmaking")

	# 4) A recipe that needs nothing routed must add no rows at all.
	_open_on_tile(BARE_TILE, FURNACE, "r_054")
	await _settle(8)
	_report("tile_5_9/high-strength-glass (expect 0 rows)")
	_shot("tile_bare_hsglass")

	await _check_filters()
	get_tree().quit(0)


## Single-select: picking a second chip must replace the first, and re-clicking the
## active chip must clear the filter entirely.
func _check_filters() -> void:
	_panel.open_browser()
	await _settle(8)
	var chips := _filter_chips()
	if chips.size() < 2:
		print("[SITEREQ] filters: expected >=2 chips, found %d" % chips.size())
		return
	chips[0].button_pressed = true
	chips[0].emit_signal("toggled", true)
	await _settle(4)
	print("[SITEREQ] filters after chip A: %s" % str(_panel._active_filters.keys()))
	_shot("filters_one")
	_filter_chips()[1].emit_signal("toggled", true)
	await _settle(4)
	print("[SITEREQ] filters after chip B (expect ONLY B): %s" % str(_panel._active_filters.keys()))
	_shot("filters_switched")
	var active := _filter_chips()
	for i in active.size():
		if active[i].button_pressed:
			active[i].emit_signal("toggled", false)
			break
	await _settle(4)
	print("[SITEREQ] filters after re-click (expect empty): %s" % str(_panel._active_filters.keys()))


func _filter_chips() -> Array:
	var out: Array = []
	for c in _panel._filter_row.get_children():
		if c is Button:
			out.append(c)
	return out


func _open_on_tile(tile_id: String, building_id: String, recipe_id: String) -> void:
	var coord: Vector2i = _wm.terrain_layer.id_to_coord(tile_id)
	var tile_data: Dictionary = _wm.terrain_layer.tiles.get(coord, {})
	_panel.open_for_tile(tile_id, tile_data)
	_panel._on_recipe_pressed(building_id, recipe_id)


## Print what the panel actually built, so a wrong row set fails loudly in the log
## rather than hiding in a screenshot nobody reads closely.
func _report(label: String) -> void:
	var rows: Array = _panel._site_requirement_rows()
	print("[SITEREQ] %s — locked_tile='%s' rows=%d" % [label, _panel._locked_tile_id, rows.size()])
	for row in rows:
		for rt in _rich_labels(row):
			print("           · %s" % rt.get_parsed_text())
	# The land line is plain text, so read it straight off the built row.
	for lbl in _plain_labels(_panel._land_required_row(_panel._selected_building)):
		print("           LAND: %s" % lbl.text)


func _plain_labels(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is Label:
			out.append(c)
		out.append_array(_plain_labels(c))
	return out


func _rich_labels(root: Node) -> Array:
	var out: Array = []
	for c in root.get_children():
		if c is RichTextLabel:
			out.append(c)
		out.append_array(_rich_labels(c))
	return out


func _shot(name_part: String) -> void:
	var path := "/tmp/poe_sitereq_%s.png" % name_part
	get_viewport().get_texture().get_image().save_png(path)
	print("[SITEREQ] saved %s" % path)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
