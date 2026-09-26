extends Node2D
## Captures of tile view v3's Buildings tab (scripts/tvp_v3/buildings_tab.gd) in scenarios the shared tool
## lacks, in the real HUD at 1920 × 1080 (two pixels each), cropped to the panel:
##   Godot --path . res://tools/tvp_v3_buildings_shot.tscn --quit-after 40000 -- --no-telemetry
## Writes into $TVP_SHOT_DIR (or /tmp):
##   bls_default_p<N>    the busy port tile as a player first sees it: groups folded, other companies shut,
##                       the port in its own case under the actions
##   bls_open_p<N>       the same with the motor group open (a fourth motor just built beside three that
##                       ran, so one member's words and output differ) and other companies' case open
##   bls_hover           a group member hovered through the real input path: its readout at the pointer
##   bls_hover_cost      the motor group's cost screen hovered: what the dearest unit costs
##   bls_hover_wind      the stalled wind farms' head hovered on the tile with no cables
##   bls_guard_lifted    the port's guarded Buy with its cover lifted, the price lit red
##   bls_port_mine       the same tile with the port yours: it reads as your buildings do
##   bls_big_p<N>        a tile with 20 of your buildings, unpowered (stalled factories read 0), folded
##   bls_big_open_p<N>   the same with the ten motors' group open
##   bls_features_p<N>   a tile with woods or ruins of the land's own
##   bls_empty           an empty tile nobody owns
## and prints rebuild timings and the width check, tagged [TVP_SHOT].

const BuildingNaming := preload("res://scripts/building_naming.gd")
const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_5_10"
const BIG_TILE := "tile_6_10"
const EMPTY_TILE := "tile_6_1"

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("TVP_SHOT_DIR")
	if dir != "":
		_out = dir
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
		cam.edge_pan_enabled = false

	# Instance ids come from BuildingState (hex counters), as in the game, so naming reads them as it would.
	MatchState.money = 80000.0
	for _i in 3:
		BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_007", "r_003", TILE, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_025", "r_037", TILE, MatchState.LOCAL_PLAYER)
	var mixes := [["b_007", "r_009"], ["b_007", "r_003"], ["b_025", "r_037"], ["b_007", "r_009"]]
	for i in 20:
		var m: Array = mixes[i % mixes.size()]
		BuildingState.add_building(str(m[0]), str(m[1]), BIG_TILE, MatchState.LOCAL_PLAYER)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	# A fourth motor factory just built beside the three that ran: it has not run yet.
	BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER)
	# One building going up, one waiting on its materials (named by the game, as a real project is).
	var built := Construction.start_on_tile("b_025", "r_037", TILE)
	if Construction.construction_projects.has(built):
		var waiting: Dictionary = (Construction.construction_projects[built] as Dictionary).duplicate(true)
		var wid := BuildingState.reserve_instance_id("b_007")
		waiting["instance_id"] = wid
		waiting["building_id"] = "b_007"
		waiting["recipe_id"] = "r_009"
		waiting["status"] = Construction.STATUS_AWAITING_MATERIALS
		waiting["turns_remaining"] = 12
		Construction.construction_projects[wid] = waiting
		waiting["name"] = BuildingNaming.label_for_tile(TILE, wid, "b_007", "r_009")
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(30)

	var panel: Control = _wm.find_child("TileInfoPanel", true, false)
	var terrain: Node = _wm.get("terrain_layer")
	UiPrefs.set_use_tvp_v3(true)
	await _settle(6)

	# As a player first sees it: every group folded, other companies shut.
	await _open(panel, terrain, TILE)
	_timings(panel, TILE)
	await _settle(20)
	await _pages(panel, "bls_default")

	# The motor group open and other companies' case open, a page at a time.
	_set_group(panel, "b_007|r_009", true)
	panel.set_meta("tvp_bl_others_open", true)
	await _open(panel, terrain, TILE)
	await _pages(panel, "bls_open")

	# A group member hovered through the real input path: its readout at the pointer.
	# The group's last member, the one just built, whose row says more than the head does.
	var member: Control = null
	var feed: Node = panel.find_child("Feed", true, false)
	if feed != null and feed.get_child_count() > 1 and feed.get_child(1).get_child_count() > 0:
		member = feed.get_child(1).get_child(feed.get_child(1).get_child_count() - 1) as Control
	if member != null:
		await _hover(panel, member, Vector2(0.3, 0.5), "bls_hover")
	var head: Control = panel.find_child("BuildingCard_b_007_r_009", true, false)
	var cost: Control = head.find_child("Cost", true, false) if head != null else null
	if cost != null:
		await _hover(panel, cost, Vector2(0.5, 0.5), "bls_hover_cost")

	# The port's Buy key.
	var guard: Control = panel.find_child("PortBuyButton", true, false)
	print("[TVP_SHOT] guard %s" % ("found" if guard != null else "MISSING"))
	panel.set_meta("tvp_bl_others_open", false)
	_set_group(panel, "b_007|r_009", false)

	# The port yours: its own case, read as your buildings are.
	var port: Dictionary = {}
	for b: Dictionary in BuildingState.get_buildings_on_tile(TILE):
		if str(b.get("building_id", "")) == "b_004":
			port = b
	if not port.is_empty():
		var owner := str(port.get("owner", ""))
		port["owner"] = MatchState.LOCAL_PLAYER
		await _open(panel, terrain, TILE)
		_save(panel.get_global_rect().grow(16.0), "bls_port_mine")
		port["owner"] = owner

	# Twenty of your buildings on unpowered land: folded, then the ten motors' group open.
	await _open(panel, terrain, BIG_TILE)
	_timings(panel, BIG_TILE)
	await _settle(30)
	await _pages(panel, "bls_big")
	var wind: Control = panel.find_child("BuildingCard_b_025_r_037", true, false)
	if wind != null:
		await _hover(panel, wind, Vector2(0.45, 0.5), "bls_hover_wind")
	_set_group(panel, "b_007|r_009", true)
	await _open(panel, terrain, BIG_TILE)
	await _pages(panel, "bls_big_open")
	_set_group(panel, "b_007|r_009", false)

	# A tile with the land's own woods or ruins.
	var feature_tile := ""
	for b: Dictionary in BuildingState.buildings.values():
		if str(b.get("building_id", "")) == "b_031" or BuildingState.is_land_owned_wood(b):
			feature_tile = str(b.get("tile_id", ""))
			break
	if feature_tile != "":
		await _open(panel, terrain, feature_tile)
		await _pages(panel, "bls_features")
	print("[TVP_SHOT] feature tile %s" % feature_tile)

	await _open(panel, terrain, EMPTY_TILE)
	_save(panel.get_global_rect().grow(16.0), "bls_empty")
	UiPrefs.set_use_tvp_v3(false)
	print("[TVP_SHOT] done")
	get_tree().quit(0)


## Moves the pointer onto `c` (at `at`, a share of its size) through the viewport's input, as a mouse does,
## waits for the tooltip, saves the panel with the tooltip, and moves the pointer off again. If the engine's
## tooltip timer does not run in this offscreen viewport, the tooltip is put up as the engine puts it up (the
## hovered control's own custom tooltip in a TooltipPanel popup at the pointer, offset as the engine offsets
## it) and the log says it was staged.
func _hover(panel: Control, c: Control, at: Vector2, tag: String) -> void:
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		var r := c.get_global_rect()
		var view := scroll.get_global_rect()
		scroll.scroll_vertical = int(scroll.scroll_vertical + r.get_center().y - view.get_center().y + 60.0)
		await _settle(4)
	var pos := c.get_global_rect().position + c.size * at
	_vp.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	for i in 3:
		var m := InputEventMouseMotion.new()
		m.position = pos + Vector2(i, 0)
		m.global_position = m.position
		_vp.push_input(m, true)
		await _settle(2)
	var hovered := _vp.gui_get_hovered_control()
	print("[TVP_SHOT] %s: pointer on %s" % [tag, str(hovered.name) if hovered != null else "nothing"])
	await get_tree().create_timer(1.2).timeout
	await _settle(4)
	var staged: Window = null
	if _shown_tip() == null and hovered != null:
		var tip_owner: Control = hovered
		while tip_owner != null and tip_owner.tooltip_text == "":
			tip_owner = tip_owner.get_parent() as Control
		if tip_owner != null:
			var custom: Object = tip_owner.call("_make_custom_tooltip", tip_owner.tooltip_text) if tip_owner.has_method("_make_custom_tooltip") else null
			staged = PopupPanel.new()
			staged.theme_type_variation = "TooltipPanel"
			staged.transparent_bg = true
			staged.transparent = true
			if custom is Control:
				staged.add_child(custom as Control)
			else:
				var l := Label.new()
				l.text = tip_owner.tooltip_text
				staged.add_child(l)
			tip_owner.add_child(staged)
			var offset: Vector2 = ProjectSettings.get_setting("display/mouse_cursor/tooltip_position_offset", Vector2(10, 10))
			staged.popup(Rect2i(Vector2i(pos + Vector2(2, 0) + offset), Vector2i(staged.get_contents_minimum_size())))
			await _settle(6)
			print("[TVP_SHOT] %s: tooltip staged at the pointer (the offscreen viewport runs no tooltip timer)" % tag)
	var shown := _shown_tip()
	if shown != null:
		print("[TVP_SHOT] %s: tooltip %s at %s, pointer at %s" % [tag, str(shown.size), str(shown.position), str(pos)])
	# The shot takes in the tooltip where the engine put it (below the pointer, right of it, or left of it
	# when the screen's edge is too near).
	var area := panel.get_global_rect().grow(16.0)
	if shown != null:
		area = area.merge(Rect2(Vector2(shown.position), Vector2(shown.size)).grow(12.0))
	_save(area, tag)
	if staged != null:
		staged.queue_free()
	var off := InputEventMouseMotion.new()
	off.position = Vector2(4, 4)
	off.global_position = off.position
	_vp.push_input(off, true)
	await _settle(4)


## The tooltip window on screen with a readout in it, if any.
func _shown_tip() -> Window:
	for w: Node in _vp.find_children("*", "Window", true, false):
		if (w as Window).visible and w.find_child("HoverReadout", true, false) != null:
			return w as Window
	return null


func _set_group(panel: Control, key: String, open: bool) -> void:
	var groups: Dictionary = panel.get_meta("tvp_bl_open_groups", {})
	groups[key] = open
	panel.set_meta("tvp_bl_open_groups", groups)


func _open(panel: Control, terrain: Node, tile_id: String) -> void:
	panel.call("show_tile", _tile(terrain, tile_id), "bl")
	await _settle(4)
	_scroll_to(panel, 0)
	await _settle(14)


## How long one rebuild of the tab takes (it runs on every refresh): from the readings kept on the panel,
## and with none kept; then v2's, and the width discipline (docs/ds2-theme.md §7.12), and how tall the
## body is.
func _timings(panel: Control, tile_id: String) -> void:
	var t0 := Time.get_ticks_usec()
	for _i in 5:
		panel.call("_refresh_pane", "bl")
	print("[TVP_SHOT] %s bl rebuild %.1f ms from kept readings" % [tile_id, (Time.get_ticks_usec() - t0) / 5000.0])
	panel.remove_meta("tvp_bl_readings")
	t0 = Time.get_ticks_usec()
	panel.call("_refresh_pane", "bl")
	print("[TVP_SHOT] %s bl rebuild %.1f ms with none kept" % [tile_id, (Time.get_ticks_usec() - t0) / 1000.0])
	var scratch := VBoxContainer.new()
	add_child(scratch)
	t0 = Time.get_ticks_usec()
	for _i in 3:
		panel.call("_build_bl_pane", scratch)
	print("[TVP_SHOT] %s v2 bl build %.1f ms" % [tile_id, (Time.get_ticks_usec() - t0) / 3000.0])
	scratch.queue_free()
	var body_scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	var panes: Dictionary = panel.get("_panes")
	var bl_pane: Control = panes.get("bl")
	if body_scroll != null and bl_pane != null:
		print("[TVP_SHOT] %s bl min width %.0f, scroll width %.0f, bar %.0f" % [tile_id,
			bl_pane.get_combined_minimum_size().x, body_scroll.size.x, body_scroll.get_v_scroll_bar().size.x])


func _tile(terrain: Node, tile_id: String) -> Dictionary:
	var td: Dictionary = {"id": tile_id}
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(tile_id), td)
	return td


func _scroll_to(panel: Control, y: int) -> void:
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = y


func _scroll_into_view(panel: Control, c: Control) -> void:
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.ensure_control_visible(c)


func _pages(panel: Control, tag: String) -> void:
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	var page := 1
	var step := maxf(80.0, scroll.size.y - 60.0) if scroll != null else 0.0
	if scroll != null:
		print("[TVP_SHOT] %s: body %.0f px in a %.0f px view" % [tag, scroll.get_v_scroll_bar().max_value, scroll.size.y])
	while page <= 6:
		_save(panel.get_global_rect().grow(16.0), "%s_p%d" % [tag, page])
		if scroll == null or scroll.scroll_vertical + scroll.size.y >= scroll.get_v_scroll_bar().max_value - 1.0:
			break
		scroll.scroll_vertical = int(scroll.scroll_vertical + step)
		await _settle(4)
		page += 1


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[TVP_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
