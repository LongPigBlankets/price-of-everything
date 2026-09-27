extends RefCounted
## The market's DS2 parts (docs/market-ds2-plan.md §5): the MARKET nameplate, the exchange bell, the arrow lamp
## (render set `marketparts`, seed 450, in tools/button_mockup/cluster.html) and the money screens under the
## digital display rule (the point in a cell of its own, five cells at most: scripts/ds2/money_figure.gd
## `display`). Everything else comes from the kit: tvp_v3/buildings_parts.gd (modules, wells, captions, body
## text), ledger_v3 (the backing, the seam, the search screen, sort marks), scripts/ds2 (dot matrix, latching
## keys, the guarded key, the dot card).

const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const DotCard := preload("res://scripts/ds2/dot_card.gd")
const MarketRules := preload("res://scripts/market_rules.gd")

const CAPTURE_SCALE := 1.875
## From layout.json: the nameplate's render (288 × 114, its plate inset by the shadow room), the bell's (128
## square) and the arrow lamp's (the pilot lamp's 112 frame, a 44 bezel).
const NAMEPLATE_SIZE := Vector2(288.0, 114.0)
const NAMEPLATE_MARGIN := 16.0
const BELL_SIZE := 128.0
const BELL_MARGIN := 16.0
const LAMP_FRAME := 112.0
const LAMP_BEZEL := 44.0
## The widest a money screen gets under the display rule.
const MONEY_CELLS := 5
## The LED colours for a tone: green, amber, red; white for none.
const TONES := {"ok": "OK", "warn": "WARN", "bad": "DANGER"}


static func tone_colour(tone: String) -> Color:
	return DS.PALETTE[TONES[tone]] if TONES.has(tone) else DS.PALETTE["TEXT"]


## A money figure on a screen (`whole`: whole pounds below £10,000, as a lot's price is charged): the printed £, then the LED (its point in a cell of its own) padded with blank
## cells to `cells` so a column's screens are one width, then K, M or B printed after it (a blank of the same
## width when `suffix_room` and there is none, so the £ signs line up down a column).
static func money(value: float, colour: Color, cells: int = MONEY_CELLS, suffix_room := false, whole := false) -> HBoxContainer:
	var shown := MoneyFigure.display(value)
	if whole and absf(value) < 10000.0:
		shown = {"figure": "%d" % roundi(value), "suffix": ""}
	var hb := HBoxContainer.new()
	hb.name = "Money"
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 4)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(Parts.caption("£", Parts.POUND_PX, HORIZONTAL_ALIGNMENT_RIGHT))
	var led: Control = Led.new()
	led.name = "Led"
	led.set("point_cell", true)
	var figure := str(shown.figure)
	led.call("set_figure", " ".repeat(maxi(0, cells - figure.length())) + figure, colour)
	hb.add_child(led)
	var suffix := str(shown.suffix)
	if suffix != "" or suffix_room:
		var s := Parts.caption(suffix if suffix != "" else "K", Parts.POUND_PX)
		s.name = "Suffix"
		if suffix == "":
			s.modulate.a = 0.0
		hb.add_child(s)
	hb.set_meta("figure", figure + suffix)
	return hb


## How wide `money` is for `cells` cells.
static func money_width(cells: int = MONEY_CELLS, suffix_room := false) -> float:
	var led: Control = Led.new()
	led.set("point_cell", true)
	led.call("set_figure", "8".repeat(maxi(1, cells)), Color.WHITE)
	var w: float = led.custom_minimum_size.x
	led.free()
	var pound: float = Plate.FONT_SEMI.get_string_size("£", HORIZONTAL_ALIGNMENT_LEFT, -1, Parts.POUND_PX).x
	var k: float = Plate.FONT_SEMI.get_string_size("K", HORIZONTAL_ALIGNMENT_LEFT, -1, Parts.POUND_PX).x + 4.0 if suffix_room else 0.0
	return ceilf(pound + 4.0 + w + k)


static func impact_text(impact: float) -> String:
	if absf(impact) < 0.005:
		return "0%"
	if absf(impact) < 1.0:
		return "%s%.2f%%" % ["+" if impact > 0.0 else "", impact]
	return "%s%.1f%%" % ["+" if impact > 0.0 else "", impact]


## The impact ladder as a dot card: a line a rung (the net units a turn that start it, and the %/turn it moves
## the price), the rung the recent average sits on marked, and a line on what is happening.
static func ladder_card(gid: String) -> Dictionary:
	var ladder := MarketRules.impact_ladder(gid)
	var rows: Array = []
	for rung: Dictionary in ladder.rungs:
		rows.append({"caption": "OVER %s A TURN" % _thousands(int(rung.threshold)), "value": "%s%%" % String.num(float(rung.rate), 2),
			"tone": "warn" if bool(rung.active) else ""})
	var notes: Array = [{"text": ladder_words(ladder), "tone": ""}]
	if (ladder.rungs as Array).is_empty():
		notes = [{"text": "No recipe makes it, so nothing moves its price.", "tone": ""}]
	return {"title": "PRICE IMPACT %s" % impact_text(float(ladder.impact)), "tone": "warn" if int(ladder.rung) >= 0 else "",
		"rows": rows, "notes": notes}


## One line on what the good's price is doing and why.
static func ladder_words(ladder: Dictionary) -> String:
	match str(ladder.regime):
		"pressure":
			return "Your %s %s it %s%% a turn." % ["selling" if float(ladder.avg) > 0.0 else "buying",
				"lowers" if float(ladder.avg) > 0.0 else "raises", String.num(float(ladder.rate), 2)]
		"recovering":
			return "Walking back to its base over %d turns." % int(ladder.recovery_turns)
	return "You are not moving this price."


static func _thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


## The black enamel MARKET nameplate in its brass rim, the size of its plate; the render's shadow reaches past.
static func nameplate() -> Control:
	return Fitted.new("market_nameplate", NAMEPLATE_SIZE, NAMEPLATE_MARGIN)


## A render drawn at its own scale (2 texels a logical pixel), the control the size of its part and the
## shadow room overflowing it.
class Fitted extends Control:
	var layer := ""
	var frame := Vector2.ZERO
	var room := 0.0

	func _init(layer_name: String, render_size: Vector2, margin: float) -> void:
		layer = layer_name
		frame = render_size
		room = margin
		name = layer_name.capitalize().replace(" ", "")
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = (render_size - Vector2.ONE * 2.0 * margin) / CAPTURE_SCALE

	func _draw() -> void:
		var r := Vector2.ONE * room / CAPTURE_SCALE
		draw_texture_rect(Plate.tex(layer), Rect2(-r, frame / CAPTURE_SCALE), false)


## The exchange bell: a brass dome on a black base beside the nameplate. It rings (a short shake) as a turn's
## prices are set, and its hover says so.
class Bell extends Control:
	var tip: Dictionary = {}
	var _ring := 0.0

	func _init() -> void:
		name = "MarketBell"
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_PASS
		custom_minimum_size = Vector2.ONE * (BELL_SIZE - 2.0 * BELL_MARGIN) / CAPTURE_SCALE
		set_process(false)

	func set_turn(turn: int) -> void:
		tip = {"title": "PRICES SET FOR TURN %d" % turn}
		tooltip_text = "Prices set for turn %d." % turn

	func ring() -> void:
		_ring = 0.7
		set_process(true)

	func is_ringing() -> bool:
		return _ring > 0.0

	func _process(delta: float) -> void:
		_ring = maxf(0.0, _ring - delta)
		if _ring <= 0.0:
			set_process(false)
		queue_redraw()

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/ds2/dot_card.gd").make(tip, self) if not tip.is_empty() else null

	func _draw() -> void:
		var r := Vector2.ONE * BELL_MARGIN / CAPTURE_SCALE
		var shake := Vector2(sin(_ring * 60.0) * _ring * 2.2, 0.0)
		draw_texture_rect(Plate.tex("market_bell"), Rect2(-r + shake, Vector2.ONE * BELL_SIZE / CAPTURE_SCALE), false)


## The arrow lamp: the pilot lamp's bezel with a triangular lens, green pointing up while the price rises,
## red pointing down while it falls, dark and round while it holds (lamp_off). Its glow is the pilot lamp's.
class ArrowLamp extends Control:
	var dir := 0
	var lamp_scale := 0.72:
		set(v):
			lamp_scale = v
			var side := roundf(LAMP_BEZEL / CAPTURE_SCALE * v)
			custom_minimum_size = Vector2(side, side)
			queue_redraw()
	var _glow: Control

	func _init() -> void:
		name = "ArrowLamp"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lamp_scale = 0.72
		_glow = Control.new()
		_glow.name = "Glow"
		_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_glow.material = Light.glow_material()
		_glow.draw.connect(func() -> void:
			if dir != 0:
				_glow.draw_texture_rect(Plate.tex("lamp_glow_green" if dir > 0 else "lamp_glow_red"), _frame_rect(), false))
		add_child(_glow)

	func set_dir(d: int) -> void:
		dir = signi(d)
		queue_redraw()
		_glow.queue_redraw()

	func _frame_rect() -> Rect2:
		var side := LAMP_FRAME / CAPTURE_SCALE * lamp_scale
		return Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side))

	func _draw() -> void:
		var layer := "lamp_off"
		if dir > 0:
			layer = "lamp_arrow_up"
		elif dir < 0:
			layer = "lamp_arrow_down"
		draw_texture_rect(Plate.tex(layer), _frame_rect(), false)
