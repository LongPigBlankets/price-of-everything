extends Node2D
## Verification shot for the Construct panel's BROWSE list: bigger building name,
## cost on the right, no recipe-count text, and — expanded — each recipe card showing
## its full diagram (3-wide input grid, name wrapped left) instead of one icon + a
## text summary.
##   Godot --path . res://tools/construct_browse_shot.tscn --quit-after 1200
## Writes to OUT_DIR: construct_browse_top.png, construct_browse_expanded.png

const OUT_DIR := "C:/Users/urigi/AppData/Local/Temp/claude/C--Users-urigi-price-of-everything-price-of-everything-0-1/07c26e3a-d370-4e95-9ab5-05bbb28794cb/scratchpad/out/"

var _wm

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var menu = _wm.get_node_or_null("UILayer/HUD")
	if menu == null or menu.get("construct_panel_v2") == null:
		print("[browse_shot] construct panel v2 not found — aborting")
		get_tree().quit(1)
		return
	var panel = menu.construct_panel_v2

	# Tile-independent browse (no terrain lock) so every building shows regardless
	# of what tile_5_10 itself would actually permit — b_007 (Industrial Goods
	# Factory) is the target and its buildability there isn't the point of this shot.
	panel._reset_to_browse()
	panel._load_data()
	panel._render()
	panel.show()
	await _settle(10)
	await _shot(OUT_DIR + "construct_browse_top.png")

	# b_007 / r_033 (Construction Equiment Assembly (ICE)) — 5 inputs, the exact
	# shape that was overflowing the old 2-column recipe diagram grid. Target ITS
	# row specifically, not the whole (much taller than the viewport) building card,
	# or ensure_control_visible settles for showing some other part of that card.
	panel._on_building_pressed("b_007")
	await _settle(10)
	var target: Control = panel.find_child("RecipeRow_r_033", true, false)
	if target == null:
		print("[browse_shot] WARNING: RecipeRow_r_033 not found")
		target = panel.find_child("BuildingCard_b_007", true, false)
	if target != null and panel._scroll != null:
		panel._scroll.ensure_control_visible(target)
		await _settle(6)
	if target != null:
		var diagram: Control = target.find_child("RecipeDiagramCard", true, false)
		print("[browse_shot] recipe row size=", target.size, " min=", target.get_combined_minimum_size())
		if diagram != null:
			print("[browse_shot] diagram size=", diagram.size, " min=", diagram.get_combined_minimum_size(),
				" global_position=", diagram.global_position)
		var name_lbl: Control = target.find_child("*", false, false)
		print("[browse_shot] name column min=", (name_lbl as Control).get_combined_minimum_size() if name_lbl != null else "n/a")
		print("[browse_shot] panel global size=", panel.size)
	await _shot(OUT_DIR + "construct_browse_expanded.png")

	# Also check the CONFIRM screen's own (full-size, 62px-cell) use of the same
	# diagram builder with the same 5-input recipe — the new honest-width report
	# is shared code, so a many-input recipe needs checking there too now, not
	# just in the compact recipe-card reuse this ask was actually about.
	MatchState.set_use_construct_panel_v3(true)
	panel._locked_tile_id = "tile_5_10"
	panel._on_recipe_pressed("b_007", "r_033")
	await _settle(12)
	var confirm_diagram: Control = panel.find_child("RecipeDiagramCard", true, false)
	if confirm_diagram != null:
		print("[browse_shot] V3 confirm diagram size=", confirm_diagram.size,
			" min=", confirm_diagram.get_combined_minimum_size(), " panel width=", panel.size.x)
	else:
		print("[browse_shot] WARNING: confirm RecipeDiagramCard not found")
	await _shot(OUT_DIR + "construct_confirm_r033.png")

	print("[browse_shot] done")
	get_tree().quit(0)

func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("[browse_shot] saved ", path)

func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
