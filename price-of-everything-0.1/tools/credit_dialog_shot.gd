extends Node2D
# Dev-only: render the missing-materials dialog with the Chief Investment
# "Build on credit" 4th option visible.
#   Godot --path . res://tools/credit_dialog_shot.tscn --quit-after 600
var _frame := 0

func _ready() -> void:
	get_window().size = Vector2i(720, 520)
	MatchState.reset()
	MatchState.recruited_advisor_ids = ["alexandra"]
	MatchState.permanent_advisor_ids = ["alexandra"]
	MatchState.assign_advisor_to_seat("chief_investment", "alexandra")
	MatchState.advisors_changed.emit()

	var layer := CanvasLayer.new()
	add_child(layer)
	var dialog = load("res://scripts/construction_missing_dialog.gd").new()
	layer.add_child(dialog)
	await get_tree().process_frame

	var bid := ""
	var missing := {}
	for b in Catalog.all_buildings():
		var reqs: Dictionary = Construction.requirements_for(str(b.get("id", "")))
		if not reqs.is_empty():
			bid = str(b.get("id", ""))
			for g in reqs:
				missing[str(g)] = int(reqs[g])
			break
	dialog.open(bid, "", "tile_5_5", missing)
	await get_tree().process_frame
	await get_tree().process_frame

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://credit_dialog_shot.png")
		print("SAVED credit_dialog_shot.png")
		get_tree().quit()
