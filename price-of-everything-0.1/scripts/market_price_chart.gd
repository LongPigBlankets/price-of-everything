extends Control
## Read-only spot-price history. Gaps in older saves are never backfilled.
var good_id: String = ""
var _samples: Array = []
var _hover_index: int = -1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_exited.connect(func() -> void: _hover_index = -1; queue_redraw())
	MarketState.prices_updated.connect(refresh)
	CostSolver.costs_updated.connect(refresh)
	TurnManager.turn_resolution_completed.connect(refresh)
	refresh()

func refresh() -> void:
	if not is_visible_in_tree():
		return
	_samples = MarketState.history_for(good_id).filter(func(sample: Dictionary) -> bool: return int(sample.turn) <= int(TurnManager.current_turn))
	_hover_index = sample_at_x(get_local_mouse_position().x) if Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()) else -1
	queue_redraw()

func _plot_rect() -> Rect2:
	return Rect2(24, 40, maxf(1, size.x - 120), maxf(1, size.y - 70))

func _point(index: int, plot: Rect2, low: float, high: float) -> Vector2:
	var first: int = int(_samples[0].turn)
	var last: int = int(_samples[-1].turn)
	var x := float(int(_samples[index].turn) - first) / float(maxi(1, last - first))
	return Vector2(plot.position.x + x * plot.size.x,
		plot.end.y - (float(_samples[index].price) - low) / (high - low) * plot.size.y)

func sample_at_x(x: float) -> int:
	if _samples.is_empty():
		return -1
	var plot := _plot_rect()
	var fraction := clampf((x - plot.position.x) / plot.size.x, 0.0, 1.0)
	var target := lerpf(float(_samples[0].turn), float(_samples[-1].turn), fraction)
	var best := 0
	for i in range(1, _samples.size()):
		if absf(float(_samples[i].turn) - target) < absf(float(_samples[best].turn) - target):
			best = i
	return best

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not Rect2(Vector2.ZERO, size).has_point(get_local_mouse_position()):
		return
	if not event is InputEventKey or not event.pressed or event.echo or event.keycode != KEY_SPACE:
		return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed or event.shift_pressed:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	var scene := get_tree().current_scene
	var button := scene.find_child("EndTurnButton", true, false) as Button if scene != null else null
	if button != null and button.is_visible_in_tree() and not button.disabled:
		button.pressed.emit()
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey:
		return
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		return
	if event is InputEventMouseMotion:
		_hover_index = sample_at_x(event.position.x)
		queue_redraw()
	accept_event()

func _cost_for_sample(sample: Dictionary) -> float:
	# Match the market's produced-goods filter; historical costs must not leave
	# a reference line behind once the player no longer produces this good.
	if CostSolver.get_good_unit_cost(good_id) < 0.0:
		return -1.0
	return float(sample.get("cost_basis", -1.0))

func _draw() -> void:
	var font: Font = get_theme_default_font()
	var ink: Color = DS.PALETTE.TEXT
	var cream: Color = DS.PALETTE.ACCENT
	draw_rect(Rect2(Vector2.ZERO, size), Color("#081b2c"))
	draw_string(font, Vector2(12, 22), "Market price", HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 16, ink)
	if _samples.is_empty():
		draw_string(font, Vector2(12, 65), "No recorded prices yet", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ink)
		return
	var low: float = float(_samples[0].price)
	var high: float = low
	for sample: Dictionary in _samples:
		low = minf(low, float(sample.price))
		high = maxf(high, float(sample.price))
		var historical_cost: float = _cost_for_sample(sample)
		if historical_cost >= 0.0:
			low = minf(low, historical_cost)
			high = maxf(high, historical_cost)
	var pad: float = maxf(0.01, maxf(high - low, high * 0.04) * 0.15)
	low = maxf(0, low - pad)
	high += pad
	var plot: Rect2 = _plot_rect()
	var axis_colour := Color("#50738A")
	draw_line(plot.position, Vector2(plot.position.x, plot.end.y), axis_colour, 1.0, true)
	draw_line(Vector2(plot.position.x, plot.end.y), plot.end, axis_colour, 1.0, true)
	var points := PackedVector2Array()
	for i in range(_samples.size()):
		points.append(_point(i, plot, low, high))
	if points.size() > 1:
		for i in range(1, points.size()):
			var a: Vector2 = points[i - 1]
			var b: Vector2 = points[i]
			draw_polygon(PackedVector2Array([a, b, Vector2(b.x, plot.end.y), Vector2(a.x, plot.end.y)]),
				PackedColorArray([Color(cream, 0.18), Color(cream, 0.18), Color(cream, 0.0), Color(cream, 0.0)]))
		draw_polyline(points, cream, 2.0, true)
	else:
		draw_circle(points[0], 12.0, cream, true, -1, true)
	# Draw each historical cost at its own turn. Gaps remain gaps.
	for i in range(_samples.size()):
		var cost: float = _cost_for_sample(_samples[i])
		if cost < 0.0:
			continue
		var point := Vector2(points[i].x, plot.end.y - (cost - low) / (high - low) * plot.size.y)
		if i > 0 and _cost_for_sample(_samples[i - 1]) >= 0.0:
			var previous := Vector2(points[i - 1].x, plot.end.y - (_cost_for_sample(_samples[i - 1]) - low) / (high - low) * plot.size.y)
			draw_line(previous, point, Color.WHITE, 3.0, true)
		else:
			draw_circle(point, 3.0, Color.WHITE, true, -1, true)
	if _hover_index >= 0 and points.size() > 1:
		var point: Vector2 = points[_hover_index]
		draw_line(Vector2(point.x, plot.position.y), Vector2(point.x, plot.end.y), Color(axis_colour, 0.5))
		draw_circle(point, 4, cream)
	# Keep persistent labels at the current endpoint. Hover adds a compact readout.
	if int(_samples[-1].turn) == int(TurnManager.current_turn):
		var end: Vector2 = points[-1]
		draw_string(font, Vector2(end.x + 16, end.y + 5), "£%.2f" % float(_samples[-1].price), HORIZONTAL_ALIGNMENT_LEFT, 78, 14, ink)
		draw_string(font, Vector2(end.x, size.y - 7), "Turn %d" % int(_samples[-1].turn), HORIZONTAL_ALIGNMENT_LEFT, 90, 12, ink)

	if _hover_index >= 0:
		var lines: PackedStringArray = _hover_lines(_hover_index)
		var box_width := 190.0
		var x: float = points[_hover_index].x + 12.0
		if x + box_width > plot.end.x:
			x = points[_hover_index].x - box_width - 12.0
		x = clampf(x, 4.0, maxf(4.0, size.x - box_width - 4.0))
		var box := Rect2(x, 27.0, box_width, 10.0 + lines.size() * 20.0)
		draw_rect(box, Color("#081b2c"))
		for i in range(lines.size()):
			draw_string(font, box.position + Vector2(10, 20 + i * 20), lines[i], HORIZONTAL_ALIGNMENT_LEFT, box_width - 20, 14, ink)

func _hover_lines(index: int) -> PackedStringArray:
	var sample: Dictionary = _samples[index]
	var lines := PackedStringArray(["Turn %d" % int(sample.turn), "Price £%.2f" % float(sample.price)])
	if CostSolver.get_good_unit_cost(good_id) >= 0.0:
		var cost: float = _cost_for_sample(sample)
		lines.append("Your cost basis £%.2f" % cost if cost >= 0.0 else "Your cost basis —")
	return lines
