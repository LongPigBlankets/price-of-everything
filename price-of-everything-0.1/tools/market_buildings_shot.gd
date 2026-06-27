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

	# Functional check: synthetic click on the first row should open the building detail panel
	# and hide the Market panel (mirrors the Building Ledger row click).
	if le != null:
		le.text = ""
		le.text_changed.emit("")
		await _settle(6)
	var body2: Control = null
	for sc in tab.find_children("*", "ScrollContainer", true, false):
		body2 = sc.get_child(0); break
	if body2 != null and body2.get_child_count() > 0:
		var row: Control = body2.get_child(0)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		row.gui_input.emit(ev)
		await _settle(10)
		var detail: Control = game.get_node_or_null("UILayer/HUD/HUDContent/BuildingDetailPanel")
		print("CLICK TEST: market.visible=%s detail.visible=%s" % [market.visible, detail != null and detail.visible])
		_shot("/tmp/poe_market_buildings_click.png")

	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
