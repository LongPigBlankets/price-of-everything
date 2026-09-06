extends Camera2D

# Movement
@export var pan_speed: float = 600.0          # pixels/sec when fully held
@export var edge_pan_enabled: bool = true
@export var edge_pan_margin: int = 15         # pixels from screen edge to trigger
@export var edge_pan_speed: float = 500.0

# Zoom
@export var zoom_min: float = 0.3              # zoomed out (smaller = see more)
@export var zoom_max: float = 2.5              # zoomed in
@export var zoom_step: float = 0.1
@export var zoom_smoothing: float = 8.0
## How many tiles tall the viewport is at maximum zoom. 1.25 puts ONE tile at 80% of the
## viewport height (owner, 2026-09-03) — twice the reach of the 2.5 it replaced, which is why
## the authored bake grew a near tier: at this zoom the old textures would be magnified.
@export var zoomed_in_tile_count: float = 1.25

var _target_zoom: Vector2
# Screen point the current zoom gesture is anchored on (the cursor), held fixed in world
# space while `zoom` eases toward `_target_zoom`. See _adjust_zoom / _apply_zoom_smoothing.
var _zoom_anchor := Vector2.ZERO
var _zoom_anchor_active := false
var _intro_tween: Tween
var _pan_tween: Tween
var _pan_target := Vector2.INF   # destination of the live pan (see pan_to_world)

# Drag-to-pan: armed by an unhandled left/middle press (so drags can never start
# over UI), promoted to a real drag after DRAG_THRESHOLD px of motion. Motion and
# the release are then consumed, so the map click that would have fired on
# release never happens.
const DRAG_THRESHOLD := 8.0
var _drag_button: int = -1
var _drag_armed := false
var _dragging := false
var _drag_accum := Vector2.ZERO

## Set true by the Empire view while it owns the full screen, so map pan/zoom go quiet
## and the (hidden) map camera does not drift behind the overlay. See empire_view.gd.
var input_blocked: bool = false

func _ready() -> void:
	add_to_group("camera")   # lets the loading screen find us for the intro zoom
	make_current()
	_configure_for_map()
	_target_zoom = zoom
	call_deferred("_configure_for_map_after_scene_ready")


## Gentle one-shot "establishing" zoom played when the player leaves the loading
## screen: ease from the full-map view (effective zoom-out) to `frac` of the way
## toward the closest zoom, over `dur` seconds, slowing into the end. Both `zoom`
## and `_target_zoom` are driven together so the per-frame smoothing never fights
## the tween.
func start_intro_zoom(frac: float, dur: float) -> void:
	var start_z := _effective_zoom_min()
	var end_z := lerpf(start_z, zoom_max, clampf(frac, 0.0, 1.0))
	if _intro_tween != null and _intro_tween.is_valid():
		_intro_tween.kill()
	zoom = Vector2.ONE * start_z
	_target_zoom = zoom
	_intro_tween = create_tween()
	_intro_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_intro_tween.tween_method(_apply_intro_zoom, start_z, end_z, dur)


func _apply_intro_zoom(z: float) -> void:
	zoom = Vector2.ONE * z
	_target_zoom = zoom

func _configure_for_map_after_scene_ready() -> void:
	_configure_for_map()
	_target_zoom = zoom

## The tutorial confines the camera to a small board rect. While `_external_clamp` is
## set, `_configure_for_map` must not stomp map_min/map_max back to the full map.
var _external_clamp := false

## Clamp the camera to an explicit world rect (tutorial board). Recenters on it and
## widens the zoom-out so the whole rect fits.
func set_bounds_rect(rect: Rect2) -> void:
	if rect.size == Vector2.ZERO:
		return
	_external_clamp = true
	map_min = rect.position
	map_max = rect.end
	position = rect.get_center()
	var viewport_size := get_viewport_rect().size
	if viewport_size.x > 0.0 and rect.size.x > 0.0 and rect.size.y > 0.0:
		zoom_min = minf(viewport_size.x / rect.size.x, viewport_size.y / rect.size.y)
	_target_zoom = Vector2.ONE * _effective_zoom_min()
	zoom = _target_zoom

## Release the tutorial clamp and restore the full-map bounds.
func clear_bounds_rect() -> void:
	_external_clamp = false
	_configure_for_map()
	_target_zoom = zoom

func _configure_for_map() -> void:
	if _external_clamp:
		return
	var hex_map := get_tree().get_first_node_in_group("hex_map")
	if hex_map == null or not hex_map.has_method("map_world_rect"):
		return
	var map_rect: Rect2 = hex_map.map_world_rect()
	if map_rect.size == Vector2.ZERO:
		return
	map_min = map_rect.position
	map_max = map_rect.end
	position = map_rect.get_center()
	var viewport_size := get_viewport_rect().size
	if viewport_size.x > 0.0 and map_rect.size.x > 0.0:
		zoom_min = viewport_size.x / map_rect.size.x
	if hex_map.tile_set != null:
		var tile_height := float(hex_map.tile_set.tile_size.y)
		if tile_height > 0.0:
			zoom_max = viewport_size.y / (tile_height * zoomed_in_tile_count)
	zoom = Vector2.ONE * zoom_min

func _process(delta: float) -> void:
	if not input_blocked:
		_handle_keyboard_pan(delta)
		if edge_pan_enabled:
			_handle_edge_pan(delta)
	_apply_zoom_smoothing(delta)
	_clamp_to_bounds()

## How long a UI-driven focus pan takes (ledger row, notification jump-to-tile, a
## tutorial step recentring the board). The tutorial raises this for its own steps so
## they settle instead of snapping; every other caller keeps the snappy default.
@export var ui_focus_duration: float = 0.3

## Smoothly pan to a world position — the UI-driven focus move (ledger/panel
## selection). Manual pans (keyboard, edge, drag) cancel it.
func pan_to_world(target: Vector2, dur: float = 0.3) -> void:
	# IDEMPOTENT: a repeat request for essentially the same destination while a pan is
	# already in flight must not restart the tween. The tutorial re-runs a step's setup
	# whenever the spotlight target has not appeared yet (_ensure_locked_panel_open), which
	# re-emitted focus_tile and restarted this pan from wherever it had reached — measured
	# as a 178px single-frame jerk in the middle of an otherwise smooth 1s move, which is
	# the "map snaps in the background" during tutorial steps.
	# Pre-clamp the destination. The per-frame _clamp_to_bounds would otherwise OVERRIDE the
	# tween every frame — during the tutorial the board rect is narrower than the viewport,
	# so the clamp force-centres the camera and the two fought each other. When the tween
	# finally died the fight stopped and the camera snapped to the centre: a measured 542px
	# single-frame jump, landing exactly as the pan ended. Aiming somewhere legal removes it.
	target = clamped_position(target)
	if _pan_tween != null and _pan_tween.is_valid() and _pan_target.distance_to(target) < 1.0:
		return
	_kill_pan_tween()
	_pan_target = target
	_pan_tween = create_tween()
	_pan_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_pan_tween.tween_property(self, "position", target, dur)

## Pan to a tile by id ("tile_X_Y"). Used when a building or tile is selected
## THROUGH UI (ledger, panels) — direct map clicks deliberately don't pan.
func pan_to_tile(tile_id: String, dur: float = 0.3) -> void:
	var hex_map := get_tree().get_first_node_in_group("hex_map")
	if hex_map == null or not hex_map.has_method("id_to_coord"):
		return
	var coord: Vector2i = hex_map.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return
	var cell: Vector2i = hex_map.map_coord_for_tile_coord(coord)
	pan_to_world(hex_map.to_global(hex_map.map_to_local(cell)), dur)

func _kill_pan_tween() -> void:
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
	_pan_target = Vector2.INF   # no live destination; the next focus request always tweens

func _input(event: InputEvent) -> void:
	# Drag promotion/consumption runs in _input so the consumed release is
	# guaranteed to beat every _unhandled_input listener (hex_map's click).
	if input_blocked or not _drag_armed:
		return
	if event is InputEventMouseMotion:
		_drag_accum += event.relative
		if not _dragging and _drag_accum.length() >= DRAG_THRESHOLD:
			_dragging = true
			_kill_pan_tween()
		if _dragging:
			position -= event.relative / zoom.x
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == _drag_button:
		if _dragging:
			get_viewport().set_input_as_handled()
		_drag_armed = false
		_dragging = false
		_drag_button = -1

## The panel the pointer is over, or null. Every HUD panel is a direct child of
## HUDContent, so this is one shallow pass rather than a tree walk, and it is only ever
## asked on a wheel event.
##
## Cached by name: the node is created once per match and the camera outlives nothing.
var _ui_root: Node = null

func _panel_under_pointer() -> Control:
	if _ui_root == null or not is_instance_valid(_ui_root):
		var scene := get_tree().current_scene if is_inside_tree() else null
		_ui_root = scene.find_child("HUDContent", true, false) if scene != null else null
		if _ui_root == null:
			return null
	var mouse := get_viewport().get_mouse_position()
	for child in _ui_root.get_children():
		if not (child is Control):
			continue
		var panel := child as Control
		# IGNORE-filter children are pass-through decoration (dim layers, legends): the
		# pointer is not 'on' them in any sense the player would recognise.
		if not panel.is_visible_in_tree() or panel.mouse_filter == Control.MOUSE_FILTER_IGNORE:
			continue
		if panel.get_global_rect().has_point(mouse):
			return panel
	return null

func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_armed = true
			_drag_button = event.button_index
			_drag_accum = Vector2.ZERO
			return   # not consumed: a clean click still selects on release
		var wheel: bool = (event.button_index == MOUSE_BUTTON_WHEEL_UP
				or event.button_index == MOUSE_BUTTON_WHEEL_DOWN)
		if wheel and _panel_under_pointer() != null:
			# The wheel belongs to the panel under the cursor. A ScrollContainer only
			# CONSUMES the wheel while it still has somewhere to scroll, so at the end of a
			# list — or in a panel with no scroll at all — the event fell through to here and
			# zoomed the map out from under the player. Swallow it instead.
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_adjust_zoom(_scroll_factor(event))
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_adjust_zoom(-_scroll_factor(event))
			get_viewport().set_input_as_handled()
	elif event is InputEventMagnifyGesture:
		_adjust_zoom(event.factor - 1.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("camera_zoom_in"):
		_adjust_zoom(1.0, false)    # keyboard: anchor on centre, the mouse is irrelevant
	elif event.is_action_pressed("camera_zoom_out"):
		_adjust_zoom(-1.0, false)

func _scroll_factor(event: InputEventMouseButton) -> float:
	return maxf(absf(event.factor), 1.0)

## `toward_cursor` records the cursor as the zoom anchor; the correction is then applied
## FRAME BY FRAME in _apply_zoom_smoothing as `zoom` eases toward `_target_zoom`.
##
## It used to move `position` instantly here while `zoom` lerped over several frames. On a
## mouse that reads as a small snap; on a trackpad, which fires a stream of small deltas,
## every event added another instant jump on top of an unfinished lerp and the map juddered
## and felt like it was fighting the scroll. Anchoring inside the smoothing means the world
## point under the cursor is held on every rendered frame, so the view slides toward what
## you are pointing at instead of arguing with you.
func _adjust_zoom(delta_steps: float, toward_cursor: bool = true) -> void:
	var effective_min := _effective_zoom_min()
	var new_zoom := clampf(_target_zoom.x + zoom_step * delta_steps, effective_min, zoom_max)
	if is_equal_approx(new_zoom, _target_zoom.x):
		return
	if toward_cursor:
		_zoom_anchor = get_viewport().get_mouse_position()
		_zoom_anchor_active = true
		_kill_pan_tween()   # a UI focus pan would fight the anchor
	else:
		_zoom_anchor_active = false
	_target_zoom = Vector2(new_zoom, new_zoom)


func _effective_zoom_min() -> float:
	var viewport_size := get_viewport_rect().size
	var map_size := map_max - map_min
	var fit_zoom_x := viewport_size.x / map_size.x
	var fit_zoom_y := viewport_size.y / map_size.y
	return maxf(zoom_min, minf(fit_zoom_x, fit_zoom_y))

func _handle_keyboard_pan(delta: float) -> void:
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return  # a text field (e.g. the debug terminal) has keyboard focus
	var direction := Vector2.ZERO
	if Input.is_action_pressed("camera_right"):
		direction.x += 1
	if Input.is_action_pressed("camera_left"):
		direction.x -= 1
	if Input.is_action_pressed("camera_down"):
		direction.y += 1
	if Input.is_action_pressed("camera_up"):
		direction.y -= 1

	if direction != Vector2.ZERO:
		_kill_pan_tween()
		# Pan speed scales inversely with zoom — feels right whether zoomed in or out
		position += direction.normalized() * pan_speed * delta / zoom.x

func _handle_edge_pan(delta: float) -> void:
	var viewport := get_viewport()
	var mouse_pos := viewport.get_mouse_position()
	var screen_size := viewport.get_visible_rect().size
	var direction := Vector2.ZERO

	if mouse_pos.x < edge_pan_margin:
		direction.x -= 1
	elif mouse_pos.x > screen_size.x - edge_pan_margin:
		direction.x += 1

	if mouse_pos.y < edge_pan_margin:
		direction.y -= 1
	elif mouse_pos.y > screen_size.y - edge_pan_margin:
		direction.y += 1

	if direction != Vector2.ZERO:
		_kill_pan_tween()
		position += direction.normalized() * edge_pan_speed * delta / zoom.x

func _apply_zoom_smoothing(delta: float) -> void:
	var effective_min := _effective_zoom_min()
	_target_zoom = _target_zoom.clamp(
		Vector2(effective_min, effective_min),
		Vector2(zoom_max, zoom_max))

	var previous := zoom.x
	zoom = zoom.lerp(_target_zoom, zoom_smoothing * delta)
	# Hold the anchored world point still across THIS frame's zoom change:
	#   pos += offset/z_prev - offset/z_now
	if _zoom_anchor_active and previous > 0.0 and zoom.x > 0.0 and not is_equal_approx(previous, zoom.x):
		var offset := _zoom_anchor - get_viewport_rect().size * 0.5
		position += offset / previous - offset / zoom.x
	if _zoom_anchor_active and is_equal_approx(zoom.x, _target_zoom.x):
		_zoom_anchor_active = false   # settled; stop steering until the next gesture

@export var map_min: Vector2 = Vector2(-880, -500)  # top-left of map
@export var map_max: Vector2 = Vector2(800, 400)    # bottom-right of map

func _clamp_to_bounds() -> void:
	position = clamped_position(position)


## Where `pos` is actually allowed to sit, given the bounds and the current zoom. Public so
## pan targets can be pre-clamped with the EXACT same rule the per-frame clamp applies —
## see pan_to_world. On an axis where the map is narrower than the viewport there is only
## one legal value (the centre), so a pan there must not aim anywhere else.
func clamped_position(pos: Vector2) -> Vector2:
	var viewport_size := get_viewport_rect().size
	var half_view := (viewport_size * 0.5) / zoom

	var min_x := map_min.x + half_view.x
	var max_x := map_max.x - half_view.x
	var min_y := map_min.y + half_view.y
	var max_y := map_max.y - half_view.y

	var out := pos
	if min_x > max_x:
		out.x = (map_min.x + map_max.x) * 0.5
	else:
		out.x = clamp(out.x, min_x, max_x)

	if min_y > max_y:
		out.y = (map_min.y + map_max.y) * 0.5
	else:
		out.y = clamp(out.y, min_y, max_y)
	return out
		
