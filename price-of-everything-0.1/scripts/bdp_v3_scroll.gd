extends StyleBox
## Building Detail v3: the scrollbar. The rail is a steel strip screwed to the backing with a slot down
## its middle; the slider is a medium-dark grey rubber grip with diagonal ridges, riding in the slot
## (res://assets/ui/bdp_v3/scroll_rail.png and scroll_thumb.png, rendered by
## tools/button_mockup/cluster.html?export). apply() sets them on a ScrollContainer's vertical bar,
## so scrolling, dragging and paging stay Godot's own.
##
## Each is drawn in three pieces: the ends keep their size, and the length between them is filled.
## The rail's is stretched, which its render allows because its steel is brushed along its length.
## The slider's diagonal ridges can't stretch, so its length is filled with whole periods of them,
## each squeezed or eased a little so a whole number fits. StyleBoxTexture draws one texture pixel per
## screen pixel, and these renders are at two per logical pixel, like every v3 layer, so this draws
## the pieces itself.

const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
const RAIL: Texture2D = preload("res://assets/ui/bdp_v3/scroll_rail.png")
const THUMB: Texture2D = preload("res://assets/ui/bdp_v3/scroll_thumb.png")
## From layout.json (scroll_rail, scroll_thumb), in layout pixels: the rows kept at each end, the
## slider's ridge period and the row its repeat is taken from (mid-grip, where every period has ridges
## above and below it), and how far the slider stops short of the rail's ends (clear of its screws).
const RAIL_CAP := 30.0
const THUMB_CAP := 15.0
const THUMB_PERIOD := 7.5
const THUMB_REPEAT_FROM := 75.0
## The slider's repeat is drawn up to this many periods at a time.
const PERIODS_PER_DRAW := 8
const TRAVEL_INSET := 22.5
## The slider under the pointer, and held.
const HOVER_TINT := Color(1.07, 1.07, 1.07)
const PRESS_TINT := Color(0.93, 0.93, 0.93)
const ITEMS: Array[StringName] = [&"scroll", &"scroll_focus", &"grabber", &"grabber_highlight", &"grabber_pressed"]

var texture: Texture2D
## Layout pixels kept at each end; for a repeating length, its period and the row the repeat is taken
## from (a period of zero stretches the length instead).
var cap := 0.0
var period := 0.0
var repeat_from := 0.0
var tint := Color.WHITE


static func make(tex: Texture2D, cap_px: float, period_px: float = 0.0, repeat_row: float = 0.0, tint_colour: Color = Color.WHITE) -> StyleBox:
	var sb: StyleBox = load("res://scripts/bdp_v3_scroll.gd").new()
	sb.texture = tex
	sb.cap = cap_px
	sb.period = period_px
	sb.repeat_from = repeat_row
	sb.tint = tint_colour
	return sb


## Puts the v3 rail and slider on `scroll`'s vertical bar, or takes them off again.
static func apply(scroll: ScrollContainer, on: bool) -> void:
	var bar := scroll.get_v_scroll_bar()
	for item in ITEMS:
		bar.remove_theme_stylebox_override(item)
	bar.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS if on else CanvasItem.TEXTURE_FILTER_PARENT_NODE
	if not on:
		return
	var rail := make(RAIL, RAIL_CAP)
	rail.content_margin_top = TRAVEL_INSET / CAPTURE_SCALE
	rail.content_margin_bottom = TRAVEL_INSET / CAPTURE_SCALE
	bar.add_theme_stylebox_override(&"scroll", rail)
	bar.add_theme_stylebox_override(&"scroll_focus", rail)
	bar.add_theme_stylebox_override(&"grabber", make(THUMB, THUMB_CAP, THUMB_PERIOD, THUMB_REPEAT_FROM))
	bar.add_theme_stylebox_override(&"grabber_highlight", make(THUMB, THUMB_CAP, THUMB_PERIOD, THUMB_REPEAT_FROM, HOVER_TINT))
	bar.add_theme_stylebox_override(&"grabber_pressed", make(THUMB, THUMB_CAP, THUMB_PERIOD, THUMB_REPEAT_FROM, PRESS_TINT))


## True when `scroll`'s vertical bar wears the v3 rail.
static func is_applied(scroll: ScrollContainer) -> bool:
	var sb := scroll.get_v_scroll_bar().get_theme_stylebox(&"scroll")
	return sb != null and sb.get_script() == load("res://scripts/bdp_v3_scroll.gd")


func _get_minimum_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_width() / TEXELS_PER_PIXEL, 2.0 * cap / CAPTURE_SCALE)


## The pieces for a `height`-pixel draw, top to bottom: [source top, source bottom (texture pixels),
## drawn height]. The ends keep their size (halved when there is not room for both). The length between
## them is stretched, or, with a period, filled with whole periods from `repeat_from`, all scaled alike
## so that they fit.
func slices(height: float) -> Array:
	if texture == null or height <= 0.0:
		return []
	var tex_h := texture.get_height() * 1.0
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE   # texture pixels per layout pixel
	var end_tx := cap * k
	var end_px := minf(cap / CAPTURE_SCALE, height * 0.5)
	var mid := height - 2.0 * end_px
	var out: Array = [[0.0, end_tx, end_px]]
	if period <= 0.0:
		out.append([end_tx, tex_h - end_tx, mid])
	elif mid > 0.0:
		var period_px := period / CAPTURE_SCALE
		var n := maxi(1, roundi(mid / period_px))
		var fit := mid / (n * period_px)
		var left := n
		while left > 0:
			var m := mini(PERIODS_PER_DRAW, left)
			out.append([repeat_from * k, (repeat_from + m * period) * k, m * period_px * fit])
			left -= m
	out.append([tex_h - end_tx, tex_h, end_px])
	return out


func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	if rect.size.x <= 0.0:
		return
	var y := rect.position.y
	for s: Array in slices(rect.size.y):
		var h: float = s[2]
		if h > 0.0:
			RenderingServer.canvas_item_add_texture_rect_region(to_canvas_item, Rect2(rect.position.x, y, rect.size.x, h),
				texture.get_rid(), Rect2(0.0, s[0], texture.get_width(), float(s[1]) - float(s[0])), tint)
		y += h
