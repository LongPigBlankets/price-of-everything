extends Control
## Building Detail v3: the cable down the diagnostics' lights. Black rubber insulation with a yellow
## tracer stripe, lying on the steel between a cable gland at each end
## (res://assets/ui/bdp_v3/diag_cable.png, rendered by tools/button_mockup/cluster.html?export).
## Drawn as a vertical three-slice down this control's height: the glands keep their size and the
## cable between them stretches, which it can, being the same all along.
##
## Each of `taps` (the diagnostics' modules) takes a feed from it: a junction box clamped over the cable,
## a short branch of the same cable, and a gland where it enters the module's end (diag_tap.png), at the
## height of the module's middle. The branch is TAP_LENGTH long, so the modules start that far to the
## right of the cable.

const Scroll := preload("res://scripts/bdp_v3_scroll.gd")
const CABLE: Texture2D = preload("res://assets/ui/bdp_v3/diag_cable.png")
const TAP: Texture2D = preload("res://assets/ui/bdp_v3/diag_tap.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (diag_cable), in layout pixels: the rows kept at each end (the glands), and the
## cable's centre across the render.
const CAP := 30.0
const CENTRE_X := 13.0
## From layout.json (diag_tap), in layout pixels: the junction's centre and the module's end.
const TAP_X := 13.0
const TAP_PLUG := 78.0
const TAP_LENGTH := (TAP_PLUG - TAP_X) / CAPTURE_SCALE

## Where the cable's centre runs, in pixels from this control's left (it may lie outside it), and how
## far in from this control's top and bottom its glands sit.
var centre_x := 0.0
var inset := 2.0
var taps: Array[Control] = []:
	set(v):
		taps = v
		for t in taps:
			t.item_rect_changed.connect(queue_redraw)
			t.visibility_changed.connect(queue_redraw)
		queue_redraw()
var _slicer: StyleBox = Scroll.make(CABLE, CAP)


func _init() -> void:
	name = "BdpV3Cable"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var left := centre_x - CENTRE_X / CAPTURE_SCALE
	var width := CABLE.get_width() / TEXELS_PER_PIXEL
	var y := inset
	for s: Array in _slicer.slices(size.y - 2.0 * inset):
		var h: float = s[2]
		if h > 0.0:
			draw_texture_rect_region(CABLE, Rect2(left, y, width, h), Rect2(0.0, s[0], CABLE.get_width(), float(s[1]) - float(s[0])))
		y += h
	var tap := TAP.get_size() / TEXELS_PER_PIXEL
	for t in taps:
		if not is_instance_valid(t) or not t.is_visible_in_tree():
			continue
		var mid_y := (get_global_transform().affine_inverse() * t.get_global_transform() * (t.size * 0.5)).y
		draw_texture_rect(TAP, Rect2(centre_x - TAP_X / CAPTURE_SCALE, mid_y - tap.y * 0.5, tap.x, tap.y), false)
