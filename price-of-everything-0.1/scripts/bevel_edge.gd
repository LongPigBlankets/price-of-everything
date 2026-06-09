extends Control
## A thin raised bevel edge drawn inset from the node's rect: bright on the top
## and left, dark on the bottom and right (lit from the top-left), so a framed
## icon reads as a raised plate. The rim sits INSET px in from the node's edge;
## the helper spans the whole frame, so this is the distance from the frame edge.

const INSET := 6.0
const T := 2.0
const LIGHT := Color(1.0, 1.0, 1.0, 0.65)
const DARK := Color(0.0, 0.0, 0.0, 0.5)

func _draw() -> void:
	var w := size.x - 2.0 * INSET
	var h := size.y - 2.0 * INSET
	if w <= T or h <= T:
		return
	draw_rect(Rect2(INSET, INSET, w, T), LIGHT)              # top
	draw_rect(Rect2(INSET, INSET, T, h), LIGHT)              # left
	draw_rect(Rect2(INSET, INSET + h - T, w, T), DARK)       # bottom
	draw_rect(Rect2(INSET + w - T, INSET, T, h), DARK)       # right
