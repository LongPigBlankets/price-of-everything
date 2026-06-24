extends Node
## Dev tool: render the real game, place a solar farm + consumers on one tile, inject a
## representative per-tile intermittency aggregate, open that tile's Power pane, and save a
## PNG to verify the new Green-power & intermittency rows. Needs a window (NOT --headless):
##   <godot> --path . res://tools/power_intermittency_shot.tscn --quit-after 900

const TILE := "tile_11_2"

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)

	# A solar farm (green producer) + a few consumers on the tile so the Power pane is real.
	for s in [["b_024", "r_146", 2], ["b_008", "r_030", 1], ["b_012", "r_012", 2], ["b_007", "r_008", 1]]:
		var id: String = MatchState.add_building(str(s[0]), str(s[1]), TILE, MatchState.LOCAL_PLAYER, "")
		MatchState.buildings[id]["level"] = int(s[2])

	# Inject a representative per-tile intermittency aggregate (the Power pane reads this via
	# Production.get_tile_intermittency). 45% of draw derated, 82% of generation intermittent.
	Production._intermittency_by_tile[TILE] = {
		"green_produced": 220, "green_intermittent_produced": 180, "total_produced": 220,
		"green_consumed": 160.0, "total_consumed": 200, "unfirmed_consumed": 90.0,
		"battery_cap": 100,
		"affected": [
			{"iid": "x1", "building_id": "b_008", "power": 80},
			{"iid": "x2", "building_id": "b_012", "power": 60},
			{"iid": "x3", "building_id": "b_007", "power": 40},
			{"iid": "x4", "building_id": "b_020", "power": 20},
		],
	}

	var info_panel: Node = game.find_child("TileInfoPanel", true, false)
	info_panel.show_tile({"id": TILE})
	info_panel._select_tab("power")
	await _settle(12)
	_shot("/tmp/poe_intermittency.png")

	# Scroll the Power pane to the bottom to capture the Battery storage row (Row 3).
	for sc in info_panel.find_children("", "ScrollContainer", true, false):
		if sc.visible:
			sc.scroll_vertical = 140
	await _settle(6)
	_shot("/tmp/poe_intermittency_bottom.png")
	get_tree().quit(0)

func _shot(path: String) -> void:
	get_viewport().get_texture().get_image().save_png(path)
	print("saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
