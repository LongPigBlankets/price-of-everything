extends Node
## Dev tool: render the real game, seed VictoryState with a believable mid-game
## board, open the fullscreen Victory panel, and save a PNG for visual checking.
## The top-bar victory widget shows above the panel in the same shot. Needs a
## window (NOT --headless):
##   <godot> --path . res://tools/victory_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	_seed_victory()

	var panel: Control = game.get_node("UILayer/HUD/HUDContent/VictoryPanel")
	PanelStack.push(panel)
	panel.show()
	await _settle(16)

	_shot("/tmp/poe_victory.png")
	get_tree().quit(0)

func _seed_victory() -> void:
	var v := VictoryState
	# Live-driving state (so each track's live progress reads sensibly).
	v.autarkic_streak = 22                                   # live 0.60
	v.logistics_total = 240
	v.logistics_efficient = 150                              # eff 0.625 -> live 0.50
	v.richest_window = [7400.0, 7400.0, 7400.0, 7400.0, 7400.0]  # live 0.54
	v._last_summary = {"power_supply": 1200, "power_supply_by_type": {"b_024": {"count": 3, "amount": 492.0}}}  # share 0.41 -> live 0.2625
	v._resolve_green_ids()
	# Widest: 140 distinct player non-infra tiles -> live 0.55.
	for i in range(140):
		MatchState.buildings["vshot%d" % i] = {"building_id": "b_001", "tile_id": "vshot_t%d" % i, "owner": "player_1"}
	# Best-ever per track. Richest's best (0.62) sits above its live (0.54) to show
	# the ghosted "locked-in but now lower" meter segment.
	v.track_best = {"autarkic": 0.60, "logistics": 0.50, "richest": 0.62, "widest": 0.55, "greenest": 0.2625}
	# Streak alive this turn (nothing bought) + a lifetime buy history for the tally.
	v.purchases_this_turn = {"input": 0, "building": 0, "upgrade": 0, "other": 0}
	v.purchases_lifetime = {"input": 37, "building": 6, "upgrade": 4, "other": 11}
	# Trend history (gentle climb -> upward ▲ badges).
	v.score_history = []
	for k in range(10):
		v.score_history.append({
			"turn": 200 + k, "total": 3700 + k * 20, "base": 1350,
			"tracks": {
				"autarkic": 0.50 + k * 0.010, "logistics": 0.46 + k * 0.004,
				"richest": 0.55 + k * 0.007, "widest": 0.50 + k * 0.005,
				"greenest": 0.20 + k * 0.006,
			},
		})
	TurnManager.current_turn = 210                          # base 1350; total ~3882 / 4000 (in progress)
	v._scored_turn = 210                                    # the turn the seeded score reflects
	v._emit_refresh()

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
