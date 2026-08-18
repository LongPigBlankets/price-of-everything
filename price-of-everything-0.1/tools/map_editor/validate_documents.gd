extends Node
## Validate every authored map document on disk against the loader's own validator.
##
## The documents in `data/map_authored/` are SOURCE — hand-drawn work with no other copy —
## and they are the one kind of file in this project that no test opens. A document that has
## gone bad fails at load, in the game, as a blank map, which is a long way from the edit that
## broke it. Run this before committing map data.
##
##   <godot> --headless --path . res://tools/map_editor/validate_documents.tscn --quit-after 600

const AuthoredMap := preload("res://scripts/authored_map.gd")


func _ready() -> void:
	var failures := 0
	var names: Array = AuthoredMap.list_documents()
	if names.is_empty():
		print("[DOCS] no documents found in %s" % AuthoredMap.DOC_DIR)
		get_tree().quit(1)
		return
	var active := AuthoredMap.active_name()
	for name_value in names:
		var name := str(name_value)
		var path := AuthoredMap.path_for(name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			print("[DOCS] FAIL %s — cannot open %s" % [name, path])
			failures += 1
			continue
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) != TYPE_DICTIONARY:
			print("[DOCS] FAIL %s — not a JSON object" % name)
			failures += 1
			continue
		var document: Dictionary = parsed
		var problems: PackedStringArray = AuthoredMap.validate(document)
		if not problems.is_empty():
			print("[DOCS] FAIL %s — %s" % [name, ", ".join(problems)])
			failures += 1
			continue
		print("[DOCS] PASS %s%s — %s" % [name, "  (ACTIVE)" if name == active else "",
			_summary(document)])
	if active == "":
		print("[DOCS] WARN active.txt names no document — the game will render no authored map")
	elif not names.has(active):
		print("[DOCS] FAIL active.txt names '%s', which is not on disk" % active)
		failures += 1
	print("[DOCS] %d document(s), %d failure(s)" % [names.size(), failures])
	get_tree().quit(1 if failures > 0 else 0)


func _summary(document: Dictionary) -> String:
	var settlements: Dictionary = document.get("settlements", {})
	var roads := 0
	var shapes := 0
	var slots := 0
	var tiles := 0
	for key in settlements.keys():
		var settlement: Dictionary = settlements[key]
		roads += (settlement.get("roads", []) as Array).size()
		for kind in ["decor", "specials", "farms", "forests", "parks", "plazas"]:
			shapes += (settlement.get(kind, []) as Array).size()
		for tile_value in (settlement.get("slots", {}) as Dictionary).values():
			slots += ((tile_value as Dictionary).get("pins", []) as Array).size()
		tiles += (settlement.get("tiles", []) as Array).size()
	return "%d roads, %d shapes, %d slots, %d tiles" % [roads, shapes, slots, tiles]
