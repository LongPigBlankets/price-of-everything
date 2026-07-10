extends Node2D
## Windowed shot: the two new input-pipeline diagnostics in the expanded briefing.
## Low cash + remote market-fed factories (incl. a spliced input on tile_16_4),
## 2 turns, expand the briefing hub, save PNG.
##   Godot --path . res://tools/briefing_diag_shot.tscn --quit-after 900
var _frame := 0
var _done := false

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var wm = packed.instantiate()
	add_child(wm)
	for _i in 16:
		await get_tree().process_frame
	var terrain = wm.get_node("%TerrainLayer")
	var bv = wm.get_node("%BuildingVisuals")
	var specs := [["tile_15_5", "r_008"], ["tile_16_4", "r_009"], ["tile_16_4", "r_008"], ["tile_16_4", "r_009"]]
	for si in specs.size():
		var iid: String = MatchState.add_building("b_007", str(specs[si][1]), str(specs[si][0]), "player_1", "shot_%d" % si)
		bv.on_building_placed(str(specs[si][0]), "b_007", str(specs[si][1]), iid, terrain.id_to_coord(str(specs[si][0])))
	MatchState.money = 500.0
	for _t in 2:
		TurnManager.commit_turn()
		await TurnManager.turn_resolution_completed
	await get_tree().process_frame
	TurnBriefing.expand()
	for _i2 in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://briefing_diag.png")
	print("SAVED briefing_diag.png")
	get_tree().quit()
