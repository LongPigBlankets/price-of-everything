extends Node2D
## One custom-draw node covers tutorial map cues. Timed cues can specify their pulse count,
## duration and colour; rail targets stay amber until the player clicks each tile. There are
## no per-tile scene nodes, and processing is disabled whenever the effect is idle.

const DEFAULT_PULSE_SECONDS := 0.5
const DEFAULT_PULSE_COUNT := 3
const CORNERS: Array[Vector2] = [
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0), Vector2(270.0, 0.0),
	Vector2(135.0, 240.0), Vector2(-135.0, 240.0), Vector2(-270.0, 0.0),
]
const AMBER := Color(1.0, 0.78, 0.18)

var _tile_centres: Dictionary = {}
var _elapsed := 0.0
var _holding := false
var _pulse_seconds := DEFAULT_PULSE_SECONDS
var _pulse_count := DEFAULT_PULSE_COUNT
var _flash_color := AMBER

func _ready() -> void:
	z_index = 85
	set_process(false)

func flash(
	tile_ids: Array,
	pulse_seconds: float = DEFAULT_PULSE_SECONDS,
	pulse_count: int = DEFAULT_PULSE_COUNT,
	color: Color = AMBER
) -> void:
	_resolve_tiles(tile_ids)
	_holding = false
	_elapsed = 0.0
	_pulse_seconds = maxf(0.05, pulse_seconds)
	_pulse_count = maxi(1, pulse_count)
	_flash_color = color
	set_process(not _tile_centres.is_empty())
	queue_redraw()


func hold(tile_ids: Array) -> void:
	_resolve_tiles(tile_ids)
	_holding = not _tile_centres.is_empty()
	_elapsed = 0.0
	_flash_color = AMBER
	set_process(false)
	queue_redraw()


func dismiss(tile_id: String) -> void:
	if not _holding or not _tile_centres.has(tile_id):
		return
	_tile_centres.erase(tile_id)
	if _tile_centres.is_empty():
		_holding = false
	queue_redraw()


func clear_hold() -> void:
	if not _holding:
		return
	clear()


func clear() -> void:
	_tile_centres.clear()
	_holding = false
	_elapsed = 0.0
	set_process(false)
	queue_redraw()


func _resolve_tiles(tile_ids: Array) -> void:
	_tile_centres.clear()
	var hex_map := get_tree().get_first_node_in_group("hex_map")
	if hex_map == null or not hex_map.has_method("id_to_coord"):
		return
	for raw_tile_id in tile_ids:
		var tile_id := str(raw_tile_id)
		var coord: Vector2i = hex_map.id_to_coord(tile_id)
		if coord == Vector2i(-1, -1):
			continue
		var cell: Vector2i = hex_map.map_coord_for_tile_coord(coord)
		_tile_centres[tile_id] = hex_map.map_to_local(cell)

func _process(delta: float) -> void:
	if _holding:
		set_process(false)
		return
	_elapsed += delta
	queue_redraw()
	if _elapsed >= _pulse_seconds * float(_pulse_count):
		clear()

func _draw() -> void:
	if _tile_centres.is_empty():
		return
	var alpha := 1.0
	if not _holding:
		if _elapsed >= _pulse_seconds * float(_pulse_count):
			return
		var phase := fmod(_elapsed, _pulse_seconds) / _pulse_seconds
		alpha = sin(phase * PI)
	var fill := Color(_flash_color.r, _flash_color.g, _flash_color.b, alpha * 0.22)
	var line := Color(_flash_color.r, _flash_color.g, _flash_color.b, alpha * 0.95)
	for centre: Vector2 in _tile_centres.values():
		var polygon := PackedVector2Array()
		for corner in CORNERS:
			polygon.append(centre + corner * 0.92)
		draw_colored_polygon(polygon, fill)
		polygon.append(polygon[0])
		draw_polyline(polygon, line, 22.0, true)
