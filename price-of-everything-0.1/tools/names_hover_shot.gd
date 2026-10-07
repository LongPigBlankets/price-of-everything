extends Node
## Captures of the building names: Building Detail v3's title hovered through the real input path, its recipe's
## dot card open, and tile view v3's Buildings tab on a tile of farms and forests. In the real HUD at
## 1920 x 1080 (two pixels each), cropped to the panel and the card. Needs a window:
##   <godot> --path . res://tools/names_hover_shot.tscn --quit-after 6000 -- --no-telemetry
## Writes names_bdp_title_hover.png and names_farms_p<N>.png into $NAMES_SHOT_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
const TILE := "tile_5_10"
const FARM_TILE := "tile_4_10"

var _vp: SubViewport
var _wm
var _out := "/tmp"


func _ready() -> void:
	var dir := OS.get_environment("NAMES_SHOT_DIR")
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
	DecisionState.enabled = false

	var iid: String = BuildingState.add_building("b_007", "r_009", TILE, MatchState.LOCAL_PLAYER)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("steel").get("id", "")), 60)
	Stockpile.add(TILE, str(Catalog.get_good_by_internal_name("copper_wiring").get("id", "")), 64)
	BuildingState.tile_land_owned[FARM_TILE] = 400
	for r: String in ["r_209", "r_211", "r_212", "r_208"]:
		BuildingState.add_building("b_014", r, FARM_TILE, MatchState.LOCAL_PLAYER)
	for r: String in ["r_213", "r_215"]:
		BuildingState.add_building("b_015", r, FARM_TILE, MatchState.LOCAL_PLAYER)
	var toasts: Node = _wm.get_node_or_null("UILayer/HUD/ToastLayer")
	if toasts != null:
		toasts.call("clear")
	await _settle(10)

	# Building Detail v3, its title hovered.
	_wm._open_building_detail(BuildingState.get_building(iid))
	await _settle(24)
	var bdp: Control = _wm.building_panel_v2
	await _hover(bdp, bdp._title_v3, Vector2(0.3, 0.5), "names_bdp_title_hover")
	bdp.hide()
	await _settle(6)

	# The tile view's Buildings tab on the farm tile.
	var panel: Control = _wm.find_child("TileInfoPanel", true, false)
	var terrain: Node = _wm.get("terrain_layer")
	var td: Dictionary = terrain.tiles.get(terrain.id_to_coord(FARM_TILE), {"id": FARM_TILE})
	panel.call("show_tile", td, "bl")
	await _settle(30)
	await _pages(panel, "names_farms")
	print("[NAMES_SHOT] done")
	get_tree().quit(0)


## Moves the pointer onto `c` through the viewport's input, waits for the tooltip, and saves `panel` with it.
## When the offscreen viewport runs no tooltip timer, the hovered control's own card is put up at the pointer
## as the engine would, and the log says so.
func _hover(panel: Control, c: Control, at: Vector2, tag: String) -> void:
	var pos := c.get_global_rect().position + c.size * at
	_vp.notification(Node.NOTIFICATION_VP_MOUSE_ENTER)
	for i in 3:
		var m := InputEventMouseMotion.new()
		m.position = pos + Vector2(i, 0)
		m.global_position = m.position
		_vp.push_input(m, true)
		await _settle(2)
	var hovered := _vp.gui_get_hovered_control()
	print("[NAMES_SHOT] %s: pointer on %s" % [tag, str(hovered.name) if hovered != null else "nothing"])
	await get_tree().create_timer(1.2).timeout
	await _settle(4)
	var shown := _shown_tip()
	if shown == null and c.tooltip_text != "":
		var staged := PopupPanel.new()
		staged.theme_type_variation = "TooltipPanel"
		staged.transparent_bg = true
		staged.transparent = true
		staged.add_child(c.call("_make_custom_tooltip", c.tooltip_text) as Control)
		c.add_child(staged)
		var offset: Vector2 = ProjectSettings.get_setting("display/mouse_cursor/tooltip_position_offset", Vector2(10, 10))
		staged.popup(Rect2i(Vector2i(pos + offset), Vector2i(staged.get_contents_minimum_size())))
		await _settle(8)
		shown = staged
		print("[NAMES_SHOT] %s: card staged at the pointer (no tooltip timer offscreen)" % tag)
	var area := panel.get_global_rect().grow(16.0)
	if shown != null:
		area = area.merge(Rect2(Vector2(shown.position), Vector2(shown.size)).grow(12.0))
	_save(area, tag)


func _shown_tip() -> Window:
	for w: Node in _vp.find_children("*", "Window", true, false):
		if (w as Window).visible and w.find_child("TransportTip", true, false) != null:
			return w as Window
	return null


func _pages(panel: Control, tag: String) -> void:
	var scroll: ScrollContainer = panel.find_child("BodyScroll", true, false)
	var step := maxf(80.0, scroll.size.y - 60.0) if scroll != null else 0.0
	for page in range(1, 4):
		_save(panel.get_global_rect().grow(16.0), "%s_p%d" % [tag, page])
		if scroll == null or scroll.scroll_vertical + scroll.size.y >= scroll.get_v_scroll_bar().max_value - 1.0:
			break
		scroll.scroll_vertical = int(scroll.scroll_vertical + step)
		await _settle(4)


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[NAMES_SHOT] saved %s" % tag)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
