extends Node
## Dev tool: verify the Victory / Defeat end screen (scripts/victory_end_screen.gd).
## Seeds fake end-game state into VictoryState + MatchState, runs EndGameData.gather(),
## instantiates the screen, and screenshots each of THREE states (grand-slam, partial,
## defeat) both full and scrolled to each section, into /tmp/.
##   $GODOT_BIN --path . res://tools/victory_end_shot.tscn --quit-after 6000

const EndGameData := preload("res://scripts/end_game_data.gd")

var _screen: CanvasLayer


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 1000))
	get_window().content_scale_size = Vector2i(1600, 1000)
	# The main scene brings up the autoloads + terrain so MatchState/Catalog resolve.
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	_screen = (load("res://scripts/victory_end_screen.gd") as Script).new()
	add_child(_screen)

	# ── State A: grand-slam victory (all 5 tracks) ──
	_seed(true, 210, ["autarkic", "logistics", "richest", "widest", "greenest"], {})
	_screen.show_end(EndGameData.gather())
	await _settle(30)
	await _shots("grandslam")
	# Verify the Expand empire overlay renders.
	_screen.call("_open_expand")
	await _settle(12)
	await _shot("/tmp/poe_victory_grandslam_expand.png")
	_screen.call("_close_expand")
	await _settle(8)

	# ── State B: partial victory (3 tracks) ──
	_seed(true, 168, ["richest", "widest", "logistics"],
		{"autarkic": 0.62, "greenest": 0.44})
	_screen.show_end(EndGameData.gather())
	await _settle(30)
	await _shots("partial")

	# ── State C: defeat (0 tracks, turn 300) ──
	_seed(false, 300, [], {"richest": 0.71, "widest": 0.55, "logistics": 0.30, "autarkic": 0.18, "greenest": 0.12})
	_screen.show_end(EndGameData.gather())
	await _settle(30)
	await _shots("defeat")

	print("[victory_shot] done")
	get_tree().quit(0)


## Seed VictoryState (+ a few player buildings) for one render.
func _seed(won: bool, turn: int, secured: Array, partial: Dictionary) -> void:
	# Fresh sim buildings so the empire/tiles are realistic and repeatable.
	MatchState.buildings.clear()
	MatchState.tile_buildings.clear()
	MatchState.money = 50000.0
	var tiles := ["tile_5_9", "tile_5_10", "tile_6_9", "tile_6_10", "tile_7_9", "tile_7_10", "tile_4_9", "tile_8_10"]
	MatchState.add_building("b_001", "r_001", tiles[0], "player_1", "vshot_m1", false)
	MatchState.add_building("b_001", "r_001", tiles[1], "player_1", "vshot_m2", false)
	MatchState.add_building("b_002", "r_003", tiles[2], "player_1", "vshot_f1", false)
	MatchState.add_building("b_002", "r_003", tiles[3], "player_1", "vshot_f2", false)
	MatchState.add_building("b_007", "r_009", tiles[4], "player_1", "vshot_g1", false)
	MatchState.add_building("b_007", "r_009", tiles[5], "player_1", "vshot_g2", false)
	MatchState.add_building("b_007", "r_009", tiles[6], "player_1", "vshot_g3", false)
	MatchState.add_building("b_004", "", tiles[7], "player_1", "vshot_p1", false)

	VictoryState.reset()
	VictoryState.won = won
	VictoryState.won_turn = turn if won else 0
	TurnManager.current_turn = turn
	for k in ["autarkic", "logistics", "richest", "widest", "greenest"]:
		if k in secured:
			VictoryState.track_best[k] = 1.0
			VictoryState.track_secured_turn[k] = maxi(60, turn - 40 + int(hash(k) % 30))
		else:
			VictoryState.track_best[k] = float(partial.get(k, 0.0))

	VictoryState.autarkic_streak = 35
	VictoryState.logistics_total = 1590
	VictoryState.logistics_efficient = 1304
	VictoryState.produced_units_lifetime = 42000
	VictoryState.richest_window = [12200.0, 12200.0, 12200.0, 12200.0, 12200.0]
	VictoryState.history_revenue = []
	VictoryState.history_output = []
	VictoryState.history_buildings = []
	var span := turn
	for i in span:
		VictoryState.history_revenue.append(200.0 + float(i) * 55.0)
		VictoryState.history_output.append(50 + i * 7)
		VictoryState.history_buildings.append(3 + i)
	VictoryState.produced_by_good = {"g_005": 58600, "g_004": 44300, "g_010": 26900, "g_002": 18200, "g_008": 15400}


func _shots(tag: String) -> void:
	var found := _screen.find_children("*", "ScrollContainer", true, false)
	var scroll: ScrollContainer = null
	for n in found:
		if not (n as Node).is_queued_for_deletion():
			scroll = n
	if scroll == null:
		push_error("[victory_shot] no scroll for %s" % tag)
		return
	var maxv := int(scroll.get_v_scroll_bar().max_value - scroll.get_v_scroll_bar().page)
	maxv = maxi(0, maxv)
	print("[victory_shot] %s scroll max = %d" % [tag, maxv])
	# Full top (header + score bar), then section crops as fractions of the range.
	var stops := {"top": 0.0, "banner": 0.26, "charts": 0.52, "empire": 0.74, "footer": 1.0}
	for name in ["top", "banner", "charts", "empire", "footer"]:
		scroll.scroll_vertical = int(float(maxv) * float(stops[name]))
		await _settle(6)
		await _shot("/tmp/poe_victory_%s_%s.png" % [tag, name])
	scroll.scroll_vertical = 0
	await _settle(4)


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[victory_shot] saved ", path)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
