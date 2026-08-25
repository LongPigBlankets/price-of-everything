extends RefCounted
## Cached font resources for the alternate TVP type tokens.
##
## NOTE: the project ships no IBM Plex Mono, so the "Plex Mono / tabular numerals"
## token is approximated with IBM Plex Sans SemiBold + the OpenType `tnum`
## (tabular figures) feature, which gives fixed-width digits for aligned columns.
## Drop in IBMPlexMono-SemiBold.ttf and point `mono()` at it to get true Plex Mono.

## Plex REGULAR is catalogued but no longer used by the UI (owner 2026-08-24). At the
## sizes this game sets text, Regular on the panel navies read as low contrast — the
## weight was doing the job a greyer colour would have, which the standing contrast rule
## forbids. The ladder is MEDIUM for body and caption, SEMIBOLD for emphasis and numerals.
const PLEX := preload("res://assets/fonts/IBMPlexSans-Regular.ttf")
const PLEX_MED := preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const PLEX_SEMI := preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const BEBAS := preload("res://assets/fonts/BebasNeue-Regular.ttf")

static var _mono: FontVariation
static var _section: FontVariation

## Tabular-numeral SemiBold — for every numeral (£, /turn, qty, capacities, RAG).
static func mono() -> FontVariation:
	if _mono == null:
		_mono = FontVariation.new()
		_mono.base_font = PLEX_SEMI
		var ts := TextServerManager.get_primary_interface()
		_mono.opentype_features = {ts.name_to_tag("tnum"): 1}
	return _mono

## Section-header face: Plex Medium, lightly tracked (uppercase applied by caller).
static func section() -> FontVariation:
	if _section == null:
		_section = FontVariation.new()
		_section.base_font = PLEX_MED
		_section.spacing_glyph = 1
	return _section
