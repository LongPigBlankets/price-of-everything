extends "res://scripts/supply_chain_3d/road_alignment.gd"
## Road alignment for the company view that remembers each road chain's result for
## the session. A chain is solved again only when something it can see changed:
## its own roads, the roads and bends already reserved around it, the buildings
## and depots it must avoid, the mine pits that grade its ground, or which company
## tiles it may run through. A building on a new tile re-solves that tile's chains
## and the neighbours that can now reach into it, and reuses everything else.
const Model := preload("res://scripts/empire_board_model.gd")
const BakeCache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
## Farther than any serpentine bend, its rounding and its clearance query reach.
const REACH := 300.0
const MEMO_LIMIT := 20000

static var _memo := {}
var memo_enabled := false
var memo_pits: Array = []
var memo_depots: Array = []
var memo_hits := 0
var memo_misses := 0
var _seed_chains: Array = []

func _engineer(chain: Array) -> Array:
	if not memo_enabled: return super._engineer(chain)
	var key := _memo_key(chain)
	var entry: Dictionary = _memo.get(key, {})
	if entry.is_empty():
		memo_misses += 1
		var counts := [switchbacks, constrained, grade_eased]
		var reserved_from := _roads.size()
		var result: Array = super._engineer(chain)
		if _memo.size() >= MEMO_LIMIT: _memo.clear()
		_memo[key] = {"result": _relative(result, chain), "reserved": _roads.slice(reserved_from).map(func(r: Dictionary) -> Dictionary: return r.duplicate()),
			"counts": [switchbacks - counts[0], constrained - counts[1], grade_eased - counts[2]]}
		return result
	memo_hits += 1
	switchbacks += entry.counts[0]; constrained += entry.counts[1]; grade_eased += entry.counts[2]
	# The bends this chain reserved still keep later chains clear of it.
	for rec in entry.reserved:
		var copy: Dictionary = rec.duplicate()
		Index.insert(_index, Index.bounds(copy.a, copy.b, 20), _roads.size()); _roads.append(copy)
	return _absolute(entry.result, chain)

## Everything _engineer() reads for this chain, by geometry, never by index.
## Heights along the chain decide whether it is steep. Only a steep stretch is
## rerouted, so only the ground around those stretches can change the result.
func _memo_key(chain: Array) -> String:
	var hasher := HashingContext.new()
	hasher.start(HashingContext.HASH_SHA256)
	var bounds := Rect2(chain[0].a, Vector2.ZERO)
	for rec in chain:
		bounds = bounds.expand(rec.a).expand(rec.b)
		var copy: Dictionary = rec.duplicate()
		copy.erase("original")
		hasher.update(var_to_bytes(BakeCache._ordered(copy)))
	_hash_ground(hasher, bounds.grow(_half(chain[0]) + 4.0))
	var search := _search_area(chain)
	if search.has_area():
		search = search.grow(REACH)
		hasher.update(var_to_bytes(search))
		var nearby: Array = []
		for id in Index.query(_index, search):
			var road: Dictionary = _roads[id]
			nearby.append([road.a, road.b, _half(road)])
		_hash_sorted(hasher, nearby)
		_hash_sorted(hasher, Index.query(_obstacle_index, search).map(func(id: int) -> PackedVector2Array: return _obstacles[id]))
		var tiles: Array = []
		for tid in _centers:
			if search.grow(Model.HEX_HALF.length()).has_point(_centers[tid]): tiles.append(str(tid))
		tiles.sort()
		hasher.update(var_to_bytes(tiles))
		_hash_ground(hasher, search)
	return hasher.finish().hex_encode()

## The steep stretches _engineer() would try to reroute, or an empty rect.
func _search_area(chain: Array) -> Rect2:
	var points := PackedVector2Array([chain[0].a]); var distances := PackedFloat32Array([0.0])
	for rec in chain:
		var count := maxi(1,ceili(rec.a.distance_to(rec.b)/STEP))
		for j in range(1,count+1):
			var p: Vector2=rec.b if j==count else rec.a.lerp(rec.b,float(j)/count)
			distances.append(distances[-1]+points[-1].distance_to(p)); points.append(p)
	if distances[-1]<30: return Rect2()
	var area := Rect2()
	var found := false
	for i in range(1,points.size()):
		var a := points[i-1]; var b := points[i]
		if float(_level.call(a))>=TUNNEL_LEVEL or float(_level.call(b))>=TUNNEL_LEVEL: continue
		if _water.is_valid() and (_water.call(a) or _water.call(b)): continue
		if absf(float(_height.call(b))-float(_height.call(a)))<=MAX_GRADE*a.distance_to(b)+0.1: continue
		# Wider than the run _engineer() grows from here: up to 45 each way.
		var lo := i-1; var hi := i
		while lo>0 and distances[i-1]-distances[lo]<45: lo-=1
		while hi<points.size()-1 and distances[hi]-distances[i]<45: hi+=1
		for k in range(lo, hi+1):
			area = area.expand(points[k]) if found else Rect2(points[k], Vector2.ZERO)
			found = true
	return area.grow(1.0) if found else Rect2()

## Mine pits and rail depots reshape the ground the chain is graded on.
func _hash_ground(hasher: HashingContext, area: Rect2) -> void:
	var items: Array = []
	for pit in memo_pits:
		if area.grow(float(pit.side) * 0.8).has_point(pit.pos): items.append([pit.pos, pit.side, pit.height])
	for depot in memo_depots:
		if area.grow(200.0).has_point(depot.pos): items.append([depot.pos, depot.yaw, depot.height])
	_hash_sorted(hasher, items)

## In a fixed order whatever order the indices return them in. Equal hashes of
## different items can only cause a needless solve, never a wrong reuse.
static func _hash_sorted(hasher: HashingContext, items: Array) -> void:
	var keyed: Array = items.map(func(item: Variant) -> Array: return [hash(item), item])
	keyed.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	hasher.update(var_to_bytes(items.size()))
	for entry in keyed: hasher.update(var_to_bytes(entry[1]))

## Results name their source road by index into this solve's road list. Store
## the position within the chain instead, which survives other roads joining.
static func _relative(result: Array, chain: Array) -> Array:
	var position := {}
	for i in chain.size(): position[chain[i].original] = i
	return result.map(func(rec: Dictionary) -> Dictionary:
		var copy: Dictionary = rec.duplicate()
		copy.original = position.get(rec.original, -1)
		return copy)

static func _absolute(result: Array, chain: Array) -> Array:
	return result.map(func(rec: Dictionary) -> Dictionary:
		var copy: Dictionary = rec.duplicate()
		if int(copy.original) >= 0: copy.original = chain[int(copy.original)].original
		return copy)

## Fills the memo for a model whose alignment came from a bake, a slice at a time,
## so the next change reuses the chains it does not reach. Same set-up and chain
## order as configure(), without the tunnel pass.
func begin_seed(model: Dictionary, height: Callable, level: Callable, water := Callable()) -> void:
	portals.clear(); switchbacks=0; constrained=0; grade_eased=0
	_height=height; _level=level; _water=water
	_roads=model.get("roads",[]).duplicate(); _index=Index.segments(_roads,20)
	_centers.clear(); _obstacles.clear(); _obstacle_index.clear()
	for tid in model.get("tiles",{}): _centers[tid]=model.tiles[tid].center
	_tile_index=Index.tiles(_centers)
	for s in model.get("standing",[]):
		if s.has("footprints"):
			for shape in s.footprints: _add_obstacle(shape)
			continue
		var poly := PackedVector2Array(s.get("footprint",[]))
		if poly.size()<3:
			var p: Vector2=s.pos; var half: float=float(s.get("pad",s.get("side",16)))*0.5+3
			poly=PackedVector2Array([p+Vector2(-half,-half),p+Vector2(half,-half),p+Vector2(half,half),p+Vector2(-half,half)])
		_add_obstacle(poly)
	for depot in model.get("depots",[]): _add_obstacle(preload("res://scripts/supply_chain_3d/rail_depot.gd").yard_polygon(depot))
	_seed_chains = _chains()
	_seed_chains.reverse()

## Returns true once every chain is in the memo.
func seed_step(budget_usec: int) -> bool:
	var started := Time.get_ticks_usec()
	while not _seed_chains.is_empty() and Time.get_ticks_usec() - started < budget_usec:
		_engineer(_seed_chains.pop_back())
	if not _seed_chains.is_empty(): return false
	_height=Callable(); _level=Callable(); _water=Callable()
	_roads=[]; _index.clear(); _obstacles.clear(); _obstacle_index.clear()
	return true
