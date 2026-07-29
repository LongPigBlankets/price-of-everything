extends Node
## What the tutorial ACTUALLY costs a player: prints every one-off cash outlay the
## tutorial script asks for, against the £2500 start, so the post-tutorial cash
## position can be checked against the per-turn burn.
##   <godot> --headless --path . res://tools/tutorial_cost_report.tscn --quit-after 6000

const MAIN_SCENE := "res://scenes/main.tscn"
const BuildingPrice := preload("res://scripts/building_price.gd")
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const TILE := "tile_5_9"

var _main: Node = null
var _started := false
var _frames := 0


func _ready() -> void:
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 6000:
		get_tree().quit(1)


func _run() -> void:
	print("=== TUTORIAL COST REPORT ===")
	print("start money            £%.0f" % MatchState.money)
	var total := 0.0

	# 1. The NPC window factory on tile_5_9
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) == TILE and str(inst.get("building_id", "")) == "b_007":
			var p := BuildingPrice.sale_price(inst)
			print("buy b_007 factory     £%d   (base %.1f, variation %.2f, near_port %s)" % [
				p, BuildingPrice.base_cost(inst), BuildingPrice.variation_multiplier(str(inst.get("instance_id", ""))),
				BuildingPrice.is_near_port(TILE)])
			total += float(p)

	# 2. Land the buy_land step demands
	var patch: int = MatchState.LAND_PATCH_SIZE
	var patch_cost: int = MatchState.LAND_PATCH_COST
	var shortfall: int = TutorialSteps._land_lesson_shortfall()
	var land_cost := float(shortfall) / float(patch) * float(patch_cost)
	print("buy land              £%.0f   (%d units, £%d per %d)" % [land_cost, shortfall, patch_cost, patch])
	total += land_cost

	# 3. Infrastructure the tutorial asks the player to lay on tile_5_9
	for infra in ["cables", "reinf_pipes"]:
		var bid := _infra_building(infra)
		var c := _infra_cost(bid)
		print("lay %-14s    £%.0f   (%s)" % [infra, c, bid])
		total += c

	# 4. Build kits bought "from market"
	for pair in [["b_002", "glass furnace"], ["b_002", "alu smelter (alt branch)"]]:
		var kit := _kit_cost(str(pair[0]))
		print("build kit %-11s £%.0f   (%s, market prices)" % [str(pair[0]), kit, str(pair[1])])
	total += _kit_cost("b_002")   # one branch only

	# 5. Retool fee for r_054
	print("retool to r_054       £%d" % _retool_fee())
	total += float(_retool_fee())

	print("--------------------------------------")
	print("TOTAL one-off outlay  £%.0f   -> cash left ~£%.0f before any turns run" % [
		total, MatchState.money - total])
	print("")
	print("Per-turn labour+maintenance floor (what you pay when STALLED, producing nothing):")
	for pair2 in [["b_007", "r_056"], ["b_002", "r_054"], ["b_002", "r_053"], ["b_002", "r_050"]]:
		var bid2 := str(pair2[0])
		var rid2 := str(pair2[1])
		print("   %s/%s  labour £%.2f + maint £%.2f = £%.2f/turn" % [
			bid2, rid2, _labour(bid2, rid2), _maint(bid2), _labour(bid2, rid2) + _maint(bid2)])
	print("   glass path total stalled burn = £%.2f/turn" % [
		_labour("b_007", "r_056") + _maint("b_007") + _labour("b_002", "r_054") + _maint("b_002")])
	print("   buy-all (factory only) stalled burn = £%.2f/turn" % [
		_labour("b_007", "r_056") + _maint("b_007")])
	print("")
	print("Cash needed each turn just to PLACE input orders (market prices, no stock):")
	for rid3 in ["r_056", "r_054", "r_053", "r_050"]:
		print("   %s inputs = £%.2f/turn" % [rid3, _input_bill(rid3)])
	get_tree().quit(0)


func _infra_building(internal: String) -> String:
	for b in Catalog.all_buildings():
		if str(b.get("internal_name", "")) == internal:
			return str(b.get("id", ""))
	return ""


func _infra_cost(bid: String) -> float:
	if bid == "":
		return 0.0
	return _kit_cost(bid)


func _kit_cost(bid: String) -> float:
	var total := 0.0
	for m in Catalog.get_building(bid).get("materials", []):
		var g: Dictionary = Catalog.get_good_by_internal_name(str(m.get("name", "")))
		var gid := str(g.get("id", ""))
		var price: float = MarketState.get_price(gid) if gid != "" else 0.0
		if price <= 0.0:
			price = float(g.get("base_price", 0.0))
		total += price * float(int(m.get("qty", 0)))
	return total


func _retool_fee() -> int:
	for k in ["RETOOL_FEE", "RECIPE_CHANGE_FEE", "RETROFIT_FEE"]:
		if MatchState.get(k) != null:
			return int(MatchState.get(k))
	return 25


func _labour(bid: String, rid: String) -> float:
	var rec: Dictionary = Catalog.get_recipe(rid)
	var bd: Dictionary = Catalog.get_building(bid)
	var u: float = float(rec.get("labour_unskilled_required", -1))
	var s: float = float(rec.get("labour_skilled_required", -1))
	var h: float = float(rec.get("labour_h_skilled_required", -1))
	if u < 0.0:
		u = float(bd.get("labour_unskilled_required", 0))
	if s < 0.0:
		s = float(bd.get("labour_skilled_required", 0))
	if h < 0.0:
		h = float(bd.get("labour_h_skilled_required", 0))
	return u * EconomyConfig.LABOUR_UNSKILLED_RATE + s * EconomyConfig.LABOUR_SKILLED_RATE \
		+ h * EconomyConfig.LABOUR_HIGH_SKILLED_RATE


func _maint(bid: String) -> float:
	return float(Catalog.get_building(bid).get("maintenance_cost", 0.0))


func _input_bill(rid: String) -> float:
	var total := 0.0
	for inp in Catalog.get_recipe(rid).get("inputs", []):
		var gid := str(inp.get("good_id", ""))
		total += MarketState.get_price(gid) * float(int(inp.get("qty", 0)))
	return total
