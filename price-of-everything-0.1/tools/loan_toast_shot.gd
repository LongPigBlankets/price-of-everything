extends Node
## Windowed screenshot of the auto-bridge loan toast: drives cash negative (fires the
## "Cash is in the red" warning toast), then runs the auto-bridge, which should add a
## RED toast directly under it — "Loan taken to cover the deficit: £X, £Y loan capacity
## left." Saves /tmp/poe_loan_toast.png. Needs a window (NOT --headless):
##   "$GODOT_BIN" --path . res://tools/loan_toast_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	# Cross cash below zero → the existing bottom-centre "Cash is in the red" toast.
	MatchState.money = -60.0
	MatchState.money_changed.emit(MatchState.money)
	await _settle(6)

	# Run the auto-bridge: takes a loan against remaining capacity and (new) pushes the
	# red "Loan taken to cover the deficit" toast under the cash-negative one.
	SolvencyState._auto_bridge_negative_cash()
	await _settle(8)

	get_viewport().get_texture().get_image().save_png("/tmp/poe_loan_toast.png")
	print("[loan_toast_shot] wrote /tmp/poe_loan_toast.png  (money now £%.2f)" % MatchState.money)
	get_tree().quit(0)

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
