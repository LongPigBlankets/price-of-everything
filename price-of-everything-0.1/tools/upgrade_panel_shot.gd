extends Node
## Windowed shot: the Upgrade building dialog, for reviewing its copy and its icon sizes. The dialog the game opens
## (the DS2 one unless `toggle upgrade ds2` switched it back); UPGRADE_SHOT_BUILDING=<building id> (b_003, the coal
## power plant) picks that kind of building instead of the first upgradable one.
##   <godot> --path . res://tools/upgrade_panel_shot.tscn --quit-after 120000

const START := "res://data/starts/metal_magnate.json"


func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	for _i in 200:
		await get_tree().process_frame
	get_viewport().set_disable_input(true)
	# A start's story card (metal_magnate_intro.gd and its siblings) would cover the dialog: close it as Begin does.
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var s: Script = n.get_script()
		if s != null and s.resource_path.ends_with("_intro.gd"):
			n.queue_free()
	# Any player-owned building with an upgrade path will do; the dialog's layout is the
	# subject, not the particular building.
	var target := ""
	var want := OS.get_environment("UPGRADE_SHOT_BUILDING")
	for instance_id in BuildingState.buildings:
		if want != "" and str(BuildingState.buildings[instance_id].get("building_id", "")) != want:
			continue
		var preview: Dictionary = BuildingWorks.preview_upgrade(str(instance_id))
		if not preview.is_empty():
			target = str(instance_id)
			print("[UPG] %s -> %s" % [target, str(preview.get("to_name", preview.keys()))])
			break
	if target == "":
		print("[UPG] no upgradeable building in this start")
		get_tree().quit(1)
		return
	var dialog: Node = main.find_child("UpgradeDialog", true, false)
	if dialog == null:
		var script: GDScript = load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd" if UiPrefs.use_upgrade_ds2 else "res://scripts/upgrade_dialog.gd")
		dialog = script.new()
		var layer := main.get_node_or_null("UILayer")
		(layer if layer != null else main).add_child(dialog)
		(dialog as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for _i in 5:
			await get_tree().process_frame
	dialog.call("open", target)
	for _i in 40:
		await get_tree().process_frame
	RenderingServer.force_draw()
	get_viewport().get_texture().get_image().save_png("user://poe_upgrade.png")
	print("[UPG] user://poe_upgrade.png")
	get_tree().quit(0)
