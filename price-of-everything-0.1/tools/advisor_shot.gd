extends Node2D
# Dev-only: render the advisor detail with the interactive pentagon + an expanded
# discipline info section.  Godot --path . res://tools/advisor_shot.tscn --quit-after 600
var _frame := 0
var _panel

func _ready() -> void:
	get_window().size = Vector2i(1060, 900)
	MatchState.reset()
	TurnManager.current_turn = 5
	MatchState.recruited_advisor_ids = ["vera", "tom", "rufus"]
	MatchState.permanent_advisor_ids = []
	MatchState.hire_advisor("vera")
	MatchState.assign_advisor_to_seat("cfo", "vera")
	MatchState.advisors_changed.emit()

	var layer := CanvasLayer.new()
	add_child(layer)
	_panel = load("res://scripts/people_panel.gd").new()
	layer.add_child(_panel)
	await get_tree().process_frame
	_panel.position = Vector2(20, 20)
	var tcs: Array = _panel.find_children("*", "TabContainer", true, false)
	if not tcs.is_empty():
		(tcs[0] as TabContainer).current_tab = 1
	_panel.call("_open_advisor_detail", MatchState.get_advisor("vera"))
	await get_tree().process_frame
	_panel.call("_on_discipline_label", "fin", "vera")   # expand the Finance info
	await get_tree().process_frame
	await get_tree().process_frame

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://advisor_shot.png")
		print("SAVED advisor_shot.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
