extends RefCounted
## Tile view v3, the Goods tab: the small parts its body is built from, each one Building Detail v3's
## (docs/ds2-theme.md §5), made the way that panel makes it so the two read as one family. The tab's layout
## is in goods_tab.gd.

const Heading := preload("res://scripts/bdp_v3_heading.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Counter := preload("res://scripts/bdp_v3_counter.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const Door := preload("res://scripts/bdp_v3_door.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const CabinetKey := preload("res://scripts/tile_cabinet_key.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

## The owner's text standard: body 14 (a row's own title semibold), captions 15 in Barlow capitals, the
## printed £ 18, emphasis 17 as Building Detail's Net Value Added.
const BODY_PX := 14
const CAPTION_PX := 15
const POUND_PX := 18
const STRONG_PX := 17
## The thin metal frame round a good's icon (layout.json icon_well), as Building Detail sets its goods.
const WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const WELL_REACH := (12.0 + 7.0) / 1.875
const WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const WELL_RADIUS := 10.0 / 1.875
## Navy print on a light surface (DS2 rule 3), as the keys print their words.
const NAVY := Color("#0b2340")
## The room between a printed £ and its screen.
const POUND_GAP := 4
## Building Detail's raised polished-metal building emblems.
const EMBLEM := "res://assets/ui/bdp_v3/bld_emblem_%s.png"
## A cabinet key's room either side of its print, beyond the face's own inset, so its label is not fitted
## down.
const KEY_PRINT_ROOM := 12.0
## The sign screwed onto a shut door: its print's room from the plate's edges, clear of the corner screws.
const SIGN_PAD := Vector2(30.0, 13.0)
## The shut door: the room above and below its sign, over the slats.
const SIGN_MARGIN := 9.0

## The widths `money_width` has measured, by cell count (each measure makes a screen to read its size).
static var _money_widths := {}


## A caption printed on the steel: Barlow Condensed SemiBold capitals in off-white (Building Detail's
## `_v3_metal_label`).
static func metal_label(text: String, align := HORIZONTAL_ALIGNMENT_LEFT, px := CAPTION_PX) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.horizontal_alignment = align
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Body text in white on the dark steel: IBM Plex Sans, Medium or (a row's own title) SemiBold. Trimmed
## with an ellipsis rather than widening the body, or with `wrap` broken over as many lines as it needs.
static func body(text: String, semibold := false, px := BODY_PX, wrap := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_SEMI if semibold else UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## The width `text` takes as body print.
static func body_width(text: String, semibold := false, px := BODY_PX) -> float:
	var font: Font = UIFonts.PLEX_SEMI if semibold else UIFonts.PLEX_MED
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## A section's heading in raised white letters (Building Detail's INPUTS, DIAGNOSTICS), then a caption
## over each of the rows' right hand columns: `columns` is [[caption, width], ...] from left to right, each
## caption centred over its column ("" for a column with none), `gap` apart as the rows' columns are. A
## third figure, [caption, width, figure width], centres the caption over a figure standing at the
## column's right edge. Falls back to a plain label for a character the letters lack.
static func heading_row(text: String, columns := [], gap := 12) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "Heading"
	hb.add_theme_constant_override("separation", gap)
	if Heading.can_show(text):
		var raised: Control = Heading.new()
		raised.text = text
		hb.add_child(raised)
	else:
		hb.add_child(metal_label(text))
	hb.add_child(spacer(0.0, true))
	for c: Array in columns:
		var cap := metal_label(str(c[0]), HORIZONTAL_ALIGNMENT_CENTER)
		cap.name = "Caption"
		cap.size_flags_vertical = Control.SIZE_SHRINK_END
		var over := float(c[2]) if c.size() > 2 else float(c[1])
		cap.custom_minimum_size.x = over
		if over >= float(c[1]) - 0.5:
			hb.add_child(cap)
			continue
		var col := HBoxContainer.new()
		col.name = "CaptionColumn"
		col.alignment = BoxContainer.ALIGNMENT_END
		col.custom_minimum_size.x = float(c[1])
		col.size_flags_vertical = Control.SIZE_SHRINK_END
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_child(cap)
		hb.add_child(col)
	return hb


## `child` at the right edge of a column `width` wide, so a column's figures, each as wide as its own
## value, share one right edge.
static func at_end(child: Control, width: float, column_name := "Column") -> HBoxContainer:
	var col := HBoxContainer.new()
	col.name = column_name
	col.alignment = BoxContainer.ALIGNMENT_END
	col.custom_minimum_size.x = width
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(child)
	return col


## Empty room in a row: `width` wide, or all the room left with `expand`.
static func spacer(width: float, expand := false) -> Control:
	var room := Control.new()
	room.name = "Room"
	room.custom_minimum_size.x = width
	room.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand:
		room.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return room


## The cells a money figure takes on its screen, for sizing a group of screens to one width.
static func money_cells(figure: float) -> int:
	return Led.cells_for("%.2f" % figure).size()


## A £ figure as Building Detail shows money: a printed £, then the figure on an LED screen in `colour`,
## padded to `digits` cells (blank ones leading) so a column of them is one width and the £ signs line up.
## With `digits` the control is `money_width(digits)` wide, the screen at its right edge.
static func money(figure: float, colour: Color, digits := 0) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "MoneyLed"
	hb.add_theme_constant_override("separation", POUND_GAP)
	if digits > 0:
		hb.alignment = BoxContainer.ALIGNMENT_END
		hb.custom_minimum_size.x = money_width(digits)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pound := metal_label("£", HORIZONTAL_ALIGNMENT_RIGHT, POUND_PX)
	hb.add_child(pound)
	var led: Control = Led.new()
	var text := "%.2f" % (0.0 if is_zero(figure) else figure)
	led.call("set_figure", " ".repeat(maxi(0, digits - Led.cells_for(text).size())) + text, colour)
	hb.add_child(led)
	return hb


## The width `money` takes at `digits` cells: the printed £, the gap and the screen.
static func money_width(digits: int) -> float:
	digits = maxi(1, digits)
	if _money_widths.has(digits):
		return float(_money_widths[digits])
	# Money always shows pence, so its screen has a lit point, which takes room of its own.
	var probe: Control = Led.new()
	probe.call("set_figure", "0".repeat(maxi(1, digits - 2)) + ".00", Color.WHITE)
	var w: float = probe.custom_minimum_size.x
	probe.free()
	var out := ceilf(Plate.FONT_SEMI.get_string_size("£", HORIZONTAL_ALIGNMENT_LEFT, -1, POUND_PX).x + POUND_GAP + w)
	_money_widths[digits] = out
	return out


## True when a £ figure shows as nothing at two places.
static func is_zero(figure: float) -> bool:
	return absf(figure) < 0.005


## Green for a result above nothing, red below it (DS2 rule 5), and nothing itself in plain white, as
## Building Detail lights a figure that is neither good nor bad: a sale of nothing is not good news.
static func result_colour(figure: float) -> Color:
	if is_zero(figure):
		return DS.PALETTE.TEXT
	return DS.PALETTE.OK if figure > 0.0 else DS.PALETTE.DANGER


## How much larger than Building Detail's the tab draws its drum counters: to the height of its LED
## screens, so a row's units and its £ stand one height on one midline.
static func drum_scale() -> float:
	var screen := Led.CELL.y + 2.0 * Led.PAD.y + 2.0 * Led.RIM / Led.CAPTURE_SCALE
	return screen / (Counter.HEIGHT / Counter.CAPTURE_SCALE)


## A drum counter showing `value` on `drums` drums, drawn at `drum_scale`. It rolls from the reading the
## panel last showed under `key`, so a figure that changes with the turn turns over like an odometer; the
## readings are kept on the panel, which outlives each rebuild of the tab.
static func counter(panel: Control, key: String, value: float, drums: int) -> Control:
	var c: Control = Counter.new()
	c.call("configure", drums, 0)
	var readings: Dictionary = panel.get_meta("tvp_prod_readings", {})
	c.call("set_value", value, float(readings[key]) if readings.has(key) else NAN)
	readings[key] = value
	panel.set_meta("tvp_prod_readings", readings)
	var k := drum_scale()
	var mount := Control.new()
	mount.name = "Drums"
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mount.custom_minimum_size = c.custom_minimum_size * k
	c.scale = Vector2(k, k)
	mount.add_child(c)
	return mount


## The width of a drum counter with `drums` drums, as `counter` draws it.
static func counter_width(drums: int) -> float:
	return (2.0 * Counter.CAP + drums * Counter.CELL) / Counter.CAPTURE_SCALE * drum_scale()


## True when the good has art to show.
static func has_icon(good_id: String) -> bool:
	var internal := str(Catalog.get_good(good_id).get("internal_name", ""))
	return GoodIcons.texture_for_size(good_id, internal, 64.0) != null


## The thin metal frame of a well, laid over `host` and reaching just beyond it.
static func _frame(host: Control) -> void:
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		Nine.paint(well, WELL, Rect2(Vector2.ZERO, well.size).grow(WELL_REACH), WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	host.add_child(well)


## A good's cream icon tile set below a thin metal frame (Building Detail's `_v3_set_in_well`), no pill:
## its quantity is on a drum beside it. Hovering names the good with `lines` under it; a click opens it in
## the encyclopedia, as every good's icon does.
static func good_in_well(good_id: String, px: int, lines := PackedStringArray()) -> Control:
	var internal := str(Catalog.get_good(good_id).get("internal_name", ""))
	var icon := UIHelpers.make_plain_good_icon(good_id, internal, px)
	var tile := icon.get_child(0) as PanelContainer
	if tile != null and tile.get_theme_stylebox("panel") is StyleBoxFlat:
		var st := (tile.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.set_corner_radius_all(roundi(WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", st)
	_frame(icon)
	if icon.get("detail_lines") != null:
		icon.set("detail_lines", lines)
	UIHelpers.link_good_icon_to_encyclopedia(icon, good_id)
	return icon


## The same well for a deposit whose good has no art: the cream tile with the good's name printed on it in
## navy capitals, so the row keeps its icon's place and says plainly what the ground holds.
static func named_well(text: String, px: int) -> Control:
	var root := Control.new()
	root.name = "NamedWell"
	root.custom_minimum_size = Vector2(px, px)
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tile := Panel.new()
	tile.set_anchors_preset(Control.PRESET_FULL_RECT)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st := StyleBoxFlat.new()
	st.bg_color = UIHelpers.PILL_PAPER
	st.set_corner_radius_all(roundi(WELL_RADIUS))
	tile.add_theme_stylebox_override("panel", st)
	root.add_child(tile)
	var l := Label.new()
	l.text = text.to_upper()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.offset_left = 4
	l.offset_right = -4
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", CAPTION_PX)
	l.add_theme_constant_override("line_spacing", -3)
	l.add_theme_color_override("font_color", NAVY)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(l)
	_frame(root)
	return root


## A raised render (a face and its swept shadow), scaled so its art, not its canvas, fills a `px` box:
## centred across and standing on the box's foot, as Building Detail's diagnostics icons stand. The shadow
## is the face's `_shadow` twin, or for a layer of Building Detail's control plate its `block_shadow_` one.
static func raised(face_path: String, px: float) -> Control:
	var box := Control.new()
	box.name = "Raised"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	box.custom_minimum_size = Vector2(px, px)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not ResourceLoader.exists(face_path):
		return box
	var face: Texture2D = load(face_path)
	var shadow_path := face_path.replace("/block_", "/block_shadow_") if face_path.contains("/block_") \
		else face_path.replace(".png", "_shadow.png")
	var shadow: Texture2D = load(shadow_path) if ResourceLoader.exists(shadow_path) else null
	box.draw.connect(func() -> void:
		var art := Indicator.art_rect(face)
		var k := px / maxf(art.size.x, art.size.y)
		var art_size := art.size * k
		var at := Vector2((box.size.x - art_size.x) * 0.5, (box.size.y + px) * 0.5 - art_size.y)
		var rect := Rect2(at - art.position * k, face.get_size() * k)
		if shadow != null:
			box.draw_texture_rect(shadow, rect, false)
		box.draw_texture_rect(face, rect, false))
	return box


## A raised mark centred in a row's icon column, `column` wide: how every row that is not a good holds
## its place beside the goods' wells, so the rows' text starts at one x.
static func mark(face_path: String, px: float, column: float) -> Control:
	var slot := CenterContainer.new()
	slot.name = "Mark"
	slot.custom_minimum_size = Vector2(column, 0)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.add_child(raised(face_path, px))
	return slot


## The scale that stands Building Detail's wide key (`BdpV3ModKey`) at the cabinet's own keys' height
## (`tile_cabinet_key.gd`, Build), so every key in the tab is one height and a column of them one rail.
static func key_scale() -> float:
	var cabinet := (CabinetKey.HEIGHT - 2.0 * CabinetKey.KEY_INSET) / CabinetKey.CAPTURE_SCALE
	var wide := (ModKey.HEIGHT - 2.0 * ModKey.KEY_INSET) / ModKey.CAPTURE_SCALE
	return cabinet / wide


## Building Detail's wide worn-white key printing `title` in navy with its chevron, inside a real Button
## named `button_name` (the top bar's keycap buttons), so a test or the tutorial can find and press it.
## The key presses down while held.
static func _wide_key(title: String, key_scale: float, button_name: String) -> Button:
	var b := Button.new()
	b.name = button_name
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, empty)
	var key: Control = ModKey.new()
	key.set("summary", title)
	key.set("key_scale", key_scale)
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	key.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	b.add_child(key)
	b.custom_minimum_size = Vector2(0.0, key.custom_minimum_size.y)
	b.button_down.connect(func() -> void:
		key.set("_held", true)
		key.queue_redraw())
	b.button_up.connect(func() -> void:
		key.set("_held", false)
		key.queue_redraw())
	return b


## A key that goes somewhere: the wide key with its chevron pointing on (as Building Detail's economics
## rows open), which calls `on_press`. Every key in the tab that opens a building is one of these; keys
## that act (Build) are the cabinet's own, in capitals.
static func link_button(title: String, key_scale: float, button_name: String, on_press: Callable) -> Button:
	var b := _wide_key(title, key_scale, button_name)
	b.pressed.connect(on_press)
	return b


## A key that folds open what explains its figure, as Building Detail's Value added in production: the
## wide key, latched down with its chevron pointing down while `open`. Pressing it flips it and calls
## `on_toggle` with the new state.
static func fold_button(title: String, key_scale: float, button_name: String, open: bool, on_toggle: Callable) -> Button:
	var b := _wide_key(title, key_scale, button_name)
	var key := b.get_child(0) as Control
	key.call("set_open", open)
	b.pressed.connect(func() -> void:
		var now := not bool(key.get("open"))
		key.call("set_open", now)
		on_toggle.call(now))
	return b


## The width a wide key needs to print `title` at its full size, chevron and rims included.
static func link_key_width(title: String, key_scale: float) -> float:
	var print_w := Plate.FONT_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(22 * key_scale)).x
	return print_w + (34.0 + 2.0 * ModKey.FACE_INSET / ModKey.CAPTURE_SCALE) * key_scale


## The width a cabinet key (`tile_cabinet_key.gd`, as Buy Land) needs to print `text` at its full size.
static func cabinet_key_width(text: String) -> float:
	var print_w := Plate.FONT_SEMI.get_string_size(text.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, CabinetKey.LABEL_PX).x
	return print_w + 6.0 + 2.0 * CabinetKey.FACE_INSET / CabinetKey.CAPTURE_SCALE + 2.0 * KEY_PRINT_ROOM


## The bay's rolling door rolled up under the heading while goods are made (Building Detail's shipments
## bay with every row in use): its housing with the bottom bar tucked under it, reaching `reach` beyond
## its sides to the frame's rim, and shading the top of the bay. The same door `shut_door` lets down.
static func rolled_door(reach: float) -> Control:
	var door: Control = Door.new()
	door.name = "RolledDoor"
	door.set("reach", reach)
	door.custom_minimum_size.y = Door.rolled_up_height()
	return door


## A bay's rolling door let down to its foot over an empty bay (Building Detail's shipments door,
## `BdpV3Door`), with `note` on a small dark plate screwed to its slats: the bay's own way of saying why
## nothing is in it. The door is `height` tall in its row and reaches `reach` beyond its sides and its foot
## to the frame's rim, so it closes the bay from the heading's groove to the rim.
static func shut_door(note: String, reach: float) -> Control:
	var door := Control.new()
	door.name = "ShutDoor"
	door.mouse_filter = Control.MOUSE_FILTER_IGNORE
	door.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	door.draw.connect(func() -> void:
		Door.paint(door, Rect2(-reach, 0.0, door.size.x + 2.0 * reach, door.size.y + reach)))
	door.resized.connect(door.queue_redraw)
	var housing := Door.TOP / Door.CAPTURE_SCALE
	var foot_bar := Door.BOTTOM / Door.CAPTURE_SCALE
	var plate := sign_plate(note)
	var plate_h := UIFonts.PLEX_MED.get_height(BODY_PX) + 2.0 * SIGN_PAD.y
	door.custom_minimum_size.y = ceilf(housing + SIGN_MARGIN + plate_h + SIGN_MARGIN + foot_bar - reach)
	# The sign sits on the slats, between the roller housing and the bottom bar.
	var slats := CenterContainer.new()
	slats.name = "Slats"
	slats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slats.set_anchors_preset(Control.PRESET_FULL_RECT)
	slats.offset_top = housing
	slats.offset_bottom = reach - foot_bar
	slats.add_child(plate)
	door.add_child(slats)
	return door


## A small plate of Building Detail's dark metal, a silver screw near each corner (`BdpV3Section` "slab"),
## printed with `text` in white.
static func sign_plate(text: String) -> MarginContainer:
	var plate: MarginContainer = Section.new()
	plate.name = "Sign"
	plate.set("style", "slab")
	plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_theme_constant_override("margin_left", roundi(SIGN_PAD.x))
	plate.add_theme_constant_override("margin_right", roundi(SIGN_PAD.x))
	plate.add_theme_constant_override("margin_top", roundi(SIGN_PAD.y))
	plate.add_theme_constant_override("margin_bottom", roundi(SIGN_PAD.y))
	var words := body(text)
	words.name = "Note"
	words.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	(plate.get("content") as VBoxContainer).add_child(words)
	return plate


## A groove pressed across a plate over `row`, in the middle of the `gap` above it, where one group of rows
## ends and the next begins: a dark cut with a light lip under it. It takes no room of its own.
static func groove_over(row: Control, gap: float) -> void:
	var y := -roundf(gap * 0.5) - 1.0
	row.draw.connect(func() -> void:
		row.draw_line(Vector2(0, y + 0.5), Vector2(row.size.x, y + 0.5), Color(0, 0, 0, 0.55), 1.0)
		row.draw_line(Vector2(0, y + 1.5), Vector2(row.size.x, y + 1.5), Color(1, 1, 1, 0.10), 1.0))
	row.resized.connect(row.queue_redraw)
