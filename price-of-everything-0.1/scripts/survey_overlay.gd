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
var _radial_tex: Texture2D  # baked radial gradient, tinted per sea tile
var _live_meshes: Array = []  # keep batched meshes alive while the canvas item references them

const PAPER_TEX := preload("res://assets/ui/survey_paper.png")
const GRUNGE_TEX := preload("res://assets/ui/survey_grunge.png")
const FONT_SCRAWL := preload("res://assets/fonts/Inkfree.ttf")
const FONT_TYPE := preload("res://assets/fonts/CourierNew.ttf")

const CREAM := Color(0.995234, 0.930806, 0.763265)   # DS PALETTE.ACCENT off-white
const CHARCOAL := Color(0.2, 0.19, 0.17)             # hill / mountain / X lines
const NOTE_GREY := Color(0.3, 0.29, 0.31)            # scrawled-note text
const GREEN_SOLID := Color(0.09, 0.26, 0.11, 0.82)   # solid hill body (dark green)
const GREEN_FADE_COL := Color(0.09, 0.26, 0.11, 0.0) # green skirt fades to nothing
const GREY_SOLID := Color(0.44, 0.44, 0.47, 0.9)     # mountain body (grey)
const GREY_FADE_COL := Color(0.44, 0.44, 0.47, 0.0)  # grey gradient fades to nothing
const SNOW := Color(0.97, 0.97, 0.98, 1.0)           # peak snow-cap
const NAVY := Color(0.016, 0.059, 0.106)             # in-progress survey hex fill
const SURVEY_LIMIT_RED := Color(0.86, 0.13, 0.13)    # max survey-range boundary line
const SURVEY_LIMIT_BURGUNDY := Color(0.45, 0.04, 0.12)  # thick boundary line
const SURVEY_LIMIT_GLOW := Color(0.78, 0.16, 0.16, 0.45)  # outward gradient at the line
const SURVEY_LIMIT_WIDTH := 30.0       # world px, boundary line thickness
const SURVEY_LIMIT_GLOW_LEN := 300.0   # world px, how far the gradient projects out
const RIVER_BLUE := Color(0.17647059, 0.40784314, 0.76862745, 1.0)
# Sea: radial gradient (lighter centre -> deep edges so neighbours stay blue).
const SEA_CENTRE := Color(0.34, 0.55, 0.76)
const SEA_EDGE := Color(0.18, 0.38, 0.62)
const DEEP_CENTRE := Color(0.17, 0.34, 0.55)
const DEEP_EDGE := Color(0.07, 0.19, 0.4)
const WAVE_SEA := Color(0.74, 0.86, 0.95, 0.7)
const WAVE_DEEP := Color(0.55, 0.72, 0.88, 0.7)

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
const COAST_AMP := 30.0       # max smooth coastline wobble (px in/out of a tile)
const COAST_SEGMENTS := 16    # more samples to resolve the higher-frequency octave
const CORNER_MAX := 40.0      # max random displacement of a shared hex corner
const SPIKE_AMP := 40.0       # occasional sharp coastline spike (px)
const SPIKE_W := 0.09         # spike half-width in edge-fraction (small => sharp)
const PATCH_RADIUS := 110.0
const PATCH_SIDES := 22
const TEX_WORLD := 900.0

const LABEL_CHANCE := 0.1      # fraction of unsurveyed land tiles that get a note
const HILL_FADE := 46.0        # green skirt height below the hill baseline
const MOUNT_FADE := 200.0      # grey gradient height up the mountain body
const MOUNT_SKIRT := 70.0      # grey gradient skirt radiating down past the base
const X_MARK_COUNT := 10
const SQRT3 := 1.7320508       # tan(60 deg): a 60deg slope rises sqrt3 per 1 across
const MOUNT_HALF := 195.0      # mountain base half-width (~3/4 of the 540 tile)
const MOUNT_BASE_Y := 110.0    # mountain baseline offset below tile centre
const SNOW_HEIGHT := 30.0      # max snow-cap height under the peak line

func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_radial_tex = _make_radial_tex()
	visible = false
	MapMode.selections_changed.connect(_on_mode_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	MatchState.surveyed_tiles_changed.connect(_on_survey_changed)
	MatchState.surveying_in_progress_changed.connect(_on_survey_changed)

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
	_live_meshes.clear()  # release last redraw's meshes; this pass rebuilds them

	# Rivers that run through unsurveyed/partial tiles (same routes the river drawer
	# uses), grouped by tile for hill avoidance.
	var rivers: Array = _survey_rivers()
	var rivers_by_coord: Dictionary = {}
	for entry in rivers:
		var c: Vector2i = entry.coord
		if not rivers_by_coord.has(c):
			rivers_by_coord[c] = []
		rivers_by_coord[c].append(entry.points)

	# PASS 1 — base fills: cream paper on land, weathered blue on sea/deep sea.
	# Polygons are collected and drawn grouped by texture so the work stays cheap.
	# Sea uses ONE radial-gradient textured polygon per tile (was a ~30-call fan).
	var weathered_polys: Array = []
	var land: Array = []  # unsurveyed land tiles get hills/mountains/notes/X-marks
	var cream_polys: Array = []  # [{poly, uvs}]
	var sea_polys: Array = []    # [{poly, uvs, tint}]
	var waves: Array = []        # [{pts, col}]
	for coord in terrain_layer.tiles:
		var status: String = _status_at(coord)
		if status == "surveyed":
			continue
		var centre: Vector2 = _centre(coord)
		var ttype: String = str(terrain_layer.tiles[coord].get("type", ""))
		if status != "partial" and (ttype == "sea" or ttype == "deep_sea"):
			var sea_poly := _hex_poly(coord, centre)
			var deep := ttype == "deep_sea"
			sea_polys.append({"poly": sea_poly, "uvs": _radial_uvs(sea_poly, centre),
				"color": DEEP_CENTRE if deep else SEA_CENTRE})
			_collect_waves(centre, coord, deep, waves)
			weathered_polys.append({"poly": sea_poly, "uvs": _uvs(sea_poly)})
			continue
		var poly: PackedVector2Array = _patch_poly(centre) if status == "partial" else _hex_poly(coord, centre)
		var uvs := _uvs(poly)
		cream_polys.append({"poly": poly, "uvs": uvs, "color": CREAM})
		weathered_polys.append({"poly": poly, "uvs": uvs})
		if status == "unsurveyed":
			land.append(coord)

	var cm := _fill_mesh(cream_polys)
	if cm != null:
		draw_mesh(cm, PAPER_TEX)
	var sm := _fill_mesh(sea_polys)
	if sm != null:
		draw_mesh(sm, _radial_tex)
	var wm := _fill_mesh(waves)
	if wm != null:
		draw_mesh(wm, null)

	# PASS 2 — decorations on the paper (under the grunge). Hill/mountain fills are
	# collected into meshes and their ridge lines into one multiline, so the whole
	# pass costs a handful of draws instead of ~9 per hill/mountain tile.
	var green_fills: Array = []
	var grey_fills: Array = []
	var ridge_lines := PackedVector2Array()
	for coord in land:
		var centre := _centre(coord)
		_collect_hills(coord, centre, rivers_by_coord.get(coord, []), green_fills, ridge_lines)
		_collect_mountain(coord, centre, rivers_by_coord.get(coord, []), grey_fills, ridge_lines)
		_draw_label(coord, centre)
	var gfm := _fill_mesh(green_fills)
	if gfm != null:
		draw_mesh(gfm, null)
	var mfm := _fill_mesh(grey_fills)
	if mfm != null:
		draw_mesh(mfm, null)
	if ridge_lines.size() >= 2:
		draw_multiline(ridge_lines, CHARCOAL, 4.0, true)
	_draw_x_marks(land)
	var river_fills: Array = []
	for entry in rivers:
		var band := _river_band(entry.points)
		if band.size() >= 3:
			river_fills.append({"poly": band, "color": RIVER_BLUE})
	var rfm := _fill_mesh(river_fills)
	if rfm != null:
		draw_mesh(rfm, null)

	# PASS 3 — grunge applied last, so every decoration (rivers included) weathers.
	var gm := _fill_mesh(weathered_polys)
	if gm != null:
		draw_mesh(gm, GRUNGE_TEX)

	# On top: the red maximum-survey-range boundary, then the in-progress markers.
	_draw_survey_limit()
	_draw_survey_progress()

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

func _is_sea_type(coord: Vector2i) -> bool:
	var t: Variant = terrain_layer.tiles.get(coord)
	if t == null:
		return false
	var ty: String = str(t.get("type", ""))
	return ty == "sea" or ty == "deep_sea"

# Each shared hex corner gets a deterministic random offset (up to CORNER_MAX),
# computed from its undisplaced world position so all three tiles meeting there
# agree — the grid stays gap-free but the corners no longer pin the coastline.
func _corner(p: Vector2) -> Vector2:
	var cx := int(round(p.x))
	var cy := int(round(p.y))
	var mag: float = CORNER_MAX * pow(_hashf(cx, cy, 400), 1.05)
	var ang: float = _hashf(cx, cy, 401) * TAU
	return p + Vector2(cos(ang), sin(ang)) * mag

func _hex_poly(coord: Vector2i, centre: Vector2) -> PackedVector2Array:
	var offs: Array[Vector2i] = EDGE_NEIGHBOUR_ODD if (coord.x % 2) == 1 else EDGE_NEIGHBOUR_EVEN
	var this_sea := _is_sea_type(coord)
	var poly := PackedVector2Array()
	for i in 6:
		var a: Vector2 = _corner(centre + CORNERS[i])
		var b: Vector2 = _corner(centre + CORNERS[(i + 1) % 6])
		poly.append(a)
		var ncoord: Vector2i = coord + offs[i]
		var neigh: String = _status_at(ncoord)
		if neigh == "unsurveyed" and this_sea != _is_sea_type(ncoord):
			# Coastline: a shared randomised sine wobble (peninsulas/gulfs). Both the
			# sea and land tiles trace the identical curve, so their fills stay
			# complementary — blue spills onto land where the sea bulges in, cream
			# spills onto sea where the land bulges out.
			poly.append_array(_coastline_curve(a, b))
		elif neigh == "surveyed" or neigh == "partial":
			var edge: Vector2 = b - a
			var perp: Vector2 = Vector2(-edge.y, edge.x).normalized()
			var phase: float = a.x * 0.013 + a.y * 0.017
			for s in range(1, WAVE_SEGMENTS):
				var t: float = float(s) / float(WAVE_SEGMENTS)
				var off: float = WAVE_AMP * sin(PI * t) * sin(t * PI * WAVE_COUNT + phase)
				poly.append(a + edge * t + perp * off)
	return poly

# Interior wobble points for a coastline edge a->b. Computed in a canonical
# corner order (+ midpoint hash) so the adjacent tile produces the same world
# curve regardless of which way it walks the shared edge. Tapers to 0 at the
# corners (which are shared by 3 tiles) and reaches at most COAST_AMP px in/out.
func _coastline_curve(a: Vector2, b: Vector2) -> PackedVector2Array:
	var flip := a.x > b.x or (a.x == b.x and a.y > b.y)
	var p: Vector2 = b if flip else a
	var q: Vector2 = a if flip else b
	# Three octaves of sine (low/mid/high frequency) with independent random phases
	# and weights summing to ~1, so the coast is irregular rather than a clean wave.
	var amp: float = lerpf(20.0, COAST_AMP, _edge_rand(p, q, 300))
	var f1: float = lerpf(0.8, 1.6, _edge_rand(p, q, 310))
	var f2: float = lerpf(2.4, 3.6, _edge_rand(p, q, 311))
	var f3: float = lerpf(4.4, 6.4, _edge_rand(p, q, 312))
	var p1: float = _edge_rand(p, q, 313) * TAU
	var p2: float = _edge_rand(p, q, 314) * TAU
	var p3: float = _edge_rand(p, q, 315) * TAU
	# Every so often a single sharp spike (a narrow tent) pokes ~40px in or out.
	var spiked: bool = _edge_rand(p, q, 320) > 0.5
	var spike_t: float = lerpf(0.2, 0.8, _edge_rand(p, q, 321))
	var spike_d: float = (1.0 if _edge_rand(p, q, 322) > 0.5 else -1.0) * SPIKE_AMP
	var edge: Vector2 = q - p
	var perp: Vector2 = Vector2(-edge.y, edge.x).normalized()
	var canon := PackedVector2Array()
	for s in range(1, COAST_SEGMENTS):
		var t: float = float(s) / float(COAST_SEGMENTS)
		var wobble: float = (0.55 * sin(t * PI * f1 + p1)
			+ 0.3 * sin(t * PI * f2 + p2)
			+ 0.15 * sin(t * PI * f3 + p3))
		var d: float = sin(PI * t) * amp * wobble  # taper to 0 at the shared corners
		if spiked:
			d += spike_d * maxf(0.0, 1.0 - absf(t - spike_t) / SPIKE_W)
		canon.append(p + edge * t + perp * d)
	if flip:
		canon.reverse()
	return canon

func _edge_rand(p: Vector2, q: Vector2, salt: int) -> float:
	return _hashf(int(round((p.x + q.x) * 0.5)), int(round((p.y + q.y) * 0.5)), salt)

# --- hills ---
func _collect_hills(coord: Vector2i, centre: Vector2, river_pts: Array, fills: Array, lines: PackedVector2Array) -> void:
	# Hills are anchored to hill-type tiles only. Three flattened bell curves: the
	# first is a "full hill" kept inside the tile (small + central, towards the
	# top); the other two may stretch out over the neighbouring paper. Green fills
	# are collected into one mesh; charcoal arcs into one multiline.
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
		_collect_green_slope(arc, fills)
		_append_segments(arc, lines)

func _append_segments(pts: PackedVector2Array, out: PackedVector2Array) -> void:
	# Convert a polyline into disjoint segments for a single batched draw_multiline.
	for i in pts.size() - 1:
		out.append(pts[i])
		out.append(pts[i + 1])

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

func _collect_green_slope(arc: PackedVector2Array, fills: Array) -> void:
	# The hill body (inside the arc, down to its flat baseline) is solid green; a
	# gradient skirt then hangs from that lowest line, fading out over HILL_FADE px.
	var base_y: float = arc[0].y
	for p in arc:
		base_y = maxf(base_y, p.y)
	# Solid body — the arc closes along its baseline, so this fills the hill shape.
	fills.append({"poly": arc, "color": GREEN_SOLID})
	var left := Vector2(arc[0].x, base_y)
	var right := Vector2(arc[arc.size() - 1].x, base_y)
	fills.append({
		"poly": PackedVector2Array([left, right, right + Vector2(0.0, HILL_FADE), left + Vector2(0.0, HILL_FADE)]),
		"colors": PackedColorArray([GREEN_SOLID, GREEN_SOLID, GREEN_FADE_COL, GREEN_FADE_COL])})

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

# --- mountains ---
func _collect_mountain(coord: Vector2i, centre: Vector2, _river_pts: Array, fills: Array, lines: PackedVector2Array) -> void:
	# Mountains are anchored to mountain-type tiles and stay inside the tile: a 60deg
	# incline to the peak then 60deg down, ~3/4 tile wide. Two of the three
	# variations connect a smaller second peak to the side (the line goes up-down-
	# up-down). The ridge has no bottom line; its grey gradient radiates out in every
	# direction, including down through the open base.
	var tile: Variant = terrain_layer.tiles.get(coord)
	if tile == null or str(tile.get("type", "")) != "mountain":
		return
	var base_y: float = centre.y + MOUNT_BASE_Y
	var bl := Vector2(centre.x - MOUNT_HALF, base_y)
	var br := Vector2(centre.x + MOUNT_HALF, base_y)
	var variation: int = int(_hashf(coord.x, coord.y, 80) * 3.0) % 3
	var outline := PackedVector2Array()
	var apex_idx := 1
	match variation:
		1:  # smaller second peak connected to the LEFT of the main peak
			outline = PackedVector2Array([
				bl,
				Vector2(centre.x - 95.0, base_y - 165.0),  # second (left) peak
				Vector2(centre.x - 30.0, base_y - 80.0),   # valley
				Vector2(centre.x + 22.0, base_y - 300.0),  # main peak (right slope ~60deg to br)
				br])
			apex_idx = 3
		2:  # smaller second peak connected to the RIGHT of the main peak
			outline = PackedVector2Array([
				bl,
				Vector2(centre.x - 22.0, base_y - 300.0),  # main peak (left slope ~60deg from bl)
				Vector2(centre.x + 30.0, base_y - 80.0),   # valley
				Vector2(centre.x + 95.0, base_y - 165.0),  # second (right) peak
				br])
			apex_idx = 1
		_:  # single 60deg peak
			outline = PackedVector2Array([bl, Vector2(centre.x, base_y - MOUNT_HALF * SQRT3), br])
			apex_idx = 1
	_collect_mountain_body(outline, bl, br, base_y, fills)
	_collect_snow(outline, apex_idx, fills)
	# Charcoal ridge line on top — an OPEN polyline, so there is no bottom edge.
	_append_segments(outline, lines)

func _collect_mountain_body(outline: PackedVector2Array, bl: Vector2, br: Vector2, base_y: float, fills: Array) -> void:
	# Grey, densest along the base and fading up the slopes (over MOUNT_FADE) and a
	# short skirt down past the base, so the gradient radiates out through the bottom.
	var body_cols := PackedColorArray()
	for v in outline:
		body_cols.append(_grey_at(v.y, base_y))
	fills.append({"poly": outline, "colors": body_cols})  # closes along the base for the fill only
	fills.append({
		"poly": PackedVector2Array([bl, br, br + Vector2(0.0, MOUNT_SKIRT), bl + Vector2(0.0, MOUNT_SKIRT)]),
		"colors": PackedColorArray([_grey_at(base_y, base_y), _grey_at(base_y, base_y), GREY_FADE_COL, GREY_FADE_COL])})

func _grey_at(y: float, base_y: float) -> Color:
	var f: float = clampf(1.0 - (base_y - y) / MOUNT_FADE, 0.0, 1.0)
	return Color(GREY_SOLID.r, GREY_SOLID.g, GREY_SOLID.b, GREY_SOLID.a * f)

func _collect_snow(outline: PackedVector2Array, apex_idx: int, fills: Array) -> void:
	# White snow-cap on the main peak, its base points sitting ON the two adjacent
	# ridge edges SNOW_HEIGHT below the peak, so it always stays inside the outline.
	var m: Vector2 = outline[apex_idx]
	var lp: Vector2 = _ridge_point_below(m, outline[apex_idx - 1], SNOW_HEIGHT)
	var rp: Vector2 = _ridge_point_below(m, outline[apex_idx + 1], SNOW_HEIGHT)
	fills.append({"poly": PackedVector2Array([m, rp, lp]), "color": SNOW})

func _ridge_point_below(m: Vector2, other: Vector2, depth: float) -> Vector2:
	if other.y <= m.y + 0.001:
		return m + Vector2(0.0, depth)
	return m.lerp(other, clampf(depth / (other.y - m.y), 0.0, 1.0))

# --- sea / deep sea ---
## Grayscale radial gradient (centre 1.0 -> edge ~0.6). Tinted per sea tile and
## drawn as ONE textured polygon, so each sea tile costs a single draw call instead
## of a ~30-call per-edge triangle fan. The lighter centre / darker edge keeps the
## "deep where neighbours meet" look from the old fan.
func _make_radial_tex() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := (float(n) - 1.0) * 0.5
	for y in n:
		for x in n:
			var d: float = Vector2(float(x) - c, float(y) - c).length() / (float(n) * 0.5)
			var v: float = clampf(1.0 - d * 0.6, 0.55, 1.0)
			img.set_pixel(x, y, Color(v, v, v, 1.0))
	return ImageTexture.create_from_image(img)

## UVs that centre the radial gradient on the tile (corners reach the texture edge).
## Clamped to [0,1] so wavy-coastline points don't wrap under TEXTURE_REPEAT_ENABLED.
func _radial_uvs(poly: PackedVector2Array, centre: Vector2) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(Vector2(
			clampf(0.5 + (p.x - centre.x) / 540.0, 0.0, 1.0),
			clampf(0.5 + (p.y - centre.y) / 480.0, 0.0, 1.0)))
	return uvs

func _collect_waves(centre: Vector2, coord: Vector2i, deep: bool, out: Array) -> void:
	# A few wave crests (two arcs meeting at a peak), collected for a grouped draw.
	var wcol: Color = WAVE_DEEP if deep else WAVE_SEA
	for w in 3:
		var pos := centre + Vector2(_rr(coord, 200 + w, -150.0, 150.0), _rr(coord, 220 + w, -150.0, 150.0))
		var ww: float = _rr(coord, 240 + w, 30.0, 48.0)
		var wh: float = ww * _rr(coord, 260 + w, 0.42, 0.6)
		out.append({"poly": _wave_points(pos, ww, wh, deg_to_rad(_rr(coord, 280 + w, -12.0, 12.0))), "color": wcol})

## Merge many polygons into ONE triangle mesh, so a whole group (e.g. every cream
## tile, or every grunge overlay) costs a single draw_mesh call instead of one
## draw_colored_polygon per polygon (which the 2D batcher does not merge).
## entries: [{poly: PackedVector2Array, uvs?: PackedVector2Array, color?: Color}]
func _fill_mesh(entries: Array) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for e in entries:
		var poly: PackedVector2Array = e.poly
		if poly.size() < 3:
			continue
		var tri := Geometry2D.triangulate_polygon(poly)
		if tri.is_empty():
			continue
		var base := verts.size()
		var euv: PackedVector2Array = e.get("uvs", PackedVector2Array())
		var col: Color = e.get("color", Color.WHITE)
		var pcols: PackedColorArray = e.get("colors", PackedColorArray())
		var have_uv := euv.size() == poly.size()
		var have_pc := pcols.size() == poly.size()  # per-vertex gradient
		for i in poly.size():
			verts.append(poly[i])
			uvs.append(euv[i] if have_uv else Vector2.ZERO)
			cols.append(pcols[i] if have_pc else col)
		for t in tri:
			idx.append(base + t)
	if verts.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# draw_mesh only stores the mesh RID on the canvas item; hold a reference so the
	# resource isn't freed (and the RID invalidated) before the item is re-rendered.
	_live_meshes.append(mesh)
	return mesh

func _wave_points(pos: Vector2, w: float, h: float, rot: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 6
	for i in steps + 1:
		var a: float = (float(i) / float(steps)) * (PI * 0.5)
		pts.append(Vector2(-w * cos(a), -h * sin(a)))
	for i in range(1, steps + 1):
		var a: float = (float(i) / float(steps)) * (PI * 0.5)
		pts.append(Vector2(w * sin(a), -h * cos(a)))
	var out := PackedVector2Array()
	for p in pts:
		out.append(pos + p.rotated(rot))
	return out

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

func _river_band(pts: PackedVector2Array) -> PackedVector2Array:
	if pts.size() < 2:
		return PackedVector2Array()
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
	return band

# --- maximum survey-range boundary ---
func _draw_survey_limit() -> void:
	# Burgundy line on every edge where a surveyable tile meets a non-surveyable one
	# — the outer limit of what can currently be surveyed — with a medium-red gradient
	# projecting outward. Gather the boundary edges first so the glow sits behind the
	# lines (and adjacent edges don't paint glow over each other's lines).
	# Each band's corners are pushed out along their RADIAL direction (centre→corner),
	# not the edge normal — so two edges that share a corner push it out identically
	# and their glow bands meet, leaving no wedge gap at outward hex corners.
	var edges: Array = []  # [{a, b, a2, b2}]
	for coord in terrain_layer.tiles:
		var tid := str(terrain_layer.tiles[coord].get("id", ""))
		if not MatchState.is_tile_surveyable(tid):
			continue
		var centre := _centre(coord)
		var offs: Array[Vector2i] = EDGE_NEIGHBOUR_ODD if (coord.x % 2) == 1 else EDGE_NEIGHBOUR_EVEN
		for i in 6:
			var ncoord: Vector2i = coord + offs[i]
			if not terrain_layer.tiles.has(ncoord):
				continue  # off the playable map
			if MatchState.is_tile_surveyable(str(terrain_layer.tiles[ncoord].get("id", ""))):
				continue
			var ca: Vector2 = CORNERS[i]
			var cb: Vector2 = CORNERS[(i + 1) % 6]
			var a := centre + ca
			var b := centre + cb
			edges.append({
				"a": a, "b": b,
				"a2": a + ca.normalized() * SURVEY_LIMIT_GLOW_LEN,
				"b2": b + cb.normalized() * SURVEY_LIMIT_GLOW_LEN,
			})
	# Outward gradient band (medium red → transparent over SURVEY_LIMIT_GLOW_LEN).
	var transparent := Color(SURVEY_LIMIT_GLOW.r, SURVEY_LIMIT_GLOW.g, SURVEY_LIMIT_GLOW.b, 0.0)
	for e in edges:
		draw_polygon(PackedVector2Array([e.a, e.b, e.b2, e.a2]),
			PackedColorArray([SURVEY_LIMIT_GLOW, SURVEY_LIMIT_GLOW, transparent, transparent]))
	# Thick burgundy boundary line on top.
	for e in edges:
		draw_line(e.a, e.b, SURVEY_LIMIT_BURGUNDY, SURVEY_LIMIT_WIDTH, true)

# --- in-progress survey marker ---
func _draw_survey_progress() -> void:
	for tile_id in MatchState.surveying_in_progress:
		var coord: Vector2i = terrain_layer.id_to_coord(str(tile_id))
		if coord == Vector2i(-1, -1) or not terrain_layer.tiles.has(coord):
			continue
		_draw_progress_hex(_centre(coord), int(MatchState.surveying_in_progress[tile_id]))

func _draw_progress_hex(centre: Vector2, turns: int) -> void:
	# A rounded-corner navy hex (200px tall, shape borrowed from the research ranks)
	# with the turns-left number centred in off-white.
	var w := 178.0
	var h := 200.0
	var pts := _rounded_hex_pts(Rect2(centre.x - w * 0.5, centre.y - h * 0.5, w, h), 0.22, 22.0)
	draw_colored_polygon(pts, NAVY)
	var ring := PackedVector2Array(pts)
	ring.append(pts[0])
	draw_polyline(ring, CREAM, 4.0, true)
	var s := str(turns)
	var fs := 118
	var sz: Vector2 = FONT_TYPE.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(FONT_TYPE, Vector2(centre.x - sz.x * 0.5, centre.y + fs * 0.36), s,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, CREAM)

# A flat-top hex (HSM-style 22% bevel) with quadratic-bezier rounded corners.
func _rounded_hex_pts(rect: Rect2, bevel_frac: float, radius: float) -> PackedVector2Array:
	var l := rect.position.x
	var r := rect.end.x
	var t := rect.position.y
	var b := rect.end.y
	var my := (t + b) * 0.5
	var bev := rect.size.x * bevel_frac
	var hex: Array[Vector2] = [
		Vector2(l + bev, t), Vector2(r - bev, t), Vector2(r, my),
		Vector2(r - bev, b), Vector2(l + bev, b), Vector2(l, my)]
	var out := PackedVector2Array()
	var n := hex.size()
	for i in n:
		var cur: Vector2 = hex[i]
		var to_prev: Vector2 = hex[(i - 1 + n) % n] - cur
		var to_next: Vector2 = hex[(i + 1) % n] - cur
		var rr: float = minf(radius, minf(to_prev.length(), to_next.length()) * 0.5)
		var a: Vector2 = cur + to_prev.normalized() * rr
		var c2: Vector2 = cur + to_next.normalized() * rr
		for st in 5:
			var tt := float(st) / 4.0
			out.append(a.lerp(cur, tt).lerp(cur.lerp(c2, tt), tt))  # quadratic bezier
	return out
