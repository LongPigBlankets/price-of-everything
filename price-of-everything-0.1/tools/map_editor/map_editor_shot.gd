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

const AuthoredMapRef := preload("res://scripts/authored_map.gd")

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
	# The editor drives itself from synthetic input here, and a computed click can land on
	# the tool panel and press a button. Scratch mode makes that harmless: the editor opens
	# an empty document and cannot write to a real one.
	OS.set_environment("POE_EDITOR_SCRATCH", "1")
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

	# POE_EDITOR_SHOT_DEMO=1 exercises the drawing tools before the capture, so the shot
	# shows what they produce rather than an empty map.
	if OS.get_environment("POE_EDITOR_SHOT_DEMO") == "1":
		await _demo(editor)
	if OS.get_environment("POE_EDITOR_SHOT_HATCH") == "1":
		await _demo_hatch(editor)
	if OS.get_environment("POE_EDITOR_SHOT_SPECIAL") == "1":
		await _demo_special(editor)
	if OS.get_environment("POE_EDITOR_SHOT_ZONES") == "1":
		editor.call("focus_tile", _tile, _zoom)
		await get_tree().process_frame
		await _demo_zones(editor)
	if OS.get_environment("POE_EDITOR_SHOT_SLOTS") == "1":
		editor.call("focus_tile", _tile, _zoom)
		await get_tree().process_frame
		await _demo_slots(editor)
	if OS.get_environment("POE_EDITOR_SHOT_FABRIC") == "1":
		editor.call("focus_tile", _tile, _zoom)
		await get_tree().process_frame
		await _demo_fabric(editor)
	# POE_EDITOR_SHOT_SAVE=<name> also saves the result under that name, exercising the real
	# save path (named file + active pointer) rather than only the drawing tools.
	var save_as := OS.get_environment("POE_EDITOR_SHOT_SAVE")
	if save_as != "":
		editor.call("_save_as", save_as)
		await get_tree().process_frame
		print("[EDITOR-SHOT] saved as '%s'" % save_as)
	if OS.get_environment("POE_EDITOR_SHOT_WATER") == "1":
		editor.call("toggle_water_mask")
	# Open named accordions before capturing, so a shot can show a folded section.
	var open_folds := OS.get_environment("POE_EDITOR_SHOT_FOLDS")
	if open_folds != "":
		for title in open_folds.split(",", false):
			editor.call("open_panel_section", str(title))
		await get_tree().process_frame
	var at := OS.get_environment("POE_EDITOR_SHOT_AT")
	if at != "":
		var xy := at.split(",", false)
		if xy.size() == 2:
			var camera: Camera2D = editor.call("camera")
			camera.position = Vector2(float(xy[0]), float(xy[1]))
			camera.zoom = Vector2(_zoom, _zoom)
			if "_target_zoom" in camera:
				camera.set("_target_zoom", camera.zoom)
			for _i in PAINT_FRAMES:
				await get_tree().process_frame
			RenderingServer.force_draw()
			var at_path := "%s_at.png" % _out
			get_viewport().get_texture().get_image().save_png(at_path)
			print("[EDITOR-SHOT] wrote %s" % at_path)
			get_tree().quit(0)
			return
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


## Draw one stroke with each tool, so a capture shows the pen, the freehand trace, the
## joined dots and a curved anchor side by side.
func _demo(editor: Node) -> void:
	editor.call("focus_tile", _tile, _zoom)
	await get_tree().process_frame
	editor.call("set_road_class", "major")
	editor.call("set_tool", "road")
	await _click(Vector2(420, 250))
	await _click(Vector2(1000, 300))
	_key(KEY_ENTER)
	await get_tree().process_frame

	editor.call("set_road_class", "mid")
	editor.call("set_tool", "trace")
	var path := [Vector2(380, 430), Vector2(520, 470), Vector2(660, 430),
		Vector2(800, 480), Vector2(980, 440)]
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = path[0]
	Input.parse_input_event(down)
	await get_tree().process_frame
	for i in range(1, path.size()):
		var motion := InputEventMouseMotion.new()
		motion.position = path[i]
		motion.relative = (path[i] as Vector2) - (path[i - 1] as Vector2)
		Input.parse_input_event(motion)
		await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = path[path.size() - 1]
	Input.parse_input_event(up)
	await get_tree().process_frame

	editor.call("set_road_class", "minor")
	editor.call("set_tool", "dots")
	for at in [Vector2(400, 640), Vector2(700, 700), Vector2(980, 620)]:
		await _click(at)
	await _click(Vector2(400, 640))
	await _click(Vector2(700, 700))
	await _click(Vector2(700, 700))
	await _click(Vector2(980, 620))

	editor.call("set_tool", "anchor")
	var mid := Vector2(550, 670)
	var grab_down := InputEventMouseButton.new()
	grab_down.button_index = MOUSE_BUTTON_LEFT
	grab_down.pressed = true
	grab_down.position = mid
	Input.parse_input_event(grab_down)
	await get_tree().process_frame
	var grab_move := InputEventMouseMotion.new()
	grab_move.position = mid + Vector2(0, 90)
	grab_move.relative = Vector2(0, 90)
	Input.parse_input_event(grab_move)
	await get_tree().process_frame
	var grab_up := InputEventMouseButton.new()
	grab_up.button_index = MOUSE_BUTTON_LEFT
	grab_up.pressed = false
	grab_up.position = mid + Vector2(0, 90)
	Input.parse_input_event(grab_up)
	await get_tree().process_frame
	editor.call("set_tool", "dots")


## Ground and fabric, for a capture that shows P2's tools rather than only the roads.
func _demo_fabric(editor: Node) -> void:
	# A wood, a farm and a park, each an outlined polygon.
	editor.call("set_area_kind", "forests")
	for at in [Vector2(300, 200), Vector2(430, 170), Vector2(470, 280), Vector2(330, 300)]:
		await _click(at)
	_key(KEY_ENTER)
	await get_tree().process_frame

	editor.call("set_area_kind", "farms")
	for at in [Vector2(560, 180), Vector2(760, 200), Vector2(780, 330), Vector2(570, 320)]:
		await _click(at)
	_key(KEY_ENTER)
	await get_tree().process_frame

	editor.call("set_area_kind", "parks")
	for at in [Vector2(860, 210), Vector2(960, 220), Vector2(940, 300), Vector2(850, 290)]:
		await _click(at)
	_key(KEY_ENTER)
	await get_tree().process_frame

	# A row of stamped masses, one per form, so the whole vocabulary is in the frame.
	editor.call("set_tool", "stamp")
	var forms: Array = editor.call("shape_tool").call("forms")
	var x := 300.0
	var y := 430.0
	for form_value in forms:
		editor.call("shape_tool").call("set_form", str(form_value))
		await _drag_stamp(Vector2(x, y), Vector2(x + 74.0, y + 6.0))
		x += 96.0
		if x > 980.0:
			x = 300.0
			y += 120.0


## A row of each slot class, with one picked. Slots have no drawn art of their own — they
## reserve ground — so the only way to check they read as small-red and medium-blue, and that
## the picked one stands out, is to look at a frame with both classes in it.
func _demo_slots(editor: Node) -> void:
	# One of every class, left to right in ladder order, so a capture shows the whole set of
	# sizes and colours together rather than one at a time.
	var at := Vector2(340, 300)
	var picked := Vector2.ZERO
	for slot_class_value in AuthoredMapRef.SLOT_BOX_CLASSES:
		editor.call("pick_slot_class", str(slot_class_value))
		await _click(at)
		if str(slot_class_value) == "medium":
			picked = at
		at.x += 160.0
	# Pick one, so the frame shows the heavier outline a selected slot gets.
	editor.call("set_tool", "select")
	await _click(picked)


## One zone of each kind, so a capture shows all three colours together and proves the corner
## cap is the zone cap rather than the area one.
func _demo_zones(editor: Node) -> void:
	var boxes := [
		[Vector2(300, 200), Vector2(520, 190), Vector2(560, 330), Vector2(430, 380), Vector2(290, 320)],
		[Vector2(620, 200), Vector2(840, 190), Vector2(880, 330), Vector2(750, 380), Vector2(610, 320)],
		[Vector2(300, 440), Vector2(520, 430), Vector2(560, 570), Vector2(430, 620), Vector2(290, 560)],
	]
	var kinds: Array = AuthoredMapRef.ZONE_KINDS
	for i in kinds.size():
		editor.call("set_area_kind", "zone:%s" % str(kinds[i]))
		for at in boxes[i]:
			await _click(at)
		_key(KEY_ENTER)
		await get_tree().process_frame
	# Select the last one, so a capture shows the hatch a selected zone gets.
	if OS.get_environment("POE_EDITOR_SHOT_ZONE_PICK") == "1":
		editor.call("set_tool", "select")
		await _click(Vector2(340 + 160 * (AuthoredMapRef.ZONE_KINDS.size() - 1), 300))
	else:
		editor.call("toggle_deposit_marks")
	await get_tree().process_frame


## Lay the three primitives, resize one, and drag a corner of another — so a capture shows
## what the parameters and the handles actually do.
func _demo_special(editor: Node) -> void:
	editor.call("focus_tile", _tile, _zoom)
	await get_tree().process_frame
	var at := {"u": Vector2(360, 300), "ring": Vector2(620, 300), "l": Vector2(880, 300)}
	for kind in ["u", "ring", "l"]:
		editor.call("pick_special", kind)
		await _click(at[kind])
	# Grow the L's long arm, proving the parameter rebuild.
	for _i in 4:
		editor.call("adjust_special_side", 0, 20.0)
	await get_tree().process_frame
	# Select the ring and drag one of its corners, proving the handles.
	editor.call("set_tool", "select")
	await _drag_box(Vector2(520, 200), Vector2(730, 420))
	var corners: PackedVector2Array = editor.call("editable_corners")
	if corners.size() > 0:
		var camera: Camera2D = editor.call("camera")
		var viewport_size := get_viewport().get_visible_rect().size
		var screen: Vector2 = (corners[0] - camera.get_screen_center_position()) \
			* camera.zoom.x + viewport_size * 0.5
		await _drag_box(screen, screen + Vector2(-40, -46))
	print("[EDITOR-SHOT] specials: %d corners on show" % corners.size())


## Stamp a few masses and select two, so a capture shows the hatched selection.
func _demo_hatch(editor: Node) -> void:
	editor.call("focus_tile", _tile, _zoom)
	await get_tree().process_frame
	editor.call("set_tool", "stamp")
	var forms := ["square", "cross", "h", "shallow_e"]
	var x := 420.0
	for form in forms:
		editor.call("shape_tool").call("set_form", form)
		await _drag_stamp(Vector2(x, 380), Vector2(x + 80.0, 396.0))
		x += 130.0
	editor.call("pick_special", "ring")
	await _click(Vector2(560, 560))
	# Box-select the middle of the row, leaving the outer ones plain for contrast.
	editor.call("set_tool", "select")
	await _drag_box(Vector2(520, 330), Vector2(800, 430))


func _drag_box(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	Input.parse_input_event(down)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	Input.parse_input_event(up)
	await get_tree().process_frame


func _drag_stamp(from: Vector2, to: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	Input.parse_input_event(down)
	await get_tree().process_frame
	var motion := InputEventMouseMotion.new()
	motion.position = to
	motion.relative = to - from
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = to
	Input.parse_input_event(up)
	await get_tree().process_frame


func _click(at: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	Input.parse_input_event(down)
	await get_tree().process_frame
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	Input.parse_input_event(up)
	await get_tree().process_frame


func _key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)


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
