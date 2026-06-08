extends Control
## Cream inner outline for the bottom menu. Its top edge runs straight between
## the buttons, but at each button it dips into a round notch that traces the
## bottom of that button's ring (the part of the ring sitting below the outline
## line), meeting the straight edge at a sharp angle on each side.

const COLOR := Color(0.995234, 0.930806, 0.763265)  # DS cream (same as the Build button text)
const LINE_W := 2.0
const TOP_Y := 1.0      # resting height of the straight outline (node-local)
const RING_PAD := 1.5   # trace just outside the button edge so the notch reads

func _ready() -> void:
	resized.connect(queue_redraw)
	var menu := get_node_or_null("%BottomMenu")
	if menu != null:
		menu.sort_children.connect(queue_redraw)
	call_deferred("queue_redraw")  # redraw once layout has settled

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Each button's ring as a circle in this node's local space: [cx, cy, radius].
	var rings: Array = []
	var menu := get_node_or_null("%BottomMenu")
	if menu != null:
		for c in menu.get_children():
			if c is Button:
				var gx: float = c.global_position.x + c.size.x * 0.5
				var gy: float = c.global_position.y + c.size.y * 0.5
				rings.append([gx - global_position.x, gy - global_position.y, c.size.x * 0.5 + RING_PAD])
	# One continuous stroke: up the left side, across the notched top, down the right.
	var pts := PackedVector2Array()
	pts.append(Vector2(1.0, h))
	pts.append(Vector2(1.0, TOP_Y))
	var x := 1.0
	while x <= w - 1.0:
		var y := TOP_Y
		for r in rings:
			var dx: float = x - r[0]
			var under: float = r[2] * r[2] - dx * dx
			if under > 0.0:
				var y_low: float = r[1] + sqrt(under)  # bottom edge of the ring at this x
				if y_low > y:
					y = y_low  # follow the ring where it sits below the outline line
		pts.append(Vector2(x, y))
		x += 1.0
	pts.append(Vector2(w - 1.0, TOP_Y))
	pts.append(Vector2(w - 1.0, h))
	draw_polyline(pts, COLOR, LINE_W, true)
