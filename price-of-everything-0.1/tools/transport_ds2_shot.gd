extends Node
## Captures of the Shipments and Stockpiles panel in the real HUD after a few turns of a seeded empire, and its
## Logistics Settings sheet in an intermediary game.
##   TRANSPORT_SHOT_DIR=<dir> <godot> --path . res://tools/transport_ds2_shot.tscn --quit-after 20000 -- --no-telemetry
## Writes transport_ds2.png and transport_ds2_settings.png.

var _wm: Node
var _dir := ""


func _ready() -> void:
	_dir = OS.get_environment("TRANSPORT_SHOT_DIR")
	if _dir == "":
		_dir = OS.get_user_data_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	_wm = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false
	DecisionState.enabled = false
	MatchState.money = 25000.0
	var specs := [
		["b_003", "r_004", "tile_10_2"], ["b_024", "r_146", "tile_11_2"], ["b_001", "r_001", "tile_12_2"],
		["b_007", "r_008", "tile_13_2"], ["b_007", "r_009", "tile_13_2"], ["b_008", "r_030", "tile_10_3"],
		["b_020", "r_039", "tile_11_3"], ["b_012", "r_012", "tile_12_3"], ["b_011", "r_024", "tile_12_3"],
	]
	for sp: Array in specs:
		BuildingState.tile_land_owned[str(sp[2])] = 200
		BuildingState.add_building(str(sp[0]), str(sp[1]), str(sp[2]), MatchState.LOCAL_PLAYER, "")
		for inp: Variant in Catalog.get_recipe(str(sp[1])).get("inputs", []):
			Stockpile.add(str(sp[2]), str((inp as Dictionary).get("good_id", "")), 60)
	TurnManager.fast_mode = true
	for _i in 4:
		TurnManager.commit_turn()
		if TurnManager.is_resolving:
			await TurnManager.turn_resolution_completed
		await _settle(6)
	MatchState.transport_panel_requested.emit()
	await _settle(20)
	var panel := _wm.find_child("TransportPanel", true, false) as Control
	_hide_overlays(_wm)
	await _settle(4)
	await _shot(panel, "transport_ds2")
	# The settings sheet exists only in an intermediary game.
	MatchState.ruleset["logistics_model"] = "middleman_v1"
	panel.call("_refresh")
	await _settle(4)
	panel.call("_toggle_settings")
	_hide_overlays(_wm)
	await _settle(12)
	await _shot(panel, "transport_ds2_settings")
	get_tree().quit(0)


const OVERLAY_SCRIPTS := ["turn_briefing.gd","cfo_intro_popup.gd", "briefing_ds2.gd"]

func _hide_overlays(n: Node) -> void:
	if n == _wm:
		# The turn briefing shows itself again after a turn: collapse it rather than hide it.
		for b in _wm.find_children("*", "", true, false):
			if b.has_method("collapse") and str((b.get_script() as Script).resource_path).ends_with("turn_briefing.gd"):
				b.call("collapse")
	var sc: Script = n.get_script() as Script
	if sc != null and n is CanvasItem and str(sc.resource_path).get_file() in OVERLAY_SCRIPTS:
		(n as CanvasItem).visible = false
	for c in n.get_children():
		_hide_overlays(c)


func _shot(panel: Control, file: String) -> void:
	var hidden := _isolate(panel)
	await _settle(2)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var g := panel.get_global_rect().grow(8)
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(_dir.path_join(file + ".png"))
	_restore(hidden)


func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame


## Hide everything beside the panel's own line of ancestors (briefings, popups, docks, the
## map), so the crop is the panel alone. Returns what was hidden, for _restore.
func _isolate(panel: Node) -> Array:
	var hidden: Array = []
	var n: Node = panel
	while n != null and n != get_tree().root:
		var parent := n.get_parent()
		if parent == null:
			break
		for sib in parent.get_children():
			if sib == n:
				continue
			if (sib is CanvasItem and (sib as CanvasItem).visible) or (sib is CanvasLayer and (sib as CanvasLayer).visible) \
					or (sib is Window and (sib as Window).visible):
				sib.set("visible", false)
				hidden.append(sib)
		n = parent
	# A CanvasLayer draws whatever its parent's visibility (popups hang off the top bar and the dock).
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var cl := layer as CanvasLayer
		if cl.visible and not cl.is_ancestor_of(panel):
			cl.visible = false
			hidden.append(cl)
	return hidden


func _restore(hidden: Array) -> void:
	for h in hidden:
		if is_instance_valid(h):
			h.set("visible", true)
