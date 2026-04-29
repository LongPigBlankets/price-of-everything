extends Node2D

# Maps building IDs to their icon textures
var building_icons: Dictionary = {}

# Per-tile occupancy: tile_id -> int (number of buildings placed so far)
# Used to determine the next grid slot for the next building on that tile
var tile_building_counts: Dictionary = {}

# Hex tile dimensions (matches your TileSet config)
const TILE_WIDTH := 64
const TILE_HEIGHT := 56

# The "rectangular section" of a pointy-top hex is the middle band.
# For a 64x56 hex, the central rectangle is roughly 64 wide x 36 tall.
const ICON_AREA_WIDTH := 64
const ICON_AREA_HEIGHT := 36

# Each building icon is small enough to fit a grid in the icon area.
# 4 columns x 3 rows = 12 slots per tile, each ~16x12 pixels.
const ICONS_PER_ROW := 4
const ICON_ROWS := 3
const ICON_SIZE_X := ICON_AREA_WIDTH / ICONS_PER_ROW   # 16px
const ICON_SIZE_Y := ICON_AREA_HEIGHT / ICON_ROWS      # 12px

func _ready() -> void:
	_load_building_icons()

func _load_building_icons() -> void:
	# Map building IDs to icon paths. Adjust IDs to match your buildings.csv
	var icon_paths := {
		"b_001": "res://assets/icons/buildings/b_001_mine.png",
		"b_002": "res://assets/icons/buildings/b_002_furnace.png",
		"b_003": "res://assets/icons/buildings/b_003_coal_power.png",
		"b_004": "res://assets/icons/buildings/b_004_port.png",
		"b_005": "res://assets/icons/buildings/b_005_road.png",
	}
	
	for building_id in icon_paths:
		var path: String = icon_paths[building_id]
		if ResourceLoader.exists(path):
			building_icons[building_id] = load(path)
		else:
			push_warning("Icon not found for %s at %s" % [building_id, path])

const MAX_VISIBLE_BUILDINGS := 12  # 4 cols × 3 rows
const OVERFLOW_INDEX := 11         # 12th slot (0-indexed)

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, _instance_id: String, coord: Vector2i) -> void:
	if not building_icons.has(building_id):
		push_warning("No icon registered for building %s" % building_id)
		return
	
	if not tile_building_counts.has(tile_id):
		tile_building_counts[tile_id] = 0
	var slot_index: int = tile_building_counts[tile_id]
	tile_building_counts[tile_id] = slot_index + 1
	
	var tile_center := _tile_center_world_pos(coord)
	
	if slot_index < OVERFLOW_INDEX:
		var slot_pos := _slot_position(tile_center, slot_index)
		_create_icon_sprite(building_icons[building_id], slot_pos)
	elif slot_index == OVERFLOW_INDEX:
		var slot_pos := _slot_position(tile_center, slot_index)
		_create_overflow_indicator(slot_pos)

func _create_icon_sprite(texture: Texture2D, slot_pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = slot_pos
	var tex_size := texture.get_size()
	if tex_size.x > 0 and tex_size.y > 0:
		var scale_x: float = float(ICON_SIZE_X) / tex_size.x
		var scale_y: float = float(ICON_SIZE_Y) / tex_size.y
		var scale_uniform: float = min(scale_x, scale_y) * 0.9
		sprite.scale = Vector2(scale_uniform, scale_uniform)
	add_child(sprite)

func _create_overflow_indicator(slot_pos: Vector2) -> void:
	var label := Label.new()
	label.text = "…"
	label.position = slot_pos - Vector2(6, 8)  # rough centering
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(0.9, 0.9, 0.9)
	add_child(label)

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	# Convert hex coord to world position. For pointy-top hexes with offset
	# coordinates, we approximate by querying the TileMapLayer (most accurate).
	# But a quick formula works too:
	# Even rows offset right by half a tile, odd rows align.
	var x := coord.x * TILE_WIDTH
	if coord.y % 2 == 1:
		x += TILE_WIDTH / 2
	var y := coord.y * (TILE_HEIGHT * 3 / 4)  # 3/4 vertical for hex stagger
	return Vector2(x + TILE_WIDTH / 2, y + TILE_HEIGHT / 2)

func _slot_position(tile_center: Vector2, slot_index: int) -> Vector2:
	# Lay out icons left-to-right, top-to-bottom in the icon area
	# centered on the tile.
	var col := slot_index % ICONS_PER_ROW
	var row := slot_index / ICONS_PER_ROW
	
	# Top-left of the icon area within the tile
	var area_top_left := tile_center - Vector2(ICON_AREA_WIDTH / 2, ICON_AREA_HEIGHT / 2)
	
	# Center of the slot
	var slot_x := area_top_left.x + col * ICON_SIZE_X + ICON_SIZE_X / 2
	var slot_y := area_top_left.y + row * ICON_SIZE_Y + ICON_SIZE_Y / 2
	
	return Vector2(slot_x, slot_y)
