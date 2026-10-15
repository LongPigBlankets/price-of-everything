extends RefCounted
## Builds the supply-chain world's static geometry. Map-space coordinates and the shared
## height field are authoritative; the camera never participates in generation.
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const HarbourTraffic := preload("res://scripts/supply_chain_3d/harbour_traffic.gd")
var harbour_traffic: Array = []
const Harbour := preload("res://scripts/supply_chain_3d/harbour.gd")
const Coast := preload("res://scripts/supply_chain_3d/coast.gd")
const Legacy := preload("res://scripts/empire_board.gd")
const Model := preload("res://scripts/empire_board_model.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")
const Relief := preload("res://scripts/supply_chain_3d/relief.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const BuildingScale := preload("res://scripts/supply_chain_3d/building_scale.gd")
const ShadowArt := preload("res://scripts/supply_chain_3d/shadow_art.gd")
const FarSprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const PylonCables := preload("res://scripts/supply_chain_3d/pylon_cables.gd")
const Railway := preload("res://scripts/supply_chain_3d/railway.gd")
const RoadGrade := preload("res://scripts/supply_chain_3d/road_grade.gd")
const RailUrban := preload("res://scripts/supply_chain_3d/rail_urban.gd")
const RailDepot := preload("res://scripts/supply_chain_3d/rail_depot.gd")
var road_grade := RoadGrade.new()
var road_alignment := preload("res://scripts/supply_chain_3d/road_alignment.gd").new()
var rail_urban := RailUrban.new()
var rail_plan := {}
var sea_fringe := preload("res://scripts/supply_chain_3d/sea_fringe.gd").new()
var depots: Array = []
var stations: Array = []
var neighbourhood := {}
const RailStation := preload("res://scripts/supply_chain_3d/rail_station.gd")
var transport_ready := false
var pylon_layout: Dictionary = {}
const CELL := 12.0
const Detail := preload("res://scripts/supply_chain_3d/detail.gd")
const Paint := preload("res://scripts/supply_chain_3d/terrain_paint.gd")
const GroundShader := preload("res://scripts/supply_chain_3d/ground.gdshader")
const TreeLayout := preload("res://scripts/supply_chain_3d/tree_layout.gd")
const RailVegetation := preload("res://scripts/supply_chain_3d/rail_vegetation.gd")
var rail_vegetation := RailVegetation.new()
var _prepared_rail_art := {}
const GlintShader := preload("res://scripts/supply_chain_3d/water_glints.gdshader")
const RoadSurface := preload("res://scripts/supply_chain_3d/road_surface.gd")
const BakeCache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Residency := preload("res://scripts/supply_chain_3d/detail_residency.gd")
const LocalDetail := preload("res://scripts/supply_chain_3d/local_detail.gd")
const FarmFields := preload("res://scripts/supply_chain_3d/farm_fields.gd")
var farm_nodes: Array = []
var far_field_meshes: Array = []
const TileCache := preload("res://scripts/supply_chain_3d/tile_resource_cache.gd")
var resource_cache := TileCache.new()
const Handover := preload("res://scripts/supply_chain_3d/lod_handover.gd")
var handover := Handover.new()
var handover_enabled := false
var _handover_preparing := false
var terrain_lods: Array = []
var detail_nodes: Array = []
var building_visuals: Array = []
var sprite_pairs: Array = []
var tree_sprite_nodes: Array = []
var tree_sprite_transforms: Dictionary = {}
var _sprites_visible := false
var _asset_tier := -1
var grade_range := Vector2.ZERO
var active_lod := -1
var lazy_assets := false
var shadow_batch := Geo.Batch.new()
var standing_shadow_mesh: Mesh
var infrastructure_bake := {}
var origin := Vector2.ZERO
var ground: RefCounted
var rivers: Dictionary = {}
var tiles: Dictionary = {}
var terrain_cache: Dictionary = {}
var mat := ShaderMaterial.new()
var line_mat := Geo.material(true)
var bounds := AABB()
var pickables: Array = []
var labels: Array = []
var flows: Array = []
var cars: Array = []
var smoke: Array = []
var glows: Array = []
var roads: Array = []
var lines: Array = []
var tree_placements: Dictionary = {}
var urban_plazas := {"tiles":{}}
var greenery_audit := {}
var road_surface := RoadSurface.new()
var pits: Dictionary = {}
var streamed := false
const BASE_RESIDENT_TILES := 96
var local_tiles: Dictionary = {}
var residency := Residency.new()
var backdrop_materials: Array = []
var local_streaming := false
var view_hulls: Dictionary = {}
var _visibility_standing: Dictionary = {}
var _visibility_centers: Dictionary = {}
const VISIBILITY_VERSION := 5
const FOUNDATION_VERSION := 3
const Footprints := preload("res://scripts/supply_chain_3d/building_footprints.gd")
const Sidewalks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
var tree_nodes: Array = []
var far_nodes: Array = []
var decor_nodes: Array = []
var _overview := false
var _river_buckets: Dictionary = {}
var _road_height_cache: Dictionary = {}
var road_mat: ShaderMaterial
var glint_nodes: Array = []
var bake_cache := BakeCache.new()
var _map_key := ""
var _continent_key := ""
var _previous_continent_key := ""
var continent: Dictionary = {}
var continent_node: Node3D
var continent_body: StaticBody3D
var road_nodes: Array = []
var _road_key := ""
var authored_profile := preload("res://scripts/supply_chain_3d/authored_road_profile.gd").new()
var frame_nodes: Array = []
var rim_material: ShaderMaterial
var scenery_ready := false
var static_shadows: Dictionary = {}
var decor_sprite_transforms: Dictionary = {}
var standing_frames: Dictionary = {}
var prepared_foundations: Dictionary = {}
var prepared_continent_pick: Shape3D
var prepared_authored_profile: Dictionary = {}
var prepared_mine_rims: Mesh
var backdrop_pending := false
var progressive_tiles := false
var ready_tiles: Dictionary = {}
var paper_owned_tiles: Dictionary = {}
var pending_infrastructure: Array[Node3D] = []
var progressive_manifest: Dictionary = {}
var tile_load_resources: Dictionary = {}
var _scenery_key := ""
var tile_chunks: Dictionary = {}
var base_ready := true
var base_loading := false
var _chunk_data: Dictionary = {}
var _detail_standing: Array = []
var _repair_chunks: Dictionary = {}
## Board-controlled picking residency is independent of visual/resource residency.
var cursor_picking := false
var collision_tiles: Dictionary = {}
var collision_revision := 0

var transport_key := ""
var transport_profile := {}
const TransportBake := preload("res://scripts/supply_chain_3d/transport_bake.gd")

func prepare_transport(model: Dictionary) -> void:
	var start := Time.get_ticks_usec()
	roads=model.get("roads",[]); lines=model.get("lines",[]); depots=model.get("depots",[]); stations=model.get("stations",[]); neighbourhood=model.get("neighbourhood",{})
	_index_rivers()
	transport_key=TransportBake.key_for(self,model)
	var cached := bake_cache.read(transport_key)
	var hit := TransportBake.restore(self,cached)
	var stages := {"lookup_ms":(Time.get_ticks_usec()-start)/1000.0,"cache_hit":hit}
	if not hit:
		var tick := Time.get_ticks_usec()
		authored_profile.configure(model.get("authored_region",{}),rivers,natural_height,open_water)
		stages.authored_ms=(Time.get_ticks_usec()-tick)/1000.0; tick=Time.get_ticks_usec()
		roads=road_alignment.configure(model,formation_height,railway_level,open_water)
		stages.alignment_ms=(Time.get_ticks_usec()-tick)/1000.0; tick=Time.get_ticks_usec()
		preload("res://scripts/supply_chain_3d/port_approach.gd").grade(roads,model.get("port_approach",{}))
		road_grade.configure(roads,formation_height,authored_profile)
		stages.grading_ms=(Time.get_ticks_usec()-tick)/1000.0; tick=Time.get_ticks_usec()
		rail_plan=Railway.network(lines)
		rail_urban.configure(tiles,road_grade.segments,road_grade.junctions,rail_plan,depots,railway_ground_height,railway_level,stations,model.get("standing",[]),standing_key,river_at)
		preload("res://scripts/supply_chain_3d/rail_crossings.gd").build(road_grade,rail_plan,rail_urban,depots)
		stages.rail_ms=(Time.get_ticks_usec()-tick)/1000.0
		bake_cache.write(transport_key,TransportBake.packed(self))
	model.roads=roads
	transport_ready=true
	if model.has("flows") and model.get("authored_region",{}).has("tiles"):
		preload("res://scripts/supply_chain_3d/authored_region.gd").reroute_flows(model,model.authored_region.tiles,roads)
	stages.total_ms=(Time.get_ticks_usec()-start)/1000.0
	transport_profile=stages
	print("[TRANSPORT] ",JSON.stringify(stages))

func configure_bakes(model: Dictionary) -> void:
	sea_fringe.configure(tiles,ground.get("tiles"))
	# Hash actual geography, never an instance ID: this survives a fresh process.
	_map_key = BakeCache.digest([BakeCache.source_key("terrain"), ground.get("tiles"), ground.get("bands"),
		ground.get("lakes"), ground.get("rivers"), MapStyle.band_colors(), MapStyle.sea_colors(),
		model.get("roads",[]),model.get("lines",[]),model.get("depots",[]),model.get("stations",[]),model.get("neighbourhood",{}),BakeCache.source_key("roads")])
	var authored: Dictionary = model.get("authored_region", {})
	_road_key = BakeCache.digest([BakeCache.source_key("roads"), _map_key, model.get("roads", []),
		authored.get("tiles", {}), authored.get("paths", []), pits])
	var layout: Array = []
	var geography: Array = []
	var pipes: Array = []
	var assets: Dictionary = {}
	var sprite_geometry: Dictionary = {}
	for tid in tiles: geography.append([tid, tiles[tid].center, tiles[tid].type])
	for s in model.get("standing", []):
		var key := standing_key(s)
		assets[key] = Assets.dimensions(key)
		if FarmFields.is_plot(s):
			var cell := Assets.key_for("farm_crop_cell", 1)
			assets[cell] = [Assets.dimensions(cell), Assets.component_for(cell)]
		if s.has("harbour"):
			var harbour_key := Assets.key_for("port", 1)
			assets["harbour:" + harbour_key] = Assets.harbour_for(harbour_key)
		sprite_geometry[key] = [FarSprites.center(key), FarSprites.entry(key).get("span", 0.0)]
		layout.append([s.iid, s.kind, s.tile, s.pos, s.side, s.get("pad", s.side), s.get("internal_name", ""), s.get("tall", false), s.get("level", 1),
			(s.sprite as Texture2D).resource_path if s.get("sprite") is Texture2D else "", s.get("harbour", {}), s.get("yaw", 0.0), s.get("footprints", [s.get("footprint", [])]), s.get("decor_family", ""), s.get("decor_asset", ""), s.get("decor_scale", 1.0)])
	for line in model.get("lines", []):
		if Model.PIPE_MODES.has(str(line.mode)): pipes.append([line.mode, line.pts])
	if Legacy.show.trees:
		for level in range(1, 4):
			var key := Assets.key_for("tree", level)
			assets[key] = [Assets.dimensions(key), Assets.projected_height(key)]
			sprite_geometry[key] = [FarSprites.center(key), FarSprites.entry(key).get("span", 0.0)]
	# These bakes contain placements, dimensions and terrain, not the building
	# artwork. An unrelated asset addition or repaint must not rebuild 600 tiles.
	_scenery_key = "scenery-" + BakeCache.digest([BakeCache.source_key("scenery"), BakeCache.source_key("buildings"), _road_key, geography, layout, pipes, Legacy.show.trees, Legacy.show.decor,
		assets])
	_continent_key = "continent-" + BakeCache.digest([BakeCache.source_key("continent"), _scenery_key, _road_key, geography, layout, pipes, Legacy.show.trees, Legacy.show.roads, Legacy.show.decor,
		sprite_geometry])
	_previous_continent_key = _continent_key
	_continent_key = "continent-" + BakeCache.digest([_previous_continent_key, FOUNDATION_VERSION])

func tile_bake_key(tid: String, tier: int) -> String:
	var holes: Array = []
	var area := Rect2((tiles[tid].center as Vector2) - Model.HEX_HALF, Model.HEX_HALF * 2.0).grow(16.0)
	for pit in pits.values():
		# The graded shoulder reaches beyond the excavation polygon and can
		# alter a neighbouring tile even when the opening stays outside it.
		var reach := float(pit.side) * 0.80
		if area.intersects(Rect2((pit.pos as Vector2) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
			holes.append(pit)
	return "tile-" + BakeCache.digest([_map_key, tid, tiles[tid].center, tiles[tid].type, holes, static_shadows.get(tid, []), urban_plazas.tiles.get(tid,[]), tier])

func prepare_scenery(host: Node, model: Dictionary) -> void:
	var water_review := "--water-review" in OS.get_cmdline_user_args()
	_detail_standing = model.get("standing", [])
	_visibility_standing.clear()
	for s in model.get("standing", []):
		(_visibility_standing.get_or_add(str(s.tile), []) as Array).append(s)
	var cached := bake_cache.read(_scenery_key) if _scenery_key != "" else {}
	if not cached.is_empty():
		tree_placements = cached.trees
		urban_plazas = cached.get("urban_plazas",{"tiles":{}})
		greenery_audit = cached.get("greenery_audit",{})
		static_shadows = cached.shadows
		standing_frames = cached.standing
		grade_range = cached.grade
		infrastructure_bake = cached.get("infrastructure", {})
		rail_vegetation.restore(cached.get("vegetation", {}))
		standing_shadow_mesh = cached.get("standing_shadows")
		if not prepared_authored_profile.is_empty():
			for field in prepared_authored_profile: authored_profile.set(field, prepared_authored_profile[field])
		elif cached.has("road_profile"): authored_profile.restore(cached.road_profile)
		else: authored_profile.configure(model.get("authored_region", {}), rivers, natural_height, open_water)
		if standing_shadow_mesh == null: prepare_standing_shadows(model.get("standing", []))
		scenery_ready = true
		return
	authored_profile.configure(model.get("authored_region", {}), rivers, natural_height, open_water)
	# Derive clearance from the exact railway that will be drawn, then reuse
	# those meshes in infrastructure(). Never do this work before a scenery hit.
	roads = model.get("roads", [])
	lines = model.get("lines", [])
	_prepare_rail_art()
	if water_review: print("[WATER REVIEW] rail art ", Time.get_ticks_msec())
	rail_vegetation.configure(_prepared_rail_art, road_grade.segments if transport_ready else roads,
		road_alignment.portals, depots, tiles, natural_height)
	if water_review: print("[WATER REVIEW] rail rows ", Time.get_ticks_msec())
	urban_plazas=preload("res://scripts/supply_chain_3d/urban_plazas.gd").build(self,model.get("standing",[]))
	var all_shadows: Array = []
	for s in model.get("standing", []):
		standing_frames[str(s.iid)] = standing_frame(s)
		if str(s.kind) == "house" and not preload("res://scripts/supply_chain_3d/civic_layout.gd").is_space(s):
			all_shadows.append(ShadowArt.footprint(s.pos, float(s.side), false))
	roads = model.get("roads", [])
	lines = model.get("lines", [])
	for tid in tiles:
		var placements := placements_for(str(tid), model.get("standing", [])) if Legacy.show.trees else []
		if Legacy.show.trees and (str(tiles[tid].type)=="urban" or tid in preload("res://scripts/supply_chain_3d/stoneshore_trial.gd").TILES):
			var planted := preload("res://scripts/supply_chain_3d/stoneshore_greenery.gd").new().plant(str(tid),placements,self,model.get("standing",[]),urban_plazas.tiles.get(tid,[]))
			placements=planted.trees;greenery_audit[tid]=planted.audit
		tree_placements[tid] = placements
		for tree in placements:
			var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[tree.kind])
			var scale := float(tree.height) / Assets.projected_height(key)
			all_shadows.append(ShadowArt.footprint(tree.pos, Assets.dimensions(key).x * scale, true))
		if tree_placements.size() % 16 == 0:
			if water_review and tree_placements.size() % 64 == 0: print("[WATER REVIEW] placements ", tree_placements.size(), " ", Time.get_ticks_msec())
			await host.get_tree().process_frame
			if not is_instance_valid(host) or not host.is_inside_tree(): return
	# A shadow can reach over a hex edge. Include it in both tile painters so
	# filtering and changing terrain tiers cannot cut its footprint at that edge.
	var buckets := {}
	for i in all_shadows.size():
		var area := ShadowArt.bounds(all_shadows[i])
		var low := Vector2i((area.position / 256.0).floor())
		var high := Vector2i((area.end / 256.0).floor())
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1): (buckets.get_or_add(Vector2i(x, y), []) as Array).append(i)
	for tid in tiles:
		var area := Rect2(tiles[tid].center - Paint.EXTENT * 0.5, Paint.EXTENT)
		var low := Vector2i((area.position / 256.0).floor())
		var high := Vector2i((area.end / 256.0).floor())
		var found := {}
		for y in range(low.y, high.y + 1):
			for x in range(low.x, high.x + 1):
				for i in buckets.get(Vector2i(x, y), []):
					if area.intersects(ShadowArt.bounds(all_shadows[i])): found[i] = true
		static_shadows[tid] = []
		var ids := found.keys()
		ids.sort()
		for i in ids: static_shadows[tid].append(all_shadows[i])
	scenery_ready = true
	configure_grade()
	prepare_standing_shadows(model.get("standing", []))
	if _scenery_key != "": bake_cache.write(_scenery_key, scenery_data())

func scenery_data() -> Dictionary:
	return {"trees": tree_placements, "urban_plazas":urban_plazas,"greenery_audit":greenery_audit, "shadows": static_shadows, "standing": standing_frames, "grade": grade_range,
		"road_profile": authored_profile.packed(), "standing_shadows": standing_shadow_mesh, "infrastructure": infrastructure_bake,
		"vegetation": rail_vegetation.packed()}

func prepare_standing_shadows(standing: Array) -> void:
	var previous := shadow_batch
	shadow_batch = Geo.Batch.new()
	for s in standing:
		if str(s.kind) in ["house", "pylon"] or s.has("harbour") or pits.has(str(s.iid)): continue
		shadow(s.pos, float(s.side))
	standing_shadow_mesh = shadow_batch.mesh()
	shadow_batch = previous

func open_water(p: Vector2) -> bool:
	var tid: String = ground.tile_at(p)
	if tid == "": return true
	return Ground.is_water(Coast.relief_of(tid, ground.tiles[tid].center), p)

func placements_for(tid: String, standing: Array) -> Array:
	if tree_placements.has(tid): return tree_placements[tid]
	var tile: Dictionary = tiles[tid]
	var area := Rect2(tile.center - Model.HEX_HALF, Model.HEX_HALF * 2.0).grow(30.0)
	var local_roads: Array = []
	for road in roads:
		if area.intersects(Rect2(road.a, Vector2.ZERO).expand(road.b).grow(20.0)): local_roads.append(road)
	var local_standing: Array = []
	for item in standing:
		if (item.pos as Vector2).distance_squared_to(tile.center) < 500000.0: local_standing.append(item)
	var result := TreeLayout.placements(tid, tile, Coast.relief_of(tid, tile.center), local_standing, local_roads, lines, rivers.get(tid, []), rail_vegetation, surface_height)
	return result.filter(func(tree):
		for site in neighbourhood.get("brownfields",[]):
			if Geometry2D.is_point_in_polygon(tree.pos,site.polygon): return false
		for station in stations:
			if Geometry2D.is_point_in_polygon(tree.pos,RailStation.polygon(station)): return false
		for depot in depots:
			var q: Vector2 = (tree.pos-depot.pos).rotated(-depot.yaw)
			if Rect2(-150,-48,300,110).has_point(q): return false
		return true)

func prepare_continent(host: Node) -> void:
	continent = bake_cache.read(_continent_key) if _continent_key != "" else {}
	if continent.is_empty() and not _previous_continent_key.is_empty():
		var previous := bake_cache.read(_previous_continent_key)
		if not previous.is_empty():
			# Only the joined foundations changed. Reuse every terrain texture,
			# tile chunk, road and tree without a continent repaint.
			continent = previous.duplicate()
			var foundations := Geo.Batch.new()
			for group in _visibility_standing.values():
				for standing in group:
					if str(standing.kind) == "house":
						var frame := standing_frame(standing)
						_append_foundation(foundations, standing, frame, frame.position)
			continent.props_mesh = foundations.mesh()
			bake_cache.write(_continent_key, continent)
	if not continent.is_empty():
		tile_chunks = continent.get("tile_chunks", {})
		base_ready = false
		bounds = continent.metadata.bounds
		labels = continent.metadata.get("labels", []).duplicate(true)
		await prepare_visibility_bounds(host, continent.metadata.get("visibility", {}))
		return
	var area := Rect2()
	var first := true
	var parts := {}
	for tid in tiles:
		var tile_area := Rect2((tiles[tid].center as Vector2) - Paint.EXTENT * 0.5, Paint.EXTENT)
		area = tile_area if first else area.merge(tile_area)
		first = false
		parts[tid] = _surface(str(tid), 24.0)
		tile_view_hull(str(tid))
		if parts.size() % 16 == 0:
			await host.get_tree().process_frame
	var texture := await Paint.bake_continent(host, tiles, rivers, pits.values(), surface_height, area, static_shadows, urban_plazas.tiles)
	continent = {"area": area, "texture": texture, "parts": parts,
		"mesh": Geo.joined(parts.values(), area), "roads": {}}

func tile_view_hull(tid: String) -> PackedVector3Array:
	if not view_hulls.has(tid):
		var center: Vector2 = tiles[tid].center
		var low := center - Model.HEX_HALF
		var high := center + Model.HEX_HALF
		var heights := Vector2(INF, -INF)
		if ground.has_method("node"):
			# Every spline sample is a positive weighted average of these lattice
			# nodes. Their extrema conservatively bound every terrain LOD, including
			# a summit between the centre and the six corners of the tile.
			var start := (low / Ground.NODE).floor() - Vector2.ONE
			var end := (high / Ground.NODE).ceil() + Vector2.ONE * 2.0
			for y in range(int(start.y), int(end.y) + 1):
				for x in range(int(start.x), int(end.x) + 1):
					var h := Relief.height(ground.node(x, y))
					heights.x = minf(heights.x, h)
					heights.y = maxf(heights.y, h)
		else:
			# Small synthetic/tool ground providers have no lattice to inspect.
			for p in Model.hex_points(center):
				var h := surface_height(p)
				heights.x = minf(heights.x, h)
				heights.y = maxf(heights.y, h)
			heights.x = minf(heights.x, surface_height(center))
			heights.y = maxf(heights.y, surface_height(center))
		if ground.get("water_geography") == true:
			# Exact lake lips/islets can be narrower than the height lattice.
			# Include their extrema in the baked culling bounds as well.
			if ground.tiles[tid].water: heights.y = maxf(heights.y, Relief.height(34.0))
			for lake in Coast.Water.lakes():
				if (lake.box as Rect2).grow(24.0).intersects(Rect2(low, high - low)):
					heights.x = minf(heights.x, Relief.height(lake.level))
					heights.y = maxf(heights.y, Relief.height(lake.plate))
		for pit in pits.values():
			if Rect2(low, high - low).intersects(pit.area.grow(float(pit.side))):
				heights.x = minf(heights.x, float(pit.height) - float(pit.sink))
				heights.y = maxf(heights.y, float(pit.height))
		if _visibility_centers.is_empty():
			for tile in tiles.values(): _visibility_centers[Vector2i((tile.center as Vector2).round())] = true
		var bottom := heights.x - 24.0
		var hex := Model.hex_points(center)
		for i in 6:
			if not _visibility_centers.has(Vector2i((hex[i] + hex[(i + 1) % 6] - center).round())):
				bottom = minf(bottom, -150.0) # the visible outer cutaway slab
		var box := AABB(Vector3(low.x - origin.x, bottom, low.y - origin.y),
			Vector3(high.x - low.x, heights.y - bottom, high.y - low.y))
		for s in _visibility_standing.get(tid, []):
			var frame := standing_frame(s)
			var basis := Basis(Vector3.UP, float(s.get("yaw", 0.0)))
			var anchor: Vector3 = frame.position + basis * (FarSprites.center(frame.key) * BuildingScale.for_asset(frame.key, float(s.side), float(s.get("decor_scale", 1.0)))) if str(frame.key) != "" else frame.position + Vector3.UP * float(frame.dimension.y) * 0.5
			box = box.merge(_sprite_view_bounds(anchor, rotated_extent(frame.dimension, basis)))
		for tree in tree_placements.get(tid, []):
			var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[tree.kind])
			var scale := float(tree.height) / Assets.projected_height(key)
			var dimension := Assets.dimensions(key) * scale
			var anchor := point(tree.pos) + FarSprites.center(key) * scale
			box = box.merge(_sprite_view_bounds(anchor, dimension))
		box = box.grow(16.0) # outlines, foundations and sprite angle quantisation
		var hull := PackedVector3Array([point(center)])
		for i in 8: hull.append(box.get_endpoint(i))
		view_hulls[tid] = hull
	return view_hulls[tid]

static func rotated_extent(dimension: Vector3, basis: Basis) -> Vector3:
	return basis.x.abs() * dimension.x + basis.y.abs() * dimension.y + basis.z.abs() * dimension.z

static func _sprite_view_bounds(anchor: Vector3, dimension: Vector3) -> AABB:
	# A depth card at the nearest baked angle effectively rotates its source
	# around the anchor. Bound that displacement too, especially tall chimneys.
	var angular_slack := dimension.length() * 0.5 * (PI / 16.0 + (1.35 - 0.30) / 8.0)
	return AABB(anchor - dimension * 0.5, dimension).grow(angular_slack)

func visibility_bake() -> Dictionary:
	return {"version": VISIBILITY_VERSION, "origin": origin, "hulls": view_hulls}

func _restore_visibility(data: Dictionary) -> bool:
	if data.get("version", -1) != VISIBILITY_VERSION or data.get("origin") != origin: return false
	var hulls: Dictionary = data.get("hulls", {})
	if hulls.size() != tiles.size(): return false
	for tid in tiles:
		if not hulls.get(tid) is PackedVector3Array or hulls[tid].size() != 9: return false
	view_hulls = hulls
	return true

func visibility_bake_key() -> String:
	return "visibility-" + BakeCache.digest([_continent_key, origin, VISIBILITY_VERSION])

func prepare_visibility_bounds(host: Node, baked: Dictionary = {}) -> void:
	if _restore_visibility(baked): return
	# Old continent bakes can acquire the small metadata supplement without
	# invalidating their artwork or rewriting hundreds of geometry chunks.
	var key := visibility_bake_key()
	if _continent_key != "" and _restore_visibility(bake_cache.read(key)): return
	view_hulls.clear()
	for tid in tiles:
		tile_view_hull(str(tid))
		if view_hulls.size() % 16 == 0: await host.get_tree().process_frame
	if _continent_key != "": bake_cache.write(key, visibility_bake())

func base_chunk(tid: String) -> Dictionary:
	if _chunk_data.has(tid): return _chunk_data[tid]
	var key := str(tile_chunks.get(tid, ""))
	var data := bake_cache.read(key) if key != "" else {}
	if data.is_empty():
		# A user cache can be partially evicted. Recreate only the requested tile;
		# the existing far resource remains usable while detail is repaired.
		data = {"mesh": _surface(tid, 24.0)}
		_repair_chunks[tid] = true
	_chunk_data[tid] = data
	return data

func prepare_local_detail(tid: String, standing: Array) -> Dictionary:
	var chunk := base_chunk(tid)
	var fingerprint := BakeCache.source_key("detail")
	if chunk.get("detail_source", "") != fingerprint or not chunk.has("local_detail"):
		chunk.local_detail = LocalDetail.build(self, tid, standing)
		chunk.detail_source = fingerprint
	return chunk.local_detail

static func prepare_picking(data: Dictionary) -> void:
	if not data.get("pick_shape") is ConcavePolygonShape3D:
		data.pick_shape = (data.mesh as Mesh).create_trimesh_shape()

func persist_base_chunk(tid: String) -> void:
	if not _repair_chunks.has(tid): return
	var data: Dictionary = _chunk_data[tid]
	if not data.has("rim_mesh") or (Legacy.show.roads and not data.has("roads_mesh")): return
	var key := str(tile_chunks.get(tid, ""))
	if key != "": bake_cache.write(key, data)
	_repair_chunks.erase(tid)

func finish_continent(parent: Node3D) -> void:
	if continent.is_empty(): return
	if not continent.has("roads_mesh"):
		bake_cache.defer_trim = true
		continent.roads_mesh = Geo.joined(continent.roads.values())
		var props: Array = []
		props.append_array(far_field_meshes)
		for node in far_nodes:
			if node is MeshInstance3D: props.append(node.mesh)
			for child in node.find_children("*", "MeshInstance3D", true, false): props.append(child.mesh)
		continent.props_mesh = Geo.joined(props)
		far_field_meshes.clear()
		continent.tree_sprites = tree_sprite_transforms
		continent.decor_sprites = decor_sprite_transforms
		var rims: Array = []
		var lips: Array = []
		for frame in frame_nodes:
			rims.append(frame.rim.mesh)
			lips.append(frame.lip.mesh)
			var tid := str(frame.tile)
			var chunk := {"mesh": continent.parts[tid], "roads_mesh": continent.roads.get(tid),
				"rim_mesh": frame.rim.mesh, "lip_mesh": frame.lip.mesh}
			var key := "base-tile-" + BakeCache.digest([BakeCache.source_key("continent"), _road_key, tid, tiles[tid].center, tiles[tid].type, tiles.keys()])
			tile_chunks[tid] = key
			# A changed backdrop does not invalidate these independently keyed
			# chunks. In particular, retain their prepared detail and picking data.
			if _continent_key != "":
				if bake_cache.read(key).is_empty(): bake_cache.write(key, chunk)
			else: _chunk_data[tid] = chunk
		continent.rim_mesh = Geo.joined(rims)
		continent.lip_mesh = Geo.joined(lips)
		continent.tile_chunks = tile_chunks
		continent.metadata = {"origin": origin, "bounds": bounds, "grade": grade_range,
			"tiles": tiles.duplicate(true), "labels": labels.duplicate(true), "standing": standing_frames, "scenery_key": _scenery_key,
			"visibility": visibility_bake()}
		# Only string keys link to detail resources. Resource subreferences would
		# eagerly deserialize every tile when opening the far map again.
		continent.erase("parts")
		continent.erase("roads")
		if _continent_key != "":
			bake_cache.write(_continent_key, continent)
			bake_cache.trim()
		bake_cache.defer_trim = false
	continent_node = Node3D.new()
	continent_node.name = "ContinentBake"
	var paint := mat.duplicate() as ShaderMaterial
	paint.set_shader_parameter("textured", true)
	paint.set_shader_parameter("artwork", continent.texture)
	continent_node.add_child(Geo.instance(continent.mesh, paint))
	continent_node.add_child(Geo.instance(continent.roads_mesh, road_mat))
	continent_node.add_child(Geo.instance(continent.props_mesh, mat))
	continent_node.add_child(Geo.instance(continent.rim_mesh, strata_material()))
	continent_node.add_child(Geo.instance(continent.lip_mesh, mat))
	for groups in [continent.get("tree_sprites", {}), continent.get("decor_sprites", {})]:
		for key in groups:
			var grove := FarSprites.grove(key, groups[key], grade_range)
			if grove != null: continent_node.add_child(grove)
	continent_node.visible = false
	parent.add_child(continent_node)
	attach_continent_pick(parent)
	residency.configure(tiles, origin)
	for child in continent_node.get_children():
		if not child is GeometryInstance3D or child.material_override == null: continue
		var material := child.material_override.duplicate() as ShaderMaterial
		material.set_meta("road", child.material_override == road_mat)
		material.set_meta("foliage", str(child.name).begins_with("FarTrees_tree_"))
		child.material_override = material
		residency.bind(material)
		backdrop_materials.append(material)

func attach_continent_pick(parent: Node3D) -> void:
	if continent_body != null: return
	# The joined far surface doubles as the selection surface; tile identity is
	# recovered from its map-space hit position, without 600 duplicate meshes.
	var body := StaticBody3D.new()
	continent_body = body
	body.name = "ContinentPick"
	body.collision_layer = 4 if cursor_picking else 1
	body.collision_mask = 0
	body.set_meta("continent_pick", true)
	var shape := CollisionShape3D.new()
	shape.shape = prepared_continent_pick if prepared_continent_pick != null else (_coarse_pick_shape(continent.mesh) if cursor_picking else (continent.mesh as Mesh).create_trimesh_shape())
	body.add_child(shape)
	parent.add_child(body)

func tile_ready(tid: String) -> bool:
	return local_tiles.has(tid) and (not progressive_tiles or ready_tiles.has(tid))

func reveal_tile(tid: String) -> void:
	ready_tiles[tid] = true
	if backdrop_pending: handover.reset(1.0)
	else: complete_detail_request()
	_apply_view_visibility()

func install_backdrop(parent: Node3D) -> void:
	finish_continent(parent)
	backdrop_pending = false
	for node in pending_infrastructure: node.show()
	pending_infrastructure.clear()
	for item in terrain_lods:
		item.data.textures[0] = continent.texture
		item.data.meshes[0] = base_chunk(item.tile).mesh
		item.data.shapes[0] = base_chunk(item.tile).get("pick_shape")
		apply_tile_detail(item, active_lod)
	_apply_view_visibility()

func prepare_company_pick_surface(parent: Node3D) -> void:
	# Reuse the lowest-detail company surfaces to locate the cursor while detailed
	# tile collision is detached. Continent views already have this shared surface.
	if not cursor_picking or continent_body != null: return
	var meshes: Array = []
	for item in terrain_lods: meshes.append(item.data.meshes[0])
	if meshes.is_empty(): return
	continent_body = StaticBody3D.new()
	continent_body.name = "CompanyPick"
	continent_body.collision_layer = 4
	continent_body.collision_mask = 0
	continent_body.set_meta("continent_pick", true)
	var shape := CollisionShape3D.new()
	shape.shape = _coarse_pick_shape(Geo.joined(meshes))
	continent_body.add_child(shape)
	parent.add_child(continent_body)

func _coarse_pick_shape(mesh: Mesh) -> Shape3D:
	# Mine openings must still select a tile at far zoom when their individual
	# bodies are detached. Cap only the invisible shared locator at the rim level.
	if pits.is_empty(): return mesh.create_trimesh_shape()
	var faces := mesh.get_faces()
	for pit in pits.values():
		var indices := Geometry2D.triangulate_polygon(pit.rim)
		for index in indices: faces.append(at_height(pit.rim[index], pit.height))
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

func collision_detail_visible() -> bool:
	return not _sprites_visible and not _overview and (not handover_enabled or handover.blend >= 1.0)

func set_collision_tiles(wanted: Dictionary) -> void:
	if collision_tiles == wanted: return
	collision_tiles = wanted.duplicate()
	for item in terrain_lods: _sync_tile_collision(item)
	for pair in sprite_pairs:
		if pair.get("standing") is Dictionary: _ensure_standing_pick(pair)

func _sync_tile_collision(item: Dictionary) -> void:
	var active := not cursor_picking or (collision_detail_visible() and collision_tiles.has(str(item.tile)))
	if not active:
		if item.has("collider") and item.collider.shape != null: item.collider.shape = null
		item.collision_tier = -1
		return
	if not item.has("collider"):
		var body := StaticBody3D.new()
		body.name = "TilePick"
		body.collision_layer = 1
		body.collision_mask = 0
		body.set_meta("tile_id", str(item.tile))
		var collider := CollisionShape3D.new()
		body.add_child(collider)
		item.node.get_parent().add_child(body)
		item.collider = collider
	var tier := int(item.get("display_tier", 0)) if streamed or cursor_picking else 0
	if int(item.get("collision_tier", -1)) == tier: return
	item.collider.shape = _terrain_shape(item.data, tier)
	item.collision_tier = tier

func update_residency() -> void:
	residency.update((ready_tiles if progressive_tiles else local_tiles) if not _overview or handover.active else {})
	for material in backdrop_materials:
		material.set_shader_parameter("local_detail_mask", not _overview or handover.active)
		material.set_shader_parameter("local_detail_blend", handover.blend if handover_enabled else 1.0)

func complete_detail_request() -> void:
	if handover_enabled and not _overview and handover.blend < 1.0:
		_begin_handover(1.0)

func _begin_handover(target: float) -> void:
	if handover.active and is_equal_approx(handover.target, target): return
	handover.clear()
	if is_equal_approx(handover.blend, target):
		_apply_view_visibility()
		return
	# Both representations must be drawable before their complementary coverage
	# is applied. Materials are temporary copies; stable shared assets stay intact.
	_handover_preparing = true
	_apply_view_visibility()
	var local: Array = []
	var far: Array = []
	for record in local_tiles.values():
		for node in record.root.find_children("*", "GeometryInstance3D", true, false):
			if node.is_visible_in_tree(): local.append(node)
	for pair in sprite_pairs:
		if pair.get("decor", false): continue # The continent already contains its far houses.
		if streamed and local_streaming and pair.get("standing") is Dictionary and pair.has("tile") and not tile_ready(str(pair.tile)): continue
		if pair.get("far") != null: far.append(pair.far)
		if pair.get("medium") != null and pair.medium.visible: local.append(pair.medium)
		for node in pair.near:
			if node.visible: local.append(node)
	handover.begin(target, local, far)
	_handover_preparing = false
	_apply_view_visibility()

func advance_handover() -> void:
	if not handover.active: return
	handover.advance()
	_apply_view_visibility()

func _apply_view_visibility() -> void:
	if cursor_picking and not collision_detail_visible(): set_collision_tiles({})
	var local := not _overview
	if handover_enabled: local = handover.blend > 0.0 or _handover_preparing
	if backdrop_pending: local = true
	if continent_node != null:
		continent_node.visible = true
		update_residency()
		for item in terrain_lods: item.node.visible = local
		for node in road_nodes: node.visible = local
		for frame in frame_nodes:
			frame.rim.visible = local
			frame.lip.visible = local
	for tid in local_tiles: local_tiles[tid].root.visible = local and tile_ready(tid) and not paper_owned_tiles.has(tid)
	for node in decor_nodes: node.visible = local
	for node in far_nodes: node.visible = _overview and continent_node == null
	for node in glint_nodes: node.visible = local
	_update_asset_tier()

func release_local_tiles(keep: Dictionary, retain_resources: bool = false) -> void:
	for tid in local_tiles.keys():
		if keep.has(tid): continue
		if retain_resources: cache_local_tile(str(tid))
		else: resource_cache.erase(str(tid))
		var record: Dictionary = local_tiles[tid]
		collision_revision += 1
		# Metadata arrays must not retain freed nodes or accumulate duplicate
		# pickables/glows after a pan away and back.
		for field in record.records:
			var items: Array = get(field)
			for value in record.records[field]: items.erase(value)
		record.root.free()
		terrain_cache.erase(terrain_key(tid))
		_chunk_data.erase(tid)
		local_tiles.erase(tid)
		ready_tiles.erase(tid)
	if continent_node != null: update_residency()

func cache_local_tile(tid: String) -> void:
	var key := terrain_key(tid)
	if terrain_cache.has(key): resource_cache.put(tid, terrain_cache[key], _chunk_data.get(tid, {}), Time.get_ticks_msec())

func prefetch_medium(tid: String) -> bool:
	if backdrop_pending: return false
	if not resource_cache.can_prefetch() or local_tiles.has(tid): return false
	var existing: Dictionary = resource_cache.entries.get(tid, {})
	if not existing.is_empty() and existing.data.meshes[1] != null: return false
	# Prefetch never generates scenery or creates a node/collider. Missing bakes
	# remain a foreground repair, so travel cannot launch an invisible rebake.
	var key := str(tile_chunks.get(tid, ""))
	if key == "": return false
	var chunk: Dictionary = existing.get("chunk", {})
	if chunk.is_empty(): chunk = bake_cache.read(key)
	if chunk.is_empty(): return false
	var fine := bake_cache.read(tile_bake_key(tid, 1))
	# Admission can fail after the read. Work on new containers so a rejected
	# upgrade cannot silently grow an existing entry without updating its cost.
	var data: Dictionary = existing.get("data", {"textures": [continent.texture, null, null],
		"meshes": [chunk.mesh, null, null], "streamed": true, "ground_id": ground.get_instance_id()}).duplicate()
	data.textures = data.textures.duplicate()
	data.meshes = data.meshes.duplicate()
	data.shapes = data.get("shapes", [chunk.get("pick_shape"), null, null]).duplicate()
	if not fine.is_empty():
		data.textures[1] = fine.texture
		data.meshes[1] = fine.mesh
		data.shapes[1] = fine.get("pick_shape")
	if not resource_cache.can_prefetch(maxi(0, TileCache.estimate(data, chunk) - int(existing.get("bytes", 0)))): return false
	resource_cache.put(tid, data, chunk, Time.get_ticks_msec())
	return true

func _terrain_shape(data: Dictionary, tier: int) -> Shape3D:
	if not data.has("shapes"): data.shapes = [null, null, null]
	if data.shapes[tier] == null: data.shapes[tier] = (data.meshes[tier] as Mesh).create_trimesh_shape()
	return data.shapes[tier]

func strata_material() -> ShaderMaterial:
	if rim_material == null:
		rim_material = mat.duplicate() as ShaderMaterial
		rim_material.set_shader_parameter("textured", true)
		rim_material.set_shader_parameter("strata", true)
		rim_material.set_shader_parameter("artwork", load("res://assets/iso/ground/strata.png"))
	return rim_material

func tile_at(p: Vector3) -> String:
	var map_point := Vector2(p.x, p.z) + origin
	var nearest := ""
	var distance := INF
	for tid in tiles:
		var d := map_point.distance_squared_to(tiles[tid].center)
		if d <= Model.HEX_HALF.length_squared() and Geometry2D.is_point_in_polygon(map_point, Model.hex_points(tiles[tid].center)): return str(tid)
		if d < distance: nearest = str(tid); distance = d
	return nearest

func configure_pits(standing: Array) -> void:
	pits.clear()
	for s in standing:
		if str(s.get("internal_name", "")) != "mine": continue
		var data := Assets.pit_for(int(s.get("level", 1)))
		if data.is_empty(): continue
		var rim := PackedVector2Array()
		var side := float(s.get("side", 80.0))
		for xy in data.rim: rim.append((s.pos as Vector2) + Vector2(xy[0], xy[1]) * side)
		var area := Rect2(rim[0], Vector2.ZERO)
		for p in rim: area = area.expand(p)
		pits[str(s.iid)] = {"rim": rim, "area": area, "tile": str(s.tile), "height": ground_height(s.pos),
			"sink": float(data.sink) * side, "step": float(data.step) * side, "pos": s.pos, "side": side, "seed": hash(str(s.iid))}

func _mine_grade(p: Vector2) -> Vector2:
	var result := Vector2.ZERO # weight, mine datum
	for pit in pits.values():
		var distance := p.distance_to(pit.pos) / float(pit.side)
		if distance >= 0.80: continue
		var weight := 1.0 - smoothstep(0.62, 0.80, distance)
		if weight > result.x: result = Vector2(weight, pit.height)
	return result

func ground_height(p: Vector2) -> float:
	return Relief.height(ground.height(p))

func natural_height(p: Vector2) -> float:
	var grade := _mine_grade(p)
	return lerpf(ground_height(p), grade.y, grade.x)

func depot_height(p: Vector2, h: float) -> float:
	for depot in depots:
		var q: Vector2 = (p-depot.pos).rotated(-depot.yaw)
		var d := maxf(maxf(-145-q.x,q.x-145),maxf(-47-q.y,q.y-57))
		if d<16: h=lerpf(h,depot.height,1.0-smoothstep(0,16,d))
	return h

func formation_height(p: Vector2) -> float:
	return depot_height(p,natural_height(p))

func surface_height(p: Vector2) -> float:
	if ground.get("water_geography") == true:
		var water := Coast.Water.lake_surface(p)
		if water.y == 1: return Relief.height(water.x)
	var h := formation_height(p)
	if not transport_ready: return h
	h=road_grade.earth_height(p,h)
	h=rail_urban.cut_height(p,h,natural_height)
	for station in stations:
		var profile: Vector3=rail_urban.track_profile(station.pos)
		if profile.z>0: h=RailStation.cut_height(station,p,h,profile.x)
	return h

func surface_gradient(p: Vector2) -> Vector2:
	if ground.get("water_geography") == true and Coast.Water.lake_surface(p).y == 1: return Vector2.ZERO
	var grade := _mine_grade(p)
	var modified := false
	if transport_ready:
		var key := Vector2i((p/RoadGrade.Index.CELL).floor())
		modified=road_grade.earth_buckets.has(Vector2i((p/RoadGrade.CELL).floor())) or rail_urban.track_buckets.has(key)
		if not modified:
			for depot in depots:
				if p.distance_squared_to(depot.pos)<40000: modified=true; break
	if not modified:
		for station in stations:
			if p.distance_squared_to(station.pos)<8100: modified=true;break
	if grade.x == 0.0 and not modified: return ground.gradient(p) * Relief.slope_scale(ground.height(p))
	if grade.x == 1.0: return Vector2.ZERO
	return Vector2(surface_height(p + Vector2.RIGHT) - surface_height(p - Vector2.RIGHT),
		surface_height(p + Vector2.DOWN) - surface_height(p - Vector2.DOWN)) * 0.5

func _cut_pits(poly: PackedVector2Array) -> Array[PackedVector2Array]:
	var parts: Array[PackedVector2Array] = [poly]
	var bounds := Rect2(poly[0], Vector2.ZERO)
	for p in poly: bounds = bounds.expand(p)
	for pit in pits.values():
		if not bounds.intersects(pit.area): continue
		var cut: Array[PackedVector2Array] = []
		for part in parts: cut.append_array(Geometry2D.clip_polygons(part, pit.rim))
		parts = cut
	return parts

func mine_rims_node() -> MeshInstance3D:
	if prepared_mine_rims != null: return Geo.instance(prepared_mine_rims, Assets.print_material())
	# The sprite cut pass kept the first inward-facing wall of the removed earth
	# block. In 3D it joins the terrain opening to the first submerged bench.
	var batch := Geo.Batch.new()
	for pit in pits.values():
		var rim: PackedVector2Array = pit.rim
		for i in rim.size():
			var a := rim[i]
			var b := rim[(i + 1) % rim.size()]
			var steps := maxi(1, ceili(a.distance_to(b) / 3.0))
			for j in steps:
				var p := a.lerp(b, float(j) / steps)
				var q := a.lerp(b, float(j + 1) / steps)
				var h: float = pit.height - pit.step
				batch.quad(point(p, 0.08), point(q, 0.08), at_height(q, h), at_height(p, h), Color(0.310, 0.273, 0.226))
	var material := Assets.print_material()
	prepared_mine_rims = batch.mesh()
	return Geo.instance(prepared_mine_rims, material)

func point(p: Vector2, lift: float = 0.0) -> Vector3:
	return Vector3(p.x - origin.x, surface_height(p) + lift, p.y - origin.y)

func at_height(p: Vector2, height: float) -> Vector3:
	return Vector3(p.x - origin.x, height, p.y - origin.y)

func configure_grade(update_assets: bool = true) -> void:
	if grade_range == Vector2.ZERO:
		grade_range = Vector2(INF, -INF)
		for tile in tiles.values():
			for p in Model.hex_points(tile.center):
				var y := Legacy.iso(p, ground_height(p)).y
				grade_range.x = minf(grade_range.x, y)
				grade_range.y = maxf(grade_range.y, y)
	mat.shader = GroundShader
	mat.set_shader_parameter("grade_range", grade_range)
	if update_assets: Assets.set_grade(grade_range)

func terrain_key(tid: String) -> String:
	var holes: Array = []
	var bounds := Rect2((tiles[tid].center as Vector2) - Model.HEX_HALF, Model.HEX_HALF * 2.0)
	for pit in pits.values():
		var reach := float(pit.side) * 0.80
		if bounds.intersects(Rect2((pit.pos as Vector2) - Vector2.ONE * reach, Vector2.ONE * reach * 2.0)):
			holes.append([pit.rim, pit.height, pit.seed])
	return "%s:%s:%s:%s" % [tid, ground.get_instance_id(), hash([MapStyle.band_colors(), MapStyle.sea_colors(), holes]), _continent_key if streamed else "company"]

func prepare_tile(host: Node, tid: String) -> void:
	var key := terrain_key(tid)
	# Progressive loading supplies a complete medium tile before attaching it;
	# no dependency on the combined far texture is needed for this path.
	if backdrop_pending and terrain_cache.has(key): return
	if streamed and not terrain_cache.has(key):
		var retained := resource_cache.restore(tid)
		if not retained.is_empty():
			terrain_cache[key] = retained.data
			_chunk_data[tid] = retained.chunk
	if streamed:
		prepare_local_detail(tid, _detail_standing)
	if terrain_cache.has(key):
		if streamed and not continent.is_empty():
			# All tiles share the one atlas loaded for this build, including after
			# owned → all → owned → all switches; never retain two atlas copies.
			terrain_cache[key].textures[0] = continent.texture
			terrain_cache[key].meshes[0] = continent.parts[tid] if continent.has("parts") else base_chunk(tid).mesh
		return
	if streamed:
		if continent.is_empty(): await prepare_continent(host)
		terrain_cache[key] = {"textures": [continent.texture, null, null], "meshes": [continent.parts[tid] if continent.has("parts") else base_chunk(tid).mesh, null, null], "shapes": [base_chunk(tid).get("pick_shape"), null, null], "streamed": true, "ground_id": ground.get_instance_id()}
		return
	var textures: Array = []
	var meshes: Array = []
	for tier in 3:
		var data := await _tile_bake(host, tid, tier)
		textures.append(data.texture)
		meshes.append(data.mesh)
		await host.get_tree().process_frame
	terrain_cache[key] = {"textures": textures, "meshes": meshes}

func _tile_bake(host: Node, tid: String, tier: int) -> Dictionary:
	var key := tile_bake_key(tid, tier)
	var cached := bake_cache.read(key) if _map_key != "" else {}
	if not cached.is_empty(): return cached
	var textures := await Paint.bake(host, tiles[tid], Coast.relief_of(tid, tiles[tid].center), rivers.get(tid, []), pits.values(), surface_height, [Detail.TEXTURES[tier]], static_shadows.get(tid, []), urban_plazas.tiles.get(tid,[]))
	var data := {"texture": textures[0], "mesh": _surface(tid, Detail.CELLS[tier])}
	prepare_picking(data)
	if _map_key != "": bake_cache.write(key, data)
	return data

func refine_tile(host: Node, item: Dictionary, tier: int) -> void:
	if item.data.meshes[tier] != null:
		apply_tile_detail(item, tier)
		return
	var tid := str(item.tile)
	var data := await _tile_bake(host, tid, tier)
	if not is_instance_valid(item.node): return
	item.data.textures[tier] = data.texture
	item.data.meshes[tier] = data.mesh
	if not item.data.has("shapes"): item.data.shapes = [null, null, null]
	item.data.shapes[tier] = data.get("pick_shape")
	apply_tile_detail(item, tier)
	if streamed: cache_local_tile(tid)

func apply_tile_detail(item: Dictionary, tier: int) -> void:
	while tier > 0 and item.data.meshes[tier] == null: tier -= 1
	item.node.mesh = item.data.meshes[tier]
	item.material.set_shader_parameter("artwork", item.data.textures[tier])
	var rect := Vector4(0, 0, 1, 1)
	if streamed and tier == 0 and not continent.is_empty():
		var area: Rect2 = continent.area
		var offset: Vector2 = ((tiles[item.tile].center as Vector2) - Paint.EXTENT * 0.5 - area.position) / area.size
		var scale := Paint.EXTENT / area.size
		rect = Vector4(offset.x, offset.y, scale.x, scale.y)
	item.material.set_shader_parameter("artwork_rect", rect)
	# Picking follows the displayed surface, including higher-detail river banks.
	if int(item.get("display_tier", -1)) != tier: collision_revision += 1
	item.display_tier = tier
	_sync_tile_collision(item)

func release_detail(keep: Dictionary, retain_resources: bool = false) -> void:
	for item in terrain_lods:
		if keep.has(str(item.tile)): continue
		if item.data.meshes[1] == null and item.data.meshes[2] == null: continue
		apply_tile_detail(item, 0)
		if retain_resources: continue
		for tier in [1, 2]:
			item.data.meshes[tier] = null
			item.data.textures[tier] = null
			if item.data.has("shapes"): item.data.shapes[tier] = null

func _terrain_parts(poly: PackedVector2Array) -> Array:
	var result: Array = []
	var water_parts: Array = Coast.Water.partition(poly) if ground.get("water_geography") == true else [poly]
	for water_part in water_parts:
		for part in _cut_pits(water_part):
			if transport_ready: result.append_array(road_grade.cut_out(part))
			else: result.append(part)
	return result

func _surface(tid: String, cell: float) -> ArrayMesh:
	var center: Vector2 = tiles[tid].center
	var hex := Model.hex_points(center)
	var batch := Geo.Batch.new()
	var vertex_cache := {}
	var normal_cache := {}
	var low := ((center - Model.HEX_HALF) / cell).floor()
	var high := ((center + Model.HEX_HALF) / cell).ceil()
	for y in range(int(low.y), int(high.y)):
		for x in range(int(low.x), int(high.x)):
			var a := Vector2(x,y)*cell
			var divisions := 1
			if transport_ready:
				var area := Rect2(a,Vector2.ONE*cell)
				for id in RoadGrade.Index.query(road_grade.earth_buckets,area,RoadGrade.CELL):
					var segment: Dictionary = road_grade.segments[id]
					if area.intersects(RoadGrade.Index.bounds(segment.a,segment.b,segment.half+RoadGrade.SHOULDER)):
						divisions=maxi(1,ceili(cell/(6.0 if cell>=12 else 3.0))); break
				if divisions==1:
					for id in RoadGrade.Index.query(rail_urban.track_buckets,area):
						var segment: Dictionary = rail_urban.tracks[id]
						if area.intersects(RoadGrade.Index.bounds(segment.a,segment.b,12)):
							divisions=maxi(1,ceili(cell/(6.0 if cell>=12 else 3.0))); break
			var step := cell/divisions
			for sy in divisions:
				for sx in divisions:
					var p := a+Vector2(sx,sy)*step
					var square := PackedVector2Array([p,p+Vector2(step,0),p+Vector2(step,step),p+Vector2(0,step)])
					for tile_part in Geometry2D.intersect_polygons(square,hex):
						for poly in _terrain_parts(tile_part):
							if Geometry2D.is_polygon_clockwise(poly): continue
							var local_poly := PackedVector2Array()
							for q in poly: local_poly.append(q-p)
							var indices := Geometry2D.triangulate_polygon(local_poly)
							for q in poly:
								if vertex_cache.has(q): continue
								vertex_cache[q]=point(q)
								var grad := surface_gradient(q)
								normal_cache[q]=Vector3(-grad.x,1,-grad.y).normalized()
							for i in range(0,indices.size(),3):
								var before := batch.vertices.size()
								batch.triangle(vertex_cache[poly[indices[i]]],vertex_cache[poly[indices[i+2]]],vertex_cache[poly[indices[i+1]]],Color.WHITE)
								if batch.vertices.size()>before:
									# Batch.triangle swaps b/c again, restoring index order.
									for j in 3: batch.normals[before+j]=normal_cache[poly[indices[i+j]]]
	return batch.mesh(Rect2(center-origin-Paint.EXTENT*0.5,Paint.EXTENT))

func tile_node(tid: String) -> Node3D:
	var tile: Dictionary = tiles[tid]
	var center: Vector2 = tile.center
	var root := Node3D.new()
	root.name = tid
	var data: Dictionary = terrain_cache[terrain_key(tid)]
	var surface: ArrayMesh = data.meshes[0]
	var paint := mat.duplicate() as ShaderMaterial
	paint.set_shader_parameter("textured", true)
	if not data.textures.is_empty(): paint.set_shader_parameter("artwork", data.textures[0])
	var land := Geo.instance(surface, paint)
	land.name = "Terrain"
	root.add_child(land)
	var item := {"node": land, "material": paint, "data": data, "tile": tid, "display_tier": 0, "collision_tier": -1}
	terrain_lods.append(item)
	collision_revision += 1
	_sync_tile_collision(item)
	var cached: Dictionary = _chunk_data.get(tid, {})
	if cached.has("rim_mesh"):
		var rim_node := Geo.instance(cached.rim_mesh, strata_material())
		var lip_node := Geo.instance(cached.lip_mesh, mat)
		root.add_child(rim_node)
		root.add_child(lip_node)
		frame_nodes.append({"tile": tid, "rim": rim_node, "lip": lip_node})
		_tile_finishing(root, tid)
		return root
	var rim := Geo.Batch.new()
	var lip := Geo.Batch.new()
	var relief: Dictionary = Coast.relief_of(tid, center)
	var is_sea := str(tile.type) in ["sea", "deep_sea"]
	var sea := MapStyle.sea_colors()
	var hex := Model.hex_points(center)
	var centers: Dictionary = {}
	for t in tiles.values(): centers[Vector2i((t.center as Vector2).round())] = true
	for i in 6:
		var a: Vector2 = hex[i]
		var b: Vector2 = hex[(i + 1) % 6]
		if centers.has(Vector2i((a + b - center).round())): continue
		var steps := ceili(a.distance_to(b) / 4.0)
		for j in steps:
			var pa := a.lerp(b, float(j) / steps)
			var pb := a.lerp(b, float(j + 1) / steps)
			if sea_fringe.contains((pa+pb)*.5+((pa+pb)*.5-center).normalized()*.5):continue
			var ah := surface_height(pa)
			var bh := surface_height(pb)
			# Coast cutaways keep the original blue water depth above the strata;
			# dry land has a thin turf lip. Both follow the real surface at every edge.
			var inward := (center - (pa + pb) * 0.5).normalized()
			var edge_width := (b - a).orthogonal().normalized() * Legacy._INK_W * 0.65
			lip.quad(point(pa - edge_width, 0.12), point(pb - edge_width, 0.12),
				point(pb + edge_width, 0.12), point(pa + edge_width, 0.12), Legacy._INK)
			var wet := is_sea or Ground.is_water(relief, (pa + pb) * 0.5 + inward * 3.0)
			var depth := Legacy._WATER_DEPTH if wet else Legacy._TURF
			var first_lip := lip.vertices.size()
			lip.quad(at_height(pa, ah), at_height(pb, bh), at_height(pb, bh - depth), at_height(pa, ah - depth),
				sea[4].lightened(0.12) if wet else Legacy._warm(sea[5]).darkened(0.38))
			if wet:
				for k in range(first_lip, lip.vertices.size()):
					var v: Vector3 = lip.vertices[k]
					var h := surface_height(Vector2(v.x, v.z) + origin)
					lip.colors[k] = sea[4].lightened(0.12).lerp(sea[1], clampf((h - v.y) / depth, 0.0, 1.0))
				lip.quad(at_height(pa, ah - depth), at_height(pb, bh - depth),
					at_height(pb, bh - depth - 1.6), at_height(pa, ah - depth - 1.6), Legacy._INK)
			ah -= depth
			bh -= depth
			rim.quad(at_height(pa, ah), at_height(pb, bh), at_height(pb, -150.0), at_height(pa, -150.0), Color.WHITE)
			var ua := float(j) / steps
			var ub := float(j + 1) / steps
			var va := (100.0 - ah) / 250.0
			var vb := (100.0 - bh) / 250.0
			rim.uvs.append_array(PackedVector2Array([Vector2(ua, va), Vector2(ub, 1), Vector2(ub, vb), Vector2(ua, va), Vector2(ua, 1), Vector2(ub, 1)]))
	var strata := mat.duplicate() as ShaderMaterial
	strata.set_shader_parameter("textured", true)
	strata.set_shader_parameter("strata", true)
	strata.set_shader_parameter("artwork", load("res://assets/iso/ground/strata.png"))
	var rim_node := Geo.instance(rim.mesh(), strata)
	var lip_node := Geo.instance(lip.mesh(), mat)
	root.add_child(rim_node)
	root.add_child(lip_node)
	frame_nodes.append({"tile": tid, "rim": rim_node, "lip": lip_node})
	if _repair_chunks.has(tid):
		_chunk_data[tid].rim_mesh = rim_node.mesh
		_chunk_data[tid].lip_mesh = lip_node.mesh
		persist_base_chunk(tid)
	rim_material = strata
	_tile_finishing(root, tid)
	return root

func _tile_finishing(root: Node3D, tid: String) -> void:
	var farms: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}).get("farms", {}) if streamed else FarmFields.build(self, tid, _detail_standing)
	if not farms.is_empty():
		var far := Geo.instance(farms.far, mat)
		far.name = "FarmFieldsFar"
		root.add_child(far)
		if not local_streaming: far_field_meshes.append(farms.far)
		var soil := Geo.instance(farms.soil, mat)
		root.add_child(soil)
		# Only resident tiles hold crop instances. The complete continent retains
		# one joined, simplified field mesh in its existing far bake.
		var medium := FarmFields.cells(farms, true)
		root.add_child(medium)
		farm_nodes.append({"far": far, "soil": soil, "medium": medium, "near": null, "root": root, "data": farms})
		_update_farm_tier(farm_nodes[-1], maxi(active_lod, 0))
	var tile: Dictionary = tiles[tid]
	var center: Vector2 = tile.center
	var relief: Dictionary = Coast.relief_of(tid, center)
	var glints := water_glints(tid, tile, relief)
	root.add_child(glints)
	glint_nodes.append(glints)
	if not local_streaming:
		labels.append({"tile": tid, "text": tile.label, "point": point(center + Vector2(135, 240) * 0.72, 4.0)})

func water_glints(tid: String, tile: Dictionary, relief: Dictionary) -> MeshInstance3D:
	var detail: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}) if streamed else {}
	var mesh: ArrayMesh = detail.get("glint_mesh")
	if mesh == null: mesh = LocalDetail.glints(self, tid, tile, relief)
	var material := ShaderMaterial.new()
	material.shader = GlintShader
	return Geo.instance(mesh, material)

func set_detail(tier: int, update_assets: bool = true) -> void:
	if tier == active_lod: return
	active_lod = tier
	# Keep the outgoing medium surface/collider through its two transition frames.
	# Streaming will release fine terrain once the far handover has completed.
	if not (handover_enabled and tier == 0):
		for item in terrain_lods: apply_tile_detail(item, tier)
	for item in detail_nodes: item.node.visible = tier >= int(item.minimum) and tier <= int(item.get("maximum", 2))
	for item in farm_nodes: _update_farm_tier(item, tier)
	# Imported glTF mesh LODs handle individual buildings as projected size changes.
	for visual in building_visuals: visual.lod_bias = [0.8, 1.2, 2.0][tier]
	Assets.set_detail(tier)
	if update_assets: _update_asset_tier()

func _update_farm_tier(item: Dictionary, tier: int) -> void:
	if tier == 2 and item.near == null:
		item.near = FarmFields.cells(item.data, false)
		item.root.add_child(item.near)
	item.far.visible = tier == 0
	item.soil.visible = tier > 0
	item.medium.visible = tier == 1
	if item.near != null: item.near.visible = tier == 2

func set_overview_scale(ppu: float, force: bool = false) -> void:
	FarSprites.set_overview_scale(ppu, streamed)
	var sprites_visible := (streamed and not base_ready) or ppu < (0.33 if _sprites_visible else 0.27)
	if sprites_visible != _sprites_visible or _asset_tier != active_lod or force:
		_sprites_visible = sprites_visible
		_update_asset_tier()
	for material in backdrop_materials:
		if material.get_meta("foliage", false): material.set_shader_parameter("foliage_softness", FarSprites._foliage_softness)
		if material.get_meta("road", false): material.set_shader_parameter("road_fade", 0.78 if sprites_visible else 0.18)
	var overview := streamed and (not base_ready or ppu < (0.33 if _overview else 0.27))
	if road_mat != null: road_mat.set_shader_parameter("road_fade", 0.78 if overview else (0.18 if streamed and ppu < 1.5 else 0.0))
	if overview == _overview and not force: return
	_overview = overview
	if continent_body != null: continent_body.collision_layer = 4 if cursor_picking else 1
	if handover_enabled and overview:
		_begin_handover(0.0)
	else:
		# A zoom-in waits for its requested tiles before revealing local detail.
		if handover_enabled and handover.active and handover.target == 0.0: _begin_handover(1.0)
		_apply_view_visibility()

func _update_asset_tier() -> void:
	_asset_tier = active_lod
	var far_visible := _sprites_visible
	var local_visible := not _sprites_visible
	if handover_enabled:
		far_visible = handover.blend < 1.0 or _handover_preparing
		local_visible = handover.blend > 0.0 or _handover_preparing
	if backdrop_pending: local_visible = true
	for pair in sprite_pairs:
		# Tree/clutter/decor pairs already belong to a streamed tile root. Only
		# the globally retained player/NPC objects need this extra residency gate.
		var global_standing: bool = pair.get("standing") is Dictionary and not pair.get("decor", false)
		var resident: bool = not (streamed and local_streaming and global_standing) or not pair.has("tile") or tile_ready(str(pair.tile))
		if global_standing: pair.root.visible = (not backdrop_pending or resident) and not paper_owned_tiles.has(str(pair.get("tile", "")))
		var pair_local: bool = local_visible and resident
		var pair_far: bool = far_visible or not resident
		if pair.get("clutter", false):
			if pair_local and active_lod == 2: _ensure_tree_near(pair)
			for node in pair.near: node.visible = pair_local and active_lod == 2
			continue
		var medium := pair_local and active_lod < 2 and bool(pair.get("medium_allowed", true))
		if medium and pair.get("medium") == null and pair.has("standing"):
			var card := FarSprites.instance(pair.key, grade_range, 1, pair.get("lit", false))
			if card != null:
				card.scale = BuildingScale.for_asset(pair.key, float(pair.standing.side), float(pair.standing.get("decor_scale", 1.0)))
				card.position = FarSprites.center(pair.key) * card.scale
				pair.root.add_child(card)
				pair.medium = card
		medium = medium and pair.get("medium") != null
		if pair_local:
			if pair.has("standing"): _ensure_standing_pick(pair)
			if not medium:
				if pair.get("tree", false): _ensure_tree_near(pair)
				elif pair.has("standing"): _ensure_standing_near(pair)
		if pair.get("far") != null: pair.far.visible = pair_far and not (handover_enabled and pair.get("decor", false))
		if pair.get("medium") != null: pair.medium.visible = medium
		for node in pair.near: node.visible = pair_local and not medium
	for node in tree_sprite_nodes: node.visible = far_visible
	for node in tree_nodes: node.visible = local_visible or not streamed


func distant_towns(standing: Array) -> Node3D:
	var root := Node3D.new()
	var foundations := Geo.Batch.new()
	decor_sprite_transforms.clear()
	for s in standing:
		if str(s.kind) != "house": continue
		var frame := standing_frame(s)
		var key := str(frame.key)
		var scale := BuildingScale.for_asset(key, float(s.side), float(s.get("decor_scale", 1.0)))
		var transforms: Array = decor_sprite_transforms.get_or_add(key, [])
		var basis := Basis(Vector3.UP, float(s.get("yaw", 0.0))).scaled(scale)
		transforms.append(Transform3D(basis, frame.position + basis * FarSprites.center(key)))
		_append_foundation(foundations, s, frame, frame.position)
	root.add_child(Geo.instance(foundations.mesh(), mat))
	root.visible = false
	far_nodes.append(root)
	return root

func add_detail(parent: Node3D, mesh: Mesh, minimum: int, maximum: int = 2) -> void:
	var node := Geo.instance(mesh, mat)
	parent.add_child(node)
	node.visible = maxi(active_lod, 0) >= minimum and maxi(active_lod, 0) <= maximum
	detail_nodes.append({"node": node, "minimum": minimum, "maximum": maximum})

func shadow(p: Vector2, side: float, tree: bool = false) -> void:
	# The old board's north-west shadow, with a feathered perimeter and soft contact.
	var throw := Vector2(-0.70710678, -0.70710678) * side * 0.38
	var center := p + throw * 0.45
	var radii := Vector2(side * 0.62, side * 0.48) if tree else Vector2(side * 0.69, side * 0.69)
	var count := 8 if streamed and tree else 16
	var rings := 2 if streamed and tree else 4
	for ring in rings:
		var r0 := float(ring) / rings
		var r1 := float(ring + 1) / rings
		for j in count:
			var a := TAU * j / count
			var b := TAU * (j + 1) / count
			var pa := center + Vector2(cos(a), sin(a)) * radii * r0
			var pb := center + Vector2(cos(b), sin(b)) * radii * r0
			var pc := center + Vector2(cos(b), sin(b)) * radii * r1
			var pd := center + Vector2(cos(a), sin(a)) * radii * r1
			var start := shadow_batch.colors.size()
			shadow_batch.quad(point(pa, 1.0), point(pb, 1.0), point(pc, 1.0), point(pd, 1.0), Color(0.04, 0.06, 0.14, 0.12))
			# Vertex alpha makes the edge soft without translucent overlapping disks.
			for k in range(start, shadow_batch.vertices.size()):
				var v: Vector3 = shadow_batch.vertices[k]
				var dist := ((Vector2(v.x, v.z) + origin - center) / radii).length()
				shadow_batch.colors[k].a = 0.17 * (1.0 - smoothstep(0.35, 1.0, dist))

func shadows_node() -> MeshInstance3D:
	var material := Geo.material(true)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var mesh: Mesh = shadow_batch.mesh() if standing_shadow_mesh == null else standing_shadow_mesh
	if standing_shadow_mesh != null and not shadow_batch.vertices.is_empty(): mesh = Geo.joined([standing_shadow_mesh, shadow_batch.mesh()])
	return Geo.instance(mesh, material)

func ribbon(batch: RefCounted, path: PackedVector2Array, width: float, color: Color, lift: float, road: bool = false) -> void:
	for i in range(path.size() - 1):
		var a := path[i]
		var b := path[i + 1]
		var normal := (b - a).orthogonal().normalized() * width * 0.5
		var steps := maxi(1, ceili(a.distance_to(b) / 9.0))
		for j in steps:
			var p := a.lerp(b, float(j) / steps)
			var q := a.lerp(b, float(j + 1) / steps)
			if road:
				batch.quad(at_height(p - normal, road_height(p) + lift), at_height(q - normal, road_height(q) + lift),
					at_height(q + normal, road_height(q) + lift), at_height(p + normal, road_height(p) + lift), color)
			else:
				batch.quad(point(p - normal, lift), point(q - normal, lift), point(q + normal, lift), point(p + normal, lift), color)

## Keep streets and traffic over a river valley rather than diving into its water.
func road_height(p: Vector2) -> float:
	if transport_ready: return road_grade.height_at(p,natural_height(p))
	if _road_height_cache.has(p): return _road_height_cache[p]
	var h := surface_height(p)
	var authored_height := authored_profile.height_at(p)
	if authored_height != -INF:
		h = maxf(h, authored_height)
		_road_height_cache[p] = h
		return h
	for segment in _river_buckets.get(Vector2i((p / 128.0).floor()), []):
		var closest := Geometry2D.get_closest_point_to_segment(p, segment.a, segment.b)
		if closest.distance_squared_to(p) < float(segment.half) * float(segment.half):
			var n: Vector2 = (segment.b - segment.a).orthogonal().normalized() * (float(segment.half) + 20.0)
			h = maxf(h, maxf(ground_height(closest - n), ground_height(closest + n)) + 2.0)
	_road_height_cache[p] = h
	return h

func _index_rivers() -> void:
	_river_buckets.clear()
	_road_height_cache.clear()
	for tid in rivers:
		for rec in rivers[tid]:
			var half := (float(rec.start_width) + float(rec.end_width)) * 0.25 + 17.0
			for i in range(rec.points.size() - 1):
				var segment := {"a": rec.points[i], "b": rec.points[i + 1], "half": half}
				var bounds := Rect2(segment.a, Vector2.ZERO).expand(segment.b).grow(half)
				var low := Vector2i((bounds.position / 128.0).floor())
				var high := Vector2i((bounds.end / 128.0).floor())
				for y in range(low.y, high.y + 1):
					for x in range(low.x, high.x + 1): (_river_buckets.get_or_add(Vector2i(x, y), []) as Array).append(segment)

func append_road(parent: Node3D, tid: String) -> void:
	var mesh: ArrayMesh
	if streamed and continent.get("roads", {}).has(tid): mesh = continent.roads[tid]
	elif streamed and tile_chunks.has(tid) and base_chunk(tid).get("roads_mesh") != null: mesh = base_chunk(tid).roads_mesh
	else:
		var key := "road-" + BakeCache.digest([_road_key, tid, road_surface.cell_size])
		var cached := bake_cache.read(key) if not streamed and _map_key != "" else {}
		if not cached.is_empty():
			mesh = cached.mesh
		else:
			# Ordinary LOD handovers already have road geometry. Reserve the
			# spatial lookup and height sampler for actual generation/cache repair.
			if not road_surface._height.is_valid():
				Sidewalks.apply(roads, tiles)
				road_surface.configure(roads, road_height, origin)
			mesh = road_surface.mesh_for(tid)
			if authored_profile.region.has(tid):
				mesh = Geo.joined([mesh, authored_profile.mesh_for(tid, natural_height, origin)])
			if transport_ready: mesh = Geo.joined([mesh,road_grade.bridge_mesh(tid,origin,natural_height),road_alignment.mesh_for(tid,road_height,origin,surface_height,railway_earth_color)])
		if streamed and continent.has("roads"): continent.roads[tid] = mesh
		elif cached.is_empty() and _map_key != "": bake_cache.write(key, {"mesh": mesh})
	var surface := Geo.instance(mesh, road_mat)
	surface.name = "JoinedRoads_" + tid.validate_node_name()
	parent.add_child(surface)
	road_nodes.append(surface)
	if _repair_chunks.has(tid):
		_chunk_data[tid].roads_mesh = mesh
		persist_base_chunk(tid)

## Map bands are numbered one above the owner's terrain levels (band 7 = height 6).
func railway_level(p: Vector2) -> float:
	var grid := NavGrid.instance()
	if grid.is_ready():
		var cell := grid.cell_of(p)
		return float(grid.band(cell.x, cell.y) - 1)
	# Tools without a navigation grid can still use the source height field.
	for band in range(Ground.Relief.BAND_LEVEL.size()-1,2,-1):
		if ground.height(p)>=Ground.Relief.BAND_LEVEL[band]: return float(band-1)
	return 0.0

## True over a river's water, with `margin` either side: where rail must be on a bridge.
## (`_river_buckets` stores a generous half-width for bank grading; the water itself is
## RIVER_BANK_MARGIN narrower.)
const RIVER_BANK_MARGIN := 17.0
func river_at(p: Vector2, margin: float = 4.0) -> bool:
	for segment in _river_buckets.get(Vector2i((p / 128.0).floor()), []):
		var water: float = float(segment.half) - RIVER_BANK_MARGIN + margin
		if Geometry2D.get_closest_point_to_segment(p, segment.a, segment.b).distance_squared_to(p) < water * water: return true
	return false

## Preserve river crossings without inheriting nearby authored road bridge grades.
func railway_ground_height(p: Vector2) -> float:
	var h := depot_height(p,natural_height(p))
	for segment in _river_buckets.get(Vector2i((p / 128.0).floor()), []):
		var closest := Geometry2D.get_closest_point_to_segment(p, segment.a, segment.b)
		if closest.distance_squared_to(p) < float(segment.half) * float(segment.half):
			var n: Vector2 = (segment.b-segment.a).orthogonal().normalized()*(float(segment.half)+20.0)
			h = maxf(h,maxf(ground_height(closest-n),ground_height(closest+n))+2.0)
	return h

## Earth fill uses the same warmed elevation palette as the terrain artwork.
func railway_earth_color(display_height: float) -> Color:
	var band := 2
	for i in range(3, Relief.Source.BAND_LEVEL.size()):
		if display_height < Relief.height(Relief.Source.BAND_LEVEL[i]): break
		band = i
	return Legacy._warm(MapStyle.band_colors()[band])

func _prepare_rail_art() -> void:
	if not _prepared_rail_art.is_empty(): return
	_prepared_rail_art = Railway.build(lines, road_grade.segments if transport_ready else roads, railway_ground_height, railway_level, origin,
		true, railway_earth_color, road_height, surface_height, {"plan": rail_plan, "burial": rail_urban.profile, "rail_profile":rail_urban.track_profile, "river": river_at} if transport_ready else {"river": river_at})

func infrastructure(model: Dictionary, show: Dictionary, build_roads: bool = true) -> Node3D:
	var root := Node3D.new()
	root.name = "Infrastructure"
	var streets := Geo.Batch.new()
	var details := Geo.Batch.new()
	roads = model.get("roads", [])
	lines = model.get("lines", [])
	_index_rivers()
	if authored_profile.region.is_empty(): authored_profile.configure(model.get("authored_region", {}), rivers, natural_height, open_water)
	road_mat = mat.duplicate()
	road_surface.cell_size = 6.0 if streamed else RoadSurface.CELL
	var line_geometry: Array = []
	for line in lines: line_geometry.append([line.mode, line.pts, line.get("ids", []), line.get("level", 1)])
	var lighting: Array = []
	for tid in tiles: lighting.append([tid, tiles[tid].get("polluters", 0)])
	var cable_anchors := {}
	for s in model.get("standing", []):
		if str(s.kind) == "pylon": cable_anchors[standing_key(s)] = Assets.cable_anchors(standing_key(s))
	var cache_key := BakeCache.digest([_scenery_key, line_geometry, lighting, cable_anchors, show, Railway.VERSION])
	if _scenery_key != "" and infrastructure_bake.get("key", "") == cache_key:
		cars.append_array(infrastructure_bake.cars)
		glows.append_array(infrastructure_bake.glows)
		pylon_layout = infrastructure_bake.pylons
		_append_sea_fringe(root,infrastructure_bake.get("sea_fringe",{}))
		if build_roads and bool(show["roads"]):
			for tid in tiles: append_road(root, str(tid))
			road_surface.finish_build()
		add_detail(root, infrastructure_bake.streets, 1 if streamed else 0)
		root.add_child(Geo.instance(infrastructure_bake.tubes, mat))
		add_detail(root, infrastructure_bake.details, 1)
		add_detail(root, infrastructure_bake.rail_overview, 0, 1)
		add_detail(root, infrastructure_bake.rail_near, 2)
		return root
	var glow_start := glows.size()
	if bool(show["roads"]):
		if build_roads:
			for tid in tiles: append_road(root, str(tid))
			road_surface.finish_build()
			_road_height_cache.clear()
		for rec in roads:
			if rec.get("tunnel",false): continue
			var a: Vector2 = rec.a
			var b: Vector2 = rec.b
			var across := (b - a).orthogonal().normalized()
			var half := float(rec.get("widths", Legacy._road_widths(int(rec.level)))[0])
			if int(rec.level) > 1 and bool(rec.get("paved", true)):
				for k in range(1, int(a.distance_to(b) / 55.0)):
					var p := a.move_toward(b, k * 55.0) + across * (half + 1.5)
					var foot := at_height(p, road_height(p) + 1.0)
					streets.tube(foot, foot + Vector3.UP * 14, 0.55, Color("50565e"), 5)
					streets.box(foot + Vector3(0, 14, 0), Vector3(2.5, 1.3, 2.5), Color("efd68e"))
					if int(tiles.get(str(rec.get("tile", "")), {}).get("polluters", 0)) > 0:
						glows.append({"point": foot + Vector3.UP * 14, "size": Vector2(15, 15)})
			if a.distance_to(b) > 80.0:
				cars.append({"a": a, "b": b, "tile": str(rec.get("tile", "")), "phase": fmod(absf(float(hash(str(a)))), 100.0) / 100.0})
	var street_mesh := streets.mesh()
	add_detail(root, street_mesh, 1 if streamed else 0)
	var tubes := Geo.Batch.new()
	var rail_overview := ArrayMesh.new()
	var rail_near := ArrayMesh.new()
	pylon_layout = PylonCables.layout(model, standing_frame)
	if bool(show.get("cables", true)):
		for span in pylon_layout.spans:
			var curve := PylonCables.curve(span.a, span.b)
			for i in range(1, curve.size()):
				tubes.tube(curve[i - 1], curve[i], 0.45, Color("d6b560"))
	if bool(show.get("rails", true)):
		_prepare_rail_art()
		var rail_art: Dictionary = _prepared_rail_art
		Railway.append_mesh(tubes, rail_art.bed)
		rail_overview = rail_art.overview
		rail_near = rail_art.detail
		for depot in depots: Railway.append_mesh(tubes,RailDepot.mesh(depot,origin))
		Railway.append_mesh(tubes,preload("res://scripts/supply_chain_3d/rail_crossings.gd").level_mesh(road_grade.crossings,origin,road_height))
		for station in stations:
			var profile: Vector3=rail_urban.track_profile(station.pos)
			Railway.append_mesh(tubes,RailStation.mesh(station,origin,profile.x if profile.z>0 else railway_ground_height(station.pos)+1.2))
	for rec in model.get("lines", []):
		var mode := str(rec.get("mode", ""))
		if Railway.is_rail(mode): continue # Both legacy "rail" and infrastructure "rails".
		if not bool(show.get(mode, true)) or mode == "cables": continue
		var path: Array = rec.get("pts", [])
		for i in range(path.size() - 1):
			var a: Vector2 = path[i].p
			var b: Vector2 = path[i + 1].p
			var count := maxi(2, ceili(a.distance_to(b) / 12.0))
			var previous := Vector3.ZERO
			for j in range(count + 1):
				var t := float(j) / count
				var p := a.lerp(b, t)
				var current := at_height(p, road_height(p) + 5.5)
				if j > 0: tubes.tube(previous, current, 2.4, Color("a0a7aa") if mode == "reinf_pipes" else Color("b78552"))
				previous = current
	if bool(show.get("decor",true)):
		Railway.append_mesh(tubes,preload("res://scripts/supply_chain_3d/neighbourhood_art.gd").mesh(model.get("neighbourhood",{}),origin,surface_height))
	var sea_bake := sea_fringe.bake(origin,surface_height,surface_gradient) if not sea_fringe.strips.is_empty() else {}
	_append_sea_fringe(root,sea_bake)
	var tube_mesh := tubes.mesh()
	var detail_mesh := details.mesh()
	root.add_child(Geo.instance(tube_mesh, mat))
	add_detail(root, detail_mesh, 1)
	add_detail(root, rail_overview, 0, 1)
	add_detail(root, rail_near, 2)
	_prepared_rail_art.clear()
	if _scenery_key != "":
		infrastructure_bake = {"key": cache_key, "streets": street_mesh, "tubes": tube_mesh, "details": detail_mesh,
			"rail_overview": rail_overview, "rail_near": rail_near, "sea_fringe":sea_bake,
			"cars": cars.duplicate(true), "glows": glows.slice(glow_start).duplicate(true), "pylons": pylon_layout}
		bake_cache.write(_scenery_key, scenery_data())
	return root

func _append_sea_fringe(root: Node3D, data: Dictionary) -> void:
	if data.is_empty():return
	for pair in [["top",mat],["lip",mat],["rim",strata_material()]]:
		var node := Geo.instance(data[pair[0]],pair[1])
		node.name="SeaMargin"+str(pair[0]).capitalize()
		root.add_child(node)

static func standing_key(s: Dictionary) -> String:
	if s.has("harbour"): return ""
	if s.has("decor_asset"): return str(s.decor_asset)
	if s.has("decor_family"): return Assets.key_for(str(s.decor_family), int(s.level))
	var kind := str(s["kind"])
	var family := str(s.get("internal_name", ""))
	if FarmFields.is_plot(s): family = "farm_building"
	if kind == "warehouse" or kind == "suppliers": family = "warehouse"
	elif kind == "port": family = "port"
	elif kind == "pylon": family = "pylon"
	elif kind == "site": family = "construction_site"
	elif kind == "house": family = "towers" if bool(s.get("tall", false)) else "house"
	var level := int(s.get("level", 1))
	# Decorative metadata uses level 3 for footprint sizing, while its chosen sprite
	# carries the actual house/tower variety. Preserve that variety in the 3D mesh.
	if kind == "house" and s.get("sprite") is Texture2D:
		var filename: String = s.sprite.resource_path.get_file().get_basename()
		if filename.begins_with(family + "_lvl"):
			level = filename.trim_prefix(family + "_lvl").to_int()
	return Assets.key_for(family, level)

func standing_frame(s: Dictionary) -> Dictionary:
	if standing_frames.has(str(s.iid)): return standing_frames[str(s.iid)]
	if s.has("harbour"): return Harbour.frame(s, surface_height, origin)
	var key := standing_key(s)
	var side := float(s.get("side", 80.0))
	var scale := BuildingScale.for_asset(key, side, float(s.get("decor_scale", 1.0)))
	var p: Vector2 = s.pos
	var floor_h := surface_height(p)
	var low_h := floor_h
	var dimension := Assets.dimensions(key) * scale
	var shapes := _foundation_shapes(s, key, dimension)
	for shape in shapes:
		for i in shape.size():
			for off in [shape[i], (shape[i] + shape[(i+1)%shape.size()]) * 0.5]:
				var h := surface_height(p + (off as Vector2).rotated(-float(s.get("yaw", 0.0))))
				floor_h = maxf(floor_h, h)
				low_h = minf(low_h, h)
	var pit: Dictionary = pits.get(str(s.iid), {})
	if not pit.is_empty(): floor_h = float(pit.height)
	var position := at_height(p, floor_h - float(pit.sink) if not pit.is_empty() else floor_h + 1.0)

	return {"key": key, "position": position, "dimension": dimension,
		"plinth_depth": floor_h - low_h + 1.0 if pit.is_empty() and floor_h - low_h > 0.75 else 0.0}

func _foundation_shapes(s: Dictionary, key: String, dimension: Vector3) -> Array:
	if str(s.kind) == "house":
		var shapes: Array = []
		for shape in Footprints.local(key):
			var poly := PackedVector2Array()
			for p in shape: poly.append(p * float(s.side))
			shapes.append(poly)
		if not shapes.is_empty(): return shapes
	var center := FarSprites.center(key) * float(s.side)
	var half := Vector2(dimension.x, dimension.z) * 0.5
	var c := Vector2(center.x, center.z)
	return [PackedVector2Array([c-half,c+Vector2(half.x,-half.y),c+half,c+Vector2(-half.x,half.y)])]

func _append_foundation(batch: Geo.Batch, s: Dictionary, frame: Dictionary, offset := Vector3.ZERO) -> void:
	if float(frame.plinth_depth) <= 0.0: return
	var basis := Basis(Vector3.UP, float(s.get("yaw", 0.0)))
	var merged := offset != Vector3.ZERO
	var colour := Color("868579")
	for shape in _foundation_shapes(s,str(frame.key),frame.dimension):
		var corners := PackedVector3Array()
		for p in shape:
			var corner := Vector3(p.x,0,p.y)
			corners.append(basis * corner if merged else corner)
		var indices := Geometry2D.triangulate_polygon(shape)
		for i in range(0,indices.size(),3):
			batch.triangle(corners[indices[i]]+offset,corners[indices[i+2]]+offset,corners[indices[i+1]]+offset,colour)
		for i in corners.size():
			var a := corners[i]
			var b := corners[(i + 1) % corners.size()]
			var steps := maxi(1, ceili(a.distance_to(b) / 12.0))
			for step in steps:
				var p := a.lerp(b, float(step) / steps)
				var q := a.lerp(b, float(step + 1) / steps)
				var sample_p := p if merged else basis * p
				var sample_q := q if merged else basis * q
				var low_p := p + Vector3.UP * minf(0.0, surface_height(s.pos + Vector2(sample_p.x, sample_p.z)) - frame.position.y - 1.0)
				var low_q := q + Vector3.UP * minf(0.0, surface_height(s.pos + Vector2(sample_q.x, sample_q.z)) - frame.position.y - 1.0)
				batch.quad(p + offset, q + offset, low_q + offset, low_p + offset, colour)

func _track_visual(node: GeometryInstance3D, tid: String) -> void:
	building_visuals.append(node)
	node.lod_bias = [0.8, 1.2, 2.0][clampi(active_lod, 0, 2)]
	if local_tiles.has(tid): local_tiles[tid].records.building_visuals.append(node)

func _ensure_standing_near(pair: Dictionary) -> void:
	if not pair.near.is_empty(): return
	if pair.standing.has("harbour"):
		var frame := standing_frame(pair.standing)
		for mesh in [Assets.mesh_for(frame.harbour_asset), Assets.contour_for(frame.harbour_asset)]:
			if mesh == null: continue
			var visual := MeshInstance3D.new()
			visual.mesh = mesh
			visual.transform = frame.harbour_transform
			pair.root.add_child(visual)
			pair.near.append(visual)
			_track_visual(visual, str(pair.tile))
		return
	var mesh := Assets.mesh_for(pair.key)
	var visual := MeshInstance3D.new()
	if mesh != null:
		visual.mesh = mesh
		visual.scale = BuildingScale.for_asset(pair.key, float(pair.standing.side), float(pair.standing.get("decor_scale", 1.0)))
		if pair.lit: visual.material_override = Assets.lit_material(str(pair.key).begins_with("towers_"))
	else:
		var box := BoxMesh.new()
		box.size = pair.dimension
		visual.mesh = box
		visual.position.y = box.size.y * 0.5
		var fallback := StandardMaterial3D.new()
		fallback.albedo_color = Color("cbc6a8")
		visual.material_override = fallback
	pair.root.add_child(visual)
	pair.near.append(visual)
	_track_visual(visual, str(pair.tile))
	var contour := Assets.contour_for(pair.key)
	if contour != null:
		var outline := MeshInstance3D.new()
		outline.name = "OuterContour"
		outline.mesh = contour
		outline.scale = visual.scale
		pair.root.add_child(outline)
		pair.near.append(outline)
		_track_visual(outline, str(pair.tile))

func _ensure_standing_pick(pair: Dictionary) -> void:
	if cursor_picking and (not collision_detail_visible() or not collision_tiles.has(str(pair.tile))):
		if pair.get("body") != null:
			var collider: CollisionShape3D = pair.body.get_child(0)
			if collider.shape != null: collider.shape = null
		return
	if pair.get("body") != null:
		if cursor_picking:
			var collider: CollisionShape3D = pair.body.get_child(0)
			if collider.shape == null: collider.shape = pair.pick_shape
		return
	var s: Dictionary = pair.standing
	if str(s.kind) not in ["building", "site", "warehouse", "suppliers"]: return
	var pit: Dictionary = pits.get(str(s.iid), {})
	var body := StaticBody3D.new()
	body.collision_layer = 2 if pit.is_empty() else 3
	body.collision_mask = 0
	body.set_meta("standing", s)
	body.set_meta("tile_id", str(s.tile))
	var dimension: Vector3 = pair.dimension
	body.set_meta("pick_bounds", AABB(Vector3(-dimension.x * 0.5, 0, -dimension.z * 0.5), dimension))
	var collider := CollisionShape3D.new()
	if s.has("harbour"):
		collider.shape = Harbour.picking_shape(standing_frame(s))
	elif str(pair.key) != "" and pit.is_empty():
		collider.shape = Assets.picking_shape(pair.key)
		collider.scale = Vector3.ONE * float(s.side)
	else:
		var shape := BoxShape3D.new()
		shape.size = dimension.max(Vector3.ONE * 6.0)
		if not pit.is_empty(): shape.size.y = maxf(shape.size.y, float(pit.sink) + 3.0)
		collider.shape = shape
		collider.position.y = shape.size.y * 0.5
	body.add_child(collider)
	pair.root.add_child(body)
	# Cursor picking queries newly attached bodies immediately, including a
	# harbour extending over another tile. Flush the inherited world transform.
	if body.is_inside_tree():
		body.force_update_transform()
		collider.force_update_transform()
	pair.body = body
	pair.pick_shape = collider.shape

func standing_node(s: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = str(s["iid"]).validate_node_name()
	var frame := standing_frame(s)
	var kind := str(s.kind)
	var key := str(frame.key)
	var family := key.get_slice("_lvl", 0)
	var side := float(s.side)
	var p: Vector2 = s.pos
	var pit: Dictionary = pits.get(str(s.iid), {})
	root.position = frame.position
	root.rotation.y = float(s.get("yaw", 0.0))
	if kind == "pylon": root.rotation.y = float(pylon_layout.get("yaws", {}).get(str(s.iid), 0.0))
	var dimension: Vector3 = frame.dimension
	if key == "" and not s.has("harbour"): dimension = Vector3(side * 0.8, side * 0.55, side * 0.65)
	var lit := int(tiles.get(str(s.tile), {}).get("polluters", 0)) > 0 and kind != "pylon" and family not in ["mine", "mine_flush", "civic_park", "civic_plaza", "civic_grove", "civic_pond"]
	var pair := {"key": key, "far": null, "near": [], "medium": null, "root": root, "standing": s,
		"dimension": dimension, "tile": str(s.tile), "lit": lit,
		# The few lattice pylons are cheap meshes. Their clamps must stay aligned
		# with continuous 3D cables instead of stepping between atlas angles.
		"medium_allowed": not s.has("harbour") and kind != "pylon" and (not lit or FarSprites.entry(key, 1).has("lit_texture")),
		"decor": streamed and kind == "house"}
	if not lazy_assets:
		_ensure_standing_near(pair)
		_ensure_standing_pick(pair)
	if lit:
		glows.append({"point": root.position + Vector3(0, dimension.y * 0.3, side * 0.45), "size": Vector2(side * 1.3, side * 0.7)})
	if streamed and kind == "house": decor_nodes.append(root)
	if standing_shadow_mesh == null and not s.has("harbour") and kind != "pylon" and pit.is_empty() and not (kind == "house" and scenery_ready): shadow(p, side)
	if float(frame.plinth_depth) > 0.0:
		var foundation: ArrayMesh = prepared_foundations.get(str(s.iid))
		if foundation == null:
			var plinth := Geo.Batch.new()
			_append_foundation(plinth, s, frame)
			foundation = plinth.mesh()
			# Decorative foundations belong to their streamed tile's lifetime.
			if kind != "house": prepared_foundations[str(s.iid)] = foundation
		root.add_child(Geo.instance(foundation, mat))
	var card := FarSprites.instance(key, grade_range)
	if card != null:
		card.scale = BuildingScale.for_asset(key, side, float(s.get("decor_scale", 1.0)))
		card.position = FarSprites.center(key) * card.scale
		card.visible = false
		root.add_child(card)
		pair.far = card
	if s.has("harbour"):
		# Four shared Blender meshes are cheap enough to retain continuous 3D
		# at far zoom, using imported mesh LODs and reduced shader detail.
		var far := MeshInstance3D.new()
		far.mesh = Assets.mesh_for(frame.harbour_asset)
		far.transform = frame.harbour_transform
		far.lod_bias = 0.8
		far.visible = false
		root.add_child(far)
		pair.far = far
		harbour_traffic.append({"root": root, "frame": frame, "center": s.pos, "traffic": {}, "phase": float(abs(str(s.tile).hash()) % 13)})
	sprite_pairs.append(pair)
	pickables.append({"iid": s.iid, "kind": kind, "tile": s.tile, "point": root.position + Vector3.UP * dimension.y * 0.5, "top": root.position + Vector3.UP * (dimension.y + 12.0), "size": rotated_extent(dimension, root.basis)})
	if bool(s.get("polluting", false)):
		smoke.append({"point": root.position + Vector3.UP * dimension.y, "radius": maxf(4.0, side * 0.08)})
	return root

func trees_node(tid: String, standing: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "LandscapeDetail"
	if str(tiles[tid].type) in ["sea", "deep_sea"]: return root
	# Tree shadows are batched with their tile so the renderer can cull them.
	var saved_shadows := shadow_batch
	if streamed: shadow_batch = Geo.Batch.new()
	var placements := placements_for(tid, standing)
	if lazy_assets:
		var prepared: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}) if streamed else {}
		var all_cards: Dictionary = prepared.get("tree_cards", {})
		if not prepared.has("tree_cards"): all_cards = LocalDetail.tree_cards(self, tid, standing)
		for kind in ["small", "fir", "large"]:
			var key := Assets.key_for("tree", {"small": 1, "fir": 2, "large": 3}[kind])
			var cards: Array = all_cards.get(kind, [])
			if not scenery_ready:
				for tree in placements:
					if tree.kind == kind: shadow(tree.pos, Assets.dimensions(key).x * float(tree.height) / Assets.projected_height(key), true)
			if cards.is_empty(): continue
			if streamed and not local_streaming:
				if not tree_sprite_transforms.has(key): tree_sprite_transforms[key] = []
				tree_sprite_transforms[key].append_array(cards)
			var medium := FarSprites.grove(key, cards, grade_range, 1)
			if medium != null: root.add_child(medium)
			var far := FarSprites.grove(key, cards, grade_range) if not streamed else null
			if far != null: root.add_child(far)
			sprite_pairs.append({"tree": true, "key": key, "kind": kind, "tile": tid, "root": root, "cards": cards,
				"near": [], "medium": medium, "far": far})
		sprite_pairs.append({"clutter": true, "tile": tid, "root": root, "standing": standing, "near": [], "far": null, "medium": null})
		if streamed:
			if not scenery_ready: root.add_child(shadows_node())
			shadow_batch = saved_shadows
		tree_nodes.append(root)
		return root
	tree_placements[tid] = placements
	for kind in ["small", "fir", "large"]:
		var level: int = {"small": 1, "fir": 2, "large": 3}[kind]
		var key := Assets.key_for("tree", level)
		# Godot selects a MultiMesh's mesh LOD from the node transform. Keep the
		# species' main scale there, rather than hiding a 20x scale in each instance;
		# otherwise tiny LODs and their contour shells diverge even at close zoom.
		var species_scale := float(Legacy._TREE_HEIGHT[kind]) / Assets.projected_height(key)
		var transforms: Array[Transform3D] = []
		var cards: Array = []
		for tree in placements:
			if tree.kind != kind: continue
			var scale := float(tree.height) / Assets.projected_height(key)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale / species_scale), point(tree.pos) / species_scale))
			cards.append(Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale), point(tree.pos) + FarSprites.center(key) * scale))
			var radius := Assets.dimensions(key).x * scale * 0.5
			if not scenery_ready: shadow(tree.pos, radius * 2.0, true)
		if transforms.is_empty(): continue
		if streamed and not local_streaming:
			if not tree_sprite_transforms.has(key): tree_sprite_transforms[key] = []
			tree_sprite_transforms[key].append_array(cards)
		elif not streamed:
			var grove := FarSprites.grove(key, cards, grade_range)
			if grove != null:
				grove.visible = false
				tree_sprite_nodes.append(grove)
		var near_nodes: Array = []
		var medium_grove := FarSprites.grove(key, cards, grade_range, 1) if local_streaming or not streamed else null
		if medium_grove != null: root.add_child(medium_grove)
		for mesh in [Assets.mesh_for(key), Assets.contour_for(key)]:
			if mesh == null: continue
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.mesh = mesh
			multi.instance_count = transforms.size()
			for i in transforms.size(): multi.set_instance_transform(i, transforms[i])
			var node := MultiMeshInstance3D.new()
			node.name = "Trees_" + kind
			node.multimesh = multi
			node.scale = Vector3.ONE * species_scale
			if mesh == Assets.mesh_for(key): node.material_override = Assets.tree_material(kind == "fir")
			root.add_child(node)
			building_visuals.append(node)
			near_nodes.append(node)
		if medium_grove != null: sprite_pairs.append({"far": null, "medium": medium_grove, "near": near_nodes})
	add_detail(root, _ground_clutter(tid, standing), 2)
	if streamed:
		if not scenery_ready: root.add_child(shadows_node())
		shadow_batch = saved_shadows
	tree_nodes.append(root)
	var group := Node3D.new()
	group.add_child(root)
	if not streamed:
		for node in tree_sprite_nodes:
			if node.get_parent() == null: group.add_child(node)
	return group

func _ensure_tree_near(pair: Dictionary) -> void:
	if not pair.near.is_empty(): return
	if pair.get("clutter", false):
		var node := Geo.instance(_ground_clutter(pair.tile, pair.standing), mat)
		pair.root.add_child(node)
		pair.near.append(node)
		return
	var key := str(pair.key)
	var species_scale := float(Legacy._TREE_HEIGHT[pair.kind]) / Assets.projected_height(key)
	for mesh in [Assets.mesh_for(key), Assets.contour_for(key)]:
		if mesh == null: continue
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = pair.cards.size()
		for i in pair.cards.size():
			var card: Transform3D = pair.cards[i]
			var scale := card.basis.x.length()
			multi.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * scale / species_scale),
				(card.origin - FarSprites.center(key) * scale) / species_scale))
		var node := MultiMeshInstance3D.new()
		node.name = "Trees_" + str(pair.kind)
		node.multimesh = multi
		node.scale = Vector3.ONE * species_scale
		if mesh == Assets.mesh_for(key): node.material_override = Assets.tree_material(pair.kind == "fir")
		pair.root.add_child(node)
		pair.near.append(node)
		_track_visual(node, str(pair.tile))

func _ground_clutter(tid: String, standing: Array) -> Mesh:
	var detail: Dictionary = _chunk_data.get(tid, {}).get("local_detail", {}) if streamed else {}
	if detail.get("clutter_mesh") is Mesh: return detail.clutter_mesh
	return LocalDetail.clutter(self, tid, standing)

func _plantable(p: Vector2, tid: String, rel: Dictionary, standing: Array, road_margin: float, nearby_roads: Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[tid].center)) or Ground.is_water(rel, p): return false
	if not rail_vegetation.clear(p, 1.5): return false
	for s in standing:
		if FarmFields.is_plot(s) and Geometry2D.is_point_in_polygon(p, s.footprint): return false
		if (s.pos as Vector2).distance_to(p) < float(s.get("side", 80)) * 0.74 + 12.0: return false
	for road in nearby_roads:
		if Geometry2D.get_closest_point_to_segment(p, road.a, road.b).distance_to(p) < road_margin: return false
	for rec in rivers.get(tid, []):
		for j in range(rec.points.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, rec.points[j], rec.points[j + 1]).distance_to(p) < (float(rec.start_width) + float(rec.end_width)) * 0.25 + 6.0: return false
	return true

func _crown(batch: RefCounted, center: Vector3, radius: Vector3, color: Color, sides: int) -> void:
	# Rounded, faceted broadleaf crowns rather than the first pass's pointed diamonds.
	var levels := [-0.82, -0.35, 0.30, 0.78]
	for ring in range(levels.size() - 1):
		var y0: float = levels[ring]
		var y1: float = levels[ring + 1]
		var r0 := sqrt(1.0 - y0 * y0)
		var r1 := sqrt(1.0 - y1 * y1)
		for j in sides:
			var a := TAU * j / sides
			var b := TAU * (j + 1) / sides
			batch.quad(center + Vector3(cos(a) * r0, y0, sin(a) * r0) * radius,
				center + Vector3(cos(b) * r0, y0, sin(b) * r0) * radius,
				center + Vector3(cos(b) * r1, y1, sin(b) * r1) * radius,
				center + Vector3(cos(a) * r1, y1, sin(a) * r1) * radius, color)
	for j in sides:
		var a := TAU * j / sides
		var b := TAU * (j + 1) / sides
		batch.triangle(center + Vector3(cos(a) * 0.626, 0.78, sin(a) * 0.626) * radius,
			center + Vector3.UP * radius.y, center + Vector3(cos(b) * 0.626, 0.78, sin(b) * 0.626) * radius, color.lightened(0.04))

func prepare_flows(model: Dictionary) -> void:
	flows.clear()
	for flow in model.get("flows", []):
		var points := PackedVector3Array()
		var distances := PackedFloat32Array([0.0])
		var source: Array = flow.get("pts", [])
		var cable := str(flow.get("mode", "")) == "cables"
		for i in range(source.size() - 1):
			var a: Vector2 = source[i].p
			var b: Vector2 = source[i + 1].p
			var count := maxi(1, ceili(a.distance_to(b) / 18.0))
			for j in range(count + (1 if i == source.size() - 2 else 0)):
				var t := float(j) / count
				var p := a.lerp(b, t)
				var h := lerpf(ground_height(a), ground_height(b), t) + 70.0 - sin(t * PI) * 12.0 if cable else road_height(p) + 16.0
				var at := at_height(p, h)
				if not points.is_empty(): distances.append(distances[-1] + points[-1].distance_to(at))
				points.append(at)
		if points.size() >= 2:
			flows.append({"points": points, "distances": distances, "length": distances[-1], "icon": flow.get("icon"), "good": flow.get("good", "")})

func update_harbour_traffic(time: float) -> void:
	var tier := 0 if _overview else active_lod
	for item in harbour_traffic:
		if tier <= 0:
			if not item.traffic.is_empty(): item.traffic.root.hide()
			continue
		if item.traffic.is_empty():
			item.traffic = HarbourTraffic.create(item.root, item.frame, item.center, surface_height)
		HarbourTraffic.update(item.traffic, time + float(item.phase), tier)
