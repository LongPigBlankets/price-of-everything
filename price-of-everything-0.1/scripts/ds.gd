# Design System for Price of Everything.
# Autoload: registered as "DS" in project.godot.
#
# Builds a Theme at startup, assigns to root viewport so every Control inherits.
# Style a node by setting `theme_type_variation`:
#
#   Label:
#     "Title"        — Bebas Neue 48 (panel / tile titles)
#     "Section"      — Barlow Cond. Bold 22, uppercase, 0.08em tracking
#     "SectionRuled" — Plex SemiBold 15, uppercase — pairs with ruled_section_head()
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
#     (default)      — Plex Sans Condensed SemiBold 17 steel-blue button
#     "Primary"      — brighter steel-blue CTA
#     "Brass"        — brass fill, dark navy text (accent; commit CTAs stay steel-blue)
#     "Build"        — steel-blue build / upgrade button (pill-ish)
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
	"BORDER": Color(0.995234, 0.930806, 0.763265),
	"BORDER_SOFT": Color(0.995, 0.93, 0.76, 0.55),
	"BORDER_STRONG": Color(0.995234, 0.930806, 0.763265),
	"ACCENT": Color(0.995234, 0.930806, 0.763265),
	"ACCENT_DIM": Color("#7A5F2C"),
	# Brass. SEMANTIC, like OK/WARN/DANGER: it means "this is the prize", so it is exempt from
	# the off-white-on-navy rule the same way they are. Reads 8.4:1 on the panel navies.
	"BRASS": Color("#D9B24C"),
	"TEXT": Color("#E8EEF7"),
	"TEXT_MUTED": Color("#C2D2E5"),       # was #9BB1CC — bumped much closer to white for legibility
	# Secondary label text. NOT a way to make text quieter on a dark panel: on the navies
	# this palette actually uses it reads as grey-on-grey at 11–14 px, which is where the
	# owner keeps finding it. THE RULE (see CLAUDE.md): text on BG_PANEL / BG_CARD /
	# BG_INSET / the top bar navy is TEXT unless it is saying something semantic. To make a
	# label feel secondary on a dark surface, drop its SIZE or weight, not its contrast.
	# Was #6B7F98, which measured 4.69:1 against BG_PANEL — over
	# the WCAG AA line by a hair, and at 11-14px it read as grey-on-grey. Now 9.92:1.
	# Owner rule, 9 Aug: the dark grey never goes on a navy or dark background.
	"TEXT_DIM": Color("#A9BCD2"),
	# DISABLED controls, and only those: low contrast IS the signal there, so this keeps the
	# old dim value. Never use it for text the player is meant to read.
	"TEXT_DISABLED": Color("#6B7F98"),
	"ACTION_BLUE": Color("#314B55"),      # skeuomorphic steel-blue — build / upgrade
	"ACTION_BLUE_HOVER": Color("#3C5C68"),
	"ACTION_BLUE_PRESSED": Color("#263A43"),
	"ACTION_BLUE_TOP": Color("#506B75"),
	"ACTION_BLUE_BORDER": Color("#17252B"),
	"BUTTON_RIM_LIGHT": Color("#B9C1C3"),
	"BUTTON_RIM_MID": Color("#5D696E"),
	"BUTTON_RIM_DARK": Color("#20282C"),
	"OK": Color("#5BD180"),
	"WARN": Color("#E6B85C"),
	"DANGER": Color("#E66060"),
}

# ── Spacing scale (pixels) ─────────────────────────────────────────────────
const SP := {"XS": 4, "SM": 8, "MD": 12, "LG": 20, "XL": 32, "XXL": 48}

# ── Font sizes ─────────────────────────────────────────────────────────────
const FS := {
	"H1": 32, "SECTION": 22, "BUILDING": 22,
	"BODY": 14, "CAPTION": 14, "NUMERIC": 16,   # CAPTION was 13 — bumped +1 for legibility
	"BUTTON": 17,
}

# ── Font paths ─────────────────────────────────────────────────────────────
const FONT_PATHS := {
	"BEBAS": "res://assets/fonts/BebasNeue-Regular.ttf",
	"BARLOW_BOLD": "res://assets/fonts/BarlowCondensed-Bold.ttf",
	"BARLOW_SEMI": "res://assets/fonts/BarlowCondensed-SemiBold.ttf",
	"PLEX": "res://assets/fonts/IBMPlexSans-Regular.ttf",   # catalogued, deliberately unused
	"PLEX_MED": "res://assets/fonts/IBMPlexSans-Medium.ttf",
	"PLEX_SEMI": "res://assets/fonts/IBMPlexSans-SemiBold.ttf",
	"PLEX_COND_SEMI": "res://assets/fonts/IBMPlexSansCondensed-SemiBold.ttf",
}

var theme: Theme

# ── DS component builders ───────────────────────────────────────────────────
# The design system is more than styleboxes: these are the blessed builders for
# the two most-repeated composite widgets, so every panel renders them identically.
# The implementations live in dedicated RefCounted modules (preloaded, headless-safe);
# DS is the discoverable façade.
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const RecipeDiagram := preload("res://scripts/recipe_diagram.gd")

## Framed + bevelled good icon (off-white plate + raised metal rim + clipped/zoomed
## art) — the market-panel goods-tab treatment. THE way to render a good icon.
func good_icon(good_id: String, internal_name: String, size: int = 98) -> Control:
	return UIHelpers.make_framed_good_icon(good_id, internal_name, size)

## The same art on the same cream, WITHOUT the metal plate and bevel — for lists, where a
## column of framed icons reads as a shelf of trophies rather than as a list.
func good_icon_plain(good_id: String, internal_name: String, size: int = 60) -> Control:
	return UIHelpers.make_plain_good_icon(good_id, internal_name, size)

## Recipe strip (cream card, inputs → navy power-arrow → output, bleeding icons +
## qty pills) from a BuildingReadout.flow() dict.
func recipe_diagram(flow: Dictionary) -> PanelContainer:
	return RecipeDiagram.build(flow)

## Recipe strip straight from a Catalog recipe dict (no building instance).
func recipe_diagram_for(recipe: Dictionary) -> PanelContainer:
	return RecipeDiagram.from_recipe(recipe)

## Ledger section head (Construct V3, spec §4): a fine rule above a small-caps
## title. Rules replace coloured tick-bars — structure never wears a status
## colour. double_rule marks a verdict/total band (the classic ledger double line).
func ruled_section_head(text: String, double_rule: bool = false) -> Control:
	return UIHelpers.make_ruled_section_head(text, double_rule)

## The bare rule, for placing above non-label content (e.g. a sticky footer).
func section_rule(double_rule: bool = false) -> Control:
	return UIHelpers.make_section_rule(double_rule)

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
	# Caption is MEDIUM, not Regular (owner 2026-08-24: "stop using the thin font
	# altogether"). Regular at caption sizes on the panel navies reads as low contrast even
	# in the off-white — the weight was doing what a greyer colour would have, and the
	# standing rule already forbids that. Nothing in the UI uses PLEX Regular now: the
	# ladder is MEDIUM for body and caption, SEMIBOLD for emphasis and every numeral.
	_label_var(t, fonts, "Caption",      "PLEX_MED",    FS["CAPTION"],  PALETTE["TEXT"])
	_label_var(t, fonts, "Numeric",      "PLEX_SEMI",   FS["NUMERIC"],  PALETTE["TEXT"])
	# What a mission pays out. Brass and semibold, so the one line on a quest card that is a
	# REWARD rather than an instruction reads as one at a glance.
	_label_var(t, fonts, "Reward",       "PLEX_SEMI",   FS["BODY"],     PALETTE["BRASS"])
	# Ledger section head (Construct V3, spec §4): small-caps at ~1.1x body, off-white,
	# paired with the fine rule that ruled_section_head() draws above it. The head is
	# quieter than "Section" because the rule carries the separation, not size or colour.
	# Plex SemiBold (owner 2026-08-26: one font family throughout Construct V3 —
	# Bebas Neue for the panel title only — with bold vs not-bold as the sole other
	# differentiator; this was the one label still on a second family, Barlow
	# Condensed, purely by inheriting the older "Section" variation's choice).
	_label_var(t, fonts, "SectionRuled", "PLEX_SEMI",   15,             PALETTE["TEXT"], 0.08)

	# ── PanelContainer base + variations ───────────────────────────────
	# Default panel: opaque navy + 2px solid cream outline + generous padding
	t.set_stylebox("panel", "PanelContainer",
		_stylebox(PALETTE["BG_PANEL"], PALETTE["BORDER"], 14, 2, 20, 16))

	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card",
		_stylebox(PALETTE["BG_CARD"], PALETTE["BORDER_SOFT"], 10, 1, 24, 20))

	t.set_type_variation("Outlined", "PanelContainer")
	t.set_stylebox("panel", "Outlined",
		_stylebox(PALETTE["BG_HIGHLIGHT"], PALETTE["BORDER_STRONG"], 10, 3, 24, 20))

	t.set_type_variation("Inset", "PanelContainer")
	t.set_stylebox("panel", "Inset",
		_stylebox(PALETTE["BG_INSET"], PALETTE["BORDER_SOFT"], 6, 1, 14, 10))

	# Coach card: opaque navy + a solid cream (off-white) 2px outline — reads clearly over the dim.
	t.set_type_variation("CoachCard", "PanelContainer")
	t.set_stylebox("panel", "CoachCard",
		_stylebox(PALETTE["BG_PANEL"], PALETTE["BORDER_STRONG"], 12, 2, 24, 20))

	# ── Button base (secondary / steel blue) ──────────────────────────
	# The generated texture adds a pale top glint and darker lower bevel so the
	# buttons sit closer to the chunky upgrade-button reference.
	t.set_stylebox("normal", "Button",
		_button_stylebox(PALETTE["ACTION_BLUE_TOP"], PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_BORDER"], 8, 2, 19, 10))
	t.set_stylebox("hover", "Button",
		_button_stylebox(Color(PALETTE["ACTION_BLUE_TOP"]).lightened(0.10), PALETTE["ACTION_BLUE_HOVER"], PALETTE["BORDER"], 8, 2, 19, 10, 0.44))
	t.set_stylebox("pressed", "Button",
		_button_stylebox(PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_PRESSED"], Color(PALETTE["ACTION_BLUE_BORDER"]).darkened(0.20), 8, 2, 19, 9, 0.18))
	t.set_stylebox("disabled", "Button",
		_button_stylebox(Color("#435965"), Color("#2D414C"), Color("#657883"), 8, 2, 19, 10, 0.16))
	t.set_stylebox("focus", "Button", t.get_stylebox("hover", "Button"))
	t.set_color("font_color", "Button", PALETTE["ACCENT"])
	t.set_color("font_hover_color", "Button", PALETTE["ACCENT"])
	t.set_color("font_pressed_color", "Button", PALETTE["ACCENT"])
	t.set_color("font_disabled_color", "Button", Color(PALETTE["ACCENT"].r, PALETTE["ACCENT"].g, PALETTE["ACCENT"].b, 0.45))
	# IBM Plex Sans Condensed is used for every themed button variant, with
	# IBM Plex Sans SemiBold as a local fallback if the condensed asset is absent.
	_apply_button_font(t, fonts, "Button")
	# No base icon_max_width cap: icon buttons that want a large icon (e.g. the
	# 100px circular bottom-menu buttons with expand_icon) size to their button.
	# The small square icon buttons set their own cap via the BuildIcon variation.

	# ── Primary button (brighter steel-blue CTA) ───────────────────────
	t.set_type_variation("Primary", "Button")
	t.set_stylebox("normal", "Primary",
		_button_stylebox(Color("#A7C8D3"), PALETTE["ACTION_BLUE_HOVER"], PALETTE["BORDER"], 8, 2, 21, 10, 0.46))
	t.set_stylebox("hover", "Primary",
		_button_stylebox(Color("#BBD5DD"), Color("#81AFC0"), PALETTE["BORDER"], 8, 2, 21, 10, 0.50))
	t.set_stylebox("pressed", "Primary",
		_button_stylebox(PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_PRESSED"], Color(PALETTE["BORDER"]).darkened(0.18), 8, 2, 21, 9, 0.20))
	t.set_stylebox("focus", "Primary", t.get_stylebox("hover", "Primary"))
	t.set_color("font_color", "Primary", PALETTE["ACCENT"])
	t.set_color("font_hover_color", "Primary", PALETTE["ACCENT"])
	t.set_color("font_pressed_color", "Primary", PALETTE["ACCENT"])
	_apply_button_font(t, fonts, "Primary")

	# ── Build / Upgrade button (steel blue, more rounded) ──────────────
	t.set_type_variation("Build", "Button")
	t.set_stylebox("normal", "Build",
		_button_stylebox(PALETTE["ACTION_BLUE_TOP"], PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_BORDER"], 14, 2, 21, 10))
	t.set_stylebox("hover", "Build",
		_button_stylebox(Color(PALETTE["ACTION_BLUE_TOP"]).lightened(0.10), PALETTE["ACTION_BLUE_HOVER"], PALETTE["BORDER"], 14, 2, 21, 10, 0.46))
	t.set_stylebox("pressed", "Build",
		_button_stylebox(PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_PRESSED"], Color(PALETTE["ACTION_BLUE_BORDER"]).darkened(0.20), 14, 2, 21, 9, 0.18))
	t.set_stylebox("focus", "Build", t.get_stylebox("hover", "Build"))
	t.set_color("font_color", "Build", PALETTE["ACCENT"])
	t.set_color("font_hover_color", "Build", PALETTE["ACCENT"])
	t.set_color("font_pressed_color", "Build", PALETTE["ACCENT"])
	_apply_button_font(t, fonts, "Build")

	# ── Silver metallic button (tutorial coach "Next" / "Begin" CTA) ────
	# Reuses the same beveled-texture generator as the steel buttons, but with a
	# bright-silver→grey fill and dark navy text, for a distinct polished-metal CTA.
	t.set_type_variation("Silver", "Button")
	t.set_stylebox("normal", "Silver",
		_button_stylebox(Color("#E8ECEE"), Color("#9BA6AC"), Color("#39424A"), 8, 2, 21, 10, 0.55))
	t.set_stylebox("hover", "Silver",
		_button_stylebox(Color("#F2F5F6"), Color("#AEB9BF"), Color("#4A545B"), 8, 2, 21, 10, 0.62))
	t.set_stylebox("pressed", "Silver",
		_button_stylebox(Color("#AEB9BF"), Color("#828E94"), Color("#2A3236"), 8, 2, 21, 9, 0.25))
	t.set_stylebox("focus", "Silver", t.get_stylebox("hover", "Silver"))
	t.set_color("font_color", "Silver", PALETTE["BG_PANEL"])
	t.set_color("font_hover_color", "Silver", PALETTE["BG_PANEL"])
	t.set_color("font_pressed_color", "Silver", PALETTE["BG_PANEL"])
	_apply_button_font(t, fonts, "Silver")

	# ── Brass button (the copper/bronze research-panel family) ──────────────────
	# Brass fill, dark navy text, dimmed-brass disabled state. Built for the V3
	# confirm CTA, then benched: commit buttons stay steel-blue for consistency
	# (owner 2026-08-26). Kept as an available accent variation.
	t.set_type_variation("Brass", "Button")
	t.set_stylebox("normal", "Brass",
		_button_stylebox(Color("#EFC96B"), Color("#C6963A"), Color("#54401C"), 8, 2, 21, 10, 0.50))
	t.set_stylebox("hover", "Brass",
		_button_stylebox(Color("#F6D67F"), Color("#D2A344"), Color("#54401C"), 8, 2, 21, 10, 0.56))
	t.set_stylebox("pressed", "Brass",
		_button_stylebox(Color("#C6963A"), Color("#A87D2C"), Color("#3E2F13"), 8, 2, 21, 9, 0.22))
	t.set_stylebox("disabled", "Brass",
		_button_stylebox(Color("#8A7648"), Color("#5E5030"), Color("#3A331F"), 8, 2, 21, 10, 0.14))
	t.set_stylebox("focus", "Brass", t.get_stylebox("hover", "Brass"))
	t.set_color("font_color", "Brass", PALETTE["BG_PANEL"])
	t.set_color("font_hover_color", "Brass", PALETTE["BG_PANEL"])
	t.set_color("font_pressed_color", "Brass", PALETTE["BG_PANEL"])
	t.set_color("font_disabled_color", "Brass",
		Color(PALETTE["BG_PANEL"].r, PALETTE["BG_PANEL"].g, PALETTE["BG_PANEL"].b, 0.65))
	_apply_button_font(t, fonts, "Brass")

	# ── Selected choice (off-white fill, navy text) ─────────────────────
	# Used by persistent selector rows such as the advisor-position preview.
	# Every interaction state stays inverted so a selected choice never falls
	# back to the default steel-blue surface between hover/press transitions.
	t.set_type_variation("ChoiceSelected", "Button")
	var choice_normal := _stylebox(PALETTE["ACCENT"], PALETTE["BORDER"], 8, 1, 14, 7)
	var choice_hover := _stylebox(Color(PALETTE["ACCENT"]).lightened(0.04), PALETTE["BORDER"], 8, 1, 14, 7)
	var choice_pressed := _stylebox(Color(PALETTE["ACCENT"]).darkened(0.08), PALETTE["BORDER"], 8, 1, 14, 7)
	t.set_stylebox("normal", "ChoiceSelected", choice_normal)
	t.set_stylebox("hover", "ChoiceSelected", choice_hover)
	t.set_stylebox("pressed", "ChoiceSelected", choice_pressed)
	t.set_stylebox("hover_pressed", "ChoiceSelected", choice_hover)
	t.set_stylebox("focus", "ChoiceSelected", choice_hover)
	t.set_stylebox("disabled", "ChoiceSelected", choice_normal)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(state, "ChoiceSelected", PALETTE["BG_PANEL"])
	_apply_button_font(t, fonts, "ChoiceSelected")
	t.set_constant("outline_size", "ChoiceSelected", 0)

	# ── Build icon button (square 40×40, steel blue, large off-white icon) ──
	# Tight padding (6) so a 28px icon fills the small square; the text Build
	# variation's 24px padding alone would force the button wider than 40px.
	t.set_type_variation("BuildIcon", "Button")
	t.set_stylebox("normal", "BuildIcon",
		_button_stylebox(PALETTE["ACTION_BLUE_TOP"], PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_BORDER"], 10, 2, 6, 6))
	t.set_stylebox("hover", "BuildIcon",
		_button_stylebox(Color(PALETTE["ACTION_BLUE_TOP"]).lightened(0.10), PALETTE["ACTION_BLUE_HOVER"], PALETTE["BORDER"], 10, 2, 6, 6, 0.46))
	t.set_stylebox("pressed", "BuildIcon",
		_button_stylebox(PALETTE["ACTION_BLUE"], PALETTE["ACTION_BLUE_PRESSED"], Color(PALETTE["ACTION_BLUE_BORDER"]).darkened(0.20), 10, 2, 6, 5, 0.18))
	t.set_stylebox("focus", "BuildIcon", t.get_stylebox("hover", "BuildIcon"))
	t.set_constant("icon_max_width", "BuildIcon", 28)
	_apply_button_font(t, fonts, "BuildIcon")
	_apply_button_font(t, fonts, "OptionButton")
	_apply_button_font(t, fonts, "MenuButton")
	_copy_button_surface(t, "OptionButton", "Button")
	_copy_button_surface(t, "MenuButton", "Button")

	# ── TabContainer (spaced, rounded-top tabs) ────────────────────────
	# Tabs read as distinct chips: rounded tops, a gap between them (drawn bg is
	# inset horizontally), and the selected tab inverts to off-white + navy text.
	t.set_stylebox("tab_unselected", "TabContainer", _tab_box(PALETTE["BG_INSET"], PALETTE["BORDER_SOFT"]))
	t.set_stylebox("tab_hovered", "TabContainer", _tab_box(PALETTE["BG_HIGHLIGHT"], PALETTE["BORDER_SOFT"]))
	t.set_stylebox("tab_selected", "TabContainer", _tab_box(PALETTE["ACCENT"], PALETTE["BORDER"]))  # off-white
	t.set_stylebox("tab_disabled", "TabContainer", _tab_box(PALETTE["BG_INSET"], PALETTE["BORDER_SOFT"]))
	t.set_stylebox("tab_focus", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("tabbar_background", "TabContainer", StyleBoxEmpty.new())
	t.set_stylebox("panel", "TabContainer", _stylebox(PALETTE["BG_PANEL"], PALETTE["BORDER_SOFT"], 8, 1, 12, 12))
	t.set_color("font_selected_color", "TabContainer", PALETTE["BG_PANEL"])   # navy on off-white
	t.set_color("font_unselected_color", "TabContainer", PALETTE["ACCENT"])    # off-white on navy
	t.set_color("font_hovered_color", "TabContainer", PALETTE["ACCENT"])
	t.set_color("font_disabled_color", "TabContainer", PALETTE["TEXT_DISABLED"])
	if fonts.get("PLEX_COND_SEMI"):
		t.set_font("font", "TabContainer", fonts["PLEX_COND_SEMI"])
	elif fonts.get("PLEX_SEMI"):
		t.set_font("font", "TabContainer", fonts["PLEX_SEMI"])
	t.set_font_size("font_size", "TabContainer", FS["BODY"])

	return t

func _tab_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 0
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	# Inset the drawn background horizontally so adjacent tabs show a visible gap.
	s.expand_margin_left = -4
	s.expand_margin_right = -4
	return s

func _copy_button_surface(t: Theme, type_name: String, source_type: String) -> void:
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		if t.has_stylebox(state, source_type):
			t.set_stylebox(state, type_name, t.get_stylebox(state, source_type))

func _apply_button_font(t: Theme, fonts: Dictionary, type_name: String) -> void:
	if fonts.get("PLEX_COND_SEMI"):
		t.set_font("font", type_name, fonts["PLEX_COND_SEMI"])
	elif fonts.get("PLEX_SEMI"):
		t.set_font("font", type_name, fonts["PLEX_SEMI"])
	t.set_font_size("font_size", type_name, FS["BUTTON"])
	t.set_color("font_outline_color", type_name, Color(0, 0, 0, 0.92))
	t.set_constant("outline_size", type_name, 1)

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

func _button_stylebox(top: Color, bottom: Color, border: Color, radius: int,
		border_w: int, pad_h: int, pad_v: int, shine: float = 0.38) -> StyleBoxTexture:
	var width := 112
	var height := 56
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var rim_w := maxi(3, border_w + 1)
	var line_w := 1
	var bevel_w := 1
	var bevel_inset := rim_w + line_w
	var fill_inset := bevel_inset + bevel_w
	var fill_width := width - (fill_inset * 2)
	var fill_height := height - (fill_inset * 2)
	var rim_radius := float(radius)
	var line_radius: float = maxf(0.0, float(radius - rim_w))
	var bevel_radius: float = maxf(0.0, float(radius - bevel_inset))
	var fill_radius: float = maxf(0.0, float(radius - fill_inset))

	for y in range(height):
		var y_t: float = clampf(float(y - fill_inset) / maxf(1.0, float(fill_height - 1)), 0.0, 1.0)
		for x in range(width):
			if not _inside_rounded_rect(x, y, width, height, rim_radius):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue

			var is_fill := _inside_rounded_rect(x - fill_inset, y - fill_inset, fill_width, fill_height, fill_radius)
			if is_fill:
				var x_t: float = clampf(float(x - fill_inset) / maxf(1.0, float(fill_width - 1)), 0.0, 1.0)
				var diagonal := (x_t + y_t) * 0.5
				var fill := top.lerp(bottom, clampf((diagonal * 0.70) + (y_t * 0.30), 0.0, 1.0))
				if diagonal < 0.34:
					fill = fill.lerp(Color.WHITE, shine * 0.38 * (1.0 - (diagonal / 0.34)))
				elif diagonal > 0.72:
					fill = fill.darkened(0.18 * ((diagonal - 0.72) / 0.28))
				img.set_pixel(x, y, fill)
			else:
				var is_bevel := _inside_rounded_rect(
					x - bevel_inset,
					y - bevel_inset,
					width - (bevel_inset * 2),
					height - (bevel_inset * 2),
					bevel_radius
				)
				if is_bevel:
					var bevel_diagonal := (float(x) / float(width - 1) + float(y) / float(height - 1)) * 0.5
					var bevel := top.lerp(border, bevel_diagonal)
					if bevel_diagonal < 0.42:
						bevel = bevel.lerp(Color.WHITE, 0.20)
					elif bevel_diagonal > 0.66:
						bevel = bevel.darkened(0.35)
					img.set_pixel(x, y, bevel)
					continue

				var is_inner_line := _inside_rounded_rect(
					x - rim_w,
					y - rim_w,
					width - (rim_w * 2),
					height - (rim_w * 2),
					line_radius
				)
				if is_inner_line:
					img.set_pixel(x, y, border)
				else:
					var diagonal := (float(x) / float(width - 1) + float(y) / float(height - 1)) * 0.5
					var rim := PALETTE["BUTTON_RIM_LIGHT"].lerp(PALETTE["BUTTON_RIM_DARK"], diagonal)
					if diagonal > 0.40:
						rim = rim.lerp(PALETTE["BUTTON_RIM_MID"], 0.28)
					if x < rim_w or y < rim_w:
						rim = rim.lerp(Color.WHITE, 0.18)
					if x >= width - rim_w or y >= height - rim_w:
						rim = rim.darkened(0.26)
					img.set_pixel(x, y, rim)

	var texture := ImageTexture.create_from_image(img)
	var s := StyleBoxTexture.new()
	s.texture = texture
	s.texture_margin_left = radius + rim_w
	s.texture_margin_top = radius + rim_w
	s.texture_margin_right = radius + rim_w
	s.texture_margin_bottom = radius + rim_w
	s.content_margin_left = pad_h
	s.content_margin_right = pad_h
	s.content_margin_top = pad_v
	s.content_margin_bottom = pad_v
	return s

func _inside_rounded_rect(x: int, y: int, width: int, height: int, radius: float) -> bool:
	if width <= 0 or height <= 0:
		return false
	var px := float(x) + 0.5
	var py := float(y) + 0.5
	var cx: float = clampf(px, radius, float(width) - radius)
	var cy: float = clampf(py, radius, float(height) - radius)
	return Vector2(px - cx, py - cy).length() <= radius

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
