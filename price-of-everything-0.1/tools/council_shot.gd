extends Node
## Dev tool: render the real game, seat a small council with varied loyalty,
## open the People panel (Advisors tab — the role-first council view), and save
## PNGs of the roster and picker views plus the top-bar council loyalty surface.
## Needs a window (NOT --headless):
##   <godot> --path . res://tools/council_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# Seat two advisors with contrasting loyalty; leave seats open so filled,
	# empty, and (if capped) locked cards all render. Force-recruit first —
	# hire_advisor refuses ids outside recruited_advisor_ids.
	for id in ["vera", "gerald", "eleanor", "sloane", "marcus", "hitomi"]:
		if not MatchState.recruited_advisor_ids.has(id):
			MatchState.recruited_advisor_ids.append(id)
	print("hire vera: ", MatchState.hire_advisor("vera"))
	print("seat vera: ", MatchState.assign_advisor_to_seat("cfo", "vera"))
	MatchState.cheat_set_loyalty("vera", 6.0)
	print("hire gerald: ", MatchState.hire_advisor("gerald"))
	print("seat gerald: ", MatchState.assign_advisor_to_seat("coo", "gerald"))
	MatchState.cheat_set_loyalty("gerald", -4.5)
	await _settle(5)

	var hud: Control = game.get_node("UILayer/HUD")
	var people: Control = load("res://scripts/people_panel.gd").new()
	hud.add_child(people)
	people.custom_minimum_size = Vector2(980, 660)
	people.position = Vector2(180, 80)
	await _settle(15)
	_shot("/tmp/poe_council_roster.png")

	# Drive the advisors tab into the picker view for the second shot.
	var tab: Node = _find_council_tab(people)
	if tab != null:
		tab.call("_set_view", {"mode": "picker", "hire_seat": "vp_logistics", "back": "roster"})
		await _settle(10)
		_shot("/tmp/poe_council_picker.png")

	# Labour tab: enable a spread of policies so spectrums show mixed states.
	MatchState.set_labour_multiplier(1.2)
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_STRICT_SAFETY, true)
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_ANNUAL_PROFIT_SHARE, true)
	var tabs: TabContainer = _find_tab_container(people)
	if tabs != null:
		tabs.current_tab = 1
		await _settle(10)
		_shot("/tmp/poe_labour_tab.png")
	get_tree().quit(0)

func _find_tab_container(root: Node) -> TabContainer:
	if root is TabContainer:
		return root
	for c in root.get_children():
		var hit := _find_tab_container(c)
		if hit != null:
			return hit
	return null

const CouncilTabScript := preload("res://scripts/advisor_council_tab.gd")

func _find_council_tab(root: Node) -> Node:
	if root.get_script() == CouncilTabScript:
		return root
	for c in root.get_children():
		var hit := _find_council_tab(c)
		if hit != null:
			return hit
	return null

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
