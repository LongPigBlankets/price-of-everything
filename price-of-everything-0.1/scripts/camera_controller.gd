extends Camera2D

# Movement
@export var pan_speed: float = 600.0          # pixels/sec when fully held
@export var edge_pan_enabled: bool = true
@export var edge_pan_margin: int = 30         # pixels from screen edge to trigger
@export var edge_pan_speed: float = 500.0

# Zoom
@export var zoom_min: float = 0.3              # zoomed out (smaller = see more)
@export var zoom_max: float = 2.5              # zoomed in
@export var zoom_step: float = 0.1
@export var zoom_smoothing: float = 8.0
@export var zoomed_in_tile_count: float = 2.5

var _target_zoom: Vector2
var _intro_tween: Tween
var _pan_tween: Tween

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

## Smoothly pan to a world position — the UI-driven focus move (ledger/panel
## selection). Manual pans (keyboard, edge, drag) cancel it.
func pan_to_world(target: Vector2, dur: float = 0.3) -> void:
	_kill_pan_tween()
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

func _unhandled_input(event: InputEvent) -> void:
	if input_blocked:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_MIDDLE:
			_drag_armed = true
			_drag_button = event.button_index
			_drag_accum = Vector2.ZERO
			return   # not consumed: a clean click still selects on release
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
		_adjust_zoom(1.0)
	elif event.is_action_pressed("camera_zoom_out"):
		_adjust_zoom(-1.0)

func _scroll_factor(event: InputEventMouseButton) -> float:
	return maxf(absf(event.factor), 1.0)

func _adjust_zoom(delta_steps: float) -> void:
	var effective_min := _effective_zoom_min()
	_target_zoom = (_target_zoom + Vector2.ONE * zoom_step * delta_steps).clamp(
		Vector2(effective_min, effective_min),
		Vector2(zoom_max, zoom_max))

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

	zoom = zoom.lerp(_target_zoom, zoom_smoothing * delta)

@export var map_min: Vector2 = Vector2(-880, -500)  # top-left of map
@export var map_max: Vector2 = Vector2(800, 400)    # bottom-right of map

func _clamp_to_bounds() -> void:
	var viewport_size := get_viewport_rect().size
	var half_view := (viewport_size * 0.5) / zoom

	var min_x := map_min.x + half_view.x
	var max_x := map_max.x - half_view.x
	var min_y := map_min.y + half_view.y
	var max_y := map_max.y - half_view.y

	# If the map is smaller than the viewport on an axis, center the camera on that axis
	if min_x > max_x:
		var center_x := (map_min.x + map_max.x) * 0.5
		position.x = center_x
	else:
		position.x = clamp(position.x, min_x, max_x)

	if min_y > max_y:
		var center_y := (map_min.y + map_max.y) * 0.5
		position.y = center_y
	else:
		position.y = clamp(position.y, min_y, max_y)
		
