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

var _target_zoom: Vector2

func _ready() -> void:
	make_current()
	_target_zoom = zoom

func _process(delta: float) -> void:
	_handle_keyboard_pan(delta)
	if edge_pan_enabled:
		_handle_edge_pan(delta)
	_apply_zoom_smoothing(delta)
	_clamp_to_bounds()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_zoom_in"):
		_target_zoom = (_target_zoom + Vector2(zoom_step, zoom_step)).clamp(
			Vector2(zoom_min, zoom_min), Vector2(zoom_max, zoom_max))
	elif event.is_action_pressed("camera_zoom_out"):
		_target_zoom = (_target_zoom - Vector2(zoom_step, zoom_step)).clamp(
			Vector2(zoom_min, zoom_min), Vector2(zoom_max, zoom_max))

func _handle_keyboard_pan(delta: float) -> void:
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
		position += direction.normalized() * edge_pan_speed * delta / zoom.x

func _apply_zoom_smoothing(delta: float) -> void:
	# Compute the minimum zoom that still keeps the map filling the view
	var viewport_size := get_viewport_rect().size
	var map_size := map_max - map_min
	var fit_zoom_x := viewport_size.x / map_size.x
	var fit_zoom_y := viewport_size.y / map_size.y
	var effective_min : float = max(zoom_min, min(fit_zoom_x, fit_zoom_y))

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
		
