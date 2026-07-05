extends Node
## Dev tool: verification shots for the improvements-to-ui branch.
##   1. Port dockhouse glyph (pan to Stoneshore Docks, zoomed in)
##   2. Money panel Sales tab (seeded sales history)
##   3. TVP stockpile standing-order controls
## Run WINDOWED (not --headless):
##   <godot> --path . res://tools/ui_improvements_shot.tscn --quit-after 900

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(40)

	# 1. Pan to the Stoneshore port tile and zoom in for the dockhouse. Wait out
	# the whole map build first — the post-load camera configure + intro zoom
	# would otherwise override the pan.
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		# The mouse idles at the window corner in scripted runs — edge pan would
		# fight (and cancel) the focus tween every frame.
		cam.edge_pan_enabled = false
		cam._target_zoom = Vector2.ONE * cam.zoom_max * 0.7
		await _settle(30)   # let the zoom settle so bounds clamping can't recentre
		cam.pan_to_tile("tile_5_10", 0.05)
	await _settle(50)
	_shot("/tmp/poe_port_glyph.png")

	# 2. Money panel Sales tab with seeded per-good history.
	var money: Control = game.get_node("UILayer/HUD/HUDContent/MoneyPanel")
	if money != null:
		money.get("_sales_history").append({
			"goods": {"g_001": {"qty": 120, "revenue": 48.0}, "g_012": {"qty": 40, "revenue": 128.0},
				"g_030": {"qty": 12, "revenue": 96.5}},
			"power": 22.4,
		})
		money.show()
		var tabs: TabContainer = money.get_node("MarginContainer/ModalLayout/TabContainer")
		for i in range(tabs.get_tab_count()):
			if tabs.get_tab_title(i) == "Sales":
				tabs.current_tab = i
				break
		money.call("_queue_refresh")
		await _settle(12)
		_shot("/tmp/poe_sales_tab.png")
		money.hide()

	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
