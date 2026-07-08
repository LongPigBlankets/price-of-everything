extends RefCounted
## Tutorial step-completion detectors — the ONLY unit-tested surface of the tutorial
## engine. Detection is state-verified: a sim signal only WAKES a check; these pure
## predicates DECIDE it by re-reading authoritative live state. This avoids the known
## footguns (building_placed re-fires for NPC/on-load; money_changed is absolute, not
## a delta), so a step still completes if its event fired before the step was entered.
##
## A `decide` predicate is a plain Dictionary: {"kind": <string>, ...params}. `poll`
## returns true when the predicate is currently satisfied against the sim autoloads.
## Referenced via preload (no class_name) so headless runs resolve it. Wave 1 ships one
## kind; later waves extend the vocabulary (tile_has_infra, survey_status, ...).

const TutorialSteps := preload("res://scripts/tutorial/tutorial_steps.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")

## Evaluate a `decide` predicate against live sim state. Unknown kinds return false
## (a step with an unrecognised predicate never auto-advances — it is not skipped).
static func poll(decide: Dictionary) -> bool:
	match str(decide.get("kind", "")):
		"building_owned_on_tile":
			return _building_owned_on_tile(
				str(decide.get("tile", "")),
				str(decide.get("building_id", "")))
		"building_or_project_on_tile":
			return _building_or_project_on_tile(
				str(decide.get("tile", "")),
				str(decide.get("building_id", "")))
		"board_has_infra":
			return _board_has_infra(str(decide.get("infra", "")))
		"tile_has_infra":
			return Catalog.tile_has_infrastructure(str(decide.get("tile", "")), str(decide.get("infra", "")))
		"tile_cabled_or_ordered":
			# True the instant the player CLICKS the Cables cell (a b_006 construction
			# project appears) OR once it finishes (tile_has_infra). Advancing on the
			# order avoids a soft-lock: the locked spotlight blocks End Turn, so we can't
			# wait for the 1-turn cable build to complete before advancing.
			return _tile_cabled_or_ordered(str(decide.get("tile", "")))
		"tile_infra_or_ordered":
			# Parameterised sibling of tile_cabled_or_ordered: true the instant the player
			# orders `infra` on `tile` (a construction project of `building_id` appears) OR
			# once it finishes. Used by the reinforced-pipe lesson (reinf_pipes / b_018).
			return _tile_infra_or_ordered(
				str(decide.get("tile", "")),
				str(decide.get("infra", "")),
				str(decide.get("building_id", "")))
		"tile_surveyed":
			return MatchState.survey_status(str(decide.get("tile", ""))) == "surveyed"
		"building_running_on_tile":
			return _building_running_on_tile(str(decide.get("tile", "")), str(decide.get("building_id", "")))
		"building_recipe_on_tile":
			# True when a player building on the tile currently runs `recipe_id` — used to detect a
			# completed recipe change / retool (e.g. the glass furnace switched to r_054).
			return _building_recipe_on_tile(str(decide.get("tile", "")), str(decide.get("recipe_id", "")))
		"research_unlocked":
			return MatchState.is_unlocked(str(decide.get("title", "")))
		"in_mapmode":
			# Map by name (avoids hardcoding enum ints). Only logistics is used today.
			return str(decide.get("mode", "")) == "logistics" and MapMode.current_mode == MapMode.Mode.LOGISTICS
		"tile_panel_open":
			# True when the player has opened the tile panel on a specific tile (pan/zoom +
			# click). Poll-driven (no signal): the engine's 0.25s poll catches the click.
			return _tile_panel_showing(str(decide.get("tile", "")))
		"node_visible":
			return _node_visible(str(decide.get("ref", "")))
		"node_hidden":
			return not _node_visible(str(decide.get("ref", "")))
		"sell_surplus_on_tile":
			return MatchState.is_sell_surplus_enabled(str(decide.get("tile", "")))
		_:
			return false


## True when the tile info panel is open AND showing `tile_id` — i.e. the player panned/zoomed
## to that tile and clicked it. Reads the panel's live `_current_tile_id` (valid while visible).
static func _tile_panel_showing(tile_id: String) -> bool:
	if tile_id == "":
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	var p := tree.current_scene.find_child("TileInfoPanel", true, false)
	return p is Control and (p as Control).is_visible_in_tree() and str(p.get("_current_tile_id")) == tile_id


## True when a named Control exists in the scene and is visible (e.g. a panel opened).
static func _node_visible(node_name: String) -> bool:
	if node_name == "":
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	var n := tree.current_scene.find_child(node_name, true, false)
	return n is Control and (n as Control).is_visible_in_tree()


## True when the player's building of `building_id` on `tile_id` actually PRODUCED last
## turn (BuildingReadout.run_state == "running") — i.e. cabled, powered, inputs arrived.
## "restarting"/"stalled" don't count. Used to gate the "end turns until it runs" step.
static func _building_running_on_tile(tile_id: String, building_id: String) -> bool:
	if tile_id == "":
		return false
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) != tile_id:
			continue
		if building_id != "" and str(inst.get("building_id", "")) != building_id:
			continue
		if not MatchState.is_player_owned(inst):
			continue
		var recipe: Dictionary = Catalog.get_recipe(str(inst.get("recipe_id", "")))
		if BuildingReadout.run_state(inst, recipe, false) == "running":
			return true
	return false


## True when the player owns a building on `tile_id` currently running `recipe_id`. Used to
## detect a finished recipe swap (the retool completes and the building's recipe_id changes).
static func _building_recipe_on_tile(tile_id: String, recipe_id: String) -> bool:
	if tile_id == "" or recipe_id == "":
		return false
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) != tile_id:
			continue
		if str(inst.get("recipe_id", "")) == recipe_id and MatchState.is_player_owned(inst):
			return true
	return false


## True when the player has a built building OR an in-progress construction project of
## `building_id` on `tile_id` — so a "build here" step advances the moment the player
## places it, not turns later when construction finishes (friendlier pacing).
static func _building_or_project_on_tile(tile_id: String, building_id: String) -> bool:
	if _building_owned_on_tile(tile_id, building_id):
		return true
	for iid in Construction.construction_projects:
		var proj: Dictionary = Construction.construction_projects[iid]
		if str(proj.get("tile_id", "")) != tile_id:
			continue
		if building_id == "" or str(proj.get("building_id", "")) == building_id:
			return true
	return false


## True when the tile already has cables OR the player just ordered them (a b_006
## cables construction project on the tile — fires on the click that starts the build).
static func _tile_cabled_or_ordered(tile_id: String) -> bool:
	if tile_id == "":
		return false
	if Catalog.tile_has_infrastructure(tile_id, "cables"):
		return true
	for iid in Construction.construction_projects:
		var proj: Dictionary = Construction.construction_projects[iid]
		if str(proj.get("tile_id", "")) == tile_id and str(proj.get("building_id", "")) == "b_006":
			return true
	return false


## True when `tile_id` already carries `infra` OR the player just ordered it (a construction
## project of `building_id` on the tile — fires on the click that starts the build). Same
## advance-on-order rationale as _tile_cabled_or_ordered, generalised for the reinforced-pipe
## step (the locked spotlight blocks End Turn, so we can't wait for the build to complete).
static func _tile_infra_or_ordered(tile_id: String, infra: String, building_id: String) -> bool:
	if tile_id == "" or infra == "":
		return false
	if Catalog.tile_has_infrastructure(tile_id, infra):
		return true
	if building_id == "":
		return false
	for iid in Construction.construction_projects:
		var proj: Dictionary = Construction.construction_projects[iid]
		if str(proj.get("tile_id", "")) == tile_id and str(proj.get("building_id", "")) == building_id:
			return true
	return false


## True when any tutorial board tile carries the given infrastructure (cables/pipes/...).
static func _board_has_infra(infra: String) -> bool:
	if infra == "":
		return false
	for tile_id in TutorialSteps.BOARD_TILES:
		if Catalog.tile_has_infrastructure(str(tile_id), infra):
			return true
	return false


## True when the local player owns a building of `building_id` sitting on `tile_id`.
## Empty `building_id` matches any building. This is the state-verified check behind
## the "buy the factory" step — robust to building_owner_changed firing for other
## buildings, because it re-reads MatchState.buildings and ownership every time.
static func _building_owned_on_tile(tile_id: String, building_id: String) -> bool:
	if tile_id == "":
		return false
	for iid in MatchState.buildings:
		var inst: Dictionary = MatchState.buildings[iid]
		if str(inst.get("tile_id", "")) != tile_id:
			continue
		if building_id != "" and str(inst.get("building_id", "")) != building_id:
			continue
		if MatchState.is_player_owned(inst):
			return true
	return false
