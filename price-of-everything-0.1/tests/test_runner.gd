extends Node
## Minimal, zero-dependency headless test runner for price-of-everything.
##
## Fast path (one command; exit code 0 = all pass, 1 = a failure):
##     <godot> --headless res://tests/test_runner.tscn
## Or from the editor: open tests/test_runner.tscn and press F6 (Run Current Scene);
## results print in the Output panel.
##
## It runs as a SCENE (not --script) so the project autoloads — Catalog,
## Stockpile, Production, DS, etc. — are available. The goal is to catch, without
## manual clicking: script parse errors, broken @onready paths, main.tscn
## corruption, and data-loading regressions.

var _passed := 0
var _failed := 0

func _ready() -> void:
	print("\n==== price-of-everything tests ====")
	_test_scripts_parse()
	_test_widgets_instantiate()
	_test_recipe_row_instantiates()
	await _test_stockpile_legend_label_visible()
	_test_scene_loads()
	await _test_main_scene_instantiates()
	_test_catalog_loaded()
	_test_recipe_requirements()
	_test_menu_icons()
	_test_ports()
	print("==== %d passed, %d failed ====\n" % [_passed, _failed])
	get_tree().quit(1 if _failed > 0 else 0)

func _check(ok: bool, name: String) -> void:
	if ok:
		_passed += 1
		print("  PASS  ", name)
	else:
		_failed += 1
		printerr("  FAIL  ", name)

func _test_ports() -> void:
	var ports := Catalog.all_ports()
	_check(ports.size() == 4, "Catalog loads 4 ports")
	var fields_ok := true
	for p in ports:
		if str(p.get("tile_id", "")) == "" or str(p.get("name", "")) == "":
			fields_ok = false
	_check(fields_ok, "every port has a tile_id and name")
	_check(Catalog.tile_hex_distance("tile_5_10", "tile_5_10") == 0, "tile_hex_distance(self) == 0")
	_check(Catalog.nearest_port_tile("tile_3_8") == "tile_5_10", "nearest_port_tile picks the closest port")
	_check(Catalog.tile_label("tile_12_2") == "[Miney McMineface] - (12_2)", "tile_label uses nickname")
	_check(Catalog.tile_label("tile_5_10") == "[Stoneshore Docks] - (5_10)", "tile_label falls back to city_name")

# Smoke: every script we touch must still parse. load() returns null on a parse
# error — this is the check that catches the bug class we couldn't verify by hand.
func _test_scripts_parse() -> void:
	for path in [
		"res://scripts/stockpile_view.gd",
		"res://scripts/infra_grid.gd",
		"res://scripts/tile_info_panel.gd",
		"res://scripts/building_detail_panel.gd",
		"res://scripts/world_map.gd",
		"res://scripts/map_overlay.gd",
		"res://scripts/ds.gd",
		"res://scripts/search_overlay.gd",
		"res://scripts/good_icons.gd",
		"res://scripts/catalog.gd",
		"res://scripts/construct_panel.gd",
		"res://scripts/building_row.gd",
		"res://scripts/recipe_row.gd",
	]:
		_check(load(path) != null, "parses: " + path)

# Smoke: the extracted widgets instantiate and build their UI.
func _test_widgets_instantiate() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	sv.set_tile("")
	_check(sv.get_child_count() > 0, "StockpileView builds its UI")
	sv.queue_free()

	var ig: Node = load("res://scripts/infra_grid.gd").new()
	add_child(ig)
	ig.set_slots([{
		"cell_size": Vector2(80, 80), "icon": null, "state": "add",
		"internal_name": "roads", "button_tooltip": "Add Roads",
		"display_label": "Roads", "label_tooltip": "", "max_label_lines": 2,
	}])
	_check(ig.get_child_count() == 1, "InfraGrid renders one slot")
	ig.queue_free()

# Regression: recipe_row.tscn must instantiate + setup (catches script/root type
# mismatches — recipe rows are only built on expand, so the main-scene test misses them).
func _test_recipe_row_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/recipe_row.tscn")
	var ok: bool = packed != null
	if ok:
		var row: Node = packed.instantiate()
		add_child(row)
		row.call("setup", {
			"recipe_id": "r_001", "display_name": "Test Recipe",
			"output_good_id": "g_001", "output_name": "coal", "output_qty": 10,
			"inputs": [], "energy_req": 4,
		}, "b_001")
		ok = row.get_node_or_null("Row/OutputIcon") != null
		row.queue_free()
	_check(ok, "recipe_row instantiates + setup runs")

# Regression: a stockpile legend row's label must render with non-zero width
# (a fixed-width label was removed; with ellipsis trimming the label collapsed
# to zero and only the colour swatch showed).
func _test_stockpile_legend_label_visible() -> void:
	var sv: Node = load("res://scripts/stockpile_view.gd").new()
	add_child(sv)
	var row: Control = sv.call("_make_row", "Coal", "g_001")
	add_child(row)
	await get_tree().process_frame
	var label := row.get_child(0) as Label
	var ok: bool = label != null and label.text == "Coal" and label.size.x > 0.0
	_check(ok, "stockpile legend label renders with width (not collapsed)")
	row.queue_free()
	sv.queue_free()
	await get_tree().process_frame

# Smoke: the big scene still loads as a resource (catches main.tscn corruption).
func _test_scene_loads() -> void:
	_check(load("res://scenes/main.tscn") != null, "main.tscn loads")

# Instantiate the whole main scene and confirm the tile panel's @onready node
# paths still resolve. This is the net for layout/scene restructuring (Slice D):
# a broken node path leaves an @onready var null, which this catches.
func _test_main_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	if packed == null:
		_check(false, "main.tscn instantiates")
		return
	var inst: Node = packed.instantiate()
	add_child(inst)
	await get_tree().process_frame
	var panel: Node = inst.find_child("TileInfoPanel", true, false)
	var tl = panel.get("title_label") if panel != null else null
	# Guards the theme-cascade fix: DS variations must actually resolve on panels.
	_check(tl != null and tl.get_theme_font_size("font_size") == DS.FS["H1"],
		"DS theme reaches the tile panel (title uses the DS Title font)")
	var ok: bool = panel != null \
		and panel.get("tile_size_chart") != null \
		and panel.get("title_label") != null \
		and panel.get("infrastructure_table") != null \
		and panel.get("close_button") != null \
		and panel.get("tile_image_banner") != null \
		and panel.get("_banner_summary_content") != null \
		and panel.get("_right_scroll_content") != null
	_check(ok, "main.tscn instantiates; TileInfoPanel @onready nodes resolve")
	inst.queue_free()
	await get_tree().process_frame

# Logic: the data CSVs load into the Catalog as expected.
func _test_catalog_loaded() -> void:
	_check(Catalog.all_goods().size() == 15, "Catalog has 15 goods")
	var _all_classed := true
	for g in Catalog.all_goods():
		if str(g.get("transport_class", "")) == "":
			_all_classed = false
	_check(_all_classed, "every loaded good has a transport_class")
	_check(Catalog.all_recipes().size() >= 18, "Catalog promotes a healthy recipe set (>=18)")
	_check(Catalog.all_buildings().size() == 37, "Catalog has 37 buildings")

# Logic: recipe requirements parse correctly (guards the build-mode path that
# silently broke earlier in the merge).
func _test_recipe_requirements() -> void:
	var recipe: Dictionary = Catalog.get_recipe("r_001")
	var reqs: Array = recipe.get("requirements", [])
	var ok: bool = reqs.size() == 1 \
		and reqs[0].get("type", "") == "deposit" \
		and reqs[0].get("value", "") == "coal"
	_check(ok, "r_001 (Coal Mining) requires deposit:coal")
	_check(recipe.get("recipe_type", "") == "extraction", "r_001 recipe_type is extraction")
	# Promotion gate: every active recipe's inputs + outputs resolve to real goods.
	var no_phantom := true
	for r in Catalog.all_recipes():
		for o in r.get("outputs", []):
			if o.get("good_id", "") == "":
				no_phantom = false
		for inp in r.get("inputs", []):
			if inp.get("good_id", "") == "":
				no_phantom = false
	_check(no_phantom, "promotion gate: active recipes only reference real goods")
	var mine_b: Dictionary = Catalog.get_building("b_001")
	_check("extraction" in mine_b.get("building_type", []), "Mine building_type contains extraction")

# Logic: the regenerated bottom-menu icons import and load as textures.
func _test_menu_icons() -> void:
	var all_ok := true
	for key in ["resources", "buildings", "map_overlays", "markets", "politics", "construct", "tech"]:
		var path := "res://assets/icons/ui_icons/200/%s.png" % key
		if not (ResourceLoader.exists(path) and load(path) is Texture2D):
			all_ok = false
	_check(all_ok, "bottom-menu icons (200px tier) import and load")
