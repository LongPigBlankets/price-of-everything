extends Control

# Compact, clickable top-bar widget: five thin vertical track fill bars (best
# progress per track), a faint base-score underline (the decaying time pressure),
# and a "score / 4000" readout. Click opens the fullscreen Victory panel. Pure
# view code — reads VictoryState.get_breakdown() and refreshes on score_changed
# (UI is read-only, rule #5). Mirrors the notification_bell self-contained
# _draw + _gui_input idiom; all colours come from DS.PALETTE.

const HEIGHT := 36.0
const BAR_W := 7.0
const BAR_GAP := 4.0
const BAR_TOP := 7.0
const UNDERLINE_GAP := 4.0
const TEXT_GAP := 9.0

signal clicked

var _breakdown: Dictionary = {}

func _ready() -> void:
	custom_minimum_size = Vector2(150, HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_breakdown = VictoryState.get_breakdown()
	VictoryState.score_changed.connect(_on_score_changed)
	_refresh()

func _on_score_changed(_total: int, breakdown: Dictionary) -> void:
	_breakdown = breakdown
	_refresh()

func _refresh() -> void:
	var total := int(_breakdown.get("total", 0))
	var threshold := int(_breakdown.get("win_threshold", 4000))
	var won := bool(_breakdown.get("won", false))
	var win_state := "✓ Won on turn %d" % int(_breakdown.get("won_turn", 0)) if won else "Win at %s" % _commas(threshold)
	tooltip_text = "Victory %s / %s\n%s — click for details" % [
		_commas(total), _commas(threshold), win_state]
	# Size to fit the bar cluster + the score readout.
	var tracks: Array = _breakdown.get("tracks", [])
	var cluster_w := _cluster_width(tracks.size())
	var font := _numeric_font()
	var fs := _numeric_size()
	var text := "%d / %d" % [total, threshold]
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font != null else 90.0
	custom_minimum_size.x = ceil(cluster_w + TEXT_GAP + tw + 4.0)
	queue_redraw()

func _draw() -> void:
	var tracks: Array = _breakdown.get("tracks", [])
	if tracks.is_empty():
		return
	var cluster_w := _cluster_width(tracks.size())
	var bar_h := size.y - BAR_TOP - (UNDERLINE_GAP + TEXT_GAP)
	if bar_h < 4.0:
		bar_h = 4.0
	# Five vertical track bars: inset track + bottom-anchored tinted fill.
	var x := 0.0
	for t in tracks:
		draw_rect(Rect2(x, BAR_TOP, BAR_W, bar_h), Color(1, 1, 1, 0.10), true)
		var p := clampf(float((t as Dictionary).get("progress", 0.0)), 0.0, 1.0)
		var fh := bar_h * p
		if fh > 0.0:
			var col: Color = DS.PALETTE.get(String((t as Dictionary).get("color_key", "ACCENT")), DS.PALETTE["ACCENT"])
			draw_rect(Rect2(x, BAR_TOP + bar_h - fh, BAR_W, fh), col, true)
		x += BAR_W + BAR_GAP
	# Score readout, tinted toward OK (green) as it approaches / passes the win.
	var font := _numeric_font()
	if font == null:
		return
	var fs := _numeric_size()
	var total := int(_breakdown.get("total", 0))
	var threshold := int(_breakdown.get("win_threshold", 4000))
	var ratio := clampf(float(total) / float(maxi(1, threshold)), 0.0, 1.0)
	var col: Color = DS.PALETTE["OK"] if bool(_breakdown.get("won", false)) else (DS.PALETTE["TEXT"] as Color).lerp(DS.PALETTE["OK"], ratio)
	var text := "%d / %d" % [total, threshold]
	var baseline := size.y * 0.5 + float(fs) * 0.34
	draw_string(font, Vector2(cluster_w + TEXT_GAP, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()
		accept_event()

func _cluster_width(n: int) -> float:
	if n <= 0:
		return 0.0
	return float(n) * BAR_W + float(n - 1) * BAR_GAP

func _numeric_font() -> Font:
	var f := get_theme_font("font", "Numeric")
	return f if f != null else get_theme_default_font()

func _numeric_size() -> int:
	var s := get_theme_font_size("font_size", "Numeric")
	return s if s > 0 else 16

func _commas(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" + out) if n < 0 else out
