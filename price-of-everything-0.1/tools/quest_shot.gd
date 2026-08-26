extends Node2D
## Verification for the post-tutorial mini quest module + its flyout, and for the construct
## panel's intermittency warning actually FLASHING.
##
## The quest needs a state no fresh match is in — tutorial finished, a chain picked, some steps
## met — so this drives MiniQuest with turn summaries rather than playing a game to get there.
## The summaries are the same shape Production emits, so what is exercised is the real
## evaluation path, not a stub.
##   Godot --path . res://tools/quest_shot.tscn --quit-after 4000

var _wm


func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	await _quest_cases()
	await _flash_case()
	get_tree().quit()


## Summaries are keyed by GOOD ID (g_020), not internal_name — Production writes
## `summary.produced[good.id]`. An earlier version of this harness fed internal names, which
## matched what mini_quest.gd was then checking, so both were wrong together and the run went
## green. Resolve through Catalog here so the harness cannot agree with a bug again.
func _gid(internal_name: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal_name).get("id", ""))


func _sum(produced: Dictionary, consumed: Dictionary = {}, sold: Dictionary = {}) -> Dictionary:
	var out := {"produced": {}, "consumed": {}, "sold": {}}
	for k in produced:
		out.produced[_gid(str(k))] = produced[k]
	for k in consumed:
		out.consumed[_gid(str(k))] = consumed[k]
	for k in sold:
		out.sold[_gid(str(k))] = sold[k]
	return out


func _quest_cases() -> void:
	# Nothing until the tutorial is behind the player.
	PlayerProfile.tutorial_completed = false
	MatchState.ruleset["tutorial_enabled"] = false
	MatchState.ruleset["start_id"] = ""
	MiniQuest._on_state_reset()
	print("[QUEST] before tutorial: available=%s (want false)" % str(MiniQuest.is_available()))

	PlayerProfile.tutorial_completed = true
	# Glass player, two steps in: silica made and self-supplied, sand still bought.
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20}, {"silica": 12, "sand": 30}))
	print("[QUEST] m1 glass: chain=%s active=%s done=%s title=%s" %
		[MiniQuest.chain, MiniQuest.active_mission(), str(MiniQuest.done), MiniQuest.title()])
	await _settle(6)
	var bar: Node = _find_topbar(_wm)
	if bar != null:
		var qb = bar.get("_quest_btn")
		var bb = bar.get("_briefing_btn")
		print("[QUEST] module pos=%s | notch right edge=%.0f (want pos.x = edge + 10)" %
			[str(qb.position), bb.position.x + bb.size.x])
	await _shoot_module("res://quest_module.png")

	# Finish mission 1 — reward lands, module flips to mission 2.
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20, "sand": 60}, {"silica": 12, "sand": 30}))
	print("[QUEST] m1 complete=%s reward=%s | now: %s" %
		[str(MiniQuest.is_mission_complete("integrate")),
		str(Modifiers.has(MiniQuest.REWARD_ID_INTEGRATE)), MiniQuest.title()])

	# Mission 2: r_029 Concrete Firing consumes silica and makes concrete.
	var iid := "quest_probe_concrete"
	MatchState.buildings[iid] = {"building_id": "b_002", "recipe_id": "r_029", "instance_id": iid, "tile_id": "tile_5_10"}
	MiniQuest._on_turn_processed(_sum(
		{"glass": 40, "silica": 20, "sand": 60, "concrete": 12}, {"silica": 12, "sand": 30}, {"concrete": 9}))
	print("[QUEST] m2 done=%s picked=%s reward=%s" %
		[str(MiniQuest.done.get("monetise")), Catalog.get_display_name(MiniQuest.monetised_good),
		MiniQuest.reward_text()])
	MatchState.buildings.erase(iid)

	# Aluminium mirror: chlorine + bauxite, both feeding the smelter.
	MiniQuest._on_state_reset()
	MiniQuest._on_turn_processed(_sum(
		{"aluminium": 30, "chlorine": 15, "bauxite_ore": 40}, {"chlorine": 10, "bauxite_ore": 22}))
	print("[QUEST] alu: chain=%s steps=%s" % [MiniQuest.chain, str(MiniQuest.steps())])

	await _magnate_cases(bar)


## The magnate pair. Buildings are stubbed into MatchState the way the sim holds them
## (building_id / recipe_id / tile_id) and routed through output_stockpile_destinations, which
## is the same dict get_output_stockpile_destination reads — so the delivery checks exercise the
## real accessor rather than a stand-in. Mine tiles are REAL tiles carrying inexhaustible
## deposits in tile_properties.csv, because has_infinite_deposit reads the terrain.
func _magnate_cases(bar: Node) -> void:
	# ISOLATE THE WORLD. This harness boots a real match, which already holds 561 buildings —
	# and _producers_of scans all of them. Left alone, a REAL coal-burning furnace elsewhere on
	# the map answered "does your steel plant need coal?" and the EAF case silently tested
	# nothing. Swap in only the probes, then put the match back.
	var saved_buildings: Dictionary = MatchState.buildings
	var saved_routes: Dictionary = MatchState.output_stockpile_destinations
	MatchState.buildings = {}
	MatchState.output_stockpile_destinations = {}
	await _magnate_body(bar)
	MatchState.buildings = saved_buildings
	MatchState.output_stockpile_destinations = saved_routes
	MatchState.ruleset["start_id"] = ""


func _magnate_body(bar: Node) -> void:
	const INGOT_TILE := "tile_5_10"
	const STEEL_TILE := "tile_5_11"
	const COAL_TILE := "tile_7_4"      # bare "coal" => inexhaustible
	const IRON_TILE := "tile_7_2"      # bare "iron_ore" => inexhaustible
	for steel_recipe in ["r_003", "r_076"]:
		var burns_coal: bool = steel_recipe == "r_003"
		MiniQuest._on_state_reset()
		MatchState.ruleset["start_id"] = "metal_magnate"
		_clear_probes()
		_probe("mq_ingots", "b_002", "r_005", INGOT_TILE)
		_probe("mq_steel", "b_002" if burns_coal else "b_008", steel_recipe, STEEL_TILE)
		_probe("mq_coal", "b_001", "r_001", COAL_TILE)
		_probe("mq_iron", "b_001", "r_002", IRON_TILE)
		# The ingots plant ships ingots to the steel tile.
		_route("mq_ingots", "iron_ingots", STEEL_TILE)
		print("[MAGNATE %s] steel recipe burns coal: %s" %
			[steel_recipe, str(MiniQuest._steel_recipe_needs_coal())])
		# Consumption matters now: the steel plant must actually EAT the ingots, not just be
		# shipped them, so every magnate summary carries what was consumed as well.
		MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30}, {"iron_ingots": 25}))
		print("[MAGNATE %s] m1 steps=%s done=%s complete=%s power_reward=%s" %
			[steel_recipe, str(MiniQuest.steps()), str(MiniQuest.done.get("steel")),
			str(MiniQuest.is_mission_complete("steel")), str(Modifiers.has(MiniQuest.REWARD_ID_STEEL))])

		# Mission 2 is now live: its step list is decided here, from the steel recipe.
		_route("mq_coal", "coal", INGOT_TILE)
		_route("mq_iron", "iron_ore", INGOT_TILE)
		MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50, "iron_ore": 50},
			{"iron_ingots": 25, "coal": 40, "iron_ore": 40}))
		var steps: Array = MiniQuest.steps()
		print("[MAGNATE %s] m2 (%d steps, coal->steel present=%s) done=%s" %
			[steel_recipe, steps.size(), str(steps.has("Supply coal from that mine to your steel building")),
			str(MiniQuest.done.get("deposits"))])
		if burns_coal:
			# One more coal mine, routed to the steel tile, closes the last step.
			_probe("mq_coal2", "b_001", "r_001", "tile_8_4")
			_route("mq_coal2", "coal", STEEL_TILE)
			MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50, "iron_ore": 50},
				{"iron_ingots": 25, "coal": 40, "iron_ore": 40}))
		print("[MAGNATE %s] m2 complete=%s transport_reward=%s" %
			[steel_recipe, str(MiniQuest.is_mission_complete("deposits")),
			str(Modifiers.has("%s_coal" % MiniQuest.REWARD_ID_DEPOSITS))])
		if bar != null and burns_coal:
			bar._toggle_fly("quest")
			await _settle(10)
			await _shoot_module("res://quest_flyout.png")
			bar._toggle_fly("quest")
	await _magnate_negatives()
	_clear_probes()


## The two things routing alone does NOT prove. Each is run from a state that is complete except
## for the one fact under test, so a pass means that fact is what carried it.
func _magnate_negatives() -> void:
	const INGOT_TILE := "tile_5_10"
	const COAL_TILE := "tile_7_4"

	# 1. An NPC's mine on an inexhaustible deposit, routed correctly, must not count.
	MiniQuest._on_state_reset()
	_clear_probes()
	_probe("mq_ingots", "b_002", "r_005", INGOT_TILE)
	_probe("mq_steel", "b_002", "r_003", "tile_5_11")
	_probe("mq_coal", "b_001", "r_001", COAL_TILE, "npc_rival")
	_route("mq_ingots", "iron_ingots", "tile_5_11")
	_route("mq_coal", "coal", INGOT_TILE)
	MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50},
		{"iron_ingots": 25, "coal": 40}))
	var d: Array = MiniQuest.done.get("deposits", [])
	print("[MAGNATE npc-mine] coal steps=%s (want [false, false] — a rival's mine is not theirs)" %
		str([d[0] if d.size() > 0 else null, d[1] if d.size() > 1 else null]))

	# 2. A player mine routed to a tile whose building does NOT eat coal. Basic Oxygen
	#    steelmaking takes oxygen and limestone, never coal, so delivery there is not supply.
	MiniQuest._on_state_reset()
	_clear_probes()
	_probe("mq_steel", "b_002", "r_025", "tile_5_11")     # Basic Oxygen — no coal
	_probe("mq_ingots", "b_002", "r_031", INGOT_TILE)     # Direct Reduced Iron — no coal either
	_probe("mq_coal", "b_001", "r_001", COAL_TILE)
	_route("mq_ingots", "iron_ingots", "tile_5_11")
	_route("mq_coal", "coal", INGOT_TILE)
	MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50},
		{"iron_ingots": 25, "coal": 40}))
	var d2: Array = MiniQuest.done.get("deposits", [])
	print("[MAGNATE no-consumer] coal->ingots=%s (want false — that ingots plant burns no coal)" %
		str(d2[1] if d2.size() > 1 else null))


func _probe(iid: String, building_id: String, recipe_id: String, tile_id: String,
		owner: String = "player_1") -> void:
	MatchState.buildings[iid] = {
		"instance_id": iid, "building_id": building_id, "recipe_id": recipe_id,
		"tile_id": tile_id, "owner": owner}


func _route(iid: String, good_internal: String, tile_id: String) -> void:
	var gid := _gid(good_internal)
	if not MatchState.output_stockpile_destinations.has(iid):
		MatchState.output_stockpile_destinations[iid] = {}
	(MatchState.output_stockpile_destinations[iid] as Dictionary)[gid] = tile_id


func _clear_probes() -> void:
	for iid in ["mq_ingots", "mq_steel", "mq_coal", "mq_coal2", "mq_iron"]:
		MatchState.buildings.erase(iid)
		MatchState.output_stockpile_destinations.erase(iid)


## The intermittency row must not just exist, it must flash: _flash_row parents a ColorRect
## wash to the row and tweens its alpha after INFRA_FLASH_DELAY. Sample past the delay and
## assert the wash is actually lit, because "the row is in the list that gets flashed" is a
## claim about code, not about what the player sees.
func _flash_case() -> void:
	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.get("construct_panel_v2") == null:
		print("[FLASH] construct panel not found")
		return
	var panel = menu.construct_panel_v2
	panel.show()
	panel._locked_tile_id = "tile_5_10"
	panel._on_recipe_pressed("b_024", "r_146")     # Solar Farm — carries the warning
	# Poll rather than guess a frame: the tween is timed in SECONDS (1.0 s delay, 0.3 s ramp)
	# and this harness does not run at a known frame rate, so sample every frame for long enough
	# to cover the whole flash and keep the peak.
	var row: Control = null
	var peak := 0.0
	var washes := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2600:
		await get_tree().process_frame
		var r := _warning_row(panel)
		if r != null:
			row = r
			for c in r.get_children():
				if c is ColorRect:
					washes = maxi(washes, 1)
					peak = maxf(peak, (c as ColorRect).color.a)
	if row == null:
		print("[FLASH] no intermittency row found")
		return
	print("[FLASH] wash present=%d peak alpha=%.3f (want > 0) %s" %
		[washes, peak, "OK" if peak > 0.0 else "NOT FLASHING"])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://intermittent_flash.png")
	print("SAVED res://intermittent_flash.png")


func _warning_row(panel) -> Control:
	for n in _all(panel):
		if n is RichTextLabel and "intermittent power" in String((n as RichTextLabel).text):
			var up: Node = n
			while up != null and not (up is PanelContainer):
				up = up.get_parent()
			return up as Control
	return null


func _shoot_module(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SAVED ", path)


func _find_topbar(n: Node) -> Node:
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("top_bar.gd"):
		return n
	for c in n.get_children():
		var f: Node = _find_topbar(c)
		if f != null:
			return f
	return null


func _all(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_all(c))
	return out


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
