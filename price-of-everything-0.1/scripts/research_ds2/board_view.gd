extends Control
## The Research panel in DS2: the window the patent board (patent_board.gd) is seen through, inside its steel
## frame. The board is a canvas: the view scales and moves it and draws the cork under it.
##   zoom    the mouse wheel, a trackpad pinch, or the + and - keys (0 puts it back), about the pointer
##   pan     a drag with the left or middle button, or a trackpad's two finger swipe
##   click   a press and release without moving more than DRAG_SLOP px picks the drawing under the pointer
##           (while licences are being chosen); a drag that starts on a drawing pans and picks nothing
## Zoom runs from the whole board fitted to the window's height (never under ZOOM_FLOOR) to ZOOM_MAX. The board
## stays within reach: narrower than the window it is centred, shorter it sits at the top, else it can move only
## as far as its own edges. The board is laid out for the window's width at zoom 1, the zoom it opens at.

signal view_changed
## A press, a wheel turn or a gesture on the board, whatever it then does.
signal interacted

const Board := preload("res://scripts/research_ds2/patent_board.gd")

const ZOOM_MAX := 2.0
const ZOOM_FLOOR := 0.3
## However tall the board, the view zooms out at least this far.
const ZOOM_OUT_AT_LEAST := 0.75
const ZOOM_STEP := 1.12
const DRAG_SLOP := 5.0
const PAN_GESTURE_SPEED := 12.0

var board: Control
var zoom := 1.0
var offset := Vector2.ZERO
var _press_pos := Vector2.INF
var _press_button := 0
var _dragging := false


func _init() -> void:
	name = "BoardView"
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	board = Board.new()
	add_child(board)
	resized.connect(_on_resized)
	board.resized.connect(_apply)


func _on_resized() -> void:
	board.size.x = size.x
	_apply()


## The least zoom: the whole board in the window's height, at least ZOOM_OUT_AT_LEAST, never under ZOOM_FLOOR.
func zoom_min() -> float:
	var h := maxf(board.size.y, 1.0)
	return clampf(minf(size.y / h, ZOOM_OUT_AT_LEAST), ZOOM_FLOOR, 1.0)


## Back to zoom 1 at the board's top left, as it opens.
func reset() -> void:
	zoom = 1.0
	offset = Vector2.ZERO
	_apply()


## Zooms by `factor` about `at` (a point in the view), so what is under it stays under it.
func zoom_at(at: Vector2, factor: float) -> void:
	var z := clampf(zoom * factor, zoom_min(), ZOOM_MAX)
	var p := (at - offset) / zoom
	zoom = z
	offset = at - p * zoom
	_apply()


## Zooms so the whole board shows.
func zoom_to_fit() -> void:
	zoom = zoom_min()
	offset = Vector2.ZERO
	_apply()


func pan(delta: Vector2) -> void:
	offset += delta
	_apply()


func _apply() -> void:
	_clamp()
	board.position = offset
	board.scale = Vector2(zoom, zoom)
	queue_redraw()
	view_changed.emit()


func _clamp() -> void:
	var content := board.size * zoom
	if content.x <= size.x:
		offset.x = (size.x - content.x) * 0.5
	else:
		offset.x = clampf(offset.x, size.x - content.x, 0.0)
	if content.y <= size.y:
		offset.y = 0.0
	else:
		offset.y = clampf(offset.y, size.y - content.y, 0.0)


## The cork under everything in view, laid in the board's own frame so it moves and scales with the board.
func _draw() -> void:
	draw_set_transform(offset, 0.0, Vector2(zoom, zoom))
	Board.draw_cork(self, Rect2(-offset / zoom, size / zoom))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A point in the view as a point on the board.
func board_point(at: Vector2) -> Vector2:
	return (at - offset) / zoom


## The drawing under a point in the view, or null.
func card_at(at: Vector2) -> Control:
	var p := board_point(at)
	for c: Control in board.call("cards"):
		if Rect2(c.position, c.size).has_point(p):
			return c
	return null


## Moves the board, at its zoom, until `card` shows whole (as near as the window allows).
func ensure_visible(card: Control) -> void:
	if card == null:
		return
	var r := Rect2(offset + card.position * zoom, card.size * zoom)
	var view := Rect2(Vector2.ZERO, size).grow(-12.0)
	if view.encloses(r):
		return
	if r.position.x < view.position.x or r.end.x > view.end.x:
		offset.x += view.get_center().x - r.get_center().x
	if r.position.y < view.position.y or r.end.y > view.end.y:
		offset.y += view.get_center().y - r.get_center().y
	_apply()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			interacted.emit()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			zoom_at(mb.position, ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			zoom_at(mb.position, 1.0 / ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_press_pos = mb.position
				_press_button = mb.button_index
				_dragging = false
			else:
				if not _dragging and _press_pos != Vector2.INF and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
				_press_pos = Vector2.INF
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos != Vector2.INF:
			if not _dragging and mm.position.distance_to(_press_pos) > DRAG_SLOP:
				_dragging = true
				mouse_default_cursor_shape = Control.CURSOR_DRAG
			if _dragging:
				pan(mm.relative)
				accept_event()
		elif mouse_default_cursor_shape != Control.CURSOR_ARROW:
			mouse_default_cursor_shape = Control.CURSOR_ARROW
	elif event is InputEventMagnifyGesture:
		interacted.emit()
		var mg := event as InputEventMagnifyGesture
		zoom_at(mg.position, mg.factor)
		accept_event()
	elif event is InputEventPanGesture:
		interacted.emit()
		pan(-(event as InputEventPanGesture).delta * PAN_GESTURE_SPEED)
		accept_event()


## + and - zoom about the window's middle, 0 puts the view back. Typing in the search box is not seen here.
func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	match k.keycode:
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			zoom_at(size * 0.5, ZOOM_STEP)
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_at(size * 0.5, 1.0 / ZOOM_STEP)
		KEY_0, KEY_KP_0:
			reset()
		_:
			return
	interacted.emit()
	get_viewport().set_input_as_handled()


func _click(at: Vector2) -> void:
	var c := card_at(at)
	if c != null and bool(c.get("choosing")) and bool(c.get("eligible")):
		c.emit_signal("picked", c)
