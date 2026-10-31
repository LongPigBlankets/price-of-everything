extends "res://tests/test_base.gd"
## Phase 6 of docs/pacing-labour-mining-licensing-spec.md: research licensing (scripts/research_licensing.gd). Each
## test names the acceptance criteria (AC…) it checks.

const FEATURE := "licensing"
const TAGS := {
	"_test_save_round_trip": ["licensing", "save"],
	"_test_research_ds2_licence_drawer": ["licensing", "ui"],
	"_test_old_canvas_strip": ["licensing", "ui"],
	"_test_money_rows_agree": ["licensing", "economy"],
}

const Licensing := preload("res://scripts/research_licensing.gd")
const LicenceDialog := preload("res://scripts/licence_dialog.gd")
const ResearchPanel := preload("res://scripts/research_panel.gd")
const MoneyPanel := preload("res://scripts/money_panel.gd")

const GROUPS := {
	"coal_power": ["Pulverized Coal Boilers", "Steam Turbine Upgrades", "Reheat Turbine Cycles"],
	"iron_steel": ["Basic Blast Furnaces", "Continuous Casting", "Pulverised Carbon Injection"],
	"refining": ["Fractional Distillation", "Catalytic Cracking", "Specialised Petrochemical Pipelines"],
	"extraction": ["Bench Blasting Expansion", "Bulk Haulage Fleets", "Continuous Surface Miners"],
	"solar": ["Utility Solar Arrays", "Utility-Scale Inverters", "Dual-Axis Tracking Farms"],
	"wind": ["Onshore Wind Control", "Taller Turbine Towers", "Tall-Tower Wind Capture"],
	"factory": ["High-Volume Press Lines", "Multi-Shift Production", "Near-Net-Shape Stamping"],
	"eaf": ["Foamy Slag Practice", "Eccentric Bottom Tapping", "Ultra-High-Power Arcs"],
}
const STEEL := "g_006"


func _fresh() -> void:
	Modifiers.reset()
	MatchState.reset()
	LoanState.import_state({})
	TurnManager.MAX_TURNS = TurnManager.DEFAULT_MAX_TURNS
	TurnManager.current_turn = 1
	MatchState.money = 5000.0
	MatchState.one_off_charges.clear()


func _ready_up(title: String) -> void:
	ResearchState.licence_ready_titles[title] = int(TurnManager.current_turn)


func _summary(goods: float) -> Dictionary:
	return {"goods_sales_revenue": goods, "power_sales_revenue": 0.0, "money_in": goods, "money_out": 0.0}


## AC30.1: the eight groups, their members in table order, and the two new members' effects.
func _test_groups() -> void:
	_fresh()
	for g: String in GROUPS:
		_check(Licensing.members(g) == GROUPS[g], "AC30.1 the %s group is %s, by rank (%s)" % [g, GROUPS[g], Licensing.members(g)])
	_check(Licensing.groups().size() == 8, "AC30.1 eight licence groups")
	var stamping: Array = Licensing._modifiers_of("Near-Net-Shape Stamping")
	_check(stamping.size() == 1 and str(stamping[0].domain) == "recipe_input" and is_equal_approx(float(stamping[0].pct), -10.0)
		and str((stamping[0].target_match as Dictionary).get("building_id", "")) == "b_007",
		"AC30.1 Near-Net-Shape Stamping: factory inputs 10% lower")
	var tapping: Array = Licensing._modifiers_of("Eccentric Bottom Tapping")
	_check(tapping.size() == 2 and tapping.all(_is_arc_furnace_cut), "AC30.1 Eccentric Bottom Tapping: arc furnace labour and maintenance 10% lower")


func _is_arc_furnace_cut(m: Dictionary) -> bool:
	return is_equal_approx(float(m.pct), -10.0) and str(m.domain) in ["labour_headcount", "maintenance"] \
		and str((m.target_match as Dictionary).get("building_id", "")) == "b_008"


## AC30.2: no member needs another member of its group; prerequisites outside the group stay.
func _test_group_prereqs() -> void:
	for g: String in GROUPS:
		var ids: Array = (GROUPS[g] as Array).map(func(t: String) -> String: return ResearchState.research_node_id_for_title(t))
		for t: String in GROUPS[g]:
			var inside: Array = (ResearchState.get_unlock_def(t).get("prereqs", []) as Array).filter(func(p: String) -> bool: return ids.has(p))
			_check(inside.is_empty(), "AC30.2 %s needs no member of its own group" % t)
	_check((ResearchState.get_unlock_def("Pulverised Carbon Injection").get("prereqs", []) as Array).has("research_metal_003"),
		"AC30.2 Pulverised Carbon Injection still needs HIsarna, outside its group")
	_check(not ResearchState.is_node_available("Pulverised Carbon Injection"), "AC30.2 the rank gate stays")


## AC30.3: a met condition makes a member ready, not granted; it stays ready and opens no rank.
func _test_condition_makes_ready() -> void:
	_fresh()
	ResearchState.record_unlock_progress("Produce", "steel", 250)
	ResearchState._check_unlock_conditions()
	_check(ResearchState.is_licence_ready("Continuous Casting") and not ResearchState.is_unlocked("Continuous Casting"),
		"AC30.3 Continuous Casting's condition met: ready to license, not granted")
	_check(not Modifiers.has("rn_continuous_casting"), "AC30.3 its effect does not apply while it is only ready")
	_check(not ResearchState.is_tier_available("Metallurgy", "II"), "AC30.3 a ready member does not open the next rank")
	ResearchState._unlock_progress.clear()
	ResearchState._check_unlock_conditions()
	_check(ResearchState.is_licence_ready("Continuous Casting"), "AC30.3 once ready it stays ready")
	_check(ResearchState.is_unlocked("research_metal_002") == false, "AC30.3 and is still not granted")
	_fresh()


## AC30.4: eras of the 300-turn campaign, and the same rule for a shorter charter.
func _test_eras() -> void:
	_fresh()
	var cases := {1: 1, 90: 1, 91: 2, 180: 2, 181: 3, 300: 3}
	for t: int in cases:
		_check(MatchState.era_for_turn(t) == int(cases[t]), "AC30.4 turn %d is era %d" % [t, cases[t]])
	TurnManager.MAX_TURNS = 200
	_check(MatchState.era_for_turn(60) == 1 and MatchState.era_for_turn(61) == 2 and MatchState.era_for_turn(121) == 3,
		"AC30.4 a 200-turn charter keeps the shares")
	_check(EconomyConfig.era_spans(300) == [[0, 90], [90, 180], [180, 300]] and EconomyConfig.DEMO_ERA_SPAN == 300,
		"AC30.4 the era rule lives in EconomyConfig")
	_check(not FileAccess.get_file_as_string("res://scripts/new_game_ds2/new_game_ds2.gd").contains("const ERA_SHARES"),
		"AC30.4 the New Game screen reads EconomyConfig's shares")
	_fresh()


## AC31.1, AC31.4: the price by order (in-house counting), by era, the cash in hand; licensing grants the node.
func _test_licence_prices() -> void:
	_fresh()
	_ready_up("Continuous Casting")
	_check(str(Licensing.terms_for("Continuous Casting").kind) == "flat" and is_equal_approx(float(Licensing.terms_for("Continuous Casting").price), 200.0),
		"AC31.1 the first licence in a group costs £200 in era 1")
	MatchState.money = 150.0
	_check(Licensing.license_refusal("Continuous Casting") == "Needs £200 in hand" and not Licensing.license("Continuous Casting"),
		"AC31.1 the first licence needs its price in hand")
	MatchState.money = 5000.0
	_check(Licensing.license("Continuous Casting"), "AC31.1 licensed")
	var charge: Dictionary = MatchState.one_off_charges.back() if not MatchState.one_off_charges.is_empty() else {}
	_check(is_equal_approx(float(charge.get("amount", 0.0)), 200.0) and str(charge.get("label", "")) == "Licence: Continuous Casting"
		and int(charge.get("turn", 0)) == 1, "AC31.1 charged in this turn's costs as a one-off charge")
	_check(ResearchState.is_unlocked("Continuous Casting") and Modifiers.has("rn_continuous_casting"),
		"AC31.4 licensing grants the node and its effect applies")
	_ready_up("Basic Blast Furnaces")
	var second := Licensing.terms_for("Basic Blast Furnaces")
	_check(str(second.kind) == "royalty" and is_equal_approx(float(second.rate), 0.02) and int(second.turns) == 30,
		"AC31.1 the second costs 2% of revenue for 30 turns")
	Licensing.license("Basic Blast Furnaces")
	_ready_up("Pulverised Carbon Injection")
	_check(is_equal_approx(float(Licensing.terms_for("Pulverised Carbon Injection").rate), 0.08), "AC31.1 the third costs 8%")
	# In-house counts: a free pick, then the next one licensed is a royalty.
	_check(ResearchState.develop_free("Reheat Turbine Cycles"), "AC32.1 a free pick develops a group member")
	_ready_up("Steam Turbine Upgrades")
	_check(str(Licensing.terms_for("Steam Turbine Upgrades").kind) == "royalty", "AC31.1 an in-house process counts as held")
	TurnManager.current_turn = 91
	_check(is_equal_approx(Licensing.first_price(91), 500.0) and is_equal_approx(Licensing.first_price(181), 2000.0)
		and is_equal_approx(Licensing.first_price(90), 200.0), "AC31.1 £500 in era 2, £2,000 in era 3")
	_fresh()


## AC31.2: no money path skips a condition.
func _test_unready_cannot_license() -> void:
	_fresh()
	_check(not Licensing.license("Continuous Casting") and not ResearchState.is_unlocked("Continuous Casting")
		and Licensing.license_refusal("Continuous Casting") == "Its condition is not met yet",
		"AC31.2 a member whose condition is unmet cannot be licensed")
	_check(not Licensing.license("HIsarna"), "AC31.2 a node outside the groups cannot be licensed")
	_fresh()


## AC31.3: royalties on each turn's revenue, used or not, for 30 charges; then paid up and kept.
func _test_royalties() -> void:
	_fresh()
	_ready_up("Continuous Casting")
	Licensing.license("Continuous Casting")
	_ready_up("Basic Blast Furnaces")
	Licensing.license("Basic Blast Furnaces")
	var money := MatchState.money
	var s := _summary(1000.0)
	Licensing.settle_turn(s)
	_check(is_equal_approx(float(s.royalties_paid), 20.0) and is_equal_approx(MatchState.money, money - 20.0)
		and is_equal_approx(float(s.money_out), 20.0), "AC31.3 2% of a £1,000 turn: £20, before tax, with no building using it")
	var charges := 1
	for t in range(2, 40):
		TurnManager.current_turn = t
		var st := _summary(1000.0)
		Licensing.settle_turn(st)
		if float(st.royalties_paid) > 0.0:
			charges += 1
	_check(charges == 30, "AC31.3 charged for 30 turns (%d)" % charges)
	_check(ResearchState.is_unlocked("Basic Blast Furnaces") and Licensing.price_line("Basic Blast Furnaces") == "Licensed, paid up",
		"AC31.3 then paid up and kept for free")
	_fresh()


## AC32.1, AC32.2: free picks and other grants are in-house, with no fee and no royalty.
func _test_in_house() -> void:
	_fresh()
	_check(ResearchState.develop_free("Basic Blast Furnaces") and Licensing.is_in_house("Basic Blast Furnaces")
		and MatchState.one_off_charges.is_empty() and Licensing.royalty_rate_total(1) == 0.0,
		"AC32.1 a free pick: in-house, no fee, no royalty, no condition needed")
	ResearchState.grant_unlock("Steam Turbine Upgrades")
	_check(str(Licensing.licence_of("Steam Turbine Upgrades").get("kind", "")) == "inhouse",
		"AC32.2 a member granted by a mission reward or a cheat is in-house")
	ResearchState.grant_unlock("HIsarna")
	_check(Licensing.is_in_house("HIsarna") and not ResearchState.licences.has("HIsarna"), "AC32.2 a node outside the groups is in-house")
	_fresh()


## AC32.3, AC35.1: the licensing state round-trips; free picks spent stay spent; an old save's members are in-house.
func _test_save_round_trip() -> void:
	_fresh()
	ResearchState.develop_free("Basic Blast Furnaces")
	_ready_up("Continuous Casting")
	Licensing.license("Continuous Casting")
	_ready_up("Steam Turbine Upgrades")
	ResearchState.grant_unlock("HIsarna")
	Licensing.license_out("HIsarna")
	var saved := ResearchState.export_fields()
	ResearchState.reset()
	ResearchState.import_fields(saved)
	_check(ResearchState.free_picks.has("Basic Blast Furnaces") and str(Licensing.licence_of("Continuous Casting").kind) == "royalty"
		and ResearchState.is_licence_ready("Steam Turbine Upgrades") and ResearchState.licensed_out.has("HIsarna")
		and ResearchState.licence_sales_due.size() == 1 and int(ResearchState.unlock_turns.get("HIsarna", -1)) == 1,
		"AC35.1 licences, sales, ready members, development turns, sales due and free picks round-trip")
	var panel: Control = ResearchPanel.new()
	panel._recount_free_unlocks()
	_check(int(panel.get("_free_unlocks")) == ResearchPanel.free_unlocks_earned_by(1, TurnManager.MAX_TURNS) - 1,
		"AC32.3 a spent free pick is not handed back after a load")
	panel.free()
	var old := {"unlocked_titles": {"Basic Blast Furnaces": true, "HIsarna": true}}
	ResearchState.import_fields(old)
	_check(str(Licensing.licence_of("Basic Blast Furnaces").get("kind", "")) == "inhouse" and Licensing.royalty_rate_total(1) == 0.0
		and ResearchState.unlock_turns.is_empty(), "AC35.1 an old save: unlocked members in-house, no royalty, development turns unknown")
	TurnManager.current_turn = 61
	_check(Licensing.patent_turns_left("HIsarna") == -1, "AC35.1 an unknown development turn counts as turn 0")
	var fields: Dictionary = (preload("res://scripts/save_validation.gd").FIELDS.match as Dictionary)
	_check(["licences", "licensed_out", "licence_ready", "unlock_turns", "free_picks"].all(func(k: String) -> bool: return (fields.dictionary as Array).has(k))
		and (fields.array as Array).has("licence_sales_due"), "AC35.1 every licensing field is registered in SaveValidation.FIELDS")
	_fresh()


## AC33.1: who may be licensed out.
func _test_licence_out_eligibility() -> void:
	_fresh()
	ResearchState.grant_unlock("HIsarna")
	_check(Licensing.license_out_refusal("HIsarna") == "" and Licensing.goods_touched("HIsarna").has(STEEL),
		"AC33.1 an in-house rank II process that touches steel can be licensed out")
	ResearchState.grant_unlock("Basic Blast Furnaces")
	_check(Licensing.license_out_refusal("Basic Blast Furnaces") == "Rank I processes are not licensed out", "AC33.1 never rank I")
	_ready_up("Ultra-High-Power Arcs")
	Licensing.license("Ultra-High-Power Arcs")
	_check(Licensing.license_out_refusal("Ultra-High-Power Arcs") == "Licensed in, so it cannot be sublicensed", "AC33.1 never one licensed in")
	var not_process := ""
	for d: Dictionary in ResearchState.unlock_defs():
		if str(d.get("rank", "")) == "II" and ResearchState.is_research_visible(d) and not Licensing.is_process(str(d.title)):
			not_process = str(d.title)
			break
	ResearchState.grant_unlock(not_process)
	_check(not_process != "" and Licensing.license_out_refusal(not_process) == "Not a process: a practice or service, not a production line",
		"AC33.1 a node that is not a production process is not licensed out (%s)" % not_process)
	_check(not Licensing.is_process("Shift Handover Documentation") and not Licensing.is_process("Union Liaison Offices"),
		"AC33.1 a company-wide practice (an effect on every building) is not a process")
	_check(Licensing.is_process("Flue Heat Recovery") and Licensing.goods_touched("Flue Heat Recovery").is_empty(),
		"AC33.1 a power plant process is a process that touches no market good")
	_check(Licensing.license_out("HIsarna") and Licensing.license_out_refusal("HIsarna") == "Already licensed out", "AC33.1 each process once")
	ResearchState.grant_unlock("Electric Arc Refining")
	TurnManager.current_turn = 60
	_check(Licensing.license_out_refusal("Electric Arc Refining") == "" and Licensing.patent_turns_left("Electric Arc Refining") == 1,
		"AC33.1 developed on turn 1, still open on turn 60, its last")
	TurnManager.current_turn = 61
	_check(Licensing.license_out_refusal("Electric Arc Refining") == "The patent window has closed", "AC33.1 closed once 60 turns have passed")
	_fresh()


## AC33.2: the price, its rate steps, the floor and the cap.
func _test_licence_out_price() -> void:
	_fresh()
	LoanState.import_state({"revenue_history": [300.0, 400.0, 500.0, 600.0, 700.0]})
	ResearchState.grant_unlock("HIsarna")
	_check(is_equal_approx(Licensing.license_out_rate("HIsarna"), 0.10) and is_equal_approx(Licensing.license_out_price("HIsarna"), 50.0),
		"AC33.2 alone: 10% of £500 is £50")
	ResearchState.grant_unlock("Electric Arc Refining")
	var rank_three := ""
	for d: Dictionary in ResearchState.unlock_defs():
		if str(d.get("rank", "")) == "III" and ResearchState.is_research_visible(d) and Licensing.is_process(str(d.title)) \
				and str(d.get("licence_group", "")) == "":
			rank_three = str(d.title)
			break
	ResearchState.grant_unlock(rank_three)
	_check(is_equal_approx(Licensing.license_out_rate("HIsarna"), 0.175) and is_equal_approx(Licensing.license_out_price("HIsarna"), 87.5),
		"AC33.2 with one other rank II and one rank III: 17.5% of £500 is £87.50")
	LoanState.import_state({"revenue_history": [100.0, 100.0, 100.0, 100.0, 100.0]})
	_check(is_equal_approx(Licensing.license_out_price("HIsarna"), 50.0), "AC33.2 never under £50")
	for d: Dictionary in ResearchState.unlock_defs():
		if str(d.get("rank", "")) in ["II", "III"] and str(d.get("licence_group", "")) == "":
			ResearchState.grant_unlock(str(d.title))
	_check(is_equal_approx(Licensing.license_out_rate("HIsarna"), 0.5), "AC33.2 the rate is capped at 50%")
	Licensing.license_out("Electric Arc Refining")
	var before := Licensing._unsold_processes("HIsarna")
	_check(not ResearchState.licensed_out.is_empty() and before.x >= 1, "AC33.2 a sold process no longer counts toward the rate")
	_fresh()


## AC33.3, AC33.4: the sale is paid in the costs phase; each sale lowers the goods it touches by 2% for 30 turns.
func _test_licence_out_sale() -> void:
	_fresh()
	LoanState.import_state({"revenue_history": [800.0, 800.0, 800.0, 800.0, 800.0]})
	ResearchState.grant_unlock("HIsarna")
	ResearchState.grant_unlock("Electric Arc Refining")
	var price := Licensing.license_out_price("HIsarna")
	Licensing.license_out("HIsarna")
	var money := MatchState.money
	var s := _summary(0.0)
	Licensing.settle_turn(s)
	_check(is_equal_approx(float(s.licence_income), price) and is_equal_approx(MatchState.money, money + price)
		and is_equal_approx(float(s.money_in), price) and ResearchState.licence_sales_due.is_empty(),
		"AC33.3 the sale is paid in the turn's costs phase as revenue before tax")
	_check(is_equal_approx(float(Modifiers.resolve_pct("market_price", STEEL).net), -2.0), "AC33.4 steel sells 2% lower")
	Licensing.license_out("Electric Arc Refining")
	_check(is_equal_approx(float(Modifiers.resolve_pct("market_price", STEEL).net), -4.0), "AC33.4 two sales touching steel: 4% lower")
	var base := MarketState.get_price(STEEL)
	_check(MarketState.get_sale_price(STEEL) <= base * 0.96 + 0.001, "AC33.4 the market's sale price carries it")
	TurnManager.current_turn = 31
	Modifiers._prune_expired()
	_check(is_equal_approx(float(Modifiers.resolve_pct("market_price", STEEL).net), 0.0), "AC33.4 after 30 turns the price is back")
	_fresh()


## AC34.2: the payback a dialog quotes, from the company's running buildings.
func _test_estimate_return() -> void:
	_fresh()
	BuildingState.tile_land_owned["tile_9_9"] = 2000
	var iid: String = BuildingState.add_building("b_002", "r_003", "tile_9_9", MatchState.LOCAL_PLAYER, "")
	Production.lifetime_pl_by_building[iid] = {"value": 1000.0, "inputs": 400.0, "power": 100.0, "labour": 200.0, "maint": 100.0, "turns": 10}
	_check(is_equal_approx(Licensing.estimate_return("Basic Blast Furnaces"), 5.0), "AC34.2 +10% furnace throughput on a £50 a turn margin returns £5")
	_check(is_equal_approx(Licensing.estimate_return("Specialised Petrochemical Pipelines"), 0.0), "AC34.2 a refinery process returns nothing with no refinery")
	Production.lifetime_pl_by_building.erase(iid)
	_fresh()


## AC34.1–AC34.3, AC34.5: the Licence groups drawer, the cards' states and lines, and both dialogs.
func _test_research_ds2_licence_drawer() -> void:
	_fresh()
	var was := UiPrefs.use_research_ds2
	UiPrefs.set_use_research_ds2(true)
	var panel: Control = ResearchPanel.new()
	panel.size = Vector2(1900, 914)
	add_child(panel)
	panel.show()
	await get_tree().process_frame
	var view: Control = panel.call("ds2_view")
	_ready_up("Continuous Casting")
	ResearchState.develop_free("Basic Blast Furnaces")
	ResearchState.grant_unlock("HIsarna")
	view.call("open_drawer", "Licence groups")
	await get_tree().process_frame
	var rows: Array = (view.call("board") as Control).get("_rows")
	_check(rows.size() == 8 and rows.all(func(r: Dictionary) -> bool: return str(r.get("group", "")) != "" and (r.cards as Array).size() == 3),
		"AC34.1 the Licence groups drawer pins a row of three drawings per group")
	var ready: Control = view.call("card_for", "Continuous Casting")
	_check(ready != null and str(ready.get("state")) == "ready" and bool(ready.get("actionable"))
		and str(ready.get("licence")) == "License for 2% of revenue, 30 turns", "AC34.1 a ready drawing: lamp, price line, a click opens the dialog")
	var developed: Control = view.call("card_for", "Basic Blast Furnaces")
	_check(developed != null and str(developed.get("state")) == "developed" and str(developed.get("licence")) == "Developed in house",
		"AC34.5 a free pick is stamped DEVELOPED")
	var open: Control = view.call("card_for", "Pulverised Carbon Injection")
	_check(open != null and str(open.get("licence")).begins_with("License for") and not bool(open.get("actionable")),
		"AC34.1 a member not yet ready shows its price, and a click does nothing")
	var dialog := LicenceDialog.open(view, "Continuous Casting")
	_check(dialog != null and dialog.dialog_text.contains("Costs 2% of company revenue a turn for 30 turns") and dialog.dialog_text.contains("Returns")
		and dialog.ok_button_text == "License", "AC34.2 the licence dialog shows the price and the payback")
	if dialog != null:
		dialog.confirmed.emit()
	await get_tree().process_frame
	_check(ResearchState.is_unlocked("Continuous Casting") and str(Licensing.licence_of("Continuous Casting").kind) == "royalty",
		"AC34.2 License buys it")
	var out := LicenceDialog.content("HIsarna", "out")
	_check(str(out.get("text", "")).contains("Sold once for £50") and str(out.text).contains("Steel") and str(out.text).contains("Patent window: 60 turns left"),
		"AC34.3 the licence-out dialog: price, market consequence, patent window")
	view.call("open_drawer", "Metallurgy")
	await get_tree().process_frame
	var licensed: Control = view.call("card_for", "Continuous Casting")
	_check(licensed != null and str(licensed.get("state")) == "licensed", "AC34.5 a licensed drawing is stamped LICENSED")
	var his: Control = view.call("card_for", "HIsarna")
	_check(his != null and str(his.get("licence")).begins_with("License out for £50") and bool(his.get("actionable")),
		"AC34.3 an in-house process shows its licence-out price")
	panel.queue_free()
	UiPrefs.set_use_research_ds2(was)
	_fresh()
	await get_tree().process_frame


## AC34.4: the old canvas prints the same lines and opens the same dialog.
func _test_old_canvas_strip() -> void:
	_fresh()
	_ready_up("Continuous Casting")
	_check(ResearchPanel.licence_strip_text("Continuous Casting") == "Ready. License for £200", "AC34.4 the old canvas: a ready member's strip")
	ResearchState.grant_unlock("HIsarna")
	_check(ResearchPanel.licence_strip_text("HIsarna").begins_with("License out for"), "AC34.4 the old canvas: an in-house process's strip")
	_check(FileAccess.get_file_as_string("res://scripts/research_panel.gd").contains("LicenceDialog.open(self"),
		"AC34.4 the old canvas opens the shared licence dialog")
	_fresh()


## AC34.6: royalties and licence sales are on both money readouts, and they agree.
func _test_money_rows_agree() -> void:
	var s := {"goods_sales_revenue": 1000.0, "money_in": 1080.0, "money_out": 20.0, "royalties_paid": 20.0, "licence_income": 80.0}
	_check(is_equal_approx(MoneyPanel.net_cash_of(s), Production.cash_change_of(s)) and is_equal_approx(MoneyPanel.net_cash_of(s), 1060.0),
		"AC34.6 the money panel and the cash change agree with royalties and licence sales")
	var src := FileAccess.get_file_as_string("res://scripts/top_bar.gd")
	_check(src.contains("[\"Royalties\", float(s.get(\"royalties_paid\"") and src.contains("[\"Licence sales\", float(s.get(\"licence_income\""),
		"AC34.6 the top bar's money sheet lists both")


## AC35.2: telemetry carries royalties and licence income each turn, and licences by kind for the run.
func _test_telemetry() -> void:
	_fresh()
	ResearchState.develop_free("Basic Blast Furnaces")
	var row: Dictionary = TelemetryState._build_row({"goods_sales_revenue": 500.0, "money_in": 560.0, "money_out": 10.0,
		"royalties_paid": 10.0, "licence_income": 60.0})
	_check(is_equal_approx(float((row.costs as Dictionary).get("royalties", 0.0)), 10.0) and is_equal_approx(float(row.licence_income), 60.0),
		"AC35.2 the turn row carries royalties and licence income")
	_check(int((TelemetryState.get("_run_licences") as Dictionary).get("inhouse", 0)) == 1 and TelemetryState.SCHEMA_VERSION == 9,
		"AC35.2 licences by kind for the run, schema 9")
	var sent: Dictionary = TelemetryState.balancing_payload({"run_id": "l9", "turns": [row], "end": {"licences": {"inhouse": 1}}})
	_check(is_equal_approx(float((sent.turns[0] as Dictionary).royalties), 10.0) and is_equal_approx(float((sent.turns[0] as Dictionary).licence_income), 60.0)
		and int(((sent.end as Dictionary).licences as Dictionary).inhouse) == 1, "AC35.2 the payload transmits royalties, licence income and licences by kind")
	_fresh()
