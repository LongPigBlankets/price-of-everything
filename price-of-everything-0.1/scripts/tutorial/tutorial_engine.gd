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

const POLL_INTERVAL := 0.25   # s; re-evaluates the active step's decide predicate

var active: bool = false
var hard_gate: bool = false  # true while a lock_panel step is up: Esc is swallowed (world_map)
var _steps: Array = []
var _index: int = -1
var _entry_turn: int = 0     # turn number when the current step was entered (for turn-gated beats)
var _overlay: Control = null
var _poll: Timer = null
var _wired: bool = false


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
	_steps = TutorialSteps.steps()
	if _steps.is_empty():
		return
	active = true
	_index = -1
	_ensure_overlay()
	_wire_signals()
	_ensure_poll()
	_apply_board_bounds()
	_enter(0)


func _enter(i: int) -> void:
	_index = i
	if _index < 0 or _index >= _steps.size():
		_finish()
		return
	_entry_turn = TurnManager.current_turn
	var step: Dictionary = _steps[_index]
	# Reaching the terminal step = the player genuinely finished the tutorial (an early
	# Skip goes straight to _finish and never enters this step, so it doesn't count).
	if str(step.get("id", "")) == "integration_done":
		PlayerProfile.mark_tutorial_completed()
	hard_gate = bool(step.get("lock_panel", false))   # swallow Esc while this step's panel is up
	_run_setup(step.get("setup", []))
	_apply_step_camera(step)
	if _overlay != null:
		_overlay.show_step(step, _index, _steps.size())
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


func _finish() -> void:
	active = false
	hard_gate = false
	_index = -1
	if _poll != null:
		_poll.stop()
	_restore_camera()
	_teardown_overlay()


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
			"close_construct":
				var cp := _find("ConstructPanel")
				if cp != null and cp is Control:
					(cp as Control).hide()
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
			"open_research":
				# Open the Research panel by pressing its bottom-bar button — but only if it's not
				# already open (the button toggles, so re-running setup mustn't close it).
				var rp := _find("ResearchPanel")
				if not (rp is Control and (rp as Control).is_visible_in_tree()):
					var tb := _find("TechButton")
					if tb is BaseButton:
						(tb as BaseButton).pressed.emit()
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


## Resolve the player-owned building instance on a tile (for focus/spotlight setup).
func _building_iid_on_tile(tile_id: String, building_id: String) -> String:
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) != tile_id:
			continue
		if building_id != "" and str(inst.get("building_id", "")) != building_id:
			continue
		if MatchState.is_player_owned(inst):
			return str(iid)
	return ""


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
	Construction.construction_completed.connect(wake)
	if Construction.has_signal("materials_ordered"):
		Construction.materials_ordered.connect(wake)
	TurnManager.turn_advanced.connect(wake)
	CostSolver.costs_updated.connect(wake)
	Production.turn_processed.connect(wake)
	if BuildMode.has_signal("infrastructure_attempted"):
		BuildMode.infrastructure_attempted.connect(wake)
	if MatchState.has_signal("sell_surplus_changed"):
		MatchState.sell_surplus_changed.connect(wake)


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
	var decide: Dictionary = (step.get("done", {}) as Dictionary).get("decide", {})
	# Evaluate completion first (info steps have no decide and advance via Next).
	if not decide.is_empty():
		var done := false
		if str(decide.get("kind", "")) == "turn_advanced":
			done = TurnManager.current_turn > _entry_turn   # needs engine state
		else:
			done = TutorialDetectors.poll(decide)
		if done:
			_advance()
			return
	# Not yet done: a locked step keeps its panel open (re-opens it if the player
	# closed it — the mouse is already blocked outside the spotlight, Esc is swallowed).
	if bool(step.get("lock_panel", false)):
		_ensure_locked_panel_open(step)


func _ensure_locked_panel_open(step: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var kind := str((step.get("spotlight", {}) as Dictionary).get("kind", "none"))
	if kind != "node_path" and kind != "node_name":
		return   # only panel/card spotlights are "keep open"
	if _overlay.spotlight_ok():
		return
	_run_setup(step.get("setup", []))            # re-open the panel
	_overlay.show_step(step, _index, _steps.size())   # re-resolve the spotlight


# ── Board confinement (camera clamp) ─────────────────────────────────────────────────

func _apply_board_bounds() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam == null or not cam.has_method("set_bounds_rect"):
		return
	var rect := _board_world_rect()
	if rect.has_area():
		cam.set_bounds_rect(rect)


func _restore_camera() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null and cam.has_method("clear_bounds_rect"):
		cam.clear_bounds_rect()


func _board_world_rect() -> Rect2:
	return _rect_for_tiles(TutorialSteps.CAMERA_TILES, 160.0)   # ~1.5 tiles of margin around the pocket


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
	return TutorialSteps.BOARD_TILES.has(tile_id)


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


func _on_overlay_advanced() -> void:
	# Next pressed on an info card.
	if active and _index >= 0 and _index < _steps.size():
		_advance()


func _on_overlay_skipped() -> void:
	_finish()


func _on_overlay_choice(goto: String) -> void:
	if active and goto != "":
		_jump_to(goto)
