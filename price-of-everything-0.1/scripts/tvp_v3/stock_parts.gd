extends RefCounted
## Tile view v3, the Stock tab: the small parts its sections and sheets share, after Building Detail v3's
## own (scripts/building_detail_panel_v2.gd): white print embossed on dark metal, metal-label captions, a
## good's icon set in a well, a raised icon trimmed to its art, figures on LED screens, a typed figure on an
## LED screen's glass, and the steel sheet that slides in over the tab's body.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Heading := preload("res://scripts/bdp_v3_heading.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

## The owner's text standard: body 14 px (semibold for a row's own title), captions 15 px, the £ 18 px.
const BODY_PX := 14
const CAPTION_PX := 15
const POUND_PX := 18
## Lamps beside a row, as Building Detail's diagnostics rows have them.
const ROW_LAMP := 0.62

## The icon well (layout.json icon_well), in layout pixels at 1.875: the frame's reach round the icon, its
## 9-slice corner in texels, and the opening's corner radius in logical pixels.
const WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const WELL_REACH := (12.0 + 7.0) / 1.875
const WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const WELL_RADIUS := 10.0 / 1.875
## Building Detail's quantity pill: its height and how far inside the icon's corner it sits (QTY_PILL_INSET).
const PILL_H := 22
const PILL_INSET := 5
## The LED screens' bezel and glass (layout.json mini_screen).
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const SCREEN_GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const SCREEN_MARGIN := 8.0 / 1.875
const SCREEN_RIM := 7.0 / 1.875
const SCREEN_CORNER := (8.0 + 7.0 + 5.0 + 2.0) * 2.0 / 1.875
## The action sheet's steel plate (layout.json sheet_plate), as Building Detail's sheets.
const SHEET: Texture2D = preload("res://assets/ui/bdp_v3/sheet_plate.png")
const SHEET_MARGIN := 10.0 / 1.875
const SHEET_CORNER := (10.0 + 60.0) * 2.0 / 1.875
const SHEET_PAD := 14
const SHEET_SLIDE_SECONDS := 0.26


## White print that stands off dark metal or plastic: a dark shadow down and to the right.
static func emboss(l: Label) -> Label:
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


## Body text, 14 px Plex Medium, or semibold for a row's own title.
static func body(text: String, semibold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_SEMI if semibold else UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", BODY_PX)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return emboss(l)


## Body text that wraps within its column.
static func para(text: String) -> Label:
	var l := body(text)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 120.0
	return l


## A metal label: Barlow Condensed SemiBold capitals, 15 px, white on the metal.
static func metal(text: String, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.uppercase = true
	l.add_theme_font_override("font", Plate.FONT_SEMI)
	l.add_theme_font_size_override("font_size", CAPTION_PX)
	l.horizontal_alignment = align
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return emboss(l)


## A section's heading in Building Detail's raised letters, with the plain label kept (hidden) behind it
## for anything that looks the words up; the plain label shows if the letters lack a character.
static func heading(text: String) -> Control:
	var box := HBoxContainer.new()
	box.name = "Heading"
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var plain := metal(text)
	plain.name = "HeadingText"
	box.add_child(plain)
	if Heading.can_show(text):
		var raised: Control = Heading.new()
		raised.text = text
		box.add_child(raised)
		plain.visible = false
	return box


## A tile as the player reads it: its name, never its coordinates (they go on hover, `coords`).
static func tile_words(tile_id: String, fallback := "another tile") -> String:
	var n := Catalog.tile_name(tile_id)
	return n if n != "" else fallback


static func coords(tile_id: String) -> String:
	return Catalog.tile_label(tile_id)


static func spacer() -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return s


static func lamp(tone: String, scale := ROW_LAMP) -> Control:
	var l: Control = Lamp.new()
	l.lamp_scale = scale
	l.set_tone(tone)
	return l


## A figure on an LED screen, padded with blank leading digits to `digits` cells.
static func led(figure: String, colour: Color, digits := 0) -> Control:
	var screen: Control = Led.new()
	screen.set_figure(" ".repeat(maxi(0, digits - Led.cells_for(figure).size())) + figure, colour)
	return screen


## A £ figure: the printed £, then the figure on an LED screen.
static func money(figure: float, colour: Color, digits := 0) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.name = "MoneyLed"
	hb.add_theme_constant_override("separation", 4)
	hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pound := metal("£", HORIZONTAL_ALIGNMENT_RIGHT)
	pound.add_theme_font_size_override("font_size", POUND_PX)
	hb.add_child(pound)
	hb.add_child(led("%.2f" % figure, colour, digits))
	return hb


## A good's icon on its cream tile, set below a thin metal frame (Building Detail's icon well), its tile's
## corners following the frame's opening; with a `qty`, its navy quantity pill sits inside the icon's
## corner over the frame, as in Building Detail's shipments bay (DS2 rule 7). It takes no clicks: the
## control it sits in does.
static func good_in_well(good_id: String, px: int, qty := -1) -> Control:
	var root := Control.new()
	root.name = "GoodInWell"
	root.custom_minimum_size = Vector2(px, px)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var tile := Panel.new()
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st := StyleBoxFlat.new()
	st.bg_color = UIHelpers.PILL_PAPER
	st.set_corner_radius_all(roundi(WELL_RADIUS))
	tile.add_theme_stylebox_override("panel", st)
	root.add_child(tile)
	var icon := TextureRect.new()
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := roundf(px * 0.1)
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = GoodIcons.texture_for_size(good_id, Catalog.get_internal_name(good_id), float(px))
	root.add_child(icon)
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		Nine.paint(well, WELL, Rect2(Vector2.ZERO, well.size).grow(WELL_REACH), WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	root.add_child(well)
	if qty >= 0:
		root.add_child(pill(qty))
	return root


## Building Detail's navy quantity pill (_qty_pill with `inside`), kept within the icon's bottom right corner.
static func pill(qty: int) -> Control:
	var content := str(qty)
	var w := maxi(PILL_H, content.length() * 9 + 14)
	var p := PanelContainer.new()
	p.name = "QtyPill"
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(w, PILL_H)
	p.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	p.offset_left = -w - PILL_INSET
	p.offset_top = -PILL_H - PILL_INSET
	p.offset_right = -PILL_INSET
	p.offset_bottom = -PILL_INSET
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(PILL_H / 2.0))
	st.set_border_width_all(2)
	st.border_color = DS.PALETTE["BORDER_STRONG"]
	p.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.theme_type_variation = "Numeric"
	l.text = content
	l.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p


## One of Building Detail's raised cream icons (a render and its swept shadow), scaled so its drawn art, not
## its canvas, fills a `px` box, standing on the box's foot as the diagnostics' indicators do.
static func raised_icon(face_path: String, px: float) -> Control:
	var face: Texture2D = load(face_path)
	var shadow: Texture2D = load(face_path.replace(".png", "_shadow.png"))
	var c := Control.new()
	c.name = "RaisedIcon"
	c.custom_minimum_size = Vector2(px, px)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.draw.connect(func() -> void:
		if face == null:
			return
		var art := Indicator.art_rect(face)
		var k := px / maxf(art.size.x, art.size.y)
		var art_size := art.size * k
		var at := Vector2((c.size.x - art_size.x) * 0.5, c.size.y - art_size.y)
		var rect := Rect2(at - art.position * k, face.get_size() * k)
		if shadow != null:
			c.draw_texture_rect(shadow, rect, false)
		c.draw_texture_rect(face, rect, false))
	return c


## A whole number typed onto an LED screen's glass: the bezel and pane painted behind a bare LineEdit, the
## figure in white. Digits only; the wheel steps it by one (ten with shift). `changed` gets each valid value.
static func entry(value: int, lo: int, hi: int, width: float, changed: Callable) -> Control:
	var screen := PanelContainer.new()
	screen.name = "EntryScreen"
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	screen.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(SCREEN_RIM + 1.0)
	screen.add_theme_stylebox_override("panel", pad)
	screen.draw.connect(func() -> void:
		Nine.paint(screen, SCREEN, Rect2(Vector2.ZERO, screen.size).grow(SCREEN_MARGIN), SCREEN_CORNER))
	var field := LineEdit.new()
	field.name = "Entry"
	field.text = str(value)
	field.custom_minimum_size = Vector2(width, 30.0)
	field.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	field.max_length = 7
	field.select_all_on_focus = true
	field.context_menu_enabled = false
	var bare := StyleBoxEmpty.new()
	bare.content_margin_left = 6
	bare.content_margin_right = 6
	for state in ["normal", "focus", "read_only"]:
		field.add_theme_stylebox_override(state, bare)
	field.add_theme_font_override("font", UIFonts.mono())
	field.add_theme_font_size_override("font_size", 18)
	field.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	field.add_theme_color_override("caret_color", DS.PALETTE.TEXT)
	field.add_theme_color_override("selection_color", Color(1, 1, 1, 0.22))
	screen.add_child(field)
	var commit := func(v: int) -> void:
		var clamped := clampi(v, lo, maxi(lo, hi))
		if field.text != str(clamped):
			var caret := field.caret_column
			field.text = str(clamped)
			field.caret_column = mini(caret, field.text.length())
		changed.call(clamped)
	field.text_changed.connect(func(t: String) -> void:
		var digits := ""
		for ch in t:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != t:
			field.text = digits
			field.caret_column = digits.length()
		if digits != "":
			changed.call(clampi(digits.to_int(), lo, maxi(lo, hi))))
	field.text_submitted.connect(func(t: String) -> void: commit.call(t.to_int()))
	field.focus_exited.connect(func() -> void: commit.call(field.text.to_int()))
	field.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb == null or not mb.pressed or mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		var step := 10 if mb.shift_pressed else 1
		commit.call(field.text.to_int() + (step if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -step))
		field.accept_event())
	return screen


## Building Detail's action sheet in the tab's body: a worn steel plate that slides in from the right the
## first time it opens for `key` (kept on the panel, so a rebuild leaves it in place), Back and its title
## across the top. It covers the body's whole view. Returns the column the sheet's rows go in.
static func sheet(panel: Control, pane: VBoxContainer, key: String, node_name: String, title: String, back: Callable) -> VBoxContainer:
	var holder := Control.new()
	holder.name = node_name
	holder.clip_contents = true
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	pane.add_child(holder)
	var plate := PanelContainer.new()
	plate.name = "SheetPlate"
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(SHEET_PAD)
	plate.add_theme_stylebox_override("panel", pad)
	plate.draw.connect(func() -> void:
		Nine.paint(plate, SHEET, Rect2(Vector2.ZERO, plate.size).grow(SHEET_MARGIN), SHEET_CORNER))
	holder.add_child(plate)
	var col := VBoxContainer.new()
	col.name = "SheetRows"
	col.add_theme_constant_override("separation", 12)
	plate.add_child(col)
	var head := HBoxContainer.new()
	head.name = "SheetHeader"
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var back_key: TextureButton = Key.make("back")
	back_key.name = "SheetBack"
	back_key.pressed.connect(back)
	head.add_child(back_key)
	var tl := Label.new()
	tl.name = "SheetTitle"
	tl.theme_type_variation = &"BuildingName"
	tl.text = title
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.clip_text = true
	emboss(tl)
	head.add_child(tl)
	var scroll := panel.get("_body_scroll") as ScrollContainer
	var fresh := str(panel.get_meta("tvp_stock_sheet", "")) != key
	panel.set_meta("tvp_stock_sheet", key)
	var state := {"slide": fresh}
	var fit := func() -> void:
		var room := (scroll.size.y - 4.0) if scroll != null else 0.0
		var h := maxf(plate.get_combined_minimum_size().y, room)
		if not is_equal_approx(holder.custom_minimum_size.y, h):
			holder.custom_minimum_size.y = h
		plate.size = Vector2(holder.size.x, h)
		if bool(state.slide) and holder.size.x > 0.0:
			state.slide = false
			plate.position.x = holder.size.x
			plate.create_tween().tween_property(plate, "position:x", 0.0, SHEET_SLIDE_SECONDS) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	plate.minimum_size_changed.connect(fit)
	holder.resized.connect(fit)
	if fresh and scroll != null:
		scroll.set_deferred("scroll_vertical", 0)
	return col


## A row of a sheet: its caption in a column of one width, then its controls.
static func sheet_row(caption: String, caption_w := 104.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cap := metal(caption)
	cap.custom_minimum_size.x = caption_w
	row.add_child(cap)
	return row
