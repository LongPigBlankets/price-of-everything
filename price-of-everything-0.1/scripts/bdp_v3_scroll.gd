extends StyleBox
## Building Detail v3: the scrollbar. The rail is a steel strip screwed to the backing with a slot down
## its middle; the slider is a cream plastic cap riding in the slot, with a ribbed grip
## (res://assets/ui/bdp_v3/scroll_rail.png and scroll_thumb.png, rendered by
## tools/button_mockup/cluster.html?export). apply() sets them on a ScrollContainer's vertical bar,
## so scrolling, dragging and paging stay Godot's own.
##
## Each is drawn as a vertical three-slice: the ends keep their size and the length between them
## stretches. The renders allow it, because the rail's steel is brushed along its length and the
## slider is plain between its ends. The slider's grip keeps its size in the middle while there is
## room for it. StyleBoxTexture draws one texture pixel per screen pixel, and these renders are at two
## per logical pixel, like every v3 layer, so this draws the slices itself.

const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
const RAIL: Texture2D = preload("res://assets/ui/bdp_v3/scroll_rail.png")
const THUMB: Texture2D = preload("res://assets/ui/bdp_v3/scroll_thumb.png")
## From layout.json (scroll_rail, scroll_thumb), in layout pixels: the rows kept at each end, the
## slider's grip rows, and how far the slider stops short of the rail's ends (clear of its screws).
const RAIL_CAP := 30.0
const THUMB_CAP := 15.0
const THUMB_GRIP := Vector2(82.5, 127.5)
const TRAVEL_INSET := 22.5
## The slider under the pointer, and held.
const HOVER_TINT := Color(1.07, 1.07, 1.07)
const PRESS_TINT := Color(0.93, 0.93, 0.93)
const ITEMS: Array[StringName] = [&"scroll", &"scroll_focus", &"grabber", &"grabber_highlight", &"grabber_pressed"]

var texture: Texture2D
## Layout pixels kept at each end, and the grip's rows (none when zero).
var cap := 0.0
var grip := Vector2.ZERO
var tint := Color.WHITE


static func make(tex: Texture2D, cap_px: float, grip_rows: Vector2 = Vector2.ZERO, tint_colour: Color = Color.WHITE) -> StyleBox:
	var sb: StyleBox = load("res://scripts/bdp_v3_scroll.gd").new()
	sb.texture = tex
	sb.cap = cap_px
	sb.grip = grip_rows
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
	bar.add_theme_stylebox_override(&"grabber", make(THUMB, THUMB_CAP, THUMB_GRIP))
	bar.add_theme_stylebox_override(&"grabber_highlight", make(THUMB, THUMB_CAP, THUMB_GRIP, HOVER_TINT))
	bar.add_theme_stylebox_override(&"grabber_pressed", make(THUMB, THUMB_CAP, THUMB_GRIP, PRESS_TINT))


## True when `scroll`'s vertical bar wears the v3 rail.
static func is_applied(scroll: ScrollContainer) -> bool:
	var sb := scroll.get_v_scroll_bar().get_theme_stylebox(&"scroll")
	return sb != null and sb.get_script() == load("res://scripts/bdp_v3_scroll.gd")


func _get_minimum_size() -> Vector2:
	if texture == null:
		return Vector2.ZERO
	return Vector2(texture.get_width() / TEXELS_PER_PIXEL, 2.0 * cap / CAPTURE_SCALE)


## The slices for a `height`-pixel draw, top to bottom: [source top, source bottom (texture pixels),
## drawn height]. The ends keep their size (halved when there is not room for both); the grip, when
## there is one, keeps its size in the middle while it fits and is left out when it does not.
func slices(height: float) -> Array:
	if texture == null or height <= 0.0:
		return []
	var tex_h := texture.get_height() * 1.0
	var k := TEXELS_PER_PIXEL / CAPTURE_SCALE   # texture pixels per layout pixel
	var end_tx := cap * k
	var end_px := minf(cap / CAPTURE_SCALE, height * 0.5)
	var mid := height - 2.0 * end_px
	var out: Array = [[0.0, end_tx, end_px]]
	if grip == Vector2.ZERO:
		out.append([end_tx, tex_h - end_tx, mid])
	else:
		var grip_px := (grip.y - grip.x) / CAPTURE_SCALE
		if mid >= grip_px + 2.0:
			var plain := (mid - grip_px) * 0.5
			out.append([end_tx, grip.x * k, plain])
			out.append([grip.x * k, grip.y * k, grip_px])
			out.append([grip.y * k, tex_h - end_tx, plain])
		else:
			out.append([end_tx, grip.x * k, mid])   # plain only, from above the grip
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
