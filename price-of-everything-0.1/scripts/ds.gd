# Design System for Price of Everything.
# Autoload: registered as "DS" in project.godot.
#
# Builds a Theme at startup, assigns to root viewport so every Control inherits.
# Style a node by setting `theme_type_variation`:
#
#   Label:
#     "Title"        — Bebas Neue 48 (panel / tile titles)
#     "Section"      — Barlow Cond. Bold 22, uppercase, 0.08em tracking
#     "BuildingName" — Barlow Cond. SemiBold 22
#     "Body"         — Plex Medium 14 (default for stats / labels)
#     "Caption"      — Plex 12 muted (tiny metadata)
#     "Numeric"      — Plex SemiBold 16 (numbers / %)
#
#   PanelContainer:
#     (default)      — base panel (navy + soft cream outline)
#     "Card"         — section card (lighter navy, soft outline)
#     "Outlined"     — emphasised section (brighter navy + bold cream outline)
#     "Inset"        — inset / track (darker, tighter padding)
#
#   Button:
#     (default)      — secondary button (dark)
#     "Primary"      — gold CTA
#     "Build"        — light-blue build / upgrade button (pill-ish)
#
# Code tokens (don't hardcode hex / px in panels):
#   DS.PALETTE.* / DS.SP.* / DS.FS.*
#
# Discipline rule: never `add_theme_*_override(...)` in panel code; if you need
# a new look, add a variation here so it cascades.

extends Node

# ── Colour palette ─────────────────────────────────────────────────────────
const PALETTE := {
	"BG": Color(0, 0.07, 0.14),
	"BG_PANEL": Color("#040F1B"),         # panel background — tile-view pipe-frame navy (all panels)
	"BG_CARD": Color("#040F1B"),          # section cards — flush w/ panel, border-delineated
	"BG_INSET": Color(0, 0.08, 0.16),     # darker navy — insets / default buttons
	"BG_HIGHLIGHT": Color(0, 0.18, 0.33), # lighter navy — outlined / highlighted sections (brighter than cards)
	"BORDER": Color("#FDEDC3"),
	"BORDER_SOFT": Color(0.995, 0.93, 0.76, 0.55),
	"BORDER_STRONG": Color("#FDEDC3"),
	"ACCENT": Color("#FDEDC3"),
	"ACCENT_DIM": Color("#7A5F2C"),
	"TEXT": Color("#E8EEF7"),
	"TEXT_MUTED": Color("#C2D2E5"),       # was #9BB1CC — bumped much closer to white for legibility
	"TEXT_DIM": Color("#6B7F98"),
	"ACTION_BLUE": Color("#2D70A8"),      # darker steel blue — build / upgrade
	"ACTION_BLUE_HOVER": Color("#3D85BD"),
	"ACTION_BLUE_PRESSED": Color("#1F5685"),
	"OK": Color("#5BD180"),
	"WARN": Color("#E6B85C"),
	"DANGER": Color("#E66060"),
}

# ── Spacing scale (pixels) ─────────────────────────────────────────────────
const SP := {"XS": 4, "SM": 8, "MD": 12, "LG": 20, "XL": 32, "XXL": 48}

# ── Font sizes ─────────────────────────────────────────────────────────────
const FS := {
	"H1": 32, "SECTION": 22, "BUILDING": 22,
	"BODY": 14, "CAPTION": 13, "NUMERIC": 16,
}

# ── Font paths ─────────────────────────────────────────────────────────────
const FONT_PATHS := {
	"BEBAS": "res://assets/fonts/BebasNeue-Regular.ttf",
	"BARLOW_BOLD": "res://assets/fonts/BarlowCondensed-Bold.ttf",
	"BARLOW_SEMI": "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
	"PLEX": "res://assets/fonts/IBMPlexSans-Regular.ttf",
	"PLEX_MED": "res://assets/fonts/IBMPlexSans-Medium.ttf",
	"PLEX_SEMI": "res://assets/fonts/IBMPlexSans-SemiBold.ttf",
}

var theme: Theme

func _ready() -> void:
	theme = _build_theme()
	get_tree().root.theme = theme
	print("[DS] Theme built: %d stylebox types, font=%s" % [
		theme.get_stylebox_type_list().size(),
		"OK" if theme.default_font else "MISSING (font files not loaded)"
	])

# ─── Theme construction ────────────────────────────────────────────────────
func _build_theme() -> Theme:
	var t := Theme.new()
	var fonts := _load_fonts()

	# Default font (anything without a variation)
	if fonts.get("PLEX_MED"):
		t.default_font = fonts["PLEX_MED"]
	t.default_font_size = FS["BODY"]
	t.set_color("font_color", "Label", PALETTE["TEXT"])

	# ── Label variations ────────────────────────────────────────────────
	_label_var(t, fonts, "Title",        "BEBAS",       FS["H1"],       PALETTE["TEXT"])
	_label_var(t, fonts, "Section",      "BARLOW_BOLD", FS["SECTION"],  PALETTE["ACCENT"], 0.08)
	_label_var(t, fonts, "BuildingName", "BARLOW_SEMI", FS["BUILDING"], PALETTE["TEXT"])
	_label_var(t, fonts, "Body",         "PLEX_MED",    FS["BODY"],     PALETTE["TEXT"])
	_label_var(t, fonts, "Caption",      "PLEX",        FS["CAPTION"],  PALETTE["TEXT_MUTED"])
	_label_var(t, fonts, "Numeric",      "PLEX_SEMI",   FS["NUMERIC"],  PALETTE["TEXT"])

	# ── PanelContainer base + variations ───────────────────────────────
	# Default panel: opaque navy + 2px solid cream outline + generous padding
	t.set_stylebox("panel", "PanelContainer",
		_stylebox(PALETTE["BG_PANEL"], PALETTE["BORDER"], 14, 2, 32, 28))

	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card",
		_stylebox(PALETTE["BG_CARD"], PALETTE["BORDER_SOFT"], 10, 1, 24, 20))

	t.set_type_variation("Outlined", "PanelContainer")
	t.set_stylebox("panel", "Outlined",
		_stylebox(PALETTE["BG_HIGHLIGHT"], PALETTE["BORDER_STRONG"], 10, 3, 24, 20))

	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset",
		_stylebox(PALETTE["BG_INSET"], PALETTE["BORDER_SOFT"], 6, 1, 14, 10))

	# ── Button base (secondary / dark) ────────────────────────────────
	# Secondary buttons must stay clearly lighter than the dark panel bg, so use
	# the lighter navy (BG_HIGHLIGHT) for normal, lighter still on hover, and a
	# darker fill when pressed.
	t.set_stylebox("normal", "Button",
		_stylebox(PALETTE["BG_HIGHLIGHT"], PALETTE["BORDER_SOFT"], 6, 1, 18, 9))
	t.set_stylebox("hover", "Button",
		_stylebox(Color(PALETTE["BG_HIGHLIGHT"]).lightened(0.10), PALETTE["BORDER"], 6, 1, 18, 9))
	t.set_stylebox("pressed", "Button",
		_stylebox(PALETTE["BG_INSET"], PALETTE["BORDER"], 6, 1, 18, 9))
	t.set_color("font_color", "Button", PALETTE["TEXT"])
	t.set_color("font_hover_color", "Button", PALETTE["ACCENT"])
	t.set_color("font_pressed_color", "Button", PALETTE["ACCENT"])
	# Barlow Condensed Bold is a narrow face — add letter-spacing so button labels
	# don't look cramped, and size up 2 steps from body (14 → 18).
	if fonts.get("BARLOW_BOLD"):
		var btn_font := FontVariation.new()
		btn_font.base_font = fonts["BARLOW_BOLD"]
		btn_font.spacing_glyph = 2
		t.set_font("font", "Button", btn_font)
	t.set_font_size("font_size", "Button", 16)
	t.set_constant("icon_max_width", "Button", 24)   # cap icon size on icon buttons

	# ── Primary button (gold CTA) ──────────────────────────────────────
	t.set_type_variation("Primary", "Button")
	t.set_stylebox("normal", "Primary",
		_stylebox(PALETTE["ACCENT"], PALETTE["ACCENT"], 6, 1, 20, 9))
	t.set_stylebox("hover", "Primary",
		_stylebox(Color(PALETTE["ACCENT"]).lightened(0.06), PALETTE["ACCENT"], 6, 1, 20, 9))
	t.set_stylebox("pressed", "Primary",
		_stylebox(Color(PALETTE["ACCENT"]).darkened(0.10), PALETTE["ACCENT"], 6, 1, 20, 9))
	t.set_color("font_color", "Primary", PALETTE["BG"])
	t.set_color("font_hover_color", "Primary", PALETTE["BG"])
	t.set_color("font_pressed_color", "Primary", PALETTE["BG"])

	# ── Build / Upgrade button (light blue, more rounded) ──────────────
	t.set_type_variation("Build", "Button")
	t.set_stylebox("normal", "Build",
		_stylebox(PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_PRESSED"], 14, 1, 20, 9))
	t.set_stylebox("hover", "Build",
		_stylebox(PALETTE["ACTION_BLUE_HOVER"], PALETTE["ACTION_BLUE_PRESSED"], 14, 1, 20, 9))
	t.set_stylebox("pressed", "Build",
		_stylebox(PALETTE["ACTION_BLUE_PRESSED"], PALETTE["ACTION_BLUE_PRESSED"], 14, 1, 20, 9))
	t.set_color("font_color", "Build", PALETTE["TEXT"])
	t.set_color("font_hover_color", "Build", PALETTE["TEXT"])
	t.set_color("font_pressed_color", "Build", PALETTE["ACCENT"])

	# ── Build icon button (square 40×40, light blue, large off-white icon) ──
	# Tight padding (6) so a 28px icon fills the small square; the text Build
	# variation's 24px padding alone would force the button wider than 40px.
	t.set_type_variation("BuildIcon", "Button")
	t.set_stylebox("normal", "BuildIcon",
		_stylebox(PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_PRESSED"], 10, 1, 6, 6))
	t.set_stylebox("hover", "BuildIcon",
		_stylebox(PALETTE["ACTION_BLUE_HOVER"], PALETTE["ACTION_BLUE_PRESSED"], 10, 1, 6, 6))
	t.set_stylebox("pressed", "BuildIcon",
		_stylebox(PALETTE["ACTION_BLUE_PRESSED"], PALETTE["ACTION_BLUE_PRESSED"], 10, 1, 6, 6))
	t.set_constant("icon_max_width", "BuildIcon", 28)

	return t

func _label_var(t: Theme, fonts: Dictionary, name: String, font_key: String,
		size: int, color: Color, tracking_em: float = 0.0) -> void:
	t.set_type_variation(name, "Label")
	var base = fonts.get(font_key)
	if base:
		var f: Font = base
		# Godot doesn't expose letter-spacing on Label directly. Wrap base font
		# in a FontVariation with spacing_glyph (in px) computed from em tracking.
		if tracking_em > 0.0:
			var variation := FontVariation.new()
			variation.base_font = base
			variation.spacing_glyph = int(round(size * tracking_em))
			f = variation
		t.set_font("font", name, f)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, color)

# Creates a StyleBoxFlat with bg/border, corner radius, border width, and
# horizontal + vertical content padding (px).
func _stylebox(bg: Color, border: Color, radius: int, border_w: int,
		pad_h: int, pad_v: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = border_w
	s.border_width_top = border_w
	s.border_width_right = border_w
	s.border_width_bottom = border_w
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_right = radius
	s.corner_radius_bottom_left = radius
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s

func _load_fonts() -> Dictionary:
	var fonts := {}
	for key in FONT_PATHS:
		var path: String = FONT_PATHS[key]
		if ResourceLoader.exists(path):
			fonts[key] = load(path)
		else:
			fonts[key] = null
			push_warning("DS: Font missing at %s — falling back to default" % path)
	return fonts
