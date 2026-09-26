extends Control
## Tile view v3: the tile's land as a hex, as big as the land the tile can hold (so a mountain's hex is
## smaller than a rural one's), filling from the bottom (docs/tile-view-ds2-plan.md §9). The planning rule
## counts everyone's space used, so the used land fills first, and the planning limit is drawn where the
## tile's first 100 units end, striped like the hazard tape on a factory floor: yellow on black, or red on
## white when the company's livery is itself yellow, so it never matches the player's buildings.
##
## Two looks. Collapsed, the mini hex at the top of the panel, read at a glance: one smooth hex laid straight
## onto the stainless plate with a thin black rim, filled from the bottom in flat bands whose areas are the
## land's shares (other companies', woods and ruins, your buildings, your free land, land to buy), one colour
## each, and the limit a level line across it; a click asks for the full view. Expanded, the split view: an annunciator panel of backlit
## windows, one square per unit of land on an aligned grid. The used land is laid out as one block per
## building, each as near square as the room allows, its windows joined in one shade (yours in shades of
## your company's livery, other companies' in the map's paper white) with a dark line between buildings;
## your free land and the land to buy follow in the order the tile fills. Under the pointer a building or a
## band lights up and its name shows; in the full view a click on a building opens it.

signal expand_requested
signal building_clicked(instance_id: String)

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const PlayerColours := preload("res://scripts/player_colours.gd")
const HOUSING: Texture2D = preload("res://assets/ui/bdp_v3/diag_plastic.png")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
const CAPTURE_SCALE := 1.875
const TEXELS := 2.0 / 1.875
## From layout.json, in layout pixels: the diagnostics' black plastic plate's shadow room and corner (the full
## view's housing), with Building Detail's silver screws in its corners.
const HOUSING_MARGIN := 14.0
const HOUSING_CORNER := 40.0
const SCREW_SIZE := 30.0 / 1.875
const SCREW_INSET := 9.0
## The map's tiles are flat topped, 540 wide by 480 tall; both hexes keep their proportions.
const TILE_ASPECT := 480.0 / 540.0
## The full view's square pitch, the gap round each square, and the room between the hex and its housing,
## in logical pixels.
const PITCH := 16.0
const GAP := 3.0
const PAD := 20.0
## The mini hex's room is one size whatever the tile. The biggest tile (200 units) fills it but for its rim
## and the ring it wears while the full view is open; a smaller tile's hex has the area its land bears to
## that. The rim is black, this wide in logical pixels, and the ring as far again past it.
const COLLAPSED_BOX := Vector2(128.0, 114.0)
const MINI_FULL := 200.0
const MINI_RIM := 2.0
const OPEN_RING_WIDTH := 3.0
const RIM := Color("#0e0f11")
## Lightness steps between buildings' shades in the full view, in OKHSL, repeating: four levels 0.12 apart,
## in an order that keeps buildings one or two apart in the layout at least that far apart. Other companies'
## step down from paper white.
const YOUR_STEPS := [0.0, 0.24, -0.12, 0.12]
const THEIR_STEPS := [0.0, -0.14, -0.06, -0.2]
## Your buildings' shades stay at least YOUR_FLOOR light (OKHSL), so a dark livery still reads as lit against
## the unlit squares, and no lighter than YOUR_CEILING, so a pale livery's lightest shade is still its colour
## and not the paper white of other companies' buildings. Theirs stay between THEIR_FLOOR and SHADE_CEILING.
const YOUR_FLOOR := 0.42
const YOUR_CEILING := 0.84
const THEIR_FLOOR := 0.6
const SHADE_CEILING := 0.95
const UNLIT := Color("#262a30")
const UNLIT_WINDOW := Color("#30343a")
const STONE := Color("#8f8a7e")
const PANE := Color("#0d1014")
const WELL := Color("#131416")
const HAZARD := Color("#f2c230")
const HAZARD_DARK := Color("#16171a")
const HAZARD_RED := Color("#e8281e")
const HAZARD_WHITE := Color("#f4f2ec")
const OPEN_RING := Color("#0b2340")
## The mini hex's bands, bottom up.
const BAND_ORDER := ["theirs", "feature", "yours", "free", "buy"]

## Drawn as the full view rather than the mini hex.
var expanded := false:
	set(v):
		expanded = v
		_resize()
## The full view is showing (mini hex only): its case gets a ring, as a latched key sits down.
var open := false:
	set(v):
		open = v
		queue_redraw()
## The groups in fill order: {kind, colour, name, short, instance_id, units, construction}, kind one of
## theirs, feature, yours, free, buy.
var groups: Array = []
## The mini hex's bands, one per kind of land present, bottom up: {kind, units, colour, name}.
var bands: Array = []
## Squares in the hex: the tile's maximum, or more when it holds more than it should.
var squares := 0
## The full view's grid: its columns, and per row (bottom to top) [first column, width].
var cols := 0
var rows: Array = []
## Each square's group. Squares are numbered in fill order: bottom row first, left to right.
var cell_group := PackedInt32Array()
## Units of land at or below the planning limit.
var limit := 100
var _hover := -1
var _row_start := PackedInt32Array()
var _cell_row := PackedInt32Array()
var _cell_col := PackedInt32Array()
var _cells: Array[Rect2] = []
var _pairs: Array = []


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_resize()


## The full view's grid for a flat-topped hex of exactly `n` squares in the map tile's proportions, on
## aligned columns so a building's block can be a true rectangle: {cols, rows: [[first column, width], ...]}
## bottom to top. Every row is centred (its width has the grid's parity); a grid that comes out over `n`
## loses a square from each end of its outer rows, top and bottom in turn, and an odd one from the top row.
static func hex_grid(n: int) -> Dictionary:
	if n <= 0:
		return {"cols": 0, "rows": []}
	var best_widths: Array = []
	var best_cols := 0
	var best_score := INF
	var c0 := sqrt(float(n) / (0.75 * TILE_ASPECT))   # a flat-topped hex's area is 3/4 of width x height
	for c in range(maxi(1, floori(c0) - 3), ceili(c0) + 4):
		var r0 := c * TILE_ASPECT
		for r in range(maxi(1, floori(r0) - 2), ceili(r0) + 3):
			var widths: Array = []
			var total := 0
			for i in r:
				var t := absf((i + 0.5) - r * 0.5) / (r * 0.5)
				var w := maxi(1, c - 2 * roundi(c * 0.25 * t))
				widths.append(w)
				total += w
			if total < n:
				continue
			var score := float(total - n) + absf(float(r) / float(c) - TILE_ASPECT) * 20.0
			if score < best_score:
				best_score = score
				best_widths = widths
				best_cols = c
	var out: Array = []
	var surplus := -n
	for w in best_widths:
		out.append([(best_cols - int(w)) / 2, int(w)])
		surplus += int(w)
	var order: Array = []
	for i in (out.size() + 1) / 2:
		order.append(out.size() - 1 - i)
		if i != out.size() - 1 - i:
			order.append(i)
	var passes := 0
	while surplus >= 2 and passes < 64:
		for r: int in order:
			if surplus < 2:
				break
			if int(out[r][1]) > 2:
				out[r][0] = int(out[r][0]) + 1
				out[r][1] = int(out[r][1]) - 2
				surplus -= 2
		passes += 1
	if surplus == 1:
		for r in range(out.size() - 1, -1, -1):
			if int(out[r][1]) > 1:
				out[r][1] = int(out[r][1]) - 1
				break
	return {"cols": best_cols, "rows": out}


## The share of a flat-topped hex's height below which the share `f` of its area lies: where the mini
## hex's bands meet.
static func level_height(f: float) -> float:
	f = clampf(f, 0.0, 1.0)
	if f <= 0.5:
		return (sqrt(1.0 + 6.0 * f) - 1.0) * 0.5
	return 1.0 - (sqrt(1.0 + 6.0 * (1.0 - f)) - 1.0) * 0.5


## The share of a flat-topped hex's area below the share `u` of its height (level_height's inverse).
static func area_below(u: float) -> float:
	u = clampf(u, 0.0, 1.0)
	if u <= 0.5:
		return (u + u * u) / 1.5
	var d := 1.0 - u
	return 1.0 - (d + d * d) / 1.5


## The six corners of a flat-topped hex filling `r`.
static func hex_polygon(r: Rect2) -> PackedVector2Array:
	var q := r.size.x * 0.25
	var m := r.position.y + r.size.y * 0.5
	return PackedVector2Array([Vector2(r.position.x + q, r.position.y), Vector2(r.end.x - q, r.position.y), Vector2(r.end.x, m),
		Vector2(r.end.x - q, r.end.y), Vector2(r.position.x + q, r.end.y), Vector2(r.position.x, m)])


## `count` shades of `base` a step apart in lightness. The steps are taken round the base's own lightness,
## moved just enough that none falls below `floor` or past `ceiling`, so no two are clamped together.
static func shades(base: Color, count: int, steps: Array, floor := 0.2, ceiling := SHADE_CEILING) -> Array:
	var lowest := 0.0
	var highest := 0.0
	for step in steps:
		lowest = minf(lowest, float(step))
		highest = maxf(highest, float(step))
	var centre := clampf(base.ok_hsl_l, floor - lowest, ceiling - highest)
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
	var your_shades := shades(livery, yours, YOUR_STEPS, YOUR_FLOOR, YOUR_CEILING)
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
			"instance_id": "", "construction": false, "colour": livery.lerp(WELL, 0.55)})
	if buy > 0:
		groups.append({"kind": "buy", "units": float(buy), "name": "%d you can buy" % buy, "short": "To buy",
			"instance_id": "", "construction": false, "colour": UNLIT_WINDOW})
	# Whole squares per group, rounded so they add up.
	var counts: Array = []
	var cum := 0.0
	var placed := 0
	for g: Dictionary in groups:
		cum += float(g.units)
		var upto := roundi(cum)
		counts.append(upto - placed)
		placed = upto
	squares = maxi(int(chart.get("type_cap", totals.get("max", 0))), placed)

	bands.clear()
	var band_units := 0
	for kind: String in BAND_ORDER:
		var units := 0
		for gi in groups.size():
			if str(groups[gi].kind) == kind:
				units += int(counts[gi])
		if kind == "buy":
			units += squares - placed   # the tile's maximum past what the groups cover is land nobody has
		if units > 0:
			bands.append({"kind": kind, "units": units, "colour": _band_colour(kind, livery), "name": _band_name(kind, units)})
			band_units += units

	var grid := hex_grid(squares)
	cols = int(grid.cols)
	rows = grid.rows
	_row_start = PackedInt32Array()
	_cell_row = PackedInt32Array()
	_cell_col = PackedInt32Array()
	for r in rows.size():
		_row_start.append(_cell_row.size())
		for i in int(rows[r][1]):
			_cell_row.append(r)
			_cell_col.append(int(rows[r][0]) + i)
	cell_group = PackedInt32Array()
	cell_group.resize(squares)
	cell_group.fill(-1)
	# The used land, the first squares in fill order, as blocks: other companies' and the land's own
	# buildings first, then yours, the biggest of each first.
	var items: Array = []
	var used := 0
	for kinds: Array in [["theirs", "feature"], ["yours"]]:
		var part: Array = []
		for gi in groups.size():
			if str(groups[gi].kind) in kinds and int(counts[gi]) > 0:
				part.append([gi, int(counts[gi])])
		part.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
		items += part
		for it: Array in part:
			used += int(it[1])
	used = mini(used, squares)
	var used_cells: Array = []
	for k in used:
		used_cells.append(k)
	# Only the full view shows the blocks; the mini hex needs only its bands.
	if expanded:
		_lay_out_blocks(used_cells, items)
	var k := used
	for kind: String in ["free", "buy"]:
		for gi in groups.size():
			if str(groups[gi].kind) != kind:
				continue
			for j in int(counts[gi]):
				if k < squares:
					cell_group[k] = gi
					k += 1
	limit = int(BuildingState.DENSITY_SOFT_CAPACITY)
	_hover = -1
	_resize()


func _band_colour(kind: String, livery: Color) -> Color:
	match kind:
		"theirs":
			return PlayerColours.NPC
		"feature":
			return STONE
		"yours":
			return livery
		"free":
			return livery.lerp(PANE, 0.55)
	return UNLIT


func _band_name(kind: String, units: int) -> String:
	match kind:
		"theirs":
			return "Other companies, %d land" % units
		"feature":
			return "Woods and ruins, %d land" % units
		"yours":
			return "Your buildings, %d land" % units
		"free":
			return "%d free to build on" % units
	return "%d you can buy" % units


## Lays the buildings into `cells` as blocks as near square as the room allows. The region is cut in two,
## down the columns or across the rows, each side taking the buildings whose land adds up to its squares
## (the list kept in order, so other companies' stay together and yours together), and each part is cut again
## until one building is left. Both cuts are tried at the two most even splits, and the layout whose worst
## block is nearest a filled square wins.
func _lay_out_blocks(cells: Array, items: Array) -> void:
	if items.is_empty() or cells.is_empty():
		return
	var best := _bisect(cells, items, INF)
	if (best.parts as Array).is_empty():
		# No layout kept every block in one piece: fall back to the fill order.
		var at := 0
		for it: Array in items:
			for j in int(it[1]):
				if at < cells.size():
					cell_group[int(cells[at])] = int(it[0])
					at += 1
		return
	for part: Array in best.parts:
		for c: int in part[0]:
			cell_group[c] = int(part[1])


## The best way to lay `items` into `cells`: {score, parts: [[cells, group], ...]}; a layout scoring `bound`
## or worse is abandoned.
func _bisect(cells: Array, items: Array, bound: float) -> Dictionary:
	if items.size() == 1:
		return {"score": _badness(cells), "parts": [[cells, int(items[0][0])]]}
	var total := 0
	var prefix: Array = [0]
	for it: Array in items:
		total += int(it[1])
		prefix.append(total)
	var splits: Array = []
	for k in range(1, items.size()):
		splits.append(k)
	splits.sort_custom(func(x: int, y: int) -> bool:
		return absf(float(prefix[x]) - total * 0.5) < absf(float(prefix[y]) - total * 0.5))
	splits = splits.slice(0, 2)
	var best := {"score": INF, "parts": []}
	for k: int in splits:
		var s: int = prefix[k]
		for down: bool in [true, false]:
			var ordered := cells.duplicate()
			ordered.sort_custom(_by_column if down else _by_row)
			var cap := minf(bound, float(best.score))
			var first := _bisect(ordered.slice(0, s), items.slice(0, k), cap)
			if float(first.score) >= cap:
				continue
			var second := _bisect(ordered.slice(s), items.slice(k), cap)
			var score := maxf(float(first.score), float(second.score))
			if score < float(best.score):
				best = {"score": score, "parts": (first.parts as Array) + (second.parts as Array)}
	return best


## How far a block is from a filled square: its bounding box's length over its width, raised by the share of
## the box it leaves empty. A block in more than one piece is ruled out.
func _badness(cells: Array) -> float:
	if cells.is_empty():
		return 0.0
	var box := _extent(cells)
	var aspect := maxf(float(box.x) / box.y, float(box.y) / box.x)
	var fill := float(box.x * box.y) / cells.size()
	if not _contiguous(cells):
		return INF
	return aspect * (1.0 + 0.6 * (fill - 1.0))


func _contiguous(cells: Array) -> bool:
	var inside := {}
	for c: int in cells:
		inside[Vector2i(_cell_col[c], _cell_row[c])] = true
	var start := Vector2i(_cell_col[int(cells[0])], _cell_row[int(cells[0])])
	var seen := {start: true}
	var todo: Array = [start]
	while not todo.is_empty():
		var at: Vector2i = todo.pop_back()
		for step: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next := at + step
			if inside.has(next) and not seen.has(next):
				seen[next] = true
				todo.append(next)
	return seen.size() == cells.size()


## Columns and rows spanned by a set of squares.
func _extent(cells: Array) -> Vector2i:
	var c0 := 1 << 30
	var c1 := -1
	var r0 := 1 << 30
	var r1 := -1
	for c: int in cells:
		c0 = mini(c0, _cell_col[c])
		c1 = maxi(c1, _cell_col[c])
		r0 = mini(r0, _cell_row[c])
		r1 = maxi(r1, _cell_row[c])
	return Vector2i(c1 - c0 + 1, r1 - r0 + 1)


func _by_column(a: int, b: int) -> bool:
	return _cell_col[a] < _cell_col[b] or (_cell_col[a] == _cell_col[b] and _cell_row[a] < _cell_row[b])


func _by_row(a: int, b: int) -> bool:
	return _cell_row[a] < _cell_row[b] or (_cell_row[a] == _cell_row[b] and _cell_col[a] < _cell_col[b])


func _resize() -> void:
	if expanded:
		custom_minimum_size = Vector2(cols, rows.size()) * PITCH + Vector2.ONE * 2.0 * PAD
	else:
		custom_minimum_size = COLLAPSED_BOX
	_layout()
	queue_redraw()


func _layout() -> void:
	_cells.clear()
	_pairs = []
	if not expanded or rows.is_empty():
		return
	var area := size if size != Vector2.ZERO else custom_minimum_size
	var origin := (area - Vector2(cols, rows.size()) * PITCH) * 0.5
	for k in _cell_row.size():
		var x := origin.x + _cell_col[k] * PITCH
		var y := origin.y + (rows.size() - 1 - _cell_row[k]) * PITCH
		_cells.append(Rect2(x + GAP * 0.5, y + GAP * 0.5, PITCH - GAP, PITCH - GAP))
	_pairs = _find_neighbours()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_layout()
		queue_redraw()
	elif what == NOTIFICATION_MOUSE_EXIT and _hover != -1:
		_hover = -1
		queue_redraw()


## The mini hex's rectangle: centred in its room, its area the tile's share of the biggest tile's.
func mini_rect() -> Rect2:
	var room := Rect2(Vector2.ZERO, size if size != Vector2.ZERO else custom_minimum_size).grow(-MINI_RIM - OPEN_RING_WIDTH)
	var w := minf(room.size.x, room.size.y / TILE_ASPECT) * sqrt(clampf(float(squares) / MINI_FULL, 0.05, 1.0))
	var h := w * TILE_ASPECT
	return Rect2(room.get_center() - Vector2(w, h) * 0.5, Vector2(w, h))


## The mini hex's band under a point, or -1.
func band_at(p: Vector2) -> int:
	var r := mini_rect()
	if bands.is_empty() or not Geometry2D.is_point_in_polygon(p, hex_polygon(r)):
		return -1
	var below := area_below((r.end.y - p.y) / r.size.y) * float(maxi(squares, 1))
	var cum := 0.0
	for bi in bands.size():
		cum += float(bands[bi].units)
		if below <= cum:
			return bi
	return bands.size() - 1


## The square under a point in the full view, or -1.
func cell_at(p: Vector2) -> int:
	for k in _cells.size():
		if _cells[k].grow(GAP * 0.5).has_point(p):
			return k
	return -1


## What is under a point: a group in the full view, a band in the mini hex, or -1.
func group_at(p: Vector2) -> int:
	if not expanded:
		return band_at(p)
	var k := cell_at(p)
	return cell_group[k] if k >= 0 and k < cell_group.size() else -1


func _get_tooltip(at: Vector2) -> String:
	if not expanded:
		var bi := band_at(at)
		var hint := "Click to show the land in full"
		return hint if bi < 0 else "%s\n%s" % [bands[bi].name, hint]
	var gi := group_at(at)
	if gi < 0:
		return ""
	var g: Dictionary = groups[gi]
	if str(g.kind) in ["yours", "theirs", "feature"]:
		return "%s, %d land%s" % [g.name, roundi(float(g.units)), ", under construction" if bool(g.construction) else ""]
	return str(g.name)


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


## A group's colour in the full view, lit up under the pointer.
func colour_of(gi: int) -> Color:
	if gi < 0 or gi >= groups.size():
		return UNLIT_WINDOW
	var g: Dictionary = groups[gi]
	var c: Color = g.colour
	if gi == _hover and str(g.kind) != "buy":
		c = c.lerp(Color.WHITE, 0.3)
	return c


func _draw() -> void:
	if expanded:
		_draw_full()
	else:
		_draw_mini()


func _draw_mini() -> void:
	var r := mini_rect()
	var poly := hex_polygon(r)
	# Laid on the plate: a navy ring while the full view is open, as a latched key sits down, then the rim.
	if open:
		for ring: PackedVector2Array in Geometry2D.offset_polygon(poly, MINI_RIM + OPEN_RING_WIDTH, Geometry2D.JOIN_MITER):
			draw_colored_polygon(ring, OPEN_RING)
	for rim: PackedVector2Array in Geometry2D.offset_polygon(poly, MINI_RIM, Geometry2D.JOIN_MITER):
		draw_colored_polygon(rim, RIM)
	var total := float(maxi(squares, 1))
	var cum := 0.0
	for bi in bands.size():
		var b: Dictionary = bands[bi]
		var y0 := r.end.y - r.size.y * level_height(cum / total)
		cum += float(b.units)
		var y1 := r.end.y - r.size.y * level_height(cum / total)
		var c: Color = b.colour
		if bi == _hover:
			c = c.lerp(Color.WHITE, 0.25)
		var slab := PackedVector2Array([Vector2(r.position.x - 1.0, y1), Vector2(r.end.x + 1.0, y1),
			Vector2(r.end.x + 1.0, y0), Vector2(r.position.x - 1.0, y0)])
		for piece: PackedVector2Array in Geometry2D.intersect_polygons(poly, slab):
			draw_colored_polygon(piece, c)
	if limit > 0 and limit < squares:
		var y := r.end.y - r.size.y * level_height(float(limit) / total)
		var half := r.size.x * 0.5 - r.size.x * 0.25 * absf(y - r.get_center().y) / (r.size.y * 0.5) + MINI_RIM
		_draw_hazard([[Vector2(r.get_center().x - half - 4.0, y), Vector2(r.get_center().x + half + 4.0, y)]], 2.8, 1.5, 2.4)


func _draw_full() -> void:
	var box := Rect2(Vector2.ZERO, size)
	Nine.paint(self, HOUSING, box.grow(HOUSING_MARGIN / CAPTURE_SCALE), (HOUSING_MARGIN + HOUSING_CORNER) * TEXELS)
	for corner in [Vector2(SCREW_INSET, SCREW_INSET), Vector2(size.x - SCREW_INSET, SCREW_INSET),
			Vector2(SCREW_INSET, size.y - SCREW_INSET), Vector2(size.x - SCREW_INSET, size.y - SCREW_INSET)]:
		draw_texture_rect(SCREW, Rect2(corner - Vector2.ONE * SCREW_SIZE * 0.5, Vector2.ONE * SCREW_SIZE), false)
	_draw_seams()
	for k in _cells.size():
		var gi := cell_group[k] if k < cell_group.size() else -1
		var c := colour_of(gi)
		var cell := _cells[k]
		draw_rect(cell, c)
		draw_line(cell.position + Vector2(0.5, 0.5), Vector2(cell.end.x - 0.5, cell.position.y + 0.5), c.lightened(0.2), 1.0)
		draw_line(Vector2(cell.position.x + 0.5, cell.end.y - 0.5), cell.end - Vector2(0.5, 0.5), c.darkened(0.25), 1.0)
		if gi >= 0 and bool(groups[gi].construction):
			draw_line(cell.position + Vector2(2, cell.size.y - 2), cell.position + Vector2(cell.size.x - 2, 2), c.darkened(0.45), 1.5)
	var segments := limit_segments()
	if not segments.is_empty():
		# A short tab past the hex at each end of the line, where an alarm mark sits on a gauge.
		var left: Array = []
		var right: Array = []
		for seg: Array in segments:
			var a: Vector2 = seg[0]
			var b: Vector2 = seg[1]
			if a.y != b.y:
				continue
			if left.is_empty() or a.x < (left[0] as Vector2).x:
				left = seg
			if right.is_empty() or b.x > (right[1] as Vector2).x:
				right = seg
		if not left.is_empty():
			segments = segments + [[(left[0] as Vector2) - Vector2(10, 0), left[0]], [right[1], (right[1] as Vector2) + Vector2(10, 0)]]
		_draw_hazard(segments, 5.0, 3.0, 5.0)


## The planning limit's tape for the livery in play: {band, stripe}. Yellow dashes on black, unless the
## livery is a yellow (hue 32 to 72 degrees, not greyed), when it is red dashes on white instead.
static func tape() -> Dictionary:
	var livery := PlayerColours.active_color()
	if livery.h >= 0.09 and livery.h <= 0.2 and livery.s > 0.3:
		return {"band": HAZARD_WHITE, "stripe": HAZARD_RED}
	return {"band": HAZARD_DARK, "stripe": HAZARD}


## Hazard tape along each [from, to]: a band with dashes along it (tape()), a dark keyline round a white band.
func _draw_hazard(segments: Array, band: float, stripe: float, dash: float) -> void:
	var colours := tape()
	if colours.band != HAZARD_DARK:
		for seg: Array in segments:
			draw_line(seg[0], seg[1], HAZARD_DARK, band + 1.5)
	for seg: Array in segments:
		draw_line(seg[0], seg[1], colours.band, band)
	for seg: Array in segments:
		var a: Vector2 = seg[0]
		var b: Vector2 = seg[1]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		var t := 0.0
		while t < length:
			draw_line(a + dir * t, a + dir * minf(t + dash, length), colours.stripe, stripe)
			t += dash * 2.0


## Pairs of neighbouring squares in the full view, [a, b, vertical]: along a row (b right of a), or in the
## same column one row up (b above a).
func _find_neighbours() -> Array:
	var out: Array = []
	for r in rows.size():
		var start := _row_start[r]
		var first := int(rows[r][0])
		var w := int(rows[r][1])
		for i in w - 1:
			out.append([start + i, start + i + 1, false])
		if r + 1 >= rows.size():
			continue
		var up_start := _row_start[r + 1]
		var up_first := int(rows[r + 1][0])
		var up_w := int(rows[r + 1][1])
		for i in w:
			var col := first + i
			if col >= up_first and col < up_first + up_w:
				out.append([start + i, up_start + col - up_first, true])
	return out


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
			draw_rect(Rect2(ra.position.x, rb.end.y, ra.size.x, ra.position.y - rb.end.y), seam)
			continue
		var gx0 := ra.end.x
		var gx1 := rb.position.x
		draw_rect(Rect2(gx0, ra.position.y, gx1 - gx0, ra.size.y), seam)
		# Carry the joint on into the gap above and below where every square round that corner is the
		# same building, or a dot of the dark line shows through at each corner.
		var r := _cell_row[a]
		if r + 1 < rows.size() and _row_all_of(r + 1, gx0, gx1, ga):
			draw_rect(Rect2(gx0, ra.position.y - GAP, gx1 - gx0, GAP), seam)
		if r > 0 and _row_all_of(r - 1, gx0, gx1, ga):
			draw_rect(Rect2(gx0, ra.end.y, gx1 - gx0, GAP), seam)


## Whether the squares of row `r` that reach across [x0, x1] are all of group `g` (and there are some).
func _row_all_of(r: int, x0: float, x1: float, g: int) -> bool:
	var start := _row_start[r]
	var any := false
	for i in int(rows[r][1]):
		var k := start + i
		var box := _cells[k].grow(GAP * 0.5)
		if box.end.x <= x0 or box.position.x >= x1:
			continue
		if (cell_group[k] if k < cell_group.size() else -1) != g:
			return false
		any = true
	return any


## The planning limit's line in the full view: the edges between a square among the tile's first `limit` and
## a neighbour past them.
func limit_segments() -> Array:
	var out: Array = []
	if limit <= 0 or limit >= _cells.size():
		return out
	for pair: Array in _pairs:
		var a := int(pair[0])
		var b := int(pair[1])
		if (a < limit) == (b < limit):
			continue
		var ra := _cells[a].grow(GAP * 0.5)
		var rb := _cells[b].grow(GAP * 0.5)
		if bool(pair[2]):
			var y := ra.position.y
			out.append([Vector2(maxf(ra.position.x, rb.position.x), y), Vector2(minf(ra.end.x, rb.end.x), y)])
		else:
			out.append([Vector2(ra.end.x, ra.position.y), Vector2(ra.end.x, ra.end.y)])
	return out
