extends Node2D
## Integration probe for the "auto-buy land when building" construct setting. Drives
## world_map._space_check_for_build directly — the single choke point every build goes
## through — and checks the four cases that matter:
##   1. setting OFF + not enough land        -> refused, nothing bought
##   2. setting ON  + not enough land        -> buys EXACTLY the shortfall, allowed
##   3. setting ON  + already enough land    -> allowed, buys nothing
##   4. setting ON  + not enough money       -> refused, nothing bought
##   <godot> --headless --path . res://tools/autobuy_land_probe.tscn --quit-after 1200

const TILE := "tile_5_7"      # rural, no player buildings in a bare boot
const BUILDING := "b_002"     # furnace

var _wm
var _fails := 0

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(120)

	var need := int(round(maxf(0.0, float(Catalog.get_building(BUILDING).get("tile_size_used", 1)))))
	print("[AUTOBUY] %s needs %d land" % [BUILDING, need])

	# 1) OFF + no land -> refused, no purchase.
	_reset(0, 100000.0, false)
	var r1: Dictionary = _wm._space_check_for_build(TILE, BUILDING)
	_check("OFF: build refused", str(r1.get("allowed", true)), "false")
	_check("OFF: no land bought", str(MatchState.get_tile_land_owned(TILE)), "0")

	# 2) ON + no land -> buys just enough (rounded up to whole patches), allowed.
	_reset(0, 100000.0, true)
	var cash_before := MatchState.money
	var r2: Dictionary = _wm._space_check_for_build(TILE, BUILDING)
	var owned2 := MatchState.get_tile_land_owned(TILE)
	var patches := int(ceil(float(need) / float(MatchState.LAND_PATCH_SIZE)))
	_check("ON: build allowed", str(r2.get("allowed", false)), "true")
	_check("ON: bought exactly %d patch(es)" % patches, str(owned2), str(patches * MatchState.LAND_PATCH_SIZE))
	_check("ON: covers the requirement", "yes" if owned2 >= need else "no", "yes")
	_check("ON: no over-buy (< one extra patch)", "yes" if owned2 - need < MatchState.LAND_PATCH_SIZE else "no", "yes")
	print("[AUTOBUY] spent £%.2f on land" % (cash_before - MatchState.money))

	# 3) ON + already enough -> allowed, buys nothing more.
	_reset(need + MatchState.LAND_PATCH_SIZE, 100000.0, true)
	var owned_before := MatchState.get_tile_land_owned(TILE)
	var cash3 := MatchState.money
	var r3: Dictionary = _wm._space_check_for_build(TILE, BUILDING)
	_check("ON+enough: build allowed", str(r3.get("allowed", false)), "true")
	_check("ON+enough: land unchanged", str(MatchState.get_tile_land_owned(TILE)), str(owned_before))
	_check("ON+enough: no money spent", "%.2f" % (cash3 - MatchState.money), "0.00")

	# 4) ON + broke -> refused, nothing bought.
	_reset(0, 0.0, true)
	var r4: Dictionary = _wm._space_check_for_build(TILE, BUILDING)
	_check("ON+broke: build refused", str(r4.get("allowed", true)), "false")
	_check("ON+broke: no land bought", str(MatchState.get_tile_land_owned(TILE)), "0")

	print("==== AUTOBUY PROBE %s ====" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)


func _reset(land: int, money: float, auto_buy: bool) -> void:
	MatchState.tile_land_owned[TILE] = land
	MatchState.money = money
	MatchState.set_construct_auto_buy_land(auto_buy)


func _check(what: String, got: String, want: String) -> void:
	if got == want:
		print("  PASS  %s = %s" % [what, got])
	else:
		_fails += 1
		print("  FAIL  %s = '%s' (expected '%s')" % [what, got, want])


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
