extends RefCounted
## Called from a real loaded game so depot datums, mines, rivers and NavGrid
## agree with the packaged railway, including tunnel and bridge classification.
static func write(builder: RefCounted, model: Dictionary) -> void:
	builder._prepare_rail_art()
	var audit := {"roads": [], "rails": [], "tiles": [], "transport_key": builder.transport_key,
		"rail_half": builder.Railway.CORRIDOR_WIDTH * 0.5}
	for tid in model.tiles:
		var tile: Dictionary = model.tiles[tid]
		audit.tiles.append({"id": tid, "label": tile.label, "center": [tile.center.x,tile.center.y]})
	for road in builder.road_grade.segments:
		audit.roads.append({"a": [road.a.x,road.a.y], "b": [road.b.x,road.b.y], "half": road.half,
			"ha": builder.road_height(road.a), "hb": builder.road_height(road.b), "tunnel": road.get("tunnel",false)})
	for profile in builder._prepared_rail_art.corridor_profiles:
		var samples: Array = []
		for sample in profile.samples:
			samples.append({"p": [sample.p.x,sample.p.y], "h": sample.h, "s": sample.s, "hidden": sample.hidden, "bridge": sample.bridge})
		audit.rails.append(samples)
	FileAccess.open("/private/tmp/transport-overlap-inputs.json",FileAccess.WRITE).store_string(JSON.stringify(audit))
	print("[TRANSPORT AUDIT] roads=",audit.roads.size()," corridors=",audit.rails.size()," key=",builder.transport_key)
