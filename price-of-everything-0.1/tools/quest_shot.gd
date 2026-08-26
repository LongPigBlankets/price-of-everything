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

	await _bar_height_check()
	await _quest_cases()
	await _celebration_case()
	await _flash_case()
	get_tree().quit()


## Summaries are keyed by GOOD ID (g_020), not internal_name — Production writes
## `summary.produced[good.id]`. An earlier version of this harness fed internal names, which
## matched what mini_quest.gd was then checking, so both were wrong together and the run went
## green. Resolve through Catalog here so the harness cannot agree with a bug again.
func _gid(internal_name: String) -> String:
	return str(Catalog.get_good_by_internal_name(internal_name).get("id", ""))


func _sum(produced: Dictionary, consumed: Dictionary = {}, sold: Dictionary = {},
		tile_supplied: Dictionary = {}, tile_consumed: Dictionary = {}) -> Dictionary:
	var out := {"produced": {}, "consumed": {}, "sold": {}, "tile_supplied": {}, "tile_consumed": {}}
	for k in produced:
		out.produced[_gid(str(k))] = produced[k]
	for k in consumed:
		out.consumed[_gid(str(k))] = consumed[k]
	for k in sold:
		out.sold[_gid(str(k))] = sold[k]
	# {tile: {good_internal: qty}} in, {tile: {good_id: qty}} out — the same id resolution the
	# rest of this harness does, for the same reason.
	for t in tile_supplied:
		out.tile_supplied[str(t)] = _by_gid(tile_supplied[t])
	for t in tile_consumed:
		out.tile_consumed[str(t)] = _by_gid(tile_consumed[t])
	return out


func _by_gid(by_name: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k in by_name:
		out[_gid(str(k))] = by_name[k]
	return out


## Does the quest module make the bar thicker, or spill out of it?
##
## TopBar is a PanelContainer, and a container grows to its children's minimum size — but this
## one hangs off HUD (a plain Control) by anchors with offset_bottom = BAR_H, so its height is
## pinned. Worth MEASURING rather than reasoning about: the module is a direct child, and the
## briefing notch next to it is deliberately TALLER than the bar, so "a child taller than BAR_H"
## is a shape this bar already contains.
func _bar_height_check() -> void:
	var bar: Node = _find_topbar(_wm)
	if bar == null:
		print("[BARH] top bar not found")
		return
	PlayerProfile.tutorial_completed = false
	MatchState.ruleset["tutorial_enabled"] = false
	MiniQuest._on_state_reset()
	await _settle(8)
	var off_h: float = bar.size.y
	var off_min: float = bar.get_combined_minimum_size().y
	# Now make the quest appear.
	PlayerProfile.tutorial_completed = true
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20}, {"silica": 12}))
	await _settle(10)
	var on_h: float = bar.size.y
	var on_min: float = bar.get_combined_minimum_size().y
	var qb = bar.get("_quest_btn")
	var bar_h: float = bar.BAR_H
	print("[BARH] BAR_H=%.0f | bar height  quest off=%.1f  on=%.1f  (delta %.1f)" %
		[bar_h, off_h, on_h, on_h - off_h])
	print("[BARH] bar min height  off=%.1f  on=%.1f  (delta %.1f)" % [off_min, on_min, on_min - off_min])
	if qb != null:
		var bottom: float = qb.position.y + qb.size.y
		print("[BARH] module rect y=%.1f h=%.1f bottom=%.1f vs drawn bar height=%.0f -> %s" %
			[qb.position.y, qb.size.y, bottom, on_h,
			"INSIDE" if bottom <= on_h + 0.5 else "OVERFLOWS BY %.1f" % (bottom - on_h)])
	MiniQuest._on_state_reset()


## "id=on id=on" for every modifier a mission's reward is supposed to create, so a reward that
## lands on only one of its apply-sites is visible in the log rather than hidden behind a single
## has() that happens to be true.
func _rewards_live(kind: String) -> String:
	var parts: Array = []
	for id in MiniQuest.reward_modifier_ids(kind):
		parts.append("%s=%s" % [str(id), "on" if Modifiers.has(str(id)) else "MISSING"])
	return " ".join(parts)


## The 1.5 s completion sequence, sampled against the CLOCK.
##
## Deliberately starts with the flyout SHUT, which is the state a player is actually in when a
## turn resolves: the sequence has to open it, flash, draw the tick, move to the next mission,
## hold it open, and put it away again. Every one of those is a separate thing that can fail.
##
## Waits are wall-clock, not frame counts. A frame in this harness is 50-70 ms, not 16, so
## counting frames put every sample well past the moment it meant to catch and the whole
## sequence looked like it had fired instantly.
func _celebration_case() -> void:
	var bar: Node = _find_topbar(_wm)
	if bar == null:
		return
	Tutorial.active = false
	Tutorial.setup_reached = true
	MatchState.ruleset["tutorial_enabled"] = false
	MatchState.ruleset["start_id"] = ""
	MiniQuest._on_state_reset()
	bar._close_fly()
	bar.set("_quest_open", "")
	# Two steps in, mission 1 not yet done.
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20}, {"silica": 12, "sand": 30}))
	await _settle(4)
	print("[CELEB] before: fly=%s open=%s" %
		[str(bar.get("_fly_open_id")), str(bar.get("_quest_open"))])
	var t0: int = Time.get_ticks_msec()
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20, "sand": 60}, {"silica": 12, "sand": 30}))
	# The flash is on the MODULE, and the flyout stays SHUT the whole time — that is the whole
	# point of the change. So during the flash want_fly is "" (closed), and the module carries
	# the glow and the tick. Only after 1.5 s does the flyout pop open on the next mission.
	# During the flash the flyout is shut, so which accordion section is "open" is moot — want "".
	await _at(t0, 0.35)
	_celeb_sample(bar, t0, "flash", "", "")
	await _at(t0, 0.75)
	_celeb_sample(bar, t0, "half tick", "", "")
	await _at(t0, 1.25)
	_celeb_sample(bar, t0, "tick drawn", "", "")
	await _at(t0, 1.90)
	_celeb_sample(bar, t0, "moved on", "quest", "monetise")
	await _at(t0, 5.20)
	_celeb_sample(bar, t0, "put away", "", "")
	MiniQuest._on_state_reset()
	bar._close_fly()
	await _celebration_shot(bar)


## The same sequence again, purely for the picture. Saving a 3440x1440 PNG takes about a
## second, so a screenshot inside the timed run knocks every later sample out of phase — the
## measurement and the photograph cannot be the same pass.
func _celebration_shot(bar: Node) -> void:
	MiniQuest._on_state_reset()
	bar.set("_quest_open", "")
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20}, {"silica": 12, "sand": 30}))
	await _settle(4)
	var t0: int = Time.get_ticks_msec()
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20, "sand": 60}, {"silica": 12, "sand": 30}))
	await _at(t0, 0.9)   # deep into the second flash, tick most of the way drawn
	await _shoot_module("res://quest_celebrate.png")
	MiniQuest._on_state_reset()
	bar._close_fly()


## The glow and tick are read off the MODULE now, not a flyout section — that is where the
## animation moved. want_fly is what the flyout should be doing at this instant: "" through the
## flash (shut), "quest" once the next mission has popped open.
func _celeb_sample(bar: Node, t0: int, label: String, want_fly: String, want_open: String) -> void:
	var mod = bar.get("_quest_btn")
	var glow: float = mod.glow if mod != null and is_instance_valid(mod) else -1.0
	var tick: float = mod.tick_progress if mod != null and is_instance_valid(mod) else -1.0
	var fly := str(bar.get("_fly_open_id"))
	var open := str(bar.get("_quest_open"))
	print("[CELEB] %+5.2fs %-11s fly=%-5s open=%-9s glow=%.2f tick=%.2f  %s" %
		[(Time.get_ticks_msec() - t0) / 1000.0, label, fly if fly != "" else "-",
		open if open != "" else "-", glow, tick,
		"OK" if fly == want_fly and open == want_open else "WANT fly=%s open=%s" % [want_fly, want_open]])


## Wait until `seconds` after t0, whatever the frame rate has been doing.
func _at(t0: int, seconds: float) -> void:
	var target: float = float(t0) + seconds * 1000.0
	while float(Time.get_ticks_msec()) < target:
		await get_tree().process_frame


func _quest_cases() -> void:
	# Nothing until the tutorial is behind the player.
	# The four states the gate has to tell apart. The profile flag is set to FALSE throughout:
	# a veteran who never pressed End Tutorial must still see missions in a normal match, which is
	# the case that was broken.
	PlayerProfile.tutorial_completed = false
	MatchState.ruleset["start_id"] = ""
	for spec in [
			{"name": "normal match", "enabled": false, "active": false, "setup": false, "want": true},
			{"name": "tutorial running", "enabled": true, "active": true, "setup": true, "want": false},
			{"name": "skipped early", "enabled": true, "active": false, "setup": false, "want": false},
			{"name": "skipped late", "enabled": true, "active": false, "setup": true, "want": true},
			{"name": "finished", "enabled": false, "active": false, "setup": true, "want": true},
		]:
		MiniQuest._on_state_reset()
		MatchState.ruleset["tutorial_enabled"] = bool(spec.enabled)
		Tutorial.active = bool(spec.active)
		Tutorial.setup_reached = bool(spec.setup)
		MiniQuest._on_turn_processed(_sum({"glass": 40}))
		var got: bool = MiniQuest.is_available()
		print("[GATE] %-18s -> %s (want %s) %s" %
			[str(spec.name), str(got), str(spec.want), "OK" if got == bool(spec.want) else "WRONG"])
	Tutorial.active = false
	Tutorial.setup_reached = true
	MatchState.ruleset["tutorial_enabled"] = false
	MiniQuest._on_state_reset()
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

	# Does finishing a mission actually SAY anything? Both channels, since a toast with no
	# signal leaves the module silent and a signal with no toast leaves the screen silent.
	var announced: Array = []
	MiniQuest.mission_completed.connect(func(k: String, t: String, r: String) -> void:
		announced.append("%s | %s | %s" % [k, t, r]))
	var toasts: Array = []
	MatchState.toast_requested.connect(func(msg: String, _kind: String) -> void:
		toasts.append(msg))

	# Finish mission 1 — reward lands, module flips to mission 2.
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20, "sand": 60}, {"silica": 12, "sand": 30}))
	print("[QUEST] m1 complete=%s reward=%s | now: %s" %
		[str(MiniQuest.is_mission_complete("integrate")),
		str(Modifiers.has(MiniQuest.REWARD_ID_INTEGRATE)), MiniQuest.title()])

	# The third channel: the module itself flashes on the bar. A toast and a signal both firing
	# still leaves the bar looking exactly as it did, which is most of what "no feedback" meant.
	if bar != null:
		var anim = bar.get("_quest_anim")
		print("[ANNOUNCE] module flash=%s celebrating=%s" %
			["running" if anim != null and anim.is_valid() else "NONE",
			str(bar.get("_quest_celebrating"))])
	print("[ANNOUNCE] signal=%s" % str(announced))
	print("[ANNOUNCE] toast=%s" % str(toasts).replace("\n", " / "))

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
		MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30}, {"iron_ingots": 25}, {},
			{STEEL_TILE: {"iron_ingots": 30}}, {STEEL_TILE: {"iron_ingots": 25}}))
		# The reward has to be on the FURNACE AND THE EAF, not on whichever one this harness
		# happened to stub. Checking a single id passed while an EAF player saw nothing.
		print("[MAGNATE %s] m1 steps=%s done=%s complete=%s power_reward=%s" %
			[steel_recipe, str(MiniQuest.steps()), str(MiniQuest.done.get("steel")),
			str(MiniQuest.is_mission_complete("steel")), _rewards_live("steel")])

		# Mission 2 is now live: its step list is decided here, from the steel recipe.
		_route("mq_coal", "coal", INGOT_TILE)
		_route("mq_iron", "iron_ore", INGOT_TILE)
		MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50, "iron_ore": 50},
			{"iron_ingots": 25, "coal": 40, "iron_ore": 40}, {},
			{STEEL_TILE: {"iron_ingots": 30}, INGOT_TILE: {"coal": 25, "iron_ore": 25}},
			{STEEL_TILE: {"iron_ingots": 25}, INGOT_TILE: {"coal": 20, "iron_ore": 20}}))
		var steps: Array = MiniQuest.steps()
		print("[MAGNATE %s] m2 (%d steps, coal->steel present=%s) done=%s" %
			[steel_recipe, steps.size(), str(steps.has("Supply coal from that mine to your steel building")),
			str(MiniQuest.done.get("deposits"))])
		if burns_coal:
			# One more coal mine, routed to the steel tile, closes the last step.
			_probe("mq_coal2", "b_001", "r_001", "tile_8_4")
			_route("mq_coal2", "coal", STEEL_TILE)
			MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50, "iron_ore": 50},
				{"iron_ingots": 25, "coal": 40, "iron_ore": 40}, {},
				{STEEL_TILE: {"iron_ingots": 30, "coal": 25}, INGOT_TILE: {"coal": 25, "iron_ore": 25}},
				{STEEL_TILE: {"iron_ingots": 25, "coal": 20}, INGOT_TILE: {"coal": 20, "iron_ore": 20}}))
		print("[MAGNATE %s] m2 complete=%s transport_reward=%s" %
			[steel_recipe, str(MiniQuest.is_mission_complete("deposits")), _rewards_live("deposits")])
		if bar != null and burns_coal:
			bar._open_fly("quest")
			await _settle(10)
			var fly: Control = bar.get("_fly_panel")
			var mod: Control = bar.get("_quest_btn")
			# The panel is the MODULE's width and left edge, not its own text's. Printed rather
			# than eyeballed off a screenshot: the window is 3440 px wide but the viewport is
			# 2580, so a panel measured in image pixels reads a third wider than it is.
			print("[FLYW] flyout %.0f wide at x=%.0f | module %.0f wide at x=%.0f -> %s" %
				[fly.size.x, fly.global_position.x, mod.size.x, mod.global_position.x,
				"ALIGNED" if absf(fly.size.x - mod.size.x) < 1.5
					and absf(fly.global_position.x - mod.global_position.x) < 1.5 else "MISMATCH"])
			for n in _all(fly):
				if n is Label:
					var lab: Label = n
					print("[FLYW]   rect=%.0f lines=%d  %s" %
						[lab.size.x, lab.get_line_count(), lab.text])
			await _shoot_module("res://quest_flyout.png")
			bar._toggle_fly("quest")
	await _magnate_negatives()
	_clear_probes()


## The two things routing alone does NOT prove. Each is run from a state that is complete except
## for the one fact under test, so a pass means that fact is what carried it.
func _magnate_negatives() -> void:
	const INGOT_TILE := "tile_5_10"
	const STEEL_TILE := "tile_5_11"
	const COAL_TILE := "tile_7_4"
	# Each negative must first FINISH the steel mission: the deposits mission is not evaluated
	# until its predecessor is done, so without this the checks below never ran at all and
	# reported <null> rather than false — a negative that passes by not happening.
	var steel_ok := {STEEL_TILE: {"iron_ingots": 30}}
	var steel_eaten := {STEEL_TILE: {"iron_ingots": 25}}

	# 1. An NPC's mine on an inexhaustible deposit, routed correctly, must not count.
	MiniQuest._on_state_reset()
	_clear_probes()
	_probe("mq_ingots", "b_002", "r_005", INGOT_TILE)
	_probe("mq_steel", "b_002", "r_003", STEEL_TILE)
	_probe("mq_coal", "b_001", "r_001", COAL_TILE, "npc_rival")
	_route("mq_ingots", "iron_ingots", STEEL_TILE)
	_route("mq_coal", "coal", INGOT_TILE)
	MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50},
		{"iron_ingots": 25, "coal": 40}, {},
		_merge(steel_ok, {INGOT_TILE: {"coal": 25}}), _merge(steel_eaten, {INGOT_TILE: {"coal": 20}})))
	var d: Array = MiniQuest.done.get("deposits", [])
	print("[MAGNATE] (steel mission complete first: %s)" % str(MiniQuest.is_mission_complete("steel")))
	print("[MAGNATE npc-mine] coal steps=%s (want [false, false] — a rival's mine is not theirs)" %
		str([d[0] if d.size() > 0 else null, d[1] if d.size() > 1 else null]))

	# 2. A player mine routed to a tile whose building does NOT eat coal. Basic Oxygen
	#    steelmaking takes oxygen and limestone, never coal, so delivery there is not supply.
	MiniQuest._on_state_reset()
	_clear_probes()
	_probe("mq_steel", "b_002", "r_025", STEEL_TILE)     # Basic Oxygen — no coal
	_probe("mq_ingots", "b_002", "r_031", INGOT_TILE)     # Direct Reduced Iron — no coal either
	_probe("mq_coal", "b_001", "r_001", COAL_TILE)
	_route("mq_ingots", "iron_ingots", STEEL_TILE)
	_route("mq_coal", "coal", INGOT_TILE)
	MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50},
		{"iron_ingots": 25, "coal": 40}, {},
		_merge(steel_ok, {INGOT_TILE: {"coal": 25}}), _merge(steel_eaten, {INGOT_TILE: {"coal": 20}})))
	var d2: Array = MiniQuest.done.get("deposits", [])
	print("[MAGNATE] (steel mission complete first: %s)" % str(MiniQuest.is_mission_complete("steel")))
	print("[MAGNATE no-consumer] coal->ingots=%s (want false — that ingots plant burns no coal)" %
		str(d2[1] if d2.size() > 1 else null))

	# 3. Everything right except that nothing actually MOVED: the mine is theirs, on an
	#    inexhaustible deposit, routed to a plant that burns coal, and coal was consumed there —
	#    but no coal arrived from their own production, so the route is intent, not supply.
	MiniQuest._on_state_reset()
	_clear_probes()
	_probe("mq_steel", "b_002", "r_003", STEEL_TILE)
	_probe("mq_ingots", "b_002", "r_005", INGOT_TILE)
	_probe("mq_coal", "b_001", "r_001", COAL_TILE)
	_route("mq_ingots", "iron_ingots", STEEL_TILE)
	_route("mq_coal", "coal", INGOT_TILE)
	MiniQuest._on_turn_processed(_sum({"steel": 20, "iron_ingots": 30, "coal": 50},
		{"iron_ingots": 25, "coal": 40}, {},
		steel_ok.duplicate(true), _merge(steel_eaten, {INGOT_TILE: {"coal": 20}})))
	var d3: Array = MiniQuest.done.get("deposits", [])
	print("[MAGNATE] (steel mission complete first: %s)" % str(MiniQuest.is_mission_complete("steel")))
	print("[MAGNATE nothing-delivered] coal->ingots=%s (want false — routed, eaten, never shipped)" %
		str(d3[1] if d3.size() > 1 else null))


## Shallow-merge two {tile: {good: qty}} dicts.
func _merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out: Dictionary = a.duplicate(true)
	for t in b:
		if not out.has(t):
			out[t] = {}
		for g in b[t]:
			(out[t] as Dictionary)[g] = b[t][g]
	return out


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
