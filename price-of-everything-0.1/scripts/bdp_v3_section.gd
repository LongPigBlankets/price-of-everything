extends MarginContainer
## Building Detail v3: a section of the detail panel (heading and content) inside a worn steel frame
## with a screw in each corner (res://assets/ui/bdp_v3/section_frame.png, drawn as a 9-slice). The
## frame's rim sits on this control's edge; its cast shadow reaches beyond it. Children go in
## `content`.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const FRAME: Texture2D = preload("res://assets/ui/bdp_v3/section_frame.png")
## The render's layout: shadow room around the rim and the rim's width (layout pixels at the capture
## scale 1.875), and the 9-slice corner in texture pixels (2 per logical pixel).
const OUTSET := 18.0 / 1.875
const RIM := 22.0 / 1.875
const CORNER_TEXELS := 62.0 * 2.0 / 1.875
const PADDING := 8.0

var content: VBoxContainer


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
	Nine.paint(self, FRAME, Rect2(Vector2.ZERO, size).grow(OUTSET), CORNER_TEXELS)
