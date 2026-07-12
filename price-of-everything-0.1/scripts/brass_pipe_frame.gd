extends Control
## Overlay that paints the turn summary's brass pipe frame around its rect: a manual
## 9-slice of brass_pipe_frame_transparent.png with the corners scaled down (168px
## source -> DEST_SLICE on screen) and the edges stretched, transparent centre. Add it
## as a full-rect child on top of a panel — it ignores the mouse and repaints on resize.

const BRASS: Texture2D = preload("res://assets/ui/brass_pipe_frame_transparent.png")
const SRC_SLICE := 168.0   # corner size in the source texture
const DEST_SLICE := 30.0    # corner size on screen

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Added as the last child of a PanelContainer (content_margin 0) → the container
	# auto-fits it to the full panel rect and re-fits on resize/drag.
	resized.connect(queue_redraw)

func _draw() -> void:
	var ts: Vector2 = BRASS.get_size()
	var s: float = minf(SRC_SLICE, minf(ts.x * 0.5, ts.y * 0.5))
	var d: float = minf(DEST_SLICE, minf(size.x * 0.35, size.y * 0.35))
	var sr: float = ts.x - s
	var sb: float = ts.y - s
	var dr: float = size.x - d
	var db: float = size.y - d
	# Corners (scaled).
	_blit(Rect2(0, 0, s, s), Rect2(0, 0, d, d))
	_blit(Rect2(sr, 0, s, s), Rect2(dr, 0, d, d))
	_blit(Rect2(0, sb, s, s), Rect2(0, db, d, d))
	_blit(Rect2(sr, sb, s, s), Rect2(dr, db, d, d))
	# Edges (stretched between the corners).
	var mid_w: float = maxf(0.0, ts.x - 2.0 * s)
	var mid_h: float = maxf(0.0, ts.y - 2.0 * s)
	if size.x - 2.0 * d > 0.0:
		_blit(Rect2(s, 0.0, mid_w, s), Rect2(d, 0.0, size.x - 2.0 * d, d))        # top
		_blit(Rect2(s, sb, mid_w, s), Rect2(d, db, size.x - 2.0 * d, d))          # bottom
	if size.y - 2.0 * d > 0.0:
		_blit(Rect2(0.0, s, s, mid_h), Rect2(0.0, d, d, size.y - 2.0 * d))        # left
		_blit(Rect2(sr, s, s, mid_h), Rect2(dr, d, d, size.y - 2.0 * d))          # right

func _blit(src: Rect2, dst: Rect2) -> void:
	draw_texture_rect_region(BRASS, dst, src)
