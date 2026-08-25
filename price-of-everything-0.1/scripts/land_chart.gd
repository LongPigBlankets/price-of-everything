extends Control
## Vertical land-ownership chart for the TVP side rail.
##
## COMPACT mode (collapsed rail, 60px): one coloured chunk per building stacked
## from the bottom; NPC buildings white-outlined; ruins brown; under-construction
## navy-hatched; dashed soft-cap line at 100 with red hatching above.
##
## DETAILED mode (expanded rail, 180px): scale labels every 50, dark rows with a
## category-coloured left strip, building icon (if the chunk is >40px tall) and
## name (if >10px tall) and the land value; a dashed "OWNED" line with buyable
## hatching above it.

signal segment_clicked(instance_id: String)

const UIFonts := preload("res://scripts/ui_fonts.gd")
const SOFT_CAP := 100.0
const NAVY := Color("#13294B")
const RED := Color("#E0524A")
const OFF_WHITE := Color("#F2EEE3")
const TOP_RESERVED := 14.0
const BOTTOM_RESERVED := 5.0
const DARK_ROW := Color(0, 0.08, 0.16)
const SCALE_W := 22.0  # left label gutter — wide enough for 3 digits ("250")
const BRACKET_MIN_OWNED := 10       # below one patch there is nothing to bracket
const BRACKET_TICK := 5.0
const BRACKET_W := 2.0
## Strip reserved to the RIGHT of the bar for the owned bracket and its label. The bracket
## always hung at the chart's right edge, but the bar ran to that edge too, so the line and
## the rotated "Owned" sat on top of the topmost building's fill and its land figure. The bar
## now stops short of it and the chart widens to match, so nothing is given up for the gutter.
const BRACKET_GUTTER := 16.0

var _segments: Array = []
var _axis_max: float = 1.0
var _max_label: int = 0
var _detailed := false
var _owned := 0
var _buyable := 0
var _npc := 0                        # NPC footprint at the bottom of the pile
var _hit_rects: Array = []   # [{rect, tooltip}] for hover tooltips

func _get_tooltip(at_position: Vector2) -> String:
	for hr in _hit_rects:
		if (hr.rect as Rect2).has_point(at_position):
			return str(hr.tooltip)
	return ""

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for hr in _hit_rects:
			if (hr.rect as Rect2).has_point(event.position):
				var iid := str(hr.get("instance_id", ""))
				if iid != "":
					segment_clicked.emit(iid)
				return

func _init() -> void:
	custom_minimum_size = Vector2(60, 0)
	size_flags_vertical = Control.SIZE_EXPAND_FILL

func configure(segments: Array, axis_max: float, max_label: int, detailed: bool = false, owned: int = 0, buyable: int = 0, npc: int = 0) -> void:
	_segments = segments
	_axis_max = maxf(1.0, axis_max)
	_max_label = max_label
	_detailed = detailed
	_owned = owned
	_buyable = buyable
	_npc = npc
	custom_minimum_size.x = int(190 + BRACKET_GUTTER) if detailed else 60  # bar 190 + the bracket gutter
	queue_redraw()

func _draw() -> void:
	_hit_rects.clear()
	if _detailed:
		_draw_detailed()
	else:
		_draw_compact()

# ── Compact (collapsed) ──────────────────────────────────────────────────────
func _draw_compact() -> void:
	var w := size.x
	var h := size.y
	var chart_top := TOP_RESERVED
	var chart_h := h - TOP_RESERVED - BOTTOM_RESERVED
	if chart_h <= 0.0:
		return
	var bottom := h - BOTTOM_RESERVED
	var unit := chart_h / _axis_max

	if SOFT_CAP < _axis_max:
		_hatch(Rect2(0, chart_top, w, (bottom - SOFT_CAP * unit) - chart_top), RED, 6.0)

	var cur := bottom
	for seg in _segments:
		var sh: float = float(seg.size) * unit
		if sh <= 0.0:
			continue
		var rect := Rect2(0, cur - sh, w, sh)
		if bool(seg.get("is_ruins", false)):
			draw_rect(rect, seg.color, true)
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
		elif bool(seg.get("is_other", false)):
			draw_rect(rect, seg.color, true)
			var t: float = minf(10.0, minf(rect.size.x, rect.size.y))
			if t > 0.0:
				draw_rect(rect.grow(-t * 0.5), Color.WHITE, false, t)
		else:
			draw_rect(rect, seg.color, true)
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
		if bool(seg.get("is_construction", false)):
			_hatch(rect, NAVY, 6.0)
		_hit_rects.append({"rect": rect, "tooltip": seg.get("tooltip", ""), "instance_id": seg.get("instance_id", "")})
		cur -= sh

	draw_rect(Rect2(0, chart_top, w, chart_h), DS.PALETTE.BORDER_SOFT, false, 1.0)
	if SOFT_CAP < _axis_max:
		_dashed_h(0.0, w, bottom - SOFT_CAP * unit, DS.PALETTE.ACCENT)
	draw_string(UIFonts.mono(), Vector2(0.0, 11.0), str(_max_label), HORIZONTAL_ALIGNMENT_CENTER, w, 10, DS.PALETTE.TEXT_MUTED)
	_draw_owned_bracket(w, bottom, unit)

# ── Detailed (expanded) ──────────────────────────────────────────────────────
func _draw_detailed() -> void:
	var w := size.x
	var h := size.y
	var bx := SCALE_W
	var bw := w - SCALE_W - BRACKET_GUTTER
	var ctop := 6.0
	var cbot := h - BOTTOM_RESERVED
	var ch := cbot - ctop
	if ch <= 0.0 or bw <= 0.0:
		return
	var unit := ch / _axis_max
	var font := get_theme_default_font()
	var num := UIFonts.mono()

	# Scale ticks + labels every 50 (pushed left into the slim padding).
	var val := 0
	while val <= int(_axis_max):
		var y := cbot - float(val) * unit
		draw_line(Vector2(bx, y), Vector2(bx + bw, y), Color(1, 1, 1, 0.06), 1.0)
		draw_string(num, Vector2(0, y + 4.0), str(val), HORIZONTAL_ALIGNMENT_RIGHT, SCALE_W - 2.0, 9, DS.PALETTE.TEXT_DIM)
		val += 50

	# Red hatching above the soft cap — same colour/pattern as the slim chart.
	if SOFT_CAP < _axis_max:
		_hatch(Rect2(bx, ctop, bw, (cbot - SOFT_CAP * unit) - ctop), RED, 6.0)

	# Building rows, stacked from the bottom — same fill rules as the slim chart.
	var cur := cbot
	for seg in _segments:
		var sh: float = float(seg.size) * unit
		if sh <= 0.0:
			continue
		var rect := Rect2(bx, cur - sh, bw, sh)
		if bool(seg.get("is_ruins", false)):
			draw_rect(rect, seg.color, true)
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
		elif bool(seg.get("is_other", false)):
			draw_rect(rect, seg.color, true)
			var t: float = minf(10.0, minf(rect.size.x, rect.size.y))
			if t > 0.0:
				draw_rect(rect.grow(-t * 0.5), Color.WHITE, false, t)
		else:
			draw_rect(rect, seg.color, true)
			draw_rect(rect, Color(0, 0, 0, 0.25), false, 1.0)
		if bool(seg.get("is_construction", false)):
			_hatch(rect, NAVY, 6.0)

		# Name (> 10px tall) + value — overlaid on the fill. No icon in the expanded
		# chart, which frees ~3 more characters before the name is ellipsised.
		var text_x := rect.position.x + 8.0
		if sh > 10.0 and font != null:
			var ny := rect.position.y + sh * 0.5 + 4.0
			var name_w := (rect.end.x - 38.0) - text_x - 4.0
			var name_txt := _fit_ellipsis(font, str(seg.get("name", "")), name_w, 14)
			_shadowed(font, Vector2(text_x, ny), name_txt, HORIZONTAL_ALIGNMENT_LEFT, name_w, 14, Color.WHITE)
			_shadowed(num, Vector2(rect.end.x - 38.0, ny), str(int(seg.get("value", 0))), HORIZONTAL_ALIGNMENT_RIGHT, 34.0, 13, Color.WHITE)
		_hit_rects.append({"rect": rect, "tooltip": seg.get("tooltip", ""), "instance_id": seg.get("instance_id", "")})
		cur -= sh

	draw_rect(Rect2(bx, ctop, bw, ch), DS.PALETTE.BORDER_SOFT, false, 1.0)
	# The right-edge square bracket replaces the old dashed OWNED line: it spans
	# exactly the player-owned land (NPC pile below it, unowned land above it).
	_draw_owned_bracket(w, cbot, unit)

# Truncate text to fit max_width, appending an ellipsis when it doesn't.
func _fit_ellipsis(font: Font, text: String, max_width: float, fsize: int) -> String:
	if max_width <= 0.0:
		return ""
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_width:
		return text
	var ell := "…"
	var t := text
	while t.length() > 1:
		t = t.substr(0, t.length() - 1)
		if font.get_string_size(t + ell, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x <= max_width:
			return t + ell
	return ell

func _shadowed(font: Font, pos: Vector2, text: String, align: int, width: float, fsize: int, color: Color) -> void:
	draw_string(font, pos + Vector2(1, 1), text, align, width, fsize, Color(0, 0, 0, 0.8))
	draw_string(font, pos, text, align, width, fsize, color)

# Right-edge square bracket over the player-owned land: it starts above the NPC
# pile (their land isn't yours) and ends at owned units — unowned land above it
# stays outside. Hidden below one patch (10) of owned land.
func _draw_owned_bracket(right_x: float, bottom_y: float, unit: float) -> void:
	if _owned < BRACKET_MIN_OWNED:
		return
	var x := right_x - BRACKET_W * 0.5
	var y_bottom := bottom_y - float(_npc) * unit
	var y_top := bottom_y - float(_npc + _owned) * unit
	draw_line(Vector2(x, y_top), Vector2(x, y_bottom), OFF_WHITE, BRACKET_W)
	draw_line(Vector2(x - BRACKET_TICK, y_top), Vector2(x, y_top), OFF_WHITE, BRACKET_W)
	draw_line(Vector2(x - BRACKET_TICK, y_bottom), Vector2(x, y_bottom), OFF_WHITE, BRACKET_W)
	# "Owned" runs along the bracket (rotated), only when the span can fit it.
	var span := y_bottom - y_top
	if span >= 34.0:
		var num := UIFonts.mono()
		var mid := (y_top + y_bottom) * 0.5
		draw_set_transform(Vector2(x - 4.0, mid + 17.0), -PI * 0.5, Vector2.ONE)
		draw_string(num, Vector2.ZERO, "Owned", HORIZONTAL_ALIGNMENT_CENTER, 34.0, 9, OFF_WHITE)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# ── Shared drawing helpers ───────────────────────────────────────────────────
func _dashed_h(x0: float, x1: float, y: float, color: Color) -> void:
	var dash := 5.0
	var gap := 4.0
	var cx := x0
	while cx < x1:
		draw_line(Vector2(cx, y), Vector2(minf(cx + dash, x1), y), color, 1.5)
		cx += dash + gap

func _hatch(rect: Rect2, color: Color, step: float) -> void:
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	draw_rect(rect, Color(color, 0.10), true)
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		var seg := _clip_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), rect)
		if seg.size() == 2:
			draw_line(seg[0], seg[1], Color(color, 0.5), 1.5)
		x += step

func _clip_line(p1: Vector2, p2: Vector2, rect: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var dx := p2.x - p1.x
	var dy := p2.y - p1.y
	var checks := [[-dx, p1.x - rect.position.x], [dx, rect.end.x - p1.x], [-dy, p1.y - rect.position.y], [dy, rect.end.y - p1.y]]
	for c in checks:
		var p: float = c[0]
		var q: float = c[1]
		if absf(p) < 0.00001:
			if q < 0.0:
				return []
		else:
			var r := q / p
			if p < 0.0:
				if r > t1: return []
				if r > t0: t0 = r
			else:
				if r < t0: return []
				if r < t1: t1 = r
	return [Vector2(p1.x + t0 * dx, p1.y + t0 * dy), Vector2(p1.x + t1 * dx, p1.y + t1 * dy)]
