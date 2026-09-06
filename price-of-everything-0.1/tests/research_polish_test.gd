extends "res://scripts/research_panel.gd"
var failures := 0
var sample_mode := true
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
	else: print("PASS: ", label)
func _ready() -> void:
	super._ready()
	get_window().size = Vector2i(1500,900)
	size = Vector2(1900,1100)
	for title in ["Process Intensification", "Shale Oil Fracturing"]:
		for row in _unlock_rows:
			if row.title != title: continue
			var spec := _presentation(row)
			var tex: Texture2D
			if spec.kind == "good": tex = GoodIcons.texture_for_size(spec.base, Catalog.get_internal_name(spec.base),80)
			else: tex = KeyedBuildingIcon.keyed(Catalog.get_building(spec.base))
			var fit := _fit_research_art(tex, Rect2(0,0,66,66))
			check(absf(fit.size.x / fit.size.y - tex.get_size().x / tex.get_size().y) < 0.001, title + " preserves artwork proportions")
	var survey: Dictionary = _presentation_rows["research_mining_009"]
	check(survey.kind == "system" and survey.glyph == "binoculars", "Geoscanning uses binoculars")
	for id in ["g_010","g_077","g_078"]:
		var tex := GoodIcons.texture_for_size(id, {"g_010":"power","g_077":"green_power","g_078":"grey_power"}[id],80)
		check(maxf(tex.get_width(),tex.get_height()) >= 256 and tex.get_image().has_mipmaps(), id + " loads full-size mipmapped thumbnail")
	var deposits = load("res://scripts/deposits_overlay.gd").new()
	add_child(deposits)
	check(deposits.get("_pill_layer").layer < 1, "Deposit quantities render below HUD")
	var fake_hud := Control.new()
	add_child(fake_hud)
	var custom_panel := Control.new()
	fake_hud.add_child(custom_panel)
	custom_panel.position = get_viewport().get_mouse_position() - Vector2(10,10)
	custom_panel.size = Vector2(40,40)
	deposits.set("_hud_content", fake_hud)
	deposits.set("_hud_resolved", true)
	check(deposits.call("_mouse_over_blocking_panel"), "Custom Control panels block deposit quantity hover")
	custom_panel.hide()
	check(not deposits.call("_mouse_over_blocking_panel"), "Closed panels release deposit hover")
	fake_hud.queue_free()
	deposits.queue_free()
	var total_before := 0
	var total_after := 0
	for category in CATEGORIES:
		_selected_category = category
		var rows := _category_unlocks(category)
		var layout := _layout_unlocks(rows)
		var old: Array = []
		_routing_used.clear()
		for row in rows:
			if row.get("is_category_root",false): continue
			for prereq in _prereq_titles(row):
				if not layout.has(prereq): continue
				var parent: Rect2 = layout[prereq]
				var child: Rect2 = layout[row.title]
				var start := _cable_inner_endpoint(Vector2(parent.get_center().x,parent.position.y),Vector2.UP) + Vector2.UP * CABLE_CONNECTOR_LEAD
				var end := _cable_inner_endpoint(Vector2(child.get_center().x,child.end.y),Vector2.DOWN) + Vector2.DOWN * CABLE_CONNECTOR_LEAD
				var baseline := _direct_cable_route(start,end,Vector2.UP,Vector2.DOWN)
				if _route_hits_unlock(baseline,layout,parent,child,10): baseline = _outside_cable_route(start,end,layout)
				old.append(baseline)
				var route := _choose_cable_route(start,end,layout,parent,child,10)
				check(not _route_hits_unlock(route,layout,parent,child,10), category + " cable avoids cards")
				_routing_used.append(route)
		var before := crossings(old)
		var after := crossings(_routing_used)
		print("ROUTING ",category,": ",before," -> ",after)
		total_before += before
		total_after += after
	check(total_after <= total_before, "Routed-wire intersections improve overall")
	print("ROUTING TOTAL: ",total_before," -> ",total_after)
	if _search_input != null: _search_input.hide()
	queue_redraw()
	for frame in 8: await get_tree().process_frame
	if "--visual" in OS.get_cmdline_user_args():
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/private/tmp/research-polish-cards.png")
		sample_mode = false
		_selected_category = "Chemistry"
		_routed_paths.clear()
		_routed_layout.clear()
		queue_redraw()
		for frame in 8: await get_tree().process_frame
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/private/tmp/research-chemistry.png")
	print("RESEARCH POLISH FAILURES: ", failures)
	get_tree().quit(1 if failures else 0)
func crossings(paths: Array) -> int:
	var total := 0
	for i in paths.size():
		for j in range(i): total += _route_crossings(paths[i], paths[j])
	return total
func _draw() -> void:
	if not sample_mode:
		super._draw()
		return
	GoodHover.begin_draw(self)
	draw_rect(Rect2(Vector2.ZERO,size),Color("#102b44"))
	var titles := ["Process Intensification","Shale Oil Fracturing","Computer Assisted Geoscanning"]
	for i in titles.size():
		for row in _unlock_rows:
			if row.title == titles[i]: _draw_unlock(row,Rect2(Vector2(30 + 400*i,70),UNLOCK_SIZE),0.0)
