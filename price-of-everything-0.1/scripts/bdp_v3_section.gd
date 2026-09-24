extends MarginContainer
## Building Detail v3: a section of the detail panel (heading and content) inside a worn steel frame
## with a screw in each corner, set on the rim's centre line (res://assets/ui/bdp_v3/section_frame.png,
## drawn as a 9-slice). The frame's rim sits on this control's edge; its cast shadow reaches beyond it.
## Children go in `content`.
##
## `style` "plastic" draws a dark moulded plastic plate over the whole section instead (diag_plastic.png,
## also a 9-slice), with silver screws (screw_silver.png) round its edge: four along the top and four
## along the bottom, six down each side (counting the corners).

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const FRAME: Texture2D = preload("res://assets/ui/bdp_v3/section_frame.png")
const PLASTIC: Texture2D = preload("res://assets/ui/bdp_v3/diag_plastic.png")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
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
		queue_redraw()


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
	if style == "plastic":
		Nine.paint(self, PLASTIC, Rect2(Vector2.ZERO, size).grow(PLASTIC_MARGIN), PLASTIC_CORNER_TEXELS)
		var s := SCREW.get_size() / 2.0
		for p in screw_points(size):
			draw_texture_rect(SCREW, Rect2(p - s * 0.5, s), false)
		return
	Nine.paint(self, FRAME, Rect2(Vector2.ZERO, size).grow(OUTSET), CORNER_TEXELS)
