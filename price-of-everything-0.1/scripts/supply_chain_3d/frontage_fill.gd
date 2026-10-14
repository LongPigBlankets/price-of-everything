extends RefCounted
## Offline street-front infill. Coverage samples both sides at equal arc lengths;
## neither extra buildings nor parallel road segments can double-count a sample.
const Trial := preload("res://scripts/supply_chain_3d/stoneshore_trial.gd")
const Index := preload("res://scripts/supply_chain_3d/road_index.gd")
const Walks := preload("res://scripts/supply_chain_3d/urban_sidewalks.gd")
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Civic := preload("res://scripts/supply_chain_3d/civic_layout.gd")
const Far := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const Scale := preload("res://scripts/supply_chain_3d/building_scale.gd")
const STEP := 4.0
const FACADE_REACH := 10.0
const TARGET := 0.84 # denser urban fronts compensate for constrained rural approaches
var samples: Array = []
var sample_index := {}
var contexts := {}
var added: Array = []
var tile_totals := {}
var failed := {}
var refusals := {"zoning":0,"plot":0}
var fit: RefCounted
var world: Dictionary

static func touches(a: Vector2,b: Vector2,poly: PackedVector2Array) -> bool:
	if Geometry2D.is_point_in_polygon(a,poly) or Geometry2D.is_point_in_polygon(b,poly): return true
	for i in poly.size():
		if Geometry2D.segment_intersects_segment(a,b,poly[i],poly[(i+1)%poly.size()])!=null: return true
	return false

static func street(road: Dictionary) -> bool:
	return str(road.get("tile","")) in Trial.TILES and not str(road.get("source","")).begins_with("access:") and not road.get("tunnel",false)

func run(model: Dictionary, fitter: RefCounted, zoning: Dictionary) -> Dictionary:
	world=model;fit=fitter;contexts=zoning
	_measure()
	var before := report()
	tile_totals=before.by_tile.duplicate(true)
	# Work from the longest uncovered runs, then use smaller existing modules in
	# remaining gaps. Every attempt uses the normal exact-footprint constraints.
	for pass_id in 2:
		failed.clear() # quarter-turn placements open narrower plots on the second pass
		var gaps := _gaps()
		if gaps.is_empty(): break
		for gap in gaps:
			if _at_target(gap.tile) or gap.length<12.0: continue
			for sample_id in gap.indices:
				var sample: Dictionary=samples[sample_id]
				if sample.covered or failed.has(sample_id): continue
				if _place(sample,pass_id):
					if _at_target(gap.tile): break
				else: failed[sample_id]=true
	var result := {"before":before,"after":report(),"added":added.size(),"target":TARGET,"refusals":refusals}
	if "--frontage-audit" in OS.get_cmdline_user_args():
		var debug := {"samples":[],"plots":[],"roads":[],"summary":result}
		for sample in samples:
			debug.samples.append({"a":[sample.a.x,sample.a.y],"b":[sample.b.x,sample.b.y],"covered":sample.covered,"excluded":sample.excluded,"tile":sample.tile})
		for lot in fit.lots:
			var points: Array=[]
			for p in lot.polygon: points.append([p.x,p.y])
			debug.plots.append({"iid":lot.iid,"points":points})
		for road in fit.roads:
			if street(road): debug.roads.append({"a":[road.a.x,road.a.y],"b":[road.b.x,road.b.y],"width":float(road.get("widths",[5.0])[0])*2})
		FileAccess.open("/private/tmp/stoneshore-frontage-audit.json",FileAccess.WRITE).store_string(JSON.stringify(debug))
	fit=null;world={}
	return result

func _measure() -> void:
	var kinds := {}
	var actual := {}
	for s in world.standing:
		kinds[str(s.iid)]="green" if Civic.is_space(s) else ("harbour" if s.has("harbour") else "building")
		if fit.exact_building(s): actual[str(s.iid)]=fit.footprints(s)
		elif not Civic.is_space(s) and not s.has("harbour"):
			# A farm's reserved field/industrial yard is not a building facade.
			var key: String=fit.asset_key.call(s)
			var dim := Assets.dimensions(key)*float(s.side)
			var center := Far.center(key)*float(s.side)
			var half := Vector2(dim.x,dim.z)*0.5
			var poly := PackedVector2Array()
			for p in [Vector2(-half.x,-half.y),Vector2(half.x,-half.y),half,Vector2(-half.x,half.y)]:
				poly.append(s.pos+(p+Vector2(center.x,center.z)).rotated(-float(s.get("yaw",0))))
			actual[str(s.iid)]=[poly]
	for road_id in fit.roads.size():
		var road: Dictionary=fit.roads[road_id]
		if not street(road): continue
		var tangent: Vector2=(road.b-road.a).normalized()
		var length: float=road.a.distance_to(road.b)
		var count := maxi(1,ceili(length/STEP))
		var reach: float=float(road.get("widths",[5.0])[0])+Walks.width(road)+0.1
		for side in [-1.0,1.0]:
			var n: Vector2=tangent.orthogonal()*side
			for i in count:
				var p: Vector2=road.a.lerp(road.b,(i+0.5)/count)
				var a := p+n*reach
				var b := a+n*FACADE_REACH
				var sample := {"road":road,"road_id":road_id,"side":side,"tile":str(road.tile),"p":p,"a":a,"b":b,"normal":n,"weight":length/count,"covered":false,"excluded":""}
				if not Index.contains(world.tiles[road.tile].center,b): sample.excluded="boundary"
				elif fit.wet(a) or fit.wet(b): sample.excluded="water"
				for other_id in Index.query(fit.road_index,Index.bounds(a,b,20)):
					if other_id==road_id: continue
					var other: Dictionary=fit.roads[other_id]
					var half: float=float(other.get("widths",[5.0])[0])+Walks.width(other)
					if a.distance_to(Geometry2D.get_closest_point_to_segment(a,other.a,other.b))<half+0.05:
						sample.excluded="junction";break
				if sample.excluded=="":
					for lot_id in Index.query(fit.lot_index,Index.bounds(a,b)):
						var lot: Dictionary=fit.lots[lot_id]
						if not touches(a,b,lot.polygon): continue
						var kind: String=kinds.get(str(lot.iid),"rail")
						if kind=="building":
							for shape in actual.get(str(lot.iid),[]): sample.covered=sample.covered or touches(a,b,shape)
							if not sample.covered: sample.excluded="reserved_plot"
						else: sample.excluded=kind
					if not sample.covered and sample.excluded=="":
						var h: float=fit.ground.call(a)
						for q in [b,b+tangent*6.0,b-tangent*6.0]:
							if absf(float(fit.ground.call(q))-h)>6.0: sample.excluded="relief"
				if sample.excluded=="" and not sample.covered:
					# A road-facing point alone can sit on a narrow sliver between
					# rail/road/water boundaries. Require a conservative 16x14u
					# land envelope, smaller than our smallest 20.75u office.
					var probe := PackedVector2Array([a-tangent*8.0,a+tangent*8.0,a+n*14.0+tangent*8.0,a+n*14.0-tangent*8.0])
					var base: float=fit.ground.call(a)
					for q in probe:
						if not Index.contains(world.tiles[road.tile].center,q): sample.excluded="plot_boundary"
						elif fit.wet(q): sample.excluded="plot_water"
						elif absf(float(fit.ground.call(q))-base)>6.0: sample.excluded="plot_relief"
					for other_id in Index.query(fit.road_index,fit.polygon_bounds(probe).grow(20)):
						if other_id==road_id: continue
						var other: Dictionary=fit.roads[other_id]
						if fit.distance_to_polygon(other.a,other.b,probe)<float(other.get("widths",[5.0])[0])+Walks.width(other):
							sample.excluded="plot_junction";break
					for lot_id in Index.query(fit.lot_index,fit.polygon_bounds(probe)):
						var lot: Dictionary=fit.lots[lot_id]
						# Decorative plots can be repacked; do not hide their small gaps
						# from the denominator. Keep permanent reservations explicit.
						if str(lot.iid).begins_with("z_trial:") or str(lot.iid).begins_with("z_frontage:"): continue
						var overlap := Geometry2D.is_point_in_polygon(lot.polygon[0],probe)
						for k in probe.size(): overlap=overlap or touches(probe[k],probe[(k+1)%probe.size()],lot.polygon)
						if overlap: sample.excluded="plot_"+kinds.get(str(lot.iid),"rail")
				Index.insert(sample_index,Index.bounds(a,b),samples.size())
				samples.append(sample)

func _gaps() -> Array:
	var runs: Array=[]
	var current := {}
	for i in samples.size():
		var s: Dictionary=samples[i]
		var key := "%d:%s" % [s.road_id,s.side]
		var blocked: bool=s.excluded!="" and not str(s.excluded).begins_with("plot_")
		if s.covered or blocked or (not current.is_empty() and current.key!=key):
			if not current.is_empty(): runs.append(current);current={}
		if s.covered or blocked: continue
		if current.is_empty(): current={"key":key,"tile":s.tile,"length":0.0,"indices":[]}
		current.length+=float(s.weight);current.indices.append(i)
	if not current.is_empty(): runs.append(current)
	runs.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:return a.length>b.length)
	# Try each run's centre first, then alternate to its ends.
	for run in runs:
		var center: float=float(run.indices[0]+run.indices[-1])*0.5
		run.indices.sort_custom(func(a: int,b: int) -> bool:return absf(a-center)<absf(b-center))
	return runs

func _choices(housing: bool, seed: int, pass_id: int) -> Array:
	var choices: Array=[]
	if housing:
		for key in (["civic_semi_lvl1","house_lvl1","house_lvl2"] if seed%3!=0 else ["house_lvl1","civic_semi_lvl1","house_lvl2"]):
			choices.append({"key":key,"side":(Scale.semi_side() if key.begins_with("civic_semi") else Scale.TERRACE_ROW_SIDE)*Trial.DECOR_SCALE})
	else:
		if pass_id==0:
			for key in (["house_lvl3","civic_commercial_lvl1"] if seed%3==0 else ["civic_commercial_lvl1","house_lvl3"]):
				choices.append({"key":key,"side":Scale.TERRACE_ROW_SIDE*Trial.DECOR_SCALE if key.begins_with("house") else 12.0/Assets.storey_height(key)*Trial.DECOR_SCALE})
		if pass_id==0 and seed%6==0:
			for module in Civic.options_for({"decor_family":"civic_l"}):
				choices.append({"key":module.key,"side":module.side*Trial.DECOR_SCALE,"bays":module.bays})
		for module in Civic.options_for({"decor_family":"civic_office","level":1}):
			choices.append({"key":module.key,"side":module.side*Trial.DECOR_SCALE,"bays":module.bays})
	return choices

func _place(sample: Dictionary, pass_id: int) -> bool:
	if not contexts.has(sample.tile): return false
	var context: Dictionary=contexts[sample.tile]
	var p: Vector2=sample.a+sample.normal*16.0
	var housing := Trial.residential(world.tiles[sample.tile],p,context.trial_edge_centers,context.trial_harbours)
	var seed := absi(hash(str(sample.p)))
	for choice in _choices(housing,seed,pass_id):
		var key: String=choice.key
		var s := {"iid":"z_frontage:%s:%04d" % [sample.tile,added.size()],"kind":"house","tile":sample.tile,"pos":p,
			"side":choice.side,"pad":choice.side,"level":1,"decor_scale":Trial.DECOR_SCALE,"decor_asset":key,
			"trial_density":true,"trial_frontage":true,"trial_residential":housing,"trial_tile":world.tiles[sample.tile],
			"trial_edge_centers":context.trial_edge_centers,"trial_harbours":context.trial_harbours,"max_relief":6.0,
			"polluting":false,"sprite":null,"name":"Semi-detached homes" if key.begins_with("civic_semi") else ("Apartments" if key=="house_lvl3" else "Neighbourhood building")}
		if key.begins_with("civic_"): s.decor_family="civic_office" if key.begins_with("civic_long") else ("civic_l" if key.begins_with("civic_corner") else key.get_slice("_lvl",0))
		if choice.has("bays"): s.civic_bays=choice.bays
		# Test both orientations, keeping the street-facing silhouette at the
		# sidewalk edge. No new asphalt driveway or reserved access stem.
		for turn in ([0.0,PI] if pass_id==0 else [PI*0.5,PI*1.5]):
			fit.street_pose(s,sample.road,sample.p,float(sample.side),0.0,turn)
			if not fit.trial_plot_allowed(s): refusals.zoning+=1;continue
			if not fit.clear_building(s,world.tiles[sample.tile].center): refusals.plot+=1;continue
			s.footprints=fit.footprints(s);s.footprint=s.footprints[0]
			for poly in s.footprints:
				fit.reserve(str(s.iid),poly)
				for id in Index.query(sample_index,fit.polygon_bounds(poly)):
					var other: Dictionary=samples[id]
					if not other.covered and (other.excluded=="" or str(other.excluded).begins_with("plot_")) and touches(other.a,other.b,poly):
						# A successful exact fit proves the conservative probe was
						# overly cautious here: count this frontage in both totals.
						if other.excluded!="":
							other.excluded="";tile_totals[other.tile].usable_length+=float(other.weight)
						other.covered=true
						tile_totals[other.tile].covered_length+=float(other.weight)
			world.standing.append(s);added.append(s)
			return true
	return false

func _at_target(tile: String) -> bool:
	return float(tile_totals[tile].covered_length)/maxf(0.001,float(tile_totals[tile].usable_length))>=TARGET

func report() -> Dictionary:
	var result := {"roadside_length":0.0,"usable_length":0.0,"covered_length":0.0,"coverage":0.0,"all_frontage_coverage":0.0,"excluded":{},"by_tile":{}}
	for s in samples:
		var tile: Dictionary=result.by_tile.get_or_add(s.tile,{"roadside_length":0.0,"usable_length":0.0,"covered_length":0.0,"coverage":0.0})
		var w: float=s.weight
		result.roadside_length+=w;tile.roadside_length+=w
		if s.excluded!="":
			result.excluded[s.excluded]=float(result.excluded.get(s.excluded,0))+w
			continue
		result.usable_length+=w;tile.usable_length+=w
		if s.covered: result.covered_length+=w;tile.covered_length+=w
	result.coverage=result.covered_length/maxf(0.001,result.usable_length)
	result.all_frontage_coverage=result.covered_length/maxf(0.001,result.roadside_length)
	for tile in result.by_tile.values(): tile.coverage=tile.covered_length/maxf(0.001,tile.usable_length)
	return result
