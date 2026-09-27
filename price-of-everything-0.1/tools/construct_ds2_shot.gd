extends Node
## Captures of the construct panel in DS2, the construction lot (`toggle construct ds2`), each cropped to the
## panel: the catalogue (whole, the Furnace opened condensed and expanded, Metallurgy picked, the goods filter),
## the settings; the build order for a Furnace's Pig Iron Smelting on Stoneshore (or CONSTRUCT_SHOT_TILE),
## at its top, its middle and its foot; the build order with no site chosen.
##   CONSTRUCT_SHOT_DIR=<dir> [CONSTRUCT_SHOT_BUILD=b_002] [CONSTRUCT_SHOT_RECIPE=r_005] \
##     <godot> --path . res://tools/construct_ds2_shot.tscn --quit-after 60000 -- --no-telemetry
## Writes ds2_<nn>_<view>.png into $CONSTRUCT_SHOT_DIR (default /tmp/poe_construct_shot). The game runs in a
## SubViewport of a fixed size, LOGICAL at two pixels each, so every capture has the same pixels whatever the
## display. Everything beside the panel is hidden for each capture (as tools/market_ds2_shot.gd does).

const LOGICAL := Vector2i(1920, 1200)

var _vp: SubViewport
var _wm: Node
var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("CONSTRUCT_SHOT_DIR")
	if _dir == "":
		_dir = "/tmp/poe_construct_shot"
	DirAccess.make_dir_recursive_absolute(_dir)
	var bid := OS.get_environment("CONSTRUCT_SHOT_BUILD")
	var rid := OS.get_environment("CONSTRUCT_SHOT_RECIPE")
	if bid == "":
		bid = "b_002"
	if rid == "":
		rid = "r_005"
	UiPrefs.set_use_construct_ds2(true)
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.set("edge_pan_enabled", false)
	MatchState.money = 50000.0
	var panel: Control = _vp.find_child("ConstructPanelV2", true, false)
	if panel == null or not (panel.get_script() as Script).resource_path.contains("construct_ds2"):
		print("[CONSTRUCT_SHOT] no DS2 construct panel")
		get_tree().quit(1)
		return
	panel.call("open_browser")
	await _settle(8)
	await _shot(panel, "catalogue")
	panel.call("expand_building", bid)
	await _settle(6)
	await _scroll_to(panel, "BuildingCard_%s" % bid)
	await _shot(panel, "catalogue_open_condensed")
	UiPrefs.set_construct_expanded_recipe_mode(true)
	panel.call("_render")
	await _settle(6)
	await _scroll_to(panel, "BuildingCard_%s" % bid)
	await _shot(panel, "catalogue_open_expanded")
	UiPrefs.set_construct_expanded_recipe_mode(false)
	panel.call("open_browser")
	panel.call("_pick_category", "metallurgy")
	await _settle(6)
	await _shot(panel, "catalogue_metallurgy")
	panel.call("open_for_output_good", "g_004")
	await _settle(6)
	await _shot(panel, "catalogue_goods_filter")
	panel.call("_on_settings_pressed")
	await _settle(6)
	await _shot(panel, "settings")
	var tile := OS.get_environment("CONSTRUCT_SHOT_TILE")
	if tile == "":
		tile = _named_tile("Stoneshore")
	var world := _vp.find_child("WorldMap", true, false)
	var td: Dictionary = world.call("_tile_data_by_id", tile) if world != null and tile != "" else {}
	print("[CONSTRUCT_SHOT] site %s (%s)" % [tile, Catalog.tile_name(tile)])
	panel.call("open_for_tile", tile, td)
	_confirm(panel, bid, rid)
	await _settle(8)
	await _shot(panel, "order_top")
	var scroll: ScrollContainer = panel.get("_scroll")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value * 0.45)
	await _settle(4)
	await _shot(panel, "order_middle")
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)
	await _settle(4)
	await _shot(panel, "order_foot")
	# Refused: too little money, then the land short with auto buy off; the Build key pressed, the blocker lit.
	scroll.scroll_vertical = 0
	var money := MatchState.money
	MatchState.money = 60.0
	panel.call("_render")
	await _settle(6)
	(panel.find_child("BuildConfirmButton", true, false) as Button).pressed.emit()
	await get_tree().create_timer(0.16).timeout
	await _shot(panel, "order_refused_money")
	MatchState.money = money
	var auto := MatchState.construct_auto_buy_land
	MatchState.set_construct_auto_buy_land(false)
	panel.call("open_for_tile", tile, td)
	_confirm(panel, bid, rid)
	await _settle(6)
	(panel.find_child("BuildConfirmButton", true, false) as Button).pressed.emit()
	await get_tree().create_timer(0.2).timeout
	await _shot(panel, "order_refused_land")
	MatchState.set_construct_auto_buy_land(auto)
	panel.call("open_browser")
	_confirm(panel, bid, rid)
	await _settle(8)
	(panel.get("_scroll") as ScrollContainer).scroll_vertical = 0
	await _settle(4)
	await _shot(panel, "order_no_site")
	print("[CONSTRUCT_SHOT] done, %s" % _dir)
	get_tree().quit(0)


func _confirm(panel: Control, bid: String, rid: String) -> void:
	panel.set("_selected_building", Catalog.get_building(bid))
	panel.set("_selected_recipe", Catalog.get_recipe(rid))
	panel.set("_view", 1)
	panel.call("_render")


## Scrolls the panel's body so the named node sits at its top.
func _scroll_to(panel: Control, node_name: String) -> void:
	var scroll: ScrollContainer = panel.get("_scroll")
	var n: Control = panel.find_child(node_name, true, false)
	if n != null:
		scroll.scroll_vertical = int(n.global_position.y - scroll.global_position.y + scroll.scroll_vertical - 8.0)
	await _settle(4)


func _named_tile(word: String) -> String:
	for t: Dictionary in Catalog.named_tiles():
		if str(t.get("name", "")).contains(word):
			return str(t.get("id", ""))
	return ""


func _shot(panel: Control, view: String) -> void:
	var hidden := _isolate(panel)
	await _settle(2)
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := Vector2(img.get_size()) / Vector2(LOGICAL)
	var g := panel.get_global_rect().grow(8)
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	_n += 1
	img.get_region(r).save_png(_dir.path_join("ds2_%02d_%s.png" % [_n, view]))
	_restore(hidden)


## Hide everything beside the panel's own line of ancestors, so the crop is the panel alone.
func _isolate(panel: Node) -> Array:
	var hidden: Array = []
	var n: Node = panel
	while n != null and n != _vp:
		var parent := n.get_parent()
		if parent == null:
			break
		for sib in parent.get_children():
			if sib == n:
				continue
			if (sib is CanvasItem and (sib as CanvasItem).visible) or (sib is CanvasLayer and (sib as CanvasLayer).visible) \
					or (sib is Window and (sib as Window).visible):
				if sib is CanvasItem and (sib as CanvasItem).is_ancestor_of(panel):
					continue
				sib.set("visible", false)
				hidden.append(sib)
		n = parent
	for layer in _vp.find_children("*", "CanvasLayer", true, false):
		var cl := layer as CanvasLayer
		if cl.visible and not cl.is_ancestor_of(panel):
			cl.visible = false
			hidden.append(cl)
	return hidden


func _restore(hidden: Array) -> void:
	for h in hidden:
		if is_instance_valid(h):
			h.set("visible", true)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
