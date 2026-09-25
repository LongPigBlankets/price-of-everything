extends Node2D
## Captures of the tile view for the v3 work (docs/tile-view-ds2-plan.md), in the real HUD at 1920 × 1080
## (two pixels each), after three turns of a busy tile you own: each tab, with the v3 look off and on
## (UiPrefs.use_tvp_v3), cropped to the panel.
##   Godot --path . res://tools/tvp_v3_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes tvp_<look>_<tab>.png into $TVP_SHOT_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_5_10"
const EMPTY_TILE := "tile_6_1"
const TABS := ["bl", "power", "prod", "stock", "transport"]

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
	BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER, "tvpshotm1")
	BuildingState.add_building("b_007", "r_003", TILE, MatchState.LOCAL_PLAYER, "tvpshots1")
	BuildingState.add_building("b_025", "r_037", TILE, MatchState.LOCAL_PLAYER, "tvpshotw1")
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 40)
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	for _i in 3:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
	var dock: Node = _wm.find_child("EndTurnDock", true, false)
	if dock != null and dock.get("_expanded") == true:
		dock.call("_collapse")
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(30)

	var panel: Control = _wm.find_child("TileInfoPanel", true, false)
	var terrain: Node = _wm.get("terrain_layer")
	var td: Dictionary = {"id": TILE}
	if terrain != null and terrain.has_method("id_to_coord"):
		td = terrain.tiles.get(terrain.id_to_coord(TILE), td)
	for look: String in ["v2", "v3"]:
		UiPrefs.set_use_tvp_v3(look == "v3")
		for tab: String in TABS:
			if tab == "transport" and look == "v2":
				continue
			panel.call("show_tile", td, tab)
			await _settle(12)
			_save(panel.get_global_rect().grow(16.0), "tvp_%s_%s" % [look, tab])
	# v3 on an empty, unsurveyed tile: Survey beside the land, nothing of yours.
	var empty: Dictionary = {"id": EMPTY_TILE}
	if terrain != null and terrain.has_method("id_to_coord"):
		empty = terrain.tiles.get(terrain.id_to_coord(EMPTY_TILE), empty)
	panel.call("show_tile", empty, "bl")
	await _settle(12)
	_save(panel.get_global_rect().grow(16.0), "tvp_v3_empty")
	UiPrefs.set_use_tvp_v3(false)
	print("[TVP_SHOT] done")
	get_tree().quit(0)


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
