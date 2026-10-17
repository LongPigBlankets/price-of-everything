extends Node
const Hub := preload("res://scripts/rail_hub.gd")
func _ready() -> void:
	TelemetryState.enabled = false; SaveLoad.autosave_enabled = false
	preload("res://tools/shot_harness.gd").arm_watchdog(self,60.0)
	DisplayServer.window_set_size(Vector2i(1100,1100))
	get_viewport().size = Vector2i(1100,1100)
	var backdrop := ColorRect.new(); backdrop.color=Color("979c76"); backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(backdrop)
	var iid := BuildingState.add_building(Hub.ID,Hub.RECIPE,"tile_5_10",Hub.OWNER)
	BuildingState.add_building("b_004","","tile_5_10","Three Diamonds Shipping Corporation")
	var panel := preload("res://scripts/tile_info_panel_v2.gd").new(); add_child(panel)
	var tile := {"id":"tile_5_10","coord":Vector2i(4,9),"terrain":"urban","type":"urban","name":"Stoneshore","infrastructure_present":["roads","cables","rails"],"infrastructure_levels":{"roads":1,"cables":1,"rails":1}}
	panel.show_tile(tile,"bl")
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../outputs/railway-assets/rail-hub-panel.png")
	get_viewport().get_texture().get_image().save_png(output)
	print("[Rail Hub UI] ",output)
	BuildingState.set_building_owner(iid,MatchState.LOCAL_PLAYER)
	for i in 8: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(output.replace("panel.png","owned-panel.png"))
	get_tree().quit()
