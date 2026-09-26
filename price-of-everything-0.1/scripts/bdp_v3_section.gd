extends MarginContainer
## Building Detail v3: a section of the detail panel (heading and content) inside a worn steel frame
## with a screw in each corner, set on the rim's centre line (res://assets/ui/bdp_v3/section_frame.png,
## drawn as a 9-slice). The frame's rim sits on this control's edge; its cast shadow reaches beyond it.
## Children go in `content`.
##
## `style` "plastic" draws a dark moulded plastic plate over the whole section instead (diag_plastic.png,
## also a 9-slice), with silver screws (screw_silver.png) round its edge: four along the top and four
## along the bottom, six down each side (counting the corners). `style` "dark" keeps the steel frame and
## fills its inside with a dark metal plate (dark_plate.png), its edges under the rim, cropped from the
## render's middle at the render's scale rather than stretched, so its scratches are the size of every
## other plate's. `style` "slab" is that dark metal plate on its own, with no steel frame: a thin dark edge,
## a soft shadow under it, and Building Detail's silver screw set in near each corner. `style` "bare" draws
## nothing: its heading and content sit straight on the plate under it, inset as a framed section's are, so
## its columns line up with the framed sections round it. `style` "plate" is one worn steel plate, its edge
## and its face one piece (sheet_plate.png as a 9-slice, its own bevel round it), its grain calmed under a
## wash of its own mean colour: a light surface, so its print is navy.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const FRAME: Texture2D = preload("res://assets/ui/bdp_v3/section_frame.png")
const PLASTIC: Texture2D = preload("res://assets/ui/bdp_v3/diag_plastic.png")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
const DARK: Texture2D = preload("res://assets/ui/bdp_v3/dark_plate.png")
const SHEET: Texture2D = preload("res://assets/ui/bdp_v3/sheet_plate.png")
## The steel plate's render (layout.json sheet_plate): its shadow room and 9-slice corner; its mean colour and
## how strongly that is washed over it to quiet its scratches.
const SHEET_MARGIN := 10.0 / 1.875
const SHEET_CORNER_TEXELS := (10.0 + 60.0) * 2.0 / 1.875
const SHEET_MEAN := Color8(135, 134, 134)
const SHEET_CALM := 0.5
const TEXELS_PER_PIXEL := 2.0
const CAPTURE_SCALE := 1.875
## The render's layout: shadow room around the rim and the rim's width (layout pixels at the capture
## scale 1.875), and the 9-slice corner in texture pixels (2 per logical pixel).
const OUTSET := 18.0 / 1.875
const RIM := 26.0 / 1.875
const CORNER_TEXELS := 62.0 * 2.0 / 1.875
const PADDING := 8.0
## The plastic plate's render (layout.json diag_plastic): its shadow room and 9-slice corner. The silver
## screws sit this far in from the plate's edges, so many along each.
const PLASTIC_MARGIN := 14.0 / 1.875
const PLASTIC_CORNER_TEXELS := (14.0 + 40.0) * 2.0 / 1.875
const SCREW_INSET := 9.0
const SCREWS_ACROSS := 4
const SCREWS_DOWN := 6

var content: VBoxContainer
var style := "steel":
	set(v):
		style = v
		var m := roundi(SLAB_PAD if v == "slab" else RIM + PADDING)
		for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			add_theme_constant_override(side, m)
		queue_redraw()
## The slab: its content's inset (clear of the corner screws), how far in its screws sit, and its shadow.
const SLAB_PAD := 16.0
const SLAB_SCREW_INSET := 11.0
const SLAB_SHADOW := Vector2(1.5, 2.5)


## Where the plastic plate's silver screws go, for a `plate_size`-pixel plate: evenly along the top and
## the bottom from corner to corner, then evenly down each side between them.
static func screw_points(plate_size: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var lo := Vector2(SCREW_INSET, SCREW_INSET)
	var hi := plate_size - lo
	for i in SCREWS_ACROSS:
		var x := lerpf(lo.x, hi.x, float(i) / (SCREWS_ACROSS - 1))
		pts.append(Vector2(x, lo.y))
		pts.append(Vector2(x, hi.y))
	for i in range(1, SCREWS_DOWN - 1):
		var y := lerpf(lo.y, hi.y, float(i) / (SCREWS_DOWN - 1))
		pts.append(Vector2(lo.x, y))
		pts.append(Vector2(hi.x, y))
	return pts


func _init() -> void:
	name = "BdpV3Section"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		add_theme_constant_override(side, roundi(RIM + PADDING))
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	add_child(content)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if style == "bare":
		return
	if style == "plastic":
		Nine.paint(self, PLASTIC, Rect2(Vector2.ZERO, size).grow(PLASTIC_MARGIN), PLASTIC_CORNER_TEXELS)
		var s := SCREW.get_size() / 2.0
		for p in screw_points(size):
			draw_texture_rect(SCREW, Rect2(p - s * 0.5, s), false)
		return
	if style == "slab":
		var plate := Rect2(Vector2.ZERO, size)
		draw_rect(plate.grow(1.5), Color(0, 0, 0, 0.18))
		draw_rect(Rect2(plate.position + SLAB_SHADOW, plate.size), Color(0, 0, 0, 0.42))
		var tex := DARK.get_size()
		var want := plate.size * TEXELS_PER_PIXEL
		if want.x <= tex.x and want.y <= tex.y:
			draw_texture_rect_region(DARK, plate, Rect2((tex - want) * 0.5, want))
		else:
			draw_texture_rect(DARK, plate, false)
		draw_rect(plate.grow(-0.5), Color(0, 0, 0, 0.55), false, 1.0)
		var s := SCREW.get_size() / 2.0
		var lo := Vector2(SLAB_SCREW_INSET, SLAB_SCREW_INSET)
		var hi := size - lo
		for p in [lo, Vector2(hi.x, lo.y), Vector2(lo.x, hi.y), hi]:
			draw_texture_rect(SCREW, Rect2(p - s * 0.5, s), false)
		return
	if style == "plate":
		Nine.paint(self, SHEET, Rect2(Vector2.ZERO, size).grow(SHEET_MARGIN), SHEET_CORNER_TEXELS)
		var calm := StyleBoxFlat.new()
		calm.bg_color = Color(SHEET_MEAN, SHEET_CALM)
		calm.set_corner_radius_all(8)
		draw_style_box(calm, Rect2(Vector2.ZERO, size).grow(-3.0))
		return
	if style == "dark":
		var fill: Texture2D = DARK
		var inside := Rect2(Vector2.ZERO, size).grow(-RIM * 0.5)
		var tex := fill.get_size()
		var want := inside.size * TEXELS_PER_PIXEL
		if want.x <= tex.x and want.y <= tex.y:
			draw_texture_rect_region(fill, inside, Rect2((tex - want) * 0.5, want))
		else:
			draw_texture_rect(fill, inside, false)
	Nine.paint(self, FRAME, Rect2(Vector2.ZERO, size).grow(OUTSET), CORNER_TEXELS)
