extends RefCounted
## The Research panel in DS2: the inks, papers and small drawn things the patent board shares (the blueprint's
## colours, the rubber stamp, the padlock, the drawing pin, the red thread, the sticky note an icon is drawn on, the
## cast shadow, the board's fonts). Presentation only.
##
## Light: the DS2 house light, from the top left (docs/ds2-theme.md rule 2), so a raised thing's shadow falls down
## and to the right and its lit edges are its upper and left ones. Every shadow and bevel here reads LIGHT_FROM.

const UIFonts := preload("res://scripts/ui_fonts.gd")

## Where the light comes from, as a unit step on screen (the top left), and how far a card's shadow falls from it.
const LIGHT_FROM := Vector2(-0.7071, -0.7071)
const SHADOW_REACH := 4.0

const TITLE_FONT: Font = preload("res://assets/fonts/IBMPlexSansCondensed-SemiBold.ttf")
const SPEC_FONT: Font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const LABEL_FONT: Font = preload("res://assets/fonts/BarlowCondensed-Bold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const BODY_SEMI: Font = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const STAMP_FONT: Font = preload("res://assets/fonts/BebasNeue-Regular.ttf")

## Blueprint: the working drawing. Locked: the same sheet faded. Granted: the cream copy kept on file.
const BLUEPRINT := Color("#1d4d84")
const BLUEPRINT_EDGE := Color("#163c69")
const FADED := Color("#4d6b8e")
const FADED_EDGE := Color("#3f5a7a")
const PAPER := Color("#ede4c9")
const PAPER_EDGE := Color("#d6caa6")
const WHITE_LINE := Color(1, 1, 1, 0.92)
const NAVY := Color("#0b2340")
const NAVY_LINE := Color(0.043, 0.137, 0.251, 0.85)
## The rubber stamps' inks.
const STAMP_RED := Color("#b3241c")
const STAMP_BLUE := Color("#1d3f94")
const THREAD_RED := Color("#c22a21")
## Licence choosing: an eligible sheet's glow.
const PICK_GLOW := Color("#f2c14e")
## Text on a dark surface (the plates, the screens).
const TEXT := Color("#E8EEF7")

## The sticky note under a research's icon, and the navy a building or a glyph is printed in on it.
const NOTE := Color("#ecdcae")
const NOTE_EDGE := Color("#cdb982")
const ICON_NAVY := Color("#0b2340")

static var _held := {}
static var _msdf := {}
static var _mono: FontVariation
static var _building_masks := {}


## The board's fonts as signed distance fields, so print stays sharp at any zoom.
static func board_font(f: Font) -> Font:
	var key := f.resource_path
	if _msdf.has(key):
		return _msdf[key]
	var out := f
	if f is FontFile:
		var d := (f as FontFile).duplicate() as FontFile
		d.multichannel_signed_distance_field = true
		d.msdf_pixel_range = 8
		d.msdf_size = 48
		out = d
	_msdf[key] = out
	return out


static func title_font() -> Font:
	return board_font(TITLE_FONT)


static func spec_font() -> Font:
	return board_font(SPEC_FONT)


static func label_font() -> Font:
	return board_font(LABEL_FONT)


static func body_font() -> Font:
	return board_font(BODY_FONT)


static func body_semi() -> Font:
	return board_font(BODY_SEMI)


static func stamp_font() -> Font:
	return board_font(STAMP_FONT)


## Tabular figures (the counts on the scales), as a distance field.
static func mono_font() -> Font:
	if _mono == null:
		_mono = FontVariation.new()
		_mono.base_font = board_font(UIFonts.PLEX_SEMI)
		var ts := TextServerManager.get_primary_interface()
		_mono.opentype_features = {ts.name_to_tag("tnum"): 1}
	return _mono


## A research's reward in a few words: "Increases coal mining output by 15% permanently." reads "+15% coal mining
## output". Other wordings are kept, less "permanently" and the full stop.
static func short_reward(description: String) -> String:
	var s := description.strip_edges().trim_suffix(".").replace(" permanently", "")
	var up := RegEx.create_from_string("^Increases (.+?) by (\\d+%)(.*)$")
	var m := up.search(s)
	if m != null:
		return "+%s %s%s" % [m.get_string(2), m.get_string(1), m.get_string(3)]
	var down := RegEx.create_from_string("^Reduces (.+?) by (\\d+%)(.*)$")
	m = down.search(s)
	if m != null:
		return "%s less %s%s" % [m.get_string(2), m.get_string(1).to_lower(), m.get_string(3)]
	return s.replace("Unlocks new recipe: ", "New recipe: ")


## A building's art as a white mask, its navy plate keyed out (keyed_building_icon.gd's key, without its emboss),
## to be printed navy on a sticky note.
static func building_mask(bd: Dictionary) -> Texture2D:
	var id := str(bd.get("id", ""))
	if _building_masks.has(id):
		return _building_masks[id]
	var tex: Texture2D = load("res://scripts/keyed_building_icon.gd").raw_texture(bd)
	if tex == null:
		_building_masks[id] = null
		return null
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > 200:
		img.resize(200, int(round(img.get_height() * 200.0 / float(img.get_width()))), Image.INTERPOLATE_LANCZOS)
	var bg := img.get_pixel(2, 2)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var dist := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			img.set_pixel(x, y, Color(1, 1, 1, clampf((dist - 0.28) / 0.45, 0.0, 1.0) * c.a))
	img.generate_mipmaps()
	var out := ImageTexture.create_from_image(img)
	_building_masks[id] = out
	return out


## A square sticky note `rect` stuck to a sheet, turned `angle` radians, its glue strip along the top and its foot
## lifting a little, with `icon` drawn on it in `tint` (white keeps a good's own colours; navy prints a mask).
static func sticky_note(ci: CanvasItem, rect: Rect2, angle: float, icon: Texture2D, tint: Color) -> void:
	var c := rect.get_center()
	var half := rect.size * 0.5
	ci.draw_set_transform(c + shadow_offset(2.5), angle, Vector2.ONE)
	ci.draw_rect(Rect2(-half, rect.size).grow(0.5), Color(0, 0, 0, 0.30))
	ci.draw_rect(Rect2(-half + shadow_offset(1.5), rect.size), Color(0, 0, 0, 0.14))
	ci.draw_set_transform(c, angle, Vector2.ONE)
	var r := Rect2(-half, rect.size)
	ci.draw_rect(r, NOTE)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.18)), Color(NOTE_EDGE, 0.35))
	ci.draw_rect(Rect2(Vector2(r.position.x, r.end.y - r.size.y * 0.12), Vector2(r.size.x, r.size.y * 0.12)), Color(1, 1, 1, 0.18))
	ci.draw_rect(r, Color(NOTE_EDGE, 0.8), false, 1.0)
	if icon != null:
		var inner := r.grow(-rect.size.x * 0.12)
		var ts := icon.get_size()
		var k := minf(inner.size.x / ts.x, inner.size.y / ts.y)
		var d := ts * k
		ci.draw_texture_rect(icon, Rect2(inner.get_center() - d * 0.5, d), false, tint)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A kit layer from assets/ui/bdp_v3/, held once loaded (a texture dropped when a draw returns draws blank).
static func tex(layer: String) -> Texture2D:
	if not _held.has(layer):
		_held[layer] = load("res://assets/ui/bdp_v3/%s.png" % layer) as Texture2D
	return _held[layer]


## The offset of a cast shadow `reach` px long: away from the light.
static func shadow_offset(reach: float = SHADOW_REACH) -> Vector2:
	return -LIGHT_FROM * reach


## A soft shadow under a sheet or plate at `rect`, cast away from the light.
static func cast_shadow(ci: CanvasItem, rect: Rect2, reach: float = SHADOW_REACH, alpha: float = 0.42, radius: int = 3) -> void:
	for i in 3:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, alpha * (0.55 - float(i) * 0.15))
		sb.set_corner_radius_all(radius + i * 2)
		ci.draw_style_box(sb, Rect2(rect.position + shadow_offset(reach * (0.6 + 0.4 * float(i))), rect.size).grow(float(i)))


## A bevel round a raised rect: the edges facing the light lit, the others in shade.
static func bevel(ci: CanvasItem, rect: Rect2, width: float = 2.0, lit: Color = Color(1, 1, 1, 0.22), shade: Color = Color(0, 0, 0, 0.35)) -> void:
	var lit_right := LIGHT_FROM.x > 0.0
	var lit_bottom := LIGHT_FROM.y > 0.0
	ci.draw_rect(Rect2(rect.position, Vector2(rect.size.x, width)), shade if lit_bottom else lit)
	ci.draw_rect(Rect2(Vector2(rect.position.x, rect.end.y - width), Vector2(rect.size.x, width)), lit if lit_bottom else shade)
	ci.draw_rect(Rect2(rect.position, Vector2(width, rect.size.y)), shade if lit_right else lit)
	ci.draw_rect(Rect2(Vector2(rect.end.x - width, rect.position.y), Vector2(width, rect.size.y)), lit if lit_right else shade)


## The kit's red drawing pin (people_pin_red, a 36 layout px render at 2 texels a px) with its point at `at`.
static func pin(ci: CanvasItem, at: Vector2, layer: String = "people_pin_red", scale: float = 1.0) -> void:
	var t := tex(layer)
	if t == null:
		return
	var s := t.get_size() / 2.0 * scale
	ci.draw_texture_rect(t, Rect2(at - s * 0.5, s), false)


## A padlock `side` px tall centred on `c`, in `ink`.
static func padlock(ci: CanvasItem, c: Vector2, side: float, ink: Color) -> void:
	var body := Rect2(c + Vector2(-side * 0.42, -side * 0.08), Vector2(side * 0.84, side * 0.58))
	var arc_c := Vector2(c.x, body.position.y)
	ci.draw_arc(arc_c, side * 0.27, PI, TAU, 14, ink, maxf(1.6, side * 0.13), true)
	var sb := StyleBoxFlat.new()
	sb.bg_color = ink
	sb.set_corner_radius_all(int(maxf(1.0, side * 0.1)))
	ci.draw_style_box(sb, body)
	ci.draw_circle(body.get_center() + Vector2(0, -side * 0.04), side * 0.08, Color(0, 0, 0, 0.55))


## A rubber stamp: `word` in a double ruled box, `ink` uneven where the rubber missed the paper, turned `angle`
## radians about `centre`. `mark_seed` keeps each sheet's misses where they were.
static func stamp(ci: CanvasItem, centre: Vector2, size: Vector2, word: String, ink: Color, angle: float, mark_seed: int) -> void:
	ci.draw_set_transform(centre, angle, Vector2.ONE)
	var r := Rect2(-size * 0.5, size)
	var ink_a := Color(ink, 0.86)
	ci.draw_rect(r, ink_a, false, 3.0)
	ci.draw_rect(r.grow(-5.0), ink_a, false, 1.4)
	var sf := stamp_font()
	var fs := int(size.y * 0.66)
	var w := sf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	while w > size.x - 16.0 and fs > 10:
		fs -= 1
		w = sf.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var base := (sf.get_ascent(fs) - sf.get_descent(fs)) * 0.5
	ci.draw_string(sf, Vector2(-w * 0.5, base), word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, ink_a)
	# Where the rubber missed: small flecks of bare paper through the ink, the same for every draw of this sheet.
	var rng := RandomNumberGenerator.new()
	rng.seed = mark_seed
	for i in 46:
		var p := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y, r.end.y))
		ci.draw_circle(p, rng.randf_range(0.5, 1.5), Color(PAPER, rng.randf_range(0.45, 0.85)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## A red thread from `a` to `b`, sagging a little under its own weight, its shadow cast away from the light.
static func thread(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
	var sag := Vector2(0, clampf(a.distance_to(b) * 0.12, 6.0, 40.0))
	var mid := (a + b) * 0.5 + sag
	var pts := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + shadow_offset(3.0))
	ci.draw_polyline(shadow, Color(0, 0, 0, 0.32), 2.4, true)
	ci.draw_polyline(pts, THREAD_RED, 2.0, true)
	var hi := PackedVector2Array()
	for p in pts:
		hi.append(p + LIGHT_FROM * 0.5)
	ci.draw_polyline(hi, Color(1, 0.62, 0.55, 0.45), 0.7, true)


## `text` broken into at most `max_lines` lines `width` px wide at `size`; the last line ends in "..." if cut.
static func wrap(font: Font, text: String, width: float, size: int, max_lines: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var current := ""
	var words := text.split(" ", false)
	var i := 0
	while i < words.size():
		var cand := words[i] if current == "" else current + " " + words[i]
		if current != "" and font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines.append(current)
			current = words[i]
			if lines.size() == max_lines:
				break
		else:
			current = cand
		i += 1
	if lines.size() < max_lines and current != "":
		lines.append(current)
		i = words.size()
	if i < words.size() and lines.size() > 0:
		var last := lines[lines.size() - 1]
		while last != "" and font.get_string_size(last + "...", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			last = last.left(last.length() - 1)
		lines[lines.size() - 1] = last.strip_edges() + "..."
	return lines


## The largest size from `size` down to `smallest` at which `text` fits `max_lines` lines `width` wide (else `smallest`).
static func fit(font: Font, text: String, width: float, size: int, smallest: int, max_lines: int) -> int:
	for s in range(size, smallest - 1, -1):
		if _fits(font, text, width, s, max_lines):
			return s
	return smallest


static func _fits(font: Font, text: String, width: float, size: int, max_lines: int) -> bool:
	var lines := 1
	var current := ""
	for word in text.split(" ", false):
		if font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			return false
		var cand := word if current == "" else current + " " + word
		if current != "" and font.get_string_size(cand, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			lines += 1
			current = word
		else:
			current = cand
	return lines <= max_lines


## Lines of print from `top`, `pitch` apart, in `colour`, aligned in `width` from `x`.
static func print_lines(ci: CanvasItem, font: Font, lines: PackedStringArray, x: float, top: float, width: float, size: int,
		pitch: float, colour: Color, align := HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var asc := font.get_ascent(size)
	for i in lines.size():
		ci.draw_string(font, Vector2(x, top + asc + pitch * float(i)), lines[i], align, width, size, colour)
