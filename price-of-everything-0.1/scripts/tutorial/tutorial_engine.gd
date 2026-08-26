extends Node
## Tutorial "Coach" engine (autoload `Tutorial`). Inert unless the active match's
## ruleset carries `tutorial_enabled` — so it costs nothing for every normal game. It
## rides EXISTING sim signals for step detection (a signal only WAKES the check; live
## state DECIDES it via tutorial_detectors), drives the coach overlay, and confines the
## player to the tutorial board. Wave 1 = the walking skeleton: one gated step + one
## info card + board camera clamp. Later waves append content to tutorial_steps.gd only.
##
## Registered AFTER MatchState/BuildMode/MapMode/TurnManager so their signals exist at
## _ready. Cross-references use preload (no class_name) for headless.

const CoachOverlayScript := preload("res://scripts/tutorial/coach_overlay.gd")
const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const TutorialDetectors := preload("res://scripts/tutorial/tutorial_detectors.gd")
const TutorialRouteHighlightScript := preload("res://scripts/tutorial/tutorial_route_highlight.gd")

const POLL_INTERVAL := 0.25   # s; re-evaluates the active step's decide predicate
const PORT_PURCHASE_DISABLED_TOOLTIP := "This option is disabled during the tutorial"

signal step_changed(id: String)

var active: bool = false
## Did this run reach the point where the post-tutorial missions make sense?
##
## The missions assume the setup the last steps build — the recipe switch that leaves the
## furnace eating silica, or the smelter on carbochlorination. Finishing earns it; so does
## skipping out at the second-to-last step, by which point the setup is done. Skipping before
## that does not, and the bar stays clear rather than offering a chain the player never built.
## Reset per run in start(), read by MiniQuest.is_available().
var setup_reached: bool = false
## How close to the end counts as "the setup is done" — the second-to-last step.
const SETUP_STEPS_FROM_END := 2
var hard_gate: bool = false  # true while a lock_panel step is up: Esc is swallowed (world_map)
var _steps: Array = []
var _index: int = -1
var _entry_turn: int = 0     # turn number when the current step was entered (for turn-gated beats)
var _market_sales_seen: int = 0 # completed sales observed during this tutorial run
var _entry_market_sales_seen: int = 0 # snapshot at the active step's entry
var _market_sale_counts: Dictionary = {} # "tile|good|turns" -> completed arrivals
var _entry_market_sale_counts: Dictionary = {}
var _overlay_released_for_step: bool = false
var _integration_branch: String = "" # "glass" or "aluminium", chosen at the fork
var _overlay: Control = null
var _route_highlight: Node2D = null
var _poll: Timer = null
var _wired: bool = false
var _saved_focus_dur := 0.3  # camera's UI pan duration before the tutorial slowed it
var _visited := 0            # steps actually ENTERED, so the counter follows the branch taken
var _active_board_tiles: Array = []


func _ready() -> void:
	SaveLoad.match_loaded.connect(_on_match_loaded)


func _on_match_loaded() -> void:
	# Only tutorial matches; a no-op for every normal new game / load.
	if not bool(MatchState.ruleset.get("tutorial_enabled", false)):
		return
	# match_loaded fires mid-build (before world_map.build_complete and before the HUD
	# is ready); defer the real start until the world exists.
	call_deferred("_boot")


func _boot() -> void:
	await _await_world_ready()
	_start()


func _await_world_ready() -> void:
	while true:
		var wm := get_tree().current_scene
		# `== true` (not bool(...)): during the scene transition current_scene may briefly be
		# the loading screen / null, whose get("build_complete") is null — bool(null) throws.
		if wm != null and wm.get("build_complete") == true:
			return
		await get_tree().process_frame


# ── Lifecycle ──────────────────────────────────────────────────────────────────────

func _start() -> void:
	# Reset any prior run (autoload persists across scene changes).
	_teardown_overlay()
	setup_reached = false
	_steps = TutorialSteps.steps()
	if _steps.is_empty():
		return
	# This opening sandbox event is deliberately absent from tutorial-started matches,
	# even after the final hand-off re-enables normal decisions. Calling this on boot
	# also repairs saves made part-way through a tutorial before that rule existed.
	DecisionState.suppress_family_friend_for_match()
	active = true
	_index = -1
	_visited = 0
	_market_sales_seen = 0
	_market_sale_counts.clear()
	_integration_branch = ""
	_active_board_tiles = TutorialSteps.CAPITAL_BOARD_TILES.duplicate()
	_prepare_capital_motor_lesson()
	_ensure_overlay()
	_wire_signals()
	_ensure_poll()
	_apply_board_bounds()
	_enter(0)


func _enter(i: int) -> void:
	# A held rail guide normally clears one tile at a time as the player builds. Also
	# clear it when a debug jump or tutorial exit leaves the step early.
	if _index >= 0 and _index < _steps.size() and i != _index:
		var previous_id := str((_steps[_index] as Dictionary).get("id", ""))
		if previous_id == "capital_rail_build":
			_clear_held_route_highlight()
	_index = i
	if _index < 0 or _index >= _steps.size():
		_finish()
		return
	if _index >= _steps.size() - SETUP_STEPS_FROM_END:
		setup_reached = true
	_entry_turn = TurnManager.current_turn
	_entry_market_sales_seen = _market_sales_seen
	_entry_market_sale_counts = _market_sale_counts.duplicate()
	_overlay_released_for_step = false
	var step: Dictionary = _steps[_index]
	var board_tiles: Array = step.get("board_tiles", [])
	if not board_tiles.is_empty():
		_active_board_tiles = board_tiles.duplicate()
		_apply_board_bounds()
	step_changed.emit(str(step.get("id", "")))
	hard_gate = bool(step.get("lock_panel", false))   # swallow Esc while this step's panel is up
	_run_setup(step.get("setup", []))
	_watch_overlay_release(step)
	_apply_step_camera(step)
	if bool(step.get("count_step", true)):
		_visited += 1
	if _overlay != null:
		# Path-aware numbering: the tutorial BRANCHES (glass vs aluminium) and the arms are
		# different lengths, so a raw index/_steps.size() jumped (…41, then 55 of 55) and
		# over-counted steps the player will never see.
		_overlay.show_step(_display_step(step), maxi(0, _visited - 1), _visited + _remaining_after(_index))
	# A step whose event already fired before entry should still complete.
	call_deferred("_maybe_advance")


func _advance() -> void:
	# A step may reroute to a labelled step (branch reconvergence); else go to the next.
	var goto := ""
	if _index >= 0 and _index < _steps.size():
		goto = str((_steps[_index] as Dictionary).get("goto", ""))
	if goto != "":
		_jump_to(goto)
	else:
		_enter(_index + 1)


func _jump_to(id: String) -> void:
	for i in _steps.size():
		if str((_steps[i] as Dictionary).get("id", "")) == id:
			_enter(i)
			return
	_finish()   # unknown target: end gracefully rather than soft-lock


## A small number of cards vary by the route the player actually took. Keep the authored
## branches in tutorial_steps.gd, then resolve them only for display so all completion
## and navigation data remains exactly the same.
func _display_step(step: Dictionary) -> Dictionary:
	var displayed := step
	var variants: Dictionary = step.get("body_by_branch", {})
	if not variants.is_empty():
		var branch := _integration_branch
		if branch == "":
			branch = _detect_integration_branch()
		var body := str(variants.get(branch, step.get("body", "")))
		if body != "":
			displayed = step.duplicate(true)
			displayed["body"] = body
	if str(step.get("body_dynamic", "")) == "last_turn_profit":
		if displayed == step:
			displayed = step.duplicate(true)
		var profit_text := _last_turn_profit_text()
		displayed["title"] = str(displayed.get("title", "")).replace("{profit}", profit_text)
		displayed["body"] = str(displayed.get("body", "")).replace("{profit}", profit_text)
	return displayed


func _last_turn_profit_text() -> String:
	var summary: Dictionary = Production.last_turn_summary
	var profit := float(summary.get("money_in", 0.0)) - float(summary.get("money_out", 0.0))
	return "£%.2f %s" % [absf(profit), "profit" if profit >= 0.0 else "loss"]


func _detect_integration_branch() -> String:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if not MatchState.is_player_owned(inst):
			continue
		match str(inst.get("recipe_id", "")):
			"r_054": return "glass"
			"r_232": return "aluminium"
	return ""


## Steps still to come after `i` on the path actually being walked. Follows `goto` links;
## at an unresolved `choices` step it takes the LONGEST arm, so the displayed total only
## ever shrinks as the player commits and never jumps upward mid-run.
func _remaining_after(i: int) -> int:
	if i < 0 or i >= _steps.size():
		return 0
	var current_weight := 1 if bool((_steps[i] as Dictionary).get("count_step", true)) else 0
	return maxi(0, _path_length_from(i, 0) - current_weight)


func _path_length_from(i: int, depth: int) -> int:
	# depth guard: a malformed goto cycle must not hang the counter.
	if i < 0 or i >= _steps.size() or depth > _steps.size():
		return 0
	var step: Dictionary = _steps[i]
	var best := 0
	var choices: Array = step.get("choices", [])
	if not choices.is_empty():
		for c in choices:
			if not (c is Dictionary):
				continue
			best = maxi(best, _path_length_from(_index_of_id(str((c as Dictionary).get("goto", ""))), depth + 1))
	else:
		var goto := str(step.get("goto", ""))
		var nxt := _index_of_id(goto) if goto != "" else i + 1
		best = _path_length_from(nxt, depth + 1)
	var weight := 1 if bool(step.get("count_step", true)) else 0
	return weight + best


func _index_of_id(id: String) -> int:
	if id == "":
		return -1
	for i in _steps.size():
		if str((_steps[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


func _finish() -> void:
	active = false
	hard_gate = false
	_index = -1
	step_changed.emit("")
	if _poll != null:
		_poll.stop()
	_restore_camera()
	_teardown_overlay()


## The final End tutorial button is deliberately the only exit that changes the match.
## Every earlier Skip tutorial link merely closes the coach and leaves tutorial rules on.
func _complete_tutorial() -> void:
	PlayerProfile.mark_tutorial_completed()
	# Belt-and-braces for legacy in-progress saves: consume the event before changing
	# tutorial_enabled, otherwise a turn-30 hand-off immediately draws its turn-3 offer.
	DecisionState.suppress_family_friend_for_match()
	MatchState.ruleset["tutorial_enabled"] = false
	MatchState.fake_money_this_turn = 0.0
	MatchState.add_money(200.0 - float(MatchState.money))
	# Tutorial turns do not become a head start on the campaign's victory tracks.
	VictoryState.reset()
	_finish()


# ── Setup dispatch (drives via existing sim intent signals / API) ────────────────────

func _run_setup(actions: Array) -> void:
	for a in actions:
		if not (a is Dictionary):
			continue
		match str(a.get("action", "")):
			"focus_tile":
				MatchState.focus_tile_requested.emit(str(a.get("tile", "")))
			"open_buildings_market":
				MatchState.buildings_market_for_tile_requested.emit(str(a.get("tile", "")))
			"focus_building_on_tile":
				var iid := _building_iid_on_tile(str(a.get("tile", "")), str(a.get("building_id", "")))
				if iid != "":
					MatchState.focus_building_requested.emit(iid)
			"focus_any_building_on_tile":
				var iid := _building_iid_on_tile(str(a.get("tile", "")), str(a.get("building_id", "")), false)
				if iid != "":
					MatchState.focus_building_requested.emit(iid)
			"focus_tile_stock":
				# Open the tile panel on its Stock tab (so the Sell-Surplus toggle exists),
				# and pre-skip the first-time confirm dialog so one click enables it.
				load("res://scripts/tile_info_panel_v2.gd").set("_skip_sell_surplus_confirm", true)
				MatchState.focus_tile_requested.emit(str(a.get("tile", "")))
				var tp := _find("TileInfoPanel")
				if tp != null and tp.has_method("_select_tab"):
					tp._select_tab("stock")
			"open_encyclopedia":
				var so := _find("SearchOverlay")
				if so != null and so.has_method("open_encyclopedia"):
					so.open_encyclopedia()
			"close_search":
				var s := _find("SearchOverlay")
				if s != null and s is Control:
					(s as Control).hide()
			"enter_build":
				BuildMode.enter_build_mode(str(a.get("building_id", "")), str(a.get("recipe_id", "")))
			"enter_infra":
				BuildMode.enter_infrastructure_mode(str(a.get("infra", "")))
			"exit_build_mode":
				BuildMode.exit_build_mode()
			"open_survey":
				MapMode.set_sentinel_mode(MapMode.Mode.SURVEYING, MapMode.SURVEYING_SENTINEL)
			"open_logistics":
				if MapMode.current_mode != MapMode.Mode.LOGISTICS:
					MapMode.set_sentinel_mode(MapMode.Mode.LOGISTICS, MapMode.LOGISTICS_SENTINEL)
			"clear_mapmode":
				MapMode.clear_all()
			"close_building_detail":
				var scene := get_tree().current_scene
				var bdp := scene.find_child("BuildingDetailPanelV2", true, false) if scene != null else null
				if bdp != null and bdp is Control:
					(bdp as Control).hide()
			"close_market_panel":
				# The tutorial's Buy button changes ownership directly, so it does not pass
				# through MarketPanel's row-selection handler (which normally hides the panel).
				var market_panel := _find("MarketPanel")
				if market_panel is Control:
					PanelStack.remove(market_panel as Control)
					(market_panel as Control).hide()
			"close_tile_panel":
				var tile_panel := _find("TileInfoPanel")
				if tile_panel != null and tile_panel is Control:
					(tile_panel as Control).hide()
			"close_construct":
				for cp_name in ["ConstructPanel", "ConstructPanelV2"]:
					var cp := _find(cp_name)
					if cp != null and cp is Control:
						(cp as Control).hide()
			"expand_construct_building":
				# Reveal a building's recipe rows in construct panel v2 so the next
				# step can spotlight a specific RecipeRow_<id>.
				var cpv2 := _find("ConstructPanelV2")
				if cpv2 != null and cpv2.has_method("expand_building"):
					cpv2.expand_building(str(a.get("building_id", "")))
			"close_empire_view":
				# Force the empire view shut when the tutorial moves on — a player who
				# opened it with Tab but didn't press Tab again to return would otherwise
				# be stuck looking at the graph while the next card talks about the map.
				var ev := _find("EmpireView")
				if ev is Control and (ev as Control).visible:
					(ev as Control).visible = false
			"close_sourcing":
				# Dismiss the "buy materials / cancel" construction dialog without building.
				var md := _find("ConstructionMissingDialog")
				if md != null and md is Control:
					(md as Control).hide()
			"open_money_panel":
				# The balance widget opens the TREASURY MINI-PANEL (a flyout), not the full
				# Money panel — money_widget.pressed runs _toggle_fly("treasury"). Press the
				# widget only when the flyout is not already up, since it toggles.
				var fly := _find("Flyout_treasury")
				if not (fly is Control and (fly as Control).is_visible_in_tree()):
					var mw := _find("MoneyWidget")
					if mw is BaseButton:
						(mw as BaseButton).pressed.emit()
			"open_money_transport":
				var money_panel := _find("MoneyPanel")
				if money_panel != null and money_panel.has_method("open_transport_breakdown"):
					money_panel.open_transport_breakdown()
			"close_money_panel":
				# Close both money surfaces. Most tutorial steps use the treasury flyout,
				# while the transport lesson opens the full Balance panel.
				var fly := _find("Flyout_treasury")
				if fly is Control and (fly as Control).is_visible_in_tree():
					var mw := _find("MoneyWidget")
					if mw is BaseButton:
						(mw as BaseButton).pressed.emit()
				var money_panel := _find("MoneyPanel")
				if money_panel != null and money_panel.has_method("close_for_tutorial"):
					money_panel.close_for_tutorial()
				elif money_panel is Control:
					(money_panel as Control).hide()
			"restock_motor_inputs":
				_restock_motor_inputs(int(a.get("turns", 1)))
			"clear_capital_motor_shipments":
				_clear_capital_motor_sale_shipments()
			"seed_motor_shipment":
				_seed_motor_shipment(str(a.get("id", "shipment")), int(a.get("turns", 1)))
			"install_tutorial_roads":
				var world := get_tree().current_scene
				if world != null and world.has_method("tutorial_install_infrastructure"):
					world.tutorial_install_infrastructure(TutorialSteps.CAPITAL_ROUTE_TILES, "roads")
			"install_tutorial_rail_port_terminal":
				var world := get_tree().current_scene
				if world != null and world.has_method("tutorial_install_infrastructure"):
					world.tutorial_install_infrastructure([TutorialSteps.CAPITAL_PORT_TILE], "rails")
			"transfer_capital_transport_infrastructure":
				_transfer_capital_transport_infrastructure_to_general()
			"flash_capital_route":
				_ensure_route_highlight()
				if _route_highlight != null and _route_highlight.has_method("flash"):
					_route_highlight.flash(TutorialSteps.CAPITAL_ROUTE_TILES)
			"flash_tiles":
				_ensure_route_highlight()
				if _route_highlight != null and _route_highlight.has_method("flash"):
					var flash_tiles: Array = a.get("tiles", [])
					var pulse_seconds := float(a.get("pulse_seconds", 0.5))
					var pulse_count := int(a.get("pulse_count", 3))
					var flash_color := Color.WHITE if str(a.get("color", "amber")) == "white" \
						else TutorialRouteHighlightScript.AMBER
					_route_highlight.flash(flash_tiles, pulse_seconds, pulse_count, flash_color)
			"hold_capital_rail_tiles":
				_ensure_route_highlight()
				if _route_highlight != null and _route_highlight.has_method("hold"):
					_route_highlight.hold(TutorialSteps.CAPITAL_RAIL_BUILD_TILES)
			"spawn_steel_demo":
				_spawn_steel_demo()
			"handoff_from_capital_lesson":
				_handoff_from_capital_lesson()
			"route_building_outputs_to_market":
				_route_building_outputs_to_market(
					str(a.get("tile", "")), str(a.get("building_id", "")))
			"route_building_outputs_to_tile":
				_route_building_outputs_to_tile(
					str(a.get("tile", "")), str(a.get("building_id", "")),
					str(a.get("destination", "")))
			"open_people_panel":
				# PeoplePanel is created lazily by bottom_menu on the first People press, so
				# it cannot be spotlit until that has happened at least once.
				var pp := _find("PeoplePanel")
				if not (pp is Control and (pp as Control).is_visible_in_tree()):
					var pb := _find("PeopleButton")
					if pb is BaseButton:
						(pb as BaseButton).pressed.emit()
			"open_research":
				# Open the Research panel by pressing its bottom-bar button — but only if it's not
				# already open (the button toggles, so re-running setup mustn't close it).
				var rp := _find("ResearchPanel")
				if not (rp is Control and (rp as Control).is_visible_in_tree()):
					var tb := _find("TechButton")
					if tb is BaseButton:
						(tb as BaseButton).pressed.emit()
			"close_research":
				var rp := _find("ResearchPanel")
				if rp is Control:
					(rp as Control).hide()
			"research_choose_free_unlock":
				var rp := _find("ResearchPanel")
				if rp != null and rp.has_method("begin_free_unlock_choice"):
					rp.begin_free_unlock_choice()
			"show_construct_for_good":
				MatchState.show_construct_for_good.emit(str(a.get("good", "")))
			"toast":
				MatchState.request_toast(str(a.get("text", "")), str(a.get("kind", "info")))
			_:
				pass


## Find a named node anywhere in the live scene (nil if absent).
func _find(node_name: String) -> Node:
	var scene := get_tree().current_scene
	return scene.find_child(node_name, true, false) if scene != null else null


## Some guided fields should be highlighted only until the player has found them.  Hook
## the LineEdit signal as well as polling, so the dim is released on the first character
## rather than up to a quarter-second later.
func _watch_overlay_release(step: Dictionary) -> void:
	var release_when: Dictionary = step.get("release_overlay_when", {})
	if str(release_when.get("kind", "")) != "research_search_nonempty":
		return
	var search := _find("ResearchSearchInput")
	if search is LineEdit and not (search as LineEdit).text_changed.is_connected(_on_tutorial_search_changed):
		(search as LineEdit).text_changed.connect(_on_tutorial_search_changed)


func _on_tutorial_search_changed(_text: String) -> void:
	_maybe_advance()


## Resolve the player-owned building instance on a tile (for focus/spotlight setup).
func _building_iid_on_tile(tile_id: String, building_id: String, player_only: bool = true) -> String:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) != tile_id:
			continue
		if building_id != "" and str(inst.get("building_id", "")) != building_id:
			continue
		if not player_only or MatchState.is_player_owned(inst):
			return str(iid)
	return ""


## Make the opening example self-contained: its five authored input batches can
## never trigger market top-ups, and one already-dispatched shipment starts five
## turns from Capital Port so the first profit lands on the fifth End Turn rather
## than requiring a sixth turn after the factory's first production pass.
func _prepare_capital_motor_lesson() -> void:
	var instance_id := _building_iid_on_tile(TutorialSteps.MOTOR_TILE, "b_007")
	if instance_id == "":
		return
	var recipe := Catalog.get_recipe("r_009")
	for input in recipe.get("inputs", []):
		MatchState.set_input_tile_only(instance_id, str(input.get("good_id", "")), true)
	for output in recipe.get("outputs", []):
		MatchState.route_output_to_market(instance_id, str(output.get("good_id", "")))
	_seed_motor_shipment("opening", TutorialSteps.CAPITAL_ROUTE_TILES.size() - 1)


func _seed_motor_shipment(seed_id: String, turns: int) -> void:
	if seed_id == "" or turns <= 0:
		return
	for shipment in MatchState.get_pending_transport_shipments():
		if str(shipment.get("tutorial_seed_id", "")) == seed_id:
			return
	var motor := Catalog.get_good_by_internal_name("motor")
	var motor_id := str(motor.get("id", ""))
	if motor_id == "":
		return
	var recipe := Catalog.get_recipe("r_009")
	var qty := 28
	for output in recipe.get("outputs", []):
		if str(output.get("good_id", "")) == motor_id:
			qty = int(output.get("qty", qty))
	var unit_price := MarketState.get_sale_price(motor_id)
	var route := TransportService.route(TutorialSteps.MOTOR_TILE, TutorialSteps.CAPITAL_PORT_TILE, motor_id)
	var path: Array = route.get("path", [])
	var tiles: Array = route.get("tiles", [])
	var legs: Array = route.get("legs", [])
	# The no-infrastructure fallback has no router path. Author the exact shortest
	# path for that first shipment; road/rail seeds use the router's range-aware
	# waypoint path so their pentagon advances 2/4 tiles per turn on screen.
	if path.is_empty() or int(route.get("turns", -1)) != turns:
		path = TutorialSteps.CAPITAL_ROUTE_TILES.duplicate()
		tiles = TutorialSteps.CAPITAL_ROUTE_TILES.duplicate()
		legs = []
	var sale_record := {
		"tile_id": TutorialSteps.MOTOR_TILE,
		"items": [{"good_id": motor_id, "qty": qty, "revenue": unit_price * float(qty)}],
		"total_qty": qty,
		"total_revenue": unit_price * float(qty),
		"transport_turns": turns,
	}
	MatchState.queue_transport_shipment({
		"tutorial_seed": true,
		"tutorial_seed_id": seed_id,
		"is_sale": true,
		"source_tile": TutorialSteps.MOTOR_TILE,
		"destination_tile": TutorialSteps.CAPITAL_PORT_TILE,
		"sale_record": sale_record,
		"tile_distance": TutorialSteps.CAPITAL_ROUTE_TILES.size() - 1,
		"transport_turns": turns,
		"turns_remaining": turns,
		"path": path,
		"tiles": tiles,
		"legs": legs,
	})


func _restock_motor_inputs(turns: int) -> void:
	if turns <= 0:
		return
	var instance_id := _building_iid_on_tile(TutorialSteps.MOTOR_TILE, "b_007")
	if instance_id == "":
		return
	for input in Catalog.get_recipe("r_009").get("inputs", []):
		var good_id := str(input.get("good_id", ""))
		var qty := int(input.get("qty", 0)) * turns
		MatchState.set_input_tile_only(instance_id, good_id, true)
		Stockpile.add(TutorialSteps.MOTOR_TILE, good_id, qty)


## Each transport lesson starts one representative 28-unit shipment. Meanwhile the
## live factory continues producing another 28 every turn. If the previous, slower
## pipeline is left in flight when the route becomes faster, old and new batches reach
## the port together and the Sales ledger correctly reports 56 (or more) in that turn.
## Retire only this demonstration factory's motor sales between speed lessons so one
## arrival remains one recipe batch; unrelated freight and non-sale moves are untouched.
func _clear_capital_motor_sale_shipments() -> void:
	var motor_id := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	if motor_id == "":
		return
	var remaining: Array = []
	var removed := false
	for raw_shipment in MatchState.pending_transport_shipments:
		var shipment: Dictionary = raw_shipment
		var is_capital_motor_sale := bool(shipment.get("is_sale", false)) \
			and str(shipment.get("source_tile", "")) == TutorialSteps.MOTOR_TILE
		if is_capital_motor_sale:
			is_capital_motor_sale = false
			for raw_item in (shipment.get("sale_record", {}) as Dictionary).get("items", []):
				if str((raw_item as Dictionary).get("good_id", "")) == motor_id:
					is_capital_motor_sale = true
					break
		if is_capital_motor_sale:
			removed = true
			continue
		remaining.append(shipment)
	MatchState.pending_transport_shipments = remaining
	if removed:
		MatchState.transport_shipments_changed.emit()


func _route_building_outputs_to_market(tile_id: String, building_id: String) -> void:
	var instance_id := _building_iid_on_tile(tile_id, building_id)
	if instance_id == "":
		return
	var building: Dictionary = MatchState.get_building(instance_id)
	for output in Catalog.get_recipe(str(building.get("recipe_id", ""))).get("outputs", []):
		var good_id := str((output as Dictionary).get("good_id", ""))
		if good_id != "":
			MatchState.route_output_to_market(instance_id, good_id)


func _route_building_outputs_to_tile(tile_id: String, building_id: String, destination: String) -> void:
	var instance_id := _building_iid_on_tile(tile_id, building_id)
	if instance_id == "" or destination == "":
		return
	var building: Dictionary = MatchState.get_building(instance_id)
	for output in Catalog.get_recipe(str(building.get("recipe_id", ""))).get("outputs", []):
		var good_id := str((output as Dictionary).get("good_id", ""))
		if good_id != "":
			MatchState.set_output_stockpile_destination(instance_id, destination, good_id)


func _spawn_steel_demo() -> void:
	var world := get_tree().current_scene
	if world == null or not world.has_method("tutorial_spawn_building"):
		return
	var instance_id: String = world.tutorial_spawn_building("b_008", "r_076", TutorialSteps.STEEL_TILE)
	if instance_id == "":
		return
	for input in Catalog.get_recipe("r_076").get("inputs", []):
		var good_id := str(input.get("good_id", ""))
		MatchState.set_input_tile_only(instance_id, good_id, true)
		if Stockpile.get_at_tile(TutorialSteps.STEEL_TILE, good_id) <= 0:
			Stockpile.add(TutorialSteps.STEEL_TILE, good_id, int(input.get("qty", 0)))


## Roads revealed by the tutorial and the two rail terminals are already tile-backed
## general infrastructure, with no MatchState instance or player upkeep. The four rail
## sections the player constructs do create ordinary building instances, however. Move
## every road/rail instance on the opening board to the same neutral owner once built so
## the route remains available without distorting the later factory-profit lessons.
func _transfer_capital_transport_infrastructure_to_general(instance_id: String = "") -> void:
	var candidates: Array = [instance_id] if instance_id != "" else MatchState.buildings.keys()
	for raw_instance_id in candidates:
		var iid := str(raw_instance_id)
		var inst: Dictionary = MatchState.get_building(iid)
		if inst.is_empty() or not TutorialSteps.CAPITAL_BOARD_TILES.has(str(inst.get("tile_id", ""))):
			continue
		var building_data: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		if str(building_data.get("internal_name", "")) not in ["roads", "rails"]:
			continue
		MatchState.set_building_owner(iid, "tile_data")


func _on_tutorial_construction_completed(instance_id: String, tile_id: String) -> void:
	if not active or not TutorialSteps.CAPITAL_BOARD_TILES.has(tile_id):
		return
	_transfer_capital_transport_infrastructure_to_general(instance_id)


## The Capital transport sequence is a self-contained demonstration, not the start of
## the player's lasting empire. Transfer both demo factories to an NPC, cancel their
## unclaimed market revenue and clear their working stock before the west-coast lesson.
## The fixed cash reset happens last, so neither scripted sale value affects the next beat.
func _handoff_from_capital_lesson() -> void:
	# A second pass makes the handoff safe for debug jumps and old mid-tutorial saves whose
	# rail completed before the immediate completion hook existed.
	_transfer_capital_transport_infrastructure_to_general()
	var demo_tiles: Array = [TutorialSteps.MOTOR_TILE, TutorialSteps.STEEL_TILE]
	var demo_buildings := [
		{"tile": TutorialSteps.MOTOR_TILE, "building_id": "b_007"},
		{"tile": TutorialSteps.STEEL_TILE, "building_id": "b_008"},
	]
	for demo in demo_buildings:
		var instance_id := _building_iid_on_tile(
			str((demo as Dictionary).get("tile", "")),
			str((demo as Dictionary).get("building_id", "")))
		if instance_id != "":
			MatchState.set_building_owner(instance_id, MatchState.SOLD_TO_OWNER)

	# Goods already dispatched by either demo would otherwise keep paying the player
	# during the glass lesson even though the source factory no longer belongs to them.
	var remaining_shipments: Array = []
	var removed_shipment := false
	for shipment in MatchState.pending_transport_shipments:
		var sale: Dictionary = shipment
		if bool(sale.get("is_sale", false)) and str(sale.get("source_tile", "")) in demo_tiles:
			removed_shipment = true
			continue
		remaining_shipments.append(shipment)
	MatchState.pending_transport_shipments = remaining_shipments
	if removed_shipment:
		MatchState.transport_shipments_changed.emit()

	# Transfer the demonstrations' remaining inventory with them and disarm any tile-level
	# sale order that could independently turn that stock back into player revenue.
	for tile_id in demo_tiles:
		var tile := str(tile_id)
		for good_id in Stockpile.get_tile_totals(tile):
			Stockpile.consume(tile, str(good_id), Stockpile.get_at_tile(tile, str(good_id)))
		MatchState.clear_stockpile_market_sale_queue(tile)
		MatchState.disable_sell_surplus(tile)
		for good_id in (MatchState.auto_sell_goods.get(tile, {}) as Dictionary).keys().duplicate():
			MatchState.disable_auto_sell_good(tile, str(good_id))
		MatchState.auto_sell_keep.erase(tile)
		MatchState.auto_sell_impact.erase(tile)
		MatchState.sales_by_tile.erase(tile)

	# Remove the old transport lesson from all "last turn" surfaces before announcing
	# the fresh balance; otherwise the top bar can still show motor profit per turn.
	Production.last_turn_summary.clear()
	var money_panel := _find("MoneyPanel")
	if money_panel != null and money_panel.has_method("reset_for_tutorial_handoff"):
		money_panel.reset_for_tutorial_handoff()
	MatchState.fake_money_this_turn = 0.0
	MatchState.money = float(TutorialSteps.WEST_COAST_HANDOFF_CASH)
	MatchState.money_changed.emit(MatchState.money)


func _ensure_route_highlight() -> void:
	if _route_highlight != null and is_instance_valid(_route_highlight):
		return
	var hex_map := get_tree().get_first_node_in_group("hex_map")
	if hex_map == null:
		return
	_route_highlight = TutorialRouteHighlightScript.new()
	_route_highlight.name = "TutorialRouteHighlight"
	hex_map.add_child(_route_highlight)


func _clear_held_route_highlight() -> void:
	if _route_highlight != null and is_instance_valid(_route_highlight) \
			and _route_highlight.has_method("clear_hold"):
		_route_highlight.clear_hold()


# ── Detection (wake + state-verified poll) ───────────────────────────────────────────

func _wire_signals() -> void:
	if _wired:
		return
	_wired = true   # persists across tutorials; every wake signal just re-evaluates the step
	var wake := func(_a = null, _b = null, _c = null, _d = null, _e = null) -> void: _maybe_advance()
	MatchState.building_owner_changed.connect(wake)
	MatchState.building_added.connect(wake)
	MatchState.tile_survey_completed.connect(wake)
	MatchState.transport_shipments_changed.connect(wake)
	Construction.construction_started.connect(wake)
	Construction.construction_completed.connect(_on_tutorial_construction_completed)
	Construction.construction_completed.connect(wake)
	if Construction.has_signal("materials_ordered"):
		Construction.materials_ordered.connect(wake)
	TurnManager.turn_advanced.connect(wake)
	CostSolver.costs_updated.connect(wake)
	Production.turn_processed.connect(wake)
	Stockpile.stockpile_changed.connect(wake)
	# A shipment reaching the market is a different event from merely ending a turn.
	# Keep this count in the tutorial rather than MatchState: it is only a lesson
	# baseline, and therefore does not need to be persisted in normal game saves.
	MatchState.stockpile_market_sale_completed.connect(_on_market_sale_completed)
	if BuildMode.has_signal("infrastructure_attempted"):
		BuildMode.infrastructure_attempted.connect(_on_infrastructure_attempted)
	if MatchState.has_signal("sell_surplus_changed"):
		MatchState.sell_surplus_changed.connect(wake)


func _on_market_sale_completed(sale: Dictionary) -> void:
	_market_sales_seen += 1
	var tile_id := str(sale.get("tile_id", ""))
	var turns := int(sale.get("transport_turns", 0))
	for item in sale.get("items", []):
		var key := _sale_key(tile_id, str(item.get("good_id", "")), turns)
		_market_sale_counts[key] = int(_market_sale_counts.get(key, 0)) + 1
	_maybe_advance()


func _on_infrastructure_attempted(infra_type: String, tile_id: String) -> void:
	if active and infra_type == "rails" and TutorialSteps.CAPITAL_RAIL_BUILD_TILES.has(tile_id) \
			and _index >= 0 and _index < _steps.size() \
			and str((_steps[_index] as Dictionary).get("id", "")) == "capital_rail_build" \
			and _route_highlight != null and is_instance_valid(_route_highlight) \
			and _route_highlight.has_method("dismiss"):
		_route_highlight.dismiss(tile_id)
	_maybe_advance()


func _sale_key(tile_id: String, good_id: String, turns: int) -> String:
	return "%s|%s|%d" % [tile_id, good_id, turns]


func _ensure_poll() -> void:
	if _poll == null:
		_poll = Timer.new()
		_poll.wait_time = POLL_INTERVAL
		_poll.timeout.connect(_maybe_advance)
		add_child(_poll)
	_poll.start()


func _maybe_advance() -> void:
	if not active or _index < 0 or _index >= _steps.size():
		return
	var step: Dictionary = _steps[_index]
	var released := _release_overlay_if_ready(step)
	var decide: Dictionary = (step.get("done", {}) as Dictionary).get("decide", {})
	# Evaluate completion first (info steps have no decide and advance via Next).
	if not decide.is_empty():
		var done := false
		if str(decide.get("kind", "")) == "turn_advanced":
			done = TurnManager.current_turn > _entry_turn   # needs engine state
		elif str(decide.get("kind", "")) == "turns_advanced":
			done = TurnManager.current_turn >= _entry_turn + maxi(1, int(decide.get("count", 1)))
		elif str(decide.get("kind", "")) == "market_sale_completed_since_entry":
			done = _market_sales_seen > _entry_market_sales_seen
		elif str(decide.get("kind", "")) == "filtered_market_sale_since_entry":
			var good := Catalog.get_good_by_internal_name(str(decide.get("good", "")))
			var key := _sale_key(str(decide.get("tile", "")), str(good.get("id", "")), int(decide.get("turns", 0)))
			done = int(_market_sale_counts.get(key, 0)) > int(_entry_market_sale_counts.get(key, 0))
		else:
			done = TutorialDetectors.poll(decide)
		if done:
			_advance()
			return
	# Not yet done: a locked step keeps its panel open (re-opens it if the player
	# closed it — the mouse is already blocked outside the spotlight, Esc is swallowed).
	if bool(step.get("lock_panel", false)) and not released:
		_ensure_locked_panel_open(step)


func _release_overlay_if_ready(step: Dictionary) -> bool:
	if _overlay_released_for_step:
		return true
	var release_when: Dictionary = step.get("release_overlay_when", {})
	if release_when.is_empty() or not TutorialDetectors.poll(release_when):
		return false
	_overlay_released_for_step = true
	if _overlay != null and is_instance_valid(_overlay) and _overlay.has_method("release_spotlight_and_dim"):
		_overlay.release_spotlight_and_dim()
	return true


func _ensure_locked_panel_open(step: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var kind := str((step.get("spotlight", {}) as Dictionary).get("kind", "none"))
	if kind != "node_path" and kind != "node_name":
		return   # only panel/card spotlights are "keep open"
	if str(step.get("mode", "")) == "annotate":
		# Annotation steps have several callouts rather than one spotlight hole. Without
		# this check their panel is "reopened" on every poll, toggling a flyout rapidly.
		var annotated := _find(str((step.get("spotlight", {}) as Dictionary).get("ref", "")))
		if annotated is Control and (annotated as Control).is_visible_in_tree():
			return
	elif _overlay.spotlight_ok():
		return
	_run_setup(step.get("setup", []))     # re-open the panel
	# refresh_spotlight, NOT show_step: show_step rebuilds the card, so on a step whose
	# panel had been replaced (opening Balance from the treasury flyout) this ran every
	# 0.25s poll and destroyed the Next button the player was clicking.
	_overlay.refresh_spotlight()


# ── Board confinement (camera clamp) ─────────────────────────────────────────────────

## How long a tutorial step's recentring pan takes. Matches the coach overlay's own
## settle (CoachOverlay.REVEAL_DUR) so the camera and the spotlight land together —
## at the stock 0.3s the map snapped while the light was still travelling, which is
## most of what made each step read as jerky.
const FOCUS_PAN_DUR := 1.0

func _apply_board_bounds() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam == null or not cam.has_method("set_bounds_rect"):
		return
	if "ui_focus_duration" in cam:
		_saved_focus_dur = float(cam.ui_focus_duration)
		cam.ui_focus_duration = FOCUS_PAN_DUR
	var rect := _board_world_rect()
	if rect.has_area():
		cam.set_bounds_rect(rect)


func _restore_camera() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam == null:
		return
	if "ui_focus_duration" in cam:
		cam.ui_focus_duration = _saved_focus_dur   # snappy again for bell/briefing jumps
	if cam.has_method("clear_bounds_rect"):
		cam.clear_bounds_rect()


func _board_world_rect() -> Rect2:
	return _rect_for_tiles(_active_board_tiles, 160.0)   # ~1.5 tiles of margin around the pocket


## World-space bounding rect of a set of tiles, grown by `grow` px of margin.
func _rect_for_tiles(tiles: Array, grow: float) -> Rect2:
	var hex_map := get_tree().get_first_node_in_group("hex_map")
	if hex_map == null or not hex_map.has_method("id_to_coord"):
		return Rect2()
	var rect := Rect2()
	var seeded := false
	for tile_id in tiles:
		var coord: Vector2i = hex_map.id_to_coord(tile_id)
		if coord == Vector2i(-1, -1):
			continue
		var cell: Vector2i = hex_map.map_coord_for_tile_coord(coord)
		var world: Vector2 = hex_map.to_global(hex_map.map_to_local(cell))
		if not seeded:
			rect = Rect2(world, Vector2.ZERO)
			seeded = true
		else:
			rect = rect.expand(world)
	if not seeded:
		return Rect2()
	return rect.grow(grow)


## Optional per-step camera override: a step may loosen the board clamp (e.g. the
## shipment-route step wants the whole port tile + surroundings visible at max zoom-out).
## Steps WITHOUT a "camera" key leave the clamp as-is (the default bounds set at start),
## so panel-focused steps never get their camera yanked. A looser clamp simply persists
## for the remaining steps — harmless, since later steps recenter via their focus setup
## and off-board interaction is still blocked by tile_allowed().
func _apply_step_camera(step: Dictionary) -> void:
	var cfg = step.get("camera", {})
	if not (cfg is Dictionary) or (cfg as Dictionary).is_empty():
		return
	var cam := get_tree().get_first_node_in_group("camera")
	if cam == null or not cam.has_method("set_bounds_rect"):
		return
	var tiles: Array = (cfg as Dictionary).get("tiles", TutorialSteps.CAMERA_TILES)
	var grow: float = float((cfg as Dictionary).get("grow", 160.0))
	var rect := _rect_for_tiles(tiles, grow)
	if rect.has_area():
		cam.set_bounds_rect(rect)


## True when `tile_id` is part of the tutorial board — the world_map input guard uses
## this to reject off-script map interaction while the tutorial is active.
func tile_allowed(tile_id: String) -> bool:
	return _active_board_tiles.has(tile_id)


## Capital Port remains an NPC trade gateway throughout the tutorial. The player
## starts with enough cash to buy it, so every port-purchase surface uses this guard.
func port_purchase_disabled(building_id: String) -> bool:
	return active and building_id == "b_004"


# ── Overlay plumbing ─────────────────────────────────────────────────────────────────

func _ensure_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		return
	_overlay = CoachOverlayScript.new()
	_overlay.name = "CoachOverlay"
	_overlay.advanced.connect(_on_overlay_advanced)
	_overlay.skipped.connect(_on_overlay_skipped)
	_overlay.choice_made.connect(_on_overlay_choice)
	var host := _overlay_host()
	if host != null:
		host.add_child(_overlay)


func _overlay_host() -> Node:
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var ui := scene.get_node_or_null("UILayer")
	return ui if ui != null else scene


func _teardown_overlay() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	if _route_highlight != null and is_instance_valid(_route_highlight):
		_route_highlight.queue_free()
	_route_highlight = null


func _on_overlay_advanced() -> void:
	# Next pressed on an info card.
	if active and _index >= 0 and _index < _steps.size():
		if str((_steps[_index] as Dictionary).get("id", "")) == "integration_done":
			_complete_tutorial()
		else:
			_advance()


func _on_overlay_skipped() -> void:
	_finish()


func _on_overlay_choice(goto: String) -> void:
	if active and goto != "":
		if goto == "build_glass_open":
			_integration_branch = "glass"
		elif goto == "build_alu_open":
			_integration_branch = "aluminium"
		_jump_to(goto)


## Exposes the current tutorial beat to UI that must enforce a time-sensitive action
## order (for example, reading an advisor's bonus before enabling their hire button).
func is_active_step(id: String) -> bool:
	return active and _index >= 0 and _index < _steps.size() \
		and str((_steps[_index] as Dictionary).get("id", "")) == id
