extends Control

# Fullscreen Victory breakdown panel (docs/victory-system-spec.md §9). Node-based
# (DS PanelContainer cards + Labels + meter bars) — it borrows the research panel's
# navy/cream look via DS variations rather than immediate-mode drawing. Read-only:
# it observes VictoryState (score_changed / victory_achieved) and renders
# get_breakdown(); it never mutates sim state (rule #5).
#
# Show/hide goes through PanelStack (Esc closes it) exactly like research_panel:
# the close button removes itself + hides; bottom_menu opens it via _set_panel_visible;
# a latched win auto-opens it (the victory moment).

const MARGIN := 22
const CARD_COLS := 3

var _total_label: Label
var _base_label: Label
var _hint_label: Label
var _banner: Label
var _grid: GridContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	VictoryState.score_changed.connect(_on_score_changed)
	visibility_changed.connect(_on_visibility_changed)
	# The victory-moment auto-open (spec §6) is driven by bottom_menu, which can hide
	# the other HUD panels first; the won banner appears here via _populate() on show.
	if visible:
		_populate()

# ── Build the static skeleton once ──────────────────────────────────────────

func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, MARGIN)
	bg.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", DS.SP["MD"])
	margin.add_child(root)

	# Header: title (left) · total (right) · close.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", DS.SP["MD"])
	root.add_child(header)

	var title := Label.new()
	title.text = "VICTORY PROGRESS"
	title.theme_type_variation = &"Title"
	header.add_child(title)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_total_label = Label.new()
	_total_label.theme_type_variation = &"Title"
	_total_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_total_label)

	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(34, 34)
	close.tooltip_text = "Close (Esc)"
	close.pressed.connect(_close)
	header.add_child(close)

	# Sub-header captions: the decaying-base explainer + the win-curve hint.
	_base_label = Label.new()
	_base_label.theme_type_variation = &"Caption"
	root.add_child(_base_label)

	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"Caption"
	root.add_child(_hint_label)

	# Victory banner (hidden until won this session).
	_banner = Label.new()
	_banner.theme_type_variation = &"Section"
	_banner.add_theme_color_override("font_color", DS.PALETTE["OK"])
	_banner.visible = false
	root.add_child(_banner)

	# Five track cards in a scrollable 3-column grid (3 on top, 2 below).
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_grid = GridContainer.new()
	_grid.columns = CARD_COLS
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", DS.SP["MD"])
	_grid.add_theme_constant_override("v_separation", DS.SP["MD"])
	scroll.add_child(_grid)

# ── Populate from the current breakdown ─────────────────────────────────────

func _populate() -> void:
	var b := VictoryState.get_breakdown()
	if b.is_empty():
		return
	var total := int(b.get("total", 0))
	var threshold := int(b.get("win_threshold", 4000))
	var turn := int(b.get("turn", 0))
	var max_turns := int(b.get("max_turns", 300))
	var won := bool(b.get("won", false))

	_total_label.text = "%s / %s" % [_commas(total), _commas(threshold)]
	var ratio := clampf(float(total) / float(maxi(1, threshold)), 0.0, 1.0)
	var total_col: Color = DS.PALETTE["OK"] if won else (DS.PALETTE["TEXT"] as Color).lerp(DS.PALETTE["OK"], ratio)
	_total_label.add_theme_color_override("font_color", total_col)

	_base_label.text = "Score %s  (turn %d of %d)   ·   need %s to win now" % [
		_commas(total), turn, max_turns, _commas(threshold)]
	_hint_label.text = "You start at 0 and the bar rises: win with 1 track at turn %d, 2 at %d, 3 at %d, 4 at %d." % [
		VictoryState.WIN_START_TURN, VictoryState.WIN_START_TURN + VictoryState.WIN_STEP_TURNS, VictoryState.WIN_START_TURN + 2 * VictoryState.WIN_STEP_TURNS, max_turns]

	if won:
		_banner.text = "✓ VICTORY — scored %s on turn %d. Keep playing to push your score." % [
			_commas(total), int(b.get("won_turn", 0))]
		_banner.visible = true
	else:
		_banner.visible = false

	for c in _grid.get_children():
		c.queue_free()
	for track in (b.get("tracks", []) as Array):
		_grid.add_child(_make_card(track as Dictionary))

# ── Card + meter builders ───────────────────────────────────────────────────

func _make_card(t: Dictionary) -> PanelContainer:
	var col: Color = DS.PALETTE.get(String(t.get("color_key", "ACCENT")), DS.PALETTE["ACCENT"])
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(260, 0)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", DS.SP["SM"])
	card.add_child(box)

	# Title row: swatch · name · contribution / max.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", DS.SP["SM"])
	box.add_child(head)
	var swatch := ColorRect.new()
	swatch.color = col
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(swatch)
	var name_label := Label.new()
	name_label.text = String(t.get("name", ""))
	name_label.theme_type_variation = &"Section"
	head.add_child(name_label)
	var head_spacer := Control.new()
	head_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(head_spacer)
	var score := Label.new()
	score.text = "%d / %d" % [int(t.get("contribution", 0)), int(t.get("max_score", 1000))]
	score.theme_type_variation = &"Numeric"
	head.add_child(score)
	_trend_badge(head, t.get("trend", []))

	# Threshold meter (best progress solid; locked-in-but-now-lower region ghosted).
	box.add_child(_make_meter(float(t.get("progress", 0.0)), float(t.get("live", 0.0)), col))

	# Concrete metric line.
	var metric := Label.new()
	metric.text = String(t.get("metric_text", ""))
	metric.theme_type_variation = &"Body"
	box.add_child(metric)

	# Autarkic-only: per-category market-buy transparency tally.
	if String(t.get("key", "")) == "autarkic":
		_autarkic_tally(box, t)

	# How-to-raise-it explanation.
	var explain := Label.new()
	explain.text = String(t.get("explain", ""))
	explain.theme_type_variation = &"Caption"
	explain.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain.custom_minimum_size = Vector2(0, 0)
	box.add_child(explain)

	return card

func _make_meter(best: float, live: float, col: Color) -> PanelContainer:
	var track := PanelContainer.new()
	track.custom_minimum_size = Vector2(0, 14)
	track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(1, 1, 1, 0.10)
	ts.set_corner_radius_all(4)
	track.add_theme_stylebox_override("panel", ts)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	track.add_child(row)
	var b := clampf(best, 0.0, 1.0)
	var lv := clampf(live, 0.0, 1.0)
	var solid := minf(lv, b)
	_meter_seg(row, solid, col)
	_meter_seg(row, maxf(0.0, b - solid), Color(col, 0.4))  # ghosted: locked-in but currently lower
	var empty := maxf(0.0, 1.0 - b)
	if empty > 0.0005:
		var sp := Control.new()
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sp.size_flags_stretch_ratio = empty
		row.add_child(sp)
	return track

func _meter_seg(row: HBoxContainer, ratio: float, color: Color) -> void:
	if ratio <= 0.0005:
		return
	var seg := PanelContainer.new()
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seg.size_flags_stretch_ratio = ratio
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(3)
	seg.add_theme_stylebox_override("panel", sb)
	row.add_child(seg)

func _trend_badge(row: HBoxContainer, trend_v: Variant) -> void:
	var trend: Array = trend_v if trend_v is Array else []
	if trend.size() < 2:
		return
	var delta := float(trend[trend.size() - 1]) - float(trend[0])
	var badge := Label.new()
	badge.theme_type_variation = &"Caption"
	if delta > 0.001:
		badge.text = "▲"
		badge.add_theme_color_override("font_color", DS.PALETTE["OK"])
	elif delta < -0.001:
		badge.text = "▼"
		badge.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
	else:
		badge.text = "–"
	badge.tooltip_text = "Trend over the last %d turns" % trend.size()
	row.add_child(badge)

func _autarkic_tally(box: VBoxContainer, t: Dictionary) -> void:
	var this_turn: Dictionary = t.get("purchases_this_turn", {})
	var lifetime: Dictionary = t.get("purchases_lifetime", {})
	var bought := 0
	for c in VictoryState.PURCHASE_CATEGORIES:
		bought += int(this_turn.get(c, 0))
	var line := Label.new()
	line.theme_type_variation = &"Caption"
	if bought == 0:
		line.text = "This turn: nothing bought — streak +1"
		line.add_theme_color_override("font_color", DS.PALETTE["OK"])
	else:
		line.text = "This turn broke the streak: %s" % _tally_str(this_turn)
		line.add_theme_color_override("font_color", DS.PALETTE["WARN"])
	box.add_child(line)
	var life := Label.new()
	life.theme_type_variation = &"Caption"
	life.text = "Lifetime market buys: %s" % _tally_str(lifetime)
	box.add_child(life)

func _tally_str(d: Dictionary) -> String:
	var parts: Array = []
	for c in VictoryState.PURCHASE_CATEGORIES:
		parts.append("%d %s" % [int(d.get(c, 0)), c])
	return " · ".join(parts)

# ── Show / hide / victory moment ────────────────────────────────────────────

func _on_score_changed(_total: int, _breakdown: Dictionary) -> void:
	if visible:
		_populate()

func _on_visibility_changed() -> void:
	if visible:
		_populate()

func _close() -> void:
	PanelStack.remove(self)
	hide()

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
