extends Control
## Tile view v3, Power: the tile's balance as a meter panel. Two bars on one scale, the power your buildings
## produced over the power they consumed (the national grid row's words), each a lit strip on a mini screen
## (Building Detail's value bars: the same bezel and glass), a slice for each kind of building, produced in
## the value bars' revenue greens and consumed in their cost reds. Each slice is named on a tag: the
## building's raised emblem and a short name printed on the plate, joined to its slice by a leader line, the
## produced tags over the produced bar and the consumed tags under the consumed bar. Where the power produced
## ends is marked down across the consumed bar, so the gap between the two ends is the tile's net.
##
## The figures stand in one column at the right, each on a dot matrix screen in white (DS2: the seven
## segment LED is for money only) with its caption printed before it and MW after it: produced, consumed,
## and the net under a sum's rule, an amber or red mark before it when the tab's key shows one. A key set
## with set_key (Build power) stands over the column, over the PRODUCED figure it adds to, at the top of the
## meter: the produced tags (or an empty bar's note) share its band, centred on its midline, and the
## produced bar starts just under it, so the band holds no dead room.
##
## Hovering a slice or its tag names it with its MW; clicking opens it.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the screen's shadow room, bezel and pane radius.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0
## Drawn sizes, in logical pixels: a bar's height inside its bezel, the room between a bar and its tags
## (the leader lines run through it), the room before the captions, the column MW is printed in.
const BAR_H := 18.0
const LEAD := 9.0
const CAPTION_GAP := 14.0
const UNIT_W := 30.0
const LABEL_PX := 15
const BADGE_PX := 12
## A tag: its band's height, the emblem's box and cap height (DS2: emblems are sized by their drawn art, to
## one cap height, no wider than the box), the room between emblem and name, between a name and its count,
## and between tags.
const TAG_H := 30.0
const EMBLEM_W := 34.0
const CAP_H := 24.0
const NAME_GAP := 3.0
const PILL_GAP := 4.0
const TAG_GAP := 12.0
## How a row's tags are set, tried in turn until they fit along the bar: the emblem and the name, the name
## alone (what tells a factory making steel from one making motors), then the emblem alone.
const MODES := ["both", "name", "emblem"]
## Emblems whose art is mostly air (a turbine's blades, a solar panel's frame) stand a little taller, so
## they weigh as much as the solid ones.
const OPTICAL := {"b_024": 1.12, "b_025": 1.2, "b_026": 1.2, "b_028": 1.05}
## The room between the drawn figure's screen and the net's, where the sum's rule runs.
const NET_GAP := 9.0
const HOT := Color(1.22, 1.22, 1.22)
## The made slices lit in Building Detail's revenue greens, the drawn ones in its cost reds, each ramp ordered
## so that neighbouring slices differ in lightness.
const MADE := [Color("#3fb265"), Color("#23713d"), Color("#5fcf85"), Color("#2e8f4f")]
const DRAWN := [Color("#b03026"), Color("#6b1914"), Color("#d64a3a"), Color("#8e231b")]
## The room between the key over the figures and the MADE figure's screen under it.
const KEY_CLEAR := 4.0
const MARK := Color("#6be08f")
## The figures' dot pitch, the one the tab keys' display uses, and the net's status marks (the display's).
const DOT_PITCH := 2.6
const STATUS_MARK := {"warn": Color("#ffb21f"), "bad": Color("#ff3b2f")}
const FALLBACK_ICON := "res://assets/ui/bdp_v3/bar_icon_power.png"

## Two rows, made then drawn: {caption, slices: [{name, short, value, count, iid, building_id, colour,
## from, to, face, shadow, factor}]}, from and to as shares of the common scale.
var rows: Array = []
## Opens a building by instance id (the tile view's own opener).
var on_open: Callable
var _made_end := 0.0
## Per row, each tag's {i (its slice), x (its left edge), w, mode}.
var _tags: Array = [[], []]
## The screens and their units: made, drawn, net.
var _leds: Array[Control] = []
var _units: Array[Label] = []
var _layer: Control
var _glass: Control
var _hot := Vector2i(-1, -1)
## The key over the figures' column, or null.
var _key: Control
## What an empty bar says in its band of tags: [made, drawn], or "" for nothing.
var notes: Array = ["", ""]


func _init() -> void:
	name = "PowerMeter"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	_layer = Control.new()
	_layer.name = "Slices"
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.material = Light.emissive_material()
	_layer.draw.connect(_draw_slices)
	add_child(_layer)
	_glass = Control.new()
	_glass.name = "Glass"
	_glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glass.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glass.draw.connect(func() -> void:
		for i in rows.size():
			Nine.paint(_glass, GLASS, _bar_rect(i).grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner()))
	add_child(_glass)
	for i in 3:
		var led: Control = DotMatrix.new()
		led.name = ["MadeFigure", "DrawnFigure", "NetFigure"][i]
		led.set("pitch", DOT_PITCH)
		led.set("align", HORIZONTAL_ALIGNMENT_RIGHT)
		led.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(led)
		_leds.append(led)
		var unit := Label.new()
		unit.text = "MW"
		unit.add_theme_font_override("font", Plate.FONT_SEMI)
		unit.add_theme_font_size_override("font_size", LABEL_PX)
		unit.add_theme_color_override("font_color", DS.PALETTE.TEXT)
		unit.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		unit.add_theme_constant_override("shadow_offset_x", 1)
		unit.add_theme_constant_override("shadow_offset_y", 1)
		unit.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(unit)
		_units.append(unit)


## A key to stand over the figures' column, right-aligned to it at its own minimum width.
func set_key(key: Control) -> void:
	if _key != null:
		_key.queue_free()
	_key = key
	if key != null:
		add_child(key)
	_relayout()


## The readings. `made` and `drawn` are [{name, short, value, count, iid, building_id}], one per kind of
## building; `made_mw`, `drawn_mw` and `net_mw` the engine's per-tile figures, shown in white on the
## screens, padded to one width. `net_tone` (warn or bad) puts the tab key's amber or red mark before the
## net, as the key's own display does.
func set_reading(made: Array, drawn: Array, made_mw: int, drawn_mw: int, net_mw: int, net_tone := "") -> void:
	var made_sum := 0.0
	for s: Dictionary in made:
		made_sum += float(s.value)
	var drawn_sum := 0.0
	for s: Dictionary in drawn:
		drawn_sum += float(s.value)
	var span := maxf(maxf(float(made_mw), float(drawn_mw)), maxf(made_sum, drawn_sum))
	rows = [
		{"caption": "Produced", "slices": _slices(made, span, MADE)},
		{"caption": "Consumed", "slices": _slices(drawn, span, DRAWN)},
	]
	_made_end = float(made_mw) / span if span > 0.0 else 0.0
	var texts := [str(made_mw), str(drawn_mw), str(net_mw)]
	var mark := "● " if STATUS_MARK.has(net_tone) else ""
	var chars := 1
	for i in 3:
		chars = maxi(chars, str(texts[i]).length() + (mark.length() if i == 2 else 0))
	for i in 3:
		var text := str(texts[i])
		var pad := " ".repeat(maxi(0, chars - text.length() - (mark.length() if i == 2 else 0)))
		var runs: Array = [{"text": pad, "colour": Color.WHITE}]
		if i == 2 and mark != "":
			runs.append({"text": mark, "colour": STATUS_MARK[net_tone]})
		runs.append({"text": text, "colour": Color.WHITE})
		_leds[i].call("set_runs", runs)
	_relayout()


## The figure a screen shows, without its padding or mark: made 0, drawn 1, net 2.
func figure(i: int) -> String:
	return str(_leds[i].get("text")).replace("● ", "").strip_edges()


static func _slices(parts: Array, span: float, inks: Array) -> Array:
	var out: Array = []
	var at := 0.0
	for i in parts.size():
		var p: Dictionary = parts[i]
		var v := maxf(0.0, float(p.value))
		if v <= 0.0 or span <= 0.0:
			continue
		var s := p.duplicate()
		s.colour = inks[out.size() % inks.size()]
		s.from = at / span
		s.to = (at + v) / span
		var bid := str(p.get("building_id", ""))
		var face_path := "res://assets/ui/bdp_v3/bld_emblem_%s.png" % bid
		if not ResourceLoader.exists(face_path):
			face_path = FALLBACK_ICON
		s.face = load(face_path)
		var shadow_path := face_path.replace(".png", "_shadow.png")
		s.shadow = load(shadow_path) if ResourceLoader.exists(shadow_path) else null
		s.factor = float(OPTICAL.get(bid, 1.0))
		out.append(s)
		at += v
	return out


func _relayout() -> void:
	_layout_tags(0)
	_layout_tags(1)
	custom_minimum_size = Vector2(0.0, _height())
	_place()
	queue_redraw()
	_layer.queue_redraw()
	_glass.queue_redraw()


# ── Geometry ────────────────────────────────────────────────────────────────────────────────────────────

func _frame_h() -> float:
	return BAR_H + 2.0 * (SCREEN_RIM / CAPTURE_SCALE + 2.0)


func _led_h() -> float:
	return _leds[0].custom_minimum_size.y


func _led_w() -> float:
	var w := 0.0
	for led in _leds:
		w = maxf(w, led.custom_minimum_size.x)
	return w


## The left edge of the figures' screens.
func _figure_x() -> float:
	return size.x - UNIT_W - _led_w()


func _caption_w() -> float:
	var font: Font = Plate.FONT_SEMI
	var w := 0.0
	for c in ["PRODUCED", "CONSUMED", "NET"]:
		w = maxf(w, font.get_string_size(c, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x)
	return w


## The bars' column: from the plate's left edge to the captions.
func _bar_x1() -> float:
	return maxf(80.0, _figure_x() - 8.0 - _caption_w() - CAPTION_GAP)


## The room over the made bar: a band for its tags (or its note, when it is empty) and the key over the
## figures. With a key, the tags are centred on the key's midline and the bar starts as soon as the MADE
## figure's screen clears the key.
func _top() -> float:
	var banded := _has_tags(0) or str(notes[0]) != ""
	if _key == null:
		return (TAG_H + LEAD) if banded else 4.0
	var top := (_band_y(0) + TAG_H + LEAD) if banded else 0.0
	return maxf(top, _key_h() + KEY_CLEAR + (_led_h() - _frame_h()) * 0.5)


func _key_h() -> float:
	return _key.get_combined_minimum_size().y if _key != null else 0.0


func _has_tags(row: int) -> bool:
	return rows.size() > row and not (rows[row].slices as Array).is_empty()


## The two bars sit close, a screen's height plus a little between their centres, so the screens beside
## them stand one over the other.
func _bar_rect(row: int) -> Rect2:
	var pitch := maxf(_frame_h() + 8.0, _led_h() + 4.0)
	return Rect2(0.0, _top() + (pitch if row == 1 else 0.0), _bar_x1(), _frame_h())


## The pane a row's slices fill, inside its bezel.
func _pane(row: int) -> Rect2:
	return _bar_rect(row).grow(-(SCREEN_RIM / CAPTURE_SCALE + 2.0))


func _corner() -> float:
	return (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * 2.0 / CAPTURE_SCALE


## The net's screen: centred a screen's height and a rule's room below the drawn one.
func _net_y() -> float:
	return _bar_rect(1).get_center().y + _led_h() + NET_GAP


## The top of a row's band of tags: over the made bar (on the key's midline when there is a key), under
## the drawn one.
func _band_y(row: int) -> float:
	if row == 1:
		return _bar_rect(1).end.y + LEAD
	if _key != null:
		return maxf(0.0, (_key_h() - TAG_H) * 0.5)
	return maxf(0.0, _top() - TAG_H - LEAD)


func _height() -> float:
	if rows.size() < 2:
		return 0.0
	var foot := _net_y() + _led_h() * 0.5 + 2.0
	if _has_tags(1) or str(notes[1]) != "":
		foot = maxf(foot, _band_y(1) + TAG_H + 2.0)
	return foot


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()
	elif what == NOTIFICATION_MOUSE_EXIT and _hot != Vector2i(-1, -1):
		_hot = Vector2i(-1, -1)
		queue_redraw()


## Each screen at its bar's height, MW printed after it; the net's under them; the key over them.
func _place() -> void:
	if rows.size() < 2:
		return
	if _key != null:
		var ks := _key.get_combined_minimum_size()
		_key.size = ks
		_key.position = Vector2(size.x - ks.x, 0.0)
	var x := _figure_x()
	for i in 3:
		var mid := _net_y() if i == 2 else _bar_rect(i).get_center().y
		var led := _leds[i]
		led.size = led.custom_minimum_size
		led.position = Vector2(x + _led_w() - led.size.x, mid - led.size.y * 0.5)
		var unit := _units[i]
		unit.size = unit.get_minimum_size()
		unit.position = Vector2(size.x - UNIT_W + 4.0, mid - unit.size.y * 0.5)


# ── Tags ────────────────────────────────────────────────────────────────────────────────────────────────

func _name_w(s: Dictionary) -> float:
	var font: Font = Plate.FONT_SEMI
	return font.get_string_size(str(s.get("short", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x


## The count's pill: its width, or 0 for a kind of one building.
static func _pill_w(s: Dictionary) -> float:
	if int(s.get("count", 1)) <= 1:
		return 0.0
	var font: Font = Plate.FONT_BOLD
	return maxf(16.0, font.get_string_size(str(int(s.count)), HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_PX).x + 9.0)


## A tag's width in a mode, and where along it its leader line starts (over the emblem, or the name's middle).
func _tag_w(s: Dictionary, mode: String) -> float:
	match mode:
		"both":
			return EMBLEM_W + NAME_GAP + _name_w(s)
		"name":
			var pill := _pill_w(s)
			return _name_w(s) + (PILL_GAP + pill if pill > 0.0 else 0.0)
	return EMBLEM_W


func _anchor(s: Dictionary, mode: String) -> float:
	return _name_w(s) * 0.5 if mode == "name" else EMBLEM_W * 0.5


## Sets a row's tags along its bar in one line: each wants its anchor over its slice's middle, and they are
## pushed apart so none overlap, kept inside the bar's column. The first of MODES that fits is used for the
## whole row; the tooltip names every slice whatever the mode.
func _layout_tags(row: int) -> void:
	_tags[row] = []
	if not _has_tags(row) or size.x <= 0.0:
		return
	var slices: Array = rows[row].slices
	var pane := _pane(row)
	var x1 := _bar_x1()
	for mode: String in MODES:
		var want: Array = []
		var widths: Array = []
		var total := TAG_GAP * float(slices.size() - 1)
		for s: Dictionary in slices:
			var w := _tag_w(s, mode)
			var mid := pane.position.x + pane.size.x * (float(s.from) + float(s.to)) * 0.5
			want.append(mid - _anchor(s, mode))
			widths.append(w)
			total += w
		if total > x1 + 0.5 and mode != MODES[-1]:
			continue
		var xs := _spread(want, widths, 0.0, x1) if total <= x1 + 0.5 else _pack(widths)
		for i in slices.size():
			_tags[row].append({"i": i, "x": xs[i], "w": widths[i], "mode": mode})
		return


## Too many kinds even for bare emblems: set them edge to edge from the left.
static func _pack(widths: Array) -> Array:
	var xs: Array = []
	var x := 0.0
	for w: float in widths:
		xs.append(x)
		x += w
	return xs


## Left edges as near `want` as they can be without overlapping, inside [x0, x1].
static func _spread(want: Array, widths: Array, x0: float, x1: float) -> Array:
	var xs := want.duplicate()
	var n := xs.size()
	for _pass in 6:
		for i in n:
			var lo := x0 if i == 0 else float(xs[i - 1]) + float(widths[i - 1]) + TAG_GAP
			xs[i] = maxf(float(xs[i]), lo)
		for i in range(n - 1, -1, -1):
			var hi := x1 - float(widths[i]) if i == n - 1 else float(xs[i + 1]) - TAG_GAP - float(widths[i])
			xs[i] = minf(float(xs[i]), hi)
	return xs


func _tag_rect(row: int, t: Dictionary) -> Rect2:
	return Rect2(float(t.x), _band_y(row), float(t.w), TAG_H)


# ── Drawing ─────────────────────────────────────────────────────────────────────────────────────────────

func _draw() -> void:
	if rows.size() < 2:
		return
	for r in 2:
		var bar := _bar_rect(r)
		Nine.paint(self, SCREEN, bar.grow(SCREEN_MARGIN / CAPTURE_SCALE), _corner())
		_print_caption(str(rows[r].caption), bar.get_center().y)
		var pane := _pane(r)
		if (rows[r].slices as Array).is_empty() and str(notes[r]) != "":
			_print_note(str(notes[r]), Rect2(pane.position.x, _band_y(r), pane.size.x, TAG_H))
		for t: Dictionary in _tags[r]:
			var s: Dictionary = rows[r].slices[int(t.i)]
			var rect := _tag_rect(r, t)
			var ex := rect.position.x + _anchor(s, str(t.mode))
			var slice_x := pane.position.x + pane.size.x * (float(s.from) + float(s.to)) * 0.5
			# The leader line, from the emblem's foot (or head) to its slice's edge of the bar.
			var a := Vector2(ex, rect.end.y + 1.0) if r == 0 else Vector2(ex, rect.position.y - 1.0)
			var b := Vector2(slice_x, bar.position.y + 1.0) if r == 0 else Vector2(slice_x, bar.end.y - 1.0)
			_leader(a, b)
			_draw_tag(s, t, rect, _hot == Vector2i(r, int(t.i)))
	_print_caption("Net", _net_y())
	# The sum's rule, engraved across the screens' column between the drawn figure and the net.
	var y := roundf((_leds[1].position.y + _leds[1].size.y + _leds[2].position.y) * 0.5) + 0.5
	var x0 := _figure_x() - 8.0 - _caption_w()
	draw_line(Vector2(x0, y), Vector2(size.x - 4.0, y), Color(0, 0, 0, 0.6), 1.0)
	draw_line(Vector2(x0, y + 1.0), Vector2(size.x - 4.0, y + 1.0), Color(1, 1, 1, 0.16), 1.0)


## A leader line with an elbow: straight down (or up) from the tag, then across to its slice when the tag
## was pushed aside.
func _leader(a: Vector2, b: Vector2) -> void:
	var ink := Color(1, 1, 1, 0.42)
	if absf(a.x - b.x) < 1.5:
		draw_line(a, Vector2(a.x, b.y), ink, 1.0, true)
		return
	var knee_y := lerpf(a.y, b.y, 0.45)
	draw_polyline(PackedVector2Array([a, Vector2(a.x, knee_y), Vector2(b.x, knee_y), b]), ink, 1.0, true)


## A caption printed on the plate just before its screen, in capitals, standing off the metal.
func _print_caption(text: String, mid_y: float) -> void:
	var font: Font = Plate.FONT_SEMI
	var label := text.to_upper()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x
	var x := _figure_x() - 8.0 - w
	var base := mid_y + (font.get_ascent(LABEL_PX) - font.get_descent(LABEL_PX)) * 0.5
	draw_string(font, Vector2(x + 1.0, base + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX, DS.PALETTE.TEXT)


## An empty bar's note, printed on the plate in its band of tags, centred over the bar.
func _print_note(text: String, band: Rect2) -> void:
	var font: Font = Plate.FONT_SEMI
	var label := text.to_upper()
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX).x
	var x := band.position.x + (band.size.x - w) * 0.5
	var base := band.get_center().y + (font.get_ascent(LABEL_PX) - font.get_descent(LABEL_PX)) * 0.5
	draw_string(font, Vector2(x + 1.0, base + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX, Color(0, 0, 0, 0.9))
	draw_string(font, Vector2(x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX, DS.PALETTE.TEXT)


## A tag: the emblem drawn by its art to the cap height on the band's midline, and its short name printed
## after it. A kind with more than one building carries the count in a navy pill, as a good's quantity is:
## inside the emblem's corner (DS2 rule 7), or after the name when the tag is the name alone.
func _draw_tag(s: Dictionary, t: Dictionary, rect: Rect2, hot: bool) -> void:
	var mode := str(t.mode)
	var face: Texture2D = s.get("face")
	if face != null and mode != "name":
		var art := Indicator.art_rect(face)
		var k := CAP_H * float(s.get("factor", 1.0)) / maxf(art.size.y, 1.0)
		if art.size.x * k > EMBLEM_W + 4.0:
			k = (EMBLEM_W + 4.0) / art.size.x
		var art_size := art.size * k
		var at := Vector2(rect.position.x + (EMBLEM_W - art_size.x) * 0.5, rect.get_center().y - art_size.y * 0.5)
		var dest := Rect2(at - art.position * k, face.get_size() * k)
		var shadow: Texture2D = s.get("shadow")
		if shadow != null:
			draw_texture_rect(shadow, dest, false)
		draw_texture_rect(face, dest, false, HOT if hot else Color.WHITE)
	var name_x := rect.position.x + (EMBLEM_W + NAME_GAP if mode == "both" else 0.0)
	if mode != "emblem":
		var font: Font = Plate.FONT_SEMI
		var label := str(s.get("short", "")).to_upper()
		var base := rect.get_center().y + (font.get_ascent(LABEL_PX) - font.get_descent(LABEL_PX)) * 0.5
		draw_string(font, Vector2(name_x + 1.0, base + 1.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX, Color(0, 0, 0, 0.9))
		draw_string(font, Vector2(name_x, base), label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_PX,
			DS.PALETTE.TEXT * HOT if hot else DS.PALETTE.TEXT)
	var pw := _pill_w(s)
	if pw <= 0.0:
		return
	var pill := Rect2(rect.position.x + EMBLEM_W - pw, rect.end.y - 16.0, pw, 16.0)
	if mode == "name":
		pill = Rect2(name_x + _name_w(s) + PILL_GAP, rect.get_center().y - 8.0, pw, 16.0)
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE.BG_PANEL
	st.set_corner_radius_all(8)
	st.set_border_width_all(1)
	st.border_color = DS.PALETTE.BORDER_STRONG
	draw_style_box(st, pill)
	var font: Font = Plate.FONT_BOLD
	var text := str(int(s.count))
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_PX).x
	var base := pill.get_center().y + (font.get_ascent(BADGE_PX) - font.get_descent(BADGE_PX)) * 0.5
	draw_string(font, Vector2(pill.get_center().x - tw * 0.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, BADGE_PX, DS.PALETTE.ACCENT)


func _draw_slices() -> void:
	if rows.size() < 2:
		return
	for r in 2:
		var pane := _pane(r)
		for s: Dictionary in rows[r].slices:
			var x0 := pane.position.x + pane.size.x * float(s.from)
			var x1 := pane.position.x + pane.size.x * float(s.to)
			var rect := Rect2(x0, pane.position.y, maxf(x1 - x0, 1.0), pane.size.y)
			_layer.draw_rect(rect, s.colour)
			# A little light along the top of each slice and shade along its foot, so it reads as lit.
			_layer.draw_rect(Rect2(rect.position, Vector2(rect.size.x, rect.size.y * 0.35)), Color(1, 1, 1, 0.12))
			_layer.draw_rect(Rect2(rect.position + Vector2(0.0, rect.size.y * 0.75), Vector2(rect.size.x, rect.size.y * 0.25)), Color(0, 0, 0, 0.18))
			if x0 > pane.position.x + 0.5:
				_layer.draw_line(Vector2(x0, rect.position.y), Vector2(x0, rect.end.y), Color(0, 0, 0, 0.6), 1.0)
	if _made_end > 0.0 and not (rows[1].slices as Array).is_empty() and _made_end < 0.999:
		# Where the power made ends, marked down from the made bar across the drawn one: a dark notch with a
		# green hairline in it.
		var made := _pane(0)
		var drawn := _pane(1)
		var mx := roundf(made.position.x + made.size.x * _made_end) + 0.5
		_layer.draw_line(Vector2(mx, drawn.position.y - 2.0), Vector2(mx, drawn.end.y + 2.0), Color(0, 0, 0, 0.7), 3.0)
		var y := made.end.y + 2.0
		while y < drawn.end.y + 2.0:
			_layer.draw_line(Vector2(mx, y), Vector2(mx, minf(y + 3.0, drawn.end.y + 2.0)), MARK, 1.0)
			y += 5.0


# ── Hover and click ─────────────────────────────────────────────────────────────────────────────────────

## The slice or tag under a point: (row, index), or (-1, -1).
func _hit(at: Vector2) -> Vector2i:
	for r in rows.size():
		var pane := _pane(r)
		for t: Dictionary in _tags[r]:
			if _tag_rect(r, t).grow(2.0).has_point(at):
				return Vector2i(r, int(t.i))
		for i in (rows[r].slices as Array).size():
			var s: Dictionary = rows[r].slices[i]
			var bar := Rect2(pane.position.x + pane.size.x * float(s.from), pane.position.y - 3.0,
				pane.size.x * (float(s.to) - float(s.from)), pane.size.y + 6.0)
			if bar.has_point(at):
				return Vector2i(r, i)
	return Vector2i(-1, -1)


func _gui_input(event: InputEvent) -> void:
	var mm := event as InputEventMouseMotion
	if mm != null:
		var hit := _hit(mm.position)
		if hit != _hot:
			_hot = hit
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hit.x >= 0 else Control.CURSOR_ARROW
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb == null or mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	var hit := _hit(mb.position)
	if hit.x < 0 or not on_open.is_valid():
		return
	accept_event()
	on_open.call(str(rows[hit.x].slices[hit.y].get("iid", "")))


func _get_tooltip(at_position: Vector2) -> String:
	var hit := _hit(at_position)
	if hit.x < 0:
		return ""
	var s: Dictionary = rows[hit.x].slices[hit.y]
	var verb := "produced" if hit.x == 0 else "consumed"
	var count := int(s.get("count", 1))
	if count == 1:
		return "%s %s %d MW.\nClick to open it." % [str(s.name), verb, int(s.value)]
	return "%d %s %s %d MW between them.\nClick to open one." % [count, str(s.name), verb, int(s.value)]
