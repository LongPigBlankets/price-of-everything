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
const MapEditorSlotBoxes := preload("res://scripts/map_editor/map_editor_slot_boxes.gd")
const MapEditorFabric := preload("res://scripts/map_editor/map_editor_fabric.gd")
const BuildingVisualsRef := preload("res://scenes/building_visuals.gd")
const MapEditorPanel := preload("res://scripts/map_editor/map_editor_panel.gd")
const MapEditorRegionImport := preload("res://scripts/map_editor/map_editor_region_import.gd")

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
## Click to plant a tree: a single small one, a single large one, or a MIXED clump. Each press
## of the key cycles which, so a row of varied planting never needs the pointer to leave the
## map — the same idiom the slot tool uses for its classes.
const TOOL_TREE := "tree"
## The three, in cycle order. "mixed" is the only clump: a stand of identical trees reads as a
## repeated stamp rather than as woodland (owner, 2026-08-28), so there is no small-clump or
## large-clump to choose by mistake.
## "forest" is the fourth: it plants a WOOD (an outline area of the current canopy type)
## rather than an individual tree. Cycling reaches it, and any of the number keys jumps
## straight to it (owner 2026-08-29).
const TREE_KINDS := ["small", "large", "mixed", "forest"]
## Canopy types, in the order the number keys select them. Read from the painter so the
## editor and the renderer can never disagree about what types exist.
const FOREST_VARIANTS := AuthoredFabricPainter.FOREST_VARIANTS
## A planted wood's default outline: a rough octagon at roughly the footprint a procedural
## forest had, which the designer then reshapes (right-drag in SELECT) or rotates ([ ]).
const FOREST_PLANT_RADIUS := 78.0
## How wide a planted clump is, in world units.
const TREE_CLUMP_RADIUS := 26.0

## The box a slot of each class reserves comes from `MapEditorSlotBoxes`, which reads the
## SHIPPED table in `building_visuals.gd`. The editor had its own copy of those numbers; two
## copies of "how much ground a slot reserves" is one drift away from the editor drawing a
## box the game will not honour.

## How close a click must land to a corner to pick it up, in world units.
const CORNER_GRAB := 16.0

## Screen pixels of movement before a press on a shape becomes a MOVE rather than a click.
## In pixels rather than world units so the gesture feels the same at every zoom — the hand
## does not know what a world unit is.
const MOVE_THRESHOLD := 4.0

## Resize step for the +/- keys. Ten percent is small enough to converge on a size and large
## enough that a press is visibly worth making.
const RESIZE_STEP := 1.1

## Rotation step for the [ and ] keys. Five degrees is fine enough to line a building up with
## something and coarse enough to get there in a few presses.
const ROTATE_STEP := deg_to_rad(5.0)

## Arrow-key nudging: world units per second, polled like the WASD pan so a held key glides
## instead of inheriting the OS key-repeat delay. Deliberately slow — arrows are for the last
## few units after a drag has got you close, which is exactly when key-repeat stutter is most
## annoying. Shift multiplies for crossing a whole lot.
const NUDGE_SPEED := 34.0
const NUDGE_FAST := 4.0
const NUDGE_KEYS := {
	KEY_UP: Vector2(0.0, -1.0),
	KEY_DOWN: Vector2(0.0, 1.0),
	KEY_LEFT: Vector2(-1.0, 0.0),
	KEY_RIGHT: Vector2(1.0, 0.0),
}

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

## SCREEN pixels moved per unit of trackpad two-finger scroll. A pan gesture's delta is a
## small step per event and they arrive in a stream, so this is a feel number: 22 is what the
## empire graph settled on for the same gesture, and matching it means one scroll covers the
## same ground in both views.
const PAN_GESTURE_SPEED := 22.0
## How hard Ctrl-scroll zooms. Deliberately gentle — a trackpad fires many events per flick,
## and a per-event factor near 1 is what keeps the ramp smooth instead of jumping.
const PAN_ZOOM_RATE := 0.03
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
var _shape_mode := false
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
## Which question the confirmation is currently asking.
var _confirm_action := ""
## Set while a drag is held with Ctrl/Cmd down. Snapping is OPT-IN (owner, 2026-08-16): a
## drag places exactly where the pointer is unless the modifier asks for a kerb.
var _snap_requested := false
## The records last moved, so the snap can act on them after the drag ends.
var _moved_records: Array = []
var _special_kind := "u"
var _slot_class := "standard"
## Corners of the free polygon being clicked out.
var _poly_points: Array = []
## True while an arrow key is held, so one snapshot covers the whole press.
var _nudging := false
## The slot pin currently picked, as `{tile_id, index}` — slots live in a per-tile dictionary
## rather than a settlement list, so they are selected separately from shapes.
var _slot_pick: Dictionary = {}
## Built once — tile deposits are static map data.
var _deposit_cache: Array = []
var _report_tile := ""
## The working document's fabric, drawn in the world (see `_mount_fabric_layer`).
var _fabric: Node2D = null
var _fabric_ground: Node2D = null
var _panel: MapEditorPanel
var _tool := TOOL_PAN
## Which tree the tree tool plants next; cycled by pressing its key again.
var _tree_kind := "small"
var _forest_variant := "current"
var _world: Node
var _camera: Camera2D
var _status: Label
var _ready_to_edit := false
var _panning := false
var _settlement := DEFAULT_SETTLEMENT
## Bumped by [method _repaint] whenever the drawn content changes; the fabric preview layers
## redraw when it moves rather than every frame.
var _preview_revision := 0


## SCRATCH MODE, for capture and input harnesses. They drive the editor with synthetic
## clicks at computed positions, and a position that lands over the panel presses whatever
## button is there — which is how a harness silently saved its demo content into a real map
## and grew it by 49 records. In scratch mode the editor starts empty and can only ever
## write to a throwaway name, so a stray click cannot reach anyone's work.
const SCRATCH_NAME := "__scratch__"


func _is_scratch() -> bool:
	return OS.get_environment("POE_EDITOR_SCRATCH") == "1"


func _ready() -> void:
	# The debug terminal's cheats reach the editor through this group, by `call()` — the
	# terminal is SHIPPED code and may not preload anything under scripts/map_editor/.
	add_to_group("map_editor")
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
	# While a text field has focus (the debug terminal, the save/load dialogs), letters are
	# TYPING, not camera keys — polling Input here would pan the map on every W or A in a
	# command or document name.
	if get_viewport().gui_get_focus_owner() != null:
		return
	_nudge_selection(delta)
	var direction := Vector2.ZERO
	for key in PAN_KEYS:
		if Input.is_physical_key_pressed(key):
			direction += PAN_KEYS[key] as Vector2
	if direction == Vector2.ZERO:
		return
	var speed := PAN_SPEED * (PAN_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	_camera.position += direction.normalized() * speed * delta / _camera.zoom.x


## Arrows nudge whatever is selected, continuously. Polled for the same reason the pan is:
## a key-repeat nudge moves once, pauses, then bursts, which is useless for lining something
## up. One undo snapshot covers a whole press rather than one per frame.
func _nudge_selection(delta: float) -> void:
	var direction := Vector2.ZERO
	for key in NUDGE_KEYS:
		if Input.is_physical_key_pressed(key):
			direction += NUDGE_KEYS[key] as Vector2
	if direction == Vector2.ZERO:
		_nudging = false
		return
	var records := _records_of(_selection)
	var slot := _selected_slot()
	if records.is_empty() and slot.is_empty():
		return
	if not _nudging:
		_document.begin_edit("nudge")
		_nudging = true
	var step := direction.normalized() * NUDGE_SPEED * delta \
		* (NUDGE_FAST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
	for record in records:
		MapEditorSelection.translate(record as Dictionary, step)
	if not slot.is_empty():
		var pos: Array = slot.get("pos", [0, 0]) as Array
		if pos.size() >= 2:
			slot["pos"] = [float(pos[0]) + step.x, float(pos[1]) + step.y]
	_repaint()


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
	#
	# STAND THE HEAVY LAYERS DOWN BEFORE THE WAIT, not after it. The world takes about a
	# hundred frames to settle, and the layers the editor is about to hide anyway were
	# rendering through every one of them. That is normally affordable and once was not: with
	# the authored bake stale the game's own fabric layer falls back to drawing the whole
	# document as vectors — 4.5 seconds a frame — and the editor sat on "Building the world…"
	# for eight minutes. The editor draws its own preview of that document, so it never needs
	# these on, and binding early means a slow layer can no longer hold the boot hostage.
	_layers.bind(_world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame
	_hide_game_ui()
	_silence_world_input(_world)
	_mount_fabric_layer()
	_take_camera()
	# Again, now that the world has finished building: layers created DURING the build (the
	# ports and the farm underlay are added at runtime) did not exist for the first pass.
	_layers.bind(_world)
	_panel.build(self, _layers)
	_ready_to_edit = true
	_refresh_status()


## Put the working document's fabric INTO THE WORLD, at the shipped fabric node's own place
## in the sibling order, so it layers against buildings and roads exactly as the game will.
##
## Drawing it on the overlay could never be right: the overlay is a CanvasLayer at layer 64,
## above the entire world, so a park drawn there sat on top of the buildings it belongs under
## no matter what order the overlay drew things in.
func _mount_fabric_layer() -> void:
	var shipped := _world.get_node_or_null("AuthoredFabricVisuals")
	if shipped == null:
		return
	# TWO nodes, because the editor shows the procedural fabric while you draw over it.
	# Plazas, parks and worked land are GROUND and must sit under the decorative buildings the
	# generator draws — which live in UrbanFabricVisuals, BEFORE the authored node. Mounting
	# everything after the authored node put parks on top of them, which is the bug this
	# splits to fix. In the game the two never meet: an authored tile suppresses the
	# procedural fabric outright.
	var procedural := _world.get_node_or_null("UrbanFabricVisuals")
	_fabric_ground = MapEditorFabric.new()
	_fabric_ground.editor = self
	_fabric_ground.half = MapEditorFabric.Half.GROUND
	_fabric_ground.name = "MapEditorFabricGround"
	_world.add_child(_fabric_ground)
	_world.move_child(_fabric_ground,
		procedural.get_index() if procedural != null else shipped.get_index())

	_fabric = MapEditorFabric.new()
	_fabric.editor = self
	_fabric.half = MapEditorFabric.Half.STANDING
	_fabric.name = "MapEditorFabric"
	_world.add_child(_fabric)
	# Directly after the shipped node: same depth, and it draws over the saved document so an
	# edit is visible immediately rather than only after a save.
	_world.move_child(_fabric, shipped.get_index() + 1)


## Stop the GAME from consuming input while the editor is up.
##
## `camera_controller`, `hex_map` and `world_map` all run `_input`/`_unhandled_input`, and
## the world is a CHILD of this node, so they see every event first. That is why Escape
## never reached the editor and why dragging fought the pen: the game was still panning,
## picking tiles and claiming keys underneath. Disabling their processing is far more
## honest than trying to out-order them, and it leaves this node the single owner of input.
func _silence_world_input(node: Node) -> void:
	# The debug terminal stays live: it is the editor's cheat surface (`enable procedural
	# <region>`), it only acts when opened with the backtick key, and its chrome sits above
	# the editor's (layer 128 vs 64) precisely so it can be used here.
	var script: Variant = node.get_script()
	if script != null and str(script.resource_path).ends_with("debug_terminal.gd"):
		return
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
	_confirm.confirmed.connect(_on_confirmed)
	_confirm.cancelled.connect(func() -> void: _set_status("Cancelled."))
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


## SOMETHING VISIBLE CHANGED — repaint the overlay and tell the fabric layers.
##
## The preview layers used to call `queue_redraw()` from `_process`, i.e. they redrew the
## WHOLE document every frame. That is affordable for a settlement and ruinous for a map:
## with the stoneshore document open the editor was measured at over nine SECONDS a frame,
## because every repaint re-scattered and re-drew the trees of all 148 woods (a wood is up to
## 900 trees, and a tree is three draw calls). The game never did this — its own authored
## layer repaints only when the view moves — so the cost lived entirely in the editor.
##
## The stamp is the seam: every mutation, selection change and tool change already ended in a
## repaint call, so bumping a counter here means the layers can sleep until one arrives.
func _repaint() -> void:
	_preview_revision += 1
	if _overlay != null:
		_overlay.queue_redraw()


## What the preview layers watch. Changes exactly when the drawn content does.
func preview_revision() -> int:
	return _preview_revision


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = "MAP EDITOR   %s" % text
	if _panel != null:
		_panel.set_status(text)


func _refresh_status() -> void:
	var counts := _document.counts()
	# The tree tool's kind is cycled by re-pressing its key, so the status line has to say
	# which one is loaded — otherwise the only way to find out is to plant one.
	var tool_note := ""
	if _tool == TOOL_TREE:
		tool_note = "   |   planting %s (T cycles" % _tree_label()
		if _tree_kind == "forest":
			tool_note += ", 1-%d picks type" % FOREST_VARIANTS.size()
		tool_note += ")"
	_set_status("%s   |   %d settlements · %d roads · %d masses   |   %s%s"
		% [_document.display_name(), counts.settlements, counts.roads, counts.masses,
			"UNSAVED" if _document.is_dirty() else "saved", tool_note])
	if _panel != null:
		_panel.refresh()
		_panel.set_tile_report(tile_report(_hovered_tile()))
	# Belt and braces for the preview stamp: picking a form, a road class or a slot size
	# changes what the tools draw as a preview but mutates no record, and every one of those
	# setters ends here. Nothing calls this per frame, so it cannot reintroduce the per-frame
	# repaint this replaced.
	_repaint()


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
			_repaint()
		elif _tool == TOOL_SELECT and _held_corner >= 0:
			_move_corner(_world_at(motion.position))
		elif _tool == TOOL_SELECT and not _grabbed.is_empty():
			# Ctrl, or Cmd on macOS, asks for the kerb; without it the drop is literal.
			_snap_requested = motion.ctrl_pressed or motion.meta_pressed
			_drag_grabbed(motion.position)
		elif _tool == TOOL_STAMP and _shape_tool.is_stamping():
			_shape_tool.drag_stamp(_world_at(motion.position))
			_repaint()
		elif _tool == TOOL_SELECT and _marquee_from != Vector2.INF:
			_marquee_to = _world_at(motion.position)
			_repaint()
		elif _tool == TOOL_ANCHOR and not _anchor_grab.is_empty():
			# Live reshaping: the curve follows the pointer, so the bend is judged against
			# the map rather than guessed and corrected.
			MapEditorStrokeEdit.shape_anchor(_anchor_grab["stroke"] as Dictionary,
				int(_anchor_grab["index"]), _world_at(motion.position))
			_repaint()
	elif event is InputEventMagnifyGesture:
		# TRACKPAD PINCH. On macOS a trackpad never sends the wheel events the zoom was bound
		# to: a pinch arrives as this, and a two-finger scroll as the pan gesture below, so on
		# a laptop the editor could not be zoomed at all. `factor` is relative to the last
		# event — a stream of small numbers around 1.0 — which is exactly what `_zoom_by`
		# takes, and anchoring on the gesture's own position zooms toward the fingers.
		var pinch := event as InputEventMagnifyGesture
		_zoom_by(pinch.factor, pinch.position)
	elif event is InputEventPanGesture:
		# TRACKPAD TWO-FINGER SCROLL: pans, or zooms while Ctrl (or Cmd) is held — the
		# modifier convention every map and canvas app shares, and the way a Windows precision
		# trackpad reports a pinch. Panning is the platform's own reading of the gesture, and
		# the editor had no answer for it either, so a trackpad could not scroll the map.
		var pan := event as InputEventPanGesture
		if pan.ctrl_pressed or pan.meta_pressed:
			_zoom_by(1.0 - pan.delta.y * PAN_ZOOM_RATE, pan.position)
		elif _camera != null:
			_camera.position += pan.delta * PAN_GESTURE_SPEED / _camera.zoom.x
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
						# A free polygon is CLICKED OUT corner by corner; the parametric
						# three are placed whole with one click.
						if _special_kind == "poly":
							_add_poly_point(world)
						else:
							_place_special(world)
				TOOL_SLOT:
					if event.pressed:
						_place_slot(world)
				TOOL_TREE:
					if event.pressed:
						if _tree_kind == "forest":
							_place_forest(world)
						else:
							_place_tree(world)
				TOOL_SELECT:
					if event.pressed:
						_select_press(world, event.position)
					else:
						_select_release(world)
		MOUSE_BUTTON_RIGHT:
			# In SELECT, the right button opens SHAPE MODE on whatever is under it: corners
			# appear as dots and can be dragged. Everywhere else it still pans, because
			# panning mid-stroke is normal when a road runs off the edge of the view.
			if _tool == TOOL_SELECT:
				if event.pressed:
					_shape_press(_world_at(event.position))
			else:
				_panning = event.pressed
		MOUSE_BUTTON_MIDDLE:
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
			_on_confirmed()
		elif event.keycode == KEY_ESCAPE:
			_confirm.close()
			_confirm_action = ""
			_set_status("Cancelled.")
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
		KEY_Y:
			# Anchor moved off T (owner 2026-08-29): T had TWO branches in this match, and
			# since the first wins, the tree tool below had been unreachable by keyboard
			# since it was added. T is the tree/forest key; anchor is Y.
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
			# First press picks the tool; each one after cycles the class, so laying a row of
			# mixed sizes never needs the pointer to leave the map.
			if _tool == TOOL_SLOT:
				_cycle_slot_class()
			else:
				set_tool(TOOL_SLOT)

		KEY_T:
			# First press picks the tool; each one after cycles small -> large -> mixed clump
			# -> forest, so planting a varied group never needs the pointer to leave the map.
			if _tool == TOOL_TREE:
				var at := TREE_KINDS.find(_tree_kind)
				_tree_kind = str(TREE_KINDS[(at + 1) % TREE_KINDS.size()])
				_refresh_status()
			else:
				set_tool(TOOL_TREE)

		KEY_EQUAL, KEY_KP_ADD:
			_resize_selection(RESIZE_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_resize_selection(1.0 / RESIZE_STEP)
		KEY_BRACKETLEFT:
			_rotate_selection(-ROTATE_STEP)
		KEY_BRACKETRIGHT:
			_rotate_selection(ROTATE_STEP)
		KEY_COMMA:
			_set_status("Form: %s" % _shape_tool.cycle_form(-1))
			_repaint()
		KEY_PERIOD:
			_set_status("Form: %s" % _shape_tool.cycle_form(1))
			_repaint()
		KEY_DELETE:
			_ask_delete()
		KEY_G:
			toggle_grid()
		KEY_H:
			toggle_water_mask()
		KEY_J:
			_toggle_hijack_selection()
		KEY_E:
			_zoom_by(ZOOM_STEP)
		KEY_Q:
			_zoom_by(1.0 / ZOOM_STEP)
		# The number keys are CONTEXTUAL: canopy types while planting, road classes otherwise.
		# Road class only means anything in the road tools, so the two never collide in use.
		KEY_1:
			_number_key(0, "major")
		KEY_2:
			_number_key(1, "mid")
		KEY_3:
			_number_key(2, "minor")
		KEY_4:
			_number_key(3, "")
		KEY_5:
			_number_key(4, "")
		KEY_6:
			_number_key(5, "")
		KEY_7:
			_number_key(6, "")
		KEY_ENTER, KEY_KP_ENTER:
			# Enter is "done" (owner, 2026-08-18). Mid-draw it commits the thing being drawn
			# and STAYS on the tool, so the next primitive or field needs no re-pick; with
			# nothing in progress it exits whatever mode is live back to Navigate.
			if _tool == TOOL_SPECIAL and _special_kind == "poly" and not _poly_points.is_empty():
				_finish_poly()
			elif _tool == TOOL_AREA and _shape_tool.is_drawing():
				_finish_area()
			elif _road_tool.is_drawing():
				_finish_stroke()
			else:
				_leave_shape_mode()
				set_tool(TOOL_PAN)
				_set_status("Back to Navigate.")
				_refresh_status()
		KEY_BACKSPACE:
			# In SELECT, Backspace removes what is selected. In the drawing tools it still
			# steps back a point, which is what a half-drawn shape needs it for.
			if _tool == TOOL_SELECT and not _slot_pick.is_empty():
				_delete_slot()
			elif _tool == TOOL_SELECT:
				_ask_delete()
			elif _tool == TOOL_SPECIAL and not _poly_points.is_empty():
				_poly_points.remove_at(_poly_points.size() - 1)
				_repaint()
			elif _tool == TOOL_AREA:
				_shape_tool.undo_point()
			elif _tool == TOOL_DOTS:
				_trace_tool.undo_dot()
			else:
				_road_tool.undo_point()
			_repaint()
		KEY_ESCAPE:
			# Escape abandons work in progress first; only an idle Escape leaves. Dots count
			# as work in progress: clearing them is what "cancel" means for that tool.
			if not _selection.is_empty():
				_selection = []
				_repaint()
				_set_status("Selection cleared.")
				_refresh_status()
				return
			if _road_tool.is_drawing() or _trace_tool.is_tracing() \
					or not _trace_tool.dots().is_empty():
				_road_tool.abandon()
				_trace_tool.cancel_trace()
				_trace_tool.clear_dots()
				_repaint()
				_refresh_status()
				return
			_leave()
		KEY_Z:
			if event.ctrl_pressed or event.meta_pressed:
				var outcome := _document.redo() if event.shift_pressed else _document.undo()
				_rebind_after_history()
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
		_repaint()
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
	_repaint()
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
		_repaint()
		return
	_selection = MapEditorSelection.in_rect(_document.data(), rect)
	# Exactly one outline-shaped thing selected: show its corners, since that is the only
	# case where "drag a corner" has an unambiguous subject.
	var single := MapEditorSelection.single_outline(_document.data(), _selection)
	_set_corner_target(single)
	_set_status("%d selected%s — Delete to remove." % [_selection.size(),
		" · drag its corners" if not single.is_empty() else ""] if not _selection.is_empty()
		else "Nothing in the box.")
	_repaint()


## Remove the picked slot. No confirmation: a slot holds nothing, so deleting one costs a
## click to replace rather than any authored work.
func _delete_slot() -> void:
	var settlements: Dictionary = _document.data().get("settlements", {})
	for key in settlements.keys():
		var slots: Dictionary = (settlements[key] as Dictionary).get("slots", {})
		var tile_id := str(_slot_pick.get("tile_id", ""))
		if not slots.has(tile_id):
			continue
		var pins: Array = (slots[tile_id] as Dictionary).get("pins", []) as Array
		var index := int(_slot_pick.get("index", -1))
		if index < 0 or index >= pins.size():
			continue
		_document.begin_edit("delete slot")
		pins.remove_at(index)
		_slot_pick = {}
		_repaint()
		_set_status("Slot removed.")
		_refresh_status()
		return


## Ask before removing. Deletion is the one action here that destroys authored work, and the
## marquee makes it easy to catch more than intended.
## Route the confirmation to whatever asked for it.
func _on_confirmed() -> void:
	match _confirm_action:
		"delete":
			_delete_selection()
		"leave":
			_do_leave()
	_confirm_action = ""


func _ask_delete() -> void:
	if _selection.is_empty():
		_set_status("Nothing selected.")
		return
	_confirm_action = "delete"
	_confirm.ask("Delete %d selected item%s?" % [_selection.size(),
		"" if _selection.size() == 1 else "s"])
	_panel.refresh()


func _delete_selection() -> void:
	if _selection.is_empty():
		return
	_document.begin_edit("delete selection")
	var removed := MapEditorSelection.delete(_document.data(), _selection)
	_selection = []
	_repaint()
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
	_repaint()
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
		_repaint()
		return
	_document.begin_edit("draw %s" % kind)
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	# Zones all live in ONE list with their kind on the record, rather than a list per kind:
	# the placement side asks "which zones of kind X cover this tile", and three parallel
	# lists would be three chances for them to drift apart.
	var list_key := kind
	var label := kind.trim_suffix("s").capitalize()
	if kind.begins_with(MapEditorShapeTool.ZONE_PREFIX):
		list_key = "zones"
		record["kind"] = kind.trim_prefix(MapEditorShapeTool.ZONE_PREFIX)
		label = str(record["kind"]).replace("_", " ").capitalize() + " zone"
	var items: Array = settlement.get(list_key, []) as Array
	items.append(record)
	settlement[list_key] = items
	_cover_tiles_of(settlement, record.get("outline", []) as Array)
	# A zone declares the tiles it covers, so the mask can be built per tile without
	# re-testing every polygon on the map.
	if list_key == "zones":
		record["tiles"] = _tiles_under(record.get("outline", []) as Array)
	_repaint()
	_set_status("%s placed (%d corners)." % [label,
		(record.get("outline", []) as Array).size()])


## Commit the mass being dragged.
func _finish_stamp() -> void:
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var record := _shape_tool.finish_stamp(_settlement, next_id)
	_repaint()
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
	_repaint()
	_set_status("Stamped %s." % str(record.get("form", "")))


## The tiles a polygon's corners fall on, sorted. Corner sampling rather than a full
## rasterisation: a zone is drawn to sit inside usable ground, so a polygon that spans a tile
## without a corner on it would have to be enormous.
func _tiles_under(points: Array) -> Array:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return []
	var tiles: Dictionary = terrain.get("tiles")
	var out: Array = []
	for entry in points:
		var values: Array = entry as Array
		if values == null or values.size() < 2:
			continue
		var world := Vector2(float(values[0]), float(values[1]))
		var coord: Vector2i = terrain.call("tile_coord_for_map_coord",
			terrain.call("local_to_map", world))
		if not tiles.has(coord):
			continue
		var tile_id := str((tiles[coord] as Dictionary).get("id", ""))
		if tile_id != "" and not out.has(tile_id):
			out.append(tile_id)
	out.sort()
	return out


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
	_repaint()
	_set_status("Placed %s — switch to Select (X) to drag its corners." % _special_kind)


# ── Select: drag to move, click to select ──────────────────────────────────────
#
# One press does three different things depending on what is under it, in this order: a
# corner handle of the shape already being edited, a shape (which then moves or selects), or
# empty ground (which starts a marquee). Ordered so the most specific target wins — a corner
# handle sits on top of its own shape, and grabbing the shape instead would make handles
# unusable.

## RIGHT-PRESS: open shape mode on the shape under the pointer, or close it on empty ground.
##
## Position and shape are separate gestures now (owner, 2026-08-17). They used to share the
## left button, with the corner test running FIRST — so selecting a shape whose corner
## happened to be near the pointer dragged that corner instead of the shape, which is most
## selections on a small shape.
func _shape_press(world: Vector2) -> void:
	var hit := MapEditorSelection.at_point(_document.data(), world)
	if hit.is_empty() or MapEditorSelection.corner_field(hit["record"] as Dictionary) == "":
		_leave_shape_mode()
		_set_status("Nothing here to reshape.")
		_refresh_status()
		return
	_shape_mode = true
	_set_corner_target(hit["record"] as Dictionary)
	_selection = [{"kind": str(hit["kind"]), "settlement": str(hit["settlement"]),
		"index": int(hit["index"]), "id": str(hit["id"])}]
	_repaint()
	_set_status("Shape mode: drag the dots to reshape. Left-click away or pick a tool to leave.")
	_refresh_status()


func _leave_shape_mode() -> void:
	_shape_mode = false
	_held_corner = -1
	_set_corner_target({})


func is_shape_mode() -> bool:
	return _shape_mode


func _select_press(world: Vector2, screen: Vector2) -> void:
	# Corners are ONLY grabbable in shape mode, which the right button opens. The left button
	# is position: select, drag, and everything that follows from having a thing selected.
	if _shape_mode:
		_held_corner = _corner_at(world)
		if _held_corner >= 0:
			_document.begin_edit("move corner")
			return
		# A left click anywhere else leaves shape mode and behaves normally from here.
		_leave_shape_mode()
	# Slots are checked first: one sits on the ground it reserves, and a shape underneath
	# would otherwise always win the click.
	var slot_hit := _slot_at(world)
	if not slot_hit.is_empty():
		_slot_pick = slot_hit
		_selection = []
		_set_corner_target({})
		_repaint()
		_set_status("%s slot selected — arrows move, [ ] rotate, Bksp deletes."
			% str(_selected_slot().get("size", "small")).capitalize())
		_refresh_status()
		return
	_slot_pick = {}
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
	# Cleared per grab: the modifier is read from the motion events of THIS drag, and a value
	# left over from a previous one would silently snap a drag the hand did not ask to snap.
	_snap_requested = false
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
	_repaint()


func _select_release(world: Vector2) -> void:
	if _held_corner >= 0:
		_held_corner = -1
		_repaint()
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
			if _snap_requested:
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
	_repaint()
	return snapped


## Turn the selection about each shape's own centre. Clockwise on screen is a POSITIVE
## angle here, because Y runs down.
func _rotate_selection(angle: float) -> void:
	var slot := _selected_slot()
	if not slot.is_empty():
		_document.begin_edit("rotate slot")
		slot["angle"] = float(slot.get("angle", 0.0)) + angle
		_repaint()
		_set_status("Slot turned to %d°" % int(round(rad_to_deg(float(slot["angle"])))))
		_refresh_status()
		return
	var records := _records_of(_selection)
	if records.is_empty():
		_set_status("Nothing selected — click a shape or a slot first.")
		return
	_document.begin_edit("rotate")
	for record_value in records:
		var record: Dictionary = record_value
		MapEditorSelection.rotate_about(record, MapEditorSelection.centre_of(record), angle)
	_repaint()
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
	_repaint()
	_set_status("Resized %d item%s to %d%%%s." % [changed, "" if changed == 1 else "s",
		int(round(factor * 100.0)),
		"" if changed == records.size() else " (roads have a class, not a size)"])
	_refresh_status()


## Mark the selected decorative buildings as hijack slots (J). A marked mass is ground
## a gameplay building will later claim: hidden in the shipped game until an NPC or
## player building takes it over and stamps it in the owner's colour. Only decor masses
## and specials qualify — ground (parks, plazas, farms, forests) and roads cannot be a
## building slot, so they are silently skipped rather than erroring a mixed selection.
## Stored as `hijack: true` on the record; cleared by erasing the key, so an unmarked
## document round-trips byte-identical.
func _toggle_hijack_selection() -> void:
	var settlements: Dictionary = _document.data().get("settlements", {})
	var records: Array = []
	for entry_value in _selection:
		var entry: Dictionary = entry_value
		var kind := str(entry.get("kind", ""))
		if kind != "decor" and kind != "specials":
			continue
		var settlement: Dictionary = settlements.get(str(entry.get("settlement", "")), {})
		var items: Array = settlement.get(kind, []) as Array
		var index := int(entry.get("index", -1))
		if index >= 0 and index < items.size():
			records.append(items[index])
	if records.is_empty():
		_set_status("Nothing hijackable selected — J marks decorative buildings (masses/specials).")
		_refresh_status()
		return
	_document.begin_edit("mark hijack")
	var marked := 0
	var cleared := 0
	for record_value in records:
		var record: Dictionary = record_value
		if bool(record.get("hijack", false)):
			record.erase("hijack")
			cleared += 1
		else:
			record["hijack"] = true
			marked += 1
	_repaint()
	_set_status("Hijack slots: %d marked, %d cleared." % [marked, cleared])
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


## The picked slot's record, or {}.
func _selected_slot() -> Dictionary:
	if _slot_pick.is_empty():
		return {}
	var settlements: Dictionary = _document.data().get("settlements", {})
	for key in settlements.keys():
		var slots: Dictionary = (settlements[key] as Dictionary).get("slots", {})
		var tile_slots: Dictionary = slots.get(str(_slot_pick.get("tile_id", "")), {})
		var pins: Array = tile_slots.get("pins", []) as Array
		var index := int(_slot_pick.get("index", -1))
		if index >= 0 and index < pins.size():
			return pins[index]
	return {}


## The slot under a world point, as `{tile_id, index}`.
func _slot_at(world: Vector2) -> Dictionary:
	for box_value in document_slot_boxes():
		var box: Dictionary = box_value
		var centre: Vector2 = box["centre"]
		var size: Vector2 = box["size"]
		var local := (world - centre).rotated(-float(box["angle"]))
		if absf(local.x) <= size.x * 0.5 and absf(local.y) <= size.y * 0.5:
			return {"tile_id": str(box["tile_id"]), "index": int(box["index"])}
	return {}


## The picked slot, for the overlay's highlight.
func picked_slot() -> Dictionary:
	return _slot_pick


func editable_corners() -> PackedVector2Array:
	# ONE choke point for the whole rule: corners are visible and grabbable only in shape
	# mode. Several paths still set `_corner_target` as a side effect of selecting — gating
	# here rather than at each of them means a new one cannot reintroduce corner-grabbing on
	# a plain left click, which is the bug this separation exists to kill.
	if not _shape_mode:
		return PackedVector2Array()
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
	_repaint()


## Undo and redo REPLACE the document dictionary rather than editing it in place, so any
## record the editor is holding on to points into an orphaned copy the moment history moves.
## The selection survives on its own — it stores addresses (settlement, kind, index) and
## re-resolves them every time. The corner target is the exception: it is the record itself,
## and after an undo it silently became a shape nobody can see. Dragging its handles then
## edited nothing, which reads as the corner tool being broken rather than as history having
## moved underneath it. Re-point it by id, and drop it if history removed the shape.
func _rebind_after_history() -> void:
	if _corner_target.is_empty():
		return
	var wanted := str(_corner_target.get("id", ""))
	if wanted == "":
		_set_corner_target({})
		return
	var settlements: Dictionary = _document.data().get("settlements", {})
	for key in settlements.keys():
		var settlement: Dictionary = settlements[key]
		for kind in ["decor", "specials", "farms", "forests", "parks", "plazas", "zones"]:
			for record_value in (settlement.get(kind, []) as Array):
				var record: Dictionary = record_value
				if str(record.get("id", "")) == wanted:
					_set_corner_target(record)
					return
	_set_corner_target({})


## Show a record's corners. Called when a selection resolves to exactly one outline-shaped
## thing; more than one and there is no single shape to edit.
func _set_corner_target(record: Dictionary) -> void:
	_corner_target = record
	_held_corner = -1
	_repaint()


## Free polygon: up to six corners, then Enter to close it. Kept separate from the farm and
## park outlines because this is a BUILDING — it takes the mass wash, the ink edge and the SE
## shadow, and it can be evicted; a park cannot.
func _add_poly_point(world: Vector2) -> void:
	if _poly_points.size() >= AuthoredSpecialShapes.POLY_MAX_POINTS:
		_set_status("%d corners maximum — press Enter to close."
			% AuthoredSpecialShapes.POLY_MAX_POINTS)
		return
	_poly_points.append([world.x, world.y])
	_repaint()
	_set_status("%d/%d corners — Enter closes, Bksp steps back."
		% [_poly_points.size(), AuthoredSpecialShapes.POLY_MAX_POINTS])


func _finish_poly() -> void:
	if _poly_points.size() < 3:
		_set_status("A shape needs at least three corners.")
		return
	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	_document.begin_edit("draw shape")
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var items: Array = settlement.get("specials", []) as Array
	items.append({"id": "s:%s:%d" % [_settlement, next_id], "kind": "poly",
		"sides": [], "outline": _poly_points.duplicate(true)})
	settlement["specials"] = items
	_cover_tiles_of(settlement, _poly_points)
	var placed: Dictionary = items[items.size() - 1]
	_poly_points = []
	_set_corner_target(placed)
	_repaint()
	_set_status("Shape placed — drag its corners to reshape.")


## Whether the confirmation is up — for the harness, and for anything that needs to know the
## editor is waiting on an answer.
func confirm_open() -> bool:
	return _confirm != null and _confirm.is_open()


func poly_points() -> Array:
	return _poly_points


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
	_repaint()
	_set_status("%s slot on %s (%d there)."
		% [_slot_class.replace("_", " ").capitalize(), tile_id, pins.size()])


## Plant one tree at `world`.
##
## Unlike a slot pin, this does NOT add the tile to the settlement. A slot is a promise about
## a tile and authoring it is the point; a tree is decoration standing at a point, and
## planting one must not quietly take a tile's fabric, roads and accommodation away from the
## generator (`AuthoredMap.covers` is that switch, and it is nothing to do with trees).
## A number key means a canopy type while the tree tool is up, and a road class otherwise.
## Picking a type also switches to planting FORESTS — pressing 3 to get "feather" and then
## having to press T twice to reach the forest sub-mode would be a needless second step.
func _number_key(variant_index: int, road_class: String) -> void:
	if _tool == TOOL_TREE:
		if variant_index >= FOREST_VARIANTS.size():
			_set_status("No canopy type %d — there are %d." % [variant_index + 1, FOREST_VARIANTS.size()])
			return
		_forest_variant = str(FOREST_VARIANTS[variant_index])
		_tree_kind = "forest"
		_refresh_status()
		_set_status("Planting %s woods." % _forest_variant)
		return
	if road_class != "":
		set_road_class(road_class)


## Plant a WOOD: an outline area of the current canopy type, plus the forest building that
## makes the tile actually wooded in the sim. The two are placed together on purpose — a wood
## the player can see but not harvest, or a forest building with no canopy drawn, are both
## states the map should not be able to get into by hand (owner 2026-08-29).
func _place_forest(world: Vector2) -> void:
	var settlement := _ensure_settlement()
	_document.begin_edit("plant wood")
	settlement = _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var forests: Array = settlement.get("forests", []) as Array
	var record := {
		"id": "fo:%s:%d" % [_settlement, next_id],
		"outline": _forest_outline(world),
		"density": 4.0,
		"variant": _forest_variant,
	}
	# The tiles this wood covers, declared on the record — this is what turns a drawn wood
	# into a forest BUILDING at world build (AuthoredMap.forest_tiles), and it mirrors how
	# zones already declare their coverage rather than making the reader re-test polygons.
	record["tiles"] = _tiles_under(record["outline"] as Array)
	forests.append(record)
	settlement["forests"] = forests
	settlement["next_id"] = next_id + 1
	_cover_tiles_of(settlement, record["outline"] as Array)
	_fabric.queue_redraw()
	_repaint()
	_set_status("Planted a %s wood (%d in this settlement)." % [_forest_variant, forests.size()])


## The default outline a planted wood starts as: a rough octagon, jittered per-wood so two
## woods planted side by side are not the same shape. Deliberately NOT a regular polygon —
## the point of the exercise was to stop woods looking stamped.
func _forest_outline(centre: Vector2) -> Array:
	var out: Array = []
	var salt := int(abs(centre.x) + abs(centre.y) * 7.0)
	for i in 8:
		var ang: float = TAU * float(i) / 8.0
		var wob: float = 0.82 + 0.28 * absf(sin(float(i) * 2.3 + float(salt % 17) * 0.4))
		var p: Vector2 = centre + Vector2(cos(ang), sin(ang)) * float(FOREST_PLANT_RADIUS) * wob
		out.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	return out


func _place_tree(world: Vector2) -> void:
	var settlement := _ensure_settlement()
	_document.begin_edit("plant tree")
	settlement = _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	var trees_value: Variant = settlement.get("trees", [])
	var trees: Array = trees_value if typeof(trees_value) == TYPE_ARRAY else []
	var record := {
		"id": "t:%s:%d" % [_settlement, next_id],
		"position": [snappedf(world.x, 0.01), snappedf(world.y, 0.01)],
		"kind": _tree_kind,
	}
	if _tree_kind == "mixed":
		record["radius"] = TREE_CLUMP_RADIUS
	trees.append(record)
	settlement["trees"] = trees
	settlement["next_id"] = next_id + 1
	_fabric.queue_redraw()
	_repaint()
	_set_status("Planted %s (%d tree record%s)."
		% [_tree_label(), trees.size(), "" if trees.size() == 1 else "s"])


func _tree_label() -> String:
	match _tree_kind:
		"small":
			return "a small tree"
		"large":
			return "a large tree"
		"forest":
			return "a %s wood" % _forest_variant
		_:
			return "a mixed clump"


## The facing for a slot: along the nearest authored road, or zero when there is none near.
func _slot_angle_at(world: Vector2) -> float:
	var probe := {"outline": [[world.x - 20.0, world.y - 20.0], [world.x + 20.0, world.y - 20.0],
		[world.x + 20.0, world.y + 20.0], [world.x - 20.0, world.y + 20.0]]}
	var seat := MapEditorRoadSnap.seat_for(_document.data(), probe)
	return float(seat.get("angle", 0.0)) if not seat.is_empty() else 0.0


func current_slot_class() -> String:
	return _slot_class


## Step to the next box class, wrapping. Driven off the shipped ladder so a class added
## there is reachable here without a second list to keep in step.
func _cycle_slot_class() -> void:
	var ladder: Array = AuthoredMap.SLOT_BOX_CLASSES
	var at := ladder.find(_slot_class)
	pick_slot_class(str(ladder[(at + 1) % ladder.size()]) if at >= 0 else str(ladder[0]))


func pick_slot_class(value: String) -> void:
	_slot_class = value
	if _tool != TOOL_SLOT:
		set_tool(TOOL_SLOT)
	else:
		_refresh_status()


## Every slot as a world-space box, for the overlay and for the click test.
##
## Reads the document being EDITED, falling back to the saved one only while the editor holds
## nothing — which is the state on a fresh boot with no document. There used to be a second
## builder for the saved case; see the header of `map_editor_slot_boxes.gd` for what that
## cost.
func document_slot_boxes() -> Array:
	var live: Dictionary = _document.data().get("settlements", {})
	var source: Dictionary = live if not live.is_empty() else AuthoredMap.settlements()
	return MapEditorSlotBoxes.build(source, _tile_centres(source))


## Tile centres in world units, for the tiles a document puts slots on. Absent tiles are left
## out, so the builder can skip slots this map has nowhere to put.
func _tile_centres(settlements: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return out
	var tiles: Dictionary = terrain.get("tiles")
	for tile_id in MapEditorSlotBoxes.tile_ids(settlements):
		var coord: Vector2i = terrain.call("id_to_coord", tile_id)
		if tiles.has(coord):
			out[tile_id] = terrain.call("map_to_local",
				terrain.call("map_coord_for_tile_coord", coord))
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
	_repaint()
	_set_status("%s = %d  (rebuilt from parameters — corner edits cleared)"
		% [str(special_parameter_names()[index]), int(sides[index])])
	_refresh_status()


## The layer visibility controller. The panel owns the buttons; a capture harness needs to
## turn a world layer on without one.
func layers() -> MapEditorLayers:
	return _layers


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
	_repaint()
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
## Which KINDS a small marquee around a point would select. For the harness: the asymmetry
## between click-select and marquee-select is deliberate and needs asserting, not trusting.
func marquee_kinds_for_test(world: Vector2) -> Array:
	var rect := Rect2(world - Vector2(12.0, 12.0), Vector2(24.0, 24.0))
	var kinds: Array = []
	for entry_value in MapEditorSelection.in_rect(_document.data(), rect):
		var kind := str((entry_value as Dictionary).get("kind", ""))
		if not kinds.has(kind):
			kinds.append(kind)
	return kinds


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
	# Picking any tool leaves shape mode — the owner's dismissal rule alongside a left click
	# on empty ground.
	if value != _tool:
		_leave_shape_mode()
	if value == _tool:
		return
	# Leaving the pen mid-stroke would otherwise strand a half-drawn road that no longer has
	# a tool to finish it.
	if _road_tool.is_drawing():
		_road_tool.abandon()
	_trace_tool.cancel_trace()
	_shape_tool.abandon()
	_poly_points = []
	_anchor_grab = {}
	_grabbed = []
	_pending_hit = {}
	_marquee_from = Vector2.INF
	_marquee_to = Vector2.INF
	_repaint()
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


## Tiles carrying at least one NON-WATER deposit, with the hex ring to draw and a short
## label. Water is excluded deliberately: 123 tiles carry it against 98 with anything else,
## and a water pump is an industrial building, not an extraction one — marking water would
## bury the tiles this overlay exists to find.
func deposit_tiles() -> Array:
	if not _deposit_cache.is_empty():
		return _deposit_cache
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return []
	for coord in (terrain.get("tiles") as Dictionary).keys():
		var tile: Dictionary = (terrain.get("tiles") as Dictionary)[coord]
		var tile_id := str(tile.get("id", ""))
		var what := _non_water_deposits(tile_id)
		if what == "":
			continue
		var centre: Vector2 = terrain.call("map_to_local",
			terrain.call("map_coord_for_tile_coord", coord))
		_deposit_cache.append({"centre": centre, "what": what})
	return _deposit_cache


## The deposit names on a tile with water dropped, comma separated, or "" when there are none.
func _non_water_deposits(tile_id: String) -> String:
	var raw := str(Catalog.tile_deposits_raw(tile_id))
	if raw == "":
		return ""
	var names := PackedStringArray()
	for token in raw.split("|", false):
		var name := str(token).split("(", false)[0].strip_edges().to_lower()
		if name == "" or name == "water" or names.has(name):
			continue
		names.append(name)
	return ", ".join(names)


## THE BUILDABILITY REPORT for one tile — what the sim will allow, what the zones can hold,
## and where those two disagree. A designer draws zones by eye; this is the arithmetic.
##
## The disagreement is the point. Land capacity and zone area are two independent limits and
## either can bind: a generous zone on a mountain is capped by terrain, and a thin zone on
## rural ground is capped by its own area. Only one of them is visible while drawing.
func tile_report(tile_id: String) -> Dictionary:
	if tile_id == "":
		return {}
	var terrain_name := Catalog.tile_type(tile_id)
	var cap := MatchState.max_tile_land(tile_id)
	# Sea is not in the terrain cap table, so it falls through to the 200 default — a number
	# that means nothing there. Offshore platforms and offshore wind farms DO stand on water,
	# so it is not "unbuildable"; it is a different kind of tile, and the report says which
	# rather than quoting a capacity for factories that can never be built.
	var offshore := terrain_name == "sea" or terrain_name == "deep_sea"
	var out := {"tile": tile_id, "terrain": terrain_name, "cap": cap, "offshore": offshore,
		"zones": [], "fits": []}
	if offshore:
		out["fits"] = []
		out["decor"] = _tile_decor_counts(tile_id)
		return out

	# By LAND: what the sim's size-unit budget allows, for the sizes that actually exist.
	for entry in [["standard plant", 15], ["furnace / power", 18], ["farm", 20], ["mine", 25]]:
		out["fits"].append({"what": str(entry[0]), "size": int(entry[1]),
			"count": int(cap / int(entry[1]))})

	# By ZONE AREA: an UPPER BOUND, because it assumes perfect packing of square boxes into
	# the polygon. Reported as such — a number that pretends to be exact here would be worse
	# than no number, since it is the optimistic side that misleads.
	var box: float = (BuildingVisualsRef.AUTHORED_SLOT_BOXES["standard"] as Vector2).x
	for kind_value in AuthoredMap.ZONE_KINDS:
		var kind := str(kind_value)
		var area := 0.0
		for zone_value in _document_zones(tile_id, kind):
			area += absf(_polygon_area(zone_value as Dictionary))
		if area <= 0.0:
			continue
		out["zones"].append({"kind": kind, "area": area,
			"max_boxes": int(area / (box * box))})
	out["decor"] = _tile_decor_counts(tile_id)
	return out


## Zones of one kind over a tile, read from the document being EDITED rather than the saved
## one — the report has to describe what is on screen.
func _document_zones(tile_id: String, kind: String) -> Array:
	var out: Array = []
	for settlement_value in (_document.data().get("settlements", {}) as Dictionary).values():
		for zone_value in ((settlement_value as Dictionary).get("zones", []) as Array):
			if typeof(zone_value) != TYPE_DICTIONARY:
				continue
			var zone: Dictionary = zone_value
			if str(zone.get("kind", "")) != kind:
				continue
			var tiles: Array = zone.get("tiles", []) as Array
			if tiles.is_empty() or tiles.has(tile_id):
				out.append(zone)
	return out


func _polygon_area(record: Dictionary) -> float:
	var pts: Array = record.get("outline", []) as Array
	if pts.size() < 3:
		return 0.0
	var total := 0.0
	for i in pts.size():
		var a: Array = pts[i] as Array
		var b: Array = pts[(i + 1) % pts.size()] as Array
		if a == null or b == null or a.size() < 2 or b.size() < 2:
			return 0.0
		total += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
	return total * 0.5


## Decorative masses over a tile, split by whether they were offered up. What a building here
## would cost in fabric.
func _tile_decor_counts(tile_id: String) -> Dictionary:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return {"total": 0, "protected": 0}
	var coord: Vector2i = terrain.call("id_to_coord", tile_id)
	if not (terrain.get("tiles") as Dictionary).has(coord):
		return {"total": 0, "protected": 0}
	var centre: Vector2 = terrain.call("map_to_local",
		terrain.call("map_coord_for_tile_coord", coord))
	var total := 0
	var protected := 0
	for settlement_value in (_document.data().get("settlements", {}) as Dictionary).values():
		for key in ["decor", "specials"]:
			for record_value in ((settlement_value as Dictionary).get(key, []) as Array):
				if typeof(record_value) != TYPE_DICTIONARY:
					continue
				var record: Dictionary = record_value
				if not _record_over_tile(record, centre):
					continue
				total += 1
				if not bool(record.get("sacrificial", false)):
					protected += 1
	return {"total": total, "protected": protected}


## Is a mass's anchor inside this tile's box? The tile box, not the hex — a cheap test that
## over-counts slightly at the corners, which is the safe direction for a warning.
func _record_over_tile(record: Dictionary, centre: Vector2) -> bool:
	var at := Vector2.INF
	if record.has("pos"):
		var pos: Array = record.get("pos", []) as Array
		if pos.size() >= 2:
			at = Vector2(float(pos[0]), float(pos[1]))
	elif record.has("outline"):
		var outline: Array = record.get("outline", []) as Array
		if not outline.is_empty():
			var first: Array = outline[0] as Array
			if first != null and first.size() >= 2:
				at = Vector2(float(first[0]), float(first[1]))
	if at == Vector2.INF:
		return false
	return absf(at.x - centre.x) <= 270.0 and absf(at.y - centre.y) <= 240.0


## Turn a tile's authored SLOTS into one industrial zone covering the ground they reserved,
## and drop the slots. The convex hull of their boxes, simplified to the zone corner cap.
##
## The point is that 31 tiles were slotted by hand before zones existed, and redrawing them
## is the only thing standing between that work and the mechanism that replaced it.
func convert_slots_to_zone(tile_id: String) -> String:
	var boxes: Array = []
	for box_value in document_slot_boxes():
		if str((box_value as Dictionary).get("tile_id", "")) == tile_id:
			boxes.append(box_value)
	if boxes.is_empty():
		return "No slots on %s to convert." % tile_id
	var corners := PackedVector2Array()
	for box_value in boxes:
		var box: Dictionary = box_value
		var centre: Vector2 = box["centre"]
		var size: Vector2 = box["size"]
		var angle := float(box["angle"])
		for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5),
				Vector2(-0.5, 0.5)]:
			corners.append(centre + (corner * size).rotated(angle))
	var hull := Geometry2D.convex_hull(corners)
	if hull.size() < 3:
		return "Those slots do not enclose an area."
	# convex_hull repeats the first point to close the ring; the document stores open rings.
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.remove_at(hull.size() - 1)
	hull = _simplify_ring(hull, AuthoredMap.ZONE_MAX_VERTICES)

	var settlement := _ensure_settlement()
	var next_id := int(settlement.get("next_id", 1))
	_document.begin_edit("slots to zone")
	settlement = _ensure_settlement()
	settlement["next_id"] = next_id + 1
	var outline: Array = []
	for v in hull:
		outline.append([v.x, v.y])
	var zones: Array = settlement.get("zones", []) as Array
	zones.append({"id": "z:%s:%d" % [_settlement, next_id], "kind": "industrial",
		"tiles": [tile_id], "outline": outline})
	settlement["zones"] = zones
	# The slots are gone: leaving them would keep _claim_slot seating buildings in boxes the
	# zone was drawn to replace, which is the worst of both mechanisms.
	var slots: Dictionary = settlement.get("slots", {})
	var removed := 0
	if slots.has(tile_id):
		removed = ((slots[tile_id] as Dictionary).get("pins", []) as Array).size()
		slots.erase(tile_id)
		settlement["slots"] = slots
	_repaint()
	return "%s: %d slot(s) became an industrial zone of %d corners." \
		% [tile_id, removed, hull.size()]


## Drop the corners that matter least until a ring is within `limit`, by removing whichever
## vertex changes the enclosed area least. Keeps the shape rather than the vertex count.
func _simplify_ring(ring: PackedVector2Array, limit: int) -> PackedVector2Array:
	var out := ring.duplicate()
	while out.size() > limit:
		var drop := 0
		var least := INF
		for i in out.size():
			var a: Vector2 = out[(i - 1 + out.size()) % out.size()]
			var b: Vector2 = out[i]
			var c: Vector2 = out[(i + 1) % out.size()]
			var loss := absf((b - a).cross(c - a)) * 0.5
			if loss < least:
				least = loss
				drop = i
		out.remove_at(drop)
	return out


## The tile under the pointer, for the report. Falls back to the last one clicked so the
## report does not blank out the moment the pointer leaves the map for the panel.
func _hovered_tile() -> String:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null or _camera == null:
		return _report_tile
	var world := _world_at(get_viewport().get_mouse_position())
	var coord: Vector2i = terrain.call("tile_coord_for_map_coord",
		terrain.call("local_to_map", world))
	var tiles: Dictionary = terrain.get("tiles")
	if tiles.has(coord):
		_report_tile = str((tiles[coord] as Dictionary).get("id", ""))
	return _report_tile


## Convert the slots on the tile under the pointer. The panel has no notion of which tile is
## meant, and asking would be a dialog for something a pointer already answers.
func convert_focused_slots_to_zone() -> void:
	var tile_id := _hovered_tile()
	if tile_id == "":
		_set_status("Point at a tile first.")
		return
	_set_status(convert_slots_to_zone(tile_id))
	_refresh_status()


func toggle_deposit_marks() -> void:
	if _overlay != null:
		_overlay.show_deposit_marks = not _overlay.show_deposit_marks
		_repaint()
		_set_status("Extraction resources %s (%d tile(s))."
			% ["shown" if _overlay.show_deposit_marks else "hidden", deposit_tiles().size()])
		_refresh_status()


func deposit_marks_shown() -> bool:
	return _overlay != null and _overlay.show_deposit_marks


func toggle_water_mask() -> void:
	if _overlay != null:
		_overlay.show_water_mask = not _overlay.show_water_mask
		_repaint()
	_refresh_status()


func toggle_grid() -> void:
	if _overlay != null:
		_overlay.show_grid = not _overlay.show_grid
		_repaint()
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
			_rebind_after_history()
			_repaint()
		"redo":
			_set_status(_document.redo())
			_rebind_after_history()
			_repaint()


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
	AuthoredMap.reset_cache()
	_document.reload()
	_refresh_world_layers()
	_selection = []
	_road_tool.abandon()
	_trace_tool.cancel_trace()
	_trace_tool.clear_dots()
	_repaint()
	var counts := _document.counts()
	_set_status("Opened '%s' — %d roads across %d settlement(s)."
		% [name, counts.roads, counts.settlements])
	_refresh_status()


## Repaint the game's own authored layers after the active document changes. They render
## from AuthoredMap, not from the editor's working copy, so without this an opened map is
## drawn on top of the one it replaced.
func _refresh_world_layers() -> void:
	if _world == null:
		return
	for node_name in ["AuthoredRoadVisuals", "AuthoredFabricVisuals"]:
		var node := _world.get_node_or_null(NodePath(node_name))
		if node != null and node is CanvasItem:
			(node as CanvasItem).queue_redraw()


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
	AuthoredMap.reset_cache()
	_set_status("Saved '%s'%s" % [name,
		"" if pointed == "" else "  (but the active pointer failed: %s)" % pointed])
	_refresh_status()


func _reload() -> void:
	AuthoredMap.reset_cache()
	_document.reload()
	_refresh_status()


## Leaving ALWAYS asks (owner, 2026-08-16). Escape is the same key that cancels a stroke and
## clears a selection, so it gets pressed often and by reflex; a confirmation is the only
## thing standing between that reflex and losing a session.
func _leave() -> void:
	_confirm_action = "leave"
	_confirm.ask("Return to the main menu?%s" % ("\n\nUNSAVED CHANGES WILL BE LOST."
		if _document.is_dirty() else ""))
	_panel.refresh()


func _do_leave() -> void:
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


# ── Procedural region cheats ────────────────────────────────────────────────────

## `enable|disable procedural <north|arin|vandel|capital|all>`, called by the debug
## terminal through the "map_editor" group. Enabling cuts that city's share of the
## whole-map import (`data/map_authored/procedural.json`) into the WORKING document as an
## editable settlement — buildings as polygons, roads, parks, plazas; disabling removes
## that settlement again. Both are ordinary edits: undoable, and on disk only after a save.
## Returns the line the terminal prints.
func procedural_region_command(verb: String, region: String) -> String:
	if verb != "enable" and verb != "disable":
		return "usage: enable|disable procedural <north|arin|vandel|capital|all>"
	if not _ready_to_edit:
		return "the editor is still building the world — try again in a moment"
	if region == "all":
		var lines := PackedStringArray()
		for one in MapEditorRegionImport.REGIONS:
			lines.append(procedural_region_command(verb, str(one)))
		return "\n".join(lines)
	if not MapEditorRegionImport.is_region(region):
		return "usage: %s procedural <north|arin|vandel|capital|all>" % verb
	var key: String = MapEditorRegionImport.settlement_key(region)
	var settlements_value: Variant = _document.data().get("settlements", {})
	var settlements: Dictionary = settlements_value if typeof(settlements_value) == TYPE_DICTIONARY else {}

	if verb == "disable":
		if not settlements.has(key):
			return "procedural %s is not shown" % region
		_document.begin_edit("hide procedural %s" % region)
		(_document.data().get("settlements", {}) as Dictionary).erase(key)
		_after_region_change()
		return "procedural %s hidden — its records are out of the document" % region

	if settlements.has(key):
		return "procedural %s is already shown  ('disable procedural %s' removes it)" % [region, region]
	var loaded: Dictionary = MapEditorRegionImport.load_source()
	if loaded.has("problem"):
		return str(loaded["problem"])
	var centres := _land_tile_centres()
	var covered: Dictionary = MapEditorRegionImport.covered_tiles(_document.data())
	var partitioned: Dictionary = MapEditorRegionImport.partition(centres, covered)
	if partitioned.is_empty():
		return "could not split the map — a region anchor tile is missing from the terrain"
	var tiles_of_region: Dictionary = MapEditorRegionImport.region_tiles(partitioned, region)
	if tiles_of_region.is_empty():
		return "nothing left near %s — every tile there is already authored" % region
	var built: Dictionary = MapEditorRegionImport.build_settlement(
		loaded["doc"] as Dictionary, region, tiles_of_region, covered,
		_tile_id_at, centres)
	if built.is_empty():
		return "nothing to import near %s" % region
	_document.begin_edit("show procedural %s" % region)
	var live: Dictionary = _document.data()
	var live_settlements: Dictionary = live.get("settlements", {}) as Dictionary
	live_settlements[key] = built
	live["settlements"] = live_settlements
	_after_region_change()
	focus_tile(str(MapEditorRegionImport.REGION_ANCHORS[region]), 0.35)
	return ("procedural %s: %d building shapes, %d roads, %d parks, %d plazas over %d tiles"
		+ " — editable like anything else; 'disable procedural %s' removes it") % [region,
		(built.get("specials", []) as Array).size(), (built.get("roads", []) as Array).size(),
		(built.get("parks", []) as Array).size(), (built.get("plazas", []) as Array).size(),
		(built.get("tiles", []) as Array).size(), region]


func _after_region_change() -> void:
	_repaint()
	_refresh_status()


## World-space centres of every LAND tile, {tile_id: Vector2} — the region partition's
## input. Sea and deep-sea tiles are out: the split is of the LANDMAP.
func _land_tile_centres() -> Dictionary:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return {}
	var out: Dictionary = {}
	var tiles: Dictionary = terrain.get("tiles")
	for coord in tiles.keys():
		var tile: Dictionary = tiles[coord]
		var kind := str(tile.get("type", ""))
		if kind == "" or kind == "sea" or kind == "deep_sea":
			continue
		var tile_id := str(tile.get("id", ""))
		if tile_id == "":
			continue
		out[tile_id] = terrain.call("map_to_local",
			terrain.call("map_coord_for_tile_coord", coord)) as Vector2
	return out


## The tile id under a world point, or "" — bound into the region importer as its anchor
## test, and shaped like `_tiles_under` for a single point.
func _tile_id_at(world: Vector2) -> String:
	var terrain := get_tree().get_first_node_in_group("hex_map")
	if terrain == null:
		return ""
	var tiles: Dictionary = terrain.get("tiles")
	var coord: Vector2i = terrain.call("tile_coord_for_map_coord",
		terrain.call("local_to_map", world))
	return str((tiles[coord] as Dictionary).get("id", "")) if tiles.has(coord) else ""
