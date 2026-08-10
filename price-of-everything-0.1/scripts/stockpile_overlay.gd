extends Node2D
## Stockpile mapmode — how close each tile's storage is to its cap, and where goods are being
## turned away at the door.
##
##   light green   holding stock, room to spare
##   amber         over STOCK_WARN of capacity
##   red           STOCK_FULL or more
##   flashing red  goods were BLOCKED here last turn (pulses between the two reds)
##
## A tile holding nothing is left untinted — the mode is about pressure on storage, and a wash
## over every empty tile would bury the handful that matter.
##
## Read-only against the sim (architecture rule 5): it reads Stockpile / MatchState and draws.

# Fill thresholds, as a fraction of the tile's capacity.
const STOCK_WARN := 0.80     # strictly above this → amber
const STOCK_FULL := 0.95     # at or above this → red

const LIGHT_GREEN := Color(0.45, 1.0, 0.48, 0.45)
const AMBER := Color(0.95, 0.65, 0.10, 0.50)
const RED := Color(0.80, 0.16, 0.16, 0.55)
## The flash alternates between RED and this, rather than red-to-nothing: a tile blinking out to
## bare terrain reads as a rendering fault, and it would also read as "nothing stored here".
const RED_FLASH := Color(1.0, 0.45, 0.36, 0.80)
const FLASH_SECONDS := 0.3

@onready var terrain_layer: HexMap = %TerrainLayer

var _active := false
var _rebuild_queued := false
var _tiles: Array = []            # [{center: Vector2, color: Color, blocked: bool}]
var _has_blocked := false
var _flash_on := false
var _flash_clock := 0.0

func _ready() -> void:
	set_process(false)
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_deactivate)
	# Coalesced (the notification-bell pattern): stockpile_changed fires on every add and
	# consume — hundreds of times per turn — and each one would otherwise walk every stocked
	# tile and ask Modifiers for its capacity.
	Stockpile.stockpile_changed.connect(_queue_rebuild)
	Production.turn_processed.connect(_on_turn_processed)

func _on_selections_changed(mode: int, _selections: Array) -> void:
	if mode == MapMode.Mode.STOCKPILE:
		_activate()
	else:
		_deactivate()

func _on_turn_processed(_summary: Dictionary) -> void:
	# Refusals are per-turn and roll over in the next PROCESS, so the flash has to re-evaluate
	# the moment a turn lands, not just when stock moves.
	_queue_rebuild()

func _activate() -> void:
	_active = true
	set_process(true)
	_flash_clock = 0.0
	_flash_on = true
	_rebuild()

func _deactivate() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	_tiles.clear()
	_has_blocked = false
	queue_redraw()

func _queue_rebuild(_arg: Variant = null) -> void:
	if not _active or _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_apply_rebuild")

func _apply_rebuild() -> void:
	_rebuild_queued = false
	if _active:
		_rebuild()

## Only tiles that can possibly be tinted are costed: everything holding stock, plus any tile
## with a shipment parked outside it. get_capacity() runs the modifier stack, so walking all 285
## tiles here would put that on every stockpile change.
func _rebuild() -> void:
	_tiles.clear()
	_has_blocked = false
	if terrain_layer == null:
		return
	var coord_by_id := {}
	for coord in terrain_layer.tiles:
		var tid := str((terrain_layer.tiles[coord] as Dictionary).get("id", ""))
		if tid != "":
			coord_by_id[tid] = coord

	var candidates := {}
	for key in Stockpile.tiles_with_stock():
		if str(key).begins_with("tile_"):
			candidates[str(key)] = true
	var blocked_tiles := {}
	for shipment in MatchState.overflow_shipments:
		var dest := str((shipment as Dictionary).get("destination_tile", ""))
		if dest != "":
			blocked_tiles[dest] = true
			candidates[dest] = true

	for tile_id in candidates:
		if not coord_by_id.has(tile_id):
			continue
		var used := Stockpile.get_used_capacity(tile_id)
		# Blocked counts BOTH ways a good fails to land: units the cap turned away during the
		# turn (Stockpile.get_refused, rolled over at the top of the next PROCESS, so between
		# turns it holds the completed turn's figure) and shipments still parked outside because
		# there was no room for them.
		var blocked: bool = Stockpile.get_refused(tile_id) > 0 or blocked_tiles.has(tile_id)
		if used <= 0 and not blocked:
			continue
		var capacity := Stockpile.get_capacity(tile_id)
		var pct := (float(used) / float(capacity)) if capacity > 0 else 1.0
		var color := LIGHT_GREEN
		if pct >= STOCK_FULL:
			color = RED
		elif pct > STOCK_WARN:
			color = AMBER
		if blocked:
			color = RED
			_has_blocked = true
		_tiles.append({
			"center": terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord_by_id[tile_id])),
			"color": color,
			"blocked": blocked,
		})
	queue_redraw()

func _process(delta: float) -> void:
	# Visual only — no sim logic in a frame callback (architecture rule 2). Skipped entirely
	# when nothing is blocked, so a calm map never redraws on a timer.
	if not _has_blocked:
		return
	_flash_clock += delta
	if _flash_clock < FLASH_SECONDS:
		return
	_flash_clock -= FLASH_SECONDS
	_flash_on = not _flash_on
	queue_redraw()

func _draw() -> void:
	if not _active or _tiles.is_empty():
		return
	var points := _hex_points(_tile_size())
	for entry: Dictionary in _tiles:
		var color: Color = entry.color
		if bool(entry.blocked) and _flash_on:
			color = RED_FLASH
		var shifted := PackedVector2Array()
		for p in points:
			shifted.append(p + (entry.center as Vector2))
		draw_colored_polygon(shifted, color)

## The flat-top hex the tile masks use — same shoulder proportions as power_hex_overlay so a
## stockpile tint lines up exactly with a power one.
func _hex_points(tile_size: Vector2) -> PackedVector2Array:
	var half_w := tile_size.x * 0.5
	var half_h := tile_size.y * 0.5
	var shoulder_x := tile_size.x * 0.25
	return PackedVector2Array([
		Vector2(-shoulder_x, -half_h),
		Vector2(shoulder_x, -half_h),
		Vector2(half_w, 0),
		Vector2(shoulder_x, half_h),
		Vector2(-shoulder_x, half_h),
		Vector2(-half_w, 0),
	])

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)
