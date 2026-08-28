extends RefCounted
## The eight company liveries a player picks from on the New Game screen.
##
## The colours were sampled ONCE from the goods icons each livery is named after
## (`tools/sample_player_colours.py`) and frozen into `data/player_colours.json`. Nothing
## re-samples at runtime: the icons are 2048px scenes, and a livery that shifted because an
## icon was redrawn would silently repaint every building on the map.
##
## Deliberately has NO `class_name`, for the reason recorded in `mass_form_shapes.gd`: a
## freshly declared global class is absent from the headless global-script-class cache until
## an `--import`, which fails the unit suite with "Identifier not declared". Reference it as
##   const PlayerColours := preload("res://scripts/player_colours.gd")
##
## The hue of each livery is the good's own; only saturation and value were clamped into a
## legibility band, because eight companies have to be told apart on the map's warm-grey
## fabric. See the sampler's header for why that band exists (ethylene is pale glass and
## sampled a near-black navy; graphite sampled too light to read as black).

const PATH := "res://data/player_colours.json"

## The livery a match uses when nobody has chosen one — saves from before the picker
## existed, tests, and the tutorial all land here.
const DEFAULT_KEY := "diesel_red"
## Fallback if the data file is missing or unreadable, so a livery is never a null colour.
const FALLBACK := Color("b94c40")

## NPC-owned buildings are paper white whatever the player picked (owner ruling 2026-07-10,
## restated 2026-08-27 for the hijack stamps). Mirrors `building_visuals.gd`'s NPC_WHITE.
const NPC := Color("efe9db")

static var _cache: Array = []
static var _swatches: Dictionary = {}


## Every livery in file order: `{key, label, color, good_icon}`. Ordered, because the
## dropdown shows them in this order and a Dictionary's key order is the file's.
static func all() -> Array:
	if not _cache.is_empty():
		return _cache
	if not FileAccess.file_exists(PATH):
		push_warning("PlayerColours: %s missing — falling back to one livery." % PATH)
		_cache = [{"key": DEFAULT_KEY, "label": "Diesel Red", "color": FALLBACK, "good_icon": ""}]
		return _cache
	var file := FileAccess.open(PATH, FileAccess.READ)
	if file == null:
		_cache = [{"key": DEFAULT_KEY, "label": "Diesel Red", "color": FALLBACK, "good_icon": ""}]
		return _cache
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("PlayerColours: %s did not parse." % PATH)
		_cache = [{"key": DEFAULT_KEY, "label": "Diesel Red", "color": FALLBACK, "good_icon": ""}]
		return _cache
	var colours: Variant = (parsed as Dictionary).get("colours", {})
	if typeof(colours) != TYPE_DICTIONARY:
		colours = {}
	var out: Array = []
	for key in (colours as Dictionary):
		var entry_value: Variant = (colours as Dictionary)[key]
		if typeof(entry_value) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = entry_value
		out.append({
			"key": str(key),
			"label": str(entry.get("label", key)),
			"color": Color(str(entry.get("hex", FALLBACK.to_html(false)))),
			"good_icon": str(entry.get("good_icon", "")),
		})
	if out.is_empty():
		out = [{"key": DEFAULT_KEY, "label": "Diesel Red", "color": FALLBACK, "good_icon": ""}]
	_cache = out
	return _cache


## True when `key` names a livery. The picker's value is written into the ruleset and so
## survives into save files — an unknown key means a hand-edited save or a renamed livery,
## and the caller falls back rather than colouring a company with nothing.
static func has(key: String) -> bool:
	for entry in all():
		if str((entry as Dictionary)["key"]) == key:
			return true
	return false


static func label_for(key: String) -> String:
	for entry in all():
		if str((entry as Dictionary)["key"]) == key:
			return str((entry as Dictionary)["label"])
	return ""


static func color_for(key: String) -> Color:
	for entry in all():
		if str((entry as Dictionary)["key"]) == key:
			return (entry as Dictionary)["color"]
	return FALLBACK


## The livery key this match is being played with. Read from the ruleset, which is where the
## New Game panel's choice lands and how it reaches a save file.
static func active_key() -> String:
	var key := str(MatchState.ruleset.get("company_colour", ""))
	return key if has(key) else DEFAULT_KEY


static func active_color() -> Color:
	return color_for(active_key())


## A flat swatch for the dropdown, `size` px square with a thin dark keyline so a pale
## livery still reads as a rectangle rather than bleeding into the popup behind it.
## Cached per key+size: an OptionButton rebuilds its items whenever the panel is rebuilt.
static func swatch(key: String, size: int = 20) -> ImageTexture:
	var cache_key := "%s|%d" % [key, size]
	if _swatches.has(cache_key):
		return _swatches[cache_key]
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(color_for(key))
	var keyline := Color(0.10, 0.09, 0.08, 0.85)
	for x in size:
		img.set_pixel(x, 0, keyline)
		img.set_pixel(x, size - 1, keyline)
	for y in size:
		img.set_pixel(0, y, keyline)
		img.set_pixel(size - 1, y, keyline)
	var tex := ImageTexture.create_from_image(img)
	_swatches[cache_key] = tex
	return tex


## Drop the parsed table (tests that rewrite the data file).
static func reset_for_tests() -> void:
	_cache = []
	_swatches = {}
