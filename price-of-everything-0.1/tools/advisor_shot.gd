extends Node2D
# Dev-only: render the People panel's advisor DETAIL view — the bonuses table (heading, and the
# green/red signed percentages) and the agenda beside it.
#   Godot --path . res://tools/advisor_shot.tscn --quit-after 600
# The old version drove people_panel._open_advisor_detail (legacy, since removed) and selected
# tab 1, which is Labour — it rendered the wrong tab with a half-built detail on top of it.
var _frame := 0
var _panel

func _ready() -> void:
	get_window().size = Vector2i(1280, 900)
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
	_panel.size = Vector2(1240, 860)
	var tcs: Array = _panel.find_children("*", "TabContainer", true, false)
	if not tcs.is_empty():
		(tcs[0] as TabContainer).current_tab = 0        # Advisors
	await get_tree().process_frame
	var councils: Array = _panel.find_children("*", "AdvisorCouncilTab", true, false)
	if councils.is_empty():
		print("[ADVISOR_SHOT] council tab not found"); get_tree().quit(1); return
	councils[0].call("_set_view", {"mode": "detail", "sel_id": "vera", "back": "roster"})
	await get_tree().process_frame
	await get_tree().process_frame
	var heading = councils[0].find_child("AdvisorBonusSection", true, false)
	print("[ADVISOR_SHOT] heading=%s size=%s colour=%s" % [
		("MISSING" if heading == null else '"%s"' % heading.text),
		("-" if heading == null else str(heading.get_theme_font_size("font_size"))),
		("-" if heading == null else heading.get_theme_color("font_color").to_html(false))])

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://advisor_shot.png")
		print("SAVED advisor_shot.png ", img.get_width(), "x", img.get_height())
		get_tree().quit()
