extends Node
## Captures of the phase 2 surfaces of docs/pacing-labour-mining-licensing-spec.md: a building hiring below 70%,
## one running short staffed, a construction project hiring, an NPC building under offer and Andrew Keeler's
## turn 3 offer with its Expansion Director choice.
##   STAFFING_SHOT_DIR=<dir> AGENT_GODOT_WINDOW=1 godot --path . res://tools/staffing_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes NN_<state>_full.png (the whole screen, half size) and NN_<state>_panel.png (the panel) into the directory.

const TILE := "tile_9_9"

var _game: Node
var _dir := ""
var _n := 0


func _ready() -> void:
	_dir = OS.get_environment("STAFFING_SHOT_DIR")
	if _dir == "":
		_dir = ProjectSettings.globalize_path("res://artifacts/staffing_p2")
	DirAccess.make_dir_recursive_absolute(_dir)
	_game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	LabourState.satisfaction = 0.0
	MatchState.money = 50000.0
	BuildingState.tile_land_owned[TILE] = 400

	# 1-2. A furnace still hiring, then running short staffed.
	var fid: String = BuildingState.add_building("b_002", "r_005", TILE, MatchState.LOCAL_PLAYER, "staffshot_furnace")
	var furnace: Dictionary = BuildingState.buildings[fid]
	furnace["staff_fill"] = 0.5
	_game._open_building_detail(furnace)
	await _settle(20)
	await _capture("hiring_below_70")
	furnace["staff_fill"] = 0.85
	_game._hide_building_detail()
	await _settle(6)
	_game._open_building_detail(furnace)
	await _settle(20)
	await _capture("running_short_staffed")
	_game._hide_building_detail()
	await _settle(6)

	# 3. A factory under construction, two turns of hiring in.
	var reqs: Dictionary = Construction.requirements_for("b_007")
	for gid in reqs:
		Stockpile.add(TILE, str(gid), int(reqs[gid]))
	var pid := Construction.start_on_tile("b_007", "r_056", TILE)
	Construction.tick_turn()
	Construction.tick_turn()
	_game._open_building_detail(Construction.construction_projects[pid])
	await _settle(20)
	await _capture("construction_hiring")
	_game._hide_building_detail()
	await _settle(6)

	# 4. An NPC works the player has bought, closing.
	var npc := _npc_production_building()
	if not npc.is_empty():
		var offer := MatchState.offer_for_building(str(npc.instance_id))
		print("[staff_shot] offer: %s" % str(offer))
		_game._open_building_detail(npc)
		await _settle(20)
		await _capture("under_offer")
		_game._hide_building_detail()
		await _settle(6)

	# 5. Andrew Keeler's offer, now with three chairs.
	DecisionState.enabled = true
	print("[staff_shot] draw family_friend -> '%s'" % DecisionState.force_draw("family_friend"))
	await _settle(10)
	TurnBriefing.expand()
	await _settle(30)
	var card: Control = TurnBriefing._panel.get("_card") if TurnBriefing._panel != null else null
	await _capture("andrew_offer", card)
	print("[staff_shot] done")
	get_tree().quit(0)


func _npc_production_building() -> Dictionary:
	for b: Dictionary in BuildingState.buildings.values():
		if BuildingState.is_player_owned(b) or str(b.get("recipe_id", "")) == "":
			continue
		if str(Catalog.get_building(str(b.building_id)).get("category", "production")) == "infrastructure":
			continue
		if str(b.building_id) in ["b_007", "b_002"]:
			return b
	return {}


func _capture(state: String, panel: Control = null) -> void:
	_n += 1
	var stem := "%02d_%s" % [_n, state]
	await _settle(2)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var full := img.duplicate() as Image
	full.resize(img.get_width() / 2, img.get_height() / 2)
	full.save_png(_dir.path_join(stem + "_full.png"))
	if panel == null:
		panel = _game.find_child("BuildingDetailPanelV2", true, false) as Control
	if panel != null and panel.is_visible_in_tree():
		var g := panel.get_global_rect().grow(6)
		var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
		if r.size.x > 0 and r.size.y > 0:
			img.get_region(r).save_png(_dir.path_join(stem + "_panel.png"))
	print("[staff_shot] captured %s" % stem)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
