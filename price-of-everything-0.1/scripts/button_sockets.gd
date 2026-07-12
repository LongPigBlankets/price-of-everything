extends Control
## Draws a recessed socket on the tray behind each bottom-menu button (alt menu
## only), so the buttons read as set into drilled holes. Sockets sit at the
## buttons' resting positions; a selected button rises out of its socket,
## revealing the dark well beneath.

const SOCKET_TEX := preload("res://assets/icons/ui_icons/alt/_socket.png")
const SCALE := 1.10  # socket size relative to the button (rim shows just outside)

func _ready() -> void:
	resized.connect(queue_redraw)
	var menu := get_node_or_null("%BottomMenu")
	if menu != null:
		menu.sort_children.connect(queue_redraw)
	call_deferred("queue_redraw")

func _draw() -> void:
	var menu := get_node_or_null("%BottomMenu")
	if menu == null:
		return
	for c in menu.get_children():
		if c is Button:
			var sz: float = c.size.x * SCALE
			var cx: float = c.global_position.x + c.size.x * 0.5 - global_position.x
			var cy: float = c.global_position.y + c.size.y * 0.5 - global_position.y
			draw_texture_rect(SOCKET_TEX, Rect2(cx - sz * 0.5, cy - sz * 0.5, sz, sz), false)
