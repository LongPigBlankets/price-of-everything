extends Node
## Dev tool: render the real game, open the Market panel, switch to the new "Buildings"
## (NPC buildings-for-sale) tab, and save PNGs for visual verification. Loading the full
## main.tscn also parse-checks market_panel.gd + building_market_panel.gd together with
## their autoloads. Needs a window (NOT --headless):
##   <godot> --path . res://tools/market_buildings_shot.tscn --quit-after 1500

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	get_window().size = Vector2i(1320, 1040)   # tall + wide enough to see the full panel
	await _settle(50)   # let the world boot + NPC start buildings seed synchronously

	var npc := 0
	for iid in MatchState.buildings:
		if not MatchState.is_player_owned(MatchState.buildings[iid]):
			npc += 1
	print("NPC buildings in world: ", npc)

	var market: Control = game.get_node_or_null("UILayer/HUD/HUDContent/MarketPanel")
	if market == null:
		push_error("MarketPanel not found")
		get_tree().quit(1)
		return
	market.show()
	await _settle(12)

	var tc: TabContainer = null
	for n in market.find_children("*", "TabContainer", true, false):
		tc = n
		break
	if tc == null:
		push_error("TabContainer not found in MarketPanel")
		get_tree().quit(1)
		return
	var idx := -1
	for i in tc.get_tab_count():
		if tc.get_tab_title(i) == "Buildings":
			idx = i
			break
	print("Buildings tab index: ", idx, " of ", tc.get_tab_count())
	if idx < 0:
		push_error("Buildings tab not found")
		get_tree().quit(1)
		return
	tc.current_tab = idx
	await _settle(40)   # the tab builds its hundreds of rows on first show

	_shot("/tmp/poe_market_buildings.png")

	# Search-filtered frame to prove the search works (matches output good / name / tile).
	var tab: Control = tc.get_tab_control(idx)
	var le: LineEdit = null
	for n in tab.find_children("*", "LineEdit", true, false):
		le = n
		break
	if le != null:
		le.text = "coal"
		le.text_changed.emit("coal")
		await _settle(10)
		_shot("/tmp/poe_market_buildings_search.png")

	if le != null:
		le.text = ""
		le.text_changed.emit("")
		await _settle(6)

	# Buy flow: press the first row's £ button → confirm dialog → ownership transfers + row drops.
	MatchState.money = 50000.0  # ensure affordable for the success case
	var money_before: float = MatchState.money
	var first_iid: String = str(tab._rows[0]["instance_id"]) if tab._rows.size() > 0 else ""
	var rows_before: int = tab._rows.size()
	var before_owned: bool = first_iid != "" and MatchState.is_player_owned(MatchState.buildings[first_iid])
	var row0: Control = tab._rows[0]["control"]
	var buy_btn: Button = null
	for b in row0.find_children("*", "Button", true, false):
		buy_btn = b; break
	if buy_btn != null:
		buy_btn.pressed.emit()
		await _settle(8)
		_shot("/tmp/poe_buy_dialog.png")
		var confirm_btn: Button = _find_buy_button(tab._dialog)
		if confirm_btn != null:
			confirm_btn.pressed.emit()
			await _settle(10)
		var now_owned: bool = MatchState.is_player_owned(MatchState.buildings[first_iid])
		print("BUY TEST: before_owned=%s now_owned=%s rows %d→%d money %.0f→%.0f" % [
			before_owned, now_owned, rows_before, tab._rows.size(), money_before, MatchState.money])

	# Insufficient-funds: drop money below the price, try to buy → no transfer + red toast on the left.
	MatchState.money = 100.0
	if tab._rows.size() > 0:
		var poor_iid: String = str(tab._rows[0]["instance_id"])
		var poor_btn: Button = null
		for b in (tab._rows[0]["control"] as Control).find_children("*", "Button", true, false):
			poor_btn = b; break
		if poor_btn != null:
			poor_btn.pressed.emit()
			await _settle(6)
			var cb: Button = _find_buy_button(tab._dialog)
			if cb != null:
				cb.pressed.emit()
				await _settle(8)
			var still_npc: bool = not MatchState.is_player_owned(MatchState.buildings[poor_iid])
			# Red insufficient-money toast now lives in the bottom-left success stack with the others.
			var stack: Control = game.get_node_or_null("UILayer/HUD/ToastLayer/SuccessStack")
			var stack_x: float = stack.global_position.x if stack != null else -1.0
			var red_toast := false
			if stack != null:
				for t in stack.get_children():
					for lbl in t.find_children("*", "Label", true, false):
						if str(lbl.text).begins_with("Not enough money to buy"):
							red_toast = true
			print("POOR TEST: still_npc=%s left_stack_x=%.0f red_toast_present=%s" % [still_npc, stack_x, red_toast])
			_shot("/tmp/poe_buy_insufficient.png")

	# Reactivity: open the building ledger; the just-bought building should be listed (player-owned).
	var ledger: Control = (load("res://scenes/building_ledger_panel.tscn") as PackedScene).instantiate()
	game.get_node("UILayer/HUD").add_child(ledger)
	await _settle(12)
	var found_in_ledger := false
	for entry in ledger._all_vms:
		if str(entry.get("instance_id", "")) == first_iid:
			found_in_ledger = true; break
	print("LEDGER TEST: bought building in player ledger = %s" % found_in_ledger)
	_shot("/tmp/poe_buy_ledger.png")

	# No-double check: right after a re-render, the body must hold exactly one row per shown
	# building (the old rows are detached synchronously, not left lingering for a frame).
	var expected := 0
	for entry in ledger._all_vms:
		if ledger._passes_filters(entry):
			expected += 1
	ledger._render()
	print("DOUBLE TEST: body_rows=%d expected=%d" % [ledger._body.get_child_count(), expected])

	get_tree().quit(0)

func _find_buy_button(dialog) -> Button:
	if dialog == null:
		return null
	for b in dialog.find_children("*", "Button", true, false):
		if str(b.text).begins_with("Buy for"):
			return b
	return null

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
