extends Control
## Bankruptcy game-over screen (SolvencyState mounts it). Fullscreen and opaque — it
## takes over completely, so no game action is reachable underneath. Shows the
## cautionary-tale copy, a switchable chart of the run's finances (money / profit /
## empire value / output value), and one big CTA: Return to Main Menu.

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
## The demo names this ending too — one table of endings in EndGameData, so the
## bankruptcy screen and the turn-100 screen cannot drift apart.
const EndGameData := preload("res://scripts/end_game_data.gd")

## The campaign copy, kept as the fallback for any match that is not running the demo set.
const CAMPAIGN_TITLE := "Your legacy ends here"
const CAMPAIGN_BODY := "Some journeys are meant to be cautionary tales. You tried your best but your strategy didn't pan out. But few succeed on their first business — maybe you'll succeed on the ashes of this attempt…"

const _SERIES := [
	{"key": "money", "label": "Money", "signed": true},
	{"key": "profit", "label": "Profit / turn", "signed": true},
	{"key": "empire_value", "label": "Empire value", "signed": false},
	{"key": "output_value", "label": "Output value", "signed": false},
]

var _history: Array = []
var _chart: Control = null
var _active_key := "money"
var _filter_buttons: Array = []

func _ready() -> void:
	theme = DS.theme
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_fit()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit):
		vp.size_changed.connect(_fit)
	mouse_filter = Control.MOUSE_FILTER_STOP

func open(history: Array) -> void:
	_history = history
	_build()
	visible = true
	move_to_front()

func _fit() -> void:
	var vp := get_viewport()
	if vp != null:
		size = vp.get_visible_rect().size
		position = Vector2.ZERO

func _build() -> void:
	for c in get_children():
		c.queue_free()

	var bg := ColorRect.new()
	bg.color = DS.PALETTE.get("BG_DEEP", Color("#0A1420"))
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(940, 0)
	col.add_theme_constant_override("separation", DS.SP["LG"])
	center.add_child(col)

	var title := Label.new()
	title.theme_type_variation = "Title"
	title.add_theme_font_size_override("font_size", 42)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = _ending_title()
	col.add_child(title)

	var body := Label.new()
	body.theme_type_variation = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.text = _ending_body()
	col.add_child(body)

	# Chart card: filter row + the plot.
	var card := PanelContainer.new()
	card.theme_type_variation = "Card"
	var card_vb := VBoxContainer.new()
	card_vb.add_theme_constant_override("separation", DS.SP["SM"])
	card.add_child(card_vb)

	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", DS.SP["SM"])
	filters.alignment = BoxContainer.ALIGNMENT_CENTER
	_filter_buttons.clear()
	for s in _SERIES:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = str(s.label)
		b.button_pressed = str(s.key) == _active_key
		b.pressed.connect(_on_filter.bind(str(s.key)))
		_filter_buttons.append({"key": str(s.key), "button": b})
		filters.add_child(b)
	card_vb.add_child(filters)

	_chart = _LineChart.new()
	_chart.custom_minimum_size = Vector2(0, 300)
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card_vb.add_child(_chart)
	col.add_child(card)
	_apply_series()

	var cta := Button.new()
	cta.theme_type_variation = "Primary"
	cta.focus_mode = Control.FOCUS_NONE
	cta.text = "Return to Main Menu"
	cta.custom_minimum_size = Vector2(0, 60)
	cta.add_theme_font_size_override("font_size", 22)
	cta.pressed.connect(_on_return)
	col.add_child(cta)

func _ending_title() -> String:
	if EndGameData.demo_endings_apply():
		return str((EndGameData.DEMO_ENDINGS["bankruptcy"] as Dictionary).title)
	return CAMPAIGN_TITLE

func _ending_body() -> String:
	if EndGameData.demo_endings_apply():
		return str((EndGameData.DEMO_ENDINGS["bankruptcy"] as Dictionary).copy)
	return CAMPAIGN_BODY

func _on_filter(key: String) -> void:
	_active_key = key
	for entry in _filter_buttons:
		entry.button.button_pressed = str(entry.key) == key
	_apply_series()

func _apply_series() -> void:
	if _chart == null:
		return
	var meta: Dictionary = {}
	for s in _SERIES:
		if str(s.key) == _active_key:
			meta = s
	var values: Array = []
	var turns: Array = []
	for p in _history:
		values.append(float(p.get(_active_key, 0.0)))
		turns.append(int(p.get("turn", 0)))
	var col: Color = DS.PALETTE.get("ACCENT", Color("#C9A24B"))
	_chart.set_series(turns, values, str(meta.get("label", "")), bool(meta.get("signed", false)), col)

func _on_return() -> void:
	# SolvencyState owns this panel's CanvasLayer (an autoload child that survives the
	# scene change), so it must free it as it swaps scenes — otherwise the game-over
	# screen lingers over the loaded main menu.
	SolvencyState.return_to_main_menu(MAIN_MENU_SCENE)


# A minimal line chart: axis frame, an optional zero baseline, the series polyline,
# and min/max/turn labels. Self-contained so the game-over screen has no dependencies.
class _LineChart extends Control:
	var _turns: Array = []
	var _values: Array = []
	var _label := ""
	var _signed := false
	var _color := Color.WHITE

	func set_series(turns: Array, values: Array, label: String, signed: bool, color: Color) -> void:
		_turns = turns
		_values = values
		_label = label
		_signed = signed
		_color = color
		queue_redraw()

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pad_l := 84.0
		var pad_r := 16.0
		var pad_t := 28.0
		var pad_b := 26.0
		var plot := Rect2(pad_l, pad_t, maxf(1.0, w - pad_l - pad_r), maxf(1.0, h - pad_t - pad_b))
		var frame: Color = DS.PALETTE.get("BORDER_SOFT", Color("#3A4A5C"))
		var muted: Color = DS.PALETTE.get("TEXT_MUTED", Color("#C2D2E5"))
		draw_rect(plot, Color(0, 0, 0, 0.20), true)
		draw_rect(plot, frame, false, 1.0)
		var font := get_theme_default_font()
		var fs := 12

		if _values.size() < 2:
			draw_string(font, Vector2(pad_l + 8, pad_t + 20), "Not enough data yet",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
			return

		var lo: float = float(_values[0])
		var hi: float = float(_values[0])
		for v in _values:
			lo = minf(lo, float(v))
			hi = maxf(hi, float(v))
		if _signed:
			lo = minf(lo, 0.0)
			hi = maxf(hi, 0.0)
		if is_equal_approx(lo, hi):
			hi = lo + 1.0
		var span := hi - lo

		# Zero baseline for signed series.
		if _signed and lo < 0.0 and hi > 0.0:
			var zy := plot.position.y + plot.size.y * (1.0 - (0.0 - lo) / span)
			draw_line(Vector2(plot.position.x, zy), Vector2(plot.end.x, zy), Color(muted, 0.5), 1.0)

		# The series polyline.
		var pts := PackedVector2Array()
		var n := _values.size()
		for i in n:
			var x := plot.position.x + plot.size.x * (float(i) / float(n - 1))
			var y := plot.position.y + plot.size.y * (1.0 - (float(_values[i]) - lo) / span)
			pts.append(Vector2(x, y))
		draw_polyline(pts, _color, 2.0, true)

		# Axis labels: max/min on the left, turn range on the bottom, series name top-left.
		draw_string(font, Vector2(6, plot.position.y + 6), _fmt(hi), HORIZONTAL_ALIGNMENT_LEFT, pad_l - 8, fs, muted)
		draw_string(font, Vector2(6, plot.end.y), _fmt(lo), HORIZONTAL_ALIGNMENT_LEFT, pad_l - 8, fs, muted)
		draw_string(font, Vector2(pad_l + 4, h - 8), "turn %d" % int(_turns[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, muted)
		draw_string(font, Vector2(plot.end.x - 60, h - 8), "turn %d" % int(_turns[n - 1]), HORIZONTAL_ALIGNMENT_LEFT, 60, fs, muted)
		draw_string(font, Vector2(pad_l + 4, pad_t - 10), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, _color)

	func _fmt(v: float) -> String:
		var a := absf(v)
		var s := ""
		if a >= 1000.0:
			s = "£%.1fk" % (v / 1000.0)
		else:
			s = "£%d" % int(round(v))
		return s
