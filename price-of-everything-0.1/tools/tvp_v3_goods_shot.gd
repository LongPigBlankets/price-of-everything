extends Node2D
## Captures of the tile view v3's Goods tab (scripts/tvp_v3/goods_tab.gd), in the real HUD at 1920 × 1080
## (two pixels each), after three turns:
##   busy      the port tile tools/tvp_v3_shot.gd uses, with thirty motors sold so the sales row has
##             figures, and surveyed with no deposits (the empty Deposits state)
##   deposits  a surveyed tile with three deposits: a mine on its sand, a motor factory, a chemical works
##             that loses money (a red row under a green total), and a sulphur works going up
##   loss      the tile beside it with only a hydrogen power station: a red total, and the bay's door shut
##   going_up  another tile beside it with only a building going up: the door shut, the going up note
##   sold_only a tile beside the port with none of your buildings, where stock was sold last turn: the
##             Economics section holds the sales row alone
##   survey    an unsurveyed tile inside survey range (the Survey the tile note)
##   empty     the unowned mountain tile out of survey range
## Each is paged down its whole body. Also prints how long the tab takes to build, checks that the
## economics rows add up to the Goods key's figure, and presses a building's key.
## Then the busy and deposits tiles again with the total's key pressed (the value bars folded open).
##   Godot --path . res://tools/tvp_v3_goods_shot.tscn --quit-after 40000 -- --no-telemetry
## Writes tvp_v3_goods_<view>_p<n>.png into $TVP_SHOT_DIR (or /tmp).

const GoodsTab := preload("res://scripts/tvp_v3/goods_tab.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const BuildingEconomics := preload("res://scripts/building_economics.gd")
const LOGICAL := Vector2i(1920, 1080)
const BUSY := "tile_5_10"
const DEPOSITS := "tile_7_16"
const EMPTY := "tile_6_1"
## Two recipes BuildingEconomics.per_turn values below nothing at market prices: the Haber Bosch process
## (a chemical works) and hydrogen power (a power station). [building, recipe].
const LOSS_ROW := ["b_012", "r_046"]
const LOSS_TILE := ["b_003", "r_131"]

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

	MatchState.money = 8000.0
	# The busy port tile, as tools/tvp_v3_shot.gd sets it.
	BuildingState.add_building("b_007", "r_009", BUSY, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_007", "r_003", BUSY, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_025", "r_037", BUSY, MatchState.LOCAL_PLAYER)
	Stockpile.add(BUSY, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(BUSY, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 40)
	# The deposits tile: surveyed, a mine on its sand, a motor factory, and (after the turns) a chemical
	# works and a sulphur works going up.
	MatchState.mark_tile_surveyed(DEPOSITS)
	var sand := TileViewData.deposit_build_options("sand")
	if not sand.is_empty():
		BuildingState.add_building(str(sand[0].building_id), str(sand[0].recipe_id), DEPOSITS, MatchState.LOCAL_PLAYER)
	BuildingState.add_building("b_007", "r_009", DEPOSITS, MatchState.LOCAL_PLAYER)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	# A sale from the busy tile, so its Sold last turn row has figures: thirty motors sold at the port
	# through the engine's own sale (MatchState.queue_sell), as the Stock tab's Sell does.
	var motor := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	Stockpile.add(BUSY, motor, 30)
	MatchState.queue_sell(BUSY, {motor: 30}, false)
	# Stock sold from a tile beside the port where you have no buildings.
	var sold_only := _going_up_tile(BUSY)
	if sold_only != "":
		var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
		# The engine's own record of a realised sale from the tile (what a market sale shipped from it
		# books), as a sale from a tile with no road to the port cannot be queued.
		MatchState.record_tile_sale(sold_only, 20, 20.0 * MarketState.get_price(steel))
	# The loss makers go in last: a Haber Bosch plant on the deposits tile (a red row under a green total)
	# and a hydrogen power station alone on the tile beside it (a red total, and nothing in its bay).
	BuildingState.add_building(LOSS_ROW[0], LOSS_ROW[1], DEPOSITS, MatchState.LOCAL_PLAYER)
	var loss_tile := str(Catalog.tile_neighbours(DEPOSITS)[0])
	BuildingState.add_building(LOSS_TILE[0], LOSS_TILE[1], loss_tile, MatchState.LOCAL_PLAYER)
	var sulphur := TileViewData.deposit_build_options("sulphur")
	if not sulphur.is_empty():
		var iid := Construction.start_on_tile(str(sulphur[0].building_id), str(sulphur[0].recipe_id), DEPOSITS)
		print("[TVP_GOODS] sulphur project: %s" % iid)
	# A tile with only a building going up: the steel works, started on another neighbour.
	var going_up_tile := _going_up_tile(loss_tile)
	if going_up_tile != "":
		var gid := Construction.start_on_tile("b_007", "r_003", going_up_tile)
		print("[TVP_GOODS] going up on %s: %s" % [going_up_tile, gid])
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(30)

	var panel: Control = _wm.find_child("TileInfoPanel", true, false)
	UiPrefs.set_use_tvp_v3(true)
	await _settle(6)
	var views := {"busy": BUSY, "deposits": DEPOSITS, "loss": str(Catalog.tile_neighbours(DEPOSITS)[0])}
	var up := _going_up_tile(str(views.loss))
	if up != "" and not Construction.projects_on_tile(up).is_empty():
		views["going_up"] = up
	if sold_only != "":
		views["sold_only"] = sold_only
	var survey := _surveyable_tile()
	if survey != "":
		views["survey"] = survey
	views["empty"] = EMPTY
	for view: String in views:
		var tile := str(views[view])
		panel.call("show_tile", _tile(tile), "prod")
		await _settle(14)
		_check(panel, tile)
		await _pages(panel, view)
	# The total's key folds the value bars open under it (and the state is kept on the panel).
	panel.call("show_tile", _tile(BUSY), "prod")
	await _settle(8)
	var fold: Button = panel.find_child("NetValueAddedKey", true, false)
	if fold != null:
		fold.pressed.emit()
		await _settle(10)
		var bars: Control = panel.find_child("ValueBars", true, false)
		print("[TVP_GOODS] fold key pressed: bars shown %s, meta %s" % [bars != null and bars.is_visible_in_tree(),
			str(panel.get_meta("tvp_prod_bars_open", null))])
		panel.call("_refresh_pane", "prod")
		await _settle(8)
		bars = panel.find_child("ValueBars", true, false)
		print("[TVP_GOODS] after a refresh: bars shown %s" % (bars != null and bars.is_visible_in_tree()))
		await _pages(panel, "busy_open")
		panel.call("show_tile", _tile(DEPOSITS), "prod")
		await _settle(10)
		await _pages(panel, "deposits_open")
		fold = panel.find_child("NetValueAddedKey", true, false)
		fold.pressed.emit()
		await _settle(4)
		bars = panel.find_child("ValueBars", true, false)
		print("[TVP_GOODS] fold key pressed again: bars shown %s" % (bars != null and bars.is_visible_in_tree()))
	# How long a refresh of the tab takes on the busy tile (it rebuilds on every refresh).
	panel.call("show_tile", _tile(BUSY), "prod")
	await _settle(6)
	var t0 := Time.get_ticks_usec()
	for _i in 20:
		panel.call("_refresh_pane", "prod")
	print("[TVP_GOODS] refresh busy: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	panel.call("show_tile", _tile(DEPOSITS), "prod")
	await _settle(6)
	t0 = Time.get_ticks_usec()
	for _i in 20:
		panel.call("_refresh_pane", "prod")
	print("[TVP_GOODS] refresh deposits: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	# Of which: reading your buildings' economics (BuildingEconomics.per_turn), and the deposits' options.
	t0 = Time.get_ticks_usec()
	for _i in 20:
		GoodsTab.your_economics(DEPOSITS)
	print("[TVP_GOODS]   of which per_turn readings: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	t0 = Time.get_ticks_usec()
	for _i in 20:
		for token in ["sand", "sulphur", "shale_oil"]:
			TileViewData.deposit_build_options(token)
	print("[TVP_GOODS]   of which deposit options: %.2f ms" % ((Time.get_ticks_usec() - t0) / 20000.0))
	# A building's key opens it.
	await _settle(4)
	var opened: Array = []
	panel.building_clicked.connect(func(b: Dictionary) -> void: opened.append(str(b.get("instance_id", ""))))
	var key: Button = null
	for n in panel.find_children("OpenBuilding_*", "Button", true, false):
		if (n as Control).is_visible_in_tree():
			key = n
			break
	if key != null:
		key.pressed.emit()
	print("[TVP_GOODS] key %s opened: %s" % [key.name if key != null else "(none)", str(opened)])
	# The deposit's Go to building key opens the building working it.
	opened.clear()
	var go: Button = null
	for n in panel.find_children("GoToBuilding_*", "Button", true, false):
		if (n as Control).is_visible_in_tree():
			go = n
			break
	if go != null:
		go.pressed.emit()
	print("[TVP_GOODS] key %s opened: %s" % [go.name if go != null else "(none)", str(opened)])
	UiPrefs.set_use_tvp_v3(false)
	print("[TVP_SHOT] done")
	get_tree().quit(0)


func _tile(tile_id: String) -> Dictionary:
	var terrain: Node = _wm.get("terrain_layer")
	var td: Dictionary = {"id": tile_id}
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(tile_id), td)
	return td


## A land tile beside `beside` with nothing of the player's on it, for a building going up alone.
func _going_up_tile(beside: String) -> String:
	for n in Catalog.tile_neighbours(beside):
		var t := str(n)
		if t == BUSY or t == DEPOSITS or t == EMPTY or t == beside:
			continue
		var kind := str(_tile(t).get("type", "")).to_lower()
		if kind == "" or kind.contains("sea") or kind.contains("ocean") or kind.contains("water"):
			continue
		var mine := false
		for b: Dictionary in BuildingState.get_buildings_on_tile(t):
			mine = mine or BuildingState.is_player_owned(b)
		if not mine:
			return t
	return ""


## An unsurveyed land tile the player could survey now (inside survey range), for the Survey note.
func _surveyable_tile() -> String:
	for tid in Catalog.all_tile_ids():
		var t := str(tid)
		if t == BUSY or t == DEPOSITS or t == EMPTY or not Construction.projects_on_tile(t).is_empty() \
				or int(MatchState.get_tile_sales(t).get("units", 0)) > 0:
			continue
		var kind := str(_tile(t).get("type", "")).to_lower()
		if kind == "" or kind.contains("sea") or kind.contains("ocean") or kind.contains("water"):
			continue
		if MatchState.is_tile_surveyable(t) and MatchState.survey_status(t, kind) == "unsurveyed":
			return t
	return ""


## The economics rows add up to the Goods key's figure, and what each section shows.
func _check(panel: Control, tile: String) -> void:
	var prod := TileViewData.production_summary(tile)
	var yours := GoodsTab.your_economics(tile)
	var ours: Dictionary = GoodsTab.summary(yours)
	var sum := float(ours.net_value)
	var same := (ours.rows as Array).size() == (prod.rows as Array).size()
	for i in mini((ours.rows as Array).size(), (prod.rows as Array).size()):
		var a: Dictionary = ours.rows[i]
		var b: Dictionary = prod.rows[i]
		same = same and str(a.good_id) == str(b.good_id) and int(a.qty) == int(b.qty) and is_equal_approx(float(a.value), float(b.value))
	print("[TVP_GOODS] %s: the tab's sum is the key's: %s (goods rows match: %s)" % [tile, sum == float(prod.net_value), same])
	for y: Dictionary in yours:
		print("[TVP_GOODS] %s:   %s %s net value added %.2f" % [tile, str(y.building.get("building_id", "")),
			str(y.building.get("recipe_id", "")), float(y.econ.get("net_value_added", 0.0))])
	var pane: Node = panel.find_child("OutputBay", true, false)
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if pane != null and scroll != null:
		var body_w := (pane.get_parent() as Control).get_combined_minimum_size().x
		print("[TVP_GOODS] %s: body min width %.1f, room %.1f" % [tile, body_w, scroll.size.x - scroll.get_v_scroll_bar().size.x])
	var gated := TileViewData.survey_gated_deposits(tile, _tile(tile))
	print("[TVP_GOODS] %s: net %.4f outputs %d sales %s survey %s deposits %d note %s" % [tile,
		float(prod.net_value), (prod.rows as Array).size(), str(TileViewData.sales_summary(tile)),
		str(gated.status), (gated.rows as Array).size(), GoodsTab.survey_note(tile)])
	# Where each row's words start, from the tab's left: one x for every row type.
	var xs := {}
	for n in panel.find_children("Words", "VBoxContainer", true, false):
		var c := n as Control
		if c.is_visible_in_tree():
			xs[str(c.get_parent().name).get_slice("_", 0)] = snappedf(c.global_position.x, 0.5)
	for n in panel.find_children("OpenBuilding_*", "Button", true, false):
		var c := n as Control
		if c.is_visible_in_tree():
			xs["key"] = snappedf(c.global_position.x, 0.5)
	var nva: Node = panel.find_child("NetValueAdded", true, false)
	if nva != null:
		xs["total"] = snappedf((nva.get_child(1) as Control).global_position.x, 0.5)
	for n in panel.find_children("*Note", "HBoxContainer", true, false):
		var c := n as Control
		if c.is_visible_in_tree() and c.get_child_count() > 1:
			xs[str(c.name)] = snappedf((c.get_child(1) as Control).global_position.x, 0.5)
	var none: Node = panel.find_child("NothingMade", true, false)
	if none != null and (none as Control).is_visible_in_tree():
		xs["NothingMade"] = snappedf((none.get_child(1) as Control).global_position.x, 0.5)
	print("[TVP_GOODS] %s: text column x %s" % [tile, str(xs)])
	# The grid: each figure column's edges, gathered across every section. One entry per column means its
	# figures run straight down the tab.
	var body: Node = panel.find_child("OutputBay", true, false)
	if body == null:
		body = panel.find_child("Deposits", true, false)
	var cols := {}
	if body != null:
		for pattern: String in ["Units", "MoneyLed", "DepositKey", "GoToBuilding_*"]:
			for n in body.get_parent().find_children(pattern, "", true, false):
				var c := n as Control
				if not c.is_visible_in_tree():
					continue
				var key := "units" if pattern == "Units" else ("money" if pattern == "MoneyLed" else "key")
				if not cols.has(key):
					cols[key] = {}
				cols[key]["%.1f..%.1f" % [c.global_position.x, c.global_position.x + c.size.x]] = true
		# Each counter's drums and its right edge: sized to its own figure, one right edge down the tab.
		var counters: Array = []
		for n in body.get_parent().find_children("BdpV3Counter", "", true, false):
			var c := n as Control
			if c.is_visible_in_tree():
				var mount := c.get_parent() as Control
				counters.append("%d drums reading %d, right %.1f" % [int(c.get("drums")), int(c.get("value")),
					mount.global_position.x + mount.size.x])
		print("[TVP_GOODS] %s: counters %s" % [tile, str(counters)])
		# Every key's height, and the print the cabinet keys fit their labels to.
		var keys: Array = []
		for n in body.get_parent().find_children("*", "", true, false):
			var c := n as Control
			if c == null or not c.is_visible_in_tree():
				continue
			if c is Button and (c.name.begins_with("OpenBuilding_") or c.name.begins_with("GoToBuilding_") or c.name == "NetValueAddedKey"):
				keys.append("%s h %.1f w %.1f" % [c.name, c.size.y, c.size.x])
			elif c.name == "DepositKey":
				var Plate: GDScript = load("res://scripts/bdp_v3_plate.gd")
				var label := str(c.get("text")).to_upper()
				var face := c.size.x - 2.0 * 15.6 / 1.875
				var fs: int = Plate._fit(Plate.FONT_SEMI, label, 15, face - 6.0)
				keys.append("%s %s h %.1f w %.1f print %d px" % [c.name, label, c.size.y, c.size.x, fs])
		print("[TVP_GOODS] %s: keys %s" % [tile, str(keys)])
	for key: String in cols:
		print("[TVP_GOODS] %s: %s column edges %s" % [tile, key, str((cols[key] as Dictionary).keys())])
	var housing: Control = panel.find_child("RolledDoor", true, false)
	if housing != null and housing.is_visible_in_tree():
		print("[TVP_GOODS] %s: door rolled up under the heading, %.1f tall" % [tile, housing.size.y])
	# The shut door reaches the frame's rim at its foot.
	var door: Control = panel.find_child("ShutDoor", true, false)
	if door != null and door.is_visible_in_tree():
		var bay := door.get_parent().get_parent() as Control
		print("[TVP_GOODS] %s: door foot %.1f, bay rim %.1f, note %s" % [tile, door.global_position.y + door.size.y + 8.0,
			bay.global_position.y + bay.size.y - 26.0 / 1.875, str((door.find_child("Note", true, false) as Label).text)])


## Pages down the tab's body from its top, a capture a page.
func _pages(panel: Control, view: String) -> void:
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	if scroll != null:
		scroll.scroll_vertical = 0
	await _settle(6)
	var page := 1
	var step := maxf(80.0, scroll.size.y - 60.0) if scroll != null else 0.0
	while page <= 6:
		_save(panel.get_global_rect().grow(16.0), "tvp_v3_goods_%s_p%d" % [view, page])
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
