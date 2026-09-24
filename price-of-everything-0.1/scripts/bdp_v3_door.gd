extends Control
## Building Detail v3: the inbound shipments bay's rolling door (res://assets/ui/bdp_v3/shipment_door.png,
## rendered by tools/button_mockup/cluster.html?export): a roller housing across the top, corrugated
## slats, a bottom bar, and a guide channel down each side. The bay has room for six goods; the door
## comes down over the rows no good needs, and with every row in use it is rolled up: the housing with
## the door's bottom bar tucked under it.
## The guides, the housing and the bar keep their size; the width between the guides stretches (the
## slats are the same all along) and whole slats repeat down to the door's height, each squeezed or
## eased a little so a whole number fits. The door fills this control, reaching `reach` beyond its sides
## to the frame's rim, and shades the top of the bay below it.

const DOOR: Texture2D = preload("res://assets/ui/bdp_v3/shipment_door.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (shipment_door), in layout pixels: a guide's width, the housing's and the bottom
## bar's heights, and a slat's pitch.
const SIDE := 16.0
const TOP := 44.0
const BOTTOM := 26.0
const PERIOD := 12.0
## The depth of the shade the door casts into the bay below it.
const BAY_SHADE := 14.0

var reach := 0.0


func _init() -> void:
	name = "ShipmentDoor"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


## A door rolled all the way up: its housing, with the bottom bar just under it.
static func rolled_up_height() -> float:
	return (TOP + BOTTOM) / CAPTURE_SCALE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var dest := Rect2(-reach, 0.0, size.x + 2.0 * reach, size.y)
	if size.y <= rolled_up_height() + 0.5:
		var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
		var tex_h := DOOR.get_height() * 1.0
		_paint_rows(self, dest, [[0.0, TOP * k, TOP / CAPTURE_SCALE], [tex_h - BOTTOM * k, tex_h, BOTTOM / CAPTURE_SCALE]])
	else:
		paint(self, dest)
	for i in 6:
		var t := float(i) / 6.0
		draw_rect(Rect2(dest.position.x, size.y + BAY_SHADE * t, dest.size.x, BAY_SHADE / 6.0), Color(0, 0, 0, 0.42 * (1.0 - t)))


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


static func _columns(dest: Rect2) -> Array:
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE
	var tex_w := DOOR.get_width() * 1.0
	var side_px := minf(SIDE / CAPTURE_SCALE, dest.size.x * 0.5)
	return [[0.0, SIDE * k, dest.position.x, side_px],
		[SIDE * k, tex_w - SIDE * k, dest.position.x + side_px, dest.size.x - 2.0 * side_px],
		[tex_w - SIDE * k, tex_w, dest.end.x - side_px, side_px]]


static func paint(ci: CanvasItem, dest: Rect2) -> void:
	if dest.size.x <= 0.0 or dest.size.y <= 0.0:
		return
	_paint_rows(ci, dest, rows(dest.size.y))


static func _paint_rows(ci: CanvasItem, dest: Rect2, door_rows: Array) -> void:
	var cols := _columns(dest)
	var y := dest.position.y
	for r: Array in door_rows:
		var h: float = r[2]
		for c: Array in cols:
			if float(c[3]) > 0.0 and h > 0.0:
				ci.draw_texture_rect_region(DOOR, Rect2(c[2], y, c[3], h), Rect2(c[0], r[0], float(c[1]) - float(c[0]), float(r[1]) - float(r[0])))
		y += h
