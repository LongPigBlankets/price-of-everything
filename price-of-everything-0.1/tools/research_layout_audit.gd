extends Node
func _ready() -> void:
	var panel = load("res://scripts/research_panel.gd").new()
	panel.call("_load_unlock_rows")
	var output := {}
	for category in panel.CATEGORIES:
		panel.set("_selected_category", category)
		var rows: Array = panel.call("_category_unlocks", category)
		var layout: Dictionary = panel.call("_layout_unlocks", rows)
		var nodes := []
		for row in rows:
			if row.get("is_category_root", false): continue
			var r: Rect2 = layout[row.title]
			nodes.append({"id":row.research_node_id,"title":row.title,"x":r.get_center().x,"y":r.get_center().y,"prereqs":panel.call("_prereq_titles",row),"condition":panel.call("_condition_text",row)})
		output[category]=nodes
	var path := "/private/tmp/research-layout-before.json"
	if "--after" in OS.get_cmdline_user_args(): path="/private/tmp/research-layout-after.json"
	FileAccess.open(path,FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	panel.free()
	get_tree().quit()
