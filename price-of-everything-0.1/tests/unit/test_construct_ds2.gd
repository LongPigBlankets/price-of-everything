extends "res://tests/test_base.gd"
## The construct panel in DS2, the construction lot (UiPrefs.use_construct_ds2, `toggle construct ds2`):
## behaviour, not looks. Off by default; one width in every stage; the build order's figures and its refusal
## are ConstructionRules.quote()'s; the handles the tutorial and the tests look up are there; the source knob
## sets this build's source.

const FEATURE := "construction"

const Rules := preload("res://scripts/construction_rules.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const PANEL := "res://scripts/construct_ds2/construct_ds2.gd"
const FURNACE := "b_002"
const PIG_IRON := "r_005"


func _panel() -> Control:
	var panel: Control = load(PANEL).new()
	add_child(panel)
	return panel


func _order(panel: Control, tile: String) -> void:
	if tile != "":
		panel.call("open_for_tile", tile, {"id": tile})
	else:
		panel.call("open_browser")
	panel.set("_selected_building", Catalog.get_building(FURNACE))
	panel.set("_selected_recipe", Catalog.get_recipe(PIG_IRON))
	panel.set("_view", 1)
	panel.call("_render")


func _led_figure(host: Node) -> String:
	var led: Node = host.find_child("Led", true, false)
	return str(led.call("figure")) if led != null else ""


func _test_construct_ds2_off_by_default() -> void:
	_check(not UiPrefs.use_construct_ds2, "construct ds2: off by default")
	UiPrefs.set_use_construct_ds2(true)
	_check(UiPrefs.use_construct_ds2, "construct ds2: the cheat's setter turns it on")
	UiPrefs.set_use_construct_ds2(false)


func _test_construct_ds2_one_width() -> void:
	var panel := _panel()
	var w := float(panel.get("WIDTH"))
	panel.call("open_browser")
	await get_tree().process_frame
	_check(is_equal_approx(panel.custom_minimum_size.x, w) and is_equal_approx(panel.offset_right - panel.offset_left, w),
		"construct ds2: the catalogue is the one width (%.0f)" % w)
	_order(panel, "")
	await get_tree().process_frame
	_check(is_equal_approx(panel.offset_right - panel.offset_left, w), "construct ds2: the build order is the same width")
	panel.call("_on_settings_pressed")
	await get_tree().process_frame
	_check(is_equal_approx(panel.offset_right - panel.offset_left, w), "construct ds2: the settings are the same width")
	panel.queue_free()


func _test_construct_ds2_build_order_reads_quote() -> void:
	var saved := MatchState.money
	MatchState.money = 50000.0
	var panel := _panel()
	panel.show()
	_order(panel, "")
	await get_tree().process_frame
	var q: Dictionary = panel.call("quote")
	_check(not bool(q.get("site_known", true)), "build order: with no site the quote knows none")
	var total: Node = panel.find_child("V3Total", true, false)
	_check(total != null and _led_figure(total) == str(MoneyFigure.screen(float(q.total), 2).figure).strip_edges(),
		"build order: Total is quote().total (%s)" % str(q.total))
	var key: Control = panel.find_child("BuildConfirmButton", true, false)
	_check(key != null and key.get_script() == preload("res://scripts/ds2/guard_key.gd"), "build order: BuildConfirmButton is the guarded key")
	_check(key != null and not bool(key.get("disabled")), "build order: Build is open with the money to build")
	_check(panel.find_child("ConstructionMaterialsSection", true, false) != null, "build order: the materials section keeps its name")
	_check(panel.find_child("RequirementGrid", true, false) != null, "build order: the requirements are on the pillar")
	_check(panel.find_child("SiteBoard", true, false) != null and panel.find_child("RecipeSign", true, false) != null,
		"build order: the site board carries the recipe sign")
	# Without the money, Build is refused with the quote's own words.
	MatchState.money = 1.0
	panel.call("_render")
	await get_tree().process_frame
	q = panel.call("quote")
	var reason := str(panel.call("_v3_confirm_block_reason"))
	_check(reason != "" and reason == str(((q.blocks as Array)[0] as Dictionary).text), "build order: the refusal is quote()'s first block")
	key = panel.find_child("BuildConfirmButton", true, false)
	_check(key != null and bool(key.get("disabled")), "build order: Build is refused without the money")
	MatchState.money = saved
	panel.queue_free()


func _test_construct_ds2_source_knob() -> void:
	var saved := MatchState.pending_build_material_source
	var panel := _panel()
	panel.show()
	_order(panel, "")
	await get_tree().process_frame
	var knob: Node = panel.find_child("MaterialsKnob", true, false)
	_check(knob != null, "build order: the Materials from knob is in the yard")
	panel.call("pick_material_source", "market")
	await get_tree().process_frame
	_check(MatchState.pending_build_material_source == "market", "build order: the knob sets this build's source")
	_check(str((panel.call("quote") as Dictionary).source.get("asked", "")) == "market" or str(panel.call("_current_material_source")) == "market",
		"build order: the quote follows the knob")
	MatchState.pending_build_material_source = saved
	panel.queue_free()


func _test_construct_ds2_bottom_menu_picks() -> void:
	var menu: Object = load("res://scripts/bottom_menu.gd").new()
	UiPrefs.set_use_construct_ds2(true)
	_check(str(menu.call("_construct_v2_script")) == PANEL, "bottom menu: the flag on builds the construction lot")
	UiPrefs.set_use_construct_ds2(false)
	_check(str(menu.call("_construct_v2_script")) == "res://scripts/construct_panel_v2.gd", "bottom menu: the flag off builds today's panel")
	menu.free()
