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
const FRAME_CLEAR := 22   # content inset clearing the brass pipe frame (transport panel: 26)
const SEC_PAD_H := 44

# ── Design palette ─────────────────────────────────────────────────────────────
# DS tokens, inlined by value (a const block cannot read the DS autoload). This screen was
# ported from a "Victory Screen.html" mock and carried the mock's own palette — a lighter
# blue navy, slate-grey secondary text and a silver bezel that existed nowhere else in the
# game. Re-tokened 2026-08-24: the token each value mirrors is named beside it, and the few
# NON-token colours left are the screen's own semantics (continuity amber, medal golds).
const C_NAVY_TOP := Color("#040F1B")      # DS.BG_PANEL — every real panel's near-black
const C_NAVY_BOT := Color("#02090F")      # a step deeper, for gradient feet
const C_ACCENT_WIN := Color("#E6B85C")    # DS.WARN — the gold the menus pair with brass
const C_ACCENT_LOSE := Color("#E66060")   # DS.DANGER
## "Continuity" — survived to the bell with no track but still in profit. Amber: neither the
## gold of a win nor the red of receivership (owner 2026-08-01).
const C_ACCENT_CONT := Color("#e0932c")
## The big word is amber TOO, not a pale sand (owner 2026-08-01) — victory pairs a near-white
## word with a gold accent, but continuity reads as one amber verdict rather than two tones.
const C_DISPLAY_CONT := Color("#e0932c")
const C_TOTAL_CONT := Color("#e0932c")
const C_HEADER_BORDER := Color(0.478, 0.373, 0.173, 0.55)   # DS.ACCENT_DIM — warm dividers
const C_KICKER := Color("#E8EEF7")        # DS.TEXT (was slate #71859b — the banned grey-on-navy)
const C_DISPLAY_WIN := Color("#E8EEF7")   # DS.TEXT
const C_DISPLAY_LOSE := Color("#e8b0a4")
const C_EPITHET := Color("#C2D2E5")      # DS.TEXT_MUTED
const C_TOTAL_WIN := Color("#5BD180")    # DS.OK
const C_TOTAL_LOSE := Color("#E66060")   # DS.DANGER
const C_TRACK_BG := Color(0.0, 0.08, 0.16)   # DS.BG_INSET
const C_MARKER := Color(0.995, 0.931, 0.763) # DS.ACCENT cream
const C_CREST_GOLD_A := Color("#f0dfae")
const C_CREST_GOLD_B := Color("#d9b96a")
const C_CREST_GOLD_C := Color("#a8863c")
const C_CREST_UNLIT := Color("#0a1623")
const C_CREST_UNLIT_STROKE := Color("#22384f")
const C_GLYPH_LIT := Color("#141d29")
const C_GLYPH_UNLIT := Color("#31465c")
const C_NAME_LIT := Color("#E8EEF7")     # DS.TEXT
# An unsecured track is still a NAME the player reads, so it stays legible; the unlit
# crest and the missing gold badge already say it was not won (owner 2026-08-24: "no dark
# grey text"). TEXT_DISABLED is for controls you cannot press, not for words.
const C_NAME_UNLIT := Color("#C2D2E5")   # DS.TEXT_MUTED
const C_COPY := Color("#E8EEF7")         # DS.TEXT (body copy the player is meant to read)
const C_CARD_BORDER := Color(0.995, 0.93, 0.76, 0.55)   # DS.BORDER_SOFT — cream, not slate
const C_STAT_VALUE := Color("#E8EEF7")   # DS.TEXT
const C_CHART_LABEL := Color("#C2D2E5")  # DS.TEXT_MUTED
const C_REV := Color("#5BD180")          # DS.OK
const C_OUT := Color("#E6B85C")          # DS.WARN
const C_BLD := Color("#5fa8e0")
const C_BIG := Color("#E8EEF7")          # DS.TEXT
const C_FOOT_CAP := Color("#C2D2E5")     # DS.TEXT_MUTED (was #4a5d72, ~3:1 on navy)
const C_SECTION_HEAD := Color("#E8EEF7") # DS.TEXT

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


# ── Brass frame + navy panel shell ───────────────────────────────────────────
func _build_bezel(data: Dictionary) -> Control:
	# The COPPER pipe the tile view wears (owner 2026-08-24). pipe_frame's stylebox is a
	# single 9-slice carrying both the pipe and the opaque navy centre, so it supplies the
	# ground as well as the border — no separate background and no overlay child. This
	# replaced first the mock's silver bezel, then the brass overlay: brass is now spent
	# sparingly INSIDE the panel, and the outer chrome is the game's copper.
	var bezel := PanelContainer.new()
	bezel.custom_minimum_size = Vector2(PANEL_W, 0)
	bezel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bezel.add_theme_stylebox_override("panel",
		preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(0.0))

	# Content clears the pipe with its own margins (the sections carry SEC_PAD_H already,
	# so only the vertical clearance is new).
	var clear := MarginContainer.new()
	clear.add_theme_constant_override("margin_top", FRAME_CLEAR)
	clear.add_theme_constant_override("margin_bottom", FRAME_CLEAR)
	clear.add_theme_constant_override("margin_left", FRAME_CLEAR - 8)
	clear.add_theme_constant_override("margin_right", FRAME_CLEAR - 8)
	bezel.add_child(clear)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	clear.add_child(col)

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
	col.add_child(_build_company(data))
	col.add_child(_hborder())
	col.add_child(_build_charts(data))
	col.add_child(_hborder())
	col.add_child(_build_footer())
	return bezel


func _hborder() -> Control:
	# The mock's 1px section rules are gone (owner 2026-08-24: "remove them, keep the
	# space") — the sections separate by breathing room and their own plates now.
	var r := Control.new()
	r.custom_minimum_size = Vector2(0, 10)
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
	left.add_child(_lbl(kicker, _tracked_font(), 14, C_KICKER))

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
	var thr_lbl := _lbl("/ %d" % int(data.get("threshold", 0)), _UIFonts.mono(), 20, DS.PALETTE.TEXT_MUTED)
	thr_lbl.size_flags_vertical = Control.SIZE_SHRINK_END
	total_row.add_child(thr_lbl)

	# Pill badge.
	var pill_row := HBoxContainer.new()
	pill_row.alignment = BoxContainer.ALIGNMENT_END
	right.add_child(pill_row)
	pill_row.add_child(_build_pill(won, int(data.get("turn", 0)), result))

	var sc := int(data.get("secured_count", 0))
	# Counted from the set this match ran, not from 5 — the demo plays a different five and
	# a future set may not be five at all.
	var sec_lbl := _lbl("%d of %d tracks secured" % [sc, VictoryState.TRACK_ORDER.size()],
		_UIFonts.PLEX_MED, 12, DS.PALETTE.TEXT_MUTED)
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
	var l_left := _lbl("Tracks %d" % int(data.get("total", 0)), _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
	l_left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_child(l_left)
	var l_mid := _lbl("%d to win" % int(data.get("threshold", 0)), _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
	l_mid.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l_mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.add_child(l_mid)
	var l_right := _lbl("Final %d" % int(data.get("total", 0)), _UIFonts.mono(), 14, total_col)
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
		mc.add_child(_lbl("✓  Won on turn %d" % turn, _UIFonts.PLEX_SEMI, 14, Color("#0c1622")))
	elif result == "continuity":
		# Not a red cross: no track was secured, but the company is still trading.
		var amb := C_ACCENT_CONT
		pc.add_theme_stylebox_override("panel", _sb(Color(amb.r, amb.g, amb.b, 0.14), amb, 1, 12, 0))
		mc.add_child(_lbl("=  Still trading on turn %d" % turn, _UIFonts.PLEX_SEMI, 14, amb))
	else:
		var red := C_ACCENT_LOSE
		pc.add_theme_stylebox_override("panel", _sb(Color(red.r, red.g, red.b, 0.14), red, 1, 12, 0))
		mc.add_child(_lbl("✗  No track secured", _UIFonts.PLEX_SEMI, 14, red))
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

	var card := _CutPlate.new(0, 0, _CutPlate.STEEL)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_FILL
	# How the points were earned moved to HOVER (owner 2026-08-24). The card carries the
	# crest, the name and the score; the working — what the track measures, where the run
	# got to, what it needed — is one hover away and no longer four lines of small type
	# under every hexagon.
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.tooltip_text = _track_tooltip(t)
	# No colour bar across the top (owner 2026-08-24) — the crest below is the track's
	# colour, struck in the research panel's metal, and a flat swatch over it was the one
	# undesigned element on the card.
	if done:
		card.fill = Color("#0D1E30")
	else:
		card.dimmed = true

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 0)
	card.add_child(stack)

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
	crest.custom_minimum_size = Vector2(0, 156)   # half again, now the card has the room
	inner.add_child(crest)

	var name_lbl := _lbl(str(t.get("name", "")), _BEBAS, 27, C_NAME_LIT if done else C_NAME_UNLIT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(name_lbl)

	inner.add_child(_spacer_v(12))

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
		bmc.add_child(_lbl("Secured · turn %d" % int(t.get("at", 0)), _UIFonts.PLEX_SEMI, 14, Color("#241a08")))
	else:
		var border := Color("#3a2224") if result == "defeat" else Color("#1c3149")
		badge.add_theme_stylebox_override("panel", _sb(C_TRACK_BG, border, 1, 8, 0))
		# Points, not a percentage: every track is worth 1,000 and the score bar above is
		# read in points, so the pennants should be too.
		bmc.add_child(_lbl("%s / 1,000 points" % _num(int(round(float(t.get("pct", 0.0)) * 1000.0))),
			_UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	inner.add_child(badge)
	return card


## What the card no longer says out loud: the track's rule, where the run got to, and what
## that was measured against.
func _track_tooltip(t: Dictionary) -> String:
	var lines: Array[String] = [str(t.get("name", "")).to_upper()]
	var desc := str(t.get("desc", ""))
	if desc != "":
		lines.append(desc)
	var stat := str(t.get("stat", ""))
	var sub := str(t.get("sub", ""))
	if stat != "" and sub != "":
		lines.append("%s — %s" % [stat, sub])
	elif stat != "":
		lines.append(stat)
	elif sub != "":
		lines.append(sub)
	if bool(t.get("done", false)):
		lines.append("Secured on turn %d." % int(t.get("at", 0)))
	return "
".join(lines)


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
	# The verdict is the one piece of writing on the screen; at 15 it sat below the chart
	# captions in weight and got skipped (owner 2026-08-24).
	var l := _lbl(text, _UIFonts.PLEX_MED, 24, C_COPY)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_constant_override("line_spacing", 12)
	return l


func _dropcap_para(text: String) -> Control:
	# Large ACCENT drop-cap of the first letter, then the rest flows beside/under it.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var cap := _lbl(text.substr(0, 1), _BEBAS, 64, _accent)
	cap.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cap.custom_minimum_size = Vector2(44, 0)
	row.add_child(cap)
	var rest := _lbl(text.substr(1), _UIFonts.PLEX_MED, 24, C_COPY)
	rest.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rest.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rest.add_theme_constant_override("line_spacing", 12)
	row.add_child(rest)
	return row


func _stat_card(value: String, label: String) -> Control:
	var pc := _CutPlate.new(16, 14, _CutPlate.STEEL)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mc := MarginContainer.new()
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	mc.add_child(v)
	v.add_child(_lbl(value, _UIFonts.mono(), 26, C_STAT_VALUE))
	v.add_child(_lbl(label.to_upper(), _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	return pc


# ── Section 3b: THE COMPANY — the run's own artefacts, in the game's own art ──
# Owner 2026-08-24: use the assets the game already has — good icons on the Goods Graph's
# cream chips, building icons, advisor portraits — and pack them four to a row.
func _build_company(data: Dictionary) -> Control:
	var co: Dictionary = data.get("company", {})
	var sec := _section(32, SEC_PAD_H, 36)
	var box: VBoxContainer = sec.get_child(0)
	box.add_child(_section_head("The company"))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	row.add_child(_good_showcase("Most produced", co.get("top_produced", {})))
	row.add_child(_good_showcase("Most sold", co.get("top_sold", {})))
	row.add_child(_workhorse_showcase(co.get("workhorse", {})))
	row.add_child(_advisor_showcase(co.get("advisor", {})))

	box.add_child(_chain_row(co.get("chain", {})))
	return sec


## One showcase plate: small-caps caption, an icon from the game's own art, the figure.
func _showcase_plate(caption: String, icon: Control, value: String, sub: String,
		mono: bool = true) -> Control:
	var plate := _CutPlate.new(16, 12, _CutPlate.COPPER)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	plate.add_child(v)
	v.add_child(_lbl(caption.to_upper(), _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	if icon != null:
		row.add_child(icon)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	row.add_child(col)
	var val_font: Font = _UIFonts.mono() if mono else _UIFonts.PLEX_SEMI
	var val := _lbl(value, val_font, 20, C_STAT_VALUE)
	val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(val)
	var s2 := _lbl(sub, _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
	s2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(s2)
	return plate


func _good_showcase(caption: String, d: Dictionary) -> Control:
	var gid := str(d.get("gid", ""))
	if gid == "":
		return _showcase_plate(caption, null, "—", "nothing this run")
	var icon := _UIHelpers.make_plain_good_icon(gid, Catalog.get_internal_name(gid), 72)
	return _showcase_plate(caption, icon, str(d.get("qty_text", "")),
		Catalog.get_display_name(gid))


func _workhorse_showcase(d: Dictionary) -> Control:
	if d.is_empty():
		return _showcase_plate("Most value created", null, "—", "nothing ran this game")
	var icon: Control = null
	var tex: Texture2D = d.get("icon")
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.custom_minimum_size = Vector2(72, 72)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon = tr
	return _showcase_plate("Most value created", icon, str(d.get("value", "—")),
		str(d.get("sub", "")))


func _advisor_showcase(d: Dictionary) -> Control:
	if d.is_empty():
		return _showcase_plate("Longest-serving advisor", null, "—", "no council seated")
	var icon: Control = null
	var path := str(d.get("portrait", ""))
	if path != "" and ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.custom_minimum_size = Vector2(72, 72)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.clip_contents = true
		icon = tr
	return _showcase_plate("Longest-serving advisor", icon, str(d.get("name", "")),
		"seated since Year %d" % int(d.get("since_year", 1)), false)


## The supply chain the run actually established, drawn as the GOODS GRAPH'S FOCUSED VIEW
## (owner 2026-08-24): the goods this company made, in the flow chart's own columns, wired
## to each other by the real recipe links — not a row of five tier slots with one good in
## each. What the shape shows is how deep and how wide the business actually went.
func _chain_row(chain: Dictionary) -> Control:
	var plate := _CutPlate.new(20, 14, _CutPlate.BRASS)
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	plate.add_child(v)
	v.add_child(_lbl("SUPPLY CHAIN — REACHED %d OF %d TIERS" % [int(chain.get("bands", 0)),
		int(chain.get("band_total", 5))], _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	var nodes: Array = chain.get("nodes", [])
	if nodes.is_empty():
		v.add_child(_lbl("Nothing was ever produced.", _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
		return plate
	var web := _ChainWeb.new()
	web.nodes = nodes
	web.edges = chain.get("edges", [])
	web.font = _UIFonts.PLEX_MED
	web.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Tall enough for the busiest column, so nothing is squeezed off the plate.
	var per_col: Dictionary = {}
	var deep := 1
	for n_variant: Variant in nodes:
		var t := int((n_variant as Dictionary).get("tier", 0))
		per_col[t] = int(per_col.get(t, 0)) + 1
		deep = maxi(deep, int(per_col[t]))
	web.custom_minimum_size = Vector2(0, float(deep) * _ChainWeb.ROW + 16.0)
	v.add_child(web)
	return plate


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
	rev.board = C_REV
	grid.add_child(_chart_card("Revenue per turn", str(charts.get("revenue_big", "")),
		str(charts.get("revenue_sub", "")), C_REV, rev,
		"turn 1 … turn %d" % int(data.get("turn", 0)), _CutPlate.BRASS))

	# Output — bar chart.
	var outp := _BarChart.new()
	outp.series = charts.get("output", [])
	outp.col = C_OUT
	grid.add_child(_chart_card("Output per turn", str(charts.get("output_big", "")),
		str(charts.get("output_sub", "")), C_OUT, outp, "sampled across the game",
		_CutPlate.STEEL))

	# Buildings — a stack of the estate's own emblem, one sprite per STEP buildings.
	var bld := _StackChart.new()
	bld.series = charts.get("buildings", [])
	bld.col = C_BLD
	bld.icon = charts.get("buildings_icon")
	var bpeak := 0
	for v in bld.series:
		bpeak = maxi(bpeak, int(v))
	bld.step = maxi(1, int(ceil(float(bpeak) / 4.0)))
	bld.font = _UIFonts.mono()
	var bfoot := "turn 1 … turn %d" % int(data.get("turn", 0))
	grid.add_child(_chart_card("Buildings owned", str(charts.get("buildings_big", "")),
		str(charts.get("buildings_sub", "")), C_BLD, bld, bfoot, _CutPlate.COPPER, 176))

	# Biggest outputs — five ranked bar rows.
	grid.add_child(_build_biggest(charts))

	# The empire used to run the full width with most of the plate empty around a
	# stamp-sized network (owner 2026-08-24). It is half now, and the other half is the
	# league: where the company stood, and what it led — a quarter of the row each.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	box.add_child(bottom)
	var emp := _build_empire(data.get("empire", {}))
	emp.size_flags_stretch_ratio = 2.0
	bottom.add_child(emp)
	var league: Dictionary = data.get("league", {})
	var place := _build_place(league)
	place.size_flags_stretch_ratio = 1.0
	bottom.add_child(place)
	var led := _build_led(league)
	led.size_flags_stretch_ratio = 1.0
	bottom.add_child(led)
	return sec


## Where the company stood in the revenue table, turn by turn. Rank 1 is the TOP of the
## chart, so the line rising means the company climbing — an axis that ran 1 at the bottom
## read exactly backwards.
func _build_place(league: Dictionary) -> Control:
	var pc := _CutPlate.new(20, 16, _CutPlate.STEEL)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var companies := int(league.get("companies", 10))
	var final_rank := int(league.get("final_rank", companies))
	v.add_child(_card_head("Place in the league", _ordinal(final_rank),
		"of %d companies, at the close" % companies, C_OUT))
	var chart := _RankChart.new()
	chart.series = league.get("ranks", [])
	chart.companies = companies
	chart.font = _UIFonts.mono()
	chart.custom_minimum_size = Vector2(0, 236)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(chart)
	var foot := "best: %s" % _ordinal(int(league.get("best_rank", final_rank)))
	var crowned := int(league.get("crowned_turns", 0))
	if crowned > 0:
		foot += "  ·  %d turn%s on top" % [crowned, "" if crowned == 1 else "s"]
	v.add_child(_lbl(foot, _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	return pc


## The goods the company finished first in, on the Goods Graph's cream chips.
func _build_led(league: Dictionary) -> Control:
	var pc := _CutPlate.new(20, 16, _CutPlate.BRASS)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	pc.add_child(v)
	var led: Array = league.get("led", [])
	var contested := int(league.get("contested", 0))
	v.add_child(_card_head("Goods you led", str(led.size()),
		"of %d you competed in" % contested, C_ACCENT_WIN))
	var wrap := HFlowContainer.new()
	wrap.add_theme_constant_override("h_separation", 10)
	wrap.add_theme_constant_override("v_separation", 10)
	wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(wrap)
	if led.is_empty():
		wrap.add_child(_lbl("No good finished first this game.", _UIFonts.PLEX_MED, 14,
			DS.PALETTE.TEXT_MUTED))
	for i in mini(10, led.size()):
		var g: Dictionary = led[i]
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 3)
		cell.add_child(_UIHelpers.make_plain_good_icon(str(g.get("gid", "")),
			str(g.get("internal", "")), 50))
		var nm := _lbl(str(g.get("name", "")), _UIFonts.PLEX_MED, 14, C_STAT_VALUE)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.custom_minimum_size = Vector2(78, 0)
		nm.clip_text = true
		nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		cell.add_child(nm)
		wrap.add_child(cell)
	if led.size() > 10:
		wrap.add_child(_lbl("+%d more" % (led.size() - 10), _UIFonts.PLEX_SEMI, 14, C_OUT))
	var runner := "second in %d  ·  third in %d" % [int(league.get("seconds", 0)),
		int(league.get("thirds", 0))]
	v.add_child(_lbl(runner, _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	return pc


## The chart cards' header row: small-caps label left, the figure and its gloss right.
func _card_head(label: String, big: String, sub: String, col: Color) -> Control:
	var head := HBoxContainer.new()
	var lbl := _lbl(label.to_upper(), _UIFonts.PLEX_MED, 14, C_CHART_LABEL)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lbl)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 2)
	head.add_child(rcol)
	var big_lbl := _lbl(big, _UIFonts.mono(), 20, col)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(big_lbl)
	var sub_lbl := _lbl(sub, _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(sub_lbl)
	return head


func _ordinal(n: int) -> String:
	if n <= 0:
		return "—"
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		match n % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return str(n) + suffix


func _chart_card(label: String, big: String, sub: String, col: Color, body: Control,
		footer: String, metal: int = 2, body_h: int = 150) -> Control:
	var pc := _CutPlate.new(20, 16, metal)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mc := MarginContainer.new()
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)

	# Header row: label (left) + big number & sub (right).
	var head := HBoxContainer.new()
	v.add_child(head)
	var lbl := _lbl(label.to_upper(), _UIFonts.PLEX_MED, 14, C_CHART_LABEL)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lbl)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 2)
	head.add_child(rcol)
	var big_lbl := _lbl(big, _UIFonts.mono(), 20, col)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(big_lbl)
	var sub_lbl := _lbl(sub, _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(sub_lbl)

	body.custom_minimum_size = Vector2(0, body_h)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(body)

	if footer != "":
		v.add_child(_lbl(footer, _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED))
	return pc


func _build_biggest(charts: Dictionary) -> Control:
	var pc := _CutPlate.new(20, 16, _CutPlate.STEEL)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mc := MarginContainer.new()
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	mc.add_child(v)

	var head := HBoxContainer.new()
	v.add_child(head)
	var lbl := _lbl("BIGGEST OUTPUTS", _UIFonts.PLEX_MED, 14, C_CHART_LABEL)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(lbl)
	var rcol := VBoxContainer.new()
	rcol.add_theme_constant_override("separation", 2)
	head.add_child(rcol)
	var big_lbl := _lbl(_num(int(charts.get("top_total", 0))), _UIFonts.mono(), 20, C_BIG)
	big_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rcol.add_child(big_lbl)
	var sub_lbl := _lbl("lifetime units, top five goods", _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
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
	row.add_theme_constant_override("separation", 12)
	row.custom_minimum_size = Vector2(0, 54)

	# The Goods Graph's plain chip — cream ground, rounded corners, no metal frame, at the
	# size the rest of the game shows a good (owner 2026-08-24: these were 26px and tiny).
	var icon: Control = _UIHelpers.make_plain_good_icon(str(g.get("good_id", "")),
		str(g.get("internal", "")), 50)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(icon)

	var name_lbl := _lbl(str(g.get("label", "")), _UIFonts.PLEX_MED, 14, C_STAT_VALUE)
	name_lbl.custom_minimum_size = Vector2(126, 0)
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
	bar.custom_minimum_size = Vector2(0, 22)
	row.add_child(bar)

	var num := _lbl(_num(int(g.get("units", 0))), _UIFonts.mono(), 14, C_OUT if rank == 0 else C_STAT_VALUE)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	num.custom_minimum_size = Vector2(80, 0)
	num.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(num)
	return row


func _build_empire(empire: Dictionary) -> Control:
	var pc := _CutPlate.new(20, 16, _CutPlate.COPPER)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mc := MarginContainer.new()
	pc.add_child(mc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	mc.add_child(v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	v.add_child(head)
	head.add_child(_lbl("THE EMPIRE", _UIFonts.PLEX_MED, 14, C_CHART_LABEL))
	var ports: Array = empire.get("ports", [])
	var meta := _lbl("final production network · %d ports" % ports.size(), _UIFonts.PLEX_MED, 14, DS.PALETTE.TEXT_MUTED)
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
		graph.custom_minimum_size = Vector2(0, 300)
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
	if (_EmpireGraph.build(terrain).get("nodes", []) as Array).is_empty():
		return null
	var world: Control = _GraphWorld.new()
	world.clip_contents = true
	world.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	# set_graph fits the view to the control's size, which is 0 until layout runs — apply it
	# once the graph has a real rect (first resize with width; applied once).
	var applied := [false]
	world.resized.connect(func() -> void:
		if applied[0] or world.size.x <= 1.0:
			return
		applied[0] = true
		# The SAME setup the empire view uses (EmpireGraph.populate). This used to solve the
		# layout with two arguments instead of four and pass an empty port list beside a full
		# buy-port list, which is why it read as an older sibling with a stray bottom row.
		# `trading: false` still drops the sell row — the company has stopped selling — but the
		# columns are now solved exactly as they are in the live view.
		_EmpireGraph.populate(world, get_tree().get_first_node_in_group("hex_map"), false)
		if interactive:
			return
		# Static inline copy only: the expand overlay IS meant to be clicked, and blanking the
		# node panels here was why clicking a building in the end screen did nothing.
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

	# (The 120px hairline that used to sit here went with the section rules — owner
	# 2026-08-24, "stop using the fading line". The button carries the section on its own.)

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

	var cap := _lbl("Your ledger has been archived to the Hall of Records.", _UIFonts.PLEX_MED, 14, C_FOOT_CAP)
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
	var h := _lbl("THE EMPIRE — FINAL PRODUCTION NETWORK", _tracked_font(), 14, C_ACCENT_WIN)
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
	# No trailing rule (owner 2026-08-24: "stop using the fading line"). The heading stands
	# on its own; the plates below it already say where the section starts.
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
## The game's skeuomorphic plate, replacing the mock's thin-lined rounded cards: a
## cut-corner (octagonal) navy slab with machined relief — brass rim, light catching the
## inner top edges, shadow pooling below — the same material language as the research
## stamps and the menus' brass chrome (owner 2026-08-24).
class _CutPlate extends PanelContainer:
	# Three metals, so a screenful of plates is not a screenful of gold (owner 2026-08-24:
	# "some coppery, others silver-steel, only 1-2 gold-brass"). Each is [under, body,
	# glint] — the rim is struck three times, dark first, to read as a turned edge.
	const BRASS := 0
	const COPPER := 1
	const STEEL := 2
	const _RIMS := {
		0: [Color(0.518, 0.408, 0.204), Color(0.808, 0.667, 0.396), Color(0.965, 0.886, 0.659)],
		1: [Color(0.392, 0.192, 0.110), Color(0.776, 0.451, 0.278), Color(0.949, 0.706, 0.529)],
		2: [Color(0.259, 0.318, 0.392), Color(0.616, 0.686, 0.769), Color(0.898, 0.933, 0.976)],
	}
	const GOLD_HI := Color(0.965, 0.886, 0.659)
	const GOLD_LO := Color(0.518, 0.408, 0.204)
	var cut := 14.0
	var fill := Color("#0A1826")
	var tone := BRASS
	var rim_alpha := 0.85
	var accent := Color(0, 0, 0, 0)      # optional inner top line (track colour)
	var dimmed := false                  # unlit plates: duller rim, deeper fill

	func _init(margin_h: int = 16, margin_v: int = 14, metal: int = BRASS) -> void:
		tone = metal
		var sb := StyleBoxEmpty.new()
		sb.content_margin_left = margin_h
		sb.content_margin_right = margin_h
		sb.content_margin_top = margin_v
		sb.content_margin_bottom = margin_v
		add_theme_stylebox_override("panel", sb)
		resized.connect(queue_redraw)

	func _pts(r: Rect2, c: float) -> PackedVector2Array:
		return PackedVector2Array([
			Vector2(r.position.x + c, r.position.y), Vector2(r.end.x - c, r.position.y),
			Vector2(r.end.x, r.position.y + c), Vector2(r.end.x, r.end.y - c),
			Vector2(r.end.x - c, r.end.y), Vector2(r.position.x + c, r.end.y),
			Vector2(r.position.x, r.end.y - c), Vector2(r.position.x, r.position.y + c)])

	func _draw() -> void:
		if size.x < 8.0 or size.y < 8.0:
			return
		var r := Rect2(Vector2(1.5, 1.5), size - Vector2(3, 3))
		var c := minf(cut, minf(size.x, size.y) * 0.28)
		var outer := _pts(r, c)
		draw_colored_polygon(outer, fill.darkened(0.35) if dimmed else fill)
		# Machined relief: light along the inner top run, shadow along the bottom.
		var inner := _pts(r.grow(-2.5), maxf(2.0, c - 2.0))
		draw_polyline(PackedVector2Array([inner[7], inner[0], inner[1], inner[2]]),
			Color(1, 1, 1, 0.05 if dimmed else 0.11), 1.4, true)
		draw_polyline(PackedVector2Array([inner[3], inner[4], inner[5], inner[6]]),
			Color(0, 0, 0, 0.45), 1.6, true)
		# The embossed groove a step further in.
		var groove := _pts(r.grow(-5.0), maxf(2.0, c - 4.0))
		groove.append(groove[0])
		draw_polyline(groove, Color(0, 0, 0, 0.28), 1.0, true)
		# The rim on the boundary: dark under-stroke, mid body, glint on the top run.
		var metal: Array = _RIMS[tone]
		var a := rim_alpha * (0.45 if dimmed else 1.0)
		var loop := PackedVector2Array(outer)
		loop.append(outer[0])
		draw_polyline(loop, Color(metal[0], a), 3.0, true)
		draw_polyline(loop, Color(metal[1], a), 1.6, true)
		draw_polyline(PackedVector2Array([outer[7], outer[0], outer[1], outer[2]]),
			Color(metal[2], 0.22 if dimmed else 0.7), 1.2, true)
		if accent.a > 0.0:
			draw_line(Vector2(r.position.x + c + 2.0, r.position.y + 4.0),
				Vector2(r.end.x - c - 2.0, r.position.y + 4.0), accent, 3.0, true)


## The company's place in the revenue table over the match: rank 1 at the TOP, one lane per
## company, the top lane banded gold. The line is the same embossed brass trace the revenue
## board uses, stepped — a rank is a whole number that holds until it changes, and drawing
## it as a smooth curve would claim positions the company never held.
class _RankChart extends Control:
	const GOLD_HI := Color(0.965, 0.886, 0.659)
	const GOLD_MID := Color(0.808, 0.667, 0.396)
	const GOLD_LO := Color(0.518, 0.408, 0.204)
	const GUTTER := 30.0
	var series: Array = []
	var companies: int = 10
	var font: Font = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w := size.x - GUTTER
		var h := size.y
		if w < 20.0 or h < 20.0:
			return
		var lanes := maxi(2, companies)
		var lane := h / float(lanes)
		# The lanes, and the gold band the leader occupies.
		draw_rect(Rect2(GUTTER, 0.0, w, lane), Color(GOLD_MID, 0.10))
		for i in range(1, lanes):
			var y := lane * float(i)
			draw_line(Vector2(GUTTER, y), Vector2(GUTTER + w, y), Color(1, 1, 1, 0.05), 1.0)
		if font != null:
			for r in [1, lanes / 2, lanes]:
				var y := lane * (float(r) - 0.5)
				var lab := str(r)
				var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				font.draw_string(get_canvas_item(), Vector2(GUTTER - 7.0 - lw, y + 5.0), lab,
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(GOLD_HI, 0.95) if r == 1 else Color(0.761, 0.824, 0.898, 0.9))
		if series.size() < 2:
			return
		var n := series.size()
		var pts := PackedVector2Array()
		for i in n:
			var x := GUTTER + w * float(i) / float(n - 1)
			var y := lane * (clampf(float(series[i]), 1.0, float(lanes)) - 0.5)
			if i > 0:
				pts.append(Vector2(x, pts[pts.size() - 1].y))
			pts.append(Vector2(x, y))
		var under := PackedVector2Array()
		for pt in pts:
			under.append(pt + Vector2(0, 1.6))
		draw_polyline(under, Color(0, 0, 0, 0.5), 3.4, true)
		draw_polyline(pts, GOLD_MID, 2.4, true)
		var glint := PackedVector2Array()
		for pt in pts:
			glint.append(pt + Vector2(0, -1.0))
		draw_polyline(glint, Color(GOLD_HI, 0.4), 1.0, true)
		# A solder pad wherever the position actually changed, and at the close.
		for i in n:
			if i > 0 and int(series[i]) == int(series[i - 1]) and i != n - 1:
				continue
			var p := Vector2(GUTTER + w * float(i) / float(n - 1),
				lane * (clampf(float(series[i]), 1.0, float(lanes)) - 0.5))
			draw_circle(p, 4.4, GOLD_LO)
			draw_circle(p, 3.2, GOLD_MID)
			draw_circle(p + Vector2(-1.0, -1.0), 1.1, Color(GOLD_HI, 0.85))


## The player's own corner of the Goods Graph: cream chips in the flow chart's tier
## columns, wired by the real recipe links in the graph's own route colours. Everything is
## drawn rather than laid out with containers, exactly as the Goods Graph draws its cards —
## the edges need to know where the chips landed, and a container cannot tell them.
class _ChainWeb extends Control:
	const GoodIcons := preload("res://scripts/good_icons.gd")
	const ROUTE_COLORS := [Color("#f2c14e"), Color("#6f9fd8"), Color("#7ec98a"), Color("#b48ad9")]
	const CREAM := Color(0.995234, 0.930806, 0.763265)
	const CHIP := 58.0
	const ROW := 96.0
	var nodes: Array = []
	var edges: Array = []
	var font: Font = null

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		if nodes.is_empty() or size.x < 40.0:
			return
		# Columns: the graph's own tier depths, squeezed to consecutive slots so a run that
		# skipped a tier does not leave a gap the width of a column.
		var tiers: Array = []
		for n_variant: Variant in nodes:
			var t := int((n_variant as Dictionary).get("tier", 0))
			if not tiers.has(t):
				tiers.append(t)
		tiers.sort()
		var col_of: Dictionary = {}
		for i in tiers.size():
			col_of[tiers[i]] = i
		var by_col: Dictionary = {}
		for n_variant: Variant in nodes:
			var n: Dictionary = n_variant
			var c := int(col_of[int(n.get("tier", 0))])
			if not by_col.has(c):
				by_col[c] = []
			(by_col[c] as Array).append(n)
		# Columns are capped and the block centred: spreading five goods across a
		# 1,800px plate put a chip alone in the middle of each of five empty rooms.
		var cw := minf(size.x / float(maxi(1, tiers.size())), 235.0)
		var x0 := (size.x - cw * float(tiers.size())) * 0.5
		var centre: Dictionary = {}      # id -> chip centre
		for c in by_col:
			var col: Array = by_col[c]
			col.sort_custom(_bigger_first)
			var total := float(col.size()) * ROW
			var y := (size.y - total) * 0.5 + ROW * 0.5
			for n_variant: Variant in col:
				var n: Dictionary = n_variant
				centre[str(n.get("id", ""))] = Vector2(x0 + cw * (float(c) + 0.5), y)
				y += ROW
		# Wires first, so the chips sit on top of them.
		for e_variant: Variant in edges:
			var e: Dictionary = e_variant
			var a = centre.get(str(e.get("from", "")))
			var b = centre.get(str(e.get("to", "")))
			if a == null or b == null:
				continue
			_wire(a, b, ROUTE_COLORS[clampi(int(e.get("route", 0)), 0, ROUTE_COLORS.size() - 1)])
		for n_variant: Variant in nodes:
			var n: Dictionary = n_variant
			var c2 = centre.get(str(n.get("id", "")))
			if c2 != null:
				_chip(n, c2)

	## Busiest good at the top of its column. (A named method, not an inline lambda: a
	## lambda body that wraps onto a second line inside a call argument does not parse.)
	func _bigger_first(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("units", 0)) > int((b as Dictionary).get("units", 0))

	## One orthogonal run between two chips, filleted at the corners and tipped with an
	## arrowhead. A link that runs backwards (a good feeding something in an earlier column)
	## dips under its own row rather than cutting straight through the chips between.
	func _wire(a: Vector2, b: Vector2, col: Color) -> void:
		var from := a + Vector2(CHIP * 0.5 + 3.0, 0)
		var to := b - Vector2(CHIP * 0.5 + 9.0, 0)
		var route := PackedVector2Array()
		if to.x > from.x + 12.0:
			var mid := (from.x + to.x) * 0.5
			route = PackedVector2Array([from, Vector2(mid, from.y), Vector2(mid, to.y), to])
		else:
			var dip := maxf(a.y, b.y) + ROW * 0.40
			to = b + Vector2(0, CHIP * 0.5 + 6.0)
			route = PackedVector2Array([from, Vector2(from.x + 14.0, from.y),
				Vector2(from.x + 14.0, dip), Vector2(to.x, dip), to])
		var pts := _fillet(route, 9.0)
		draw_polyline(pts, Color(0, 0, 0, 0.45), 4.2, true)
		draw_polyline(pts, Color(col, 0.85), 2.4, true)
		var tip: Vector2 = pts[pts.size() - 1]
		var dir: Vector2 = (tip - pts[pts.size() - 2]).normalized()
		var nrm := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9.0 + nrm * 5.4,
			tip - dir * 9.0 - nrm * 5.4]), Color(col, 0.9))

	func _fillet(route: PackedVector2Array, r: float) -> PackedVector2Array:
		if route.size() < 3:
			return route
		var out := PackedVector2Array([route[0]])
		for i in range(1, route.size() - 1):
			var prev: Vector2 = route[i - 1]
			var cur: Vector2 = route[i]
			var nxt: Vector2 = route[i + 1]
			var rad: float = minf(r, minf(cur.distance_to(prev), cur.distance_to(nxt)) * 0.45)
			var p0 := cur + (prev - cur).normalized() * rad
			var p1 := cur + (nxt - cur).normalized() * rad
			for k in 5:
				var t := float(k) / 4.0
				out.append(p0.lerp(cur, t).lerp(cur.lerp(p1, t), t))
		out.append(route[route.size() - 1])
		return out

	## The Goods Graph's chip: the good's icon on cream, with a rim in its category accent
	## and the name underneath.
	func _chip(n: Dictionary, c: Vector2) -> void:
		var r := Rect2(c - Vector2(CHIP, CHIP) * 0.5, Vector2(CHIP, CHIP))
		var accent := Color(str(n.get("accent", "b9c4d2")))
		draw_rect(Rect2(r.position + Vector2(1.5, 2.5), r.size), Color(0, 0, 0, 0.40), true)
		DrawUtil.round_rect(self, r, 11.0, CREAM)
		var tex: Texture2D = GoodIcons.texture_for_size(str(n.get("gid", "")),
			str(n.get("id", "")), CHIP)
		if tex != null:
			draw_texture_rect(tex, r.grow(-5.0), false)
		var rim := PackedVector2Array([r.position + Vector2(11.0, 0), Vector2(r.end.x - 11.0, r.position.y),
			Vector2(r.end.x, r.position.y + 11.0), Vector2(r.end.x, r.end.y - 11.0),
			Vector2(r.end.x - 11.0, r.end.y), Vector2(r.position.x + 11.0, r.end.y),
			Vector2(r.position.x, r.end.y - 11.0), Vector2(r.position.x, r.position.y + 11.0),
			r.position + Vector2(11.0, 0)])
		draw_polyline(rim, Color(accent, 0.9), 2.0, true)
		if font == null:
			return
		var name := str(n.get("display", ""))
		var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		font.draw_string(get_canvas_item(), Vector2(c.x - tw * 0.5, r.end.y + 17.0),
			name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("#E8EEF7"))


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


## The track crest, struck as the RESEARCH PANEL'S TIER STAMP (owner 2026-08-24: "use the
## rounded hex corner style hexes... reuse the same metallic raised effect"): a rounded-corner
## hexagon with a dropped shadow, a diagonal gradient face inside a lighter outline shell, and
## per-edge lighting from the top-left. Geometry and metal are HexStamp's, shared with the
## panel itself. A secured track is struck in gold; an unsecured one in cold navy.
class _Crest extends Control:
	# Owner-supplied track icons (white silhouettes, tinted at draw time).
	const _ICONS := {
		"autarkic": preload("res://assets/icons/victory/autarkic.png"),
		"logistics": preload("res://assets/icons/victory/logistics.png"),
		"richest": preload("res://assets/icons/victory/richest.png"),
		"widest": preload("res://assets/icons/victory/widest.png"),
		"greenest": preload("res://assets/icons/victory/greenest.png"),
	}
	const _HexStamp := preload("res://scripts/hex_stamp.gd")
	## The demo runs five tracks of its own, and the crests came up BLANK because the icon
	## set is keyed by the campaign's names. Each demo track borrows the campaign crest that
	## means the same thing: top of the rankings is the richest firm, producing at every
	## tier is self-supply, long hauls are logistics, and an estate is reach.
	const _DEMO_GLYPH := {
		"crown": "richest", "tiers": "autarkic", "distance": "logistics",
		"green_demo": "greenest", "estate": "widest",
	}
	var done: bool = false
	var color: Color = Color.WHITE
	var glyph: String = ""
	func _draw() -> void:
		var side := minf(size.x, size.y) - 6.0
		if side < 12.0:
			return
		# The stamp is wider than tall, as it is in the tree — the hex points sideways.
		var rw := side * 1.14
		var rect := Rect2(size.x * 0.5 - rw * 0.5, size.y * 0.5 - side * 0.5, rw, side)
		var fill := Color("#C9A75C") if done else Color("#0B1725")
		var out_lt := Color(0.86, 0.80, 0.62, 0.90) if done else Color(0.40, 0.46, 0.54, 0.65)
		var out_dk := Color(0.42, 0.34, 0.16, 0.85) if done else Color(0.16, 0.21, 0.27, 0.70)
		var inner := _HexStamp.draw_stamp(self, rect, fill, out_lt, out_dk,
			maxf(3.0, side * 0.08), maxf(4.0, side * 0.16))
		var tex: Texture2D = _ICONS.get(str(_DEMO_GLYPH.get(glyph, glyph)))
		if tex == null:
			return
		var gs := inner.size.y * 0.82
		var tint := Color("#141d29") if done else Color(color, 0.55)
		draw_texture_rect(tex, Rect2(inner.get_center() - Vector2(gs, gs) * 0.5,
			Vector2(gs, gs)), false, tint)


## Revenue as a CIRCUIT BOARD (owner 2026-08-24): the area under the line is the green
## board, the line itself the gold edge trace, and the board is laid out with gold runs
## between solder pads across its whole surface. Runs are laid on a lattice and kept only
## where BOTH pads sit under the curve, so the etching fills the shape exactly and stops
## at the line. The pattern is hashed off the lattice cell, never a RNG -- _draw re-runs
## on every redraw, and a board that re-etched itself each frame would crawl.
class _LineChart extends Control:
	const GOLD_HI := Color(0.965, 0.886, 0.659)
	const GOLD_MID := Color(0.808, 0.667, 0.396)
	const GOLD_LO := Color(0.518, 0.408, 0.204)
	const PITCH := 22.0
	var series: Array = []
	var col: Color = Color.WHITE
	var board: Color = Color(0.357, 0.820, 0.502)   # the board green (DS.OK)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if series.size() < 2:
			return
		var mx := 0.0
		for v in series:
			mx = maxf(mx, float(v))
		mx = maxf(mx, 1.0)
		var n := series.size()
		var pts := PackedVector2Array()
		for i in n:
			pts.append(Vector2(w * float(i) / float(n - 1),
				h - (float(series[i]) / mx) * (h - 6.0)))
		# The board: a green ground, darkening towards the foot.
		var fill := pts.duplicate()
		fill.append(Vector2(w, h))
		fill.append(Vector2(0, h))
		draw_polygon(fill, PackedColorArray([Color(board, 0.24)]))
		var deep := board.darkened(0.62)
		draw_polygon(PackedVector2Array([Vector2(0, h * 0.4), Vector2(w, h * 0.4),
			Vector2(w, h), Vector2(0, h)]), PackedColorArray([
			Color(deep, 0.0), Color(deep, 0.0), Color(deep, 0.34), Color(deep, 0.34)]))
		_etch(pts, w, h)
		# The gold edge trace: embossed, with a glint riding on top.
		var under := PackedVector2Array()
		for pt in pts:
			under.append(pt + Vector2(0, 1.6))
		draw_polyline(under, Color(0, 0, 0, 0.5), 3.0, true)
		draw_polyline(pts, GOLD_MID, 2.4, true)
		var glint := PackedVector2Array()
		for pt in pts:
			glint.append(pt + Vector2(0, -1.0))
		draw_polyline(glint, Color(GOLD_HI, 0.4), 1.0, true)
		for i in n:
			if i % 8 != 0 and i != n - 1:
				continue
			draw_circle(pts[i], 4.6, GOLD_LO)
			draw_circle(pts[i], 3.4, GOLD_MID)
			draw_circle(pts[i] + Vector2(-1.0, -1.0), 1.2, Color(GOLD_HI, 0.85))

	## The board itself: a CPU seated in the middle of the copper, and BUSES running to it —
	## bundles of parallel traces that go straight for a run, break to 45 degrees together,
	## and go straight again (owner 2026-08-24). Every trace in a bundle breaks one pitch
	## further along than the one beside it, which is what keeps the diagonals parallel and
	## the spacing even; it is also how a real board fans a bus into a pin row.
	##
	## Nothing is clipped by a mask: each run is walked in short steps and a step is drawn
	## only where the curve is above it, so the etching stops at the line by construction.
	func _etch(pts: PackedVector2Array, w: float, h: float) -> void:
		if w < 90.0 or h < 50.0:
			return
		# Seat the CPU where the board is deepest towards the right, where the area is tallest.
		var cx := w * 0.62
		var top := _curve_y(pts, cx, w)
		var room := h - top
		if room < 46.0:
			return
		var side: float = clampf(minf(room * 0.52, w * 0.17), 34.0, 96.0)
		var cy: float = clampf(top + room * 0.52, top + side * 0.5 + 10.0, h - side * 0.5 - 8.0)
		var chip := Rect2(cx - side * 0.5, cy - side * 0.5, side, side)
		var pitch: float = maxf(6.0, side / 7.0)
		# Three buses into the chip: from the left edge, out to the right edge, and down to
		# the board's foot. Each fans from a straight run through one 45-degree break.
		var lanes := maxi(3, int(side / pitch) - 1)
		var y_pin := chip.position.y + pitch * 1.2
		_bus(pts, w, h, Vector2(2.0, top + room * 0.24), Vector2(chip.position.x - 2.0, y_pin),
			lanes, pitch, 1.0)
		_bus(pts, w, h, Vector2(chip.end.x + 2.0, y_pin), Vector2(w - 2.0, top + room * 0.16),
			lanes, pitch, 1.0)
		_bus(pts, w, h, Vector2(chip.position.x - 2.0, chip.end.y - pitch * 1.2),
			Vector2(2.0, h - 6.0), lanes, pitch, -1.0)
		_chip(chip, pitch)

	## One bus: `lanes` parallel traces from `a` to `b`, straight-then-45-then-straight, each
	## lane offset by `pitch` along `spread` (down when +1, up when -1) so the bundle keeps
	## its spacing through the turn.
	func _bus(pts: PackedVector2Array, w: float, h: float, a: Vector2, b: Vector2,
			lanes: int, pitch: float, spread: float) -> void:
		var dx: float = b.x - a.x
		if absf(dx) < 24.0:
			return
		var sign_x: float = signf(dx)
		for i in lanes:
			var off := float(i) * pitch * spread
			var ya := a.y + off
			var yb := b.y + off
			var dy := yb - ya
			var diag: float = absf(dy)                       # 45 degrees: |dx| == |dy|
			var lead: float = absf(dx) * 0.30 + float(i) * pitch
			if lead + diag > absf(dx) - 6.0:
				lead = maxf(4.0, absf(dx) - diag - 6.0)
			var x1 := a.x + sign_x * lead
			var x2 := x1 + sign_x * diag
			var run := PackedVector2Array([a + Vector2(0, off), Vector2(x1, ya),
				Vector2(x2, yb), Vector2(b.x, yb)])
			_run(pts, w, h, run)

	## A trace, drawn only where the board actually is. Each leg is stepped and a step is
	## skipped when the curve above it has not risen past it yet; a pad is dropped at the
	## last point that survived, so a run that meets the edge ends on a pad like a real one.
	func _run(pts: PackedVector2Array, w: float, h: float, path: PackedVector2Array) -> void:
		var run_col := Color(GOLD_MID, 0.34)
		var last := Vector2.INF
		var first := Vector2.INF
		for seg in range(path.size() - 1):
			var p0: Vector2 = path[seg]
			var p1: Vector2 = path[seg + 1]
			var steps := maxi(2, int(p0.distance_to(p1) / 5.0))
			for k in steps:
				var q0 := p0.lerp(p1, float(k) / float(steps))
				var q1 := p0.lerp(p1, float(k + 1) / float(steps))
				if not (_inside(pts, w, h, q0) and _inside(pts, w, h, q1)):
					continue
				draw_line(q0, q1, run_col, 1.4, true)
				if first == Vector2.INF:
					first = q0
				last = q1
		for pad in [first, last]:
			if pad == Vector2.INF:
				continue
			draw_circle(pad, 3.0, Color(0, 0, 0, 0.30))
			draw_circle(pad, 2.4, Color(GOLD_MID, 0.46))
			draw_circle(pad, 1.0, Color(0.02, 0.08, 0.05, 0.85))

	func _inside(pts: PackedVector2Array, w: float, h: float, p: Vector2) -> bool:
		return p.x > 1.0 and p.x < w - 1.0 and p.y < h - 2.0 and p.y > _curve_y(pts, p.x, w) + 5.0

	## The processor: a dark package with a brass rim, a pin comb on all four sides, the die
	## showing through the lid, and the orientation dot every chip carries at pin 1.
	func _chip(r: Rect2, pitch: float) -> void:
		var pin := Color(GOLD_MID, 0.55)
		var n := maxi(3, int(r.size.y / pitch) - 1)
		for i in n:
			var t := (float(i) + 1.0) / float(n + 1)
			var y := r.position.y + r.size.y * t
			var x := r.position.x + r.size.x * t
			draw_line(Vector2(r.position.x - 6.0, y), Vector2(r.position.x, y), pin, 1.6, true)
			draw_line(Vector2(r.end.x, y), Vector2(r.end.x + 6.0, y), pin, 1.6, true)
			draw_line(Vector2(x, r.position.y - 6.0), Vector2(x, r.position.y), pin, 1.6, true)
			draw_line(Vector2(x, r.end.y), Vector2(x, r.end.y + 6.0), pin, 1.6, true)
		draw_rect(Rect2(r.position + Vector2(1.5, 2.5), r.size), Color(0, 0, 0, 0.45))
		draw_rect(r, Color(0.043, 0.075, 0.063, 0.96))
		var rim := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
			Vector2(r.position.x, r.end.y), r.position])
		draw_polyline(rim, Color(GOLD_LO, 0.9), 2.4, true)
		draw_polyline(rim, Color(GOLD_MID, 0.8), 1.2, true)
		draw_polyline(PackedVector2Array([Vector2(r.position.x, r.end.y), r.position,
			Vector2(r.end.x, r.position.y)]), Color(GOLD_HI, 0.45), 1.0, true)
		var die := r.grow(-r.size.x * 0.26)
		draw_rect(die, Color(0.114, 0.161, 0.137, 0.9))
		draw_polyline(PackedVector2Array([die.position, Vector2(die.end.x, die.position.y),
			die.end, Vector2(die.position.x, die.end.y), die.position]),
			Color(GOLD_MID, 0.35), 1.0, true)
		draw_circle(r.position + Vector2(r.size.x * 0.14, r.size.y * 0.14), 2.2,
			Color(GOLD_HI, 0.75))

	func _curve_y(pts: PackedVector2Array, x: float, w: float) -> float:
		var t := clampf(x / maxf(w, 1.0), 0.0, 1.0) * float(pts.size() - 1)
		var i := clampi(int(t), 0, pts.size() - 2)
		return lerpf(pts[i].y, pts[i + 1].y, t - float(i))


## Output as a rack of BEAKERS: flat-bottomed glass tubes with light-blue liquid to the
## turn's level, a meniscus glint on the surface and a brushed highlight up the wall. The
## biggest turn's beaker holds cream. The feet used to be drawn as half-circles, which
## read as bubbles under the liquid rather than as the bottom of a tube (owner
## 2026-08-24) — they are square now, with the corners eased by a short chamfer.
class _BarChart extends Control:
	const GLASS := Color(0.72, 0.78, 0.85, 0.45)
	const LIQUID := Color(0.45, 0.68, 0.92, 0.8)
	var series: Array = []
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		if series.is_empty():
			return
		var n := mini(24, series.size())
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
		var gap := 7.0
		var bw := (w - gap * float(n - 1)) / float(n)
		var foot := h - 1.0
		var chamfer := minf(3.0, bw * 0.2)
		for i in n:
			var x := float(i) * (bw + gap)
			var liquid := LIQUID if i != peak_i else Color(0.95, 0.9, 0.78, 0.9)
			var level := foot - (vals[i] / mx) * (h - 10.0)
			if level < foot:
				draw_rect(Rect2(Vector2(x + 1.5, level), Vector2(bw - 3.0, foot - level - chamfer)),
					liquid)
				# The eased corners of the tube's floor, so the liquid sits IN the glass.
				draw_colored_polygon(PackedVector2Array([
					Vector2(x + 1.5, foot - chamfer), Vector2(x + bw - 1.5, foot - chamfer),
					Vector2(x + bw - 1.5 - chamfer, foot - 0.5),
					Vector2(x + 1.5 + chamfer, foot - 0.5)]), liquid)
				draw_line(Vector2(x + 1.5, level), Vector2(x + bw - 1.5, level),
					Color(1, 1, 1, 0.35), 1.2, true)
			# Glass: two walls down to a flat floor, open at the top, chamfered at the corners.
			draw_line(Vector2(x, 3.0), Vector2(x, foot - chamfer), GLASS, 1.3, true)
			draw_line(Vector2(x + bw, 3.0), Vector2(x + bw, foot - chamfer), GLASS, 1.3, true)
			draw_polyline(PackedVector2Array([
				Vector2(x, foot - chamfer), Vector2(x + chamfer, foot),
				Vector2(x + bw - chamfer, foot), Vector2(x + bw, foot - chamfer)]),
				GLASS, 1.3, true)
			draw_line(Vector2(x + 2.5, foot - 3.0), Vector2(x + 2.5, 6.0),
				Color(1, 1, 1, 0.10), 1.0, true)


## Buildings standing, STACKED FROM THE ESTATE'S OWN EMBLEM (owner 2026-08-24: "a furnace
## or some other building the player built — stack that same icon over and over per bar").
## The unit is decided up front: one sprite is `step` buildings, chosen so the tallest
## column runs about five sprites, and the card's footer says so. A column 1.5 units high
## draws a whole sprite with half a sprite standing on it — and the half shown is the
## sprite's LOWER half, so the part that is cut off is its roof, not its footings.
class _StackChart extends Control:
	var series: Array = []
	var col: Color = Color.WHITE
	var icon: Texture2D = null
	var step: int = 1
	var font: Font = null
	const GUTTER := 36.0     # room for the left axis's figures
	func _draw() -> void:
		var w := size.x - GUTTER
		var h := size.y
		if series.is_empty() or w < 8.0:
			return
		var n := mini(12, series.size())
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
		var cw := w / float(n)
		var rows := maxf(1.0, mx / float(step))
		var sp: float = minf(cw - 3.0, (h - 4.0) / maxf(rows, 1.0))
		sp = maxf(sp, 8.0)
		# The left axis: one rule per sprite, each labelled with the count it stands for.
		# The sprite IS the unit, so the axis is the legend — no "one sprite = N buildings"
		# note under the chart (owner 2026-08-24: "just label the axes clearly").
		var shelf := h - sp
		var tick := 1
		while shelf > 0.0:
			draw_line(Vector2(GUTTER, shelf), Vector2(GUTTER + w, shelf), Color(1, 1, 1, 0.05), 1.0)
			if font != null:
				var lab := str(tick * step)
				var lw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				font.draw_string(get_canvas_item(), Vector2(GUTTER - 7.0 - lw, shelf + 5.0),
					lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.761, 0.824, 0.898, 0.92))
			shelf -= sp
			tick += 1
		var ts := Vector2(sp, sp) if icon == null else icon.get_size()
		for i in n:
			var units := vals[i] / float(step)
			var full := int(floor(units))
			var frac := units - float(full)
			var x := GUTTER + float(i) * cw + (cw - sp) * 0.5
			var tint := Color(1, 1, 1, 1) if i != peak_i else Color(1.12, 1.08, 0.94, 1)
			for k in full:
				var y := h - float(k + 1) * sp
				_stamp(Rect2(x, y, sp, sp), Rect2(Vector2.ZERO, ts), tint)
			if frac > 0.06:
				var ph := sp * frac
				var y2 := h - float(full) * sp - ph
				# Source region: the sprite's lower `frac`, so its base sits on the stack.
				_stamp(Rect2(x, y2, sp, ph),
					Rect2(0.0, ts.y * (1.0 - frac), ts.x, ts.y * frac), tint)
		# The ground the stacks stand on, and the axis they rise from.
		draw_line(Vector2(GUTTER, h - 0.5), Vector2(GUTTER + w, h - 0.5), Color(col, 0.5), 2.0)
		draw_line(Vector2(GUTTER - 0.5, 0.0), Vector2(GUTTER - 0.5, h), Color(col, 0.35), 1.5)

	## One sprite, with a dark offset copy behind it so it sits on the stack below.
	func _stamp(dst: Rect2, src: Rect2, tint: Color) -> void:
		if icon == null:
			var body := Color(col.r * 0.9, col.g * 0.9, col.b * 0.9, 0.95)
			draw_rect(Rect2(dst.position + Vector2(0, 1.5), dst.size), Color(0, 0, 0, 0.45))
			draw_rect(dst, body)
			draw_line(dst.position, dst.position + Vector2(dst.size.x, 0),
				Color(1, 1, 1, 0.22), 1.2)
			return
		draw_texture_rect_region(icon, Rect2(dst.position + Vector2(1.0, 1.6), dst.size),
			src, Color(0, 0, 0, 0.5))
		draw_texture_rect_region(icon, dst, src, tint)


# A single horizontal ranked bar (rank 0 gold + glow).
class _RankBar extends Control:
	## Brushed metal, the way the panels do it (owner 2026-08-24): a solid body under a
	## top-left light, a fine horizontal grain, a machined rim and a bevel just inside the
	## top edge. Square ends with a small corner radius -- the old pill's h/2 radius put a
	## circle on both ends of every bar.
	const RAD := 4.0
	var frac: float = 0.0
	var rank: int = 0
	var col: Color = Color.WHITE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		DrawUtil.round_rect(self, Rect2(Vector2.ZERO, Vector2(w, h)), RAD, Color("#08131F"))
		draw_polyline(_ring(Rect2(Vector2(0.5, 0.5), Vector2(w - 1.0, h - 1.0))),
			Color(1, 1, 1, 0.06), 1.0, true)
		var bw := maxf(h, frac * w)
		var body: Color = Color("#C9A75C") if rank == 0 else col
		DrawUtil.round_rect(self, Rect2(Vector2.ZERO, Vector2(bw, h)), RAD, body.darkened(0.32))
		# Light from the top-left, shade to the bottom-right -- on a 4-vertex quad, never a
		# per-vertex ramp around the rounded outline (that fans into artifacts in GL compat).
		var q := PackedVector2Array([Vector2(1.5, 1.5), Vector2(bw - 1.5, 1.5),
			Vector2(bw - 1.5, h - 1.5), Vector2(1.5, h - 1.5)])
		var lt := body.lightened(0.34)
		draw_polygon(q, PackedColorArray([Color(lt, 0.95), Color(lt, 0.45),
			Color(lt, 0.05), Color(lt, 0.45)]))
		draw_polygon(q, PackedColorArray([Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.10),
			Color(0, 0, 0, 0.34), Color(0, 0, 0, 0.10)]))
		# Brushed grain: fine horizontal streaks at a deterministic alpha.
		var y := 3.0
		var i := 0
		while y < h - 2.0:
			draw_line(Vector2(2.5, y), Vector2(bw - 2.5, y),
				Color(1, 1, 1, 0.025 + 0.022 * absf(sin(float(i) * 12.9898))), 1.0)
			y += 3.0
			i += 1
		# Machined rim, and the bevel just inside the top edge.
		draw_polyline(_ring(Rect2(Vector2(0.75, 0.75), Vector2(bw - 1.5, h - 1.5))),
			Color(body.lightened(0.55), 0.75), 1.4, true)
		draw_line(Vector2(RAD + 1.0, 2.2), Vector2(bw - RAD - 1.0, 2.2),
			Color(1, 1, 1, 0.28), 1.2, true)

	func _ring(r: Rect2) -> PackedVector2Array:
		var rad: float = minf(RAD, minf(r.size.x, r.size.y) * 0.5)
		var pts := PackedVector2Array()
		var centres: Array[Vector2] = [
			Vector2(r.position.x + rad, r.position.y + rad),
			Vector2(r.end.x - rad, r.position.y + rad),
			Vector2(r.end.x - rad, r.end.y - rad),
			Vector2(r.position.x + rad, r.end.y - rad)]
		var starts: Array[float] = [PI, PI * 1.5, 0.0, PI * 0.5]
		for c in 4:
			for j in 5:
				var a: float = starts[c] + (PI * 0.5) * float(j) / 4.0
				pts.append(centres[c] + Vector2(cos(a), sin(a)) * rad)
		pts.append(pts[0])
		return pts


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
