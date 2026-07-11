extends Node
## Windowed verification of the CTRL+click ship-quantity flow: the instruction row
## in the ship-to-tile mode, the green destination highlight + consumers panel, the
## BDP "Sending N to X / Sending M to tile stockpile" split, and the empire view's
## dashed (potential) vs absent (redirected) sell edges.
##   <godot> --path . res://tools/ship_qty_shot.tscn --quit-after 3000

const MAIN_SCENE := "res://scenes/main.tscn"
const FACTORY_TILE := "tile_5_9"
const FURNACE_TILE := "tile_5_7"

var _main: Node = null
var _started := false
var _frames := 0


func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	SaveLoad.prepare_new_game("res://data/starts/tutorial.json")
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
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
	# Own the window factory (the glass consumer) + build a player glass furnace.
	for iid in MatchState.tile_buildings.get(FACTORY_TILE, []):
		if str(MatchState.get_building(str(iid)).get("building_id", "")) == "b_007":
			MatchState.set_building_owner(str(iid), MatchState.LOCAL_PLAYER)
	var furnace_iid := MatchState.add_building("b_002", "r_053", FURNACE_TILE)
	var glass_gid := ""
	for o in Catalog.get_recipe("r_053").get("outputs", []):
		glass_gid = str((o as Dictionary).get("good_id", ""))
		break
	print("[SHOT] furnace=", furnace_iid, " glass=", glass_gid)

	# 1) Enter the ship-to-tile mode: instruction row + tinted map.
	MatchState.begin_output_stockpile_selection(furnace_iid, glass_gid)
	await _settle()
	_capture("ship_qty_mode.png")

	# 2) CTRL+click the factory tile: green highlight + consumers panel.
	var terrain = _main.get_node("%TerrainLayer")
	var tile_data: Dictionary = {}
	for coord in terrain.tiles:
		if str((terrain.tiles[coord] as Dictionary).get("id", "")) == FACTORY_TILE:
			tile_data = terrain.tiles[coord]
	terrain.end_stockpile_destination_selection()
	terrain.stockpile_destination_selected.emit(tile_data, true)
	await _settle()
	_capture("ship_qty_panel.png")

	# 3) Confirm 10/turn → BDP shows the split.
	var panel = _main.find_child("ShipQuantityPanel", true, false)
	if panel != null:
		panel._spin.value = 10
		panel._close(true)
	await _settle()
	print("[SHOT] cap=", MatchState.get_output_ship_quantity(furnace_iid, glass_gid),
		" dest=", MatchState.get_output_stockpile_destination(furnace_iid, glass_gid))
	MatchState.focus_building_requested.emit(furnace_iid)
	await _settle()
	_capture("ship_qty_bdp.png")

	# 4) Empire view: furnace redirected (no port edge), factory default (dashed edge).
	var ev := _main.find_child("EmpireView", true, false)
	if ev != null:
		ev.call("toggle")
		await _settle()
		_capture("ship_qty_empire.png")
	get_tree().quit(0)


func _settle() -> void:
	for _i in 12:
		await get_tree().process_frame


func _capture(fname: String) -> void:
	var out := ProjectSettings.globalize_path("res://" + fname)
	get_viewport().get_texture().get_image().save_png(out)
	print("saved ", out)
