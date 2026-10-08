extends Node
## Windowed visual check for the Company Rankings top-bar module and league table.
## Run: <godot> --path . res://tools/company_rankings_shot.tscn --quit-after 600

const START := "res://data/starts/metal_magnate.json"

func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var frames := 0
	while frames < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		frames += 1
	# The start's opener and intro card out of the way, and the league revealed (it shows from turn 10), so the
	# panel opens over the map.
	if main.has_method("reveal_for_play"):
		main.call("reveal_for_play")
	MatchState.ruleset["opener_done"] = true
	Tutorial._on_overlay_skipped()
	for layer: Node in main.find_children("*", "CanvasLayer", true, false):
		var sc := layer.get_script() as Script
		if sc != null and sc.resource_path.ends_with("_intro.gd"):
			layer.queue_free()
	TurnManager.current_turn = maxi(int(TurnManager.current_turn), int(CompanyRankings.REVEAL_TURN))
	CompanyRankings.import_state({"player_revenue_history": [110.0, 145.0, 180.0, 230.0, 280.0]})
	for _i: int in range(12):
		await get_tree().process_frame
	var top_bar: Node = main.find_child("TopBar", true, false)
	if top_bar == null:
		push_error("no TopBar found")
		get_tree().quit(1)
		return
	top_bar.call("_open_rankings_panel")
	for _i: int in range(12):
		await get_tree().process_frame
	RenderingServer.force_draw(false)   # macOS stops drawing a window it cannot see
	get_viewport().get_texture().get_image().save_png("res://company_rankings_shot.png")
	print("[SHOT] saved company_rankings_shot.png")
	top_bar.call("_set_rankings_tab", "goods")
	for _i: int in range(12):
		await get_tree().process_frame
	RenderingServer.force_draw(false)   # macOS stops drawing a window it cannot see
	get_viewport().get_texture().get_image().save_png("res://company_rankings_goods_shot.png")
	print("[SHOT] saved company_rankings_goods_shot.png")
	get_tree().quit(0)
