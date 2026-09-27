extends "res://scripts/bdp_v3_section.gd"
## DS2 market, a good's slip (decision 10): it opens inline under the good's row on the board, a dark metal
## slab with its silver screws. On it:
##   the chart recorder: graph paper behind glass, the sale price over the recorded turns as a navy trace,
##     and under it a readout that names the hovered turn: its price and the units you sold and bought that
##     turn (MarketRules.history); with nothing hovered, the latest turn;
##   the price impact: the ladder as ten LED cells with the rung your recent volume sits on lit, and a line on
##     what is happening (the board's impact card says the same, in full);
##   the good's keys: Buy, Sell, Move, Build more.

signal sell_requested(good_id: String)

const MarketRules := preload("res://scripts/market_rules.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const MParts := preload("res://scripts/market_ds2/parts.gd")
const HISTORY_TURNS := 20
const CHART_SIZE := Vector2(400, 150)
const KEY_SCALE := 0.8

var good_id := ""
var chart: Chart
var readout: Control
var _samples: Array = []


func _init(gid: String) -> void:
	super()
	good_id = gid
	name = "MarketSlip"
	style = "slab"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_samples = MarketRules.history(good_id, HISTORY_TURNS)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 18)
	content.add_child(line)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	line.add_child(left)
	left.add_child(Parts.caption("%s, sell price" % Catalog.get_display_name(good_id)))
	chart = Chart.new()
	chart.samples = _samples
	chart.custom_minimum_size = CHART_SIZE
	chart.hovered.connect(_show_sample)
	left.add_child(chart)
	readout = DotMatrix.new()
	readout.name = "ChartReadout"
	readout.set("pitch", 2.0)
	readout.set("align", HORIZONTAL_ALIGNMENT_LEFT)
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(readout)
	_show_sample(-1)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 8)
	line.add_child(right)
	var ladder := MarketRules.impact_ladder(good_id)
	right.add_child(Parts.caption("Price impact %s" % MParts.impact_text(float(ladder.impact))))
	var meter := LadderMeter.new()
	meter.rungs = (ladder.rungs as Array).size()
	meter.lit = int(ladder.rung)
	meter.name = "LadderMeter"
	right.add_child(meter)
	var words := Parts.body(MParts.ladder_words(ladder))
	words.name = "LadderWords"
	right.add_child(words)
	var keys := GridContainer.new()
	keys.columns = 2
	keys.add_theme_constant_override("h_separation", 8)
	keys.add_theme_constant_override("v_separation", 8)
	right.add_child(keys)
	var buy := Parts.key_button("Buy", "SlipBuy", KEY_SCALE)
	buy.disabled = not Catalog.is_good_buyable(good_id)
	buy.pressed.connect(func() -> void: MatchState.purchase_for_good_requested.emit(good_id))
	keys.add_child(buy)
	var sell := Parts.key_button("Sell", "SlipSell", KEY_SCALE)
	sell.disabled = not Catalog.is_good_sellable(good_id)
	sell.pressed.connect(func() -> void: sell_requested.emit(good_id))
	keys.add_child(sell)
	var move := Parts.key_button("Move", "SlipMove", KEY_SCALE)
	move.pressed.connect(func() -> void: MatchState.transfer_for_good_requested.emit(good_id))
	keys.add_child(move)
	var build := Parts.key_button("Build more", "SlipBuild", KEY_SCALE)
	build.pressed.connect(func() -> void: MatchState.show_construct_for_good.emit(good_id))
	keys.add_child(build)


## The readout's words for sample `i` (the latest when -1): "TURN 7  £0.57  SOLD 30  BOUGHT 5".
func sample_text(i: int) -> String:
	if _samples.is_empty():
		return "NO PRICES RECORDED YET"
	var s: Dictionary = _samples[i if i >= 0 else _samples.size() - 1]
	return "TURN %d  %s  SOLD %d  BOUGHT %d" % [int(s.turn), load("res://scripts/ds2/money_figure.gd").display_text(float(s.sale)),
		int(s.sold), int(s.bought)]


func _show_sample(i: int) -> void:
	readout.set("text", sample_text(i))


## Hovers sample `i` (from the end when negative), as the pointer would: the capture tool and tests.
func hover_sample(i: int) -> void:
	var at := i if i >= 0 else _samples.size() + i
	chart.hover = clampi(at, -1, _samples.size() - 1)
	chart.queue_redraw()
	_show_sample(chart.hover)


func shown_text() -> String:
	return str(readout.get("text"))


## The chart recorder: cream graph paper behind glass in the mini screen's bezel, the sale price as a navy
## trace, the hovered turn marked. `hovered(i)` as the pointer moves over a turn (-1 when it leaves).
class Chart extends Control:
	signal hovered(index: int)
	const Nine := preload("res://scripts/bdp_v3_nine.gd")
	const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
	const PAPER := Color("#efe6cf")
	const GRID := Color(0.043, 0.137, 0.251, 0.12)
	const INK := Color("#0b2340")
	const PAD := Vector2(14, 12)
	var samples: Array = []
	var hover := -1

	func _init() -> void:
		name = "ChartRecorder"
		mouse_filter = Control.MOUSE_FILTER_STOP
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mouse_exited.connect(func() -> void:
			hover = -1
			queue_redraw()
			hovered.emit(-1))

	func _gui_input(event: InputEvent) -> void:
		var mm := event as InputEventMouseMotion
		if mm == null:
			return
		var i := sample_at_x(mm.position.x)
		if i != hover:
			hover = i
			queue_redraw()
			hovered.emit(i)

	func _plot() -> Rect2:
		return Rect2(PAD, size - PAD * 2.0)

	func sample_at_x(x: float) -> int:
		if samples.is_empty():
			return -1
		var p := _plot()
		var f := clampf((x - p.position.x) / maxf(1.0, p.size.x), 0.0, 1.0)
		return clampi(roundi(f * float(samples.size() - 1)), 0, samples.size() - 1)

	func _range() -> Vector2:
		var lo := INF
		var hi := -INF
		for s: Dictionary in samples:
			lo = minf(lo, float(s.sale))
			hi = maxf(hi, float(s.sale))
		if hi - lo < 0.0001:
			var mid := lo
			lo = mid * 0.9
			hi = mid * 1.1 + 0.01
		var pad := (hi - lo) * 0.15
		return Vector2(lo - pad, hi + pad)

	func point(i: int) -> Vector2:
		var p := _plot()
		var r := _range()
		var x := p.position.x + (float(i) / float(maxi(1, samples.size() - 1))) * p.size.x
		var y := p.end.y - (float(samples[i].sale) - r.x) / (r.y - r.x) * p.size.y
		return Vector2(x, y)

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE
		Nine.paint(self, DotMatrix.SCREEN, box.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), corner)
		var paper := box.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE)
		draw_rect(paper, PAPER)
		var step := 10.0
		var x := paper.position.x
		while x < paper.end.x:
			draw_line(Vector2(x, paper.position.y), Vector2(x, paper.end.y), GRID, 1.0)
			x += step
		var y := paper.position.y
		while y < paper.end.y:
			draw_line(Vector2(paper.position.x, y), Vector2(paper.end.x, y), GRID, 1.0)
			y += step
		if not samples.is_empty():
			if samples.size() == 1:
				draw_circle(point(0), 3.0, INK)
			else:
				var pts := PackedVector2Array()
				for i in samples.size():
					pts.append(point(i))
				draw_polyline(pts, INK, 2.0, true)
				for p in pts:
					draw_circle(p, 2.2, INK)
			if hover >= 0 and hover < samples.size():
				var hp := point(hover)
				draw_line(Vector2(hp.x, paper.position.y + 2), Vector2(hp.x, paper.end.y - 2), Color(INK, 0.5), 1.0)
				draw_circle(hp, 4.5, Color("#c0392b"))
		Nine.paint(self, DotMatrix.GLASS, box.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), corner)


## The impact ladder as a row of LED cells on a mini screen, one a rung, the rungs up to the one your recent
## volume sits on lit amber.
class LadderMeter extends Control:
	const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
	const Nine := preload("res://scripts/bdp_v3_nine.gd")
	const Light := preload("res://scripts/bdp_v3_light.gd")
	const AMBER := Color("#ffa412")
	var rungs := 10
	var lit := -1
	var _cells: Control
	var _glass: Control

	func _init() -> void:
		custom_minimum_size = Vector2(0, 26)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		# The cells give off their own light: a lamp overlay does not dim them.
		_cells = Control.new()
		_cells.name = "Cells"
		_cells.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_cells.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cells.material = Light.emissive_material()
		_cells.draw.connect(_draw_cells)
		add_child(_cells)
		_glass = Control.new()
		_glass.name = "Glass"
		_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_glass.draw.connect(func() -> void:
			Nine.paint(_glass, DotMatrix.GLASS, Rect2(Vector2.ZERO, size).grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), _corner()))
		add_child(_glass)

	func _corner() -> float:
		return (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size)
		Nine.paint(self, DotMatrix.SCREEN, box.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), _corner())
		draw_rect(box.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE), DotMatrix.PANE)

	func _draw_cells() -> void:
		var pane := Rect2(Vector2.ZERO, size).grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE)
		var n := maxi(1, rungs)
		var gap := 3.0
		var inner := pane.grow(-3.0)
		var w := (inner.size.x - gap * (n - 1)) / n
		for i in n:
			var r := Rect2(inner.position.x + i * (w + gap), inner.position.y, w, inner.size.y)
			if i <= lit:
				_cells.draw_rect(r.grow(1.0), Color(AMBER, 0.3))
				_cells.draw_rect(r, AMBER)
			else:
				_cells.draw_rect(r, Color(AMBER, 0.1))
