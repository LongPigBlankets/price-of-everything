extends Control
## Building Detail v3: the non-slip edge over the seam where the panel's scrolling body meets its fixed
## header (res://assets/ui/bdp_v3/seam_edge.png, rendered by tools/button_mockup/cluster.html?export).
## A dark ribbed rubber strip, like the nosing on a stair tread, run across the panel from trim to trim
## and screwed at each end. The body slides out from under its lip, and the strip's shadow and the
## shade under the lip fall on the body.
##
## It is drawn as a horizontal three-slice: the ends, with the screws, keep their size and the length
## between them fits the panel's width. The renders allow it, because the strip is the same all along
## between its ends. This control is the strip itself, from its back edge to its lip; the render
## reaches past it, out to the trim at both sides and down over the top of the body, so the panel adds
## it after the scroll area.

const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
const EDGE: Texture2D = preload("res://assets/ui/bdp_v3/seam_edge.png")
## From layout.json (seam_edge), in layout pixels: the ends kept at their size, and where the strip's
## back edge and its lip sit in the frame.
const CAP := 45.0
const TOP := 6.0
const NOSE := 26.0

## How far the strip reaches past this control at each side, in pixels (out to the backing's trim).
var outset := 0.0


func _init() -> void:
	name = "BdpV3Seam"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## The strip's height on screen, from its back edge to its lip.
static func strip_height() -> float:
	return roundf((NOSE - TOP) / CAPTURE_SCALE)


## The three slices for a strip `width` pixels long: [source left, source right (texture pixels),
## drawn left, drawn right (pixels from the strip's left end)].
static func slices(width: float) -> Array:
	var tw := EDGE.get_width() * 1.0
	var cap_tx := CAP * TEXELS_PER_PIXEL / CAPTURE_SCALE
	var end_px := minf(CAP / CAPTURE_SCALE, width * 0.5)
	return [[0.0, cap_tx, 0.0, end_px], [cap_tx, tw - cap_tx, end_px, width - end_px], [tw - cap_tx, tw, width - end_px, width]]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var left := -outset
	var top := -TOP / CAPTURE_SCALE
	var h := EDGE.get_height() / TEXELS_PER_PIXEL
	for s: Array in slices(size.x + 2.0 * outset):
		var w: float = s[3] - s[2]
		if w > 0.0:
			draw_texture_rect_region(EDGE, Rect2(left + float(s[2]), top, w, h), Rect2(s[0], 0.0, float(s[1]) - float(s[0]), EDGE.get_height()))
