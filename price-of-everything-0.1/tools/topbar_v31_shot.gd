extends Node
## Dev tool: verify the top bar's v3.1 icon faces (cheat: `swap topbar v3.1`).
## Mirrors tools/topbar_v2_shot.gd's shape. Screenshots:
##   topbar_v31_classic.png     — bar as it ships today (flag off), for a side-by-side
##   topbar_v31_calm.png        — flag on, healthy state (green lights where they exist)
##   topbar_v31_problem.png     — flag on, power starved+derated+grid-drawing
##   quest_v31_intro.png        — mission module's first-appearance reveal (full text)
##   quest_v31_resting.png      — settled: collapsed to the icon
##   quest_v31_gold_tick.png    — completion: icon gold, tick mid-wipe
##   quest_v31_next_reveal.png  — completion handoff: next mission's full-text reveal
##   quest_v31_after_collapse.png — back to resting on the icon
##   power_fly_default.png      — power flyout open, factory-default priorities
##   power_fly_flipped.png      — power flyout, coal/gas toggled to Grid
## Needs a window:  "$GODOT_BIN" --path . res://tools/topbar_v31_shot.tscn --quit-after 1500

const OUT_DIR := "C:/Users/urigi/AppData/Local/Temp/claude/C--Users-urigi-price-of-everything-price-of-everything-0-1/07c26e3a-d370-4e95-9ab5-05bbb28794cb/scratchpad/out/"

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Seat a council + give the mission module something to show, same seed the v2
	# shot tool uses, so the two are visually comparable.
	MatchState.advisor_seats = {"cfo": "vera", "coo": "gerald", "government_affairs": "rufus"}
	MatchState.advisor_loyalty = {"vera": 7.2, "gerald": 1.5, "rufus": -5.0}
	MatchState.advisors_changed.emit()
	TurnManager.current_turn = 63
	TurnManager.turn_advanced.emit(63)
	Production.last_turn_summary = {"money_in": 900.0, "money_out": 400.0,
		"goods_sales_revenue": 700.0, "power_supply": 240, "grid_bought": 0}
	Production.turn_processed.emit(Production.last_turn_summary)
	await _settle(20)
	if TurnBriefing.expanded:
		TurnBriefing.collapse()
	await _settle(10)
	await _shot(OUT_DIR + "topbar_v31_classic.png")

	MatchState.set_use_topbar_v3_1(true)
	await _settle(10)
	await _shot(OUT_DIR + "topbar_v31_calm.png")

	# Hover verification: warp the mouse over the Victory module's icon and push a
	# synthetic motion event so Godot's own mouse-over tracking actually fires
	# mouse_entered (warp_mouse alone doesn't reliably trigger it).
	var bar: Control = game.get_node("UILayer/HUD/TopBar")
	var victory_mod: Control = bar.find_child("VictoryModule", true, false)
	var hover_pos: Vector2 = victory_mod.global_position + victory_mod.size * 0.5
	get_viewport().warp_mouse(hover_pos)
	var motion := InputEventMouseMotion.new()
	motion.position = hover_pos
	motion.global_position = hover_pos
	Input.parse_input_event(motion)
	await _settle(6)
	await _shot(OUT_DIR + "hover_glow_check.png")

	# Power in trouble: some buildings unpowered (red), some derated by intermittency
	# (blinking amber — the blink phase itself is whatever it lands on for this frame),
	# and drawing from the grid.
	var iid := "probe_building"
	MatchState.buildings[iid] = {"id": iid, "recipe_id": "", "owner": "player"}
	Production.missing_by_building[iid] = [{"good_id": "power", "amount": 5.0}]
	Production._intermittency_by_building["probe_building_2"] = {"derate": 0.4}
	Production.last_turn_summary = {"money_in": 300.0, "money_out": 900.0,
		"goods_sales_revenue": 200.0, "power_supply": 180, "grid_bought": 40}
	Production.turn_processed.emit(Production.last_turn_summary)
	await _settle(20)
	await _shot(OUT_DIR + "topbar_v31_problem.png")
	# Back to a calm supply so the mission sequence below isn't shot over a red bar.
	Production.missing_by_building.erase(iid)
	Production._intermittency_by_building.erase("probe_building_2")
	Production.last_turn_summary = {"money_in": 900.0, "money_out": 400.0,
		"goods_sales_revenue": 700.0, "power_supply": 240, "grid_bought": 0}
	Production.turn_processed.emit(Production.last_turn_summary)
	await _settle(10)

	# MiniQuest.is_available() otherwise stays false with no start_id and nothing
	# produced yet to infer a chain from (see mini_quest.gd:_pick_chain) — force one
	# so the QuestModule actually shows for this shot. v3.1 is already on from above.
	MiniQuest.chain = "glass"
	MiniQuest.quest_changed.emit()
	# Intro: full-width text reveal, right after the module first appears (before
	# QUEST_V31_HOLD_SEC=3s elapses and it collapses to the icon).
	await _settle(6)
	await _shot(OUT_DIR + "quest_v31_intro.png")
	await _wait(3.0 + 1.0 + 0.5)   # QUEST_V31_HOLD_SEC + QUEST_V31_COLLAPSE_SEC + margin
	await _shot(OUT_DIR + "quest_v31_resting.png")
	# Completion timeline from the emit (t=0, resequenced 27 Aug — gold fill, then a tick wipes
	# across it, THEN the handoff; no more separate "icon holds gold" beat in between):
	# stage 0 fade [0, .18], stage 1 gold fill [.18, .53] + hold [.53, .78],
	# stage 2 tick wipe [.78, 1.23] + hold [1.23, 1.68] -> _finish_celebration fires.
	# stage 3: expand tween starts immediately, [1.68, 2.68]; QUEST_V31_HOLD_SEC's 3s timer
	# starts at the SAME t=1.68, so the true "settled, holding" window is [2.68, 4.68].
	# stage 4: collapse tween [4.68, 5.68].
	# Actually mark it done, not just the signal — active_mission() reads MiniQuest's
	# own done[] state, not the completion signal, so faking only the signal would
	# leave "integrate" the active mission and the reveal below would show it again.
	MiniQuest.done["integrate"] = [true, true, true, true]
	MiniQuest.mission_completed.emit("integrate", "Integrate glass and sand production", "+5% margin")
	await _wait(0.4)
	await _shot(OUT_DIR + "quest_v31_fill.png")          # t=.4: stage 1, gold filling in
	await _wait(0.6)
	await _shot(OUT_DIR + "quest_v31_tick_wipe.png")     # t=1.0: stage 2, tick mid-wipe
	await _wait(1.9)
	await _shot(OUT_DIR + "quest_v31_next_reveal.png")   # t=2.9: stage 3 settled, next mission shown
	await _wait(3.3)
	await _shot(OUT_DIR + "quest_v31_after_collapse.png")  # t=6.2: stage 4 done + margin

	# Power flyout: two Supply Priority toggles. Factory defaults are coal_gas=
	# "self" ("Your buildings" pill lit) and wind_solar="grid" ("Grid" pill lit).
	# top_bar.gd has no public "open this flyout" API — _toggle_fly is the same
	# method the PowerModule button's own pressed handler calls, so drive it the
	# same way a click would rather than fabricating mouse events for a flyout
	# opened via a plain (non-hover-dependent) click.
	var power_mod: Control = bar.find_child("PowerModule", true, false)
	if power_mod == null:
		print("[topbar_v31_shot] WARNING: PowerModule not found by name")
	bar.call("_toggle_fly", "power")
	await _settle(6)
	await _shot(OUT_DIR + "power_fly_default.png")
	print("[topbar_v31_shot] defaults: coal_gas=", MatchState.power_priority_coal_gas,
		" wind_solar=", MatchState.power_priority_wind_solar)

	# Flip coal/gas to Grid the same way the toggle button's own handler does
	# (set + rebuild the open flyout in place) and confirm it sticks + redraws.
	MatchState.set_power_priority("coal_gas", "grid")
	bar.call("_refresh_open_fly")
	await _settle(6)
	await _shot(OUT_DIR + "power_fly_flipped.png")
	print("[topbar_v31_shot] after flip: coal_gas=", MatchState.power_priority_coal_gas)

	print("[topbar_v31_shot] done")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[topbar_v31_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
