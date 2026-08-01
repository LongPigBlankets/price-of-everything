extends Node
## Verifies the research panel's search: the result set must be drawn from EVERY category,
## not just the open tab (the tutorial's target node lives under a tab nobody would guess).
##   <godot> --path . res://tools/research_search_shot.tscn --quit-after 900
func _ready() -> void:
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	var panel: Control = game.get_node("UILayer/HUD/HUDContent/ResearchPanel")
	PanelStack.push(panel)
	panel.show()
	panel.set("_selected_category", "Recycling")   # deliberately the WRONG tab
	await _settle(10)
	for q in ["glass", "maintenance", "zzznope"]:
		panel.call("_on_search_changed", q)
		await _settle(8)
		var hits: Array = panel.call("_category_unlocks", "Recycling")
		var cats := {}
		var titles: Array = []
		for h in hits:
			cats[str((h as Dictionary).get("category", ""))] = true
			titles.append(str((h as Dictionary).get("title", "")))
		print("[RSEARCH] '%s' -> %d hit(s) across %d categor(ies): %s"
			% [q, hits.size(), cats.size(), str(titles.slice(0, 4))])
		if q == "glass":
			get_viewport().get_texture().get_image().save_png("/tmp/poe_research_search.png")
			print("[RSEARCH] saved /tmp/poe_research_search.png")
	get_tree().quit(0)

func _settle(frames: int) -> void:
	for _i in range(frames):
		await get_tree().process_frame
