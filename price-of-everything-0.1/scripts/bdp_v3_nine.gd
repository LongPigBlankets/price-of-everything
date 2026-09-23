extends Control
## Building Detail v3: paints one of the rendered plates (res://assets/ui/bdp_v3/) as a 9-slice over
## this control's rect, so a fixed-size render fits any size: the corners keep their drawn size and
## the edges and middle stretch between them. The renders are at 2 texture pixels per logical pixel.
## Used full-rect behind the panel for its brass backing; the section frames call paint() directly.

const TEXELS_PER_PIXEL := 2.0

var texture: Texture2D
## Corner size in texture pixels (screws and rounded corners sit inside it).
var corner := 64.0
## How far the texture reaches beyond the rect, in logical pixels (room for a cast shadow).
var outset := 0.0


static func make(layer: String, corner_texels: float, outset_px: float = 0.0) -> Control:
	var n: Control = load("res://scripts/bdp_v3_nine.gd").new()
	n.name = "BdpV3" + layer.to_pascal_case()
	n.texture = load("res://assets/ui/bdp_v3/%s.png" % layer)
	n.corner = corner_texels
	n.outset = outset_px
	return n


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	paint(self, texture, Rect2(Vector2.ZERO, size).grow(outset), corner)


static func paint(ci: CanvasItem, tex: Texture2D, dest: Rect2, corner_texels: float) -> void:
	if tex == null or dest.size.x <= 0.0 or dest.size.y <= 0.0:
		return
	var ts := tex.get_size()
	var c := minf(corner_texels, minf(ts.x, ts.y) * 0.5)
	var d := minf(c / TEXELS_PER_PIXEL, minf(dest.size.x, dest.size.y) * 0.5)
	var sx := [0.0, c, ts.x - c, ts.x]
	var sy := [0.0, c, ts.y - c, ts.y]
	var dx := [dest.position.x, dest.position.x + d, dest.end.x - d, dest.end.x]
	var dy := [dest.position.y, dest.position.y + d, dest.end.y - d, dest.end.y]
	for i in 3:
		for j in 3:
			var dst := Rect2(dx[i], dy[j], dx[i + 1] - dx[i], dy[j + 1] - dy[j])
			if dst.size.x > 0.0 and dst.size.y > 0.0:
				ci.draw_texture_rect_region(tex, dst, Rect2(sx[i], sy[j], sx[i + 1] - sx[i], sy[j + 1] - sy[j]))
