extends Node2D
## Surveying map overlay.
##
## When the Surveying mapmode is active, every tile the player has not surveyed is
## covered with an aged cream "paper" (old-school unexplored-map look):
##   - unsurveyed tile        -> the whole hex is covered in cream paper.
##   - partially surveyed tile -> a small round patch of cream paper (urban tiles
##                                start partially surveyed).
##   - surveyed tile           -> nothing drawn; the tile shows through as normal.
##
## Where cream meets a surveyed/partial tile the boundary is a low-amplitude
## ("suppressed") sine wave; where cream meets more cream the fill just continues
## (the shared straight hex edge), so neighbouring unsurveyed tiles merge seamlessly.
## The grunge texture is sampled in world space so the paper looks like one
## continuous sheet across the map.

@onready var terrain_layer: HexMap = %TerrainLayer

const PAPER_TEX := preload("res://assets/ui/survey_paper.png")
const CREAM := Color(0.995234, 0.930806, 0.763265)  # DS PALETTE.ACCENT off-white

# Flat-top hex corners relative to the tile centre (tile_set tile_size 540x480),
# clockwise from the top-left corner. Matches HexMap's HSM geometry.
const CORNERS: Array[Vector2] = [
	Vector2(-135.0, -240.0),  # top-left
	Vector2(135.0, -240.0),   # top-right
	Vector2(270.0, 0.0),      # right
	Vector2(135.0, 240.0),    # bottom-right
	Vector2(-135.0, 240.0),   # bottom-left
	Vector2(-270.0, 0.0),     # left
]
# Neighbour tile-coord offset across edge i (corner i -> corner i+1), for even/odd
# columns. Mirrors HexMap._neighbor_offset_for_hsm (HSM1..HSM6 in order).
const EDGE_NEIGHBOUR_EVEN: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0),
	Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]
const EDGE_NEIGHBOUR_ODD: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0),
]

const WAVE_AMP := 18.0       # suppressed sine amplitude (world units; tile is 540 wide)
const WAVE_COUNT := 2.0      # number of half-waves along a wavy edge
const WAVE_SEGMENTS := 10    # subdivisions per wavy edge
const PATCH_RADIUS := 110.0  # cream patch radius for partially surveyed tiles
const PATCH_SIDES := 22
const TEX_WORLD := 900.0     # world distance over which the paper texture repeats

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

func _status(coord: Vector2i) -> String:
	# "surveyed" / "partial" / "unsurveyed", or "" when the coord is off the map.
	var t: Variant = terrain_layer.tiles.get(coord)
	if t == null:
		return ""
	return MatchState.survey_status(str(t.get("id", "")), str(t.get("type", "")))

func _draw() -> void:
	if MapMode.current_mode != MapMode.Mode.SURVEYING:
		return
	for coord in terrain_layer.tiles:
		var tile: Dictionary = terrain_layer.tiles[coord]
		var status: String = MatchState.survey_status(str(tile.get("id", "")), str(tile.get("type", "")))
		if status == "surveyed":
			continue
		var centre: Vector2 = terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
		if status == "partial":
			_draw_patch(centre)
		else:
			_draw_cream_hex(centre, coord)

func _draw_patch(centre: Vector2) -> void:
	# A small irregular round patch of cream paper.
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var phase: float = centre.x * 0.01 + centre.y * 0.013
	for i in PATCH_SIDES:
		var a: float = TAU * float(i) / float(PATCH_SIDES)
		var r: float = PATCH_RADIUS * (1.0 + 0.08 * sin(a * 3.0 + phase))
		var p: Vector2 = centre + Vector2(cos(a), sin(a)) * r
		pts.append(p)
		uvs.append(p / TEX_WORLD)
	draw_colored_polygon(pts, CREAM, uvs, PAPER_TEX)

func _draw_cream_hex(centre: Vector2, coord: Vector2i) -> void:
	var offs: Array[Vector2i] = EDGE_NEIGHBOUR_ODD if (coord.x % 2) == 1 else EDGE_NEIGHBOUR_EVEN
	var poly := PackedVector2Array()
	for i in 6:
		var a: Vector2 = centre + CORNERS[i]
		var b: Vector2 = centre + CORNERS[(i + 1) % 6]
		poly.append(a)
		var neigh: String = _status(coord + offs[i])
		if neigh == "surveyed" or neigh == "partial":
			# Boundary against a revealed tile: trace a suppressed sine wave between
			# the two (fixed) corners so the cream edge reads as a hand-drawn coast.
			var edge: Vector2 = b - a
			var perp: Vector2 = Vector2(-edge.y, edge.x).normalized()
			var phase: float = a.x * 0.013 + a.y * 0.017
			for s in range(1, WAVE_SEGMENTS):
				var t: float = float(s) / float(WAVE_SEGMENTS)
				var env: float = sin(PI * t)  # taper to 0 at both corners
				var off: float = WAVE_AMP * env * sin(t * PI * WAVE_COUNT + phase)
				poly.append(a + edge * t + perp * off)
		# else: a straight shared hex edge — neighbouring cream tiles overlap it
		# exactly, so the fill is seamless.
	var uvs := PackedVector2Array()
	for p in poly:
		uvs.append(p / TEX_WORLD)
	draw_colored_polygon(poly, CREAM, uvs, PAPER_TEX)
