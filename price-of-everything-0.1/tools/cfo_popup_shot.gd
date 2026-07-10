extends Node
## Windowed screenshot of the one-time CFO tax-credit explainer (top-left portrait +
## dark gradient + copy) AND the collapsed briefing strip nested in the top bar. Seats a
## CFO, seeds a briefing item, then banks a credit (fires the explainer). Needs a window:
##   "$GODOT_BIN" --path . res://tools/cfo_popup_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Seed a briefing item so the collapsed strip shows in the top bar.
	EventScheduler.emit_event({
		"kind": "research_unlocked",
		"severity": "info",
		"title": "Research unlocked — Electric Arc Furnace",
		"body": "A new recipe route is available.",
		"source": "test",
		"persistent": false,
		"auto_dismiss_turns": 3,
	})
	await _settle(6)

	# Seat a CFO with a portrait, then bank the first tax credit → fires the explainer.
	MatchState.advisor_seats = {"cfo": "vera"}
	MatchState.cfo_tax_credit_intro_shown = false
	MatchState.cfo_bank_tax_credit(1200.0)
	await _settle(30)

	get_viewport().get_texture().get_image().save_png("/tmp/poe_cfo_popup.png")
	print("[cfo_popup_shot] wrote /tmp/poe_cfo_popup.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
