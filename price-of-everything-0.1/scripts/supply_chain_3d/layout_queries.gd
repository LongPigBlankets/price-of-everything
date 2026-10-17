extends RefCounted
## Persist only the model's pure geographical queries, never live goods/routes.
## Its existing memo tables include Callable.hash(), which changes each process.
## This adapter remaps that suffix while retaining every original query argument.
const Model := preload("res://scripts/empire_board_model.gd")
const Cache := preload("res://scripts/supply_chain_3d/bake_cache.gd")
const Landscape := preload("res://scripts/empire_board.gd")
static var _relief_geography := ""
var key := ""
var data := {}
var _cost_suffix := ""
var _shore_suffix := ""
var _previous_paths := {}

func prepare(cache: RefCounted, geography: Array, water: Callable) -> void:
	# Use the normal source layer so compiled-script exports recover the same
	# fingerprint from the package instead of hashing different .gdc bytes.
	key = "layout-" + Cache.digest([Cache.source_key("layout"), geography])
	data = cache.read(key)
	# Plot fitting asks for coast/land polygons clipped to each hex. Re-clipping
	# hundreds of tiles dominated the remaining first-process layout time.
	if data.has("relief"):
		Landscape._relief_cache = data.relief.duplicate(true)
	elif _relief_geography != key:
		Landscape._relief_cache.clear()
	_relief_geography = key
	# Street routing is also pure geography, but its memo table otherwise dies
	# with the process. Keep this view's map-specific entries out of other boards.
	_previous_paths = Model.Streets._paths
	Model.Streets._paths = data.get("paths", {}).duplicate(true)
	_cost_suffix = "|" + str(water.hash())
	_shore_suffix = ", " + str(water.hash()) + "]"
	for query in data.get("costs", {}): Model._street_costs[query + _cost_suffix] = data.costs[query]
	for query in data.get("shores", {}): Model._shore_streets[query + _shore_suffix] = data.shores[query]

func finish(cache: RefCounted) -> void:
	var costs := {}
	var shores := {}
	for query in Model._street_costs.keys():
		if str(query).ends_with(_cost_suffix):
			costs[str(query).trim_suffix(_cost_suffix)] = Model._street_costs[query]
			Model._street_costs.erase(query)
	for query in Model._shore_streets.keys():
		if str(query).ends_with(_shore_suffix):
			shores[str(query).trim_suffix(_shore_suffix)] = Model._shore_streets[query]
			Model._shore_streets.erase(query)
	var updated := {"costs": costs, "shores": shores, "paths": Model.Streets._paths,
		"relief": Landscape._relief_cache.duplicate(true)}
	Model.Streets._paths = _previous_paths
	_previous_paths = {}
	if updated != data:
		data = updated
		cache.write(key, data)
