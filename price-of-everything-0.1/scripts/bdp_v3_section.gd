extends MarginContainer
## Building Detail v3: a section of the detail panel (heading and content) inside a worn steel frame
## with a screw in each corner, set on the rim's centre line (res://assets/ui/bdp_v3/section_frame.png,
## drawn as a 9-slice). The frame's rim sits on this control's edge; its cast shadow reaches beyond it.
## Children go in `content`.
##
## `style` "plastic" draws a dark moulded plastic plate over the whole section instead (diag_plastic.png,
## also a 9-slice), with silver screws (screw_silver.png) set along its top and down its sides, spaced
## evenly for its size. `door_until`, when set, puts the shipments' rolling door behind the section's top,
## reaching down to just below that control (bdp_v3_door.gd), with a shade where the bay opens below it.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Door := preload("res://scripts/bdp_v3_door.gd")
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
## screws sit this far in from the plate's edges, about this far apart.
const PLASTIC_MARGIN := 14.0 / 1.875
const PLASTIC_CORNER_TEXELS := (14.0 + 40.0) * 2.0 / 1.875
const SCREW_INSET := 9.0
const SCREW_SPACING := 56.0
## How far the door reaches below `door_until`, and the depth of the shade under it.
const DOOR_OVERHANG := 6.0
const BAY_SHADE := 14.0

var content: VBoxContainer
var style := "steel":
	set(v):
		style = v
		queue_redraw()
var door_until: Control:
	set(v):
		door_until = v
		if v != null:
			v.item_rect_changed.connect(queue_redraw)
		queue_redraw()


## Where the plastic plate's silver screws go, for a `plate_size`-pixel plate: along the top, then down
## each side below the top row.
static func screw_points(plate_size: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var span_x := plate_size.x - 2.0 * SCREW_INSET
	var n_top := maxi(1, roundi(span_x / SCREW_SPACING))
	for i in n_top + 1:
		pts.append(Vector2(SCREW_INSET + span_x * i / n_top, SCREW_INSET))
	var span_y := plate_size.y - 2.0 * SCREW_INSET
	var n_side := maxi(1, roundi(span_y / SCREW_SPACING))
	for i in range(1, n_side + 1):
		var y := SCREW_INSET + span_y * i / n_side
		pts.append(Vector2(SCREW_INSET, y))
		pts.append(Vector2(plate_size.x - SCREW_INSET, y))
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
	if door_until != null and is_instance_valid(door_until) and door_until.is_visible_in_tree():
		var bottom := (door_until.get_global_rect().end - get_global_rect().position).y + DOOR_OVERHANG
		var door := Rect2(RIM, RIM, size.x - 2.0 * RIM, bottom - RIM)
		Door.paint(self, door)
		# The bay below the door is in the door's shadow for a little way.
		for i in 6:
			var t := float(i) / 6.0
			draw_rect(Rect2(RIM, door.end.y + BAY_SHADE * t, door.size.x, BAY_SHADE / 6.0), Color(0, 0, 0, 0.42 * (1.0 - t)))
	Nine.paint(self, FRAME, Rect2(Vector2.ZERO, size).grow(OUTSET), CORNER_TEXELS)
