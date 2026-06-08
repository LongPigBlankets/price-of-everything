extends Node2D
## Surveying map overlay — a hand-drawn cartographer's sheet over everything the
## player hasn't surveyed.
##
## States (see MatchState.survey_status):
##   - unsurveyed -> the whole hex is aged cream paper, decorated with hill
##     symbols, scrawled notes and X-marks, like an old "here be dragons" map.
##   - partial (urban) -> a small round patch of cream paper on the normal tile.
##   - surveyed (ports at start) -> nothing drawn; the tile shows as normal.
##
## Draw order each redraw: cream paper base -> hill symbols (+ green slopes) ->
## scrawled notes -> X-marks -> thick hand-drawn rivers -> grunge pass last (so
## every decoration, rivers included, looks weathered into the paper).
##
## Boundaries against revealed tiles are a low-amplitude ("suppressed") sine wave;
## unsurveyed meeting unsurveyed shares the straight hex edge so the cream merges.
## Decorations are placed deterministically from tile coords so they stay put.

@onready var terrain_layer: HexMap = %TerrainLayer

const PAPER_TEX := preload("res://assets/ui/survey_paper.png")
const GRUNGE_TEX := preload("res://assets/ui/survey_grunge.png")
const FONT_SCRAWL := preload("res://assets/fonts/Inkfree.ttf")
const FONT_TYPE := preload("res://assets/fonts/CourierNew.ttf")

const CREAM := Color(0.995234, 0.930806, 0.763265)   # DS PALETTE.ACCENT off-white
const CHARCOAL := Color(0.2, 0.19, 0.17)             # hill / X lines (not pure black)
const NOTE_GREY := Color(0.3, 0.29, 0.31)            # scrawled-note text
const GREEN_TOP := Color(0.09, 0.26, 0.11, 0.5)      # hill slope shade
const GREEN_BOT := Color(0.09, 0.26, 0.11, 0.0)      # fades to nothing
const RIVER_BLUE := Color(0.17647059, 0.40784314, 0.76862745, 1.0)

const LABELS: Array[String] = [
	"Ores here?", "Flat land maybe", "Oil?", "How big is the deposit?", "Must dig deeper...",
]

# Flat-top hex corners relative to the tile centre (tile_size 540x480), clockwise
# from the top-left. Matches HexMap's HSM geometry.
const CORNERS: Array[Vector2] = [
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
]
const EDGE_NEIGHBOUR_EVEN: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const EDGE_NEIGHBOUR_ODD: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

const WAVE_AMP := 18.0
const WAVE_COUNT := 2.0
const WAVE_SEGMENTS := 10
const PATCH_RADIUS := 110.0
const PATCH_SIDES := 22
const TEX_WORLD := 900.0

const LABEL_CHANCE := 0.1      # fraction of unsurveyed tiles that get a scrawled note
const GREEN_FADE := 50.0       # downward green-slope gradient height
const X_MARK_COUNT := 10

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	visible = false
	MapMode.selections_changed.connect(_on_mode_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	MatchState.surveyed_tiles_changed.connect(_on_survey_changed)

func _on_mode_changed(_mode: int, _sel: Array) -> void:
	_update()

func _on_mode_cleared() -> void:
	_update()

func _on_survey_changed() -> void:
	if visible:
		queue_redraw()

func _update() -> void:
	visible = MapMode.current_mode == MapMode.Mode.SURVEYING
	queue_redraw()

# --- deterministic per-tile pseudo-randomness (stable across redraws) ---
func _hashf(a: int, b: int, salt: int) -> float:
	var h: int = (a + 100) * 73856093
	h = h ^ ((b + 100) * 19349663)
	h = h ^ ((salt + 100) * 83492791)
	return float(absi(h) % 1000003) / 1000003.0

func _rr(coord: Vector2i, salt: int, lo: float, hi: float) -> float:
	return lo + _hashf(coord.x, coord.y, salt) * (hi - lo)

func _centre(coord: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _status_at(coord: Vector2i) -> String:
	var t: Variant = terrain_layer.tiles.get(coord)
	if t == null:
		return ""
	return MatchState.survey_status(str(t.get("id", "")), str(t.get("type", "")))

func _draw() -> void:
	if MapMode.current_mode != MapMode.Mode.SURVEYING:
		return

	# Rivers that run through unsurveyed/partial tiles (same routes the river drawer
	# uses), grouped by tile for hill avoidance.
	var rivers: Array = _survey_rivers()
	var rivers_by_coord: Dictionary = {}
	for entry in rivers:
		var c: Vector2i = entry.coord
		if not rivers_by_coord.has(c):
			rivers_by_coord[c] = []
		rivers_by_coord[c].append(entry.points)

	# PASS 1 — cream paper base; remember each cream polygon for the grunge pass.
	var cream_polys: Array = []
	var unsurveyed: Array = []
	for coord in terrain_layer.tiles:
		var status: String = _status_at(coord)
		if status == "surveyed":
			continue
		var centre: Vector2 = _centre(coord)
		var poly: PackedVector2Array = _patch_poly(centre) if status == "partial" else _hex_poly(coord, centre)
		var uvs := _uvs(poly)
		draw_colored_polygon(poly, CREAM, uvs, PAPER_TEX)
		cream_polys.append({"poly": poly, "uvs": uvs})
		if status == "unsurveyed":
			unsurveyed.append(coord)

	# PASS 2 — decorations on the cream (under the grunge).
	for coord in unsurveyed:
		var centre := _centre(coord)
		_draw_hills(coord, centre, rivers_by_coord.get(coord, []))
		_draw_label(coord, centre)
	_draw_x_marks(unsurveyed)
	for entry in rivers:
		_draw_thick_river(entry.points)

	# PASS 3 — grunge applied last, so every decoration (rivers included) weathers.
	for cp in cream_polys:
		draw_colored_polygon(cp.poly, Color.WHITE, cp.uvs, GRUNGE_TEX)

func _uvs(poly: PackedVector2Array) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(p / TEX_WORLD)
	return uvs

# --- cream shapes ---
func _patch_poly(centre: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var phase: float = centre.x * 0.01 + centre.y * 0.013
	for i in PATCH_SIDES:
		var a: float = TAU * float(i) / float(PATCH_SIDES)
		var r: float = PATCH_RADIUS * (1.0 + 0.08 * sin(a * 3.0 + phase))
		pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts

func _hex_poly(coord: Vector2i, centre: Vector2) -> PackedVector2Array:
	var offs: Array[Vector2i] = EDGE_NEIGHBOUR_ODD if (coord.x % 2) == 1 else EDGE_NEIGHBOUR_EVEN
	var poly := PackedVector2Array()
	for i in 6:
		var a: Vector2 = centre + CORNERS[i]
		var b: Vector2 = centre + CORNERS[(i + 1) % 6]
		poly.append(a)
		var neigh: String = _status_at(coord + offs[i])
		if neigh == "surveyed" or neigh == "partial":
			var edge: Vector2 = b - a
			var perp: Vector2 = Vector2(-edge.y, edge.x).normalized()
			var phase: float = a.x * 0.013 + a.y * 0.017
			for s in range(1, WAVE_SEGMENTS):
				var t: float = float(s) / float(WAVE_SEGMENTS)
				var off: float = WAVE_AMP * sin(PI * t) * sin(t * PI * WAVE_COUNT + phase)
				poly.append(a + edge * t + perp * off)
	return poly

# --- hills ---
func _draw_hills(coord: Vector2i, centre: Vector2, river_pts: Array) -> void:
	# Hills are anchored to hill-type tiles only. Three flattened bell curves: the
	# first is a "full hill" kept inside the tile (small + central, towards the
	# top); the other two may stretch out over the neighbouring paper.
	var tile: Variant = terrain_layer.tiles.get(coord)
	if tile == null or str(tile.get("type", "")) != "hill":
		return
	var slots: Array[Vector2] = [
		Vector2(_rr(coord, 1, -22.0, 22.0), -78.0),           # contained, towards the top
		Vector2(-110.0 + _rr(coord, 2, -25.0, 25.0), 60.0),   # stretches left
		Vector2(110.0 + _rr(coord, 3, -25.0, 25.0), 35.0),    # stretches right
	]
	for si in 3:
		var amp: float = _rr(coord, 10 + si, 30.0, 46.0)
		# The anchor hill is narrow enough to sit fully inside the tile.
		var wide: float = _rr(coord, 20, 56.0, 74.0) if si == 0 else _rr(coord, 20 + si, 82.0, 115.0)
		var c: Vector2 = _avoid_rivers(centre + slots[si], wide, river_pts)
		var arc := _hill_arc(c, amp, wide)
		_draw_green_slope(arc)
		draw_polyline(arc, CHARCOAL, _rr(coord, 30 + si, 3.0, 5.0), true)

func _hill_arc(peak_base: Vector2, amp: float, wide: float) -> PackedVector2Array:
	# Flattened normal distribution; only the top of the hill is drawn.
	var pts := PackedVector2Array()
	var span: float = wide * 2.4
	var n := 18
	for i in n + 1:
		var x: float = -span + (2.0 * span) * float(i) / float(n)
		var dx: float = x / wide
		pts.append(peak_base + Vector2(x, -amp * exp(-dx * dx)))
	return pts

func _draw_green_slope(arc: PackedVector2Array) -> void:
	# A dark-green band hanging off the hill line, fading out over GREEN_FADE px.
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for p in arc:
		pts.append(p)
		cols.append(GREEN_TOP)
	for i in range(arc.size() - 1, -1, -1):
		pts.append(arc[i] + Vector2(0.0, GREEN_FADE))
		cols.append(GREEN_BOT)
	draw_polygon(pts, cols)

func _avoid_rivers(c: Vector2, wide: float, river_pts: Array) -> Vector2:
	if river_pts.is_empty():
		return c
	var clear: float = wide * 0.6 + 24.0
	for _iter in 3:
		var nearest := Vector2.INF
		var nd := 1.0e12
		for arr in river_pts:
			for p in arr:
				var d: float = c.distance_to(p)
				if d < nd:
					nd = d
					nearest = p
		if nearest == Vector2.INF or nd >= clear:
			break
		var away: Vector2 = c - nearest
		if away.length() < 0.5:
			away = Vector2(0.0, -1.0)
		c = nearest + away.normalized() * clear
	return c

# --- scrawled notes ---
func _draw_label(coord: Vector2i, centre: Vector2) -> void:
	if _hashf(coord.x, coord.y, 41) > LABEL_CHANCE:
		return
	var text: String = LABELS[int(_hashf(coord.x, coord.y, 42) * float(LABELS.size())) % LABELS.size()]
	var font: Font = FONT_SCRAWL if _hashf(coord.x, coord.y, 43) < 0.5 else FONT_TYPE
	var size: int = int(_rr(coord, 44, 70.0, 100.0))  # large enough to read; spans tiles
	var angle: float = deg_to_rad(_rr(coord, 45, -45.0, 45.0))
	var pos: Vector2 = centre + Vector2(_rr(coord, 46, -45.0, 45.0), _rr(coord, 47, -35.0, 35.0))
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_set_transform(pos, angle, Vector2.ONE)
	draw_string(font, Vector2(-w * 0.5, size * 0.34), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, NOTE_GREY)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- X marks ---
func _draw_x_marks(unsurveyed: Array) -> void:
	# Spread X_MARK_COUNT marks across the lowest-hashed unsurveyed tiles (stable),
	# each off-centre and angled.
	var ranked: Array = unsurveyed.duplicate()
	ranked.sort_custom(func(a, b): return _hashf(a.x, a.y, 71) < _hashf(b.x, b.y, 71))
	for i in mini(X_MARK_COUNT, ranked.size()):
		var coord: Vector2i = ranked[i]
		var centre := _centre(coord)
		var ang_off: float = _rr(coord, 72, 0.0, TAU)
		var dist: float = _rr(coord, 73, 95.0, 175.0)  # never in the centre
		var pos: Vector2 = centre + Vector2(cos(ang_off), sin(ang_off)) * dist
		var angle: float = deg_to_rad(_rr(coord, 74, -45.0, 45.0))
		var size: float = _rr(coord, 75, 52.0, 82.0)
		var wdt: float = _rr(coord, 76, 4.0, 6.0)
		draw_set_transform(pos, angle, Vector2.ONE)
		var h: float = size * 0.5
		draw_line(Vector2(-h, -h), Vector2(h, h), CHARCOAL, wdt, true)
		draw_line(Vector2(-h, h), Vector2(h, -h), CHARCOAL, wdt, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# --- rivers ---
func _survey_rivers() -> Array:
	var rv: Node = get_parent().get_node_or_null("RiverVisuals")
	if rv == null or not rv.has_method("get_river_polylines"):
		return []
	var out: Array = []
	for entry in rv.get_river_polylines():
		var st: String = _status_at(entry.coord)
		if st == "unsurveyed" or st == "partial":
			out.append(entry)
	return out

func _draw_thick_river(pts: PackedVector2Array) -> void:
	if pts.size() < 2:
		return
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var acc := 0.0
	for i in pts.size():
		var dir: Vector2
		if i == 0:
			dir = pts[1] - pts[0]
		elif i == pts.size() - 1:
			dir = pts[i] - pts[i - 1]
		else:
			dir = pts[i + 1] - pts[i - 1]
		dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
		var nrm := Vector2(-dir.y, dir.x)
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		# thickness oscillates 30px -> 15px (half-width 15 -> 7.5).
		var hw: float = 11.25 + 3.75 * sin(acc / 52.0)
		left.append(pts[i] + nrm * hw)
		right.append(pts[i] - nrm * hw)
	var band := PackedVector2Array()
	band.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		band.append(right[i])
	draw_colored_polygon(band, RIVER_BLUE)
