extends Node
## Dev probe: render the Encyclopedia's "Advisors and the council" body and print it, so the
## numbers can be checked against the live model rather than against the format string.
##   <godot> --path . res://tools/advisor_entry_probe.tscn --quit-after 500

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	for _i in 30:
		await get_tree().process_frame
	var overlay := _find(game, "search_overlay.gd")
	if overlay == null:
		print("PROBE: no SearchOverlay found")
		get_tree().quit(1)
		return
	var ids: Array = []
	for e in overlay.MECHANIC_ENTRIES:
		ids.append(str((e as Dictionary).get("id", "")))
	print("MECHANIC IDS: %s" % str(ids))
	var which := OS.get_environment("ENTRY")
	if which == "":
		which = "advisors"
	var body: String = overlay._mechanic_body(which)
	print("--- %s BODY (%d chars) ---" % [which.to_upper(), body.length()])
	print(body)
	print("--- seats=%d  per-advisor now=%.2f  payroll@rev1000=%.2f ---" % [
		MatchState.max_advisor_slots, MatchState.advisor_cost_per_advisor(0.0),
		MatchState.advisor_payroll_per_turn(1000.0)])
	get_tree().quit(0)

func _find(n: Node, script_tail: String) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with(script_tail):
		return n
	for c in n.get_children():
		var f := _find(c, script_tail)
		if f != null:
			return f
	return null
