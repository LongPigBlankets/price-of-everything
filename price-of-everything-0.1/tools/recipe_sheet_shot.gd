extends Node2D
## Verification shot for the building detail panel's "Change recipe" sheet: the
## same compressed mini-diagram look the Construct panel's recipe cards use
## (filled navy arrow, bold "+", no quantities), and the panel widened to fit it.
##   Godot --path . res://tools/recipe_sheet_shot.tscn --quit-after 900
## Writes to OUT_DIR: recipe_sheet.png

const OUT_DIR := "C:/Users/urigi/AppData/Local/Temp/claude/C--Users-urigi-price-of-everything-price-of-everything-0-1/07c26e3a-d370-4e95-9ab5-05bbb28794cb/scratchpad/out/"

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	MatchState.money = 5000.0
	var iid: String = MatchState.add_building("b_007", "", "tile_9_9", "player_1", "shot_recipe_sheet")

	var panel: Control = game.building_panel_v2
	panel.show_building(MatchState.get_building(iid))
	await _settle(6)

	print("[recipe_sheet_shot] panel size before sheet=", panel.size)
	panel._open_recipe_sheet(MatchState.get_building(iid))
	await _settle(10)
	print("[recipe_sheet_shot] panel size with sheet=", panel.size)
	var sheet: Control = panel.find_child("ActionSheet", true, false)
	if sheet == null:
		print("[recipe_sheet_shot] WARNING: ActionSheet not found")
	else:
		var diagram: Control = sheet.find_child("MiniRecipeDiagramCard", true, false)
		print("[recipe_sheet_shot] sheet size=", sheet.size, " a mini diagram found=", diagram != null)
	await _shot(OUT_DIR + "recipe_sheet.png")

	print("[recipe_sheet_shot] done")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[recipe_sheet_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
