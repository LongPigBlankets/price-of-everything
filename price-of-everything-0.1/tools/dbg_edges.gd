extends Node
## TEMP: dump edges on given tiles (env TILES=comma list) with endpoint context.
@onready var terrain: HexMap = %TerrainLayer
func _ready() -> void:
	await get_tree().process_frame
	RoadNetwork.reset()
	RoadNetwork.bootstrap_from_bake()
	var net := RoadNetwork.instance()
	for tid in OS.get_environment("TILES").split(","):
		var coord: Vector2i = terrain.id_to_coord(tid)
		print("[DBG] === %s coord=%s edges=%d ===" % [tid, str(coord), net.edges_on_tile(coord).size()])
		for eid in net.edges_on_tile(coord):
			var e: Dictionary = net.edges[eid]
			var g: PackedVector2Array = e.geometry
			# how close each endpoint is to any OTHER edge
			var d0 := 1.0e30
			var d1 := 1.0e30
			for oid in net.edges:
				if oid == eid:
					continue
				var og: PackedVector2Array = net.edges[oid].geometry
				for i in range(og.size() - 1):
					d0 = minf(d0, g[0].distance_to(Geometry2D.get_closest_point_to_segment(g[0], og[i], og[i + 1])))
					d1 = minf(d1, g[g.size() - 1].distance_to(Geometry2D.get_closest_point_to_segment(g[g.size() - 1], og[i], og[i + 1])))
			print("[DBG] %s a=%s b=%s pts=%d len=%.0f bridges=%d endgapA=%.1f endgapB=%.1f tiles=%s" % [
				eid, str(e.a), str(e.b), g.size(), _len(g), (e.bridges as Array).size(), d0, d1, str(e.tiles)])
	get_tree().quit(0)
func _len(g: PackedVector2Array) -> float:
	var t := 0.0
	for i in range(1, g.size()):
		t += g[i - 1].distance_to(g[i])
	return t
