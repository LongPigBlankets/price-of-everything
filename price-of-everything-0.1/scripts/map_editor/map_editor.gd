extends Node
## The map editor shell — P0 of `docs/map-editor-plan.md`.
##
## EDITOR-ONLY. This directory is excluded from exported builds (`export_presets.cfg`),
## so NO SHIPPED SCRIPT MAY REFERENCE IT: a `preload` from shipped code resolves at parse
## time and would break the exported game. `main_menu.gd` reaches the editor by probing
## `ResourceLoader.exists()` and loading the scene by path string, never by symbol; the
## unit suite pins that (`_test_shipped_code_avoids_editor_only_paths`).
##
## It boots the real game world and draws on top of it, rather than reimplementing a map:
## the editor previews with the same renderers the bake and the game use, so preview,
## export and play cannot drift. (The browser Packing Lab taught the opposite lesson —
## constants ported by hand go stale.)
##
## P0 SCOPE: boot, camera, overlay toggles, document load/save, the undo stack, and the
## status readout. It authors nothing yet — the pen, stamp and slot tools are P1-P3. The
## gate for this phase is that it opens, draws no authored content, and leaves the game
## and the suite untouched.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredRoadGeometry := preload("res://scripts/authored_road_geometry.gd")
const MapEditorDocument := preload("res://scripts/map_editor/map_editor_document.gd")
const MapEditorOverlay := preload("res://scripts/map_editor/map_editor_overlay.gd")
const MapEditorRoadTool := preload("res://scripts/map_editor/map_editor_road_tool.gd")
const MapEditorLayers := preload("res://scripts/map_editor/map_editor_layers.gd")
const MapEditorStrokeEdit := preload("res://scripts/map_editor/map_editor_stroke_edit.gd")
const MapEditorTraceTool := preload("res://scripts/map_editor/map_editor_trace_tool.gd")
const MapEditorSelection := preload("res://scripts/map_editor/map_editor_selection.gd")
const MapEditorConfirm := preload("res://scripts/map_editor/map_editor_confirm.gd")
const MapEditorNameDialog := preload("res://scripts/map_editor/map_editor_name_dialog.gd")
const MapEditorLoadDialog := preload("res://scripts/map_editor/map_editor_load_dialog.gd")
const MapEditorShapeTool := preload("res://scripts/map_editor/map_editor_shape_tool.gd")
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const AuthoredSpecialShapes := preload("res://scripts/authored_special_shapes.gd")
const MapEditorRoadSnap := preload("res://scripts/map_editor/map_editor_road_snap.gd")
const AuthoredSlotSizes := preload("res://scripts/authored_slot_sizes.gd")
const MapEditorPanel := preload("res://scripts/map_editor/map_editor_panel.gd")

## Tools. NAVIGATE is the default and does nothing but move the view: an editor whose idle
## state authors geometry cannot be explored, and every stray click becomes a road.
const TOOL_PAN := "pan"
const TOOL_ROAD := "road"
## Click an existing road to insert a point, then drag it to bow BOTH adjacent segments.
const TOOL_ANCHOR := "anchor"
## Press and drag to trace a line; the path is simplified into an editable stroke.
const TOOL_TRACE := "trace"
## Click to drop dots, then click two of them to join with a straight run.
const TOOL_DOTS := "dots"
## Click a road to step it up a class; Shift-click steps it back down.
const TOOL_UPGRADE := "upgrade"
## Drag a box over content, then delete it behind a confirmation.
const TOOL_SELECT := "select"
## Click corners to outline a farm, wood or park; Enter closes it.
const TOOL_AREA := "area"
## Press and drag to stamp a decorative mass from the form vocabulary.
const TOOL_STAMP := "stamp"
## Click to lay a parametric primitive (U, ring or L) at its current side lengths.
const TOOL_SPECIAL := "special"
## Click to place an empty slot a gameplay building will later occupy.
const TOOL_SLOT := "slot"

## The box a slot of each class reserves, world units. Sized from the drawn art it must hold
## with room for its shadow and a little air, so a building dropped into one is not touching
## its neighbour.
const SLOT_BOXES := {"small": Vector2(62.0, 62.0), "medium": Vector2(96.0, 96.0)}

## How close a click must land to a corner to pick it up, in world units.
const CORNER_GRAB := 16.0

## Screen pixels of movement before a press on a shape becomes a MOVE rather than a click.
## In pixels rather than world units so the gesture feels the same at every zoom — the hand
## does not know what a world unit is.
const MOVE_THRESHOLD := 4.0

## Resize step for the +/- keys. Ten percent is small enough to converge on a size and large
## enough that a press is visibly worth making.
const RESIZE_STEP := 1.1

## Rotation step for the Z / Y keys. Five degrees is fine enough to line a building up with
## something and coarse enough to get there in a few presses.
const ROTATE_STEP := deg_to_rad(5.0)

## Which settlement new content joins. P1 authors into one at a time; the settlement picker
## arrives with the tools that need to move content between them.
const DEFAULT_SETTLEMENT := "untitled"

## Frames to let the world settle before framing the camera. The shot tools use 150 and
## the world build is ~20-30 s of coroutine work on this branch; the readout reports when
## the world is actually ready rather than leaving a blank screen.
const SETTLE_FRAMES := 150

## Editing zooms. Well inside the camera controller's own clamp, and chosen so one tile
## (540x480 u) fills a comfortable working area.
const START_ZOOM := 0.9
const ZOOM_MIN := 0.12
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.12

## WASD pan speed in SCREEN pixels per second. Divided by zoom before it moves the camera,
## so the map slides past at the same apparent rate whether you are looking at one tile or
## the whole coast — a world-unit speed would crawl when zoomed in and bolt when zoomed out.
const PAN_SPEED := 900.0
## Held Shift multiplier, for crossing the map rather than nudging along a street.
const PAN_FAST := 3.0
## Physical scancodes, so the keys stay under the same fingers on a non-QWERTY layout —
## WASD is a position on the keyboard, not four letters.
const PAN_KEYS := {
	KEY_W: Vector2(0.0, -1.0),
	KEY_S: Vector2(0.0, 1.0),
	KEY_A: Vector2(-1.0, 0.0),
	KEY_D: Vector2(1.0, 0.0),
}

# Typed through the const preloads above: an untyped `RefCounted` here makes every call
# return Variant, and `:=` inference then fails at parse time.
var _document: MapEditorDocument
var _overlay: MapEditorOverlay
var _road_tool: MapEditorRoadTool
var _trace_tool: MapEditorTraceTool
var _shape_tool: MapEditorShapeTool
var _layers: MapEditorLayers
## While the anchor tool has a point picked up: `{settlement, stroke, index}`.
var _anchor_grab: Dictionary = {}
var _confirm: MapEditorConfirm
var _name_dialog: MapEditorNameDialog
var _load_dialog: MapEditorLoadDialog
## Marquee in world units while dragging, and the records it caught.
var _marquee_from := Vector2.INF
var _marquee_to := Vector2.INF
var _selection: Array = []
## The record whose corners are on show, and which one is held. Corner editing works on any
## outline — a primitive, a farm, a wood, a park — because they are all polygons.
var _corner_target: Dictionary = {}
var _held_corner := -1
## The press-to-move-or-select gesture: what is under the cursor, where it started, and
## whether the pointer has travelled far enough to call it a drag.
var _grabbed: Array = []
var _grab_world := Vector2.INF
var _grab_screen := Vector2.INF
var _grab_moved := false
var _pending_hit: Dictionary = {}
## Set while a drag is held with Ctrl/Cmd down, which places exactly where the pointer is.
var _snap_suppressed := false
## The records last moved, so the snap can act on them after the drag ends.
var _moved_records: Array = []
var _special_kind := "u"
var _slot_class := "small"
var _panel: MapEditorPanel
var _tool := TOOL_PAN
var _world: Node
var _camera: Camera2D
var _status: Label
var _ready_to_edit := false
var _panning := false
var _settlement := DEFAULT_SETTLEMENT


## SCRATCH MODE, for capture and input harnesses. They drive the editor with synthetic
## clicks at computed positions, and a position that lands over the panel presses whatever
## button is there — which is how a harness silently saved its demo content into a real map
## and grew it by 49 records. In scratch mode the editor starts empty and can only ever
## write to a throwaway name, so a stray click cannot reach anyone's work.
const SCRATCH_NAME := "__scratch__"


func _is_scratch() -> bool:
	return OS.get_environment("POE_EDITOR_SCRATCH") == "1"


func _ready() -> void:
	if _is_scratch():
		# Point the loader at a name that does not exist, so nothing real is opened.
		AuthoredMap.set_override(SCRATCH_NAME)
	_document = MapEditorDocument.new()
	_road_tool = MapEditorRoadTool.new()
	_trace_tool = MapEditorTraceTool.new()
	_shape_tool = MapEditorShapeTool.new()
	_layers = MapEditorLayers.new()
	_build_chrome()
	_boot_world()


## Continuous panning has to be polled rather than driven by key events: an editor that
## moved one step per repeat would inherit the OS's repeat delay and rate, which is a typing
## setting, not a camera one.
func _process(delta: float) -> void:
	if not _ready_to_edit or _camera == null:
		return
	var direction := Vector2.ZERO
	for key in PAN_KEYS:
		if Input.is_physical_key_pressed(key):
			direction += PAN_KEYS[key] as Vector2
	if direction == Vector2.ZERO:
		return
	var speed := PAN_SPEED * (PAN_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.position += direction.normalized() * speed * delta / _camera.zoom.x


# ── Boot ────────────────────────────────────────────────────────────────────────

## Instantiate the real game scene as a child, then take its camera. This is the shot
## tools' recipe (`tools/tile_shot.gd`) with one deliberate difference: input stays
## ENABLED. Those tools call `set_disable_input(true)` because they only capture; an
## editor must receive the mouse.
func _boot_world() -> void:
	_set_status("Building the world…")
	var packed := load("res://scenes/main.tscn") as PackedScene
	if packed == null:
		_set_status("Could not load the map scene.")
		return
	_world = packed.instantiate()
	add_child(_world)
	# Draw order: the overlay must sit above every world layer. The world map uses sibling
	# order for layering and reserves z up to 90 (the parchment multiply), so the overlay
	# rides its own CanvasLayer instead of competing for a z_index.
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_hide_game_ui()
	_silence_world_input(_world)
	_take_camera()
	_layers.bind(_world)
	_panel.build(self, _layers)
	_ready_to_edit = true
	_refresh_status()


## Stop the GAME from consuming input while the editor is up.
##
## `camera_controller`, `hex_map` and `world_map` all run `_input`/`_unhandled_input`, and
## the world is a CHILD of this node, so they see every event first. That is why Escape
## never reached the editor and why dragging fought the pen: the game was still panning,
## picking tiles and claiming keys underneath. Disabling their processing is far more
## honest than trying to out-order them, and it leaves this node the single owner of input.
func _silence_world_input(node: Node) -> void:
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	node.set_process_shortcut_input(false)
	for child in node.get_children():
		_silence_world_input(child)


## Hide the HUD and the hover grid, leaving the map itself. `main.tscn`'s ROOT node is
## `WorldMap`, so these are direct children of the instantiated scene — not "WorldMap/…"
## paths. Looked up with `get_node_or_null` so a scene rename degrades to "chrome still
## visible" rather than a crash mid-session.
func _hide_game_ui() -> void:
	for node_name in ["UILayer", "HexGridOverlay"]:
		var node := _world.get_node_or_null(NodePath(node_name))
		if node != null and node is CanvasItem:
			(node as CanvasItem).visible = false
		elif node != null and node is CanvasLayer:
			(node as CanvasLayer).visible = false


## Take over the game camera. Its `_process` lerps toward `_target_zoom` and re-clamps to
## the map bounds every frame, so an editor that only writes `position`/`zoom` gets
## dragged back — the shot tools hit this too. Disabling its processing is the fix.
func _take_camera() -> void:
	_camera = get_viewport().get_camera_2d()
	if _camera == null:
		return
	_camera.set_process(false)
	_camera.set_physics_process(false)
	if "edge_pan_enabled" in _camera:
		_camera.set("edge_pan_enabled", false)
	_camera.zoom = Vector2(START_ZOOM, START_ZOOM)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)


# ── Chrome ──────────────────────────────────────────────────────────────────────

func _build_chrome() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 64   # above the world, below the debug terminal (128)
	add_child(layer)

	_overlay = MapEditorOverlay.new()
	_overlay.editor = self
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)

	_confirm = MapEditorConfirm.new()
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.confirmed.connect(_delete_selection)
	_confirm.cancelled.connect(func() -> void: _set_status("Deletion cancelled."))
	layer.add_child(_confirm)

	_name_dialog = MapEditorNameDialog.new()
	_name_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_name_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_name_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_name_dialog.accepted.connect(_save_as)
	_name_dialog.cancelled.connect(func() -> void: _set_status("Save cancelled."))
	layer.add_child(_name_dialog)

	_load_dialog = MapEditorLoadDialog.new()
	_load_dialog.set_anchors_preset(Control.PRESET_CENTER)
	_load_dialog.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_load_dialog.grow_vertical = Control.GROW_DIRECTION_BOTH
	_load_dialog.chosen.connect(_load_named)
	_load_dialog.cancelled.connect(func() -> void: _set_status("Load cancelled."))
	layer.add_child(_load_dialog)

	_panel = MapEditorPanel.new()
	_panel.anchor_top = 0.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = 8.0
	_panel.offset_top = 44.0
	_panel.offset_bottom = -8.0
	layer.add_child(_panel)

	var bar := PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.06, 0.85)
	bar.add_theme_stylebox_override("panel", style)
	layer.add_child(bar)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	bar.add_child(margin)

	_status = Label.new()
	_status.add_theme_color_override("font_color", Color(0.75, 0.95, 0.8))
	margin.add_child(_status)
	_set_status("Starting…")


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = "MAP EDITOR   %s" % text
	if _panel != null:
		_panel.set_status(text)


func _refresh_status() -> void:
	var counts := _document.counts()
	_set_status("%s   |   %d settlements · %d roads · %d masses   |   %s"
		% [_document.display_name(), counts.settlements, counts.roads, counts.masses,
			"UNSAVED" if _document.is_dirty() else "saved"])
	if _panel != null:
		_panel.refresh()


# ── Input ───────────────────────────────────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_to_edit:
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _panning and _camera != null:
			# Drag the world under the cursor: screen delta / zoom is the world delta.
			_camera.position -= motion.relative / _camera.zoom.x
		elif _tool == TOOL_TRACE and _trace_tool.is_tracing():
			_trace_tool.extend_trace(_world_at(motion.position))
			_overlay.queue_redraw()
		elif _tool == TOOL_SELECT and _held_corner >= 0:
			_move_corner(_world_at(motion.position))
		elif _tool == TOOL_SELECT and not _grabbed.is_empty():
			# Ctrl, or Cmd on macOS, places exactly where the pointer is.
			_snap_suppressed = motion.ctrl_pressed or motion.meta_pressed
			_drag_grabbed(motion.position)
		elif _tool == TOOL_STAMP and _shape_tool.is_stamping():
			_shape_tool.drag_stamp(_world_at(motion.position))
			_overlay.queue_redraw()
		elif _tool == TOOL_SELECT and _marquee_from != Vector2.INF:
			_marquee_to = _world_at(motion.position)
			_overlay.queue_redraw()
		elif _tool == TOOL_ANCHOR and not _anchor_grab.is_empty():
			# Live reshaping: the curve follows the pointer, so the bend is judged against
			# the map rather than guessed and corrected.
			MapEditorStrokeEdit.shape_anchor(_anchor_grab["stroke"] as Dictionary,
				int(_anchor_grab["index"]), _world_at(motion.position))
			_overlay.queue_redraw()
	elif event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event as InputEventKey)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			var world := _world_at(event.position)
			match _tool:
				# In NAVIGATE the left button drags the view. Only the drawing tools author,
				# so an idle click can never leave geometry behind.
				TOOL_PAN:
					_panning = event.pressed
				TOOL_ROAD:
					if event.double_click and _road_tool.is_drawing():
						_finish_stroke()
					elif event.pressed:
						# Alt places a raw point, bypassing the junction snap.
						_road_tool.press(world,
							MapEditorRoadTool.snap_targets(_document.data()), not event.alt_pressed)
					else:
						_road_tool.release(world)
				TOOL_ANCHOR:
					if event.pressed:
						_anchor_press(world)
					else:
						_anchor_grab = {}
				TOOL_TRACE:
					if event.pressed:
						_trace_tool.begin_trace(world)
					else:
						_finish_trace()
				TOOL_DOTS:
					if event.pressed:
						_dot_press(world)
				TOOL_UPGRADE:
					if event.pressed:
						_upgrade_press(world, not event.shift_pressed)
				TOOL_AREA:
					if event.pressed:
						var refused := _shape_tool.add_point(world)
						if refused != "":
							_set_status(refused)
				TOOL_STAMP:
					if event.pressed:
						_shape_tool.begin_stamp(world)
					else:
						_finish_stamp()
				TOOL_SPECIAL:
					if event.pressed:
						_place_special(world)
				TOOL_SLOT:
					if event.pressed:
						_place_slot(world)
				TOOL_SELECT:
					if event.pressed:
						_select_press(world, event.position)
					else:
						_select_release(world)
		MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT:
			# Always available, whatever the tool: panning mid-stroke is normal when a road
			# runs off the edge of the view.
			_panning = event.pressed
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_zoom_by(ZOOM_STEP, event.position)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_zoom_by(1.0 / ZOOM_STEP, event.position)


func _handle_key(event: InputEventKey) -> void:
	# The confirmation is modal — while it is up, Enter and Escape belong to it and nothing
	# else may act. Anything less makes Escape ambiguous at exactly the wrong moment.
	if _load_dialog != null and _load_dialog.is_open():
		if event.keycode == KEY_ESCAPE:
			_load_dialog.close()
			_set_status("Load cancelled.")
			_refresh_status()
		return
	if _name_dialog != null and _name_dialog.is_open():
		# The field owns typing while it is open; only Escape is taken from it here, and
		# Enter is handled by the field's own submit.
		if event.keycode == KEY_ESCAPE:
			_name_dialog.close()
			_set_status("Save cancelled.")
			_refresh_status()
		return
	if _confirm != null and _confirm.is_open():
		if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
			_confirm.close()
			_delete_selection()
		elif event.keycode == KEY_ESCAPE:
			_confirm.close()
			_set_status("Deletion cancelled.")
		_refresh_status()
		return
	match event.keycode:
		KEY_F5:
			_save()
		KEY_F6:
			_reload()
		KEY_V:
			set_tool(TOOL_PAN)
		KEY_R:
			set_tool(TOOL_ROAD)
		KEY_T:
			set_tool(TOOL_ANCHOR)
		KEY_F:
			set_tool(TOOL_TRACE)
		KEY_C:
			set_tool(TOOL_DOTS)
		KEY_U:
			set_tool(TOOL_UPGRADE)
		KEY_X:
			set_tool(TOOL_SELECT)
		KEY_B:
			set_tool(TOOL_STAMP)
		KEY_N:
			set_tool(TOOL_AREA)
		KEY_M:
			set_tool(TOOL_SPECIAL)
		KEY_K:
			set_tool(TOOL_SLOT)
		KEY_Z:
			_rotate_selection(ROTATE_STEP)
		KEY_Y:
			_rotate_selection(-ROTATE_STEP)
		KEY_EQUAL, KEY_KP_ADD:
			_resize_selection(RESIZE_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_resize_selection(1.0 / RESIZE_STEP)
		KEY_BRACKETLEFT:
			_set_status("Form: %s" % _shape_tool.cycle_form(-1))
			_overlay.queue_redraw()
		KEY_BRACKETRIGHT:
			_set_status("Form: %s" % _shape_tool.cycle_form(1))
			_overlay.queue_redraw()
		KEY_DELETE:
			_ask_delete()
		KEY_G:
			toggle_grid()
		KEY_H:
			toggle_water_mask()
		KEY_E:
			_zoom_by(ZOOM_STEP)
		KEY_Q:
			_zoom_by(1.0 / ZOOM_STEP)
		KEY_1:
			set_road_class("major")
		KEY_2:
			set_road_class("mid")
		KEY_3:
			set_road_class("minor")
		KEY_ENTER, KEY_KP_ENTER:
			if _tool == TOOL_AREA:
				_finish_area()
			else:
				_finish_stroke()
		KEY_BACKSPACE:
			if _tool == TOOL_AREA:
				_shape_tool.undo_point()
			elif _tool == TOOL_DOTS:
				_trace_tool.undo_dot()
			else:
				_road_tool.undo_point()
			_overlay.queue_redraw()
		KEY_ESCAPE:
			# Escape abandons work in progress first; only an idle Escape leaves. Dots count
			# as work in progress: clearing them is what "cancel" means for that tool.
			if not _selection.is_empty():
				_selection = []
				_overlay.queue_redraw()
				_set_status("Selection cleared.")
				_refresh_status()
				return
			if _road_tool.is_drawing() or _trace_tool.is_tracing() \
					or not _trace_tool.dots().is_empty():
				_road_tool.abandon()
				_trace_tool.cancel_trace()
				_trace_tool.clear_dots()
				_overlay.queue_redraw()
				_refresh_status()
				return
			_leave()
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				var outcome := _document.redo() if event.shift_pressed else _document.undo()
				_set_status(outcome)
				await get_tree().process_frame
				_refresh_status()


## Zoom about the CURSOR, not the screen centre: in an editor you zoom in on the junction
## you are about to draw, and a centre-anchored zoom slides it out of view exactly when you
## are trying to get closer to it. The world point under the pointer is pinned by moving the
## camera to compensate — the same thing the game's own controller does for the player.
## `anchor` is a screen position; the keyboard path passes the viewport centre, which makes
## it behave like a plain zoom.
func _zoom_by(factor: float, anchor: Vector2 = Vector2.INF) -> void:
	if _camera == null:
		return
	var screen_anchor := anchor
	if screen_anchor == Vector2.INF:
		screen_anchor = get_viewport().get_visible_rect().size * 0.5
	var before := _world_at(screen_anchor)
	var z := clampf(_camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	_camera.position += before - _world_at(screen_anchor)


# ── Authoring ───────────────────────────────────────────────────────────────────

## World position under a screen point. The inverse of the overlay's projection, and the
## reason the editor drives the camera directly rather than letting the controller lerp:
## a moving camera would put the click somewhere the designer did not aim.
func _world_at(screen: Vector2) -> Vector2:
	if _camera == null:
		return screen
	var viewport_size := get_viewport().get_visible_rect().size
	return _camera.get_screen_center_position() + (screen - viewport_size * 0.5) / _camera.zoom.x


## Commit the stroke being drawn into the document, under the current settlement.
func _finish_stroke() -> void:
	if not _road_tool.is_drawing():
		return
	var terrain := get_tree().get_first_node_in_group("hex_map")
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var stroke := _road_tool.finish(_settlement, next_id, terrain)
	if stroke.is_empty():
		_set_status("Stroke discarded — too short to keep.")
		_overlay.queue_redraw()
		return
	# begin_edit snapshots first, so this is undoable like every other mutation.
	_document.begin_edit("draw road")
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var roads: Array = settlement.get("roads", []) as Array
	roads.append(stroke)
	settlement["roads"] = roads
	# The settlement's tile list is the suppression key: a tile only stands its procedural
	# systems down once something authored actually sits on it.
	var tiles: Array = settlement.get("tiles", []) as Array
	for tile_id in (stroke.get("tiles", []) as Array):
		if not tiles.has(tile_id):
			tiles.append(tile_id)
	tiles.sort()
	settlement["tiles"] = tiles
	_overlay.queue_redraw()
	_report_stroke(stroke)


## ADD ANCHOR. A press either picks up an existing point of the stroke under the cursor, or
## inserts a new one there. Inserting alone never changes the road's shape — the new point is
## a plain corner sitting exactly on the line it was inserted into — so the curve is entirely
## the product of the drag that follows, which is what makes the gesture predictable.
func _anchor_press(world: Vector2) -> void:
	var found := MapEditorStrokeEdit.stroke_at(_document.data(), world)
	if found.is_empty():
		_set_status("No road under the cursor.")
		return
	var stroke: Dictionary = found["stroke"]
	# One snapshot for the whole grab: the drag that follows mutates in place, so undo steps
	# back to before the anchor appeared rather than through every frame of the drag.
	_document.begin_edit("shape road")
	var existing := MapEditorStrokeEdit.point_at(stroke, world, MapEditorStrokeEdit.HIT_MIN)
	var index := existing
	if index < 0:
		index = MapEditorStrokeEdit.insert_anchor(stroke,
			MapEditorStrokeEdit.anchor_slot(stroke, world))
	if index < 0:
		_set_status("Could not place an anchor there.")
		return
	_anchor_grab = {"stroke": stroke, "index": index}
	_set_status("Drag to curve both segments%s." % ("" if existing < 0 else " (existing point)"))


## UPGRADE. One click steps the road under the cursor up a class; Shift-click steps it back.
func _upgrade_press(world: Vector2, up: bool) -> void:
	var found := MapEditorStrokeEdit.stroke_at(_document.data(), world)
	if found.is_empty():
		_set_status("No road under the cursor.")
		return
	var stroke: Dictionary = found["stroke"]
	var was := str(stroke.get("class", "mid"))
	_document.begin_edit("change road class")
	var now := MapEditorStrokeEdit.step_class(stroke, up)
	if now == "":
		_set_status("Already %s — %s." % [was, "the widest class" if up else "the narrowest class"])
		return
	# The stroke's drawn geometry is unchanged, but its width is not, so the runtime cache
	# keyed by id would otherwise keep the old look.
	_set_status("%s → %s" % [was, now])


## SELECT. Close the marquee and record what it caught.
func _finish_marquee(world: Vector2) -> void:
	if _marquee_from == Vector2.INF:
		return
	_marquee_to = world
	var rect := Rect2(_marquee_from, Vector2.ZERO).expand(_marquee_to)
	var dragged := rect.size.length() * (_camera.zoom.x if _camera != null else 1.0)
	_marquee_from = Vector2.INF
	_marquee_to = Vector2.INF
	if dragged < MapEditorSelection.MIN_DRAG:
		# A click, not a box: clear rather than select nothing, so clicking empty ground is
		# the natural way to drop a selection.
		_selection = []
		_set_status("Selection cleared.")
		_overlay.queue_redraw()
		return
	_selection = MapEditorSelection.in_rect(_document.data(), rect)
	# Exactly one outline-shaped thing selected: show its corners, since that is the only
	# case where "drag a corner" has an unambiguous subject.
	var single := MapEditorSelection.single_outline(_document.data(), _selection)
	_set_corner_target(single)
	_set_status("%d selected%s — Delete to remove." % [_selection.size(),
		" · drag its corners" if not single.is_empty() else ""] if not _selection.is_empty()
		else "Nothing in the box.")
	_overlay.queue_redraw()


## Ask before removing. Deletion is the one action here that destroys authored work, and the
## marquee makes it easy to catch more than intended.
func _ask_delete() -> void:
	if _selection.is_empty():
		_set_status("Nothing selected.")
		return
	_confirm.ask("Delete %d selected item%s?" % [_selection.size(),
		"" if _selection.size() == 1 else "s"])
	_panel.refresh()


func _delete_selection() -> void:
	if _selection.is_empty():
		return
	_document.begin_edit("delete selection")
	var removed := MapEditorSelection.delete(_document.data(), _selection)
	_selection = []
	_overlay.queue_redraw()
	_set_status("Deleted %d item%s." % [removed, "" if removed == 1 else "s"])


## CONNECT THE DOTS. Dots live outside the document until two are joined; the join is what
## produces a stroke.
func _dot_press(world: Vector2) -> void:
	var link := _trace_tool.click_dot(world)
	if link.is_empty():
		var pending := _trace_tool.pending_dot()
		_set_status("Dot armed — click another to join." if pending >= 0
			else "Dot placed (%d)." % _trace_tool.dots().size())
		return
	_commit_points(link, "connect dots")


## FREEHAND. The traced path is simplified before it becomes a stroke — see the tool's
## header for why a recording of the gesture would be useless as an object.
func _finish_trace() -> void:
	var points := _trace_tool.end_trace()
	if points.is_empty():
		_set_status("Trace too short to keep.")
		return
	_commit_points(points, "trace road")


## Turn a bare point list into a stroke and put it in the document, with the same
## tile-touch, unlockable and bridge treatment a penned stroke gets. Shared so the three
## drawing tools cannot drift apart in what they record.
func _commit_points(points: Array, label: String) -> void:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var stroke := _road_tool.build_stroke(points, _settlement, next_id, terrain)
	if stroke.is_empty():
		_set_status("Stroke discarded — too short to keep.")
		return
	_document.begin_edit(label)
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var roads: Array = settlement.get("roads", []) as Array
	roads.append(stroke)
	settlement["roads"] = roads
	var tiles: Array = settlement.get("tiles", []) as Array
	for tile_id in (stroke.get("tiles", []) as Array):
		if not tiles.has(tile_id):
			tiles.append(tile_id)
	tiles.sort()
	settlement["tiles"] = tiles
	_overlay.queue_redraw()
	_report_stroke(stroke)


func _report_stroke(stroke: Dictionary) -> void:
	var wet := _wet_length(stroke)
	var note := "%s road, %d tiles%s" % [
		str(stroke.get("class", "")),
		(stroke.get("tiles", []) as Array).size(),
		", UNLOCKABLE" if bool(stroke.get("unlockable", false)) else "",
	]
	if not (stroke.get("bridges", []) as Array).is_empty():
		note += ", %d bridge(s)" % (stroke.get("bridges", []) as Array).size()
	if wet > 0.0:
		# The lint that matters most: a road drawn over sea or lake. Reported rather than
		# refused — the designer may be mid-stroke on a causeway — but never silent.
		note += "   ⚠ %d sample(s) OVER WATER" % int(wet)
	_set_status(note)


func _wet_length(stroke: Dictionary) -> float:
	var centreline := AuthoredRoadGeometry.sample(stroke)
	return float(AuthoredRoadGeometry.wet_samples(centreline, NavGrid.instance()).size())


## The settlement new content joins, created on first use.
func _ensure_settlement() -> Dictionary:
	var doc := _document.data()
	var settlements_value: Variant = doc.get("settlements", {})
	var settlements: Dictionary = settlements_value if typeof(settlements_value) == TYPE_DICTIONARY else {}
	if not settlements.has(_settlement):
		settlements[_settlement] = {"tiles": [], "next_id": 1, "roads": []}
	doc["settlements"] = settlements
	return settlements[_settlement]


## Close the outline being drawn into a farm, wood or park.
func _finish_area() -> void:
	if not _shape_tool.is_drawing():
		return
	var settlement := _ensure_settlement()
	var kind := _shape_tool.kind()
	var next_id := int(settlement.get("next_id", 1))
	var record := _shape_tool.finish_polygon(_settlement, next_id)
	if record.is_empty():
		_set_status("Needs at least three corners.")
		_overlay.queue_redraw()
		return
	_document.begin_edit("draw %s" % kind)
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var items: Array = settlement.get(kind, []) as Array
	items.append(record)
	settlement[kind] = items
	_cover_tiles_of(settlement, record.get("outline", []) as Array)
	_overlay.queue_redraw()
	_set_status("%s placed (%d corners)." % [kind.trim_suffix("s").capitalize(),
		(record.get("outline", []) as Array).size()])


## Commit the mass being dragged.
func _finish_stamp() -> void:
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var record := _shape_tool.finish_stamp(_settlement, next_id)
	_overlay.queue_redraw()
	if record.is_empty():
		_set_status("Too small to stamp.")
		return
	_document.begin_edit("stamp mass")
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var items: Array = settlement.get("decor", []) as Array
	items.append(record)
	settlement["decor"] = items
	_cover_tiles_of(settlement, [record.get("pos", [0, 0])])
	_overlay.queue_redraw()
	_set_status("Stamped %s." % str(record.get("form", "")))


## Add the tiles a set of world points falls on to the settlement's coverage. Ground and
## fabric suppress procedural content the same way roads do, so they have to declare their
## tiles too — a mass drawn on an unlisted tile would sit on top of the procedural fabric
## rather than replacing it.
func _cover_tiles_of(settlement: Dictionary, points: Array) -> void:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return
	var tiles: Array = settlement.get("tiles", []) as Array
	var all_tiles: Dictionary = terrain.get("tiles")
	for entry in points:
		var values: Array = entry as Array
		if values == null or values.size() < 2:
			continue
		var world := Vector2(float(values[0]), float(values[1]))
		var coord: Vector2i = terrain.call("tile_coord_for_map_coord",
			terrain.call("local_to_map", world))
		if not all_tiles.has(coord):
			continue
		var tile_id := str((all_tiles[coord] as Dictionary).get("id", ""))
		if tile_id != "" and not tiles.has(tile_id):
			tiles.append(tile_id)
	tiles.sort()
	settlement["tiles"] = tiles


# ── Parametric primitives and corner editing ───────────────────────────────────

## Lay a primitive at its current side lengths.
func _place_special(world: Vector2) -> void:
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var record := AuthoredSpecialShapes.record(
		"s:%s:%d" % [_settlement, next_id], _special_kind, world, _special_sides())
	if record.is_empty():
		_set_status("Could not build that primitive.")
		return
	_document.begin_edit("place %s" % _special_kind)
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var items: Array = settlement.get("specials", []) as Array
	items.append(record)
	settlement["specials"] = items
	_cover_tiles_of(settlement, record.get("outline", []) as Array)
	# Laying one selects it, so its parameters and corners are immediately to hand.
	_corner_target = record
	_overlay.queue_redraw()
	_set_status("Placed %s — switch to Select (X) to drag its corners." % _special_kind)


# ── Select: drag to move, click to select ──────────────────────────────────────
#
# One press does three different things depending on what is under it, in this order: a
# corner handle of the shape already being edited, a shape (which then moves or selects), or
# empty ground (which starts a marquee). Ordered so the most specific target wins — a corner
# handle sits on top of its own shape, and grabbing the shape instead would make handles
# unusable.

func _select_press(world: Vector2, screen: Vector2) -> void:
	_held_corner = _corner_at(world)
	if _held_corner >= 0:
		_document.begin_edit("move corner")
		return
	var hit := MapEditorSelection.at_point(_document.data(), world)
	if hit.is_empty():
		_marquee_from = world
		_marquee_to = world
		return
	# Dragging something already in the selection moves the WHOLE selection; dragging
	# something outside it moves just that thing. Anything else makes multi-select useless
	# for arranging, which is most of what it is for.
	var in_selection := false
	for entry_value in _selection:
		if str((entry_value as Dictionary).get("id", "")) == str(hit.get("id", "")):
			in_selection = true
	_grabbed = _records_of(_selection) if in_selection else [hit["record"]]
	_grab_world = world
	_grab_screen = screen
	_grab_moved = false
	# Recorded whether or not it was already selected: a click that never becomes a drag
	# selects exactly what was under it, collapsing a multi-selection to that one thing.
	# Only remembering it for unselected shapes meant clicking a member of a selection did
	# nothing at all, which reads as the click having missed.
	_pending_hit = hit


func _drag_grabbed(screen: Vector2) -> void:
	if _grab_screen.distance_to(screen) < MOVE_THRESHOLD and not _grab_moved:
		return
	if not _grab_moved:
		# Snapshot once, at the moment it becomes a move — so undo steps back to before the
		# drag rather than through every frame of it.
		_document.begin_edit("move")
		_grab_moved = true
		_moved_records = _grabbed.duplicate()
	var world := _world_at(screen)
	var delta := world - _grab_world
	_grab_world = world
	for record in _grabbed:
		MapEditorSelection.translate(record as Dictionary, delta)
	_overlay.queue_redraw()


func _select_release(world: Vector2) -> void:
	if _held_corner >= 0:
		_held_corner = -1
		_overlay.queue_redraw()
		return
	if not _grabbed.is_empty():
		var moved := _grab_moved
		var hit := _pending_hit
		_grabbed = []
		_pending_hit = {}
		_grab_world = Vector2.INF
		_grab_screen = Vector2.INF
		_grab_moved = false
		if moved:
			var snapped := 0
			if not _snap_suppressed:
				snapped = _snap_moved_to_roads()
			_set_status("Moved %d item%s%s." % [
				_selection.size() if _selection.size() > 1 else 1,
				"" if _selection.size() <= 1 else "s",
				"" if snapped == 0 else " — %d snapped to a road" % snapped])
			_refresh_status()
			return
		# A press that never travelled is a CLICK: select what was under it, and open its
		# editable properties if it has any.
		if not hit.is_empty():
			_selection = [{"kind": hit["kind"], "settlement": hit["settlement"],
				"index": hit["index"], "id": hit["id"]}]
			var record: Dictionary = hit["record"]
			# Masses expose their parcel corners too, so a rectangle can be pulled into an
			# irregular quad and the form re-fitted into it.
			_set_corner_target(record if MapEditorSelection.corner_field(record) != "" else {})
			_set_status("Selected %s%s." % [str(hit["kind"]).trim_suffix("s"),
				" — drag its corners, or adjust its sides" if record.has("sides")
				else (" — drag its corners" if record.has("outline") else "")])
			_refresh_status()
		return
	_finish_marquee(world)


## Seat everything just moved against a nearby road. Applied on RELEASE rather than during
## the drag: a shape that snapped every frame would jump out from under the pointer and
## fight the hand. Roads themselves are skipped — a road does not stand beside a road.
func _snap_moved_to_roads() -> int:
	var snapped := 0
	for record_value in _moved_records:
		var record: Dictionary = record_value
		if not (record.has("outline") or record.has("form")):
			continue
		var seat := MapEditorRoadSnap.seat_for(_document.data(), record)
		if seat.is_empty():
			continue
		var centre := MapEditorSelection.centre_of(record)
		MapEditorSelection.rotate_about(record, centre, float(seat["angle"]))
		# Re-measured after the turn: rotating changes how deep the shape is across the road.
		var reseat := MapEditorRoadSnap.seat_for(_document.data(), record)
		var target: Vector2 = reseat.get("position", seat["position"])
		MapEditorSelection.translate(record, target - MapEditorSelection.centre_of(record))
		snapped += 1
	_moved_records = []
	_overlay.queue_redraw()
	return snapped


## Turn the selection about each shape's own centre. Clockwise on screen is a POSITIVE
## angle here, because Y runs down.
func _rotate_selection(angle: float) -> void:
	var records := _records_of(_selection)
	if records.is_empty():
		_set_status("Nothing selected — click a shape first.")
		return
	_document.begin_edit("rotate")
	for record_value in records:
		var record: Dictionary = record_value
		MapEditorSelection.rotate_about(record, MapEditorSelection.centre_of(record), angle)
	_overlay.queue_redraw()
	_set_status("Rotated %d item%s %s 5°." % [records.size(), "" if records.size() == 1 else "s",
		"clockwise" if angle > 0.0 else "anticlockwise"])
	_refresh_status()


## Grow or shrink the selection about each shape's own centre.
func _resize_selection(factor: float) -> void:
	var records := _records_of(_selection)
	if records.is_empty():
		_set_status("Nothing selected — click a shape first.")
		return
	_document.begin_edit("resize")
	var changed := 0
	for record_value in records:
		if MapEditorSelection.scale_record(record_value as Dictionary, factor):
			changed += 1
	_overlay.queue_redraw()
	_set_status("Resized %d item%s to %d%%%s." % [changed, "" if changed == 1 else "s",
		int(round(factor * 100.0)),
		"" if changed == records.size() else " (roads have a class, not a size)"])
	_refresh_status()


## The live records behind a selection, so a move can mutate them in place.
func _records_of(selection: Array) -> Array:
	var out: Array = []
	var settlements: Dictionary = _document.data().get("settlements", {})
	for entry_value in selection:
		var entry: Dictionary = entry_value
		var settlement: Dictionary = settlements.get(str(entry.get("settlement", "")), {})
		var items: Array = settlement.get(str(entry.get("kind", "")), []) as Array
		var index := int(entry.get("index", -1))
		if index >= 0 and index < items.size():
			out.append(items[index])
	return out


## The corners currently on show, in world units.
func editable_corners() -> PackedVector2Array:
	var field := MapEditorSelection.corner_field(_corner_target)
	if field == "":
		return PackedVector2Array()
	# A stamped mass has no stored corners until one is dragged; show the box its form sits
	# in so there is something to grab.
	if field == "parcel" and not _corner_target.has("parcel"):
		return AuthoredFabricPainter.mass_parcel(_corner_target)
	var out := PackedVector2Array()
	for entry in (_corner_target.get(field, []) as Array):
		var values: Array = entry as Array
		if values != null and values.size() >= 2:
			out.append(Vector2(float(values[0]), float(values[1])))
	return out


func held_corner() -> int:
	return _held_corner


func _corner_at(world: Vector2) -> int:
	var corners := editable_corners()
	var best := -1
	var best_distance := CORNER_GRAB
	for i in corners.size():
		var distance := corners[i].distance_to(world)
		# Strictly closer, so if two corners ever coincide the earlier one wins rather than
		# the later shadowing it — the defect that made ring corners undraggable.
		if distance < best_distance:
			best_distance = distance
			best = i
	return best


## Move the held corner. The outline is the truth once a corner has been dragged, so this
## edits it directly rather than trying to solve back to side lengths — a shape reshaped by
## hand and a shape defined by three numbers cannot both be true at once.
func _move_corner(world: Vector2) -> void:
	var field := MapEditorSelection.corner_field(_corner_target)
	if field == "":
		return
	MapEditorSelection.ensure_corners(_corner_target)
	var corners: Array = _corner_target.get(field, []) as Array
	if _held_corner < 0 or _held_corner >= corners.size():
		return
	corners[_held_corner] = [world.x, world.y]
	_corner_target[field] = corners
	_overlay.queue_redraw()


## Show a record's corners. Called when a selection resolves to exactly one outline-shaped
## thing; more than one and there is no single shape to edit.
func _set_corner_target(record: Dictionary) -> void:
	_corner_target = record
	_held_corner = -1
	_overlay.queue_redraw()


# ── Gameplay building slots ────────────────────────────────────────────────────

## Place an empty slot. It holds NOTHING until a building arrives — at game start, from an
## NPC, or from the player — and every one of those routes lands through the same placement
## call, so one seam serves all three.
##
## Slots are stored TILE-CENTRE-RELATIVE, because that is the frame the placement pipeline
## works in (`center_rel`, `TILE_CENTER`). Storing world coordinates would mean converting on
## every read and drifting the day a tile's origin moves.
func _place_slot(world: Vector2) -> void:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return
	var coord: Vector2i = terrain.call("tile_coord_for_map_coord", terrain.call("local_to_map", world))
	var tiles: Dictionary = terrain.get("tiles")
	if not tiles.has(coord):
		_set_status("Not on a tile.")
		return
	var tile_id := str((tiles[coord] as Dictionary).get("id", ""))
	var centre: Vector2 = terrain.call("map_to_local", terrain.call("map_coord_for_tile_coord", coord))
	var settlement := _ensure_settlement()
	_document.begin_edit("place slot")
	settlement = _ensure_settlement()
	var slots_value: Variant = settlement.get("slots", {})
	var slots: Dictionary = slots_value if typeof(slots_value) == TYPE_DICTIONARY else {}
	var tile_value: Variant = slots.get(tile_id, {})
	var tile_slots: Dictionary = tile_value if typeof(tile_value) == TYPE_DICTIONARY else {}
	var pins: Array = tile_slots.get("pins", []) as Array
	# Angle from the nearest authored road, so a slot faces its street without a second step.
	var angle := _slot_angle_at(world)
	pins.append({"pos": [world.x - centre.x, world.y - centre.y], "angle": angle,
		"size": _slot_class})
	tile_slots["pins"] = pins
	slots[tile_id] = tile_slots
	settlement["slots"] = slots
	var tile_list: Array = settlement.get("tiles", []) as Array
	if not tile_list.has(tile_id):
		tile_list.append(tile_id)
		tile_list.sort()
		settlement["tiles"] = tile_list
	_overlay.queue_redraw()
	_set_status("%s slot on %s (%d there)." % [_slot_class.capitalize(), tile_id, pins.size()])


## The facing for a slot: along the nearest authored road, or zero when there is none near.
func _slot_angle_at(world: Vector2) -> float:
	var probe := {"outline": [[world.x - 20.0, world.y - 20.0], [world.x + 20.0, world.y - 20.0],
		[world.x + 20.0, world.y + 20.0], [world.x - 20.0, world.y + 20.0]]}
	var seat := MapEditorRoadSnap.seat_for(_document.data(), probe)
	return float(seat.get("angle", 0.0)) if not seat.is_empty() else 0.0


func current_slot_class() -> String:
	return _slot_class


func pick_slot_class(value: String) -> void:
	_slot_class = value
	if _tool != TOOL_SLOT:
		set_tool(TOOL_SLOT)
	else:
		_refresh_status()


## Every slot in the document as world-space boxes, for the overlay.
func slot_boxes() -> Array:
	var out: Array = []
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return out
	for key in AuthoredMap.settlements().keys():
		var settlement: Dictionary = AuthoredMap.settlements()[key]
		var slots_value: Variant = settlement.get("slots", {})
		if typeof(slots_value) != TYPE_DICTIONARY:
			continue
		for tile_id in (slots_value as Dictionary).keys():
			var coord: Vector2i = terrain.call("id_to_coord", str(tile_id))
			if not (terrain.get("tiles") as Dictionary).has(coord):
				continue
			var centre: Vector2 = terrain.call("map_to_local",
				terrain.call("map_coord_for_tile_coord", coord))
			var tile_slots: Dictionary = (slots_value as Dictionary)[tile_id]
			for pin_value in (tile_slots.get("pins", []) as Array):
				var pin: Dictionary = pin_value
				var pos: Array = pin.get("pos", [0, 0]) as Array
				if pos.size() < 2:
					continue
				out.append({
					"centre": centre + Vector2(float(pos[0]), float(pos[1])),
					"angle": float(pin.get("angle", 0.0)),
					"size": SLOT_BOXES.get(str(pin.get("size", "small")), SLOT_BOXES["small"]),
					"class": str(pin.get("size", "small")),
				})
	return out


## The editor's own document may hold slots the loader has not seen; read from it directly.
func document_slot_boxes() -> Array:
	var saved := AuthoredMap.settlements()
	var live: Dictionary = _document.data().get("settlements", {})
	if live.is_empty() or saved == live:
		return slot_boxes()
	return _boxes_from(live)


func _boxes_from(settlements: Dictionary) -> Array:
	var out: Array = []
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return out
	for key in settlements.keys():
		var settlement: Dictionary = settlements[key]
		var slots_value: Variant = settlement.get("slots", {})
		if typeof(slots_value) != TYPE_DICTIONARY:
			continue
		for tile_id in (slots_value as Dictionary).keys():
			var coord: Vector2i = terrain.call("id_to_coord", str(tile_id))
			if not (terrain.get("tiles") as Dictionary).has(coord):
				continue
			var centre: Vector2 = terrain.call("map_to_local",
				terrain.call("map_coord_for_tile_coord", coord))
			for pin_value in (((slots_value as Dictionary)[tile_id] as Dictionary)
					.get("pins", []) as Array):
				var pin: Dictionary = pin_value
				var pos: Array = pin.get("pos", [0, 0]) as Array
				if pos.size() < 2:
					continue
				out.append({
					"centre": centre + Vector2(float(pos[0]), float(pos[1])),
					"angle": float(pin.get("angle", 0.0)),
					"size": SLOT_BOXES.get(str(pin.get("size", "small")), SLOT_BOXES["small"]),
					"class": str(pin.get("size", "small")),
				})
	return out


func current_special_kind() -> String:
	return _special_kind


func pick_special(kind: String) -> void:
	_special_kind = kind
	if _tool != TOOL_SPECIAL:
		set_tool(TOOL_SPECIAL)
	_set_status("Primitive: %s — click to place." % kind)
	_refresh_status()


## The side lengths shown in the panel: the selected primitive's own, or the defaults for the
## kind about to be placed.
func special_sides() -> Array:
	if _corner_target.has("sides"):
		return _corner_target.get("sides", []) as Array
	return AuthoredSpecialShapes.defaults_for(_special_kind)


func special_parameter_names() -> Array:
	var kind := str(_corner_target.get("kind", _special_kind))
	return AuthoredSpecialShapes.parameters_for(kind)


func _special_sides() -> Array:
	return AuthoredSpecialShapes.defaults_for(_special_kind)


## Nudge one side length. On a placed primitive this REBUILDS its outline from the numbers,
## discarding corner edits — said plainly in the status line rather than left to surprise.
func adjust_special_side(index: int, delta: float) -> void:
	if not _corner_target.has("sides"):
		_set_status("Select a primitive first (X, then click it).")
		return
	var sides: Array = _corner_target.get("sides", []) as Array
	if index < 0 or index >= sides.size():
		return
	_document.begin_edit("resize primitive")
	sides[index] = AuthoredSpecialShapes.clamp_side(float(sides[index]) + delta)
	_corner_target["sides"] = sides
	AuthoredSpecialShapes.rebuild(_corner_target)
	_overlay.queue_redraw()
	_set_status("%s = %d  (rebuilt from parameters — corner edits cleared)"
		% [str(special_parameter_names()[index]), int(sides[index])])
	_refresh_status()


func shape_tool() -> MapEditorShapeTool:
	return _shape_tool


## Choosing a shape selects the stamp tool with it — picking a form is a statement of intent
## to place one, and making the designer then find the tool is a step for nothing.
func open_panel_section(title: String) -> void:
	if _panel != null:
		_panel.open_section(title)


func pick_form(value: String) -> void:
	_shape_tool.set_form(value)
	if _tool != TOOL_STAMP:
		set_tool(TOOL_STAMP)
	else:
		_refresh_status()
	_set_status("Form: %s" % value)


func cycle_form(step: int) -> void:
	_set_status("Form: %s" % _shape_tool.cycle_form(step))
	_overlay.queue_redraw()
	_refresh_status()


func current_form() -> String:
	return _shape_tool.form()


func current_area_kind() -> String:
	return _shape_tool.kind()


func set_area_kind(value: String) -> void:
	_shape_tool.set_kind(value)
	if _tool != TOOL_AREA:
		set_tool(TOOL_AREA)
	else:
		_refresh_status()


func road_tool() -> MapEditorRoadTool:
	return _road_tool


func trace_tool() -> MapEditorTraceTool:
	return _trace_tool


## The live marquee in world units, or an empty Rect2 when not dragging.
func marquee_rect() -> Rect2:
	if _marquee_from == Vector2.INF or _marquee_to == Vector2.INF:
		return Rect2()
	return Rect2(_marquee_from, Vector2.ZERO).expand(_marquee_to)


## Ids of the selected records, for the overlay's highlight.
func selected_ids() -> Dictionary:
	var out: Dictionary = {}
	for entry_value in _selection:
		out[str((entry_value as Dictionary).get("id", ""))] = true
	return out


func selection_size() -> int:
	return _selection.size()


# ── Public API (the tool panel and the keyboard share it) ───────────────────────
#
# Every control the panel offers routes through these, so a button and its shortcut cannot
# drift apart — they are the same call.

func current_tool() -> String:
	return _tool


func set_tool(value: String) -> void:
	if value == _tool:
		return
	# Leaving the pen mid-stroke would otherwise strand a half-drawn road that no longer has
	# a tool to finish it.
	if _road_tool.is_drawing():
		_road_tool.abandon()
	_trace_tool.cancel_trace()
	_shape_tool.abandon()
	_anchor_grab = {}
	_grabbed = []
	_pending_hit = {}
	_marquee_from = Vector2.INF
	_marquee_to = Vector2.INF
	_overlay.queue_redraw()
	_tool = value
	_panning = false
	_refresh_status()


func current_road_class() -> String:
	return _road_tool.stroke_class()


func set_road_class(value: String) -> void:
	_road_tool.set_stroke_class(value)
	# Picking a class is a statement of intent to draw, so it selects the pen too.
	if _tool != TOOL_ROAD:
		set_tool(TOOL_ROAD)
	else:
		_refresh_status()


func grid_shown() -> bool:
	return _overlay != null and _overlay.show_grid


func water_mask_shown() -> bool:
	return _overlay != null and _overlay.show_water_mask


func toggle_water_mask() -> void:
	if _overlay != null:
		_overlay.show_water_mask = not _overlay.show_water_mask
		_overlay.queue_redraw()
	_refresh_status()


func toggle_grid() -> void:
	if _overlay != null:
		_overlay.show_grid = not _overlay.show_grid
		_overlay.queue_redraw()
	_refresh_status()


func run_action(action: String) -> void:
	match action:
		"save":
			_save()
		"reload":
			_reload()
		"leave":
			_leave()
		"delete":
			_ask_delete()
		"save_as":
			_ask_name()
		"load":
			_ask_load()
		"undo":
			_set_status(_document.undo())
			_overlay.queue_redraw()
		"redo":
			_set_status(_document.redo())
			_overlay.queue_redraw()


# ── Document ────────────────────────────────────────────────────────────────────

## F5 saves under the document's current name, and asks for one the first time.
func _save() -> void:
	if _is_scratch():
		# Belt and braces: even a direct Save in a harness goes to the throwaway name.
		_save_as(SCRATCH_NAME)
		return
	if _document.name_of() == "":
		_ask_name()
		return
	_save_as(_document.name_of())


func _ask_load() -> void:
	_load_dialog.open(_document.name_of(), _document.is_dirty())
	_panel.refresh()


## Open a saved map, and point the game at it — see the load dialog's header for why the two
## go together.
func _load_named(name: String) -> void:
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	var pointed := AuthoredMap.write_active(name, directory)
	if pointed != "":
		_set_status("LOAD FAILED — %s" % pointed)
		return
	AuthoredMap.reset_for_tests()
	_document.reload()
	_selection = []
	_road_tool.abandon()
	_trace_tool.cancel_trace()
	_trace_tool.clear_dots()
	_overlay.queue_redraw()
	var counts := _document.counts()
	_set_status("Opened '%s' — %d roads across %d settlement(s)."
		% [name, counts.roads, counts.settlements])
	_refresh_status()


func _ask_name() -> void:
	_name_dialog.open(_document.name_of())
	_panel.refresh()


## Write the document under `name` and point the game at it. Saving and activating are one
## step deliberately: a save that did not become the map you then look at would be a trap,
## and every other variant stays on disk to switch back to.
func _save_as(name: String) -> void:
	if _is_scratch() and name != SCRATCH_NAME:
		_set_status("Scratch mode — refusing to write '%s'." % name)
		return
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	var absolute := "%s/%s.json" % [directory, name]
	var problem := _document.save_to(absolute)
	if problem != "":
		_set_status("SAVE FAILED — %s" % problem)
		_refresh_status()
		return
	var pointed := AuthoredMap.write_active(name, directory)
	_document.set_name(name)
	# Drop the game-side cache so anything reading it now sees what was just written.
	AuthoredMap.reset_for_tests()
	_set_status("Saved '%s'%s" % [name,
		"" if pointed == "" else "  (but the active pointer failed: %s)" % pointed])
	_refresh_status()


func _reload() -> void:
	AuthoredMap.reset_for_tests()
	_document.reload()
	_refresh_status()


func _leave() -> void:
	if _document.is_dirty() and not _document.discard_armed():
		# One press arms, the second leaves: an editor that discards an hour's work on a
		# stray Escape is worse than one that asks twice.
		_document.arm_discard()
		_set_status("UNSAVED CHANGES — press Esc again to discard, or F5 to save.")
		return
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## True once the world has settled and the camera is under editor control. Capture
## harnesses poll this instead of guessing a frame count.
func is_ready_to_edit() -> bool:
	return _ready_to_edit


## Frame the view on a tile, for capture harnesses and (later) the editor's own
## go-to-tile command. Returns false when the tile id is unknown.
func focus_tile(tile_id: String, zoom: float = START_ZOOM) -> bool:
	if _camera == null:
		return false
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return false
	var coord: Vector2i = terrain.call("id_to_coord", tile_id)
	if not (terrain.get("tiles") as Dictionary).has(coord):
		return false
	_camera.position = terrain.call("map_to_local", terrain.call("map_coord_for_tile_coord", coord))
	var z := clampf(zoom, ZOOM_MIN, ZOOM_MAX)
	_camera.zoom = Vector2(z, z)
	if "_target_zoom" in _camera:
		_camera.set("_target_zoom", _camera.zoom)
	return true


func document() -> MapEditorDocument:
	return _document


func camera() -> Camera2D:
	return _camera
