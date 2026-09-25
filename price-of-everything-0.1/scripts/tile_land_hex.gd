extends Control
## Tile view v3: the tile's land as a hex of squares, one square per unit of land and as many squares as the
## tile can hold, so a mountain's hex is smaller than a rural one's (docs/tile-view-ds2-plan.md §9). It fills
## from the bottom row up, left to right: other companies' land and the land's own woods and ruins, then your
## buildings, your free land and the land you can buy. The top of the fill is then everyone's space used,
## the figure the planning rule counts, and the planning limit is the stepped line between the 100th square
## and the 101st, striped yellow and black like the hazard tape on a factory floor so it reads on every
## company's livery.
##
## Two looks. Collapsed, an LED dot-matrix screen at the top of the panel, read at a glance; a click asks for
## the full view. Expanded, an annunciator panel of backlit windows: each building's windows joined in one
## shade (yours in shades of your company's livery, other companies' in the map's paper white) with a dark
## line between buildings. Under the pointer a building's squares light up and its name shows; in the full
## view a click opens it.

signal expand_requested
signal building_clicked(instance_id: String)

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const PlayerColours := preload("res://scripts/player_colours.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const HOUSING: Texture2D = preload("res://assets/ui/bdp_v3/diag_plastic.png")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
const CAPTURE_SCALE := 1.875
const TEXELS := 2.0 / 1.875
## From layout.json, in layout pixels: the mini screen's shadow room, bezel and pane corner (the collapsed
## look's case), and the diagnostics' black plastic plate's shadow room and corner (the full view's housing),
## with Building Detail's silver screws in its corners.
const SCREEN_MARGIN := 8.0
const SCREEN_RIM := 7.0
const SCREEN_RADIUS := 5.0
const HOUSING_MARGIN := 14.0
const HOUSING_CORNER := 40.0
const SCREW_SIZE := 30.0 / 1.875
const SCREW_INSET := 9.0
## The map's tiles are flat topped, 540 wide by 480 tall; the hex keeps their proportions.
const TILE_ASPECT := 480.0 / 540.0
## Square pitch and the gap round each square, in logical pixels, for each look, and the room between the
## full view's hex and its housing.
const COLLAPSED_PITCH := 5.6
const COLLAPSED_GAP := 1.3
const EXPANDED_PITCH := 16.0
const EXPANDED_GAP := 3.0
const EXPANDED_PAD := 20.0
## The collapsed screen is one size whatever the tile: room for the biggest hex, 200 squares.
const COLLAPSED_BOX := Vector2(116.0, 104.0)
## Lightness steps between buildings' shades, in OKHSL, repeating: four levels 0.12 apart, in an order that
## keeps buildings one or two apart in the fill at least that far apart (a building's squares can sit on the
## row above its last neighbour but one). Other companies' step down from paper white.
const YOUR_STEPS := [0.0, 0.24, -0.12, 0.12]
const THEIR_STEPS := [0.0, -0.14, -0.06, -0.2]
const UNLIT := Color("#262a30")
const UNLIT_WINDOW := Color("#30343a")
const STONE := Color("#8f8a7e")
const PANE := Color("#0d1014")
const WELL := Color("#131416")
const HAZARD := Color("#f2c230")
const HAZARD_DARK := Color("#16171a")
## Your buildings' shades stay at least this light (OKHSL), so a dark livery still reads as lit against the
## unlit squares; other companies' paper white stays at least this light. None go past SHADE_CEILING.
const YOUR_FLOOR := 0.42
const THEIR_FLOOR := 0.6
const SHADE_CEILING := 0.95
const OPEN_RING := Color("#0b2340")

## Drawn as the full view rather than the screen.
var expanded := false:
	set(v):
		expanded = v
		_resize()
## The full view is showing (collapsed look only): its case gets a ring, as a latched key sits down.
var open := false:
	set(v):
		open = v
		queue_redraw()
## The groups in fill order: {kind, colour, name, instance_id, units, construction}, kind one of theirs,
## feature, yours, free, buy.
var groups: Array = []
## Row widths, bottom to top, and each square's group.
var rows: Array = []
var cell_group := PackedInt32Array()
## Squares at or below the planning limit.
var limit := 100
var _hover := -1
var _cells: Array[Rect2] = []
var _row_start := PackedInt32Array()
var _cell_row := PackedInt32Array()
var _pairs: Array = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_resize()


## Row widths, bottom to top, for a flat-topped hex of exactly `n` squares in the map tile's proportions:
## each row as wide as a regular hex is at that height, rounded so the rows add up to `n`.
static func hex_rows(n: int) -> Array:
	if n <= 0:
		return []
	var widest := sqrt(float(n) / (0.75 * TILE_ASPECT))   # a flat-topped hex's area is 3/4 of width x height
	var count := maxi(1, roundi(widest * TILE_ASPECT))
	var ideal: Array = []
	var total := 0.0
	for r in count:
		var t := absf((r + 0.5) - count * 0.5) / (count * 0.5)
		var x := widest * (1.0 - 0.5 * t)
		ideal.append(x)
		total += x
	var widths: Array = []
	var remainders: Array = []
	var sum := 0
	for r in count:
		var x: float = float(ideal[r]) * float(n) / total
		var w := maxi(1, floori(x))
		widths.append(w)
		sum += w
		remainders.append([x - floorf(x), r])
	# The rest goes to the rows with the largest remainders, the lower row first on a tie: a symmetric
	# pair gets one each, and the hex stays level.
	remainders.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) + 0.000001 or (absf(float(a[0]) - float(b[0])) <= 0.000001 and int(a[1]) < int(b[1])))
	var i := 0
	while sum < n:
		widths[int(remainders[i % count][1])] += 1
		sum += 1
		i += 1
	while sum > n:
		var widest_row := 0
		for r in count:
			if int(widths[r]) > int(widths[widest_row]):
				widest_row = r
		widths[widest_row] -= 1
		sum -= 1
	return widths


## `count` shades of `base` a step apart in lightness. The steps are taken round the base's own lightness,
## moved just enough that none falls below `floor` or past SHADE_CEILING, so no two are clamped together.
static func shades(base: Color, count: int, steps: Array, floor := 0.2) -> Array:
	var lowest := 0.0
	var highest := 0.0
	for step in steps:
		lowest = minf(lowest, float(step))
		highest = maxf(highest, float(step))
	var centre := clampf(base.ok_hsl_l, floor - lowest, SHADE_CEILING - highest)
	var out: Array = []
	for i in count:
		var l := centre + float(steps[i % steps.size()])
		out.append(Color.from_ok_hsl(base.ok_hsl_h, base.ok_hsl_s, l))
	return out


## `chart` is TileViewData.land_chart_data, `totals` TileViewData.land_totals.
func configure(chart: Dictionary, totals: Dictionary) -> void:
	groups.clear()
	var yours := 0
	var theirs := 0
	for seg: Dictionary in chart.get("segments", []):
		var kind := "yours"
		if bool(seg.get("feature", false)) or bool(seg.get("is_ruins", false)):
			kind = "feature"
		elif bool(seg.get("is_other", false)):
			kind = "theirs"
		groups.append({"kind": kind, "units": float(seg.get("size", 0.0)), "name": str(seg.get("tooltip", seg.get("name", ""))),
			"short": str(seg.get("name", "")), "instance_id": str(seg.get("instance_id", "")),
			"construction": bool(seg.get("is_construction", false))})
		if kind == "yours":
			yours += 1
		elif kind == "theirs":
			theirs += 1
	var livery := PlayerColours.active_color()
	var your_shades := shades(livery, yours, YOUR_STEPS, YOUR_FLOOR)
	var their_shades := shades(PlayerColours.NPC, theirs, THEIR_STEPS, THEIR_FLOOR)
	var yi := 0
	var ti := 0
	for g: Dictionary in groups:
		match str(g.kind):
			"yours":
				g["colour"] = your_shades[yi]
				yi += 1
			"theirs":
				g["colour"] = their_shades[ti]
				ti += 1
			_:
				g["colour"] = STONE
	var free := int(totals.get("free", 0))
	var buy := int(totals.get("buyable", 0))
	if free > 0:
		groups.append({"kind": "free", "units": float(free), "name": "%d free to build on" % free, "short": "Your free land",
			"instance_id": "", "construction": false, "colour": your_shades[0] if yours > 0 else livery})
	if buy > 0:
		groups.append({"kind": "buy", "units": float(buy), "name": "%d you can buy" % buy, "short": "To buy",
			"instance_id": "", "construction": false, "colour": UNLIT})
	var total := 0.0
	for g: Dictionary in groups:
		total += float(g.units)
	# The whole tile, or more when it holds more than it should (built past the land owned).
	var n := maxi(int(chart.get("type_cap", totals.get("max", 0))), roundi(total))
	rows = hex_rows(n)
	cell_group = PackedInt32Array()
	cell_group.resize(n)
	cell_group.fill(-1)
	var cum := 0.0
	for gi in groups.size():
		var a := roundi(cum)
		cum += float(groups[gi].units)
		for k in range(a, mini(roundi(cum), n)):
			cell_group[k] = gi
	limit = int(BuildingState.DENSITY_SOFT_CAPACITY)
	_hover = -1
	_resize()


func _resize() -> void:
	var widest := 0
	for w in rows:
		widest = maxi(widest, int(w))
	if expanded:
		custom_minimum_size = Vector2(widest, rows.size()) * EXPANDED_PITCH + Vector2.ONE * 2.0 * EXPANDED_PAD
	else:
		custom_minimum_size = COLLAPSED_BOX
	_layout()
	queue_redraw()


func _pitch() -> float:
	return EXPANDED_PITCH if expanded else COLLAPSED_PITCH


func _gap() -> float:
	return EXPANDED_GAP if expanded else COLLAPSED_GAP


func _layout() -> void:
	_cells.clear()
	_row_start = PackedInt32Array()
	_row_start.resize(rows.size())
	_cell_row = PackedInt32Array()
	var p := _pitch()
	var gap := _gap()
	var widest := 0
	for w in rows:
		widest = maxi(widest, int(w))
	var area := size if size != Vector2.ZERO else custom_minimum_size
	var origin := (area - Vector2(widest, rows.size()) * p) * 0.5
	var k := 0
	for r in rows.size():
		_row_start[r] = k
		var w := int(rows[r])
		var y := origin.y + (rows.size() - 1 - r) * p
		var x0 := origin.x + (widest - w) * p * 0.5
		for i in w:
			_cells.append(Rect2(x0 + i * p + gap * 0.5, y + gap * 0.5, p - gap, p - gap))
			_cell_row.append(r)
			k += 1
	_pairs = _find_neighbours()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


## The square under a point, or -1.
func cell_at(p: Vector2) -> int:
	var half := _gap() * 0.5
	for k in _cells.size():
		if _cells[k].grow(half).has_point(p):
			return k
	return -1


func group_at(p: Vector2) -> int:
	var k := cell_at(p)
	return cell_group[k] if k >= 0 and k < cell_group.size() else -1


func _get_tooltip(at: Vector2) -> String:
	var gi := group_at(at)
	var hint := "" if expanded else "Click to show the land in full"
	if gi < 0:
		return hint
	var g: Dictionary = groups[gi]
	var line := str(g.name)
	if str(g.kind) in ["yours", "theirs", "feature"]:
		line = "%s, %d land%s" % [g.name, roundi(float(g.units)), ", under construction" if bool(g.construction) else ""]
	return line if hint == "" else "%s\n%s" % [line, hint]


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		var gi := group_at(motion.position)
		if gi != _hover:
			_hover = gi
			var opens := expanded and gi >= 0 and str(groups[gi].instance_id) != ""
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (opens or not expanded) else Control.CURSOR_ARROW
			queue_redraw()
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not expanded:
		expand_requested.emit()
		accept_event()
		return
	var gi := group_at(mb.position)
	if gi >= 0 and str(groups[gi].instance_id) != "":
		building_clicked.emit(str(groups[gi].instance_id))
		accept_event()


## A square's colour in this look.
func colour_of(gi: int) -> Color:
	if gi < 0:
		return UNLIT_WINDOW if expanded else UNLIT
	var g: Dictionary = groups[gi]
	var c: Color = g.colour
	match str(g.kind):
		"buy":
			c = UNLIT_WINDOW if expanded else UNLIT
		"free":
			c = c.lerp(WELL if expanded else PANE, 0.62)
		"theirs", "feature":
			if not expanded:
				c = c.lerp(PANE, 0.35)
	if gi == _hover and str(g.kind) != "buy":
		c = c.lerp(Color.WHITE, 0.3)
	return c


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	if expanded:
		Nine.paint(self, HOUSING, box.grow(HOUSING_MARGIN / CAPTURE_SCALE), (HOUSING_MARGIN + HOUSING_CORNER) * TEXELS)
		for corner in [Vector2(SCREW_INSET, SCREW_INSET), Vector2(size.x - SCREW_INSET, SCREW_INSET),
				Vector2(SCREW_INSET, size.y - SCREW_INSET), Vector2(size.x - SCREW_INSET, size.y - SCREW_INSET)]:
			draw_texture_rect(SCREW, Rect2(corner - Vector2.ONE * SCREW_SIZE * 0.5, Vector2.ONE * SCREW_SIZE), false)
		_draw_seams()
	else:
		var corner := (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * TEXELS
		Nine.paint(self, SCREEN, box.grow(SCREEN_MARGIN / CAPTURE_SCALE), corner)
		draw_rect(box.grow(-SCREEN_RIM / CAPTURE_SCALE), PANE)
	for k in _cells.size():
		var gi := cell_group[k] if k < cell_group.size() else -1
		var c := colour_of(gi)
		var r := _cells[k]
		var lit := gi >= 0 and str(groups[gi].kind) != "buy"
		if expanded:
			draw_rect(r, c)
			draw_line(r.position + Vector2(0.5, 0.5), Vector2(r.end.x - 0.5, r.position.y + 0.5), c.lightened(0.2), 1.0)
			draw_line(Vector2(r.position.x + 0.5, r.end.y - 0.5), r.end - Vector2(0.5, 0.5), c.darkened(0.25), 1.0)
			if lit and bool(groups[gi].construction):
				draw_line(r.position + Vector2(2, r.size.y - 2), r.position + Vector2(r.size.x - 2, 2), c.darkened(0.45), 1.5)
		else:
			if lit:
				draw_rect(r.grow(0.9), Color(c, 0.22))
			draw_rect(r, c.darkened(0.3) if lit and bool(groups[gi].construction) else c)
	_draw_limit()
	if not expanded:
		var corner := (SCREEN_MARGIN + SCREEN_RIM + SCREEN_RADIUS + 2.0) * TEXELS
		Nine.paint(self, GLASS, box.grow(SCREEN_MARGIN / CAPTURE_SCALE), corner)
		if open:
			draw_rect(box.grow(SCREEN_MARGIN / CAPTURE_SCALE - 1.0), OPEN_RING, false, 2.0)


## Pairs of neighbouring squares, [a, b, vertical]: across a row's gap (b right of a), or across the gap
## between a row and the one above it where the two squares overlap (b above a).
func _find_neighbours() -> Array:
	var out: Array = []
	for r in rows.size():
		var start := _row_start[r]
		var w := int(rows[r])
		for i in w - 1:
			out.append([start + i, start + i + 1, false])
		if r + 1 >= rows.size():
			continue
		var up := _row_start[r + 1]
		for i in w:
			for j in int(rows[r + 1]):
				if _overlap(start + i, up + j) > 0.5:
					out.append([start + i, up + j, true])
	return out


func _overlap(a: int, b: int) -> float:
	var half := _gap() * 0.5
	var ra := _cells[a].grow(half)
	var rb := _cells[b].grow(half)
	return minf(ra.end.x, rb.end.x) - maxf(ra.position.x, rb.position.x)


## The full view joins a building's windows: its colour, a shade darker, across the gap between two of its
## squares, so the dark gaps left are the lines between buildings.
func _draw_seams() -> void:
	for pair: Array in _pairs:
		var a := int(pair[0])
		var b := int(pair[1])
		var ga := cell_group[a] if a < cell_group.size() else -1
		if ga < 0 or ga != (cell_group[b] if b < cell_group.size() else -1):
			continue
		var seam := colour_of(ga).darkened(0.12)
		var ra := _cells[a]
		var rb := _cells[b]
		if bool(pair[2]):
			var x0 := maxf(ra.position.x, rb.position.x)
			var x1 := minf(ra.end.x, rb.end.x)
			if x1 > x0:
				draw_rect(Rect2(x0, rb.end.y, x1 - x0, ra.position.y - rb.end.y), seam)
			continue
		var gx0 := ra.end.x
		var gx1 := rb.position.x
		draw_rect(Rect2(gx0, ra.position.y, gx1 - gx0, ra.size.y), seam)
		# Carry the joint on into the gap above and below where every square round that corner is the
		# same building, or a dot of the dark line shows through at each corner.
		var gap := _gap()
		var r := _cell_row[a]
		if r + 1 < rows.size() and _row_all_of(r + 1, gx0, gx1, ga):
			draw_rect(Rect2(gx0, ra.position.y - gap, gx1 - gx0, gap), seam)
		if r > 0 and _row_all_of(r - 1, gx0, gx1, ga):
			draw_rect(Rect2(gx0, ra.end.y, gx1 - gx0, gap), seam)


## Whether the squares of row `r` that reach across [x0, x1] are all of group `g` (and there are some).
func _row_all_of(r: int, x0: float, x1: float, g: int) -> bool:
	var half := _gap() * 0.5
	var start := _row_start[r]
	var any := false
	for i in int(rows[r]):
		var k := start + i
		var box := _cells[k].grow(half)
		if box.end.x <= x0 or box.position.x >= x1:
			continue
		if (cell_group[k] if k < cell_group.size() else -1) != g:
			return false
		any = true
	return any


## The planning limit as hazard tape: a dark band with yellow dashes along it, and in the full view a short
## tab past the hex at each end, where an alarm mark sits on a gauge.
func _draw_limit() -> void:
	var segments := limit_segments()
	if segments.is_empty():
		return
	if expanded:
		var left: Array = segments[0]
		var right: Array = segments[0]
		for seg: Array in segments:
			if (seg[0] as Vector2).y == (seg[1] as Vector2).y:
				if (seg[0] as Vector2).x < (left[0] as Vector2).x or left[0].y != left[1].y:
					left = seg
				if (seg[1] as Vector2).x > (right[1] as Vector2).x or right[0].y != right[1].y:
					right = seg
		segments = segments + [[(left[0] as Vector2) - Vector2(10, 0), left[0]], [right[1], (right[1] as Vector2) + Vector2(10, 0)]]
	var band := 5.0 if expanded else 2.6
	var stripe := 3.0 if expanded else 1.4
	var dash := 5.0 if expanded else 2.2
	for seg: Array in segments:
		draw_line(seg[0], seg[1], HAZARD_DARK, band)
	for seg: Array in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var t := 0.0
		while t < length:
			draw_line(a + dir * t, a + dir * minf(t + dash, length), HAZARD, stripe)
			t += dash * 2.0


## The planning limit's line: the edges between a square inside the limit and a neighbour past it.
func limit_segments() -> Array:
	var out: Array = []
	if limit <= 0 or limit >= _cells.size():
		return out
	var half := _gap() * 0.5
	for pair: Array in _pairs:
		var a := int(pair[0])
		var b := int(pair[1])
		if (a < limit) == (b < limit):
			continue
		var ra := _cells[a].grow(half)
		var rb := _cells[b].grow(half)
		if bool(pair[2]):
			var y := ra.position.y
			out.append([Vector2(maxf(ra.position.x, rb.position.x), y), Vector2(minf(ra.end.x, rb.end.x), y)])
		else:
			out.append([Vector2(ra.end.x, ra.position.y), Vector2(ra.end.x, ra.end.y)])
	return out
