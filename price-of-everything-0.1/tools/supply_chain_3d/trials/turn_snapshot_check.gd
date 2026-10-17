extends "res://tools/supply_chain_3d/capture.gd"
## Does the bundled continent snapshot still match after ordinary turns?
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/trials/turn_snapshot_check.tscn -- \
##   --continent-review --no-telemetry --turns=N --bake-cache-directory=<new dir>
func _open_supply_view(view: Control) -> void:
	var turns := 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--turns="): turns = int(arg.trim_prefix("--turns="))
	for i in turns:
		TurnManager.commit_turn()
		await get_tree().process_frame
		while TurnManager.is_resolving: await get_tree().process_frame
		for f in 10: await get_tree().process_frame
	print("[TURN CHECK] turn=", TurnManager.current_turn, " buildings=", BuildingState.buildings.size())
	await super._open_supply_view(view)

func _continent_review(board: Control, _home: Dictionary) -> void:
	var started := Time.get_ticks_msec()
	while board.background_status == "loading" or board.background_active():
		await get_tree().process_frame
		if Time.get_ticks_msec() - started > 120000: break
	print("[TURN CHECK] background=", board.background_status, " after_ms=", Time.get_ticks_msec() - started)
