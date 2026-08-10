extends CanvasLayer
## The end-of-game Victory / Defeat screen — a full-screen overlay (layer 150)
## porting the owner's "Victory Screen.html" design into Godot. It renders the ONE
## dict assembled by scripts/end_game_data.gd (EndGameData.gather()); see that file
## and show_end() below for the contract. UI is read-only against the sim (rule #5):
## nothing here mutates state; only the footer button emits back_to_menu_pressed.
##
## Structure: dim scrim → vertically-scrolling ScrollContainer (inset 20px from every
## screen edge, almost full screen) → a width-filling silver
## metal bezel → navy panel with five stacked sections (header+score bar, banner of
## five pennants, copy+statline, charts+empire, footer). Rounded fills use StyleBoxFlat
## (repo convention); graphics (score bar, charts, crests, empire map) are custom _draw
## Controls, using 4-vertex gradient quads / solid fills / hex polygons only — never the
## many-point gradient polygons that fan-artifact under the GL Compatibility renderer.

signal back_to_menu_pressed

# ── Design geometry ────────────────────────────────────────────────────────────
const MARGIN := 20        # inset from every screen edge (almost full screen)
const PANEL_W := 1560     # min plate width; the plate expands to fill the wider screen
const BEZEL_PAD := 8
const SEC_PAD_H := 44

# ── Design palette (the owner's exact hex values) ──────────────────────────────
const C_BEZEL_LT := Color("#aeb6bf")
const C_BEZEL_MD := Color("#727c87")
const C_BEZEL_DK := Color("#454e58")
const C_RIVET_LT := Color("#eef2f6")
const C_RIVET_DK := Color("#5a636e")
const C_NAVY_TOP := Color("#0c1d31")
const C_NAVY_BOT := Color("#0a1521")
const C_ACCENT_WIN := Color("#e6b34a")
const C_ACCENT_LOSE := Color("#e2604a")
## "Continuity" — survived to the bell with no track but still in profit. Amber: neither the
## gold of a win nor the red of receivership (owner 2026-08-01).
const C_ACCENT_CONT := Color("#e0932c")
## The big word is amber TOO, not a pale sand (owner 2026-08-01) — victory pairs a near-white
## word with a gold accent, but continuity reads as one amber verdict rather than two tones.
const C_DISPLAY_CONT := Color("#e0932c")
const C_TOTAL_CONT := Color("#e0932c")
const C_HEADER_BORDER := Color("#16273a")
const C_KICKER := Color("#71859b")
const C_DISPLAY_WIN := Color("#f3f8fd")
const C_DISPLAY_LOSE := Color("#e8b0a4")
const C_EPITHET := Color("#8298ac")
const C_TOTAL_WIN := Color("#5fbf6b")
const C_TOTAL_LOSE := Color("#e2604a")
const C_TRACK_BG := Color("#0a1623")
const C_MARKER := Color("#f2e6c8")
const C_CREST_GOLD_A := Color("#f0dfae")
const C_CREST_GOLD_B := Color("#d9b96a")
const C_CREST_GOLD_C := Color("#a8863c")
const C_CREST_UNLIT := Color("#0a1623")
const C_CREST_UNLIT_STROKE := Color("#22384f")
const C_GLYPH_LIT := Color("#141d29")
const C_GLYPH_UNLIT := Color("#31465c")
const C_NAME_LIT := Color("#f3f8fd")
const C_NAME_UNLIT := Color("#5b6e84")
const C_COPY := Color("#a9bccf")
const C_CARD_BORDER := Color("#1c3149")
const C_STAT_VALUE := Color("#eef4fb")
const C_CHART_LABEL := Color("#71859b")
const C_REV := Color("#5fbf6b")
const C_OUT := Color("#e6b34a")
const C_BLD := Color("#5fa8e0")
const C_BIG := Color("#eef4fb")
const C_FOOT_CAP := Color("#4a5d72")
const C_SECTION_HEAD := Color("#c7d4e3")

# ── Fonts ──────────────────────────────────────────────────────────────────────
const _UIFonts := preload("res://scripts/ui_fonts.gd")
const _UIHelpers := preload("res://scripts/ui_helpers.gd")
const _BEBAS := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const _BARLOW := preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
# The REAL empire node-graph (the Tab empire view's data + layout + drawing layer).
const _EmpireGraph := preload("res://scripts/empire_graph.gd")
const _EmpireLayout := preload("res://scripts/empire_layout.gd")
const _GraphWorld := preload("res://scripts/empire_graph_world.gd")

var _accent: Color = C_ACCENT_WIN
var _tracked: FontVariation
var _empire_data: Dictionary = {}
var _expand_overlay: Control


func _ready() -> void:
	layer = 150


# ── Public API ───────────────────────────────────────────────────────────────
## Build + display the screen from an EndGameData.gather() dict. Idempotent.
func show_end(data: Dictionary) -> void:
	# Free previous children immediately (not queue_free) so a rebuild's "Scroll"
	# node name doesn't collide with a not-yet-freed old one.
	for c in get_children():
		remove_child(c)
		c.free()
	_expand_overlay = null

	var result := str(data.get("result", "victory"))
	_accent = C_ACCENT_WIN if result == "victory" else (
		C_ACCENT_CONT if result == "continuity" else C_ACCENT_LOSE)
	_empire_data = data.get("empire", {})

	# Dim scrim (STOP so nothing behind reacts; clicks are swallowed, not destructive).
	var scrim := ColorRect.new()
	scrim.color = Color(0.01, 0.03, 0.06, 0.82)
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(scrim)

	# Vertically-scrolling viewport, inset MARGIN px from every screen edge (almost
	# full screen). The panel fills the width; the tall content scrolls within.
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, MARGIN)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.name = "Scroll"
	add_child(scroll)

	# The plate fills the scroll's width (ScrollContainer fits its single child to its
	# own width when horizontal scrolling is off).
	scroll.add_child(_build_bezel(data))


func _grow() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


# ── Bezel + navy panel shell ─────────────────────────────────────────────────
func _build_bezel(data: Dictionary) -> Control:
	# Silver metal plate: a PanelContainer with a solid mid-silver rounded fill, a
	# diagonal sheen overlay, and four corner rivets. 8px pad → navy panel inside.
	var bezel := PanelContainer.new()
	bezel.custom_minimum_size = Vector2(PANEL_W, 0)
	bezel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bezel.add_theme_stylebox_override("panel", _sb(C_BEZEL_MD, C_BEZEL_DK, 1, 18, BEZEL_PAD))

	# Diagonal sheen + rivets, drawn over the plate (mouse-ignore).
	var sheen := _Bezel.new()
	sheen.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bezel.add_child(sheen)

	# Navy panel.
	var navy := PanelContainer.new()
	navy.add_theme_stylebox_override("panel", _sb(C_NAVY_TOP, C_NAVY_TOP, 0, 12, 0))
	bezel.add_child(navy)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	navy.add_child(col)

	# 3px top accent line (transparent → ACCENT → transparent).
	var accent_line := _HRule.new()
	accent_line.mode = _HRule.SYMMETRIC
	accent_line.col = _accent
	accent_line.custom_minimum_size = Vector2(0, 3)
	col.add_child(accent_line)

	col.add_child(_build_header(data))
	col.add_child(_hborder())
	col.add_child(_build_banner(data))
	col.add_child(_hborder())
	col.add_child(_build_copy(data))
	col.add_child(_hborder())
	col.add_child(_build_charts(data))
	col.add_child(_hborder())
	col.add_child(_build_footer())
	return bezel


func _hborder() -> Control:
	var r := ColorRect.new()
	r.color = C_HEADER_BORDER
	r.custom_minimum_size = Vector2(0, 1)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


# ── Section 1: HEADER + SCORE BAR ────────────────────────────────────────────
func _build_header(data: Dictionary) -> Control:
	var result := str(data.get("result", "victory"))
	var won := bool(data.get("won", false))
	var sec := _section(36, SEC_PAD_H, 28)
	var box: VBoxContainer = sec.get_child(0)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 24)
	box.add_child(top)

	# Left column.
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	top.add_child(left)

	var kicker := "CARBON AND CAPITAL · END OF GAME · TURN %d OF %d" % [int(data.get("turn", 0)), int(data.get("max_turns", 300))]
	left.add_child(_lbl(kicker, _tracked_font(), 12, C_KICKER))

	var word_row := HBoxContainer.new()
	word_row.add_theme_constant_override("separation", 18)
	word_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	left.add_child(word_row)
	# The big word is the result CATEGORY and sits beside the title, so continuity needs its own
	# — left on the else branch it read "DEFEAT Continuity", which is the opposite of the point.
	var word := "VICTORY" if result == "victory" else ("SURVIVAL" if result == "continuity" else "DEFEAT")
	var word_col := C_DISPLAY_WIN if result == "victory" else (
		C_DISPLAY_CONT if result == "continuity" else C_DISPLAY_LOSE)
	var word_lbl := _lbl(word, _BEBAS, 74, word_col)
	word_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	word_row.add_child(word_lbl)
	var title_lbl := _lbl(str(data.get("title", "")), _BEBAS, 40, _accent)
	title_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	word_row.add_child(title_lbl)

	left.add_child(_lbl(str(data.get("epithet", "")), _UIFonts.PLEX_MED, 15, C_EPITHET))

	# Right column (right-aligned).
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(360, 0)
	right.add_theme_constant_override("separation", 8)
	top.add_child(right)

	var total_row := HBoxContainer.new()
	total_row.alignment = BoxContainer.ALIGNMENT_END
	total_row.add_theme_constant_override("separation", 6)
	right.add_child(total_row)
	var total_col := C_TOTAL_WIN if result == "victory" else (
		C_TOTAL_CONT if result == "continuity" else C_TOTAL_LOSE)
	var total_lbl := _lbl(str(int(data.get("total", 0))), _UIFonts.mono(), 52, total_col)
	total_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	total_row.add_child(total_lbl)
	var thr_lbl := _lbl("/ %d" % int(data.get("threshold", 0)), _UIFonts.mono(), 20, DS.PALETTE.TEXT_DIM)
	thr_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	total_row.add_child(thr_lbl)

	# Pill badge.
	var pill_row := HBoxContainer.new()
	pill_row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(pill_row)
	pill_row.add_child(_build_pill(won, int(data.get("turn", 0)), result))

	var sc := int(data.get("secured_count", 0))
	var sec_lbl := _lbl("%d of 5 tracks secured" % sc, _UIFonts.PLEX_MED, 12, DS.PALETTE.TEXT_DIM)
	sec_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(sec_lbl)

	# ── Score bar ──
	var bar_wrap := VBoxContainer.new()
	bar_wrap.add_theme_constant_override("separation", 9)
	var bar_margin := MarginContainer.new()
	bar_margin.add_theme_constant_override("margin_top", 24)
	bar_margin.add_child(bar_wrap)
	box.add_child(bar_margin)

	var bar := _ScoreBar.new()
	bar.custom_minimum_size = Vector2(0, 20)
	bar.total = int(data.get("total", 0))
	bar.threshold = int(data.get("threshold", 0))
	bar.tracks = data.get("tracks", [])
	bar_wrap.add_child(bar)

	var labels := HBoxContainer.new()
	bar_wrap.add_child(labels)
	var l_left := _lbl("Tracks %d" % int(data.get("total", 0)), _UIFonts.PLEX_MED, 12, DS.PALETTE.TEXT_DIM)
	l_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_child(l_left)
	var l_mid := _lbl("%d to win" % int(data.get("threshold", 0)), _UIFonts.PLEX_MED, 12, DS.PALETTE.TEXT_DIM)
	l_mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_child(l_mid)
	var l_right := _lbl("Final %d" % int(data.get("total", 0)), _UIFonts.mono(), 12, total_col)
	l_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l_right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_child(l_right)

	# Faint radial ACCENT glow at the top of the header.
	var glow := _Glow.new()
	glow.col = _accent
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sec.add_child(glow)
	sec.move_child(glow, 0)
	return sec


func _build_pill(won: bool, turn: int, result: String = "victory") -> Control:
	var pc := PanelContainer.new()
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 12)
	mc.add_theme_constant_override("margin_right", 12)
	mc.add_theme_constant_override("margin_top", 5)
	mc.add_theme_constant_override("margin_bottom", 5)
	pc.add_child(mc)
	if won:
		pc.add_theme_stylebox_override("panel", _sb(C_TOTAL_WIN, C_TOTAL_WIN, 0, 12, 0))
		mc.add_child(_lbl("✓  Won on turn %d" % turn, _UIFonts.PLEX_SEMI, 13, Color("#0c1622")))
	elif result == "continuity":
		# Not a red cross: no track was secured, but the company is still trading.
		var amb := C_ACCENT_CONT
		pc.add_theme_stylebox_override("panel", _sb(Color(amb.r, amb.g, amb.b, 0.14), amb, 1, 12, 0))
		mc.add_child(_lbl("=  Still trading on turn %d" % turn, _UIFonts.PLEX_SEMI, 13, amb))
	else:
		var red := C_ACCENT_LOSE
		pc.add_theme_stylebox_override("panel", _sb(Color(red.r, red.g, red.b, 0.14), red, 1, 12, 0))
		mc.add_child(_lbl("✗  No track secured", _UIFonts.PLEX_SEMI, 13, red))
	return pc


# ── Section 2: BANNER (five pennants) ────────────────────────────────────────
func _build_banner(data: Dictionary) -> Control:
	var result := str(data.get("result", "victory"))
	var sec := _section(32, SEC_PAD_H, 36)
	var box: VBoxContainer = sec.get_child(0)
	box.add_child(_section_head("The banner"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)

	var tracks: Array = data.get("tracks", [])
	for t: Dictionary in tracks:
		row.add_child(_build_pennant(t, result))
	return sec


func _build_pennant(t: Dictionary, result: String) -> Control:
	var done := bool(t.get("done", false))
	var color := Color(str(t.get("color", "#ffffff")))

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	if done:
		card.add_theme_stylebox_override("panel", _sb(Color("#0e2135"), Color(color.r, color.g, color.b, 0.40), 1, 13, 0))
	else:
		card.modulate = Color(1, 1, 1, 0.82)
		card.add_theme_stylebox_override("panel", _sb(Color("#0b1a2b"), C_HEADER_BORDER, 1, 13, 0))

	# Top hairline in the track colour (or grey).
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	card.add_child(stack)
	var hair := ColorRect.new()
	hair.color = color if done else C_HEADER_BORDER
	hair.custom_minimum_size = Vector2(0, 2)
	stack.add_child(hair)

	if done:
		var glow := _PennantGlow.new()
		glow.col = color
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(glow)
		card.move_child(glow, 0)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 16)
	pad.add_theme_constant_override("margin_right", 16)
	pad.add_theme_constant_override("margin_top", 20)
	pad.add_theme_constant_override("margin_bottom", 16)
	stack.add_child(pad)

	var inner := VBoxContainer.new()
	inner.alignment = BoxContainer.ALIGNMENT_BEGIN
	inner.add_theme_constant_override("separation", 6)
	pad.add_child(inner)

	var crest := _Crest.new()
	crest.done = done
	crest.color = color
	crest.glyph = str(t.get("key", ""))
	crest.custom_minimum_size = Vector2(0, 104)
	inner.add_child(crest)

	var name_lbl := _lbl(str(t.get("name", "")), _BEBAS, 27, C_NAME_LIT if done else C_NAME_UNLIT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_lbl)

	var desc_lbl := _lbl(str(t.get("desc", "")), _UIFonts.PLEX, 11, DS.PALETTE.TEXT_DIM)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(desc_lbl)

	inner.add_child(_spacer_v(4))

	var stat_lbl := _lbl(str(t.get("stat", "")), _UIFonts.mono(), 19, color if done else DS.PALETTE.TEXT_DIM)
	stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(stat_lbl)

	var sub_lbl := _lbl(str(t.get("sub", "")), _UIFonts.PLEX, 11, DS.PALETTE.TEXT_DIM)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inner.add_child(sub_lbl)

	inner.add_child(_spacer_v(6))

	# Bottom badge.
	var badge := PanelContainer.new()
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var bmc := MarginContainer.new()
	bmc.add_theme_constant_override("margin_left", 12)
	bmc.add_theme_constant_override("margin_right", 12)
	bmc.add_theme_constant_override("margin_top", 4)
	bmc.add_theme_constant_override("margin_bottom", 4)
	badge.add_child(bmc)
	if done:
		badge.add_theme_stylebox_override("panel", _sb(C_CREST_GOLD_B, C_CREST_GOLD_A, 1, 8, 0))
		bmc.add_child(_lbl("Secured · turn %d" % int(t.get("at", 0)), _UIFonts.PLEX_SEMI, 11, Color("#241a08")))
	else:
		var border := Color("#3a2224") if result == "defeat" else Color("#1c3149")
		badge.add_theme_stylebox_override("panel", _sb(C_TRACK_BG, border, 1, 8, 0))
		bmc.add_child(_lbl("%d%% banked" % int(round(float(t.get("pct", 0.0)) * 100.0)), _UIFonts.PLEX_MED, 11, DS.PALETTE.TEXT_DIM))
	inner.add_child(badge)
	return card


# ── Section 3: COPY + STATLINE ───────────────────────────────────────────────
func _build_copy(data: Dictionary) -> Control:
	var result := str(data.get("result", "victory"))
	var sec := _section(32, SEC_PAD_H, 36)
	var box: VBoxContainer = sec.get_child(0)
	box.add_child(_section_head("What you built" if result == "victory" else "What remains"))

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 44)
	box.add_child(cols)

	# Copy column.
	var copy_col := VBoxContainer.new()
	copy_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy_col.add_theme_constant_override("separation", 16)
	cols.add_child(copy_col)

	var paras: Array = data.get("copy", [])
	for i in paras.size():
		var text := str(paras[i])
		if i == 0 and text.length() > 0:
			copy_col.add_child(_dropcap_para(text))
		else:
			copy_col.add_child(_copy_para(text))

	# Statline column (2×2 grid of small cards).
	var stat_col := VBoxContainer.new()
	stat_col.custom_minimum_size = Vector2(360, 0)
	cols.add_child(stat_col)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	stat_col.add_child(grid)
	for s: Dictionary in (data.get("statline", []) as Array):
		grid.add_child(_stat_card(str(s.get("v", "")), str(s.get("k", ""))))
	return sec


func _copy_para(text: String) -> Control:
	var l := _lbl(text, _UIFonts.PLEX_MED, 15, C_COPY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", 9)
	return l


func _dropcap_para(text: String) -> Control:
	# Large ACCENT drop-cap of the first letter, then the rest flows beside/under it.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := _lbl(text.substr(0, 1), _BEBAS, 42, _accent)
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cap.custom_minimum_size = Vector2(30, 0)
	row.add_child(cap)
	var rest := _lbl(text.substr(1), _UIFonts.PLEX_MED, 15, C_COPY)
	rest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.add_theme_constant_override("line_spacing", 9)
	row.add_child(rest)
	return row


func _stat_card(value: String, label: String) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _sb(Color("#0b1a2b"), C_CARD_BORDER, 1, 11, 0))
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 16)
	mc.add_theme_constant_override("margin_right", 16)
	mc.add_theme_constant_override("margin_top", 14)
	mc.add_theme_constant_override("margin_bottom", 14)
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	mc.add_child(v)
	v.add_child(_lbl(value, _UIFonts.mono(), 23, C_STAT_VALUE))
	v.add_child(_lbl(label.to_upper(), _UIFonts.PLEX_MED, 11, DS.PALETTE.TEXT_DIM))
	return pc


# ── Section 4: CHARTS + EMPIRE ───────────────────────────────────────────────
func _build_charts(data: Dictionary) -> Control:
	var sec := _section(32, SEC_PAD_H, 36)
	var box: VBoxContainer = sec.get_child(0)
	box.add_child(_section_head("The books"))

	var charts: Dictionary = data.get("charts", {})
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	box.add_child(grid)

	# Revenue — filled area line.
	var rev := _LineChart.new()
	rev.series = charts.get("revenue", [])
	rev.col = C_REV
	grid.add_child(_chart_card("Revenue per turn", str(charts.get("revenue_big", "")),
		str(charts.get("revenue_sub", "")), C_REV, rev, "turn 1 … turn %d" % int(data.get("turn", 0))))

	# Output — bar chart.
	var outp := _BarChart.new()
	outp.series = charts.get("output", [])
	outp.col = C_OUT
	grid.add_child(_chart_card("Output per turn", str(charts.get("output_big", "")),
		str(charts.get("output_sub", "")), C_OUT, outp, "sampled across the game"))

	# Buildings — step area.
	var bld := _StepChart.new()
	bld.series = charts.get("buildings", [])
	bld.col = C_BLD
	grid.add_child(_chart_card("Buildings standing", str(charts.get("buildings_big", "")),
		str(charts.get("buildings_sub", "")), C_BLD, bld, "turn 1 … turn %d" % int(data.get("turn", 0))))

	# Biggest outputs — five ranked bar rows.
	grid.add_child(_build_biggest(charts))

	# Empire card (full width).
	box.add_child(_build_empire(data.get("empire", {})))
	return sec


func _chart_card(label: String, big: String, sub: String, col: Color, body: Control, footer: String) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _sb(Color("#0b1a2b"), C_CARD_BORDER, 1, 13, 0))
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)

	# Header row: label (left) + big number & sub (right).
	var head := HBoxContainer.new()
	v.add_child(head)
	var lbl := _lbl(label.to_upper(), _UIFonts.PLEX_MED, 11, C_CHART_LABEL)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lbl)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 2)
	head.add_child(rcol)
	var big_lbl := _lbl(big, _UIFonts.mono(), 20, col)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(big_lbl)
	var sub_lbl := _lbl(sub, _UIFonts.PLEX, 11, DS.PALETTE.TEXT_DIM)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(sub_lbl)

	body.custom_minimum_size = Vector2(0, 150)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	if footer != "":
		v.add_child(_lbl(footer, _UIFonts.PLEX, 11, DS.PALETTE.TEXT_DIM))
	return pc


func _build_biggest(charts: Dictionary) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _sb(Color("#0b1a2b"), C_CARD_BORDER, 1, 13, 0))
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var lbl := _lbl("BIGGEST OUTPUTS", _UIFonts.PLEX_MED, 11, C_CHART_LABEL)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lbl)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 2)
	head.add_child(rcol)
	var big_lbl := _lbl(_num(int(charts.get("top_total", 0))), _UIFonts.mono(), 20, C_BIG)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(big_lbl)
	var sub_lbl := _lbl("lifetime units, top five goods", _UIFonts.PLEX, 11, DS.PALETTE.TEXT_DIM)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(sub_lbl)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 8)
	v.add_child(rows)

	var top: Array = charts.get("top", [])
	var maxu := 1
	if not top.is_empty():
		maxu = maxi(1, int((top[0] as Dictionary).get("units", 1)))
	for i in top.size():
		rows.add_child(_biggest_row(top[i], i, maxu))
	return pc


func _biggest_row(g: Dictionary, rank: int, maxu: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 30)

	var icon: Control = _UIHelpers.make_framed_good_icon(str(g.get("good_id", "")), str(g.get("internal", "")), 26)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var name_lbl := _lbl(str(g.get("label", "")), _UIFonts.PLEX_MED, 13, C_STAT_VALUE)
	name_lbl.custom_minimum_size = Vector2(108, 0)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(name_lbl)

	var bar := _RankBar.new()
	bar.frac = clampf(float(int(g.get("units", 0))) / float(maxu), 0.0, 1.0)
	bar.rank = rank
	bar.col = Color(str(g.get("color", "#8f9dae")))
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.custom_minimum_size = Vector2(0, 18)
	row.add_child(bar)

	var num := _lbl(_num(int(g.get("units", 0))), _UIFonts.mono(), 14, C_OUT if rank == 0 else C_STAT_VALUE)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.custom_minimum_size = Vector2(80, 0)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	return row


func _build_empire(empire: Dictionary) -> Control:
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", _sb(Color("#0b1a2b"), C_CARD_BORDER, 1, 13, 0))
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 20)
	mc.add_theme_constant_override("margin_right", 20)
	mc.add_theme_constant_override("margin_top", 16)
	mc.add_theme_constant_override("margin_bottom", 16)
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	mc.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(_lbl("THE EMPIRE", _UIFonts.PLEX_MED, 11, C_CHART_LABEL))
	var ports: Array = empire.get("ports", [])
	var meta := _lbl("final production network · %d ports" % ports.size(), _UIFonts.PLEX, 11, DS.PALETTE.TEXT_DIM)
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(meta)
	var expand := Button.new()
	expand.text = "Expand"
	expand.theme_type_variation = "Silver"
	expand.pressed.connect(_open_expand)
	head.add_child(expand)

	# The REAL empire network, snapshotted from the live sim at game end. Static
	# inline (no input); the Expand overlay gets the interactive pan/zoom version.
	# Falls back to the stylised design map when there is no graph to show.
	var graph := _make_empire_graph(false)
	if graph != null:
		graph.custom_minimum_size = Vector2(0, 380)
		graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(graph)
	else:
		var map := _EmpireMap.new()
		map.data = empire
		map.custom_minimum_size = Vector2(0, 260)
		map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_child(map)
	return pc


## Build the live empire node-graph exactly the way the Tab empire view does
## (EmpireGraph.build → EmpireLayout.solve/place_ports → GraphWorld.set_graph),
## capturing the network as it stands at the moment the game ended. Returns null
## when there's nothing to draw. `interactive` keeps GraphWorld's pan/zoom; the
## node cards' click-through (focus a building) is always disabled — game over.
func _make_empire_graph(interactive: bool) -> Control:
	var terrain: Node = get_tree().get_first_node_in_group("hex_map")
	var g: Dictionary = _EmpireGraph.build(terrain)
	if (g.get("nodes", []) as Array).is_empty():
		return null
	_EmpireLayout.solve(g["nodes"], g["edges"])
	# The end screen shows the network as it stood when the company stopped trading, so the SELL
	# row goes: nothing leaves through those docks any more. The BUY row stays, because what the
	# empire drew in from the market is part of the picture that remains (owner 2026-08-01).
	# The sell ports are still POSITIONED — place_buy_ports mirrors each top hex onto its bottom
	# twin's x — they are simply not handed to the graph, so nothing draws them.
	var area: Rect2 = _EmpireLayout.bbox_of(g["nodes"])
	_EmpireLayout.place_ports(g["ports"], area)
	_EmpireLayout.place_buy_ports(g["buy_ports"], g["ports"], area)
	var world: Control = _GraphWorld.new()
	world.clip_contents = true
	world.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	# set_graph fits the view to the control's size, which is 0 until layout runs —
	# apply it once the graph has a real rect (first resize with width; applied once).
	var applied := [false]
	world.resized.connect(func() -> void:
		if applied[0] or world.size.x <= 1.0:
			return
		applied[0] = true
		# Empty sell ports + empty sell edges; the buy row and its market lines carry through.
		world.set_graph(g["nodes"], g["edges"], [], [], g["market_edges"], g["buy_ports"])
		for c in world.get_children():
			if c is Control:
				(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE)
	return world


# ── Section 5: FOOTER ────────────────────────────────────────────────────────
func _build_footer() -> Control:
	var sec := _section(30, SEC_PAD_H, 38)
	var box: VBoxContainer = sec.get_child(0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 16)

	var divider := ColorRect.new()
	divider.color = C_HEADER_BORDER
	divider.custom_minimum_size = Vector2(120, 1)
	divider.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(divider)

	var btn := Button.new()
	btn.text = "   Back to Main Menu"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.icon = _make_arrow_tex(Color("#0c1622"), 18)
	btn.add_theme_font_override("font", _BEBAS)
	btn.add_theme_font_size_override("font_size", 24)
	btn.add_theme_color_override("font_color", Color("#0c1622"))
	btn.add_theme_color_override("font_hover_color", Color("#0c1622"))
	btn.add_theme_color_override("font_pressed_color", Color("#0c1622"))
	btn.add_theme_stylebox_override("normal", _gold_btn_sb(0.0))
	btn.add_theme_stylebox_override("hover", _gold_btn_sb(0.08))
	btn.add_theme_stylebox_override("pressed", _gold_btn_sb(-0.08))
	btn.add_theme_stylebox_override("focus", _gold_btn_sb(0.08))
	btn.pressed.connect(func() -> void: back_to_menu_pressed.emit())
	box.add_child(btn)

	var cap := _lbl("Your ledger has been archived to the Hall of Records.", _UIFonts.PLEX_MED, 12, C_FOOT_CAP)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(cap)
	return sec


# ── Expand overlay (enlarged empire map) ─────────────────────────────────────
func _open_expand() -> void:
	if _expand_overlay != null:
		return
	var scroll := get_node_or_null("Scroll")
	var host: Node = scroll if scroll != null else self
	var overlay := PanelContainer.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_theme_stylebox_override("panel", _sb(Color(0.02, 0.05, 0.09, 1.0), _accent, 2, 0, 0))
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	_expand_overlay = overlay

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", 40)
	mc.add_theme_constant_override("margin_right", 40)
	mc.add_theme_constant_override("margin_top", 30)
	mc.add_theme_constant_override("margin_bottom", 30)
	mc.add_child(v)
	overlay.add_child(mc)

	var head := HBoxContainer.new()
	v.add_child(head)
	var h := _lbl("THE EMPIRE — FINAL PRODUCTION NETWORK", _tracked_font(), 13, C_ACCENT_WIN)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(h)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = "Silver"
	close.pressed.connect(_close_expand)
	head.add_child(close)

	# The real network, interactive: drag to pan, scroll to zoom (node clicks stay off).
	var graph := _make_empire_graph(true)
	if graph != null:
		graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(graph)
	else:
		var map := _EmpireMap.new()
		map.data = _empire_data
		map.big = true
		map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		map.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(map)


func _close_expand() -> void:
	if _expand_overlay != null:
		_expand_overlay.queue_free()
		_expand_overlay = null


# ── Small builders / helpers ─────────────────────────────────────────────────
func _section(pad_top: int, pad_h: int, pad_bottom: int) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.add_theme_constant_override("margin_left", pad_h)
	mc.add_theme_constant_override("margin_right", pad_h)
	mc.add_theme_constant_override("margin_top", pad_top)
	mc.add_theme_constant_override("margin_bottom", pad_bottom)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	mc.add_child(v)
	return mc


func _section_head(text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var lbl := _lbl(text, _BEBAS, 26, C_SECTION_HEAD)
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var rule := _HRule.new()
	rule.mode = _HRule.FADE_RIGHT
	rule.col = C_CARD_BORDER
	rule.custom_minimum_size = Vector2(0, 1)
	rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(rule)
	return row


func _lbl(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _spacer_v(h: int) -> Control:
	var s := Control.new()
	s.custom_minimum_size = Vector2(0, h)
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


func _tracked_font() -> FontVariation:
	if _tracked == null:
		_tracked = FontVariation.new()
		_tracked.base_font = _UIFonts.PLEX_SEMI
		_tracked.spacing_glyph = 2
	return _tracked


func _sb(bg: Color, border: Color, border_w: int, radius: int, pad: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	return s


func _gold_btn_sb(shift: float) -> StyleBoxFlat:
	var base := C_CREST_GOLD_B
	if shift > 0.0:
		base = base.lightened(shift)
	elif shift < 0.0:
		base = base.darkened(-shift)
	var s := _sb(base, C_CREST_GOLD_A, 1, 10, 0)
	s.content_margin_left = 26
	s.content_margin_right = 26
	s.content_margin_top = 12
	s.content_margin_bottom = 12
	return s


func _make_arrow_tex(color: Color, size: int) -> Texture2D:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color.TRANSPARENT)
	# A left-pointing triangle arrowhead + shaft.
	var mid := int(size / 2.0)
	for x in range(2, mid + 2):
		var half := x - 2
		for y in range(mid - half, mid + half + 1):
			if y >= 0 and y < size:
				img.set_pixel(x, y, color)
	for x in range(mid, size - 2):
		for y in range(mid - 2, mid + 2):
			if y >= 0 and y < size:
				img.set_pixel(x, y, color)
	return ImageTexture.create_from_image(img)


func _num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if n < 0 else "") + out


# ═══════════════════════════════════════════════════════════════════════════════
# Custom-draw helper classes. All use 4-vertex gradient quads, solid fills, hex/poly
# polygons and polylines — never many-point gradient polygons (GL-compat fan artifact).
# ═══════════════════════════════════════════════════════════════════════════════

class DrawUtil:
	## Rounded-rect fill via a plus-shape of two rects + four corner circles.
	static func round_rect(ci: CanvasItem, r: Rect2, radius: float, col: Color) -> void:
		var rad: float = minf(radius, minf(r.size.x, r.size.y) * 0.5)
		if rad <= 0.5:
			ci.draw_rect(r, col)
			return
		ci.draw_rect(Rect2(r.position + Vector2(rad, 0), Vector2(r.size.x - rad * 2.0, r.size.y)), col)
		ci.draw_rect(Rect2(r.position + Vector2(0, rad), Vector2(r.size.x, r.size.y - rad * 2.0)), col)
		ci.draw_circle(r.position + Vector2(rad, rad), rad, col)
		ci.draw_circle(r.position + Vector2(r.size.x - rad, rad), rad, col)
		ci.draw_circle(r.position + Vector2(rad, r.size.y - rad), rad, col)
		ci.draw_circle(r.position + Vector2(r.size.x - rad, r.size.y - rad), rad, col)

	static func hexagon(cx: float, cy: float, radius: float) -> PackedVector2Array:
		# Flat-top hexagon (flat horizontal top and bottom edges).
		var pts := PackedVector2Array()
		for i in 6:
			var a := deg_to_rad(60.0 * float(i))
			pts.append(Vector2(cx + radius * cos(a), cy + radius * sin(a)))
		return pts


# The silver bezel sheen + corner rivets, drawn over the plate.
class _Bezel extends Control:
	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Diagonal light band top-left → transparent (150deg feel).
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
			PackedColorArray([Color(0.78, 0.82, 0.87, 0.55), Color(0.44, 0.48, 0.53, 0.0),
				Color(0.27, 0.30, 0.35, 0.45), Color(0.68, 0.72, 0.78, 0.30)]))
		# Central dark trough (horizontal band).
		var y0 := h * 0.42
		var y1 := h * 0.58
		draw_polygon(
			PackedVector2Array([Vector2(0, y0), Vector2(w, y0), Vector2(w, y1), Vector2(0, y1)]),
			PackedColorArray([Color(0.16, 0.18, 0.21, 0.30), Color(0.16, 0.18, 0.21, 0.30),
				Color(0.16, 0.18, 0.21, 0.30), Color(0.16, 0.18, 0.21, 0.30)]))
		# Four corner rivets.
		var inset := 12.0
		for p in [Vector2(inset, inset), Vector2(w - inset, inset),
				Vector2(inset, h - inset), Vector2(w - inset, h - inset)]:
			draw_circle(p, 9.0, Color("#5a636e"))
			draw_circle(p, 6.5, Color("#c9d0d8"))
			draw_circle(p - Vector2(1.5, 1.5), 3.2, Color("#eef2f6"))


# Faint radial accent glow (header + expand).
class _Glow extends Control:
	var col: Color = Color("#e6b34a")
	func _draw() -> void:
		var cx := size.x * 0.5
		for i in range(6, 0, -1):
			var rr := float(i) * 28.0
			draw_circle(Vector2(cx, 4.0), rr, Color(col.r, col.g, col.b, 0.02))


# Soft glow inside a lit pennant.
class _PennantGlow extends Control:
	var col: Color = Color.WHITE
	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.30
		for i in range(6, 0, -1):
			draw_circle(Vector2(cx, cy), float(i) * 12.0, Color(col.r, col.g, col.b, 0.018))
		# Faint 135° diagonal stripe overlay.
		var w := size.x
		var h := size.y
		draw_polygon(
			PackedVector2Array([Vector2(0, 0), Vector2(w * 0.5, 0), Vector2(0, h * 0.5)]),
			PackedColorArray([Color(col.r, col.g, col.b, 0.06), Color(col.r, col.g, col.b, 0.0),
				Color(col.r, col.g, col.b, 0.0)]))


# A horizontal gradient hairline. mode: SYMMETRIC (transp→col→transp), FADE_RIGHT (col→transp).
class _HRule extends Control:
	const SYMMETRIC := 0
	const FADE_RIGHT := 1
	var mode: int = SYMMETRIC
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if mode == SYMMETRIC:
			var mid := w * 0.5
			draw_polygon(
				PackedVector2Array([Vector2(0, 0), Vector2(mid, 0), Vector2(mid, h), Vector2(0, h)]),
				PackedColorArray([Color(col.r, col.g, col.b, 0.0), col, col, Color(col.r, col.g, col.b, 0.0)]))
			draw_polygon(
				PackedVector2Array([Vector2(mid, 0), Vector2(w, 0), Vector2(w, h), Vector2(mid, h)]),
				PackedColorArray([col, Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0), col]))
		else:
			draw_polygon(
				PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
				PackedColorArray([col, Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0), col]))


# The score bar: track, per-track segments (rising-bar model), threshold marker.
class _ScoreBar extends Control:
	const MAXPTS := 5000.0
	var total: int = 0
	var threshold: int = 0
	var tracks: Array = []
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var full := Rect2(Vector2.ZERO, Vector2(w, h))
		DrawUtil.round_rect(self, full, h * 0.5, Color("#0a1623"))
		# Segments — one per track with pct>0, width ∝ round(pct*1000)/5000.
		var x := 1.0
		for t: Dictionary in tracks:
			var pct := float(t.get("pct", 0.0))
			if pct <= 0.0:
				continue
			var pts: float = round(pct * 1000.0)
			var seg_w := (pts / MAXPTS) * (w - 2.0)
			var col := Color(str(t.get("color", "#ffffff")))
			if not bool(t.get("done", false)):
				col = Color(col.r, col.g, col.b, 0.32)
			draw_rect(Rect2(Vector2(x, 2.0), Vector2(maxf(1.0, seg_w), h - 4.0)), col)
			x += seg_w
		# Threshold marker (bright, subtle glow).
		var mx := clampf(float(threshold) / MAXPTS, 0.0, 1.0) * w
		draw_rect(Rect2(Vector2(mx - 3.0, -2.0), Vector2(6.0, h + 4.0)), Color(0.95, 0.90, 0.78, 0.14))
		draw_rect(Rect2(Vector2(mx - 1.0, -2.0), Vector2(2.0, h + 4.0)), Color("#f2e6c8"))


# The gold crest hexagon + a minimal track glyph.
class _Crest extends Control:
	# Owner-supplied track icons (white silhouettes, tinted at draw time).
	const _ICONS := {
		"autarkic": preload("res://assets/icons/victory/autarkic.png"),
		"logistics": preload("res://assets/icons/victory/logistics.png"),
		"richest": preload("res://assets/icons/victory/richest.png"),
		"widest": preload("res://assets/icons/victory/widest.png"),
		"greenest": preload("res://assets/icons/victory/greenest.png"),
	}
	var done: bool = false
	var color: Color = Color.WHITE
	var glyph: String = ""
	func _draw() -> void:
		var cx := size.x * 0.5
		var cy := size.y * 0.5
		var r := 48.0
		var hex := DrawUtil.hexagon(cx, cy, r)
		if done:
			# Gold vertical gradient via a 4-vertex quad clipped visually by the hex fill:
			# fill the hex with the mid gold, then lay a top-light / bottom-dark quad band.
			draw_polygon(hex, PackedColorArray([
				Color("#f0dfae"), Color("#e7cd8f"), Color("#c9a75c"),
				Color("#a8863c"), Color("#c9a75c"), Color("#e7cd8f")]))
			draw_polyline(_closed(hex), Color("#f2e6c8"), 2.0, true)
			var inner := DrawUtil.hexagon(cx, cy, r - 6.0)
			draw_polyline(_closed(inner), Color(1, 1, 1, 0.25), 1.0, true)
		else:
			draw_polygon(hex, PackedColorArray([
				Color("#0a1623"), Color("#0a1623"), Color("#0a1623"),
				Color("#0a1623"), Color("#0a1623"), Color("#0a1623")]))
			draw_polyline(_closed(hex), Color("#22384f"), 1.5, true)
		var tex: Texture2D = _ICONS.get(glyph)
		if tex != null:
			var s := 46.0
			var tint := Color("#141d29") if done else Color("#31465c")
			draw_texture_rect(tex, Rect2(cx - s * 0.5, cy - s * 0.5, s, s), false, tint)

	func _closed(pts: PackedVector2Array) -> PackedVector2Array:
		var c := pts.duplicate()
		c.append(pts[0])
		return c


# Filled area line chart.
class _LineChart extends Control:
	var series: Array = []
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		# Faint gridlines.
		for i in range(1, 4):
			var y := h * float(i) / 4.0
			draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.05), 1.0)
		if series.size() < 2:
			return
		var mx := 0.0
		for v in series:
			mx = maxf(mx, float(v))
		mx = maxf(mx, 1.0)
		var pts := PackedVector2Array()
		var n := series.size()
		for i in n:
			var x := w * float(i) / float(n - 1)
			var y := h - (float(series[i]) / mx) * (h - 4.0)
			pts.append(Vector2(x, y))
		# Fill under the line (fan from a baseline is fine — single solid colour, no per-vertex gradient).
		var fill := pts.duplicate()
		fill.append(Vector2(w, h))
		fill.append(Vector2(0, h))
		draw_polygon(fill, PackedColorArray([Color(col.r, col.g, col.b, 0.18)]))
		draw_polyline(pts, col, 2.0, true)


# Bar chart (≈46 bars; peak in cream).
class _BarChart extends Control:
	var series: Array = []
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if series.is_empty():
			return
		var n := mini(46, series.size())
		# Sample n bars evenly.
		var vals := PackedFloat32Array()
		var mx := 0.0
		var peak_i := 0
		for i in n:
			var src := int(float(i) / float(n) * float(series.size()))
			var v := float(series[clampi(src, 0, series.size() - 1)])
			vals.append(v)
			if v > mx:
				mx = v
				peak_i = i
		mx = maxf(mx, 1.0)
		var gap := 2.0
		var bw := (w - gap * float(n - 1)) / float(n)
		for i in n:
			var bh := (vals[i] / mx) * (h - 2.0)
			var x := float(i) * (bw + gap)
			var c := Color("#f2e6c8") if i == peak_i else Color(col.r, col.g, col.b, 0.75)
			draw_rect(Rect2(Vector2(x, h - bh), Vector2(maxf(1.0, bw), bh)), c)


# Step area chart.
class _StepChart extends Control:
	var series: Array = []
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		for i in range(1, 4):
			var y := h * float(i) / 4.0
			draw_line(Vector2(0, y), Vector2(w, y), Color(1, 1, 1, 0.05), 1.0)
		if series.size() < 2:
			return
		var mx := 0.0
		for v in series:
			mx = maxf(mx, float(v))
		mx = maxf(mx, 1.0)
		var pts := PackedVector2Array()
		var n := series.size()
		for i in n:
			var x := w * float(i) / float(n - 1)
			var y := h - (float(series[i]) / mx) * (h - 4.0)
			if i > 0:
				pts.append(Vector2(x, pts[pts.size() - 1].y))
			pts.append(Vector2(x, y))
		var fill := pts.duplicate()
		fill.append(Vector2(w, h))
		fill.append(Vector2(0, h))
		draw_polygon(fill, PackedColorArray([Color(col.r, col.g, col.b, 0.16)]))
		draw_polyline(pts, col, 2.0, true)


# A single horizontal ranked bar (rank 0 gold + glow).
class _RankBar extends Control:
	var frac: float = 0.0
	var rank: int = 0
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		DrawUtil.round_rect(self, Rect2(Vector2.ZERO, Vector2(w, h)), h * 0.5, Color("#0a1623"))
		var bw := maxf(h, frac * w)
		if rank == 0:
			DrawUtil.round_rect(self, Rect2(Vector2(0, 0), Vector2(bw, h)), h * 0.5, Color("#e6b34a"))
			DrawUtil.round_rect(self, Rect2(Vector2(0, 0), Vector2(bw, h * 0.55)), h * 0.4, Color(1, 1, 1, 0.18))
		else:
			DrawUtil.round_rect(self, Rect2(Vector2(0, 0), Vector2(bw, h)), h * 0.5, Color(col.r, col.g, col.b, 0.6))


# The empire production-network map: four node columns, connectors, gold ports.
class _EmpireMap extends Control:
	var data: Dictionary = {}
	var big: bool = false
	func _draw() -> void:
		var w := size.x
		var h := size.y
		var node_w := 200.0 if big else 186.0
		var node_h := 56.0 if big else 50.0
		var mines := int(data.get("mines", 0))
		var furn_a := int(data.get("furn_a", 0))
		var furn_b := int(data.get("furn_b", 0))
		var factories := int(data.get("factories", 0))
		var ports: Array = data.get("ports", [])
		var cols := [
			{"label": "Mine", "n": mines},
			{"label": "Furnace", "n": furn_a},
			{"label": "Furnace", "n": furn_b},
			{"label": "Goods Factory", "n": factories},
		]
		var ny := h * 0.28
		var xs := PackedFloat32Array()
		var count := cols.size()
		for i in count:
			var cx := (w / float(count)) * (float(i) + 0.5)
			xs.append(cx)
		# Grey connectors column → column.
		for i in range(count - 1):
			draw_line(Vector2(xs[i] + node_w * 0.5, ny), Vector2(xs[i + 1] - node_w * 0.5, ny),
				Color(0.5, 0.6, 0.72, 0.35), 2.0, true)
		# Node boxes.
		for i in count:
			_node(xs[i], ny, node_w, node_h, str(cols[i].label), int(cols[i].n))
		# Ports as gold hexagons along the bottom.
		var py := h * 0.78
		var pcount := ports.size()
		var port_x := PackedFloat32Array()
		for i in pcount:
			var px := (w / float(pcount + 1)) * float(i + 1)
			port_x.append(px)
			_port(px, py, str(ports[i]))
		# Bold gold route from the last factory to the last port.
		if pcount > 0:
			draw_line(Vector2(xs[count - 1], ny + node_h * 0.5),
				Vector2(port_x[pcount - 1], py - (34.0 if big else 30.0)),
				Color("#e6b34a"), 3.0, true)

	func _node(cx: float, cy: float, nw: float, nh: float, label: String, n: int) -> void:
		var r := Rect2(Vector2(cx - nw * 0.5, cy - nh * 0.5), Vector2(nw, nh))
		DrawUtil.round_rect(self, r, 8.0, Color("#0b1c30"))
		draw_rect(r, Color(0.90, 0.70, 0.29, 0.55), false, 1.5)
		var f: Font = get_theme_default_font()
		var txt := "%s ×%d" % [label, n]
		draw_string(f, Vector2(r.position.x + 12, r.position.y + 21), txt,
			HORIZONTAL_ALIGNMENT_LEFT, nw - 24, 13, Color("#dfe7f0"))
		# Row of 5 status dots.
		var dot_y := r.position.y + nh - 14.0
		var colors := [Color("#5fbf6b"), Color("#5fbf6b"), Color("#e6b34a"), Color("#5fbf6b"), Color("#e2604a")]
		for d in 5:
			draw_circle(Vector2(r.position.x + 14 + float(d) * 14.0, dot_y), 3.5, colors[d])

	func _port(cx: float, cy: float, name: String) -> void:
		var r := 42.0 if big else 34.0
		var hex := DrawUtil.hexagon(cx, cy, r)
		draw_polygon(hex, PackedColorArray([
			Color("#f0dfae"), Color("#e7cd8f"), Color("#c9a75c"),
			Color("#a8863c"), Color("#c9a75c"), Color("#e7cd8f")]))
		var closed := hex.duplicate()
		closed.append(hex[0])
		draw_polyline(closed, Color("#f2e6c8"), 2.0, true)
		# Tiny crane/hull glyph.
		draw_line(Vector2(cx - r * 0.4, cy + r * 0.2), Vector2(cx + r * 0.4, cy + r * 0.2), Color("#3a2c10"), 2.0)
		draw_line(Vector2(cx - r * 0.25, cy + r * 0.2), Vector2(cx - r * 0.25, cy - r * 0.35), Color("#3a2c10"), 2.0)
		draw_line(Vector2(cx - r * 0.25, cy - r * 0.35), Vector2(cx + r * 0.35, cy - r * 0.1), Color("#3a2c10"), 2.0)
		var f: Font = get_theme_default_font()
		draw_string(f, Vector2(cx - 60, cy + r + 16), name, HORIZONTAL_ALIGNMENT_CENTER, 120, 12, Color("#c9d4e2"))
