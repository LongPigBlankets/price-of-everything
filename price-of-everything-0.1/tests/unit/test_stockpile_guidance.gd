extends "res://tests/test_base.gd"
const FEATURE := "stockpile_guidance"
const Guidance := preload("res://scripts/stockpile_guidance.gd")

func _test_redirection_forecast_and_dynamic_surplus() -> void:
	MatchState.reset()
	Stockpile.import_state({})
	Modifiers.import_state({})
	var producer := BuildingState.add_building("b_002", "r_007", "tile_5_10", "player_1", "guidance_smelter", false)
	BuildingState.add_building("b_002", "r_026", "tile_5_10", "player_1", "guidance_pipe", false)
	MatchState.set_output_stockpile_destination(producer, "tile_5_10", "g_005")
	var forecast := Guidance.estimate("tile_5_10", "g_005")
	_check(int(forecast.incoming) > 0 and int(forecast.consumed) == 13, "redirect forecast includes smelter output and pipe input")
	_check(int(forecast.growth) == int(forecast.incoming) - 13, "redirect forecast reports only net accumulation")
	MatchState.enable_auto_sell_good("tile_5_10", "g_005")
	_check(MatchState.should_auto_sell_good("tile_5_10", "g_005") and not MatchState.should_auto_sell_good("tile_5_10", "g_004"), "accepting copper surplus does not enable iron sales")
	BuildingState.add_building("b_002", "r_026", "tile_5_10", "player_1", "guidance_pipe_two", false)
	_check(int(Production.compute_sell_reserve_for_tile("tile_5_10").get("g_005", 0)) == 26, "new consumer automatically increases protected copper reserve")
	MatchState.set_output_stockpile_destination(producer, "tile_5_11", "g_005")
	MatchState.set_output_ship_quantity(producer, "g_005", 7)
	var allocation := Guidance.output_allocations(BuildingState.get_building(producer), "g_005", 32)
	_check(int(allocation.get("tile_5_11", 0)) == 7 and int(allocation.get("tile_5_10", 0)) == 25, "capped remote route retains the correct remainder at origin")
	TransportState.add_recurring_move("tile_5_11", "tile_5_12", {"g_005": 5})
	var remote := Guidance.estimate("tile_5_11", "g_005")
	_check(int(remote.growth) == 2, "forecast accounts for recurring onward shipments")

func _test_accumulation_notice_reserve_and_cooldown() -> void:
	MatchState.reset()
	Stockpile.import_state({})
	var monitor := Guidance.new()
	monitor.reset()
	MatchState.set_auto_sell_keep("tile_5_10", "g_005", 20)
	for turn in range(1, 5):
		Stockpile.add("tile_5_10", "g_005", 5)
		_check(monitor.sample(turn).is_empty(), "filling chosen buffer does not warn")
	var hits: Array = []
	for turn in range(5, 8):
		Stockpile.add("tile_5_10", "g_005", 5)
		hits = monitor.sample(turn)
	_check(hits.size() == 1 and float(hits[0].growth) == 5.0, "three consecutive surplus increases produce one accurate notice")
	_check(monitor.sample(7).is_empty(), "same resolved turn cannot generate duplicate notices")
	Stockpile.add("tile_5_10", "g_005", 5)
	_check(monitor.sample(8).is_empty(), "persistent accumulation respects cooldown")
	monitor.reset()
	TurnManager.current_turn = 1
	Guidance.retain_intentionally("tile_5_10", "g_005")
	for turn in range(1, 5):
		Stockpile.add("tile_5_10", "g_005", 5)
		_check(monitor.sample(turn).is_empty(), "explicit keep-stock choice suppresses immediate nagging")
	monitor.reset()
	MatchState.reset()
	Stockpile.import_state({})

func _test_releasing_buffer_without_stock_growth_does_not_warn() -> void:
	MatchState.reset()
	Stockpile.import_state({})
	var monitor := Guidance.new()
	monitor.reset()
	Stockpile.add("tile_5_10", "g_005", 100)
	for turn in range(1, 5):
		MatchState.set_auto_sell_keep("tile_5_10", "g_005", 80 - turn * 10)
		_check(monitor.sample(turn).is_empty(), "reducing reserve alone is not accumulating stock")
	monitor.reset()
	MatchState.reset()
	Stockpile.import_state({})
