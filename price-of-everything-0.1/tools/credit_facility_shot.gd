extends Node2D
## Renders the credit-facility offer with real turn arithmetic.
##   Godot --path . res://tools/credit_facility_shot.tscn --quit-after 600
func _ready() -> void:
	get_window().size = Vector2i(760, 460)
	await get_tree().process_frame
	MatchState.reset()
	TurnManager.current_turn = 12
	var layer := CanvasLayer.new()
	add_child(layer)
	var back := ColorRect.new()
	back.color = Color("#08111c")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)
	var dlg = load("res://scripts/building_credit_dialog.gd").new()
	layer.add_child(dlg)
	await get_tree().process_frame
	dlg.open("inst_demo", "Furnace")
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://credit_facility_shot.png")
	print("SAVED credit_facility_shot.png")
	get_tree().quit()
