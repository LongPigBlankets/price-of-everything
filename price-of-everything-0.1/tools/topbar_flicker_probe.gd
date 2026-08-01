extends Node
## Dev tool: prove the top bar's victory/council strips no longer double up mid-frame.
##
## queue_free() is DEFERRED. The old refresh freed children and added replacements in the same
## frame, so for one frame the HBox laid out BOTH sets — twice the widgets in the same width,
## which is the flicker. Calling the refresh repeatedly WITHOUT yielding reproduces exactly that
## condition: if children are only queue_free'd, the count climbs with every call.
##   <godot> --path . res://tools/topbar_flicker_probe.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(36)
	# Seat an advisor so the council strip has something to rebuild.
	MatchState.permanent_advisor_ids = ["vera", "tom"]
	MatchState.advisor_seats = {"cfo": "vera", "coo": "tom"}
	var bar := _find(game, "top_bar.gd")
	if bar == null:
		push_error("top bar not found"); get_tree().quit(1); return
	for pair in [["_victory_meters", "_refresh_victory"], ["_council_stack", "_refresh_council"]]:
		var box: Node = bar.get(str(pair[0]))
		if box == null:
			print("%s: not built" % str(pair[0])); continue
		bar.call(str(pair[1]))
		var base: int = box.get_child_count()
		# Five refreshes inside ONE frame — no awaits, so nothing deferred has run yet.
		for _i in range(5):
			bar.call(str(pair[1]))
		var after: int = box.get_child_count()
		print("%-16s %d child(ren) after 1 refresh, %d after 5 in the same frame -> %s"
			% [str(pair[0]), base, after, ("STABLE" if after == base else "DOUBLING (flicker)")])
	get_tree().quit(0)

func _find(n: Node, script_file: String) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with(script_file):
		return n
	for c in n.get_children():
		var f := _find(c, script_file)
		if f != null:
			return f
	return null

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
