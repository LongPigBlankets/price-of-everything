extends Control
## A navy dashed rectangle outline that fills its rect. Used as the "In use for storage" cell
## of the battery storage diagram (building detail panel).

var color: Color = Color(0.0, 0.119856, 0.243095, 1.0)
var line_width: float = 2.0
var dash: float = 6.0

func _ready() -> void:
	resized.connect(queue_redraw)

func _draw() -> void:
	var tl := Vector2(1, 1)
	var tr := Vector2(size.x - 1, 1)
	var br := Vector2(size.x - 1, size.y - 1)
	var bl := Vector2(1, size.y - 1)
	draw_dashed_line(tl, tr, color, line_width, dash)
	draw_dashed_line(tr, br, color, line_width, dash)
	draw_dashed_line(br, bl, color, line_width, dash)
	draw_dashed_line(bl, tl, color, line_width, dash)
