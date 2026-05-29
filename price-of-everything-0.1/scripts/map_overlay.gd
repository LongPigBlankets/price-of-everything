extends Node2D

const SliceMarkerScene: PackedScene = preload("res://scenes/slice_marker.tscn")
const BuildModeHexOverlayScript: Script = preload("res://scripts/build_mode_hex_overlay.gd")
const BuildModeBackdropScript: Script = preload("res://scripts/build_mode_backdrop.gd")

const POWER_COLORS: Dictionary = {
	"surplus": Color(0.2, 0.8, 0.2),         # green
	"deficit": Color(0.8, 0.2, 0.2),         # red
	"balanced": Color(0.2, 0.8, 0.2),        # green (same as surplus)
	"cables_missing": Color(0.05, 0.05, 0.05),  # near-black
	"cables_unused": Color(0.5, 0.5, 0.5),   # grey
}

const POWER_LABEL_FONT_SIZE := 22
const POWER_CIRCLE_RADIUS := 18.0
const BUILD_TILE_VERTICAL_OFFSET := Vector2(0, -5)
const BUILD_RED := Color(0.45, 0.02, 0.02, 0.42)
const BUILD_DARK_GREEN := Color(0.02, 0.28, 0.1, 0.34)
const BUILD_LIGHT_GREEN := Color(0.45, 1.0, 0.48, 0.86)

@onready var terrain_layer: HexMap = %TerrainLayer

var current_overlays: Array = []
var build_overlays: Array = []
var build_legend: PanelContainer = null

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

# --- Build-mode viability overlay ---

func _on_build_mode_entered(_building_id: String, recipe_id: String) -> void:
	_clear_build_overlays()
	_show_build_legend()
	if recipe_id == "":
		return
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	if recipe.is_empty():
		return
	_render_build_overlay(recipe)

func _on_build_mode_exited() -> void:
	_clear_build_overlays()
	_hide_build_legend()

func _clear_build_overlays() -> void:
	for node in build_overlays:
		if is_instance_valid(node):
			node.queue_free()
	build_overlays.clear()

func _render_build_overlay(recipe: Dictionary) -> void:
	_add_build_backdrop()
	var reqs: Array = recipe.get("requirements", [])
	var input_names: Array[String] = _recipe_input_internal_names(recipe)
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var state := _build_overlay_state(tile_data, reqs, input_names)
		if state == "none":
			continue
		var marker := _make_build_hex_marker(state)
		marker.position = _tile_world_pos(coord) + BUILD_TILE_VERTICAL_OFFSET
		add_child(marker)
		build_overlays.append(marker)

func _add_build_backdrop() -> void:
	var backdrop := Node2D.new()
	backdrop.set_script(BuildModeBackdropScript)
	backdrop.set("bounds", _map_bounds())
	add_child(backdrop)
	build_overlays.append(backdrop)

func _map_bounds() -> Rect2:
	var has_tile := false
	var min_pos := Vector2.ZERO
	var max_pos := Vector2.ZERO
	for coord in terrain_layer.tiles:
		var pos: Vector2 = _tile_world_pos(coord)
		if not has_tile:
			min_pos = pos
			max_pos = pos
			has_tile = true
			continue
		min_pos.x = min(min_pos.x, pos.x)
		min_pos.y = min(min_pos.y, pos.y)
		max_pos.x = max(max_pos.x, pos.x)
		max_pos.y = max(max_pos.y, pos.y)
	if not has_tile:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return Rect2(min_pos - _tile_size(), (max_pos - min_pos) + _tile_size() * 2.0)

func _build_overlay_state(tile_data: Dictionary, reqs: Array, input_names: Array[String]) -> String:
	var matched_input_count := _tile_input_match_count(tile_data, input_names)
	var tracked_input_count := input_names.size()
	if tracked_input_count > 0:
		if matched_input_count >= 2 or matched_input_count >= tracked_input_count:
			return "recommended"
		if tracked_input_count > 1 and matched_input_count == 1:
			return "viable"
	if not reqs.is_empty() and _tile_meets_all_build_reqs(tile_data, reqs):
		return "recommended"
	if reqs.is_empty():
		return "none"
	return "blocked"

func _tile_meets_all_build_reqs(tile_data: Dictionary, reqs: Array) -> bool:
	for req in reqs:
		if not _tile_meets_build_req(tile_data, req):
			return false
	return true

func _tile_meets_build_req(tile_data: Dictionary, req: Dictionary) -> bool:
	match req.get("type", ""):
		"deposit":
			var deps: Array = tile_data.get("deposits", [])
			return deps.has(req.get("value", ""))
		"produces":
			return _tile_produces_good(tile_data, req.get("value", ""))
		"potential":
			var v: String = req.get("value", "")
			if v == "wind":
				return tile_data.get("wind_potential", 0) > 0
			if v == "solar":
				return tile_data.get("solar_potential", 0) > 0
			return false
		_:
			return false

func _make_build_hex_marker(state: String) -> Node2D:
	var marker := Node2D.new()
	marker.set_script(BuildModeHexOverlayScript)
	marker.set("tile_size", _tile_size())
	match state:
		"blocked":
			marker.set("fill_color", BUILD_RED)
			marker.set("hatch_color", Color(1, 0.42, 0.42, 0.28))
		"viable":
			marker.set("fill_color", BUILD_DARK_GREEN)
			marker.set("hatch_color", Color(0.65, 1, 0.72, 0.26))
		"recommended":
			marker.set("fill_color", BUILD_LIGHT_GREEN)
			marker.set("hatch_color", Color(0.03, 0.2, 0.06, 0.34))
	return marker

func _recipe_input_internal_names(recipe: Dictionary) -> Array[String]:
	var input_names: Array[String] = []
	for input in recipe.get("inputs", []):
		var internal_name: String = input.get("internal_name", "")
		if internal_name != "" and not input_names.has(internal_name):
			input_names.append(internal_name)
	for req in recipe.get("requirements", []):
		if req.get("type", "") == "deposit":
			var deposit_name: String = req.get("value", "")
			if deposit_name != "" and not input_names.has(deposit_name):
				input_names.append(deposit_name)
	return input_names

func _tile_input_match_count(tile_data: Dictionary, input_names: Array[String]) -> int:
	var matches := 0
	for input_name in input_names:
		if _tile_has_deposit(tile_data, input_name) or _tile_produces_good(tile_data, input_name):
			matches += 1
	return matches

func _tile_has_deposit(tile_data: Dictionary, internal_name: String) -> bool:
	var deposits: Array = tile_data.get("deposits", [])
	return deposits.has(internal_name)

func _tile_produces_good(tile_data: Dictionary, internal_name: String) -> bool:
	var tile_id: String = tile_data.get("id", "")
	if tile_id == "":
		return false
	var instance_ids: Array = MatchState.tile_buildings.get(tile_id, [])
	for inst_id in instance_ids:
		var building: Dictionary = MatchState.buildings.get(inst_id, {})
		if building.is_empty():
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.get("output_name", "") == internal_name:
			return true
		for output in recipe.get("outputs", []):
			if output.get("internal_name", "") == internal_name:
				return true
	return false

func _show_build_legend() -> void:
	if build_legend == null:
		build_legend = _make_build_legend()
	build_legend.show()

func _hide_build_legend() -> void:
	if build_legend != null:
		build_legend.hide()

func _make_build_legend() -> PanelContainer:
	var parent_control := get_parent().get_node_or_null("UILayer/HUD/HUDContent") as Control
	var panel := PanelContainer.new()
	panel.name = "BuildModeLegend"
	panel.custom_minimum_size = Vector2(230, 132)
	panel.anchor_left = 1.0
	panel.anchor_top = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -250
	panel.offset_top = -166
	panel.offset_right = -20
	panel.offset_bottom = -20
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.07, 0.12, 0.92)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(0.55, 0.7, 0.82, 0.65)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	if parent_control != null:
		parent_control.add_child(panel)
	else:
		add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Build viability"
	title.add_theme_font_size_override("font_size", 14)
	box.add_child(title)
	_add_build_legend_row(box, BUILD_RED, "Cannot build")
	_add_build_legend_row(box, BUILD_DARK_GREEN, "1 input present")
	_add_build_legend_row(box, BUILD_LIGHT_GREEN, "2+ / all met")
	_add_build_legend_row(box, Color(0, 0, 0, 0), "Unrestricted")
	return panel

func _add_build_legend_row(parent: VBoxContainer, color: Color, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.color = color
	row.add_child(swatch)
	var label := Label.new()
	label.text = text
	row.add_child(label)

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
			marker.position = _tile_world_pos(coord)
			marker.radius = _tile_marker_radius()
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
		var world_pos: Vector2 = _tile_world_pos(coord)
		_draw_power_marker(world_pos, status)

func _draw_power_marker(world_pos: Vector2, status: Dictionary) -> void:
	var marker := Node2D.new()
	marker.position = world_pos
	add_child(marker)
	current_overlays.append(marker)
	
	var color: Color = POWER_COLORS.get(status.state, Color.MAGENTA)
	var radius := _power_circle_radius()
	
	# Coloured circle background
	var circle := _make_circle_node(color, radius)
	marker.add_child(circle)
	
	# Label (if state has a number)
	# Label (if state has a number)
	var label_text: String = _format_power_label(status)
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.add_theme_font_size_override("font_size", _power_label_font_size())
		label.add_theme_color_override("font_color", Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Fixed-size box centred on origin for any 1-5 char label
		label.size = Vector2(radius * 2, radius * 2)
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

func _tile_world_pos(coord: Vector2i) -> Vector2:
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _tile_size() -> Vector2:
	if terrain_layer != null and terrain_layer.tile_set != null:
		return Vector2(terrain_layer.tile_set.tile_size)
	return Vector2(540, 480)

func _tile_marker_radius() -> float:
	return maxf(20.0, minf(_tile_size().x, _tile_size().y) * 0.08)

func _power_circle_radius() -> float:
	return maxf(POWER_CIRCLE_RADIUS, minf(_tile_size().x, _tile_size().y) * 0.075)

func _power_label_font_size() -> int:
	return maxi(POWER_LABEL_FONT_SIZE, roundi(_power_circle_radius() * 0.85))

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
