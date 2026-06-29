extends Node
## Dev tool: apply a start config through the real pipeline and report the resulting
## player-building count + money, so we can confirm the authored starts actually place
## their buildings without errors. Headless is fine:
##   <godot> --headless --path . res://tools/start_check.tscn --quit-after 600 -- <start_name>
## Defaults to checking every start in sequence if no name is given.

const STARTS := ["open_field", "glass_merchant", "coal_baron", "troubled_carmaker",
	"semiconductor_turnaround", "too_many_acquisitions", "ambitious_start"]

func _ready() -> void:
	var only := _arg_name()
	var names: Array = [only] if only != "" else STARTS
	for n in names:
		await _check(String(n))
	get_tree().quit(0)

func _check(name: String) -> void:
	var path := "res://data/starts/%s.json" % name
	SaveLoad.prepare_new_game(path)
	var snap: Dictionary = SaveLoad._pending_snapshot
	var want: int = ((snap.get("match", {}) as Dictionary).get("buildings", {}) as Dictionary).size()
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	await _settle(150)   # world builds progressively, then apply_pending runs
	var got := 0
	for iid in MatchState.buildings:
		if MatchState.is_player_owned(MatchState.buildings[iid]):
			got += 1
	var levels: Array = []
	for iid in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[iid]
		if MatchState.is_player_owned(b) and int(b.get("level", 1)) > 1:
			levels.append("%s L%d" % [str(b.get("building_id", "")), int(b.get("level", 1))])
	print("START %-26s want=%d placed=%d money=%s levels=%s" % [name, want, got, str(MatchState.money), str(levels)])
	main.queue_free()
	await _settle(5)

func _arg_name() -> String:
	for a in OS.get_cmdline_user_args():
		if not a.is_valid_int():
			return a
	return ""

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
