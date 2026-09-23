extends Node
const Paths := preload("res://scripts/app_paths.gd")
func _enter_tree() -> void:
	Paths._base = "/tmp/pepper-consolidation/runtime"
	RunMetrics.enabled = false
func _ready() -> void:
	SaveLoad.autosave_enabled = false
	SaveLoad.prepare_new_game("res://data/starts/pepper_valley_motors.json", {"ruleset":{"logistics_model":"middleman_v1"}})
	add_child(load("res://scenes/main.tscn").instantiate())
	for frame in 160:
		await get_tree().process_frame
	TurnManager.current_turn = 44
	var workloads: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("/tmp/pepper-consolidation/workloads.json"))
	var result := {}
	for scenario in workloads:
		TransportState.pending_transport_shipments.clear()
		for stream in workloads[scenario]:
			var route: Dictionary = stream.route
			var duration := maxi(1, int(route.turns))
			# One recurring daily batch at every pipeline age. No production/storage bypass
			# is claimed: this probes transport prices at the requested full throughput.
			for remaining in range(1, duration + 1):
				TransportState.pending_transport_shipments.append({"qty":int(stream.quantity),"tiles":route.tiles,"legs":route.legs,"transport_turns":duration,"turns_remaining":remaining})
		var flow: Dictionary = TransportState.transport_link_flow()
		var quotes := []
		for stream in workloads[scenario]:
			TransportState._last_link_flow = {}
			var base := TransportService.transport_cost_for_route(str(stream.good), int(stream.quantity), stream.route)
			TransportState._last_link_flow = flow
			var charged := TransportService.transport_cost_for_route(str(stream.good), int(stream.quantity), stream.route)
			quotes.append({"good":stream.good,"quantity":stream.quantity,"base":base,"charged":charged,"congestion":charged-base,"binding":TransportState.route_congestion(stream.route)})
		result[scenario] = {"flow":flow,"quotes":quotes}
	var f := FileAccess.open("/tmp/pepper-consolidation/quotes.json",FileAccess.WRITE)
	f.store_string(JSON.stringify(result,"\t"))
	get_tree().quit()
