extends Node
## Dev tool: verify the briefing notch (middle of the top bar) shows the research
## microscope on the turn a research unlock lands. Screenshots:
##   /tmp/poe_topbar_research_before.png — bell only, no research this turn
##   /tmp/poe_topbar_research_after.png  — microscope leads the notch
## Needs a window:  <godot> --path . res://tools/topbar_research_shot.tscn --quit-after 1200

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Land on a turn FIRST so the unlock falls inside the briefing's [t-1, t] window.
	TurnManager.current_turn = 12
	TurnManager.turn_advanced.emit(12)
	await _settle(20)
	await _shot("/tmp/poe_topbar_research_before.png")

	# A research unlock this turn → research_unlocked bell event → briefing item →
	# the notch reveals the microscope.
	EventScheduler.emit_event({
		"kind": "research_unlocked", "severity": "info",
		"title": "Research unlocked — Electric Arc Furnace",
		"body": "A new recipe route is available.", "source": "test",
		"persistent": false, "auto_dismiss_turns": 3,
	})
	await _settle(30)
	await _shot("/tmp/poe_topbar_research_after.png")

	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw   # capture the freshly-rendered frame
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
