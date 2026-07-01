extends Node2D
# Dev-only: render the People panel (Labour tab) to a PNG so the new labour
# indicator's placement can be eyeballed. Run WINDOWED (not --headless):
#   Godot --path . res://tools/people_shot.tscn --quit-after 600
var _frame := 0
var _panel

func _ready() -> void:
	MatchState.reset()
	TurnManager.current_turn = 20
	# A few player-owned buildings so the labour indicator has real numbers.
	MatchState.add_building("b_007", "r_009", "tile_5_10", MatchState.LOCAL_PLAYER, "shot_a1")
	MatchState.add_building("b_009", "", "tile_5_10", MatchState.LOCAL_PLAYER, "shot_a2")
	MatchState.add_building("b_001", "r_001", "tile_6_8", MatchState.LOCAL_PLAYER, "shot_a3")
	MatchState.add_building("b_010", "", "tile_5_10", MatchState.LOCAL_PLAYER, "shot_a4")
	# Slider up + a creeping pensions policy so the trend arrow lights up.
	MatchState.set_labour_multiplier(1.2)
	MatchState.set_workforce_policy_enabled(MatchState.WORKFORCE_POLICY_GENEROUS_PENSIONS, true)
	for i in 12:
		MatchState.tick_workforce_policies()

	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = load("res://scripts/people_panel.gd").new()
	layer.add_child(_panel)
	await get_tree().process_frame
	_panel.position = Vector2(40, 30)
	_panel.call("_refresh_labour_indicator")
	await get_tree().process_frame

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://people_shot.png")
		print("SAVED people_shot.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
