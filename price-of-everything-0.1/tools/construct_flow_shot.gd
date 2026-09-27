extends Node
## Captures of every stage and state of the construct flow (docs/construct-ds2-plan.md §1.2, §2):
## the catalogue (open, a building opened, a category, a search, a goods filter, locked to a tile,
## short of cash), settings, the confirm for a factory, short of land, short of cash, a power plant,
## a battery, infrastructure, no site yet, the map pick after it, and the old confirm. Each stage is
## paged top to bottom. Needs a window:
##   <godot> --path . res://tools/construct_flow_shot.tscn --quit-after 8000 -- --no-telemetry
## Writes cf_<nn>_<name>.png (panel crops) and full_<name>.png (whole screen, half size) into
## $CONSTRUCT_SHOT_DIR (or the user data folder).

var _wm: Node
var _dir := ""
var _panel: Control
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("CONSTRUCT_SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir()
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	var hud: Node = _wm.get_node("UILayer/HUD")
	_panel = hud.get("construct_panel_v2")
	print("[CF] viewport ", get_viewport().get_visible_rect().size, " money ", MatchState.money)
	MatchState.money = 50000.0

	# 1. Browse from the bottom menu.
	hud.call("_on_construct_pressed")
	await _settle(12)
	_full("browse_open")
	await _pages("browse")

	# 2. A building expanded to its recipes.
	_panel.call("_on_building_pressed", "b_002")
	await _settle(10)
	await _pages("browse_expanded")
	_panel.call("_on_building_pressed", "b_002")
	await _settle(4)

	# 3. A category filter, then a search.
	_panel.call("_on_filter_toggled", true, "power")
	await _settle(8)
	await _pages("browse_filter_power")
	_panel.call("_on_filter_toggled", false, "power")
	_panel.call("_on_search_changed", "steel")
	await _settle(8)
	_shot("browse_search_steel")
	_panel.call("_on_search_changed", "")
	await _settle(4)

	# 4. Settings.
	_panel.call("_on_settings_pressed")
	await _settle(8)
	await _pages("settings")

	# 5. Output good filter (the goods graph / encyclopedia route).
	var steel_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	if steel_id != "":
		_panel.call("open_for_output_good", steel_id)
		await _settle(10)
		_shot("browse_output_good_steel")

	# 6. Locked to a tile (the tile view's Build key).
	var td: Dictionary = _wm.call("_tile_data_by_id", "tile_5_10")
	_panel.call("open_for_tile", "tile_5_10", td)
	await _settle(12)
	_full("browse_locked_tile")
	await _pages("browse_locked_tile")

	# 7. Confirm for a factory on that tile (v3 confirm), paged top to bottom.
	_panel.call("_on_recipe_pressed", "b_002", "r_005")
	await _settle(16)
	_full("confirm_factory")
	await _pages("confirm_factory")

	# 8. Land short on the same tile.
	var owned_before: int = int(BuildingState.tile_land_owned.get("tile_5_10", 0))
	BuildingState.tile_land_owned["tile_5_10"] = 0
	_panel.call("_on_back_to_browse")
	_panel.set("_locked_tile_id", "tile_5_10")
	_panel.call("_on_recipe_pressed", "b_002", "r_005")
	await _settle(16)
	await _pages("confirm_land_short")
	BuildingState.tile_land_owned["tile_5_10"] = owned_before

	# 9. Not enough cash: the recipe click toasts; the confirm (reached with cash) then short.
	MatchState.money = 20.0
	_panel.call("_on_back_to_browse")
	_panel.set("_locked_tile_id", "tile_5_10")
	await _settle(6)
	await _pages("browse_poor")
	_panel.call("_on_recipe_pressed", "b_002", "r_005")
	await _settle(10)
	_full("recipe_click_poor_toast")
	MatchState.money = 50000.0
	_panel.call("_on_recipe_pressed", "b_002", "r_005")
	await _settle(10)
	MatchState.money = 20.0
	_panel.call("_render")
	await _settle(10)
	await _pages("confirm_poor")
	MatchState.money = 50000.0

	# 10. A power plant (solar) and a battery on the tile.
	for bid in ["b_024", "b_028"]:
		var rid := ""
		for r in Catalog.all_recipes():
			if str(r.get("building_id", "")) == bid:
				rid = str(r.get("recipe_id", ""))
				break
		if rid == "":
			continue
		_panel.call("_on_back_to_browse")
		_panel.set("_locked_tile_id", "tile_5_10")
		_panel.call("_on_recipe_pressed", bid, rid)
		await _settle(14)
		await _pages("confirm_" + bid)

	# 11. Infrastructure (cables, roads).
	for bid in ["b_006", "b_005"]:
		_panel.call("_on_back_to_browse")
		_panel.set("_locked_tile_id", "tile_5_10")
		_panel.call("_on_infrastructure_selected", bid)
		await _settle(12)
		await _pages("confirm_infra_" + bid)

	# 12. No tile: the bottom-menu route to confirm, then Confirm into the map pick.
	_panel.call("open_browser")
	await _settle(8)
	_panel.call("_on_recipe_pressed", "b_002", "r_005")
	await _settle(14)
	await _pages("confirm_no_tile")
	_panel.call("_on_confirm_pressed")
	await _settle(20)
	_full("after_confirm_no_tile")
	var bm := get_node_or_null("/root/BuildMode")
	print("[CF] build mode node=", bm != null, " ", (str(bm.get("active")) if bm != null else ""))

	# 13. The v2 confirm for comparison.
	UiPrefs.set_use_construct_panel_v3(false)
	_panel.call("open_for_tile", "tile_5_10", td)
	_panel.call("_on_recipe_pressed", "b_002", "r_005")
	await _settle(14)
	await _pages("confirm_v2_factory")
	UiPrefs.set_use_construct_panel_v3(true)

	print("[CF] done, ", _n, " captures")
	get_tree().quit(0)


func _pages(name: String) -> void:
	# The panel's own body scroll, not the category chips' strip above it.
	var sc := _panel.get("_scroll") as ScrollContainer
	if sc == null:
		_shot(name)
		return
	sc.scroll_vertical = 0
	await _settle(4)
	var bar := sc.get_v_scroll_bar()
	var maxv := int(bar.max_value - bar.page)
	var step := int(sc.size.y * 0.85)
	var y := 0
	var p := 0
	while true:
		sc.scroll_vertical = y
		await _settle(4)
		_shot("%s_p%d" % [name, p])
		p += 1
		if y >= maxv or p >= 8:
			break
		y = mini(y + step, maxv)
	print("[CF] %s: %d pages, content %d px, view %d px" % [name, p, int(bar.max_value), int(sc.size.y)])
	sc.scroll_vertical = 0


func _shot(name: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var g := _panel.get_global_rect().grow(8)
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	_n += 1
	var path := _dir.path_join("cf_%02d_%s.png" % [_n, name])
	img.get_region(r).save_png(path)
	print("[CF] ", path, "  panel ", _panel.get_global_rect())


func _full(name: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	img.resize(img.get_width() / 2, img.get_height() / 2)
	img.save_png(_dir.path_join("full_%s.png" % name))


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
