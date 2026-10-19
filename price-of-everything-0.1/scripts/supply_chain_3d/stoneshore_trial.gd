extends RefCounted
## Shared decorative scale/zoning, with an optional five-tile art review.
const TILES := ["tile_4_9", "tile_4_10", "tile_5_9", "tile_5_10", "tile_6_9"]
const PACKAGE := "res://assets/supply_chain_3d/stoneshore_trial_bakes"

static func preview_enabled() -> bool:
	return "--stoneshore-review" in preload("res://scripts/demo_build.gd").user_args()

static func restrict_model(model: Dictionary) -> void:
	for tid in model.tiles.keys():
		if tid not in TILES: model.tiles.erase(tid)
	model.standing = model.standing.filter(func(s: Dictionary) -> bool: return model.tiles.has(str(s.tile)))
	model.roads = model.roads.filter(func(r: Dictionary) -> bool: return model.tiles.has(str(r.tile)))
	for name in ["lines", "flows"]:
		model[name] = model[name].filter(func(line: Dictionary) -> bool:
			for p in line.get("pts", []):
				if not model.tiles.has(str(p.tile)): return false
			return true)

## Measured before this trial, excluding parks/plazas and gameplay buildings.
const BASELINE_BUILDINGS := {"tile_4_9": 14, "tile_4_10": 13, "tile_5_10": 13, "tile_5_9": 0, "tile_6_9": 0}
## Initial landmarks and variety; measured street-front infill adds the rest.
const TARGET_BUILDINGS := {"tile_4_9": 12, "tile_4_10": 10, "tile_5_10": 12, "tile_5_9": 0, "tile_6_9": 0}
const RESIDENTIAL_LIMITS := {"tile_4_9": 14, "tile_4_10": 14, "tile_5_10": 14, "tile_5_9": 8, "tile_6_9": 8}
const SPACES := ["civic_pond", "civic_grove", "civic_park", "civic_plaza"]
const GREEN_LIMITS := {"civic_pond":1,"civic_grove":2,"civic_park":2,"civic_plaza":1}
## Relative to the preceding half-scale trial: 35% smaller in each dimension.
## Public spaces and gameplay buildings do not use this decorative scale.
const DECOR_SIZE_FACTOR := 0.65
const DECOR_SCALE := 0.5 * DECOR_SIZE_FACTOR
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Sprites := preload("res://scripts/building_sprites.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")

static func residential(tile: Dictionary, p: Vector2, edge_centers: Array, harbours: Array = []) -> bool:
	for shore in harbours:
		if p.distance_to(shore)<240.0: return false
	if str(tile.type) != "urban": return true
	for center in edge_centers:
		var offset: Vector2 = center - tile.center
		if offset.length() < 510.0 and (p - tile.center).dot(offset.normalized()) > 130.0: return true
	return false

## Dense urban infill everywhere. Retain the approved Stoneshore fringe, but
## other rural tiles keep their existing hamlets rather than becoming suburbs.
static func dense_tiles(model: Dictionary) -> Array:
	var result: Array=[]
	for tid in model.tiles:
		if str(model.tiles[tid].type)=="urban" or tid in TILES: result.append(tid)
	return result

static func populate(model: Dictionary, terrain: Node = null) -> void:
	if "--stoneshore-baseline" in preload("res://scripts/demo_build.gd").user_args(): return
	var scope := dense_tiles(model)
	model.standing = model.standing.filter(func(s: Dictionary) -> bool:
		return str(s.tile) not in scope or str(s.kind) != "house")
	# Rural hamlets use the same kit scale; do not multiply repeatedly on rebuild.
	for s in model.standing:
		if str(s.kind)!="house" or s.get("decor_scale",0.0)==DECOR_SCALE: continue
		s.side=Scale.TERRACE_ROW_SIDE*DECOR_SCALE
		s.pad=s.side; s.decor_scale=DECOR_SCALE
		s.erase("footprint");s.erase("footprints")
	var edge_centers: Array = []
	if terrain != null:
		var ids := {}
		for tid in scope:
			for other in Catalog.tile_neighbours(tid):
				if Catalog.tile_type(other)!="urban": ids[other]=true
		for tid in ids: edge_centers.append(preload("res://scripts/empire_board_model.gd").tile_center(terrain,tid))
	else:
		for tile in model.tiles.values():
			if str(tile.type)!="urban": edge_centers.append(tile.center)
	var harbours: Array=[]
	for s in model.standing:
		if s.has("harbour"): harbours.append(s.harbour.shore_anchor)
	model.trial_targets = {}
	model.trial_residential_limits = RESIDENTIAL_LIMITS.duplicate()
	model.dense_tiles = scope
	for tid in scope:
		model.trial_targets[tid] = int(TARGET_BUILDINGS.get(tid,12))
		model.trial_residential_limits[tid] = int(RESIDENTIAL_LIMITS.get(tid,14))
		var tile: Dictionary = model.tiles[tid]
		var local_edges: Array=edge_centers.filter(func(c):return c.distance_to(tile.center)<510.0)
		var local_harbours: Array=harbours.filter(func(c):return c.distance_to(tile.center)<550.0)
		var points: Array = []
		for y in range(-210, 211, 26):
			for x in range(-210, 211, 26):
				var id := "%s:%d:%d" % [tid, x, y]
				points.append({"p": tile.center + Vector2(x,y), "order": absi(hash(id))})
		points.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return a.order < b.order)
		for i in points.size():
			var p: Vector2 = points[i].p
			var housing := residential(tile,p,local_edges,local_harbours)
			var family: String = ["house","civic_office","civic_commercial","house","civic_l","civic_office","civic_commercial","civic_u_office"][i%8]
			var level := 1 # house_lvl1 is the compact flat-roof apartment block
			if housing:
				family = "civic_semi" if i%4!=3 else "house"
				level = 1 if family == "civic_semi" else 2 + i%2
			var side := Scale.TERRACE_ROW_SIDE if family == "house" else (Scale.semi_side() if family == "civic_semi" else 12.0 / maxf(Assets.storey_height(Assets.key_for(family,level)), .01))
			var standing := {"iid": "z_trial:%s:%04d" % [tid,i], "kind": "house", "tile":tid,
				"pos":p, "side":side * DECOR_SCALE, "pad":side * DECOR_SCALE, "level":level,
				"decor_scale":DECOR_SCALE, "trial_density":true, "trial_residential":housing,
				"trial_tile":tile, "trial_edge_centers":local_edges, "trial_harbours":local_harbours,
				"polluting":false, "max_relief":6.0,
				"name":"Semi-detached homes" if family=="civic_semi" else ("Apartments" if family=="house" and not housing else "Neighbourhood building"),
				"sprite":Sprites.texture_for("house",level) if family == "house" else null}
			if family != "house": standing.decor_family = family
			model.standing.append(standing)
		# Public space sites sit within the cells, not on the Voronoi edges.
		var gardens: Array=[]
		for plot in model.get("district_blocks",{}).get("plots",[]):
			if plot.tile==tid: gardens.append(plot.pos)
		if gardens.is_empty():
			for i in range(0,points.size(),12): gardens.append(points[i].p)
		for i in gardens.size():
			var p: Vector2=gardens[i]
			if harbours.any(func(shore): return p.distance_to(shore)<225): continue
			for family in (SPACES if str(tile.type)=="urban" else ["civic_grove"]):
				if family=="civic_pond" and tid=="tile_5_10": continue
				var side: float={"civic_pond":76.0,"civic_grove":54.0,"civic_park":44.0,"civic_plaza":38.0}[family]
				model.standing.append({"iid":"z0_green:%s:%d:%03d" % [tid,SPACES.find(family),i],
					"kind":"house","tile":tid,"pos":p,"side":side,"pad":side,"level":1,
					"decor_family":family,"trial_green":true,"fixed_plot":true,"space_slot":str(i),
					"sprite":null,"polluting":false,"max_relief":0.8 if family=="civic_pond" else 2.0,"name":"Wooded pond" if family=="civic_pond" else "Neighbourhood green"})
	# Three compact skyline landmarks take precedence over small decorative plots.
	# Landmarks share the same size reduction as ordinary decoration at every LOD.
	if model.tiles.has("tile_5_10"):
		var center: Vector2=model.tiles.tile_5_10.center
		for i in 3:
			var family := "civic_u_office" if i==2 else "towers"
			var level := 1 if i!=1 else 2
			var side := (45.3 if i==2 else (30.0 if i==0 else 34.0)) * DECOR_SIZE_FACTOR
			model.standing.append({"iid":"z0_docks_skyline:%d"%i,"kind":"house","tile":"tile_5_10",
				"pos":center+[Vector2(-60,-5),Vector2(-30,50),Vector2(-90,65)][i],
				"side":side,"pad":side,"level":level,"decor_family":family,"decor_scale":DECOR_SCALE,
				"trial_skyline":center,"trial_max_distance":135.0,"trial_density":true,
				"polluting":false,"max_relief":6.0,"sprite":null,"name":"Docks skyline"})
	# Reserve one factory first, on the landward approach to the actual harbour.
	for port in model.standing.duplicate():
		if str(port.tile) not in TILES or not port.has("harbour"): continue
		# port.pos is the centre of the offshore piers. Use the shore contact,
		# then search inland, so a factory stays beside the port on dry land.
		var shore: Vector2 = port.harbour.shore_anchor
		var p: Vector2 = shore - (port.harbour.offshore as Vector2) * 60.0
		var side := 12.0 / Assets.storey_height(Assets.key_for("civic_bauhaus",1)) * DECOR_SCALE
		model.standing.append({"iid":"z0_trial_port_factory", "kind":"house", "tile":str(port.tile),
			"pos":p, "side":side, "pad":side, "level":1, "decor_scale":DECOR_SCALE,
			"decor_family":"civic_bauhaus", "trial_density":true, "trial_port":shore, "trial_max_distance":180.0,
			"sprite":null, "polluting":false, "name":"Harbour Bauhaus works", "max_relief":6.0})
		break
