extends Node
## Dev tool: where the main thread goes when a Metal Magnate player finishes the first mission,
## places a steel furnace, routes the iron furnace's output to the stockpile and takes the steel
## furnace's input from the stockpile. Every frame over 100 ms is printed with the step it fell in,
## and each action's own signal listeners are timed one by one.
##   godot --headless --path . res://tools/freeze_probe.tscn -- [--no-board]
## --no-board: the hidden supply chain view never rebuilds, to tell its cost apart from the rest.

const START := "res://data/starts/metal_magnate.json"
const TILE := "tile_9_9"
const Service := preload("res://scripts/middleman_service.gd")

var _label := "boot"
var _last := 0
var _worst := {}
var _view: Node = null

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last > 0:
		var gap := (now - _last) / 1000.0
		_worst[_label] = maxf(float(_worst.get(_label, 0.0)), gap)
		if gap > 100.0: print("[FREEZE] %-30s frame %9.1f ms" % [_label, gap])
	_last = now

## --loading-screen: the game loads as a player's does, behind the loading screen (its warm-ups
## included), and Begin is pressed the moment it is offered. The probe lives on the tree root then,
## because the loading screen replaces the scene it started in.
func _ready() -> void:
	DecisionState.auto_resolve = true  # nobody is there to answer the decision cards
	var loading := "--loading-screen" in OS.get_cmdline_user_args()
	if loading and not has_meta("survivor"):
		var probe := Node.new()
		probe.set_script(get_script())
		probe.set_meta("survivor", true)
		get_tree().root.add_child.call_deferred(probe)
		return
	SaveLoad.prepare_new_game(START)
	if loading:
		await get_tree().process_frame
		var screen: Node = preload("res://scripts/loading_screen.gd").show_global(get_tree())
		while not screen.is_inside_tree(): await get_tree().process_frame
		screen.begin_load(SaveLoad.MAIN_SCENE)
		while not (screen.get("_begin") is Button and (screen.get("_begin") as Button).visible and (screen.get("_begin") as Button).modulate.a >= 0.9):
			await get_tree().process_frame
		_label = "Begin"
		(screen.get("_begin") as Button).pressed.emit()
	else:
		var world: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
		add_child(world)
	await _settle(8000)
	var view := _find_script(get_tree().root, "res://scripts/empire_view.gd")
	_view = view
	print("[PROBE] empire view: %s, low quality: %s" % [view != null, PlayerProfile.is_low_quality()])
	if loading: pass
	elif "--no-board" in OS.get_cmdline_user_args() and view != null:
		view.set_process(false)
		view.set("_preparing", true)
	elif view != null:
		# The loading screen builds the supply view before Begin (world_map.gd); a direct boot does not.
		_label = "boot: prepare supply view"
		await view.prepare()
	await _wait_prepared(view, "boot: background supply view")
	MiniQuest.mission_completed.connect(func(kind: String, title: String, _reward: String) -> void:
		print("[PROBE] mission completed: %s (%s) during '%s'" % [kind, title, _label]))
	if "--mission-listeners" in OS.get_cmdline_user_args():
		if "--warm-plate" in OS.get_cmdline_user_args():
			_label = "warm plate"
			await _find_script(get_tree().root, "res://scripts/top_bar.gd").warm_mission_plate()
			await _settle(1000)
		_label = "mission listeners"
		_time_listeners([MiniQuest.quest_changed], [])
		_time_listeners([MiniQuest.mission_completed], ["t_open", "Open your building", ""])
		await _settle(2000)
		for step in _worst: print("[PROBE]   %-44s %9.1f ms" % [step, _worst[step]])
		get_tree().quit(0)
		return
	# The Tutorial's first mission: open one of your buildings.
	var bdp := _find_script(get_tree().root, "res://scripts/building_detail_panel_v2.gd")
	var first := _furnace_making("r_005")
	if "--npc-first" in OS.get_cmdline_user_args():
		var npc := ""
		for iid in BuildingState.buildings:
			if str(BuildingState.buildings[iid].get("building_id", "")) == "b_002" and not BuildingState.is_player_owned(BuildingState.buildings[iid]):
				npc = str(iid); break
		_label = "open NPC building (no mission)"
		var at := Time.get_ticks_usec()
		bdp.call("show_building", BuildingState.get_building(npc).merged({"instance_id": npc}))
		print("[PROBE] NPC show_building in %.1f ms" % [(Time.get_ticks_usec() - at) / 1000.0])
		await _settle(2000)
		bdp.visible = false
		await _settle(500)
	_label = "open building (first mission)"
	var opened := Time.get_ticks_usec()
	bdp.call("show_building", BuildingState.get_building(first).merged({"instance_id": first}))
	print("[PROBE] show_building in %.1f ms, missions done %s" % [(Time.get_ticks_usec() - opened) / 1000.0, MiniQuest.get("board_done")])
	await _settle(2000)
	bdp.visible = false
	await _settle(500)
	_label = "open building again (no mission)"
	opened = Time.get_ticks_usec()
	bdp.call("show_building", BuildingState.get_building(first).merged({"instance_id": first}))
	print("[PROBE] show_building again in %.1f ms" % [(Time.get_ticks_usec() - opened) / 1000.0])
	await _settle(2000)
	if "--panel-only" in OS.get_cmdline_user_args():
		for step in _worst: print("[PROBE]   %-44s %9.1f ms" % [step, _worst[step]])
		get_tree().quit(0)
		return
	_label = "cash change, building panel open"
	_time_listeners([MatchState.money_changed], [MatchState.money])
	await _turn(1)
	bdp.visible = false
	var construct := _find_script(get_tree().root, "res://scripts/construct_ds2/construct_ds2.gd")
	if construct != null:
		construct.call("open_browser")
		await _settle(1000)
		_label = "cash change, construct panel open"
		_time_listeners([MatchState.money_changed], [MatchState.money])
		await _turn(2)
		construct.visible = false
	for turn in range(3, 6):
		await _turn(turn)

	_label = "build steel furnace"
	MatchState.add_money(1000.0)  # the player took a loan first
	BuildMode.enter_build_mode("b_002", "r_003")
	Construction.placing_level = 1
	var map := _find_script(get_tree().root, "res://scripts/world_map.gd")
	var started := Time.get_ticks_usec()
	var placed: bool = map.call("_attempt_build", "b_002", TILE)
	print("[PROBE] _attempt_build placed=%s in %.1f ms, sites=%s" % [placed, (Time.get_ticks_usec() - started) / 1000.0, Construction.construction_projects.size()])
	if BuildMode.has_method("exit_build_mode"): BuildMode.exit_build_mode()
	await _settle(1500)
	await _wait_prepared(view, "build steel furnace: background supply view")
	var turn := 6
	while _steel_furnace() == "" and turn < 20:
		await _turn(turn)
		turn += 1
	await _turn(turn)

	var iron := _furnace_making("r_005")
	var steel := _steel_furnace()
	print("[PROBE] iron furnace %s, steel furnace %s" % [iron, steel])
	await _route_step(bdp, iron, "iron furnace output to stockpile", func(building: Dictionary, recipe: Dictionary) -> void:
		MatchState.set_output_stockpile_destination(iron, TILE, "g_004")
		bdp.call("_queue_refresh")
		bdp.call("_open_output_sheet", building, recipe))
	await _route_step(bdp, steel, "steel furnace input from stockpile", func(building: Dictionary, recipe: Dictionary) -> void:
		var result: Dictionary = Service.set_input_route(steel, "g_004", "primary", "stockpile")
		if bool(result.get("ok", false)): result = Service.set_input_route(steel, "g_004", "fallback", "")
		print("[PROBE] set_input_route ", result.get("ok"))
		bdp.call("_queue_refresh")
		bdp.call("_open_input_sources_sheet", building, recipe))
	await _turn(turn + 1)

	print("[PROBE] worst frame per step:")
	for step in _worst: print("[PROBE]   %-44s %9.1f ms" % [step, _worst[step]])
	get_tree().quit(0)

## Opens the building, then does what a route knob does: the change, a panel refresh and the sheet
## reopened (bdp_v3_routes.gd).
func _route_step(bdp: Node, iid: String, label: String, change: Callable) -> void:
	var building := BuildingState.get_building(iid).merged({"instance_id": iid})
	var recipe := Catalog.get_recipe(str(building.get("recipe_id", "")))
	_label = label + ": open building"
	bdp.call("show_building", building)
	await _settle(1500)
	_label = label
	var started := Time.get_ticks_usec()
	change.call(building, recipe)
	print("[PROBE] %s: change + sheet in %.1f ms" % [label, (Time.get_ticks_usec() - started) / 1000.0])
	await _settle(3000)
	await _wait_prepared(_view, label + ": background supply view")
	bdp.visible = false

func _turn(n: int) -> void:
	_label = "turn %d" % n
	var started := Time.get_ticks_usec()
	TurnManager.commit_turn()
	await TurnManager.turn_resolution_completed
	print("[PROBE] turn %d resolved in %.1f ms" % [n, (Time.get_ticks_usec() - started) / 1000.0])
	await _settle(1500)
	await _wait_prepared(_view, "turn %d: background supply view" % n)

func _settle(msec: int) -> void:
	var until := Time.get_ticks_msec() + msec
	while Time.get_ticks_msec() < until: await get_tree().process_frame

## Waits out a background rebuild of the hidden supply chain view, so its frames land in the step
## that started it.
func _wait_prepared(view: Node, label: String) -> void:
	if view == null: return
	var was := _label
	_label = label
	var until := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < until and (bool(view.get("_preparing")) or bool(view.get("_refresh_queued"))):
		await get_tree().process_frame
	var board: Object = view.get("_board")
	if board != null:
		var slow := {}
		var profile: Dictionary = board.get("load_profile")
		for k in profile:
			if (profile[k] is float or profile[k] is int) and float(profile[k]) >= 100.0: slow[k] = snappedf(float(profile[k]), 1)
		print("[PROBE] %s: board stages over 100 ms %s" % [label, JSON.stringify(slow)])
	_label = was

## Calls each listener of these signals on its own, with these arguments, and prints its time.
func _time_listeners(signals: Array, args: Array) -> void:
	for sig: Signal in signals:
		for connection: Dictionary in sig.get_connections():
			var callable: Callable = connection.callable
			var started := Time.get_ticks_usec()
			callable.callv(args.slice(0, callable.get_argument_count()) if callable.get_argument_count() >= 0 else args)
			var ms := (Time.get_ticks_usec() - started) / 1000.0
			var target: Object = callable.get_object()
			var where := str(target.get_script().resource_path) if target != null and target.get_script() != null else str(target)
			print("[LISTENER] %-40s %-48s %8.2f ms" % [sig.get_name(), "%s:%s" % [where.get_file(), callable.get_method()], ms])

func _furnace_making(recipe: String) -> String:
	for iid in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[iid]
		if BuildingState.is_player_owned(b) and str(b.get("recipe_id", "")) == recipe and str(b.get("building_id", "")) == "b_002":
			return str(iid)
	return ""

func _steel_furnace() -> String:
	return _furnace_making("r_003")

func _find_script(node: Node, path: String) -> Node:
	if node.get_script() != null and (node.get_script() as Script).resource_path == path: return node
	for child in node.get_children():
		var found := _find_script(child, path)
		if found != null: return found
	return null
