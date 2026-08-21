extends Node2D
## The node that paints one authored tile into a texture, through the SAME painters the game
## draws with (`authored_fabric_painter.gd`, `authored_road_painter.gd`). Shared by the export
## tool (`tools/map_editor/bake_authored_map.gd`) and by the RUNTIME re-bake that repairs a
## tile after a decorative mass is evicted, so an in-match repaint cannot drift from the
## texture that shipped.
##
## Its transform maps the tile's world rect onto the texture, so the painters keep drawing in
## world coordinates and know nothing about the bake.

const FabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const RoadPainter := preload("res://scripts/authored_road_painter.gd")
const Layout := preload("res://scripts/authored_bake_layout.gd")

var _layer := "fabric"
var _records: Dictionary = {}
## Regions the fabric is cut around — the harbours. Baked IN, so a textured map shows the town
## stopping short of a quay exactly as a vector one does.
var _keep_out: Array = []


func configure(layer: String, records: Dictionary, world_to_texture: Transform2D,
		keep_out: Array = []) -> void:
	_layer = layer
	_records = records
	_keep_out = keep_out
	transform = world_to_texture
	queue_redraw()


func _draw() -> void:
	if _layer == "roads":
		# A fresh cache per tile: the polyline is world geometry and identical every time, but
		# holding it across every tile would pin every stroke in memory for no gain.
		RoadPainter.draw_strokes(self, _records.get("roads", []), {})
		return
	# Layer-major, exactly as authored_fabric_visuals draws it: all ground first, then
	# everything standing on it (see Layout.FABRIC_ORDER).
	for kind in Layout.FABRIC_ORDER:
		for record in (_records.get(kind, []) as Array):
			match kind:
				"plazas":
					FabricPainter.draw_plaza(self, record)
				"parks":
					FabricPainter.draw_park(self, record)
				"farms":
					FabricPainter.draw_farm(self, record)
				"decor":
					FabricPainter.draw_mass(self, record, _keep_out)
				"specials":
					FabricPainter.draw_special(self, record, _keep_out)
				"forests":
					FabricPainter.draw_forest(self, record)
