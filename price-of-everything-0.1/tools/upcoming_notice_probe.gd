extends Node
const Forecast := preload("res://scripts/cash_commitments.gd")
const Paths := preload("res://scripts/app_paths.gd")
func _enter_tree() -> void:
	Paths._base = "/tmp/cnc-upcoming-notice-probe"
	RunMetrics.enabled = false
func _ready() -> void:
	var rows: Array = []
	var failures := 0
	for start in ["metal_magnate", "glass_merchant"]:
		SaveLoad.prepare_new_game("res://data/starts/" + start + ".json", {"ruleset": {"start_id":start,"difficulty":"normal","speed_turns":100,"policy_timeline":"demo_itch","victory_set":"demo_itch","tutorial_enabled":false}})
		var world: Node = load("res://scenes/main.tscn").instantiate()
		add_child(world)
		for frame in range(160): await get_tree().process_frame
		TurnManager.fast_mode = true
		DecisionState.auto_resolve = true
		for child in world.get_children():
			if child.has_method("_on_begin") and child.get_script() != null and str(child.get_script().resource_path).contains("intro"):
				child._on_begin()
		for turn in range(12):
			var data := Forecast.snapshot()
			var alert := Forecast.attention_costs(data,Forecast.last_comparison)
			if not is_zero_approx(float(alert.total)) or alert != Forecast.next_turn_costs(data):
				failures += 1
			rows.append({"start":start,"turn":TurnManager.current_turn,"alert":alert,"subtotal":Forecast.next_turn_costs(data),"forecast":data,"previous":Forecast.last_comparison.duplicate(true)})
			print("[NoticeProbe] ",start," turn=",TurnManager.current_turn," alert=",JSON.stringify(alert)," subtotal=",JSON.stringify(Forecast.next_turn_costs(data)))
			TurnManager.commit_turn()
			while TurnManager.is_resolving: await get_tree().process_frame
		world.queue_free()
		for frame in range(8): await get_tree().process_frame
	var f := FileAccess.open("/tmp/cnc-upcoming-notice-after.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(rows,"\t"))
	print("[NoticeProbe] failures=", failures)
	get_tree().quit(1 if failures > 0 else 0)
