extends Node
## Windowed regression: public rail usage remains visible after the shipment arrives.
func _ready() -> void:
	TelemetryState.enabled = false
	RunMetrics.enabled = false
	MatchState.reset()
	var source := "tile_5_10"
	var destination := "tile_4_10"
	for tile: String in [source, destination]:
		Catalog._tile_infra[tile] = ["rail"]
	Catalog._route_cache.clear()
	var route := Catalog.route(source, destination, "g_001")
	TransportState.queue_transport_shipment({"good_id": "g_001", "qty": 75, "source_tile": source, "destination_tile": destination, "turns_remaining": 1, "tiles": route.get("tiles", []), "legs": route.get("legs", [])})
	TransportState.update_transport_congestion()
	TransportState.advance_transport_shipments()
	var slots := preload("res://scripts/tile_view_data.gd").infrastructure_summary(destination, {"infrastructure_present": ["rails"], "infrastructure_levels": {"rails": 1}})
	var used := 0
	for slot: Dictionary in slots:
		if str(slot.get("key", "")) == "rails":
			used = int((slot.get("transit", {}) as Dictionary).get("used", 0))
	print("[public infra] tile readout: ", used, "; overview rows: ", TransportState.active_links().size())
	if used != 75 or TransportState.active_links().size() != 2 or not BuildingState.buildings.is_empty():
		get_tree().quit(1)
		return
	var panel := preload("res://scripts/transport_panel.gd").new()
	panel.theme = DS.theme
	add_child(panel)
	panel.open()
	for button in panel.find_children("*", "Button", true, false):
		if button.text == "Rails":
			button.button_pressed = true
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/public-infra-panel.png")
	get_tree().quit()
