extends Control
## Cream inner outline for the bottom menu. The top edge dips into a small
## downward notch at each button's centre (as if avoiding the buttons), with the
## left/right sides running off-screen at the bottom like the silver frame.

const COLOR := Color(0.995234, 0.930806, 0.763265)  # DS cream (same as the Build button text)
const LINE_W := 2.0
const NOTCH_DEPTH := 30.0    # how far the top edge dips at each button centre
const NOTCH_HALF_W := 40.0   # half-width of each notch

func _ready() -> void:
	resized.connect(queue_redraw)
	var menu := get_node_or_null("%BottomMenu")
	if menu != null:
		menu.sort_children.connect(queue_redraw)
	# Redraw once layout has settled so button centres are valid.
	call_deferred("queue_redraw")

func _draw() -> void:
	var w := size.x
	var h := size.y
	# Button-centre x positions in this node's local space.
	var centers: Array[float] = []
	var menu := get_node_or_null("%BottomMenu")
	if menu != null:
		for c in menu.get_children():
			if c is Button:
				# Control has no to_local(); map the button centre's global x into
				# this node's local space (no rotation/scale in this UI).
				centers.append(c.global_position.x + c.size.x * 0.5 - global_position.x)
	# One continuous stroke: up the left side, across the notched top, down the right.
	var pts := PackedVector2Array()
	pts.append(Vector2(1.0, h))
	pts.append(Vector2(1.0, 1.0))
	var x := 1.0
	while x <= w - 1.0:
		var y := 1.0
		for cx in centers:
			var dx: float = x - cx
			if absf(dx) < NOTCH_HALF_W:
				y = maxf(y, 1.0 + NOTCH_DEPTH * 0.5 * (1.0 + cos(PI * dx / NOTCH_HALF_W)))
		pts.append(Vector2(x, y))
		x += 2.0
	pts.append(Vector2(w - 1.0, 1.0))
	pts.append(Vector2(w - 1.0, h))
	draw_polyline(pts, COLOR, LINE_W, true)
