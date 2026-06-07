extends Control
## Tile-space visualisation for the Buildings & Land tab. Draws a horizontal bar
## (0 .. max land) with segments:
##   • Built            — solid green
##   • Under construction — hatched light/dark green
##   • Owned, empty     — faded green
##   • Buyable          — amber
## Plus a vertical mark at the density soft cap (100) and, 10px under the bar, a
## dashed line with overlaid text explaining the over-density build-cost penalty.

const TOP := 14.0          # room above the bar for the "100" label
const BAR_H := 28.0
const GAP_BELOW := 10.0    # dashed line sits this far under the bar
const TEXT_H := 16.0
const SOFT_CAP := 100.0
const PENALTY_TEXT := "+50% building cost due to local opposition to density"

var _built := 0.0
var _construction := 0.0
var _owned_empty := 0.0
var _buyable := 0.0
var _max := 1.0

func _init() -> void:
	custom_minimum_size = Vector2(0, TOP + BAR_H + GAP_BELOW + TEXT_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

func configure(built: float, construction: float, owned_empty: float, buyable: float, max_land: float) -> void:
	_built = maxf(0.0, built)
	_construction = maxf(0.0, construction)
	_owned_empty = maxf(0.0, owned_empty)
	_buyable = maxf(0.0, buyable)
	_max = maxf(1.0, max_land)
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var unit := w / _max
	var bar_top := TOP
	var bar_bottom := TOP + BAR_H

	# --- Segments ---
	var x := 0.0
	x = _solid_segment(x, _built * unit, bar_top, DS.PALETTE.OK)
	var cons_w := _construction * unit
	if cons_w > 0.0:
		_hatched_segment(Rect2(x, bar_top, cons_w, BAR_H))
		x += cons_w
	x = _solid_segment(x, _owned_empty * unit, bar_top, Color(DS.PALETTE.OK, 0.34))
	x = _solid_segment(x, _buyable * unit, bar_top, DS.PALETTE.WARN)

	# Bar outline
	draw_rect(Rect2(0, bar_top, w, BAR_H), DS.PALETTE.BORDER_SOFT, false, 1.0)

	var font := get_theme_default_font()

	# --- Max label above the right (max) mark ---
	if font != null:
		var mlabel := str(int(round(_max)))
		var mw := font.get_string_size(mlabel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
		draw_string(font, Vector2(w - mw, bar_top - 3.0), mlabel, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, DS.PALETTE.TEXT_MUTED)

	# --- Density soft-cap (100) mark + the penalty bracket under the 100→max span ---
	if SOFT_CAP < _max:
		var x100 := SOFT_CAP * unit
		var xmax := w
		var dash_y := bar_bottom + GAP_BELOW
		# 100 mark on the bar
		draw_line(Vector2(x100, bar_top), Vector2(x100, bar_bottom), DS.PALETTE.ACCENT, 2.0)
		if font != null:
			var lw := font.get_string_size("100", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
			draw_string(font, Vector2(clampf(x100 - lw * 0.5, 0.0, w - lw), bar_top - 3.0), "100", HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, DS.PALETTE.ACCENT)
		# Connector lines down from the 100 mark and the max mark to the dashed line
		draw_line(Vector2(x100, bar_bottom), Vector2(x100, dash_y), DS.PALETTE.WARN, 1.0)
		draw_line(Vector2(xmax, bar_bottom), Vector2(xmax, dash_y), DS.PALETTE.WARN, 1.0)
		# Dashed line spanning only the 100→max region
		_dashed_line(x100, xmax, dash_y, DS.PALETTE.WARN)
		# Penalty text centered over the span; drawn over an opaque background so it
		# supersedes (hides) the dashed line behind it.
		if font != null:
			var tw := font.get_string_size(PENALTY_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10).x
			var cx := (x100 + xmax) * 0.5
			var tx := cx - tw * 0.5
			draw_rect(Rect2(tx - 3.0, dash_y - 9.0, tw + 6.0, 14.0), DS.PALETTE.BG_PANEL, true)
			draw_string(font, Vector2(tx, dash_y + 4.0), PENALTY_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 10, DS.PALETTE.WARN)

func _solid_segment(x: float, width_px: float, top: float, color: Color) -> float:
	if width_px > 0.0:
		draw_rect(Rect2(x, top, width_px, BAR_H), color, true)
	return x + width_px

# Light-green fill with dark-green diagonal hatching, clipped to the rect.
func _hatched_segment(rect: Rect2) -> void:
	draw_rect(rect, Color(0.55, 0.85, 0.62, 0.5), true)  # light green base
	var step := 7.0
	var x := rect.position.x - rect.size.y
	while x < rect.end.x:
		var seg := _clip_line(Vector2(x, rect.position.y), Vector2(x + rect.size.y, rect.end.y), rect)
		if seg.size() == 2:
			draw_line(seg[0], seg[1], DS.PALETTE.OK, 2.0)  # dark-green stripes
		x += step

func _dashed_line(x0: float, x1: float, y: float, color: Color) -> void:
	var dash := 6.0
	var gap := 4.0
	var cx := x0
	while cx < x1:
		draw_line(Vector2(cx, y), Vector2(minf(cx + dash, x1), y), color, 1.0)
		cx += dash + gap

# Liang–Barsky line clip to a rect. Returns [a, b] or [].
func _clip_line(p1: Vector2, p2: Vector2, rect: Rect2) -> Array:
	var t0 := 0.0
	var t1 := 1.0
	var dx := p2.x - p1.x
	var dy := p2.y - p1.y
	var checks := [
		[-dx, p1.x - rect.position.x],
		[dx, rect.end.x - p1.x],
		[-dy, p1.y - rect.position.y],
		[dy, rect.end.y - p1.y],
	]
	for c in checks:
		var p: float = c[0]
		var q: float = c[1]
		if absf(p) < 0.00001:
			if q < 0.0:
				return []
		else:
			var r := q / p
			if p < 0.0:
				if r > t1:
					return []
				if r > t0:
					t0 = r
			else:
				if r < t0:
					return []
				if r < t1:
					t1 = r
	return [Vector2(p1.x + t0 * dx, p1.y + t0 * dy), Vector2(p1.x + t1 * dx, p1.y + t1 * dy)]
