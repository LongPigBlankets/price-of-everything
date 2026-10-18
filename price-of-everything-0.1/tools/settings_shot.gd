extends Node2D
# Dev-only: render the Settings panel (opens on the Audio tab).
#   Godot --path . res://tools/settings_shot.tscn --quit-after 600 [-- --tab=Graphics --tooltip --out=<png>]
# --tab opens that tab. --tooltip also draws the tab's info badge tooltip, built exactly as a
# hover builds it, below the badge. --out defaults to res://settings_shot.png.
var _frame := 0
var _out := "res://settings_shot.png"


func _ready() -> void:
	get_window().size = Vector2i(1100, 720)
	var tab_name := ""
	var tooltip := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tab="): tab_name = arg.trim_prefix("--tab=")
		elif arg.begins_with("--out="): _out = arg.trim_prefix("--out=")
		elif arg == "--tooltip": tooltip = true
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(root)
	await get_tree().process_frame   # let DS assign the theme to the root viewport
	var panel := SettingsPanel.open(root)
	if tab_name != "":
		for tabs in panel.find_children("*", "TabContainer", true, false):
			for i in (tabs as TabContainer).get_tab_count():
				if (tabs as TabContainer).get_tab_title(i) == tab_name: (tabs as TabContainer).current_tab = i
	if tooltip:
		await get_tree().process_frame
		await get_tree().process_frame
		for badge in panel.find_children("*", "Button", true, false):
			if (badge as Button).text != "i" or not (badge as Button).is_visible_in_tree(): continue
			var tip: Control = badge.call("_make_custom_tooltip", (badge as Button).tooltip_text)
			root.add_child(tip)
			tip.position = (badge as Button).global_position + Vector2(-60, 32)
			break


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 12:
		var img := get_viewport().get_texture().get_image()
		img.save_png(_out)
		print("SAVED ", _out, " ", img.get_width(), "x", img.get_height())
		get_tree().quit()
