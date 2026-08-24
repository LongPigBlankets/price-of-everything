extends Node
## Dev tool: the Construct panel's confirm screen, on a tile that has room and on one that
## does not — the second is where the land tickbox appears, ticked, with its price.
##   Godot --path . res://tools/construct_land_shot.tscn --quit-after 1400

func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(120)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var panel: Node = _find_by_method(game, "_on_confirm_pressed")
	if panel == null:
		print("[LAND] construct panel not found")
		get_tree().quit(1)
		return

	var tile := "tile_5_10"
	MatchState.money = 500000.0
	var building: Dictionary = Catalog.get_building("b_009")
	var recipe: Dictionary = {}
	for r_variant: Variant in Catalog.all_recipes():
		var r: Dictionary = r_variant
		if str(r.get("building_id", "")) == "b_009":
			recipe = r
			break

	# A · plenty of land — the quiet one-line state.
	MatchState.tile_land_owned[tile] = 90
	_open(panel, building, recipe, tile)
	await _settle(16)
	print("[LAND] roomy: units=%s cost=%s wanted=%s" % [
		str(panel.get("_land_purchase_units")), str(panel.get("_land_purchase_cost")),
		str(panel.get("_buy_land_wanted"))])
	get_viewport().get_texture().get_image().save_png("user://poe_construct_land_ok.png")

	# B · not enough land — the tickbox, ticked, with the price.
	MatchState.tile_land_owned[tile] = 5
	_open(panel, building, recipe, tile)
	await _settle(16)
	print("[LAND] short: units=%s cost=%s wanted=%s total=%s" % [
		str(panel.get("_land_purchase_units")), str(panel.get("_land_purchase_cost")),
		str(panel.get("_buy_land_wanted")),
		str(panel.call("_confirm_total_cost"))])
	# The land row sits directly above Confirm, at the bottom of a scrolling panel.
	for sc_variant: Variant in (panel as Control).find_children("*", "ScrollContainer", true, false):
		var sc := sc_variant as ScrollContainer
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)
	await _settle(6)
	get_viewport().get_texture().get_image().save_png("user://poe_construct_land_short.png")

	# Unticking must drop the land back out of the total.
	var build_only: float = panel.call("_construction_display_cost", "b_009")
	panel.call("_on_buy_land_toggled", false)
	print("[LAND] unticked total=%s build-only=%s" % [
		str(panel.call("_confirm_total_cost")), str(build_only)])
	print("[LAND] done")
	get_tree().quit(0)


func _open(panel: Node, building: Dictionary, recipe: Dictionary, tile: String) -> void:
	panel.set("_selected_building", building)
	panel.set("_selected_recipe", recipe)
	panel.set("_locked_tile_id", tile)
	(panel as Control).visible = true
	(panel as Control).move_to_front()
	# Go through the panel's own dispatcher: _render() clears _content and _footer first, and
	# calling _render_confirm() directly stacked a second Confirm button on the old screen.
	panel.set("_view", 1)   # View.CONFIRM
	panel.call("_render")


func _find_by_method(n: Node, method: String) -> Node:
	if n.has_method(method):
		return n
	for c in n.get_children():
		var hit := _find_by_method(c, method)
		if hit != null:
			return hit
	return null


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
