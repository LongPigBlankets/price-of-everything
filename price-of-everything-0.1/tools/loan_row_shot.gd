extends Node
## Dev tool: the building-detail economics rows with a CARRIED TAB open, so the loan line can
## be read. Seats the tab directly (a CFO and five turns of carry is a long way to walk for a
## screenshot) and shoots the panel in both states: still carrying, then repaying.
##   /tmp/poe_loan_row_carrying.png, /tmp/poe_loan_row_repaying.png
## Windowed: <godot> --path . res://tools/loan_row_shot.tscn --quit-after 40000

func _ready() -> void:
	SaveLoad.prepare_new_game("res://data/starts/metal_magnate.json", {"ruleset": {
		"start_id": "metal_magnate", "difficulty": "normal", "speed_turns": 100,
		"policy_timeline": "demo_itch", "victory_set": "demo_itch",
		"tutorial_enabled": false, "survey_all_tiles": true, "company_colour": "diesel_red",
	}})
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(240)
	for node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var script_res: Variant = node.get_script()
		if script_res != null and str((script_res as Script).resource_path).ends_with("_intro.gd"):
			node.queue_free()
	await _settle(10)
	var panel: Node = game.find_child("BuildingDetailPanelV2", true, false)
	if panel == null:
		push_error("[LOAN] no detail panel"); get_tree().quit(1); return
	# A player building to hang the tab on.
	var target: Dictionary = {}
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(b) and str(b.get("recipe_id", "")) != "":
			target = b
			break
	if target.is_empty():
		push_error("[LOAN] no player building"); get_tree().quit(1); return
	var iid := str(target.get("instance_id", ""))
	for state in [
		{"name": "carrying", "tab": {"turns_left": 3, "accrued": 240.0, "mode": "slices", "slices_left": 0}},
		{"name": "repaying", "tab": {"turns_left": 0, "accrued": 90.0, "mode": "slices", "slices_left": 9}},
	]:
		MatchState.building_tabs[iid] = (state["tab"] as Dictionary).duplicate()
		var quoted: Dictionary = MatchState.building_tab_repayment(iid)
		print("[LOAN] %s: per_turn=%.2f turns_left=%d starts_in=%d" % [
			str(state["name"]), float(quoted.per_turn), int(quoted.turns_left), int(quoted.starts_in)])
		panel.call("show_building", target)
		await _settle(45)
		await RenderingServer.frame_post_draw
		var path := "/tmp/poe_loan_row_%s.png" % str(state["name"])
		get_viewport().get_texture().get_image().save_png(path)
		print("[LOAN] saved ", path)
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
