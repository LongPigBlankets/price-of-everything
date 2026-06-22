extends StyleBox
## Metallic Building-Ledger row plate. A rounded rect with a continuous bluish-silver rim (lit
## a touch brighter at the top-left, gently deeper — but never dark grey — toward the bottom-right)
## over a diagonal steel-navy sheen. Inspired by the panels' bluish-silver buttons; lit from the
## top-left like bevel_edge.gd. Set `hover` to brighten the fill.

var hover := false

const BORDER := 4.0    # metallic-grey rim thickness
const RADIUS := 11.0   # outer corner radius
const PAD_H := 8.0     # cell inset beyond the rim (BORDER + PAD_H == ROW_INSET 12 in the ledger)
const PAD_V := 15.0    # holds the row height steady after the rim thinned 5 → 4
const CORNER_SEGS := 8

# Rim: a uniform metallic light blue-grey (#b2bfcc) all around.
const RIM_TL := Color("#b2bfcc")
const RIM_BR := Color("#b2bfcc")

# Steel-navy interior sheen (brightest top-left → darkest bottom-right).
const FILL_TL := Color(0.17, 0.29, 0.41)
const FILL_BR := Color(0.03, 0.10, 0.17)
const FILL_TL_HOVER := Color(0.27, 0.41, 0.55)
const FILL_BR_HOVER := Color(0.06, 0.16, 0.26)

func _get_content_margin(margin: int) -> float:
	match margin:
		SIDE_LEFT, SIDE_RIGHT:
			return BORDER + PAD_H
		SIDE_TOP, SIDE_BOTTOM:
			return BORDER + PAD_V
	return BORDER

func _draw(to_canvas_item: RID, rect: Rect2) -> void:
	# Outer rounded rect = the bluish-silver rim (a continuous gradient, lighter top-left).
	var outer := _rounded_rect(rect, RADIUS)
	RenderingServer.canvas_item_add_polygon(to_canvas_item, outer, _diagonal_colors(outer, rect, RIM_TL, RIM_BR))

	# Inner rounded rect (inset by the rim) = the steel-navy sheen fill.
	var fill_tl := FILL_TL_HOVER if hover else FILL_TL
	var fill_br := FILL_BR_HOVER if hover else FILL_BR
	var inner_rect := Rect2(rect.position + Vector2(BORDER, BORDER), rect.size - Vector2(BORDER * 2.0, BORDER * 2.0))
	var inner := _rounded_rect(inner_rect, maxf(2.0, RADIUS - BORDER))
	RenderingServer.canvas_item_add_polygon(to_canvas_item, inner, _diagonal_colors(inner, inner_rect, fill_tl, fill_br))

# Clockwise perimeter of a rounded rect (TR → BR → BL → TL arcs), as a convex polygon.
func _rounded_rect(rect: Rect2, r: float) -> PackedVector2Array:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var h := rect.size.y
	r = minf(r, minf(w, h) * 0.5)
	var corners := [
		[Vector2(x + w - r, y + r), -PI * 0.5, 0.0],          # top-right
		[Vector2(x + w - r, y + h - r), 0.0, PI * 0.5],       # bottom-right
		[Vector2(x + r, y + h - r), PI * 0.5, PI],            # bottom-left
		[Vector2(x + r, y + r), PI, PI * 1.5],               # top-left
	]
	var pts := PackedVector2Array()
	for c in corners:
		var centre: Vector2 = c[0]
		for i in range(CORNER_SEGS + 1):
			var a: float = lerpf(c[1], c[2], float(i) / float(CORNER_SEGS))
			pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts

# Colour each vertex by its position along the top-left → bottom-right diagonal.
func _diagonal_colors(pts: PackedVector2Array, rect: Rect2, c0: Color, c1: Color) -> PackedColorArray:
	var x := rect.position.x
	var y := rect.position.y
	var w := maxf(1.0, rect.size.x)
	var h := maxf(1.0, rect.size.y)
	var cols := PackedColorArray()
	for p in pts:
		var t := clampf(((p.x - x) / w + (p.y - y) / h) * 0.5, 0.0, 1.0)
		cols.append(c0.lerp(c1, t))
	return cols
