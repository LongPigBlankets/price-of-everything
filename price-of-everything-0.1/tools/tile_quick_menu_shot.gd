extends Node2D
## Captures of a tile's quick menu (right click on the map) and the building panel's Favourite key, in the real HUD
## at 1920 × 1080 (two pixels each).
##   AGENT_GODOT_WINDOW=1 godot --path . res://tools/tile_quick_menu_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes quick_menu_<page>.png and quick_menu_star_<off|on>.png into $QUICK_SHOT_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_5_10"

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("QUICK_SHOT_DIR")
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
	BuildingState.purchase_tile_land(TILE, 6)
	var iid := BuildingState.add_building("b_002", "r_005", TILE, MatchState.LOCAL_PLAYER, "quickshotf1")
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 40)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("coal").get("id", "")), 120)
	MatchState.toggle_favourite_build("b_007", "r_009", 1)
	MatchState.toggle_favourite_build("b_002", "r_005", 2)
	await _settle(10)

	var td: Dictionary = _wm.terrain_layer.tiles.get(_wm.terrain_layer.id_to_coord(TILE), {"id": TILE})
	_wm._on_tile_menu_requested(td, Vector2(760, 300))
	var menu: PopupPanel = _wm._tile_menu
	for page: String in ["main", "goods", "favourites", "buy_land"]:
		menu.show_page(page)
		await _settle(12)
		_save(Rect2(Vector2(menu.position), Vector2(menu.size)).grow(12.0), "quick_menu_%s" % page)
	menu.hide()

	_wm._open_building_detail(BuildingState.get_building(iid))
	await _settle(24)
	var panel: Control = _wm.building_panel_v2
	var head := Rect2(panel.global_position, Vector2(panel.size.x, 190.0)).grow(8.0)
	_save(head, "quick_menu_star_off")
	panel.call("_on_star_pressed")
	await _settle(8)
	_save(head, "quick_menu_star_on")
	print("[QUICK_SHOT] done")
	get_tree().quit(0)


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[QUICK_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
