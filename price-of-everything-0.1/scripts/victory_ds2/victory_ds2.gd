extends Control
## The Victory panel in DS2, built into the Victory panel (scripts/victory_panel.gd) while UiPrefs.use_victory_ds2
## is on. A control desk on Building Detail's navy steel backing in its brass trim, over a dimmed map:
##   the raised title and the Close key;
##   the score, on a plate of black moulded plastic: the total on a drum counter and a lamp, amber while the
##     race is on and green once won, beside a dot-matrix screen saying what it takes to win (or when it was);
##   a bank of five dials, one per track, each on a dark metal plate (dark_metal_plate.png, blackened
##     gunmetal edge to edge): its raised name, a panel gauge whose needle stands at the track's best progress
##     and whose lamp is green when the track is full, its points on a dot-matrix display, a lamp for its trend,
##     and what it measures or how to score more. How the track scores in full is the dial's hover readout.
## Read-only: everything comes from VictoryState.get_breakdown(), given to populate().

signal close_requested

const Parts := preload("res://scripts/ds2/parts.gd")
const SheetParts := preload("res://scripts/ds2/sheet_parts.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const Drum := preload("res://scripts/ds2/drum_figure.gd")
const Tip := preload("res://scripts/ds2/tip.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Gauge := preload("res://scripts/panel_gauge.gd")

## Building Detail's backing: its 9-slice corner in texels and the content's margin inside the brass trim.
const BACKING_CORNER := 64.0
const CONTENT_MARGIN := 26
const DIM := Color(0.0, 0.0, 0.0, 0.45)
const TRACK_W := 214.0
const TRACK_GAP := 12
const DRUMS := 4
const DRUM_H := 40.0
## The score plate's screen's dot pitch.
const RULE_PITCH := 2.0
const GAUGE_PX := 190.0
## The dials mark their scale green from here up.
const GREEN_FROM := 40.0
## The points display's height: its screen and bezel round one line of dots.
const POINTS_H := 30.0
## A trend's lamp and word: up, down, flat.
const TRENDS := {1: ["ok", "Rising"], -1: ["bad", "Falling"], 0: ["off", "Steady"]}
## The dark metal plate (layout.json dark_metal_plate): its 9-slice corner in texels, the shadow room beyond the
## slab in px, and the padding inside it.
const PLATE_CORNER := (10.0 + 44.0) * 2.0 / 1.875
const PLATE_OUTSET := 10.0 / 1.875
const PLATE_PAD := 16

var _cabinet: PanelContainer
var _drum_slot: HBoxContainer
var _status_lamp: HBoxContainer
var _rule_slot: HBoxContainer
var _tracks: HBoxContainer


func _init() -> void:
	name = "VictoryDs2"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_build()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), DIM)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _build() -> void:
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_cabinet = PanelContainer.new()
	_cabinet.name = "VictoryCabinet"
	var bare := StyleBoxEmpty.new()
	_cabinet.add_theme_stylebox_override("panel", bare)
	var backing: Control = Nine.make("panel_backing", BACKING_CORNER)
	backing.name = "VictoryBacking"
	_cabinet.add_child(backing)
	centre.add_child(_cabinet)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, CONTENT_MARGIN)
	_cabinet.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)
	col.add_child(_title_row())
	col.add_child(_score_plate())
	_tracks = HBoxContainer.new()
	_tracks.name = "Tracks"
	_tracks.add_theme_constant_override("separation", TRACK_GAP)
	col.add_child(_tracks)


func _title_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "VictoryTitleRow"
	row.add_theme_constant_override("separation", 12)
	var title: Control = Title.new()
	title.call("set_text", "Victory")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(title)
	var close: TextureButton = Key.make("close", Title.line_height())
	close.name = "CloseKey"
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(func() -> void: close_requested.emit())
	row.add_child(close)
	return row


## The score on a plastic plate: the drum counter, its lamp and the screen beside them.
func _score_plate() -> Control:
	var plate: Control = Section.new()
	plate.name = "ScorePlate"
	plate.set("style", "plastic")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	(plate.get("content") as VBoxContainer).add_child(row)
	_drum_slot = HBoxContainer.new()
	row.add_child(_drum_slot)
	_status_lamp = HBoxContainer.new()
	row.add_child(_status_lamp)
	_rule_slot = HBoxContainer.new()
	_rule_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_rule_slot)
	return plate


## Shows `b` (VictoryState.get_breakdown()).
func populate(b: Dictionary) -> void:
	if b.is_empty():
		return
	var total := int(b.get("total", 0))
	var threshold := int(b.get("win_threshold", 2500))
	var won := bool(b.get("won", false))
	for c in _drum_slot.get_children():
		c.queue_free()
	_drum_slot.add_child(Drum.new(DRUM_H, DRUMS, mini(total, 9999)))
	for c in _status_lamp.get_children():
		c.queue_free()
	_status_lamp.add_child(SheetParts.lamp("ok" if won else ("warn" if total > 0 else "off"), 0.8))
	for c in _rule_slot.get_children():
		c.queue_free()
	var rule := "Won on turn %d with %d points. Keep playing to push your score." % [int(b.get("won_turn", 0)), total] if won \
		else _rule_text(b)
	var screen := _screen([rule], RULE_PITCH, 0.0)
	screen.name = "RuleScreen"
	screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule_slot.add_child(screen)
	for c in _tracks.get_children():
		c.queue_free()
	for t: Variant in b.get("tracks", []) as Array:
		_tracks.add_child(_track(t as Dictionary))


## What it takes to win: the demo's flat bar, or the campaign's bar that rises with the turn.
func _rule_text(b: Dictionary) -> String:
	var max_turns := int(b.get("max_turns", 300))
	var threshold := int(b.get("win_threshold", 2500))
	if VictoryState.win_threshold_for_turn(1) == VictoryState.win_threshold_for_turn(max_turns):
		return "Score %d to win. Each track is up to 1000 points." % threshold
	return "The bar rises with the turn: one full track wins at turn %d, two at %d, three at %d, four at %d." % [
		VictoryState.WIN_START_TURN, VictoryState.WIN_START_TURN + VictoryState.WIN_STEP_TURNS,
		VictoryState.WIN_START_TURN + 2 * VictoryState.WIN_STEP_TURNS, max_turns]


## One track's dial on its dark metal plate.
func _track(t: Dictionary) -> Control:
	var plate := Tip.TipPanel.new()
	plate.name = "Track_%s" % str(t.get("key", ""))
	plate.custom_minimum_size.x = TRACK_W
	plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var best := clampf(float(t.get("progress", 0.0)), 0.0, 1.0)
	Tip.attach(plate, {"stage": "Victory", "name": str(t.get("name", "")), "detail": str(t.get("explain", "")),
		"tone": "ok" if best >= 1.0 else ("warn" if best > 0.0 else "off")})
	var metal: Control = Nine.make("dark_metal_plate", PLATE_CORNER, PLATE_OUTSET)
	metal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(metal)
	var pad := MarginContainer.new()
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, PLATE_PAD)
	plate.add_child(pad)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 8)
	pad.add_child(content)
	var head := Parts.heading(str(t.get("name", "")).to_upper())
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(head)
	var dial_centre := CenterContainer.new()
	dial_centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(dial_centre)
	var gauge: Control = Gauge.new()
	gauge.name = "Dial"
	gauge.set("gauge_size", GAUGE_PX)
	gauge.set("green_percent", 100.0)
	gauge.set("amber_percent", 0.0)
	gauge.set("green_from_percent", GREEN_FROM)
	gauge.set("led_mode", Gauge.LedMode.GREEN if best >= 1.0 else (Gauge.LedMode.AMBER if best > 0.0 else Gauge.LedMode.OFF))
	gauge.set("value", best)
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dial_centre.add_child(gauge)
	var points: Control = DotMatrix.new()
	points.name = "Points"
	points.set("text", "%d / %d" % [int(t.get("contribution", 0)), int(t.get("max_score", 1000))])
	points.custom_minimum_size = Vector2(TRACK_W - 40.0, POINTS_H)
	points.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	points.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(points)
	var trend := _trend(t.get("trend", []))
	var trend_row := HBoxContainer.new()
	trend_row.alignment = BoxContainer.ALIGNMENT_CENTER
	trend_row.add_theme_constant_override("separation", 6)
	trend_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	trend_row.add_child(SheetParts.lamp(str(TRENDS[trend][0])))
	trend_row.add_child(Parts.caption(str(TRENDS[trend][1])))
	content.add_child(trend_row)
	var metric := SheetParts.body(str(t.get("metric_text", "")))
	metric.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	metric.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	metric.custom_minimum_size.x = TRACK_W - 2.0 * PLATE_PAD
	content.add_child(metric)
	return plate


## A dot-matrix screen in its bezel, `lines` stacked on it (at least `min_lines`), centred.
static func _screen(lines: Array, pitch: float, width: float, min_lines: int = 1) -> PanelContainer:
	var screen := PanelContainer.new()
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := StyleBoxEmpty.new()
	inset.set_content_margin_all(DotMatrix.RIM / DotMatrix.CAPTURE_SCALE + 4.0)
	screen.add_theme_stylebox_override("panel", inset)
	var corner := (DotMatrix.MARGIN + DotMatrix.RIM + DotMatrix.RADIUS + 2.0) * 2.0 / DotMatrix.CAPTURE_SCALE
	screen.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, screen.size)
		Nine.paint(screen, DotMatrix.SCREEN, r.grow(DotMatrix.MARGIN / DotMatrix.CAPTURE_SCALE), corner)
		screen.draw_rect(r.grow(-DotMatrix.RIM / DotMatrix.CAPTURE_SCALE), DotMatrix.PANE))
	screen.resized.connect(screen.queue_redraw)
	if width > 0.0:
		screen.custom_minimum_size.x = width
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", int(pitch * 2.0))
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(stack)
	var all: Array = lines.duplicate()
	while all.size() < min_lines:
		all.append("")
	for line: Variant in all:
		var dots: Control = DotMatrix.new()
		dots.set("framed", false)
		dots.set("pitch", pitch)
		dots.set("text", str(line))
		dots.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(dots)
	return screen


## +1, -1 or 0: which way the track has gone over its recent turns.
static func _trend(trend_v: Variant) -> int:
	var trend: Array = trend_v if trend_v is Array else []
	if trend.size() < 2:
		return 0
	var delta := float(trend[trend.size() - 1]) - float(trend[0])
	return 1 if delta > 0.001 else (-1 if delta < -0.001 else 0)
