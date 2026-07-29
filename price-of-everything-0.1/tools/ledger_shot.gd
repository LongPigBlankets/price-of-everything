extends Node
## Dev tool: render the real game, seed a few player buildings with varied levels + run/cost
## data, open the Building Ledger, and save a PNG for visual verification. Needs a window
## (NOT --headless):
##   <godot> --path . res://tools/ledger_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Seed a variety of player building types (the player starts with none) at mixed levels:
	# [building_id, recipe_id, level]. Includes power producers (coal_power, solar_farm) and
	# consumers (factory, eaf, electrolyser, chem) to exercise the building icons + power column.
	var specs := [
		["b_003", "r_004", 1, "tile_10_2"],  # power_plant — producer
		["b_024", "r_146", 2, "tile_11_2"],  # solar_farm  — producer
		["b_001", "r_001", 1, "tile_12_2"],  # mine
		["b_007", "r_008", 2, "tile_13_2"],  # industrial_factory — consumer
		["b_008", "r_030", 1, "tile_10_3"],  # eaf — consumer
		["b_020", "r_039", 3, "tile_11_3"],  # electrolyser — consumer (L3 → MAX)
		["b_012", "r_012", 2, "tile_12_3"],  # chem_plant — consumer
		["b_014", "r_090", 1, "tile_13_3"],  # farm
	]
	var ids: Array = []
	for s in specs:
		var id: String = MatchState.add_building(str(s[0]), str(s[1]), str(s[3]), MatchState.LOCAL_PLAYER, "")
		MatchState.buildings[id]["level"] = int(s[2])
		ids.append(id)

	# Run one production pass (mines without a deposit will starve — that's fine), then
	# seed run/cost variety so the Status/Power/Cost RAG dots show a mix of colours.
	TurnManager.fast_mode = true
	TurnManager.phase_started.emit(TurnManager.Phase.PROCESS)
	await _settle(3)
	var coal: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	for i in ids.size():
		var id: String = ids[i]
		if i % 3 == 0:
			Production.last_turn_run[id] = true
			CostSolver.last_result["per_building"][id] = {"output_good_id": coal, "unit_cost": 8.0 + float(i) * 6.0}
		elif i % 3 == 1:
			Production.missing_by_building[id] = [{"good_id": coal, "qty": 5}]
	TurnManager.turn_resolution_completed.emit()
	await _settle(6)

	var hud: Control = game.get_node("UILayer/HUD")
	var ledger: Control = (load("res://scenes/building_ledger_panel.tscn") as PackedScene).instantiate()
	hud.add_child(ledger)
	await _settle(12)

	_shot("/tmp/poe_ledger.png")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
