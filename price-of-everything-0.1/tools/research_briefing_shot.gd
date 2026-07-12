extends Node
## Dev tool: verify the aggregated-research feature end to end.
##   /tmp/poe_research_notch.png — notch badge (60px) + count pill when >1 unlock
##   /tmp/poe_research_panel.png — the single "N research unlocked" briefing update
##                                 (name / bold-green reward / condition per entry)
## Needs a window: <godot> --path . res://tools/research_briefing_shot.tscn --quit-after 1500

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Land on a turn first so the unlocks fall inside the briefing's [t-1, t] window.
	TurnManager.current_turn = 14
	TurnManager.turn_advanced.emit(14)
	await _settle(10)

	# Two research unlocks this turn, each carrying name / reward / condition — the
	# shape event_scheduler now stamps onto each research_unlocked event.
	EventScheduler.emit_event({
		"kind": "research_unlocked", "severity": "info",
		"title": "Unlocked: Electric Arc Furnace", "body": "A new research entry is available.",
		"source": "test", "persistent": false, "auto_dismiss_turns": 5,
		"research_name": "Electric Arc Furnace",
		"research_reward": "Unlocks new recipes: EAF Steel Making (24 Steel).",
		"research_condition": "Produce steel 500 units",
	})
	EventScheduler.emit_event({
		"kind": "research_unlocked", "severity": "info",
		"title": "Unlocked: Deep Coal Cutting", "body": "A new research entry is available.",
		"source": "test", "persistent": false, "auto_dismiss_turns": 5,
		"research_name": "Deep Coal Cutting",
		"research_reward": "Increases coal mining output by 20% permanently.",
		"research_condition": "Run coal_mine for 20 turns",
	})
	await _settle(30)
	await _shot("/tmp/poe_research_notch.png")

	# Open the briefing panel on the aggregated research update. TurnBriefing owns
	# the panel on its own CanvasLayer; select the item, then expand.
	TurnBriefing.set("_select_on_expand", "research_unlocked_agg")
	TurnBriefing.expand()
	await _settle(24)
	await _shot("/tmp/poe_research_panel.png")

	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
