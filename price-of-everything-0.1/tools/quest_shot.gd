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
	MiniQuest._on_state_reset()
	print("[QUEST] before tutorial: available=%s (want false)" % str(MiniQuest.is_available()))

	PlayerProfile.tutorial_completed = true
	# Glass player, two steps in: silica made and self-supplied, sand still bought.
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20}, {"silica": 12, "sand": 30}))
	print("[QUEST] m1 glass: chain=%s available=%s done=%s title=%s (want glass/true/2 done)" %
		[MiniQuest.chain, str(MiniQuest.is_available()), str(MiniQuest.done[0]), MiniQuest.title()])
	await _settle(6)
	var bar: Node = _find_topbar(_wm)
	if bar != null:
		var qb = bar.get("_quest_btn")
		var bb = bar.get("_briefing_btn")
		print("[QUEST] module pos=%s size=%s | notch right edge=%.0f (want pos.x = edge + 10)" %
			[str(qb.position), str(qb.size), bb.position.x + bb.size.x])
	await _shoot_module("res://quest_module.png")

	# Finish mission 1 — the reward lands and the module flips to mission 2.
	MiniQuest._on_turn_processed(_sum({"glass": 40, "silica": 20, "sand": 60}, {"silica": 12, "sand": 30}))
	print("[QUEST] m1 complete=%s reward=%s | now showing: %s" %
		[str(MiniQuest.is_mission_complete(0)), str(Modifiers.has(MiniQuest.REWARD_ID_INTEGRATE)),
		MiniQuest.title()])
	print("[QUEST] m2 steps=%s" % str(MiniQuest.steps()))

	# Mission 2 needs a building of theirs running a recipe that eats the surplus and makes
	# something else. r_029 Concrete Firing consumes silica and makes concrete.
	var iid := "quest_probe_concrete"
	MatchState.buildings[iid] = {"building_id": "b_001", "recipe_id": "r_029", "instance_id": iid}
	MiniQuest._on_turn_processed(_sum(
		{"glass": 40, "silica": 20, "sand": 60, "concrete": 12},
		{"silica": 12, "sand": 30},
		{"concrete": 9}))
	print("[QUEST] m2 done=%s picked=%s reward=%s (want 3 done)" %
		[str(MiniQuest.done[1]), Catalog.get_display_name(MiniQuest.monetised_good),
		MiniQuest.reward_text()])
	var timed := false
	for m in Modifiers.active():
		if str(m.get("id", "")) == MiniQuest.REWARD_ID_MONETISE:
			timed = int(m.get("expires_turn", 0)) > 0
			print("[QUEST] m2 modifier pct=%s expires_turn=%s target=%s" %
				[str(m.get("pct")), str(m.get("expires_turn")), str(m.get("target_match"))])
	print("[QUEST] m2 reward is time-limited: %s (want true)" % str(timed))
	MatchState.buildings.erase(iid)

	if bar != null:
		bar._toggle_fly("quest")
		await _settle(10)
		await _shoot_module("res://quest_flyout.png")
		print("[QUEST] flyout size=%s (want y=120)" % str(bar._fly_panel.size))
		bar._toggle_fly("quest")

	# Aluminium mirror: chlorine + bauxite, both feeding the smelter.
	MiniQuest._on_state_reset()
	MiniQuest._on_turn_processed(_sum(
		{"aluminium": 30, "chlorine": 15, "bauxite_ore": 40},
		{"chlorine": 10, "bauxite_ore": 22}))
	print("[QUEST] alu: chain=%s done=%s title=%s" %
		[MiniQuest.chain, str(MiniQuest.done[0]), MiniQuest.title()])
	print("[QUEST] alu steps=%s" % str(MiniQuest.steps()))


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
