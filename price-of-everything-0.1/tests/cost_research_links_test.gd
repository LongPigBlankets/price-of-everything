extends Control
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		push_error(label)
	else: print("PASS: ", label)
func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	var labour = load("res://scripts/labour_policy_tab.gd").new()
	labour.position = Vector2(20, 40)
	labour.size = Vector2(960, 820)
	add_child(labour)
	var detail = load("res://scripts/building_detail_panel_v2.gd").new()
	var metrics := VBoxContainer.new()
	metrics.position = Vector2(1000, 40)
	metrics.size = Vector2(400, 450)
	add_child(metrics)
	var maintenance: HBoxContainer = detail.call("_metric", "Maintenance / turn", "−£12.50", Color("#e28b80"), false)
	var wages: HBoxContainer = detail.call("_metric", "Labour / turn", "−£35.20", Color("#e28b80"), false)
	metrics.add_child(maintenance)
	metrics.add_child(wages)
	metrics.add_child(detail.call("_build_labour", {"unskilled":20,"skilled":10,"highly":3,"total":33,"cost":35.2}))
	check(maintenance.get_child(0).name == "EffectEmblem_gears", "Maintenance uses shared research emblem")
	check(wages.get_child(0).name == "EffectEmblem_engineer", "Labour uses shared research emblem")
	detail.free()
	for frame in 15: await get_tree().process_frame
	check(maintenance.size.x <= metrics.size.x + 1, "Emblem and cost fit the economics column")
	check(labour.find_children("EffectEmblem_gears", "", true, false).size() >= 2, "Maintenance visible for safety and automation policies")
	check(labour.find_children("EffectEmblem_engineer", "", true, false).size() >= 1, "Labour summary and policies show the labour emblem")
	if "--visual" in OS.get_cmdline_user_args():
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/private/tmp/cost-emblems.png")
	labour.hide()
	metrics.hide()
	var graph = load("res://scripts/goods_graph_world.gd").new()
	graph.size = Vector2(1500, 900)
	add_child(graph)
	graph.set_graph(load("res://scripts/goods_flow_graph.gd").build())
	graph.call("_enter_grid", "steel")
	var events: Array = []
	graph.research_requested.connect(func(title: String): events.append(title))
	var islands: Array = graph.get("_grid_islands")
	var tested := 0
	for island in islands:
		var recipe: Dictionary = island.recipe
		var title: String = graph.call("_recipe_research_title", recipe)
		var p: Vector2 = island.rect.position + Vector2(5, 22)
		check(graph.call("_grid_research_at", p) == title, "Header hit targets its research or is inert for base recipes")
		if title != "":
			var screen: Vector2 = p * float(graph.get("_view_zoom")) + graph.get("_view_offset")
			graph.call("_click_at", screen)
			check(events.back() == title, "Recipe click dispatches exact research title")
			tested += 1
	check(tested > 0, "Steel alternatives include research links")
	check(graph.call("_recipe_research_title", {"tech_unlock_req":"research_petro_020"}) == "", "Demo-hidden research is not linked")
	for frame in 15: await get_tree().process_frame
	if "--visual" in OS.get_cmdline_user_args():
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/private/tmp/alternate-research-links.png")
	print("COST/LINK FAILURES: ", failures)
	get_tree().quit(1 if failures else 0)
