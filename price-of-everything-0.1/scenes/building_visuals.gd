extends Node2D

# Draws every building's map icon in a single _draw() pass. Previously each
# placement spawned 1-3 child nodes (an NPC marker is a navy box + white box +
# sprite); with the ~500-building start pool that was well over a thousand
# canvas items submitted every frame. Holding the placements as plain data and
# drawing them here collapses that to one canvas item.

var building_icons: Dictionary = {}

# Per-tile occupancy: tile_id -> count, to assign the next grid slot.
var tile_building_counts: Dictionary = {}

# Ordered placements + an index for O(1) removal. Each placement:
#   {instance_id, slot, pos, texture, is_npc}
var _placements: Array = []
var _placement_index: Dictionary = {}   # instance_id -> index into _placements

const ICONS_PER_ROW := 4
const ICON_ROWS := 3
const ROADS_BUILDING_ID := "b_005"
const FOREST_BUILDING_IDS := {"b_015": true, "b_016": true}
const NPC_NAVY := Color(0.015686275, 0.058823529, 0.105882353)
const NPC_OUTLINE_PX := 10.0
const MAX_VISIBLE_BUILDINGS := 12  # 4 cols × 3 rows
const OVERFLOW_INDEX := 11         # 12th slot (0-indexed)

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

func on_building_placed(tile_id: String, building_id: String, _recipe_id: String, instance_id: String, coord: Vector2i) -> void:
	if building_id == ROADS_BUILDING_ID or FOREST_BUILDING_IDS.has(building_id):
		return
	if not building_icons.has(building_id):
		push_warning("No icon registered for building %s" % building_id)
		return

	if not tile_building_counts.has(tile_id):
		tile_building_counts[tile_id] = 0
	var slot_index: int = tile_building_counts[tile_id]
	tile_building_counts[tile_id] = slot_index + 1
	if slot_index > OVERFLOW_INDEX:
		return  # past the overflow indicator — nothing more to draw on this tile

	var tile_center := _tile_center_world_pos(coord)
	var owner_id := str(MatchState.get_building(instance_id).get("owner", ""))
	var is_npc: bool = owner_id != "" and owner_id != "player_1"

	var placement := {
		"instance_id": instance_id,
		"slot": slot_index,
		"pos": _slot_position(tile_center, slot_index),
		"texture": building_icons[building_id] if slot_index < OVERFLOW_INDEX else null,
		"is_npc": is_npc,
	}
	if instance_id != "":
		_placement_index[instance_id] = _placements.size()
	_placements.append(placement)
	queue_redraw()

func clear_all() -> void:
	# Used when a loaded save rebuilds the map visuals (world_map._rebuild_after_load).
	_placements.clear()
	_placement_index.clear()
	tile_building_counts.clear()
	queue_redraw()

func remove_instance(instance_id: String) -> void:
	# A cancelled construction frees its icon; the slot is left vacant (no reindex).
	if not _placement_index.has(instance_id):
		return
	var idx: int = _placement_index[instance_id]
	_placements.remove_at(idx)
	_placement_index.erase(instance_id)
	# Indices after the removed one shifted down by one.
	for iid in _placement_index:
		if _placement_index[iid] > idx:
			_placement_index[iid] -= 1
	queue_redraw()

func _draw() -> void:
	var icon_size := _icon_slot_size()
	for placement in _placements:
		if int(placement.slot) == OVERFLOW_INDEX:
			_draw_overflow(placement.pos)
			continue
		var texture: Texture2D = placement.texture
		if texture == null:
			continue
		if bool(placement.is_npc):
			_draw_npc_marker(texture, placement.pos, icon_size)
		else:
			_draw_icon(texture, placement.pos, icon_size)

func _draw_icon(texture: Texture2D, slot_pos: Vector2, icon_size: Vector2) -> void:
	var dest := _fit_rect(texture, slot_pos, icon_size, 0.9)
	draw_texture_rect(texture, dest, false)

func _draw_npc_marker(texture: Texture2D, slot_pos: Vector2, icon_size: Vector2) -> void:
	# NPC-owned buildings read as a WHITE box with a thick navy outline, icon inside.
	var hw: float = icon_size.x * 0.45
	var hh: float = icon_size.y * 0.45
	var b := NPC_OUTLINE_PX
	draw_rect(Rect2(slot_pos - Vector2(hw + b, hh + b), Vector2(hw + b, hh + b) * 2.0), NPC_NAVY, true)
	draw_rect(Rect2(slot_pos - Vector2(hw, hh), Vector2(hw, hh) * 2.0), Color.WHITE, true)
	var inner := Vector2(hw * 2.0, hh * 2.0)
	draw_texture_rect(texture, _fit_rect_size(texture, slot_pos, inner, 0.8), false)

func _draw_overflow(slot_pos: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var size := roundi(_tile_size().y * 0.08)
	draw_string(font, slot_pos - Vector2(size * 0.25, -size * 0.35), "…",
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0.9, 0.9, 0.9))

func _fit_rect(texture: Texture2D, center: Vector2, slot: Vector2, fill: float) -> Rect2:
	return _fit_rect_size(texture, center, slot, fill)

func _fit_rect_size(texture: Texture2D, center: Vector2, box: Vector2, fill: float) -> Rect2:
	var tex_size := texture.get_size()
	if tex_size.x <= 0.0 or tex_size.y <= 0.0:
		return Rect2(center - box * 0.5, box)
	var scale_uniform: float = min(box.x / tex_size.x, box.y / tex_size.y) * fill
	var draw_size := tex_size * scale_uniform
	return Rect2(center - draw_size * 0.5, draw_size)

func _tile_center_world_pos(coord: Vector2i) -> Vector2:
	if terrain_layer != null:
		return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))
	return Vector2.ZERO

func _slot_position(tile_center: Vector2, slot_index: int) -> Vector2:
	# Lay out icons left-to-right, top-to-bottom in the icon area, centered on the tile.
	var col := slot_index % ICONS_PER_ROW
	var row := slot_index / ICONS_PER_ROW
	var icon_area := _icon_area_size()
	var icon_size := _icon_slot_size()
	var area_top_left := tile_center - (icon_area * 0.5)
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
