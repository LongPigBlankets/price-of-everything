extends Node2D

const SliceMarkerScene: PackedScene = preload("res://scenes/slice_marker.tscn")
const BuildModeHexOverlayScript: Script = preload("res://scripts/build_mode_hex_overlay.gd")
const BuildModeBackdropScript: Script = preload("res://scripts/build_mode_backdrop.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const InfraIcons := preload("res://scripts/infra_icons.gd")
const InfraMarkersScript := preload("res://scripts/infra_mapmode_markers.gd")

# Producing / Consuming icons are sized as a fraction of the tile (world units),
# so they scale with zoom. Multiple selected goods on one tile cluster + shrink.
# Cluster shapes (offsets are tile fractions, centred on the tile):
#   1 centre · 2 side-by-side · 3 triangle · 4 square · 5 square + one on top
#   middle · 6 a 3-row × 2-column grid. Player can pick at most MAX_SELECTIONS (6).
const RESOURCE_ICON_TILE_FRACTION := 0.5
const RESOURCE_CLUSTER_OFFSETS := {
	1: [Vector2(0, 0)],
	2: [Vector2(-0.18, 0), Vector2(0.18, 0)],
	3: [Vector2(0, -0.19), Vector2(-0.19, 0.16), Vector2(0.19, 0.16)],
	4: [Vector2(-0.18, -0.18), Vector2(0.18, -0.18), Vector2(-0.18, 0.18), Vector2(0.18, 0.18)],
	5: [Vector2(0, -0.32), Vector2(-0.22, -0.04), Vector2(0.22, -0.04), Vector2(-0.22, 0.26), Vector2(0.22, 0.26)],
	6: [Vector2(-0.22, -0.30), Vector2(0.22, -0.30), Vector2(-0.22, 0.0), Vector2(0.22, 0.0), Vector2(-0.22, 0.30), Vector2(0.22, 0.30)],
}
# Icon scale (fraction of the single-icon size) per cluster count. The single-icon
# size is RESOURCE_ICON_TILE_FRACTION (0.5) of the tile, so a 0.80 factor → 40% of
# the tile each. Counts 2–4 stay large (fill the tile, overlap a little); 5–6
# shrink so the grid still fits.
const RESOURCE_CLUSTER_SCALE := {
	1: 1.0, 2: 0.80, 3: 0.80, 4: 0.80, 5: 0.46, 6: 0.44,
}

const POWER_COLORS: Dictionary = {
	"surplus": Color(0.2, 0.8, 0.2),         # green
	"self_supplied": Color(0.95, 0.65, 0.10),# amber — deficit covered 100% by your own production
	"national": Color(0.8, 0.2, 0.2),        # red — drawn from the national grid
	"deficit": Color(0.8, 0.2, 0.2),         # red (legacy fallback)
	"balanced": Color(0.2, 0.8, 0.2),        # green (same as surplus)
	"cables_missing": Color(0.05, 0.05, 0.05),  # near-black
	"cables_unused": Color(0.5, 0.5, 0.5),   # grey
}

const POWER_LABEL_FONT_SIZE := 40
const POWER_CIRCLE_RADIUS := 18.0
const BUILD_TILE_VERTICAL_OFFSET := Vector2(0, -5)
const TILE_MASK_ALPHA := 0.5
const LEGEND_LEFT := 12.0
const LEGEND_BOTTOM := 24.0
const BUILD_RED := Color(0.45, 0.02, 0.02, TILE_MASK_ALPHA)
const BUILD_DARK_GREEN := Color(0.02, 0.34, 0.12, TILE_MASK_ALPHA)
const BUILD_LIGHT_GREEN := Color(0.45, 1.0, 0.48, TILE_MASK_ALPHA)

@onready var terrain_layer: HexMap = %TerrainLayer

var current_overlays: Array = []
var build_overlays: Array = []
var build_legend: PanelContainer = null

# Infrastructure hover: while the infra overlay is up, the built tile under the
# mouse gets a white glow + throughput card (see infra_mapmode_markers.gd).
var _infra_markers: Node2D = null
var _infra_built_pos: Dictionary = {}   # tile_id -> tile-centre world pos
var _infra_hover_tile := ""

# Infrastructure mapmode key -> the router's mode name (Catalog namespace).
const INFRA_ROUTE_MODES := {
	"roads": "roads", "rails": "rail", "pipes": "pipes", "reinf_pipes": "reinf_pipes",
}

func _ready() -> void:
	set_process(false)
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	MapMode.infrastructure_selection_changed.connect(_on_infra_selection_changed)
	# Construction lifecycle redraws the infrastructure overlay's dashed state.
	# Deferred so world_map applies a completed infra build to its tile first —
	# otherwise the re-render runs before the tile gains the infra and the
	# just-finished tile would briefly show neither dashed nor solid.
	Construction.construction_started.connect(_on_construction_changed, CONNECT_DEFERRED)
	Construction.construction_completed.connect(_on_construction_changed, CONNECT_DEFERRED)
	Construction.construction_cancelled.connect(_on_construction_changed, CONNECT_DEFERRED)
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

func _on_infra_selection_changed() -> void:
	if MapMode.current_mode == MapMode.Mode.INFRASTRUCTURE:
		_on_selections_changed(MapMode.current_mode, MapMode.selections)

func _on_construction_changed(_instance_id: String, _tile_id: String) -> void:
	_on_infra_selection_changed()

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
	_infra_markers = null
	_infra_built_pos.clear()
	_infra_hover_tile = ""
	set_process(false)

# --- Build-mode viability overlay ---

func _on_build_mode_entered(_building_id: String, recipe_id: String) -> void:
	_clear_build_overlays()
	var recipe: Dictionary = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	_show_build_legend()
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
	if terrain_layer != null and terrain_layer.has_method("map_world_rect"):
		return terrain_layer.map_world_rect()
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
	var tile_id: String = tile_data.get("id", "")
	if MatchState.survey_status(tile_id, str(tile_data.get("type", ""))) == "unsurveyed":
		return "none"
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
			return _deposits_include(deps, str(req.get("value", "")))
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
		"viable":
			marker.set("fill_color", BUILD_DARK_GREEN)
		"recommended":
			marker.set("fill_color", BUILD_LIGHT_GREEN)
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
	# TODO: Surface finite deposit quantities like coal(500) in build mode once
	# temporary deposits have depletion/remaining-amount gameplay.
	return _deposits_include(deposits, internal_name)

func _deposits_include(deposits: Array, internal_name: String) -> bool:
	if internal_name == "":
		return false
	for deposit in deposits:
		if _deposit_base_name(str(deposit)) == internal_name:
			return true
	return false

func _deposit_base_name(deposit: String) -> String:
	var value := deposit.strip_edges()
	var quantity_marker := value.find("(")
	if quantity_marker > 0 and value.ends_with(")"):
		return value.substr(0, quantity_marker)
	return value

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
	if build_legend != null and is_instance_valid(build_legend):
		build_legend.queue_free()
	build_legend = _make_build_legend()
	build_legend.show()

func _hide_build_legend() -> void:
	if build_legend != null:
		build_legend.hide()

func _make_build_legend() -> PanelContainer:
	var parent_control := get_parent().get_node_or_null("UILayer/HUD/HUDContent") as Control
	var panel := PanelContainer.new()
	panel.name = "BuildModeLegend"
	var height := 146
	panel.custom_minimum_size = Vector2(230, height)
	panel.anchor_left = 0.0
	panel.anchor_top = 1.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = LEGEND_LEFT
	panel.offset_top = -(height + LEGEND_BOTTOM)
	panel.offset_right = LEGEND_LEFT + 230
	panel.offset_bottom = -LEGEND_BOTTOM
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
	_add_build_legend_note(box, "Unsurveyed tiles are hidden")
	_add_build_legend_note(box, "Partial surveys can match")
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

func _add_build_legend_note(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.78, 0.86, 0.9, 0.82))
	parent.add_child(label)

# --- Top-level dispatch ---

func _render_overlay(mode: int, selections: Array) -> void:
	if mode == MapMode.Mode.POWER_BALANCE:
		_render_power_overlay()
	elif mode == MapMode.Mode.INFRASTRUCTURE:
		_render_infrastructure_overlay()
	else:
		_render_resource_overlay(mode, selections)

# --- Infrastructure overlay ---
# Entering the mode darkens the map (build-mode backdrop); the Infrastructure
# panel's single pick then shows every tile holding that infrastructure as a
# coloured circle, with lines joining adjacent same-infrastructure tiles
# (dashed when under construction — see infra_mapmode_markers.gd).

func _render_infrastructure_overlay() -> void:
	var backdrop := Node2D.new()
	backdrop.set_script(BuildModeBackdropScript)
	backdrop.set("bounds", _map_bounds())
	add_child(backdrop)
	current_overlays.append(backdrop)
	var infra_key: String = MapMode.infrastructure_selection
	if infra_key == "":
		return

	var built: Dictionary = {}  # coord -> tile-centre world pos
	for coord in terrain_layer.tiles:
		if _tile_has_infrastructure(terrain_layer.tiles[coord], infra_key):
			built[coord] = _tile_world_pos(coord)
	var under_construction := _infra_construction_tiles(infra_key, built)

	var markers := InfraMarkersScript.new()
	markers.color = InfraIcons.color_for(infra_key)
	markers.circles = built.values()
	for coord in built:
		for n in terrain_layer.neighbor_coords(coord):
			if built.has(n):
				if _coord_precedes(coord, n):  # each pair once
					var level: int = mini(_infra_level(coord, infra_key), _infra_level(n, infra_key))
					markers.solid_links.append({"a": built[coord], "b": built[n], "level": level})
			elif under_construction.has(n):
				# Under-construction infrastructure has no level yet — level 1.
				markers.dashed_links.append({"a": built[coord], "b": under_construction[n], "level": 1})
	for coord in under_construction:
		var neighbors := terrain_layer.neighbor_coords(coord)
		var connected := false
		for n in neighbors:
			if built.has(n):
				connected = true
			elif under_construction.has(n):
				connected = true
				if _coord_precedes(coord, n):
					markers.dashed_links.append({"a": under_construction[coord], "b": under_construction[n], "level": 1})
		if connected:
			markers.uc_circles.append(under_construction[coord])
		else:
			var edge_mids: Array = []
			for n in neighbors:
				edge_mids.append((under_construction[coord] + _tile_world_pos(n)) * 0.5)
			markers.stranded.append({"pos": under_construction[coord], "edge_mids": edge_mids})
	add_child(markers)
	current_overlays.append(markers)

	# Hover: track the built tile under the mouse every frame while this
	# overlay is up (cleared with the overlay in _clear_overlays).
	_infra_markers = markers
	for coord in built:
		_infra_built_pos["tile_%d_%d" % [coord.x + 1, coord.y + 1]] = built[coord]
	set_process(true)

func _process(_delta: float) -> void:
	if _infra_markers == null or not is_instance_valid(_infra_markers):
		set_process(false)
		return
	var tile_id := terrain_layer.tile_id_under_mouse()
	if not _infra_built_pos.has(tile_id):
		tile_id = ""
	if tile_id == _infra_hover_tile:
		return
	_infra_hover_tile = tile_id
	if tile_id == "":
		_infra_markers.set_hover(Vector2.INF, [])
	else:
		_infra_markers.set_hover(_infra_built_pos[tile_id],
			_infra_hover_lines(tile_id, MapMode.infrastructure_selection))

# Throughput card rows for a hovered built tile. Shipment-carried infra counts
# the in-transit units whose route crosses this tile on this infra's network;
# cables report the (single, global) grid's energy flow — uncapped.
func _infra_hover_lines(tile_id: String, infra_key: String) -> Array:
	var lines: Array = ["%s throughput" % _infra_slot_label(infra_key)]
	match infra_key:
		"cables":
			lines.append("Grid energy: %d" % maxi(Power.supply_this_turn, Power.demand_this_turn))
			lines.append("No cap")
		"pipes":
			var t: Dictionary = _tile_mode_throughput(tile_id, "pipes")
			lines.append("Liquids: %d" % (int(t.get("safe_liquid", 0)) + int(t.get("liquid", 0))))
			lines.append("Gases: %d" % int(t.get("gas", 0)))
		"reinf_pipes":
			var t2: Dictionary = _tile_mode_throughput(tile_id, "reinf_pipes")
			lines.append("Hazard liquids: %d" % int(t2.get("hazard_liquid", 0)))
			lines.append("Gases: %d" % int(t2.get("gas", 0)))
		_:
			var mode: String = INFRA_ROUTE_MODES.get(infra_key, "")
			# Same flow the tile-view uses: networked pass-through + first/last-mile.
			var total := MatchState.tile_mode_flow(tile_id, mode) if mode != "" else 0
			var cap: float = MatchState.tile_mode_capacity(mode, _infra_level(terrain_layer.id_to_coord(tile_id), infra_key))
			if cap > 0.0:
				lines.append("Transit units: %d / %d" % [total, int(round(cap))])
			else:
				lines.append("Transit units: %d" % total)
	return lines

func _infra_slot_label(infra_key: String) -> String:
	for slot in InfraIcons.SLOTS:
		if str(slot.key) == infra_key:
			return str(slot.label)
	return infra_key.capitalize()

# Units of in-transit goods crossing `tile_id` on a leg of routing `mode`,
# bucketed by the good's transport class.
func _tile_mode_throughput(tile_id: String, mode: String) -> Dictionary:
	var totals: Dictionary = {}
	for s in MatchState.get_pending_transport_shipments():
		var tiles: Array = s.get("tiles", [])
		var legs: Array = s.get("legs", [])
		if tiles.is_empty() or legs.is_empty():
			continue
		if not _shipment_mode_tiles(tiles, legs, mode).has(tile_id):
			continue
		var goods := _shipment_goods(s)
		for good_id in goods:
			var cls := Catalog.get_transport_class(str(good_id))
			totals[cls] = int(totals.get(cls, 0)) + int(goods[good_id])
	return totals

# The tiles a shipment crosses using `mode` (tile_id -> true). A route's
# `tiles` array is its legs' tile segments concatenated in order, so walking
# it leg by leg recovers which slice belongs to which mode.
func _shipment_mode_tiles(tiles: Array, legs: Array, mode: String) -> Dictionary:
	var result: Dictionary = {}
	var idx := 0
	for leg in legs:
		var start := idx
		while idx < tiles.size() - 1 and str(tiles[idx]) != str(leg.get("to", "")):
			idx += 1
		if str(leg.get("mode", "")) == mode:
			for i in range(start, idx + 1):
				result[str(tiles[i])] = true
	return result

# {good_id: qty} carried by a shipment (sale shipments carry several goods).
func _shipment_goods(s: Dictionary) -> Dictionary:
	var g: Dictionary = {}
	if bool(s.get("is_sale", false)):
		for item in s.get("sale_record", {}).get("items", []):
			g[str(item.get("good_id", ""))] = int(item.get("qty", 0))
	else:
		var gid := str(s.get("good_id", ""))
		if gid != "":
			g[gid] = int(s.get("qty", 0))
	return g

# Tiles with a pending construction project for this infrastructure type
# (coord -> world pos). Tiles that already hold the built infra are skipped.
func _infra_construction_tiles(infra_key: String, built: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for instance_id in Construction.construction_projects:
		var project: Dictionary = Construction.construction_projects[instance_id]
		var building: Dictionary = Catalog.get_building(str(project.get("building_id", "")))
		if InfraIcons.normalise(str(building.get("internal_name", ""))) != infra_key:
			continue
		var coord: Vector2i = terrain_layer.id_to_coord(str(project.get("tile_id", "")))
		if coord != Vector2i(-1, -1) and terrain_layer.tiles.has(coord) and not built.has(coord):
			result[coord] = _tile_world_pos(coord)
	return result

func _coord_precedes(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y if a.x == b.x else a.x < b.x

# A tile's level for an infrastructure type (default 1). Levels live in the
# tile's `infrastructure_levels` dict, keyed by the canonical slot key.
func _infra_level(coord: Vector2i, infra_key: String) -> int:
	var tile_data: Dictionary = terrain_layer.tiles.get(coord, {})
	return int(tile_data.get("infrastructure_levels", {}).get(infra_key, 1))

func _tile_has_infrastructure(tile_data: Dictionary, infra_key: String) -> bool:
	for entry in tile_data.get("infrastructure_present", []):
		if InfraIcons.normalise(str(entry)) == infra_key:
			return true
	return false

# --- Resource overlay (Producing / Consuming) ---
# Each selected good is drawn on a matching tile as its own icon (goods with no
# art fall back to a colour slice so they stay visible).

func _render_resource_overlay(mode: int, selections: Array) -> void:
	var icon_world := _resource_icon_world_size()
	var tile := _tile_size()
	for coord in terrain_layer.tiles:
		var tile_data: Dictionary = terrain_layer.tiles[coord]
		var matched: Array = []
		for s in selections:
			if _tile_matches(mode, tile_data, s.good_id):
				matched.append(s)
		if matched.is_empty():
			continue
		_place_resource_markers(_tile_world_pos(coord), matched, icon_world, tile)

func _place_resource_markers(center: Vector2, matched: Array, icon_world: float, tile: Vector2) -> void:
	# Up to 6 icons cluster on one tile (matches the MAX_SELECTIONS cap).
	var count: int = mini(matched.size(), 6)
	var offsets: Array = RESOURCE_CLUSTER_OFFSETS.get(count, RESOURCE_CLUSTER_OFFSETS[1])
	var size := icon_world * float(RESOURCE_CLUSTER_SCALE.get(count, 1.0))
	for i in count:
		var s: Dictionary = matched[i]
		var offset: Vector2 = offsets[i] * tile
		var node := _make_resource_marker(str(s.good_id), s.color, size)
		node.position = center + offset
		add_child(node)
		current_overlays.append(node)

func _make_resource_marker(good_id: String, color: Color, world_size: float) -> Node2D:
	var tex := GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id), true)
	if tex != null:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.centered = true
		var dim: float = maxf(1.0, float(maxi(tex.get_width(), tex.get_height())))
		var scale_factor := world_size / dim
		sprite.scale = Vector2(scale_factor, scale_factor)
		return sprite
	# No art for this good — fall back to the colour slice marker.
	var marker := SliceMarkerScene.instantiate()
	marker.radius = _tile_marker_radius()
	marker.set_colors([color] as Array[Color])
	return marker

func _resource_icon_world_size() -> float:
	return minf(_tile_size().x, _tile_size().y) * RESOURCE_ICON_TILE_FRACTION

func _tile_matches(mode: int, tile_data: Dictionary, good_id: String) -> bool:
	match mode:
		MapMode.Mode.TILES_PRODUCING:
			return _tile_produces(tile_data, good_id)
		MapMode.Mode.TILES_CONSUMING:
			return _tile_consumes(tile_data, good_id)
	return false

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

		# Match ANY output, not just the primary one — a chemical plant emits
		# chlorine *and* sodium hydroxide, so both goods must light up its tile.
		if _recipe_outputs_good(recipe, target_internal):
			# A mine whose deposit ran out is no longer producing — drop the icon.
			if _recipe_deposit_exhausted(tile_id, recipe):
				continue
			return true

	return false

# True if internal_name is the recipe's primary output or any secondary output.
func _recipe_outputs_good(recipe: Dictionary, internal_name: String) -> bool:
	if recipe.get("output_name", "") == internal_name:
		return true
	for output in recipe.get("outputs", []):
		if str(output.get("internal_name", "")) == internal_name:
			return true
	return false

# True if the recipe needs a (depletable) deposit that this tile has mined out.
# Pure water never depletes, so it's ignored.
func _recipe_deposit_exhausted(tile_id: String, recipe: Dictionary) -> bool:
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) != "deposit":
			continue
		var token: String = str(req.get("value", ""))
		if token == "" or token == "water":
			continue
		if MatchState.deposit_remaining_for(tile_id, token) == 0:
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

	var tile := _tile_size()

	# Transparent hex the size of the tile (was a small circle).
	var hex := Node2D.new()
	hex.set_script(load("res://scripts/power_hex_overlay.gd"))
	hex.set("tile_size", tile)
	if status.state == "partial":
		# Some consumption self-supplied, some from the national grid -> amber base + red bars.
		var amber: Color = POWER_COLORS["self_supplied"]
		var red: Color = POWER_COLORS["national"]
		hex.set("color", Color(amber.r, amber.g, amber.b, TILE_MASK_ALPHA))
		hex.set("hatch", true)
		hex.set("hatch_color", Color(red.r, red.g, red.b, TILE_MASK_ALPHA))
	else:
		var color: Color = POWER_COLORS.get(status.state, Color.MAGENTA)
		hex.set("color", Color(color.r, color.g, color.b, TILE_MASK_ALPHA))
	marker.add_child(hex)

	# Label (if state has a number) — outlined so it stays legible over the tile.
	var label_text: String = _format_power_label(status)
	if label_text != "":
		var label := Label.new()
		label.text = label_text
		label.add_theme_font_size_override("font_size", _power_label_font_size())
		label.add_theme_color_override("font_color", Color.WHITE)
		label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
		label.add_theme_constant_override("outline_size", 5)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Box spans the tile so the number sits at the hex centre.
		label.size = tile
		label.position = -tile / 2.0
		marker.add_child(label)

func _format_power_label(status: Dictionary) -> String:
	match status.state:
		"surplus":
			return "+%d" % status.net
		"deficit", "self_supplied", "national", "partial":
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
	# Sized as a fraction of the tile (world units) — like the shipment/logistics
	# overlay labels — so it scales with camera zoom. Larger coefficient = bigger.
	return maxi(POWER_LABEL_FONT_SIZE, roundi(minf(_tile_size().x, _tile_size().y) * 0.18))

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
			return _classify_power_draw(net, tile_id)
		else:
			return {"state": "balanced", "net": 0}
	elif has_cables:
		return {"state": "cables_unused"}
	else:
		return {"state": "none"}

# A consuming (deficit) tile draws its shortfall from its cable network, then the national grid.
# Classify by the per-network self-supply settled this turn: the tile's draw was fully covered by
# its own cable network's generation (amber) or it imported from the national grid (red).
func _classify_power_draw(net: int, tile_id: String) -> Dictionary:
	if Power.is_self_supplied(tile_id):
		return {"state": "self_supplied", "net": net}
	return {"state": "national", "net": net}
