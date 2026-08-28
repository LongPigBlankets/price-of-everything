extends Node
## Windowed shot: the Upgrade building dialog, for reviewing its copy and its icon sizes.
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
	# Any player-owned building with an upgrade path will do; the dialog's layout is the
	# subject, not the particular building.
	var target := ""
	for instance_id in MatchState.buildings:
		var preview: Dictionary = MatchState.preview_upgrade(str(instance_id))
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
		var script: GDScript = load("res://scripts/upgrade_dialog.gd")
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
