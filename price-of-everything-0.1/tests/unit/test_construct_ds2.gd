extends "res://tests/test_base.gd"
## The construct panel in DS2, the construction lot: behaviour, not looks. One width in every stage; the build
## order's figures and its refusal are ConstructionRules.quote()'s; the handles the tutorial and the tests look
## up are there; the source knob sets this build's source.

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
	_check(key is Button and key.get_script() == preload("res://scripts/ds2/cream_key.gd"), "build order: BuildConfirmButton is a plain cream key")
	_check(key != null and key.get("title_ink") != preload("res://scripts/ds2/cream_key.gd").RED_INK, "build order: Build prints navy with the money to build")
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
	_check(key != null and key.get("title_ink") == preload("res://scripts/ds2/cream_key.gd").RED_INK, "build order: Build prints red without the money")
	# Pressed while refused, it builds nothing and the money glows.
	var view_before := int(panel.get("_view"))
	(key as Button).pressed.emit()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(str(panel.get("last_flagged")) == "funds" and int(panel.get("_view")) == view_before,
		"build order: a refused press makes the money glow and builds nothing")
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


func _test_construct_ds2_catalogue() -> void:
	var saved := MatchState.money
	MatchState.money = 50000.0
	var panel := _panel()
	panel.call("open_browser")
	await get_tree().process_frame
	var card: Node = panel.find_child("BuildingCard_%s" % FURNACE, true, false)
	_check(card != null and card is Button, "catalogue: the Furnace's board is BuildingCard_b_002")
	var price_led: Node = card.find_child("Led", true, false) if card != null else null
	var price := float(Rules.quote(FURNACE, "", "", {}, {"source": str(panel.call("_current_material_source")), "buy_land": false}).total)
	_check(price_led != null and str(price_led.call("figure")).strip_edges() == str(MoneyFigure.screen(price, 2).figure),
		"catalogue: a board's price is quote()'s (%s)" % str(price))
	_check(panel.find_child("CataloguePlate", true, false) != null and panel.find_child("Filter_metallurgy", true, false) != null,
		"catalogue: the control plate carries the category keys")
	# Open the Furnace: its board across the width, its recipes hung as tags.
	(card as Button).pressed.emit()
	await get_tree().process_frame
	var tag: Node = panel.find_child("RecipeRow_%s" % PIG_IRON, true, false)
	_check(tag != null and tag is Button, "catalogue: the opened board hangs RecipeRow_r_005")
	var wide: Control = panel.find_child("BuildingCard_%s" % FURNACE, true, false)
	_check(wide != null and is_equal_approx(wide.custom_minimum_size.x, float(panel.get("CONTENT_W"))), "catalogue: the opened board spans the width")
	# A tag pressed opens its build order.
	(tag as Button).pressed.emit()
	await get_tree().process_frame
	_check(int(panel.get("_view")) == 1 and str((panel.get("_selected_recipe") as Dictionary).get("recipe_id", "")) == PIG_IRON,
		"catalogue: a tag opens its build order")
	# A category key filters; again clears it.
	panel.call("open_browser")
	panel.call("_pick_category", "power")
	await get_tree().process_frame
	_check((panel.get("_active_filters") as Dictionary).has("power") and panel.find_child("BuildingCard_%s" % FURNACE, true, false) == null,
		"catalogue: Power shows the power buildings alone")
	var key: Node = panel.find_child("Filter_power", true, false)
	_check(key != null and bool(key.get("latched")), "catalogue: the Power key stays down")
	panel.call("_pick_category", "power")
	await get_tree().process_frame
	_check((panel.get("_active_filters") as Dictionary).is_empty(), "catalogue: the key again shows every building")
	# The goods filter is shown and clears.
	panel.call("open_for_output_good", "g_004")
	await get_tree().process_frame
	var clear: Button = panel.find_child("ClearGoodsFilter", true, false)
	_check(clear != null and panel.find_child("GoodsFilter", true, false) != null, "catalogue: the goods filter is shown")
	if clear != null:
		clear.pressed.emit()
		await get_tree().process_frame
	_check(str(panel.get("_output_good_filter")) == "", "catalogue: Show all clears the goods filter")
	# The settings key on the crane opens the settings, and again comes back.
	var gear: BaseButton = panel.find_child("SettingsKey", true, false)
	_check(gear != null, "catalogue: the settings key is on the crane")
	if gear != null:
		gear.pressed.emit()
		await get_tree().process_frame
		_check(int(panel.get("_view")) == 2, "catalogue: the settings key opens the settings")
		gear.pressed.emit()
		await get_tree().process_frame
		_check(int(panel.get("_view")) == 0, "catalogue: pressed again, it comes back")
	MatchState.money = saved
	panel.queue_free()


func _test_construct_ds2_land_glows() -> void:
	var saved_money := MatchState.money
	var saved_auto := MatchState.construct_auto_buy_land
	MatchState.money = 50000.0
	MatchState.set_construct_auto_buy_land(false)
	# Stoneshore: a land tile the player owns no land on at the start.
	var tile := "tile_4_9"
	var panel := _panel()
	panel.show()
	_order(panel, tile)
	await get_tree().process_frame
	var blocks: Array = (panel.call("quote") as Dictionary).get("blocks", [])
	var land_blocked := not blocks.is_empty() and str((blocks[0] as Dictionary).key) in ["land_short", "cannot_buy_land", "full"]
	_check(land_blocked, "build order: with auto buy off and no land, the land blocks (%s)" % tile)
	if land_blocked:
		(panel.find_child("BuildConfirmButton", true, false) as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_check(str(panel.get("last_flagged")) == "land", "build order: a refused press makes the land glow")
		var buy: Button = panel.find_child("RequirementAction_land", true, false)
		_check(buy != null, "build order: the land row offers Buy land")
		if buy != null:
			buy.pressed.emit()
			await get_tree().process_frame
			var after: Array = (panel.call("quote") as Dictionary).get("blocks", [])
			_check(after.is_empty() and bool(panel.get("_buy_land_wanted")), "build order: Buy land lifts the land's block")
	MatchState.set_construct_auto_buy_land(saved_auto)
	MatchState.money = saved_money
	panel.queue_free()


func _test_construct_ds2_infrastructure() -> void:
	var saved := MatchState.money
	MatchState.money = 50000.0
	var panel := _panel()
	panel.show()
	panel.call("open_browser")
	panel.call("_on_infrastructure_selected", "b_006")
	await get_tree().process_frame
	_check(panel.find_child("PurposeSign", true, false) != null and panel.find_child("RecipeSign", true, false) == null,
		"infrastructure: Cables' sign says what it is for, no recipe")
	_check(panel.find_child("LevelsTable", true, false) != null and panel.find_child("ProgrammeBoard", true, false) == null,
		"infrastructure: its levels stand in place of the outlook")
	_check(panel.find_child("ConstructionMaterialsSection", true, false) != null, "infrastructure: Cables' materials are in the yard")
	_check(panel.find_child("LandLot", true, false) == null, "infrastructure: no land lot")
	var total: Node = panel.find_child("V3Total", true, false)
	var q: Dictionary = panel.call("quote")
	_check(total != null and _led_figure(total) == str(MoneyFigure.screen(float(q.total), 2).figure).strip_edges(), "infrastructure: Total is quote()'s")
	_check(str(panel.call("_v3_confirm_block_reason")) == "", "infrastructure: Build is open with the money")
	var rows: Array = preload("res://scripts/construct_ds2/build_order.gd").level_rows("roads")
	_check(rows.size() == 3 and (rows[1] as Array).size() == 4 and not str(rows[2]).contains("–"), "infrastructure: three rows of three levels, no dashes")
	panel.call("open_browser")
	panel.call("_on_infrastructure_selected", "b_005")
	await get_tree().process_frame
	_check(panel.find_child("ConstructionMaterialsSection", true, false) == null, "infrastructure: Roads take no materials, no yard")
	MatchState.money = saved
	panel.queue_free()


func _test_construct_ds2_card_states() -> void:
	var CAT := preload("res://scripts/construct_ds2/catalogue.gd")
	_check(CAT.price_colour(100.0, 200.0) == DS.PALETTE["TEXT"] and CAT.price_colour(100.0, 199.0) == DS.PALETTE["DANGER"],
		"card: white from twice the price in cash, red below")
	var saved := MatchState.money
	var panel := _panel()
	panel.call("open_browser")
	MatchState.money = 1000.0
	panel.call("_render")
	await get_tree().process_frame
	var cables: Control = panel.find_child("BuildingCard_b_006", true, false)
	var led: Node = cables.find_child("Led", true, false) if cables != null else null
	_check(led != null and led.get("colour") == DS.PALETTE["TEXT"], "card: Cables at £75 reads white with £1,000")
	var is_grey := func(c: Control) -> bool: return c != null and c.material is ShaderMaterial and (c.material as ShaderMaterial).shader == CAT.GREY_SHADER
	_check(cables != null and not is_grey.call(cables), "card: an affordable card is not grey")
	var dear: Control = panel.find_child("BuildingCard_b_009", true, false)
	_check(is_grey.call(dear) and dear.tooltip_text != "", "card: one you can't pay for is grey (the lamp keeps off it), the reason on its hover")
	MatchState.money = saved
	panel.queue_free()


## The verdict's turns: the materials' delivery beside the build, from the quote, so a cheap slow source shows its
## wait. With no site there is nothing to deliver yet.
func _test_construct_ds2_delivery_drum() -> void:
	var saved_money := MatchState.money
	var saved_source := MatchState.pending_build_material_source
	MatchState.money = 50000.0
	var panel := _panel()
	panel.show()
	_order(panel, "")
	await get_tree().process_frame
	_check(panel.find_child("DeliveryDrum", true, false) == null and panel.find_child("BuildDrum", true, false) != null,
		"turns: with no site only the build is counted")
	_order(panel, "tile_4_9")
	await get_tree().process_frame
	for source: String in ["middleman", "market"]:
		panel.call("pick_material_source", source)
		await get_tree().process_frame
		var q: Dictionary = panel.call("quote")
		var deliver: Control = panel.find_child("DeliveryDrum", true, false)
		var build: Control = panel.find_child("BuildDrum", true, false)
		_check(deliver != null and int(deliver.get("value")) == int(q.materials_turns)
			and build != null and int(build.get("value")) == int(q.build_turns),
			"turns (%s): deliver %d + build %d, the quote's" % [source, int(q.materials_turns), int(q.build_turns)])
		var words := deliver.tooltip_text if deliver != null else ""
		var expect := "Global market" if str((q.source as Dictionary).buys_via) == "market" else "Logistics Intermediary"
		_check(bool((q.materials_quote as Dictionary).get("satisfied", false)) or words.begins_with(expect),
			"turns (%s): the delivery's hover names where the materials come from (%s)" % [source, words])
	_check(panel.find_child("MaterialsArrive", true, false) == null, "turns: the drum replaces the line under the verdict")
	MatchState.pending_build_material_source = saved_source
	MatchState.money = saved_money
	panel.queue_free()


func _test_global_trade_license_threshold() -> void:
	var d: Dictionary = ResearchState.get_unlock_def(ResearchState.GLOBAL_TRADE_LICENSE_TITLE)
	_check(str(d.get("action", "")) == "Profit" and int(d.get("qty", 0)) == 75 and str(d.get("unit", "")) == "3 turns",
		"licence: the Import/Export License asks for £75 profit a turn, 3 turns in a row (got %s %s %s)" % [
			str(d.get("action", "")), str(d.get("qty", "")), str(d.get("unit", ""))])
	_check(ResearchState.unlock_condition_text(ResearchState.GLOBAL_TRADE_LICENSE_TITLE) == "Make £75 profit a turn for 3 turns in a row",
		"licence: its condition reads as the three turns")
	# The streak: two good turns (a start's free opening stock) then a thin one do not carry it; three in a row do.
	var saved: Array = (ResearchState.get("_recent_profits") as Array).duplicate()
	ResearchState.set("_recent_profits", [115.0, 118.0, 32.0])
	_check(not bool(ResearchState.call("_live_condition_met", d)), "licence: 115, 118 then 32 is not three turns at £75")
	ResearchState.set("_recent_profits", [32.0, 80.0, 90.0])
	_check(not bool(ResearchState.call("_live_condition_met", d)), "licence: two turns at £75 are not enough")
	ResearchState.set("_recent_profits", [32.0, 80.0, 90.0, 75.0])
	_check(bool(ResearchState.call("_live_condition_met", d)), "licence: three turns in a row at £75 or more unlock it")
	ResearchState.set("_recent_profits", saved)
	var exported: Dictionary = ResearchState.export_fields()
	_check(exported.has("recent_profits") and exported.has("recent_profits_last_turn"), "licence: the profit history is saved")


func _test_micro_silica_glass_bonus() -> void:
	var glass := 0.0
	for m: Dictionary in Modifiers.UNLOCK_MODIFIERS.get("research_inorg_003", []):
		if str(m.get("id", "")) == "rn_micro_silica_glass":
			glass = float(m.get("pct", 0.0))
	_check(is_equal_approx(glass, 10.0), "Micro Silica Synthesis adds 10%% glass (got %.0f%%)" % glass)
	_check(str(ResearchState.get_unlock_def("Micro Silica Synthesis").get("description", "")).contains("Glass output by 10%"),
		"its description says 10%")
