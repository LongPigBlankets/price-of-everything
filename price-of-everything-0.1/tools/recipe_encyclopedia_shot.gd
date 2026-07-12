extends Node
## Windowed shot: the Encyclopedia good→recipes panel (swap recipes cheat) rendered
## with the reusable DS RecipeDiagram builder. Also exercises the font change.

const START := "res://data/starts/metal_magnate.json"
const GOOD_ID := "g_004"  # iron_ingots — produced by smelting, used by steelmaking

func _good(id: String) -> Dictionary:
	for g in Catalog.all_goods():
		if str(g.get("id", "")) == id:
			return g
	return {}

func _ready() -> void:
	get_window().size = Vector2i(1440, 960)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	for _i in range(20):
		await get_tree().process_frame

	var so: Node = main.find_child("SearchOverlay", true, false)
	if so == null:
		push_error("no SearchOverlay found"); get_tree().quit(1); return
	so.call("open_encyclopedia")
	await get_tree().process_frame
	var good := _good(GOOD_ID)
	var res := {"type": "good", "id": GOOD_ID, "title": str(good.get("display_name", GOOD_ID)), "payload": good}
	so.call("_show_result_detail", res)
	for _i in range(40):
		await get_tree().process_frame

	var img := get_viewport().get_texture().get_image()
	img.save_png("res://recipe_encyclopedia.png")
	print("[SHOT] saved recipe_encyclopedia.png for good=", GOOD_ID, " (", res.title, ")")
	get_tree().quit(0)
