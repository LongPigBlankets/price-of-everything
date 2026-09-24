extends Node2D
## The text on the DS2 surfaces, measured rather than guessed: every visible Label and RichTextLabel on the
## top bar, its hover readout, the Treasury and Power sheets and Building Detail v3, by font and size.
##   Godot --headless --path . res://tools/topbar_font_audit.tscn --quit-after 6000
## Prints "[FONTS] <surface> | <font> <size> px | <count> | <examples>" lines.

var _wm


func _ready() -> void:
	UiPrefs.set_use_topbar_ds2(true)
	UiPrefs.set_use_bdp_v3(true)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	for _i in 60:
		await get_tree().process_frame
	var bar: Control = _wm.get_node("UILayer/HUD/TopBar")
	var iid: String = BuildingState.add_building("b_007", "r_009", "tile_5_10", "player_1", "fontaudit")
	TurnManager.fast_mode = true
	DecisionState.auto_resolve = true
	TurnManager.commit_turn()
	if TurnManager.is_resolving:
		await TurnManager.turn_resolution_completed
	for _i in 10:
		await get_tree().process_frame

	_report("top bar", bar, ["Ds2Readout"])
	var power: Control = bar.find_child("PowerModule", true, false)
	power.mouse_entered.emit()
	await get_tree().process_frame
	_report("hover readout", bar.get("_ds2_readout"), [])
	power.mouse_exited.emit()
	for id: String in ["treasury", "power"]:
		bar.call("_open_fly", id)
		for _i in 4:
			await get_tree().process_frame
		_report("%s sheet" % id, bar.get("_fly_panel"), [])
		bar.call("_close_fly")
	var bdp: Node = _wm.find_child("BuildingDetailPanelV2", true, false)
	if bdp == null:
		bdp = _wm.find_child("BuildingDetailPanel", true, false)
	if bdp != null and bdp.has_method("show_building"):
		bdp.call("show_building", BuildingState.get_building(iid))
		for _i in 6:
			await get_tree().process_frame
		_report("building detail v3", bdp, [])
	else:
		print("[FONTS] building detail panel not found")
	print("[FONTS] done")
	get_tree().quit(0)


func _report(surface: String, root: Node, skip_names: Array) -> void:
	if root == null:
		print("[FONTS] %s | not found" % surface)
		return
	var groups := {}
	for n: Node in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or _under(c, root, skip_names):
			continue
		var font: Font = null
		var px := 0
		var text := ""
		if c is Label:
			if (c as Label).text.strip_edges() == "":
				continue
			font = c.get_theme_font("font")
			px = c.get_theme_font_size("font_size")
			text = (c as Label).text
		elif c is RichTextLabel:
			if (c as RichTextLabel).get_parsed_text().strip_edges() == "":
				continue
			font = c.get_theme_font("normal_font")
			px = c.get_theme_font_size("normal_font_size")
			text = (c as RichTextLabel).get_parsed_text()
		elif c is Button and (c as Button).text.strip_edges() != "":
			font = c.get_theme_font("font")
			px = c.get_theme_font_size("font_size")
			text = "[button] " + (c as Button).text
		else:
			continue
		var fname := _font_name(font)
		var key := "%s %d px" % [fname, px]
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(text.replace("\n", " ").left(28))
	var keys := groups.keys()
	keys.sort()
	for key: String in keys:
		var ex: Array = groups[key]
		print("[FONTS] %s | %s | %d | %s" % [surface, key, ex.size(), ", ".join(PackedStringArray(ex.slice(0, 4)))])


func _under(c: Node, root: Node, names: Array) -> bool:
	var p := c
	while p != null and p != root:
		if str(p.name) in names:
			return true
		p = p.get_parent()
	return false


func _font_name(font: Font) -> String:
	if font == null:
		return "?"
	var path := font.resource_path
	if path == "" and font is FontVariation and (font as FontVariation).base_font != null:
		path = (font as FontVariation).base_font.resource_path
	if path != "":
		return path.get_file().get_basename()
	return font.get_font_name() if font.has_method("get_font_name") else str(font)
