extends Node2D
## Captures for the top bar and tile view plans: the whole HUD at 1920 × 1080 (two pixels each), the top
## bar, the drawn footprint of every icon in it, and the tile view's four tabs on a busy player tile.
##   Godot --path . res://tools/ui_plan_shot.tscn --quit-after 6000 -- --no-telemetry
## Writes into $UI_PLAN_SHOT_DIR (or /tmp): PNGs, topbar_tree.txt and topbar_icons.csv.

const LOGICAL := Vector2i(1920, 1080)

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("UI_PLAN_SHOT_DIR")
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

	var bar: Control = _wm.get_node("UILayer/HUD/TopBar")
	_save_full("hud_start")
	_save_rect(_bar_rect(bar), "topbar_start")

	# A busy player tile: two motor factories (one starved), a steel furnace, a wind farm, two NPC
	# buildings, and a fresh building with no run yet.
	MatchState.money = 8000.0
	var tile := "tile_5_10"
	var steel_id := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var wiring_id := str(Catalog.get_good_by_internal_name("copper_wiring").get("id", ""))
	BuildingState.add_building("b_007", "r_009", tile, "player_1", "uiplan_m1")
	BuildingState.add_building("b_007", "r_009", tile, "player_1", "uiplan_m2")
	BuildingState.add_building("b_007", "r_003", tile, "player_1", "uiplan_s1")
	BuildingState.add_building("b_025", "r_037", tile, "player_1", "uiplan_w1")
	BuildingState.add_building("b_002", "r_003", tile, "npc_glass", "uiplan_npc1")
	BuildingState.add_building("b_007", "r_009", tile, "npc_glass", "uiplan_npc2")
	Stockpile.add(tile, steel_id, 40)
	Stockpile.add(tile, wiring_id, 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	await _settle(20)
	BuildingState.add_building("b_007", "r_033", tile, "player_1", "uiplan_fresh")
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	await _settle(40)

	_save_full("hud_turn3")
	_save_rect(_bar_rect(bar), "topbar_turn3")
	_dump_tree(bar)
	await _measure_icons(bar)

	# The tile view, each tab, then with the building detail panel docked beside it.
	var panel: Control = _wm.info_panel
	var coord: Vector2i = _wm.terrain_layer.id_to_coord(tile)
	var tile_data: Dictionary = (_wm.terrain_layer.tiles.get(coord, {}) as Dictionary).duplicate()
	if not tile_data.has("id"):
		tile_data["id"] = tile
	panel.show_tile(tile_data)
	await _settle(25)
	for tab: String in ["bl", "power", "prod", "stock"]:
		panel.call("_select_tab", tab)
		await _settle(20)
		_save_rect(panel.get_global_rect().grow(24.0), "tile_" + tab)
	panel.call("_select_tab", "bl")
	await _settle(10)
	_save_full("hud_tile")
	var building: Dictionary = BuildingState.get_building("uiplan_m1")
	_wm._open_building_detail(building)
	await _settle(30)
	_save_full("hud_tile_bdp")

	# An unowned land tile and an NPC tile, if the map has them near the port.
	var shown := 0
	for c: Vector2i in _wm.terrain_layer.tiles:
		if shown >= 2:
			break
		var td: Dictionary = _wm.terrain_layer.tiles[c]
		var tid := str(td.get("id", ""))
		if tid == "" or tid == tile or str(td.get("type", "")).to_lower() in ["sea", "deep_sea", "ocean", "water"]:
			continue
		var on_tile: Array = BuildingState.get_buildings_on_tile(tid)
		if shown == 0 and on_tile.is_empty():
			panel.show_tile(td.duplicate())
			await _settle(25)
			_save_rect(panel.get_global_rect().grow(24.0), "tile_empty_" + tid)
			shown += 1
		elif shown == 1 and not on_tile.is_empty():
			panel.show_tile(td.duplicate())
			await _settle(25)
			_save_rect(panel.get_global_rect().grow(24.0), "tile_npc_" + tid)
			shown += 1
	print("[UI_PLAN_SHOT] done")
	get_tree().quit(0)


## The bar and whatever hangs below it (the briefing notch): the bar's rect, taken 120 px deeper.
func _bar_rect(bar: Control) -> Rect2:
	var r := bar.get_global_rect()
	return Rect2(r.position, Vector2(r.size.x, r.size.y + 120.0))


func _dump_tree(bar: Control) -> void:
	var f := FileAccess.open(_out.path_join("topbar_tree.txt"), FileAccess.WRITE)
	f.store_line("viewport %s, bar %s" % [_vp.get_visible_rect().size, bar.get_global_rect()])
	_dump(bar, 0, f)
	f.close()


func _dump(n: Node, depth: int, f: FileAccess) -> void:
	var line := "%s%s [%s]" % ["  ".repeat(depth), n.name, n.get_class()]
	var s: Script = n.get_script()
	if s != null:
		line += " script=%s" % (s.resource_path if s.resource_path != "" else str(s))
	if n is Control:
		var c := n as Control
		line += " rect=%s vis=%s" % [c.get_global_rect(), c.is_visible_in_tree()]
		if c is Label:
			line += " text=%s font=%d" % [JSON.stringify((c as Label).text), (c as Label).get_theme_font_size("font_size")]
		if c is TextureRect and (c as TextureRect).texture != null:
			var t := (c as TextureRect).texture
			line += " tex=%s %s expand=%d stretch=%d" % [t.resource_path, t.get_size(), (c as TextureRect).expand_mode, (c as TextureRect).stretch_mode]
		if c is Button:
			line += " btn_text=%s" % JSON.stringify((c as Button).text)
	f.store_line(line)
	for ch in n.get_children():
		_dump(ch, depth + 1, f)


## Every small leaf control in the bar that isn't text: hide it by alpha (layout unchanged), capture,
## and bound the pixels that changed. That bound is the icon as drawn, glow and shadow included.
func _measure_icons(bar: Control) -> void:
	var f := FileAccess.open(_out.path_join("topbar_icons.csv"), FileAccess.WRITE)
	f.store_line("path,class,rect_x,rect_y,rect_w,rect_h,drawn_x,drawn_y,drawn_w,drawn_h")
	var k := 2.0
	for n: Node in bar.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or c is Label or c is RichTextLabel:
			continue
		var leaf := true
		for ch in c.get_children():
			if ch is Control and (ch as Control).is_visible_in_tree():
				leaf = false
		if not leaf and not (c is TextureRect):
			continue
		var r := c.get_global_rect()
		if r.size.x < 4.0 or r.size.y < 4.0 or r.size.x > 160.0 or r.size.y > 100.0:
			continue
		var base := _grab()
		var old := c.modulate
		c.modulate = Color(old.r, old.g, old.b, 0.0)
		await _settle(2)
		var hidden := _grab()
		c.modulate = old
		await _settle(2)
		var box := _diff_box(base, hidden, r.grow(16.0), k)
		f.store_line("%s,%s,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f,%.1f" % [str(bar.get_path_to(c)).replace(",", ";"), c.get_class(),
			r.position.x, r.position.y, r.size.x, r.size.y, box.position.x, box.position.y, box.size.x, box.size.y])
	f.close()


func _diff_box(a: Image, b: Image, area: Rect2, k: float) -> Rect2:
	var img_rect := Rect2i(Vector2i.ZERO, a.get_size())
	var px := Rect2i(Vector2i(area.position * k), Vector2i(area.size * k)).intersection(img_rect)
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-1, -1)
	for y in range(px.position.y, px.end.y):
		for x in range(px.position.x, px.end.x):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			if absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b) > 0.06:
				lo = Vector2i(mini(lo.x, x), mini(lo.y, y))
				hi = Vector2i(maxi(hi.x, x), maxi(hi.y, y))
	if hi.x < 0:
		return Rect2()
	return Rect2(Vector2(lo) / k, Vector2(hi - lo + Vector2i.ONE) / k)


func _save_full(tag: String) -> void:
	_grab().save_png(_out.path_join("uiplan_%s.png" % tag))
	print("[UI_PLAN_SHOT] saved %s" % tag)


func _save_rect(r: Rect2, tag: String) -> void:
	var img := _grab()
	var k := img.get_width() / _vp.get_visible_rect().size.x
	var crop := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(crop).save_png(_out.path_join("uiplan_%s.png" % tag))
	print("[UI_PLAN_SHOT] saved %s" % tag)


## Drawn now, not the last frame: macOS stops drawing while no window can be seen.
func _grab() -> Image:
	RenderingServer.force_draw(false)
	return _vp.get_texture().get_image()


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
