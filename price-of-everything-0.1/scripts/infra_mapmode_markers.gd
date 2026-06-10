extends Node2D
## World-space drawing for the Infrastructure mapmode. Every tile holding the
## selected infrastructure is a filled circle in that type's colour (80 world
## px across — full size at the most zoomed-in level, shrinking naturally as
## the camera zooms out), joined to adjacent same-infrastructure tiles by
## straight centre-to-centre lines (circles draw on top, so lines read as
## rim-to-rim). Links touching under-construction infrastructure are dashed;
## a stranded under-construction tile (no adjacent tile with the infra) gets
## a transparent cross cut out of its circle plus dashed stubs reaching
## halfway to each hex edge midpoint.
##
## Hovering a built tile (driven by map_overlay) glows its circle and every
## link touching it — white, radiating GLOW_REACH px beyond the shapes,
## drawn UNDER the line/circle composition — and floats a throughput card
## above the tile (same plate style as the logistics shipment hover panel).

const CIRCLE_DIAMETER := 80.0
const LINE_WIDTH := 10.0
const DASH_LEN := 24.0
# Infrastructure level styling: level 2 adds a thin "rail" running parallel to
# the main line (RAIL_GAP clear of its edge); level 3 adds one on each side.
const RAIL_WIDTH := 3.0
const RAIL_GAP := 2.0
const CROSS_HALF_WIDTH := 9.0    # half-thickness of the cut-out cross arms
const STUB_EDGE_FRACTION := 0.5  # stubs stop halfway to the edge midpoint
const ARC_SEGMENTS := 24
const GLOW_REACH := 30.0         # how far the hover glow radiates past the shapes
const GLOW_LAYERS := 6           # stacked translucent layers fake the falloff
const TILE_W := 540.0            # hex tile world width (matches the tileset)
const CARD_BG := Color(0.03, 0.05, 0.09, 0.97)
const CARD_BORDER := Color(0.7, 0.85, 1.0, 0.5)

var color := Color.WHITE
var circles: Array = []        # Vector2 tile centres — built infrastructure
var uc_circles: Array = []     # Vector2 — under construction with a neighbour
var stranded: Array = []       # {pos: Vector2, edge_mids: Array} — isolated UC
var solid_links: Array = []    # {a, b, level} — built <-> built
var dashed_links: Array = []   # {a, b, level} with an under-construction endpoint
var hover_pos := Vector2.INF   # hovered built tile centre (INF = no hover)
var hover_card_lines: Array = []  # throughput card rows; row 0 is the title

func set_hover(pos: Vector2, card_lines: Array) -> void:
	if pos == hover_pos and card_lines == hover_card_lines:
		return
	hover_pos = pos
	hover_card_lines = card_lines
	queue_redraw()

func _draw() -> void:
	if hover_pos != Vector2.INF:
		_draw_hover_glow()
	for link in solid_links:
		_draw_link(link.a, link.b, int(link.level), false)
	for link in dashed_links:
		_draw_link(link.a, link.b, int(link.level), true)
	var radius := CIRCLE_DIAMETER * 0.5
	for entry in stranded:
		_draw_stranded(entry.pos, entry.edge_mids, radius)
	for pos in circles:
		draw_circle(pos, radius, color)
	for pos in uc_circles:
		draw_circle(pos, radius, color)
	if hover_pos != Vector2.INF:
		_draw_hover_card()

# White radiance under the hovered tile's circle and its links: stacked
# translucent layers, widest and faintest first, shrinking toward the shapes.
func _draw_hover_glow() -> void:
	var radius := CIRCLE_DIAMETER * 0.5
	for k in range(GLOW_LAYERS, 0, -1):
		var t := float(k) / float(GLOW_LAYERS)
		var glow := Color(1, 1, 1, lerpf(0.16, 0.05, t))
		draw_circle(hover_pos, radius + GLOW_REACH * t, glow)
		for link in solid_links:
			_draw_link_glow(link, glow, GLOW_REACH * t)
		for link in dashed_links:
			_draw_link_glow(link, glow, GLOW_REACH * t)

func _draw_link_glow(link: Dictionary, glow: Color, extent: float) -> void:
	var a: Vector2 = link.a
	var b: Vector2 = link.b
	if a.distance_squared_to(hover_pos) > 1.0 and b.distance_squared_to(hover_pos) > 1.0:
		return
	# Halo spans the whole composition: just the main line at level 1, out to
	# the outer rail edges at levels 2/3.
	var comp_width: float = LINE_WIDTH if int(link.level) < 2 \
			else 2.0 * (LINE_WIDTH * 0.5 + RAIL_GAP + RAIL_WIDTH)
	draw_line(a, b, glow, comp_width + 2.0 * extent)

# Throughput card above the hovered tile — same plate/border/zoom-step sizing
# as the logistics overlay's shipment hover panel.
func _draw_hover_card() -> void:
	if hover_card_lines.is_empty():
		return
	var z := maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	var quarter_screen := TILE_W * 0.25 * z
	var step_px := 140.0
	if quarter_screen > 320.0:
		step_px = 280.0
	elif quarter_screen > 240.0:
		step_px = 210.0
	var world_w := step_px / z
	var pad := world_w * 0.08
	var avail := world_w - 2.0 * pad
	var font := ThemeDB.fallback_font
	# Font scales with the panel, shrinking only if a line would overflow.
	var base := maxf(8.0, world_w * 0.13)
	var max_w := 1.0
	for ln in hover_card_lines:
		max_w = maxf(max_w, font.get_string_size(str(ln), HORIZONTAL_ALIGNMENT_LEFT, -1, int(base)).x)
	var font_world := base
	if max_w > avail:
		font_world = base * (avail / max_w)
	font_world = maxf(6.0, font_world)
	var line_h := font_world * 1.35
	var world_h := 2.0 * pad + line_h * float(hover_card_lines.size())
	var origin := hover_pos - Vector2(world_w * 0.5, world_h + TILE_W * 0.35)
	draw_rect(Rect2(origin, Vector2(world_w, world_h)), CARD_BG)
	draw_rect(Rect2(origin, Vector2(world_w, world_h)), CARD_BORDER, false, maxf(1.0, 2.0 / z))
	var y := pad + font_world
	for i in hover_card_lines.size():
		var line_color: Color = DS.PALETTE.ACCENT if i == 0 else Color.WHITE
		draw_string(font, origin + Vector2(pad, y), str(hover_card_lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, avail, int(font_world), line_color)
		y += line_h

func _draw_link(a: Vector2, b: Vector2, level: int, dashed: bool) -> void:
	_draw_link_line(a, b, LINE_WIDTH, dashed)
	if level < 2:
		return
	var offset: Vector2 = (b - a).normalized().orthogonal() \
			* (LINE_WIDTH * 0.5 + RAIL_GAP + RAIL_WIDTH * 0.5)
	_draw_link_line(a + offset, b + offset, RAIL_WIDTH, dashed)
	if level >= 3:
		_draw_link_line(a - offset, b - offset, RAIL_WIDTH, dashed)

func _draw_link_line(from: Vector2, to: Vector2, width: float, dashed: bool) -> void:
	if dashed:
		draw_dashed_line(from, to, color, width, DASH_LEN)
	else:
		draw_line(from, to, color, width)

func _draw_stranded(pos: Vector2, edge_mids: Array, radius: float) -> void:
	# Dashed stubs start at the circle rim (the cross hole is see-through, so
	# they can't pass under the disc) and stop halfway to each edge midpoint.
	for mid in edge_mids:
		var to: Vector2 = pos + (mid - pos) * STUB_EDGE_FRACTION
		var from: Vector2 = pos + (mid - pos).normalized() * radius
		draw_dashed_line(from, to, color, LINE_WIDTH, DASH_LEN)
	# Circle with a transparent cross cut out of the middle: four quadrant
	# pieces, each the part of the disc beyond the cross arms.
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			draw_colored_polygon(_quadrant_points(pos, radius, sx, sy), color)

func _quadrant_points(center: Vector2, radius: float, sx: float, sy: float) -> PackedVector2Array:
	var w := CROSS_HALF_WIDTH
	var reach := sqrt(radius * radius - w * w)
	var points := PackedVector2Array()
	points.append(center + Vector2(w * sx, w * sy))
	var angle_from := atan2(reach, w)  # on the vertical arm's edge
	var angle_to := atan2(w, reach)    # on the horizontal arm's edge
	for i in ARC_SEGMENTS + 1:
		var angle := lerpf(angle_from, angle_to, float(i) / float(ARC_SEGMENTS))
		points.append(center + Vector2(cos(angle) * radius * sx, sin(angle) * radius * sy))
	return points
