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
	CompanyRankings.import_state({"player_revenue_history": [110.0, 145.0, 180.0, 230.0, 280.0]})
	for _i: int in range(12):
		await get_tree().process_frame
	var top_bar: Node = main.find_child("TopBar", true, false)
	if top_bar == null:
		push_error("no TopBar found")
		get_tree().quit(1)
		return
	top_bar.call("_open_fly", "rankings")
	for _i: int in range(12):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://company_rankings_shot.png")
	print("[SHOT] saved company_rankings_shot.png")
	top_bar.set("_rankings_tab", "goods")
	top_bar.call("_close_fly")
	top_bar.call("_open_fly", "rankings")
	for _i: int in range(12):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://company_rankings_goods_shot.png")
	print("[SHOT] saved company_rankings_goods_shot.png")
	get_tree().quit(0)
