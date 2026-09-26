extends RefCounted
## Tile view v3, the Stock tab: the small parts its sections and sheets share, after Building Detail v3's
## own (scripts/building_detail_panel_v2.gd): white print embossed on dark metal, metal-label captions, a
## good's icon set in a well, a raised icon trimmed to its art, money on LED screens and every other figure
## on a dot matrix, a typed figure on an LED screen's glass, and the steel sheet that slides in over the
## tab's body.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Led := preload("res://scripts/bdp_v3_led.gd")
const DotMatrix := preload("res://scripts/ds2/dot_matrix.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
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
## The body's navy steel sheet, sampled, behind a sheet's rounded corners.
const SHEET_BACKING := Color("#232a33")
## A figure's dot matrix: the dots' pitch (seven rows of 2 px make a 14 px figure, the body text's size).
const DOT_PITCH := 2.0
## The mark a dot matrix lights before its figure when the figure is a warning.
const DOT_MARK := "●"


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


## A figure that isn't money on a framed dot matrix, in white; with a `tone` of "warn" or "bad" a mark lit
## amber or red before it (as the cabinet's key bed marks its figures).
static func dots(text: String, tone := "") -> Control:
	var d: Control = DotMatrix.new()
	d.pitch = DOT_PITCH
	d.framed = true
	var mark := {"warn": DS.PALETTE.WARN, "bad": DS.PALETTE.DANGER}
	if mark.has(tone):
		d.set_runs([{"text": DOT_MARK + " ", "colour": mark[tone]}, {"text": text, "colour": Color.WHITE}])
	else:
		d.text = text
	return d


## A figure on an LED screen, padded with blank leading digits to `digits` cells. Money and unit costs only.
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
## control it sits in does. With `link`, the icon is a TextureRect, which the game's good hover registry
## (scripts/good_hover_registry.gd) turns into a link to the good's encyclopedia entry, a click on it
## opening the entry; without it the icon is drawn, so a click on it reaches the control it sits in (the
## bay's cells, where a click opens the good's Move or sell sheet).
static func good_in_well(good_id: String, px: int, qty := -1, link := false) -> Control:
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
	var tex := GoodIcons.texture_for_size(good_id, Catalog.get_internal_name(good_id), float(px))
	var inset := roundf(px * 0.1)
	var icon: Control
	if link:
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture = tex
		icon = rect
	else:
		icon = Control.new()
		icon.draw.connect(func() -> void:
			if tex == null:
				return
			var k := minf(icon.size.x / tex.get_width(), icon.size.y / tex.get_height())
			var drawn := tex.get_size() * k
			icon.draw_texture_rect(tex, Rect2((icon.size - drawn) * 0.5, drawn), false))
		icon.resized.connect(icon.queue_redraw)
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
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


## Building Detail's action sheet over the tab's body: a worn steel plate that slides in from the right, over
## the body as it stands (the body stays built, and scrolled where it was, under it), the first time it
## opens for `key` (kept on the panel, so a rebuild leaves it in place). Back and its title stay across the
## top; the rows scroll under them on the sheet's own rail. The sheet covers the body's whole view and
## takes its clicks. It is a cover laid on the body's navy sheet beside the scroll, so it lives outside the
## tab's pane: the tab takes it off whenever it rebuilds without it (`close`), and it goes when the tab is
## left and hides while the land's full view has the body's place. Returns the column the rows go in.
static func sheet(panel: Control, key: String, node_name: String, title: String, back: Callable) -> VBoxContainer:
	var body := panel.get("_body_scroll") as ScrollContainer
	var host := body.get_parent() as Control
	# A rebuild of the same sheet keeps it where it was scrolled to.
	var keep := -1
	var old := cover(panel)
	if old != null and str(old.get_meta("sheet_key", "")) == key:
		var old_scroll := old.find_child("SheetScroll", true, false) as ScrollContainer
		if old_scroll != null:
			keep = old_scroll.scroll_vertical
	close(panel)
	_hook(panel)
	var lid := Control.new()
	lid.name = node_name
	lid.set_meta(COVER_META, true)
	lid.set_meta("sheet_key", key)
	lid.clip_contents = true
	lid.mouse_filter = Control.MOUSE_FILTER_STOP
	lid.visible = body.visible
	host.add_child(lid)
	var plate := PanelContainer.new()
	plate.name = "SheetPlate"
	plate.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	plate.mouse_filter = Control.MOUSE_FILTER_STOP
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(SHEET_PAD)
	plate.add_theme_stylebox_override("panel", pad)
	plate.draw.connect(func() -> void:
		# The navy sheet's own colour behind the plate's rounded corners, so nothing of the body shows there.
		plate.draw_rect(Rect2(Vector2.ZERO, plate.size), SHEET_BACKING)
		Nine.paint(plate, SHEET, Rect2(Vector2.ZERO, plate.size).grow(SHEET_MARGIN), SHEET_CORNER))
	lid.add_child(plate)
	var col := VBoxContainer.new()
	col.name = "SheetColumn"
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
	var scroll := ScrollContainer.new()
	scroll.name = "SheetScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Scroll.apply(scroll, true)
	col.add_child(scroll)
	var rows := VBoxContainer.new()
	rows.name = "SheetRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	scroll.add_child(rows)
	if keep > 0:
		# Once the rows are laid out and the rail knows their height.
		scroll.get_v_scroll_bar().changed.connect(func() -> void: scroll.scroll_vertical = keep, CONNECT_ONE_SHOT)
	var fresh := str(panel.get_meta("tvp_stock_sheet", "")) != key
	panel.set_meta("tvp_stock_sheet", key)
	# The plate fills the cover edge to edge, so none of the body shows round it once it is in.
	var state := {"slide": fresh, "sliding": false}
	var fit := func() -> void:
		plate.size = lid.size
		plate.position.y = 0.0
		if bool(state.slide) and lid.size.x > 0.0:
			state.slide = false
			state.sliding = true
			plate.position.x = lid.size.x
			var tw := plate.create_tween()
			tw.tween_property(plate, "position:x", 0.0, SHEET_SLIDE_SECONDS) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.finished.connect(func() -> void: state.sliding = false)
		elif not bool(state.sliding):
			plate.position.x = 0.0
	lid.resized.connect(fit)
	return rows


const COVER_META := "tvp_stock_sheet_cover"


## The sheet over the body, or null.
static func cover(panel: Control) -> Control:
	var body := panel.get("_body_scroll") as ScrollContainer
	if body == null or body.get_parent() == null:
		return null
	for c: Node in body.get_parent().get_children():
		if c.has_meta(COVER_META) and not c.is_queued_for_deletion():
			return c as Control
	return null


## Takes the sheet off the body, if one is on it.
static func close(panel: Control) -> void:
	var lid := cover(panel)
	while lid != null:
		lid.get_parent().remove_child(lid)
		lid.queue_free()
		lid = cover(panel)


## Once for the panel: the sheet goes when the Stock tab is left, and hides while the body's scroll does
## (the land's full view has the body's place).
static func _hook(panel: Control) -> void:
	var body := panel.get("_body_scroll") as ScrollContainer
	if body != null and not body.has_meta("tvp_stock_sheet_hook"):
		body.set_meta("tvp_stock_sheet_hook", true)
		body.visibility_changed.connect(func() -> void:
			var lid := cover(panel)
			if lid != null:
				lid.visible = body.visible)
	var panes = panel.get("_panes")
	var pane := (panes as Dictionary).get("stock") as Control if panes is Dictionary else null
	if pane != null and not pane.has_meta("tvp_stock_sheet_hook"):
		pane.set_meta("tvp_stock_sheet_hook", true)
		pane.visibility_changed.connect(func() -> void:
			if not pane.visible:
				close(panel))


## A row of a sheet: its caption in a column of one width, then its controls.
static func sheet_row(caption: String, caption_w := 104.0) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var cap := metal(caption)
	cap.custom_minimum_size.x = caption_w
	row.add_child(cap)
	return row
