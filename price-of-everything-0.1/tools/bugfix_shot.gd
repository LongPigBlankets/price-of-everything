extends Node
## Windowed verification shots for the bug-fixes branch: the TVP land rail with the
## new right-edge "Owned" bracket (collapsed + expanded, with NPC buildings and a
## bought-off-NPC building at the top of the pile), and the Stockpile tab's
## "Stock Utilisation last turn" row.
##   <godot> --path . res://tools/bugfix_shot.tscn --quit-after 2500

const MAIN_SCENE := "res://scenes/main.tscn"
const TILE := "tile_25_6"   # hosts gold_arm NPC start buildings

var _main: Node = null
var _started := false
var _frames := 0


func _ready() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_main = packed.instantiate()
	add_child(_main)


func _process(_dt: float) -> void:
	if _started:
		return
	_frames += 1
	if _main != null and _main.get("build_complete") == true:
		_started = true
		_run()
	elif _frames > 3000:
		get_tree().quit(1)


func _run() -> void:
	var cam := get_tree().get_first_node_in_group("camera")
	if cam != null:
		cam.set("edge_pan_enabled", false)
	MatchState.money = 100000.0
	var td: Dictionary = _main._tile_data_by_id(TILE)
	var panel = _main.info_panel

	print("[SHOT] owned before: ", MatchState.get_tile_land_owned(TILE),
		" npc: ", MatchState.get_tile_npc_footprint(TILE))
	panel.show_tile(td)
	for _i in 6:
		await get_tree().process_frame
	_capture("bugfix_shot_no_land.png")   # owned 0 → no bracket

	MatchState.purchase_tile_land(TILE, 6)   # 60 owned → bracket appears
	# Buy one NPC building: it should move to the top of the pile + grant its land.
	for b in MatchState.get_buildings_on_tile(TILE):
		if not MatchState.is_player_owned(b):
			MatchState.set_building_owner(str(b.get("instance_id", "")), MatchState.LOCAL_PLAYER)
			break
	print("[SHOT] owned after: ", MatchState.get_tile_land_owned(TILE),
		" npc: ", MatchState.get_tile_npc_footprint(TILE))
	for _i in 6:
		await get_tree().process_frame
	_capture("bugfix_shot_collapsed.png")

	panel._toggle_rail()
	for _i in 6:
		await get_tree().process_frame
	_capture("bugfix_shot_expanded.png")

	panel._toggle_rail()
	panel._select_tab("stock")
	for _i in 6:
		await get_tree().process_frame
	_capture("bugfix_shot_stock.png")
	get_tree().quit(0)


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
