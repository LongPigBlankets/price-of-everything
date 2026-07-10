extends Node
## Windowed screenshots of the two negative-cash features:
##   /tmp/poe_bankruptcy_strip.png — the "Bankruptcy imminent" strip under the money widget
##   /tmp/poe_bridge_popup.png     — the auto-bridge loan popup
##   "$GODOT_BIN" --path . res://tools/bridge_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Drive the runway (cash + borrowing room) under £100 so the strip shows.
	# (The auto-bridge popup is retired — it now surfaces as a Turn Briefing info item;
	# see tools/briefing_shot.tscn for that surface.)
	MatchState.money = -40.0
	MatchState.money_changed.emit(MatchState.money)
	await _settle(6)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_bankruptcy_strip.png")
	print("[bridge_shot] wrote /tmp/poe_bankruptcy_strip.png")
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
