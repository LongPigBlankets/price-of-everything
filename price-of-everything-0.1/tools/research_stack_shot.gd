extends Node
## Dev tool: several research unlocks landing on one turn now pop ONE FLYOUT EACH, stacked
## under the notch, instead of collapsing into a single "N research unlocked" banner.
## Needs a window:
##   <godot> --path . res://tools/research_stack_shot.tscn --quit-after 120000

const NAMES := ["Electric Arc Furnace", "In-Pit Crushing", "Catalytic Reforming",
	"Hydrogen Combustion Turbines", "Continuous Casting", "Vacuum Distillation"]


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(160)
	get_viewport().set_disable_input(true)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	TurnManager.current_turn = 12
	TurnManager.turn_advanced.emit(12)
	await _settle(20)
	# ONE unlock: the owner reports a single research showing up twice.
	_unlock(NAMES[0])
	await _settle(60)
	await _shot("user://poe_research_stack.png")
	# ...and the overflow case, where the tail folds into one "+N more".
	TurnManager.current_turn = 13
	TurnManager.turn_advanced.emit(13)
	await _settle(20)
	for name in NAMES:
		_unlock(name)
	await _settle(60)
	await _shot("user://poe_research_overflow.png")
	get_tree().quit(0)


func _unlock(research_name: String) -> void:
	EventScheduler.emit_event({
		"kind": "research_unlocked", "severity": "info",
		"title": "Research unlocked — %s" % research_name,
		"research_name": research_name,
		"research_reward": "A new recipe route is available.",
		"research_condition": "",
		"body": "", "source": "test",
		"persistent": false, "auto_dismiss_turns": 3,
	})


func _shot(path: String) -> void:
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png(path)
	print("[RSTACK] ", path)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
