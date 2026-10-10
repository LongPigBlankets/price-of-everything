extends Node
const Builder = preload("res://scripts/supply_chain_3d/world_builder.gd")
const Harbour = preload("res://scripts/supply_chain_3d/harbour.gd")
const Legacy = preload("res://scripts/empire_board.gd")
const Ground = preload("res://scripts/empire_board_ground.gd")
const Authored = preload("res://scripts/authored_map.gd")
const Curves = preload("res://scripts/authored_road_geometry.gd")
func _ready():
	call_deferred("audit")
func audit():
	var rel = preload("res://scripts/supply_chain_3d/coast.gd").relief_of("tile_4_10", Vector2(2295,5760))
	var nav = NavGrid.instance()
	for s in Authored.settlements().values():
		for r in s.get("roads", []):
			if r.id not in ["r:untitled:224", "r:untitled:225", "r:untitled:226"]: continue
			print(r.id)
			var pts = Curves.sample(r)
			for i in range(1,pts.size()):
				for t in [0.0,0.25,0.5,0.75,1.0]:
					var p = pts[i-1].lerp(pts[i],t)
					var c = nav.cell_of(p)
					print(p, " supply_water=",Ground.is_water(rel,p)," nav_water=",nav.water(c.x,c.y))
	for tid in Harbour.layouts():
		var layout = Harbour.layouts()[tid]
		var s = {"harbour": layout, "pos": layout.bounds.get_center()}
		var frame = Harbour.frame(s, func(_p): return 34.0, Vector2.ZERO)
		print("HARBOUR ", tid, " ", layout.bounds, " quays=", layout.quays.size(), " decor=", layout.decor.size(), " triangles=", Harbour.picking_shape(frame).get_faces().size()/3)
	get_tree().quit()
