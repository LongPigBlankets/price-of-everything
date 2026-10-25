extends RefCounted
## Step-completion detectors for the opening steps (Tutorial.start_opener). Detection is state-verified: a
## signal or the engine's poll only WAKES a check; these pure predicates DECIDE it by re-reading live state,
## so a step still completes if its event fired before the step was entered.
##
## A `decide` predicate is a plain Dictionary: {"kind": <string>, ...params}. `poll` returns true when the
## predicate is currently satisfied. The engine answers "turn_advanced" itself (it needs the entry turn).
## Referenced via preload (no class_name) so headless runs resolve it.

## Evaluate a `decide` predicate against live state. Unknown kinds return false (a step with an
## unrecognised predicate never auto-advances — it is not skipped).
static func poll(decide: Dictionary) -> bool:
	match str(decide.get("kind", "")):
		"own_buildings_shown":
			# The player has found their buildings: the tile panel is open on a tile where they own one,
			# or the Building Ledger is open.
			return _own_buildings_shown()
		"node_visible":
			return _node_visible(str(decide.get("ref", "")))
		"building_detail_open":
			return _building_detail_open(
				str(decide.get("tile", "")),
				str(decide.get("building_id", "")),
				str(decide.get("recipe_id", "")))
		_:
			return false


static func _own_buildings_shown() -> bool:
	if _node_visible("BuildingLedgerPanel"):
		return true
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	var p := tree.current_scene.find_child("TileInfoPanel", true, false)
	if not (p is Control and (p as Control).is_visible_in_tree()):
		return false
	var tile := str(p.get("_current_tile_id"))
	for b: Dictionary in BuildingState.buildings.values():
		if str(b.get("tile_id", "")) == tile and BuildingState.is_player_owned(b):
			return true
	return false


## True when a named Control exists in the scene and is visible (e.g. a panel opened).
static func _node_visible(node_name: String) -> bool:
	if node_name == "":
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	var n := tree.current_scene.find_child(node_name, true, false)
	return n is Control and (n as Control).is_visible_in_tree()


static func _building_detail_open(tile_id: String, building_id: String, recipe_id: String) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.current_scene == null:
		return false
	var panel := tree.current_scene.find_child("BuildingDetailPanelV2", true, false)
	if not (panel is Control and (panel as Control).is_visible_in_tree()):
		return false
	var building: Dictionary = panel.get("_current_building")
	return (tile_id == "" or str(building.get("tile_id", "")) == tile_id) \
		and (building_id == "" or str(building.get("building_id", "")) == building_id) \
		and (recipe_id == "" or str(building.get("recipe_id", "")) == recipe_id)
