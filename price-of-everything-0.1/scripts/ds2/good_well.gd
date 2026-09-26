extends RefCounted
## DS2 (the tile view's Transport and Stock tabs): a good in Building Detail's icon well with its quantity in a pill, the one shape a
## good's quantity takes in the cabinet (DS2 rule 7): the cream icon set below a thin metal frame
## (res://assets/ui/bdp_v3/icon_well.png, a 9-slice), its quantity in a small navy pill inside its corner, kept
## clear of most of the drawing. The goods riding a link, what laying one takes, and the materials on a hover
## card all use it.

const UIFonts := preload("res://scripts/ui_fonts.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")

## Building Detail's icon well (layout.json icon_well): how far the frame reaches beyond the opening, its
## 9-slice corner, the opening's radius.
const WELL: Texture2D = preload("res://assets/ui/bdp_v3/icon_well.png")
const WELL_REACH := (12.0 + 7.0) / 1.875
const WELL_CORNER := (12.0 + 7.0 + 16.0) * 2.0 / 1.875
const WELL_RADIUS := 10.0 / 1.875
const PILL_H := 16.0
const PILL_INSET := 3.0
const PILL_PX := 12


## `gid` at `px` in its well with `qty` in its pill; `note` follows the quantity and the name on hover.
static func make(gid: String, qty: int, note: String, px: int) -> Control:
	var icon := UIHelpers.make_plain_good_icon(gid, Catalog.get_internal_name(gid), px)
	UIHelpers.link_good_icon_to_encyclopedia(icon, gid)
	var tile := icon.get_child(0) as PanelContainer
	if tile != null and tile.get_theme_stylebox("panel") is StyleBoxFlat:
		var st := (tile.get_theme_stylebox("panel") as StyleBoxFlat).duplicate() as StyleBoxFlat
		st.set_corner_radius_all(roundi(WELL_RADIUS))
		tile.add_theme_stylebox_override("panel", st)
	var well := Control.new()
	well.name = "IconWell"
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	well.set_anchors_preset(Control.PRESET_FULL_RECT)
	well.draw.connect(func() -> void:
		Nine.paint(well, WELL, Rect2(Vector2.ZERO, well.size).grow(WELL_REACH), WELL_CORNER))
	well.resized.connect(well.queue_redraw)
	icon.add_child(well)
	var text := count(qty)
	var w := maxf(PILL_H, UIFonts.PLEX_SEMI.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, PILL_PX).x + 9.0)
	var pill := PanelContainer.new()
	pill.name = "QuantityPill"
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	pill.offset_left = -w - PILL_INSET
	pill.offset_top = -PILL_H - PILL_INSET
	pill.offset_right = -PILL_INSET
	pill.offset_bottom = -PILL_INSET
	var st := StyleBoxFlat.new()
	st.bg_color = DS.PALETTE["BG_PANEL"]
	st.set_corner_radius_all(int(PILL_H / 2.0))
	st.set_border_width_all(1)
	st.border_color = DS.PALETTE["BORDER_STRONG"]
	st.content_margin_top = 0
	st.content_margin_bottom = 0
	pill.add_theme_stylebox_override("panel", st)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_SEMI)
	l.add_theme_font_size_override("font_size", PILL_PX)
	l.add_theme_color_override("font_color", DS.PALETTE["ACCENT"])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(l)
	icon.add_child(pill)
	icon.tooltip_text = ("%s %s %s" % [text, Catalog.get_display_name(gid), note]).strip_edges()
	return icon


## How far the well's frame reaches past the icon, for the room kept round a row of them.
static func reach() -> float:
	return WELL_REACH


static func count(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out
