extends Node
## Capture harness for the map editor — the only way to verify an editor that has no
## headless behaviour to assert. WINDOWED ONLY: `--headless` renders nothing, and every
## capture would come back as an empty or stale frame.
##
##   <godot> --path . res://tools/map_editor/map_editor_shot.tscn --quit-after 6000 -- \
##       --tile=tile_23_8 --zoom=0.9 --out=/tmp/poe_map_editor
##
## Options (env fallbacks in brackets, CLI wins):
##   --tile=<id>     tile to frame        [POE_EDITOR_SHOT_TILE]   default tile_23_8
##   --zoom=<f>      px per world unit    [POE_EDITOR_SHOT_ZOOM]   default 0.9
##   --size=WxH      window size          [POE_EDITOR_SHOT_SIZE]   default 1280x800
##   --out=<prefix>  PNG path prefix      [POE_EDITOR_SHOT_OUT]    default /tmp/poe_map_editor
##
## Delete the target PNG before running: a failed capture otherwise leaves the previous
## run's file in place and gets compared silently (the trap recorded in the QA skill).

const DEFAULT_TILE := "tile_23_8"
const DEFAULT_ZOOM := 0.9
const DEFAULT_SIZE := Vector2i(1280, 800)
const DEFAULT_OUT := "/tmp/poe_map_editor"

## The editor's own settle is 150 frames; this is the outer bound before giving up, so a
## world that never finishes reports a failure instead of capturing a grey screen.
const MAX_WAIT_FRAMES := 1200
## Frames between "the editor says it is ready" and the capture, for the first paint.
const PAINT_FRAMES := 20

var _tile := DEFAULT_TILE
var _zoom := DEFAULT_ZOOM
var _size := DEFAULT_SIZE
var _out := DEFAULT_OUT


func _ready() -> void:
	_parse_options()
	get_window().size = _size
	var packed := load("res://tools/map_editor/map_editor.tscn") as PackedScene
	if packed == null:
		push_error("[EDITOR-SHOT] could not load the editor scene")
		get_tree().quit(1)
		return
	var editor := packed.instantiate()
	add_child(editor)

	var waited := 0
	while waited < MAX_WAIT_FRAMES and not bool(editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		waited += 1
	if not bool(editor.call("is_ready_to_edit")):
		push_error("[EDITOR-SHOT] the editor never became ready (%d frames)" % waited)
		get_tree().quit(1)
		return
	print("[EDITOR-SHOT] editor ready after %d frames" % waited)

	if not bool(editor.call("focus_tile", _tile, _zoom)):
		push_error("[EDITOR-SHOT] unknown tile '%s'" % _tile)
		get_tree().quit(1)
		return
	for _i in PAINT_FRAMES:
		await get_tree().process_frame
	# force_draw beats awaiting frame_post_draw here: an occluded window never presents,
	# and every capture then returns the same stale frame (tools/map_style_shot.gd).
	RenderingServer.force_draw()
	var image := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_out, _tile]
	var err := image.save_png(path)
	if err != OK:
		push_error("[EDITOR-SHOT] save failed (%d) for %s" % [err, path])
		get_tree().quit(1)
		return
	print("[EDITOR-SHOT] wrote %s  (%dx%d)" % [path, image.get_width(), image.get_height()])
	get_tree().quit(0)


func _parse_options() -> void:
	_tile = _env("POE_EDITOR_SHOT_TILE", DEFAULT_TILE)
	_zoom = float(_env("POE_EDITOR_SHOT_ZOOM", str(DEFAULT_ZOOM)))
	_out = _env("POE_EDITOR_SHOT_OUT", DEFAULT_OUT)
	var size_text := _env("POE_EDITOR_SHOT_SIZE", "")
	if size_text != "":
		_size = _parse_size(size_text)
	for argument in OS.get_cmdline_user_args():
		var text := str(argument)
		if text.begins_with("--tile="):
			_tile = text.substr(7)
		elif text.begins_with("--zoom="):
			_zoom = float(text.substr(7))
		elif text.begins_with("--out="):
			_out = text.substr(6)
		elif text.begins_with("--size="):
			_size = _parse_size(text.substr(7))


func _parse_size(text: String) -> Vector2i:
	var parts := text.split("x", false)
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return DEFAULT_SIZE
	return Vector2i(int(parts[0]), int(parts[1]))


func _env(key: String, fallback: String) -> String:
	var value := OS.get_environment(key)
	return value if value != "" else fallback
