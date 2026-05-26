extends Node2D

const SliceMarkerScene: PackedScene = preload("res://scenes/slice_marker.tscn")

const POWER_COLORS: Dictionary = {
	"surplus": Color(0.2, 0.8, 0.2),         # green
	"deficit": Color(0.8, 0.2, 0.2),         # red
	"balanced": Color(0.2, 0.8, 0.2),        # green (same as surplus)
	"cables_missing": Color(0.05, 0.05, 0.05),  # near-black
	"cables_unused": Color(0.5, 0.5, 0.5),   # grey
}

const POWER_LABEL_FONT_SIZE := 22
const POWER_CIRCLE_RADIUS := 18.0

@onready var terrain_layer: TileMapLayer = %TerrainLayer

const BUILD_REQ_MARKER_SIZE := 32.0

var current_overlays: Array = []
var build_overlays: Array = []

func _ready() -> void:
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	Production.turn_processed.connect(_on_turn_processed)
	BuildMode.mode_entered.connect(_on_build_mode_entered)
	BuildMode.mode_exited.connect(_on_build_mode_exited)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_RIGHT \
			and event.pressed \
			and MapMode.current_mode != MapMode.Mode.NONE:
		MapMode.clear_all()
		get_viewport().set_input_as_handled()

func _on_selections_changed(mode: int, selections: Array) -> void:
	_clear_overlays()
	_render_overlay(mode, selections)

func _on_mode_cleared() -> void:
	_clear_overlays()

func _on_turn_processed(_summary: Dictionary) -> void:
	print("[MapOverlay] turn_processed received, current_mode=", MapMode.current_mode)
	if MapMode.current_mode != MapMode.Mode.NONE:
		_clear_overlays()
		_render_overlay(MapMode.current_mode, MapMode.selections)

func _clear_overlays() -> void:
	for node in current_overlays:
		if is_instance_valid(node):
			node.queue_free()
	current_overlays.clear()

# --- Build-mode requirement overlay (deposits / potentials) ---
# Shown while BuildMode is active for a recipe whose `requirements` reference
# a deposit or potential. Persists across placements; cleared only when
# BuildMode exits (right-click).

func _on_build_mode_entered(_building_id: String, recipe_id: String) -> void:
	_clear_build_overlays()
	if recipe_id == "":
		return
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		return
	var reqs: Array = recipe.get("requirements", [])
	if reqs.is_empty():
		return
	_render_build_overlay(reqs)

func _on_build_mode_exited() -> void:
	_clear_build_overlays()

func _clear_build_overlays() -> void:
	for node in build_overlays:
		if is_instance_valid(node):
			node.queue_free()
	build_overlays.clear()

func _render_build_overlay(reqs: Array) -> void:
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var matched_req: Dictionary = _first_matching_req(tile_data, reqs)
		if matched_req.is_empty():
			continue
		var marker := _make_build_req_marker(matched_req)
		marker.position = terrain_layer.map_to_local(coord)
		add_child(marker)
		build_overlays.append(marker)

func _first_matching_req(tile_data: Dictionary, reqs: Array) -> Dictionary:
	for req in reqs:
		if _tile_meets_build_req(tile_data, req):
			return req
	return {}

func _tile_meets_build_req(tile_data: Dictionary, req: Dictionary) -> bool:
	match req.get("type", ""):
		"deposit":
			var deps: Array = tile_data.get("deposits", [])
			return deps.has(req.get("value", ""))
		"potential":
			var v: String = req.get("value", "")
			if v == "wind":
				return tile_data.get("wind_potential", 0) > 0
			if v == "solar":
				return tile_data.get("solar_potential", 0) > 0
			return false
		_:
			return false

func _make_build_req_marker(req: Dictionary) -> Node2D:
	if req.get("type", "") == "deposit":
		var tex: Texture2D = _load_deposit_icon(req.get("value", ""))
		if tex != null:
			var sprite := Sprite2D.new()
			sprite.texture = tex
			var tex_size: Vector2 = tex.get_size()
			if tex_size.x > 0 and tex_size.y > 0:
				var s: float = BUILD_REQ_MARKER_SIZE / max(tex_size.x, tex_size.y)
				sprite.scale = Vector2(s, s)
			return sprite
	# Fallback to a red potentials-style marker
	var marker := SliceMarkerScene.instantiate()
	marker.set_colors([Color.RED])
	return marker

func _load_deposit_icon(deposit_name: String) -> Texture2D:
	if deposit_name == "":
		return null
	var good: Dictionary = Catalog.get_good_by_internal_name(deposit_name)
	if good.is_empty():
		return null
	var good_id: String = good.get("id", "")
	if good_id == "":
		return null
	for ext in ["PNG", "png"]:
		var path: String = "res://assets/icons/goods/medium/%s_%s.%s" % [good_id, deposit_name, ext]
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null

# --- Top-level dispatch ---

func _render_overlay(mode: int, selections: Array) -> void:
	if mode == MapMode.Mode.POWER_BALANCE:
		_render_power_overlay()
	else:
		_render_resource_overlay(mode, selections)

# --- Resource overlay (Potentials / Producing / Consuming) ---

func _render_resource_overlay(mode: int, selections: Array) -> void:
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var colors_for_tile: Array[Color] = []
		for s in selections:
			if _tile_matches(mode, tile_data, s.good_id):
				colors_for_tile.append(s.color)
		if not colors_for_tile.is_empty():
			var marker := SliceMarkerScene.instantiate()
			marker.position = terrain_layer.map_to_local(coord)
			marker.set_colors(colors_for_tile)
			add_child(marker)
			current_overlays.append(marker)

func _tile_matches(mode: int, tile_data: Dictionary, good_id: String) -> bool:
	match mode:
		MapMode.Mode.POTENTIALS:
			return _tile_has_potential(tile_data, good_id)
		MapMode.Mode.TILES_PRODUCING:
			return _tile_produces(tile_data, good_id)
		MapMode.Mode.TILES_CONSUMING:
			return _tile_consumes(tile_data, good_id)
	return false

func _tile_has_potential(tile_data: Dictionary, good_id: String) -> bool:
	if good_id == "solar" or good_id == "g_solar":
		return tile_data.get("solar_potential", 0) > 0
	if good_id == "wind" or good_id == "g_wind":
		return tile_data.get("wind_potential", 0) > 0
	var deposits: Array = tile_data.get("deposits", [])
	if deposits.is_empty():
		return false
	var internal := Catalog.get_internal_name(good_id)
	return deposits.has(good_id) or deposits.has(internal)

func _tile_produces(tile_data: Dictionary, good_id: String) -> bool:
	var tile_id: String = tile_data.get("id", "")
	if tile_id == "":
		return false
	
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	if instance_ids.is_empty():
		return false
	
	var target_internal: String = Catalog.get_internal_name(good_id)
	if target_internal == "":
		return false
	
	for inst_id in instance_ids:
		if not Production.last_turn_run.get(inst_id, false):
			continue
		
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		
		if recipe.get("output_name", "") == target_internal:
			return true
	
	return false

func _tile_consumes(tile_data: Dictionary, good_id: String) -> bool:
	var tile_id: String = tile_data.get("id", "")
	if tile_id == "":
		return false
	
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	if instance_ids.is_empty():
		return false
	
	var target_internal: String = Catalog.get_internal_name(good_id)
	if target_internal == "":
		return false
	
	for inst_id in instance_ids:
		if not Production.last_turn_run.get(inst_id, false):
			continue
		
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		
		var inputs: Array = recipe.get("inputs", [])
		for input in inputs:
			if input.get("internal_name", "") == target_internal:
				return true
	
	return false

# --- Power balance overlay ---

func _render_power_overlay() -> void:
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var status: Dictionary = _get_power_status_for_tile(tile_data)
		if status.state == "none":
			continue
		var world_pos: Vector2 = terrain_layer.map_to_local(coord)
		_draw_power_marker(world_pos, status)

func _draw_power_marker(world_pos: Vector2, status: Dictionary) -> void:
	var marker := Node2D.new()
	marker.position = world_pos
	add_child(marker)
	current_overlays.append(marker)
	
	var color: Color = POWER_COLORS.get(status.state, Color.MAGENTA)
	
	# Coloured circle background
	var circle := _make_circle_node(color, POWER_CIRCLE_RADIUS)
	marker.add_child(circle)
	
	# Label (if state has a number)
	# Label (if state has a number)
	var label_text: String = _format_power_label(status)
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.add_theme_font_size_override("font_size", POWER_LABEL_FONT_SIZE)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Fixed-size box centred on origin for any 1-5 char label
		label.size = Vector2(POWER_CIRCLE_RADIUS * 2, POWER_CIRCLE_RADIUS * 2)
		label.position = -label.size / 2.0
		marker.add_child(label)

func _format_power_label(status: Dictionary) -> String:
	match status.state:
		"surplus":
			return "+%d" % status.net
		"deficit":
			return "%d" % status.net  # already negative, "-N"
		"balanced":
			return "0"
		"cables_missing":
			return "(-%d)" % status.power_required
		"cables_unused":
			return ""
		_:
			return ""

func _make_circle_node(color: Color, radius: float) -> Node2D:
	var node := Node2D.new()
	node.set_script(load("res://scripts/circle_drawer.gd"))
	node.set("color", color)
	node.set("radius", radius)
	return node

func _get_power_status_for_tile(tile_data: Dictionary) -> Dictionary:
	var tile_id: String = tile_data.get("id", "")
	if tile_id == "":
		return {"state": "none"}
	
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	var has_cables: bool = tile_data.get("infrastructure_present", []).has("cables")
	
	var power_produced: int = 0
	var power_consumed: int = 0
	var power_required_total: int = 0
	var has_power_buildings: bool = false
	
	for inst_id in instance_ids:
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		
		var ran_last_turn: bool = Production.last_turn_run.get(inst_id, false)
		var produces_power: bool = recipe.get("output_name", "") == "power"
		var energy_req: int = recipe.get("energy_req", 0)
		
		if produces_power or energy_req > 0:
			has_power_buildings = true
		
		if produces_power and ran_last_turn:
			power_produced += recipe.get("output_qty", 0)
		
		if energy_req > 0:
			power_required_total += energy_req
			if ran_last_turn:
				power_consumed += energy_req
	
	if has_power_buildings:
		if power_required_total > 0 and not has_cables:
			return {"state": "cables_missing", "power_required": power_required_total}
		var net: int = power_produced - power_consumed
		if net > 0:
			return {"state": "surplus", "net": net}
		elif net < 0:
			return {"state": "deficit", "net": net}
		else:
			return {"state": "balanced", "net": 0}
	elif has_cables:
		return {"state": "cables_unused"}
	else:
		return {"state": "none"}
