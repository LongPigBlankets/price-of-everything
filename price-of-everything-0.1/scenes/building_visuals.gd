extends Node2D

# Maps building IDs to their icon textures
var building_icons: Dictionary = {}

# Per-tile occupancy: tile_id -> int (number of buildings placed so far)
# Used to determine the next grid slot for the next building on that tile
var tile_building_counts: Dictionary = {}

const ICONS_PER_ROW := 4
const ICON_ROWS := 3
const ROADS_BUILDING_ID := "b_005"

@onready var terrain_layer: HexMap = %TerrainLayer

func _ready() -> void:
	_load_building_icons()

func _load_building_icons() -> void:
	for building in Catalog.all_buildings():
		var building_id: String = building.id
		var internal_name: String = building.internal_name
		if building_id == "" or internal_name == "":
			continue
		
		var primary_path: String = "res://assets/icons/buildings/%s_%s.png" % [building_id, internal_name]
		if ResourceLoader.exists(primary_path):
			building_icons[building_id] = load(primary_path)
			continue
		
		var fallback_path: String = "res://assets/icons/buildings/%s.png" % building_id
		if ResourceLoader.exists(fallback_path):
			building_icons[building_id] = load(fallback_path)
			continue
		
		push_warning("[BuildingVisuals] No icon for %s (tried %s and %s)" % [
			building_id, primary_path, fallback_path
		])
const MAX_VISIBLE_BUILDINGS := 12  # 4 cols × 3 rows
const OVERFLOW_INDEX := 11         # 12th slot (0-indexed)

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, _instance_id: String, coord: Vector2i) -> void:
	if building_id == ROADS_BUILDING_ID:
		return
	print("[BuildingVisuals] placing for ", building_id)
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
		var icon_size := _icon_slot_size()
		var scale_x: float = icon_size.x / tex_size.x
		var scale_y: float = icon_size.y / tex_size.y
		var scale_uniform: float = min(scale_x, scale_y) * 0.9
		sprite.scale = Vector2(scale_uniform, scale_uniform)
	add_child(sprite)

func _create_overflow_indicator(slot_pos: Vector2) -> void:
	var label := Label.new()
	label.text = "…"
	var tile_size := _tile_size()
	label.position = slot_pos - (tile_size * 0.02)
	label.add_theme_font_size_override("font_size", roundi(tile_size.y * 0.08))
	label.modulate = Color(0.9, 0.9, 0.9)
	add_child(label)

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	if terrain_layer != null:
		return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	return Vector2.ZERO

func _slot_position(tile_center: Vector2, slot_index: int) -> Vector2:
	# Lay out icons left-to-right, top-to-bottom in the icon area
	# centered on the tile.
	var col := slot_index % ICONS_PER_ROW
	var row := slot_index / ICONS_PER_ROW
	var icon_area := _icon_area_size()
	var icon_size := _icon_slot_size()
	
	# Top-left of the icon area within the tile
	var area_top_left := tile_center - (icon_area * 0.5)
	
	# Center of the slot
	var slot_x := area_top_left.x + col * icon_size.x + icon_size.x / 2
	var slot_y := area_top_left.y + row * icon_size.y + icon_size.y / 2
	
	return Vector2(slot_x, slot_y)

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)

func _icon_area_size() -> Vector2:
	var tile_size := _tile_size()
	return Vector2(tile_size.x * 0.72, tile_size.y * 0.56)

func _icon_slot_size() -> Vector2:
	var icon_area := _icon_area_size()
	return Vector2(icon_area.x / ICONS_PER_ROW, icon_area.y / ICON_ROWS)
