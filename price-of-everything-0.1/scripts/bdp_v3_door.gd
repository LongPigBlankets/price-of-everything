extends RefCounted
## Building Detail v3: the inbound shipments' rolling door, slid up, drawn as the section's backdrop
## (res://assets/ui/bdp_v3/shipment_door.png, rendered by tools/button_mockup/cluster.html?export): a
## roller housing across the top, corrugated slats, a bottom bar, and a guide channel down each side.
## The guides, the housing and the bar keep their size; the width between the guides stretches (the
## slats are the same all along) and whole slats repeat down to the height the door must reach, each
## squeezed or eased a little so a whole number fits.

const DOOR: Texture2D = preload("res://assets/ui/bdp_v3/shipment_door.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (shipment_door), in layout pixels: a guide's width, the housing's and the bottom
## bar's heights, and a slat's pitch.
const SIDE := 16.0
const TOP := 44.0
const BOTTOM := 26.0
const PERIOD := 12.0


## The door's rows for a `height`-pixel door: [source top, source bottom (texture pixels), drawn height].
static func rows(height: float) -> Array:
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
	var tex_h := DOOR.get_height() * 1.0
	var top_px := TOP / CAPTURE_SCALE
	var bottom_px := BOTTOM / CAPTURE_SCALE
	var period_px := PERIOD / CAPTURE_SCALE
	var squeeze := minf(1.0, height / (top_px + bottom_px + period_px))
	var mid := maxf(0.0, height - (top_px + bottom_px) * squeeze)
	var n := maxi(1, roundi(mid / period_px))
	var out: Array = [[0.0, TOP * k, top_px * squeeze]]
	for i in n:
		out.append([TOP * k, (TOP + PERIOD) * k, mid / n])
	out.append([tex_h - BOTTOM * k, tex_h, bottom_px * squeeze])
	return out


static func paint(ci: CanvasItem, dest: Rect2) -> void:
	if dest.size.x <= 0.0 or dest.size.y <= 0.0:
		return
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
	var tex_w := DOOR.get_width() * 1.0
	var side_px := minf(SIDE / CAPTURE_SCALE, dest.size.x * 0.5)
	var cols := [[0.0, SIDE * k, dest.position.x, side_px],
		[SIDE * k, tex_w - SIDE * k, dest.position.x + side_px, dest.size.x - 2.0 * side_px],
		[tex_w - SIDE * k, tex_w, dest.end.x - side_px, side_px]]
	var y := dest.position.y
	for r: Array in rows(dest.size.y):
		var h: float = r[2]
		for c: Array in cols:
			if float(c[3]) > 0.0 and h > 0.0:
				ci.draw_texture_rect_region(DOOR, Rect2(c[2], y, c[3], h), Rect2(c[0], r[0], float(c[1]) - float(c[0]), float(r[1]) - float(r[0])))
		y += h
