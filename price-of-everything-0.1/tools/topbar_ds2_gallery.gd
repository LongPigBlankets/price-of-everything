extends Node2D
## Every hover state and every flyout of the DS2 top bar, in the real HUD at 1920 × 1080 (two pixels
## each), after three turns of a busy player tile so the modules have something to say: each module
## hovered (its readout under the bar, Transport once per lamp), then each flyout open (Rankings on both
## of its tabs).
##   Godot --path . res://tools/topbar_ds2_gallery.tscn --quit-after 20000 -- --no-telemetry
## Writes hover_<module>.png and flyout_<id>.png into $TOPBAR_GALLERY_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
## A hover crop: the bar and the readout under it, this wide round the module.
const HOVER_HALF_W := 270.0
const HOVER_H := 150.0
const MODULES := ["MoneyWidget", "PowerModule", "TransportModule", "VictoryModule", "RankingsModule",
	"CouncilModule", "GoodsGraphModule", "EncyclopediaButton", "MenuModule"]

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("TOPBAR_GALLERY_DIR")
	if dir != "":
		_out = dir
	_vp = SubViewport.new()
	_vp.size = LOGICAL * 2
	_vp.size_2d_override = LOGICAL
	_vp.size_2d_override_stretch = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.gui_embed_subwindows = true
	add_child(_vp)
	UiPrefs.set_use_topbar_ds2(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(_wm)
	await _settle(140)
	var cam := _vp.get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	var bar: Control = _wm.get_node("UILayer/HUD/TopBar")

	MatchState.money = 8000.0
	var tile := "tile_5_10"
	BuildingState.add_building("b_007", "r_009", tile, "player_1", "gallery_m1")
	BuildingState.add_building("b_007", "r_003", tile, "player_1", "gallery_s1")
	BuildingState.add_building("b_025", "r_037", tile, "player_1", "gallery_w1")
	Stockpile.add(tile, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(tile, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	# The league shows from its reveal turn: jump there so Rankings has its module and flyout.
	TurnManager.current_turn = maxi(int(TurnManager.current_turn), int(CompanyRankings.REVEAL_TURN))
	CompanyRankings.rankings_updated.emit()
	bar.call("_queue_refresh")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(40)

	for mod_name: String in MODULES:
		var mod: Control = bar.find_child(mod_name, true, false)
		if mod == null or not mod.is_visible_in_tree():
			continue
		var cells: Array = ["storage", "links", "freight"] if mod_name == "TransportModule" else [""]
		for cell: String in cells:
			bar.set("ds2_readout_cell", cell)
			mod.mouse_entered.emit()
			await _settle(8)
			var c := mod.get_global_rect().get_center().x
			var x0 := clampf(c - HOVER_HALF_W, 0.0, LOGICAL.x - 2.0 * HOVER_HALF_W)
			var tag := mod_name.trim_suffix("Module").trim_suffix("Widget").trim_suffix("Button").to_lower()
			_save(Rect2(x0, 0, 2.0 * HOVER_HALF_W, HOVER_H), "hover_%s%s" % [tag, ("_" + cell) if cell != "" else ""])
			mod.mouse_exited.emit()
			await _settle(4)
	bar.set("ds2_readout_cell", "")

	for id: String in ["treasury", "power", "victory", "rankings", "council", "quest"]:
		var tabs: Array = ["revenue", "goods"] if id == "rankings" else [""]
		for tab: String in tabs:
			if tab != "":
				bar.set("_rankings_tab", tab)
			bar.call("_toggle_fly", id)
			await _settle(14)
			var panel: Control = bar.get("_fly_panel")
			if panel != null and panel.is_visible_in_tree():
				var r := panel.get_global_rect().grow(24.0)
				r = Rect2(Vector2(r.position.x, 0), Vector2(r.size.x, r.end.y))
				_save(r, "flyout_%s%s" % [id, ("_" + tab) if tab != "" else ""])
			else:
				print("[GALLERY] no flyout for %s" % id)
			bar.call("_close_fly")
			await _settle(6)
	print("[GALLERY] done")
	get_tree().quit(0)


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[GALLERY] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
