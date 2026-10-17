extends Node
## When does global revenue double? Replays the rankings table for a few match seeds and prints the first turn
## each doubling of LandPrice.base_revenue() lands. The player's row is held at `--player=N` a turn (default 0),
## so the turns are the rivals' clock; a real player's revenue brings them earlier.
##   <godot> --headless --path . res://tools/land_economy_probe.tscn -- [--player=N] [--seeds=1,2,3]

const LandPrice := preload("res://scripts/land_price.gd")

func _ready() -> void:
	var player := 0.0
	var seeds: Array = [1, 2, 3]
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--player="):
			player = float(arg.trim_prefix("--player="))
		elif arg.begins_with("--seeds="):
			seeds = Array(arg.trim_prefix("--seeds=").split(",")).map(func(s: String) -> int: return int(s))
	var g0 := LandPrice.base_revenue()
	for match_seed: int in seeds:
		var firsts := {}
		var history: Array[float] = []
		for turn in range(1, 301):
			history.append(player)
			var total := 0.0
			for row: Dictionary in CompanyRankings.standings_for(match_seed, turn, history):
				total += float(row.revenue)
			var level := LandPrice.doublings(total)
			for step in range(1, level + 1):
				if not firsts.has(step):
					firsts[step] = turn
		print("LAND_ECONOMY seed=%d player=%d first turns by doubling: %s" % [match_seed, int(player), str(firsts)])
	get_tree().quit()
