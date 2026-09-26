extends Node2D
## The tile view v3's fixed part on tiles with deposits: surveyed, partly surveyed and unsurveyed, each with
## several deposits, in the real HUD at 1920 x 1080 (two pixels each), cropped to the panel's top.
##   Godot --path . res://tools/tvp_v3_deposits_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes tvp_v3_deposits_<tile>.png into $TVP_SHOT_DIR (or /tmp).

const LOGICAL := Vector2i(1920, 1080)
const TILES := {"tile_11_4": "surveyed", "tile_7_16": "surveyed", "tile_18_18": "unsurveyed", "tile_12_5": "surveyed"}

var _vp: SubViewport
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
	var wm: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	_vp.add_child(wm)
	for _i in 140:
		await get_tree().process_frame
	UiPrefs.set_use_tvp_v3(true)
	var panel: Control = wm.find_child("TileInfoPanel", true, false)
	var terrain: Node = wm.get("terrain_layer")
	for tile: String in TILES:
		if TILES[tile] == "surveyed":
			MatchState.mark_tile_surveyed(tile)
		var td: Dictionary = {"id": tile}
		if terrain != null and terrain.has_method("id_to_coord"):
			td = terrain.tiles.get(terrain.id_to_coord(tile), td)
		panel.call("show_tile", td, "bl")
		for _i in 12:
			await get_tree().process_frame
		var r := panel.get_global_rect()
		_save(Rect2(r.position - Vector2(16, 16), Vector2(r.size.x + 32, 300)), "tvp_v3_deposits_%s" % tile)
	UiPrefs.set_use_tvp_v3(false)
	print("[DEPOSITS_SHOT] done")
	get_tree().quit(0)


func _save(r: Rect2, tag: String) -> void:
	RenderingServer.force_draw(false)
	var img := _vp.get_texture().get_image()
	var k := img.get_width() / float(LOGICAL.x)
	var px := Rect2i(Vector2i(r.position * k), Vector2i(r.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(px).save_png(_out.path_join("%s.png" % tag))
	print("[DEPOSITS_SHOT] saved %s" % tag)
