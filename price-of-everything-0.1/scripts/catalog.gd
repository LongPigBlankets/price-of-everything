extends Node
# Static reference data: goods, recipes, (later: buildings).
# Loaded once at game start. Never mutated during a match.

const GOODS_CSV_PATH := "res://data/Goods - goodsMVP.csv"
const RECIPES_CSV_PATH := "res://data/recipes_all.csv"
const BUILDINGS_CSV_PATH := "res://data/Buildings - buildingsMVP.csv"
const PORTS_CSV_PATH := "res://data/ports.csv"
const TILE_PROPS_CSV_PATH := "res://data/tile_properties.csv"
const INFRA_CSV_PATH := "res://data/infrastructure.csv"

# recipes_all.csv references buildings by internal_name; a few don't match the
# game's building internal_names, so alias them here. Recipes whose building can't
# be resolved (or whose goods don't all exist) are dropped by the promotion gate.
const BUILDING_ALIAS := {
	"power_plant": "coal_power",
	"factory": "industrial_factory",
	"industrial_goods_factory": "industrial_factory",
	"consumer_goods_factory": "consumer_factory",
	"water_well": "water_pump",
	"desal_plant": "desal",
	"water_treatment_plant": "water_recycling",
	"hydro_dam": "hydro_power_plant",
	"forest": "new_forest",
}

# --- Goods storage ---
var _goods_by_id: Dictionary = {}
var _goods_by_internal_name: Dictionary = {}
var _all_goods: Array = []

# --- Recipes storage ---
var _recipes_by_id: Dictionary = {}
var _recipes_by_building: Dictionary = {}
var _all_recipes: Array = []

# Buildings storage
var _buildings_by_id: Dictionary = {}
var _buildings_by_internal_name: Dictionary = {}
var _all_buildings: Array = []

# Ports storage
var _ports: Array = []

# Tile display names (nickname, else city_name) for labelling tile ids in the UI
var _tile_names: Dictionary = {}

# Infrastructure type properties (range, routing, tolerated classes, ...) keyed by type
var _infra_by_type: Dictionary = {}

# Per-tile routing data (static, from tile_properties.csv; live infra is a later wire-up)
var _tile_infra: Dictionary = {}   # tile_id -> ["roads","rail",...] (normalised)
var _tile_land: Dictionary = {}    # tile_id -> bool (false for sea/deep_sea)

# Routing caches. route() pathfinding and nearest_port_tile() are recomputed per
# building, per input good, EVERY turn by the production loop — and the results
# only change when the road/rail network changes (route) or never (ports are
# static). Memoise them. _route_cache is cleared only when a *routing* mode
# (rail/roads/pipes) is added or removed; _port_cache is permanent (static).
var _route_cache: Dictionary = {}  # "src|dst|modes" -> route dict
var _port_cache: Dictionary = {}   # from_tile -> nearest port tile_id

# Infra ids that goods routing actually traverses (see _modes_for_good). Adding or
# removing anything else (notably cables, which carry power, not goods) leaves every
# route unchanged, so we must NOT clear the route cache for it.
const ROUTE_AFFECTING_INFRA := ["roads", "rail", "pipes", "reinf_pipes"]

const MARKET_DESTINATION := "__market__"

const ROUTE_MAP_W := 30
const ROUTE_MAP_H := 20

# Global maintenance balance knob, applied to every building's per-turn maintenance
# as it is parsed (lives here, not in EconomyConfig, because Catalog loads first).
const MAINTENANCE_MULTIPLIER := 2.0

func _ready() -> void:
	_load_goods()
	_load_buildings()
	_load_recipes()
	_load_ports()
	_load_tile_names()
	_load_infrastructure()
	# Wire the output-destination safeguard after the other autoloads exist.
	call_deferred("_wire_routing_safeguard")


# When a building's output destination changes, re-validate the route it will now
# use (warming the cache) and warn if the new destination is unreachable. The
# route cache is keyed by (source, dest, modes) — pure map facts — so a changed
# destination never makes a cached entry stale; this is a reachability safeguard.
func _wire_routing_safeguard() -> void:
	var ms := get_node_or_null("/root/MatchState")
	if ms != null and ms.has_signal("output_stockpile_destination_changed"):
		if not ms.output_stockpile_destination_changed.is_connected(_on_output_destination_changed):
			ms.output_stockpile_destination_changed.connect(_on_output_destination_changed)


func _on_output_destination_changed(instance_id: String, tile_id: String, good_id: String) -> void:
	var ms := get_node_or_null("/root/MatchState")
	if ms == null:
		return
	var building: Dictionary = ms.buildings.get(instance_id, {})
	var source: String = str(building.get("tile_id", ""))
	if source == "":
		return
	var dest := tile_id
	if dest == MARKET_DESTINATION:
		dest = nearest_port_tile(source)
	if dest == "" or dest == source:
		return
	var r := route(source, dest, good_id)
	if int(r.get("turns", 0)) >= (1 << 30):
		push_warning("[Catalog] Output of %s now routes to %s, which is unreachable." % [instance_id, dest])

# =========================================================================
# PORTS
# =========================================================================

func _load_ports() -> void:
	_ports.clear()
	if not FileAccess.file_exists(PORTS_CSV_PATH):
		push_warning("Catalog: ports CSV not found at %s" % PORTS_CSV_PATH)
		return
	var file := FileAccess.open(PORTS_CSV_PATH, FileAccess.READ)
	if file == null:
		return
	var headers := file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var raw := {}
		for i in headers.size():
			raw[headers[i].strip_edges().to_lower().replace(" ", "_")] = line[i].strip_edges()
		_ports.append({
			"id": raw.get("id", ""),
			"name": raw.get("name", ""),
			"tile_id": raw.get("tile_id", ""),
			"region": raw.get("region", ""),
		})

func all_ports() -> Array:
	return _ports.duplicate(true)

func nearest_port_tile(from_tile_id: String) -> String:
	if _port_cache.has(from_tile_id):
		return _port_cache[from_tile_id]
	var best := ""
	var best_d := 1 << 30
	for p in _ports:
		var t: String = p.get("tile_id", "")
		if t == "":
			continue
		var d := tile_hex_distance(from_tile_id, t)
		if d < best_d:
			best_d = d
			best = t
	_port_cache[from_tile_id] = best
	return best

func tile_hex_distance(a: String, b: String) -> int:
	var ca := _port_tile_to_coord(a)
	var cb := _port_tile_to_coord(b)
	if ca == Vector2i(-1, -1) or cb == Vector2i(-1, -1):
		return 0
	var aa := _oddq_to_axial(ca)
	var ab := _oddq_to_axial(cb)
	var dq := aa.x - ab.x
	var dr := aa.y - ab.y
	return int((abs(dq) + abs(dr) + abs(dq + dr)) / 2)

func _port_tile_to_coord(tile_id: String) -> Vector2i:
	var parts := tile_id.split("_")
	if parts.size() != 3 or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[1]) - 1, int(parts[2]) - 1)

func _oddq_to_axial(coord: Vector2i) -> Vector2i:
	return Vector2i(coord.x, coord.y - int((coord.x - (coord.x & 1)) / 2))

func _load_tile_names() -> void:
	_tile_names.clear()
	_tile_infra.clear()
	_tile_land.clear()
	if not FileAccess.file_exists(TILE_PROPS_CSV_PATH):
		return
	var file := FileAccess.open(TILE_PROPS_CSV_PATH, FileAccess.READ)
	if file == null:
		return
	var headers := file.get_csv_line()
	var idx := {}
	for i in headers.size():
		idx[headers[i].strip_edges().to_lower()] = i
	var id_i: int = idx.get("id", -1)
	var nick_i: int = idx.get("nickname", -1)
	var city_i: int = idx.get("city_name", -1)
	var type_i: int = idx.get("type", -1)
	var infra_i: int = idx.get("infrastructure_present", -1)
	if id_i < 0:
		return
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() <= id_i or line[id_i].strip_edges() == "":
			continue
		var tid := line[id_i].strip_edges()
		var nick := ""
		if nick_i >= 0 and nick_i < line.size():
			nick = line[nick_i].strip_edges()
		var city := ""
		if city_i >= 0 and city_i < line.size():
			city = line[city_i].strip_edges()
		var label_name := nick if nick != "" else city
		if label_name != "":
			_tile_names[tid] = label_name
		var ttype := ""
		if type_i >= 0 and type_i < line.size():
			ttype = line[type_i].strip_edges().to_lower()
		_tile_land[tid] = ttype != "sea" and ttype != "deep_sea"
		if infra_i >= 0 and infra_i < line.size():
			var infra_list: Array = []
			for part in str(line[infra_i]).split("|", false):
				var norm := _normalise_infra_id(part.strip_edges().to_lower())
				if norm != "" and not infra_list.has(norm):
					infra_list.append(norm)
			if not infra_list.is_empty():
				_tile_infra[tid] = infra_list

func _normalise_infra_id(value: String) -> String:
	match value:
		"roads", "road":
			return "roads"
		"rail", "rails", "railway", "railways":
			return "rail"
		"pipes", "pipework", "pipeworks":
			return "pipes"
		"reinf_pipes", "reinforced_pipes", "reinforced_pipework", "reinforced_pipeworks":
			return "reinf_pipes"
		_:
			return value

func tile_name(tile_id: String) -> String:
	return _tile_names.get(tile_id, "")

func tile_has_infrastructure(tile_id: String, infra_type: String) -> bool:
	return _tile_infra.get(tile_id, []).has(_normalise_infra_id(infra_type.strip_edges().to_lower()))

func is_land_tile(tile_id: String) -> bool:
	return bool(_tile_land.get(tile_id, true))

func add_tile_infrastructure(tile_id: String, infra_type: String) -> void:
	# Mirror a runtime-built road/rail into the router's live infra map.
	var norm := _normalise_infra_id(infra_type.strip_edges().to_lower())
	if tile_id == "" or norm == "":
		return
	var list: Array = _tile_infra.get(tile_id, [])
	if not list.has(norm):
		list.append(norm)
		_tile_infra[tile_id] = list
		if ROUTE_AFFECTING_INFRA.has(norm):
			_route_cache.clear()   # routing network changed: cached paths may now be shorter

func reset_runtime_infrastructure() -> void:
	# Rebuild the tile-infra map from the CSV baseline, dropping runtime-built
	# roads/rails (this autoload outlives the map scene, so a previous match's
	# infrastructure would otherwise leak into a loaded save). SaveLoad calls this
	# before re-applying a snapshot's infrastructure.
	_load_tile_names()
	_route_cache.clear()

func remove_tile_infrastructure(tile_id: String, infra_type: String) -> void:
	var norm := _normalise_infra_id(infra_type.strip_edges().to_lower())
	var list: Array = _tile_infra.get(tile_id, [])
	if list.has(norm):
		list.erase(norm)
		_tile_infra[tile_id] = list
		if ROUTE_AFFECTING_INFRA.has(norm):
			_route_cache.clear()   # routing network changed: cached paths may now be invalid

func tile_label(tile_id: String) -> String:
	# "name - (a_b)", or "(a_b)" when the tile has no nickname/city_name.
	if tile_id == "":
		return ""
	var coord_part := tile_id
	if coord_part.begins_with("tile_"):
		coord_part = coord_part.substr(5)
	var label_name: String = _tile_names.get(tile_id, "")
	return ("%s - (%s)" % [label_name, coord_part]) if label_name != "" else ("(%s)" % coord_part)

func _load_infrastructure() -> void:
	_infra_by_type.clear()
	if not FileAccess.file_exists(INFRA_CSV_PATH):
		return
	var file := FileAccess.open(INFRA_CSV_PATH, FileAccess.READ)
	if file == null:
		return
	var headers := file.get_csv_line()
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < 1 or line[0].strip_edges() == "":
			continue
		var raw := {}
		for i in headers.size():
			if i < line.size():
				raw[headers[i].strip_edges().to_lower().replace(" ", "_")] = line[i].strip_edges()
		var type_id := str(raw.get("type", ""))
		if type_id == "":
			continue
		var range_str := str(raw.get("range", ""))
		_infra_by_type[type_id] = {
			"type": type_id,
			"display_name": raw.get("display_name", ""),
			"range": int(range_str) if range_str.is_valid_int() else 0,
			"routing": raw.get("routing", ""),
			"market_connector": str(raw.get("market_connector", "")).to_lower() == "true",
			"good_types_tolerated": str(raw.get("good_types_tolerated", "")).split("|", false),
			"double_cost_types": str(raw.get("double_cost_types", "")).split("|", false),
		}

func all_infrastructure() -> Array:
	return _infra_by_type.values()

func infra(type_id: String) -> Dictionary:
	return _infra_by_type.get(type_id, {})

func infra_range(type_id: String) -> int:
	return int(_infra_by_type.get(type_id, {}).get("range", 0))

# =========================================================================
# TRANSPORT ROUTING (turn-move shortest path; see docs/transport-routing-plan.md)
# =========================================================================

const ROUTE_MODE_NONE := "nothing"

func tile_neighbours(tile_id: String) -> Array:
	# Hex (odd-q offset) neighbours, clamped to the map.
	var c := _port_tile_to_coord(tile_id)  # (col-1, row-1) == (q, r)
	if c == Vector2i(-1, -1):
		return []
	var offs: Array
	if c.x % 2 == 1:
		offs = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0)]
	else:
		offs = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
	var out: Array = []
	for o in offs:
		var nc: int = c.x + o.x
		var nr: int = c.y + o.y
		if nc >= 0 and nc < ROUTE_MAP_W and nr >= 0 and nr < ROUTE_MAP_H:
			out.append("tile_%d_%d" % [nc + 1, nr + 1])
	return out

func _mode_range(mode: String) -> int:
	if mode == ROUTE_MODE_NONE:
		return 1
	return maxi(1, infra_range(mode))

func _tile_supports_mode(tile_id: String, mode: String) -> bool:
	if mode == ROUTE_MODE_NONE:
		return bool(_tile_land.get(tile_id, true))
	return _tile_infra.get(tile_id, []).has(mode)

const FLUID_CLASSES := ["safe_liquid", "hazard_liquid", "liquid", "gas"]

func _modes_for_good(good_id: String) -> Array:
	var tclass := get_transport_class(good_id) if good_id != "" else ""
	# Fluids (liquids/gases) move ONLY by pipe — no overland haul. Solids may go
	# overland (slow fallback) or by rail/road. rail first (longer range) wins ties.
	var modes: Array = [] if FLUID_CLASSES.has(tclass) else [ROUTE_MODE_NONE]
	for m in ["rail", "roads", "pipes", "reinf_pipes"]:
		var tolerated: Array = _infra_by_type.get(m, {}).get("good_types_tolerated", [])
		if good_id == "" or tclass == "" or tolerated.has(tclass):
			modes.append(m)
	return modes

func _turn_move_neighbours(tile_id: String, modes: Array) -> Array:
	# Tiles reachable in ONE turn (one mode, up to its range hops). [{tile, mode}]
	var out: Array = []
	var seen: Dictionary = {}
	for m in modes:
		if not _tile_supports_mode(tile_id, m):
			continue
		var rng := _mode_range(m)
		var visited: Dictionary = {tile_id: true}
		var frontier: Array = [tile_id]
		var depth := 0
		while not frontier.is_empty() and depth < rng:
			var nextf: Array = []
			for t in frontier:
				for nb in tile_neighbours(t):
					if visited.has(nb) or not _tile_supports_mode(nb, m):
						continue
					visited[nb] = true
					nextf.append(nb)
					if not seen.has(nb):
						seen[nb] = true
						out.append({"tile": nb, "mode": m})
			frontier = nextf
			depth += 1
	return out

func route(source_tile: String, dest_tile: String, good_id: String = "") -> Dictionary:
	# Cached front for the Dijkstra solver below. Trivial cases pass through;
	# reachable/unreachable results are memoised per (src, dst, modes) and the
	# cache is cleared whenever the network changes (see add/remove_tile_infrastructure).
	if source_tile == "" or dest_tile == "" or source_tile == dest_tile:
		return _route_uncached(source_tile, dest_tile, good_id)
	var key := "%s|%s|%s" % [source_tile, dest_tile, "-".join(_modes_for_good(good_id))]
	if not _route_cache.has(key):
		_route_cache[key] = _route_uncached(source_tile, dest_tile, good_id)
	return _route_cache[key]


func _route_uncached(source_tile: String, dest_tile: String, good_id: String = "") -> Dictionary:
	# Fewest turns A->B. Returns {turns, path:[turn-boundary tiles], legs:[{mode,from,to}]}.
	# (Objective currently FASTEST; cheapest/blended need infra cost_per_unit_shipped.)
	if source_tile == "" or dest_tile == "":
		return {"turns": 0, "path": [], "legs": []}
	if source_tile == dest_tile:
		return {"turns": 0, "path": [source_tile], "legs": [], "tiles": [source_tile]}  # 0-turn same-tile
	var modes := _modes_for_good(good_id)
	var INF := 1 << 30
	var dist: Dictionary = {source_tile: 0}
	var prev: Dictionary = {}  # tile -> {from, mode}
	# Every turn-move costs exactly 1 turn, so this graph is unit-weight: plain BFS finds
	# shortest paths in O(V+E). (The old solver re-scanned every known tile for the minimum
	# on each step — O(V^2) — which dominated routing once the road/rail network spanned the
	# map.) A unit-weight node can never be relaxed below the distance it is first reached at,
	# so processing the queue FIFO yields the identical prev-tree/distances the old code did.
	var queue: Array = [source_tile]
	var head := 0
	while head < queue.size():
		var u: String = str(queue[head])
		head += 1
		if u == dest_tile:
			break
		var nd := int(dist[u]) + 1
		for entry in _turn_move_neighbours(u, modes):
			var nb: String = entry.tile
			if dist.has(nb):
				continue
			dist[nb] = nd
			prev[nb] = {"from": u, "mode": entry.mode}
			queue.append(nb)
	if not dist.has(dest_tile):
		return {"turns": INF, "path": [], "legs": [], "tiles": []}  # unreachable via networks
	var path: Array = [dest_tile]
	var legs: Array = []
	var cur := dest_tile
	while prev.has(cur):
		var p: Dictionary = prev[cur]
		legs.push_front({"mode": p.mode, "from": p.from, "to": cur})
		path.push_front(p.from)
		cur = p.from
	var tiles: Array = [source_tile]
	for leg in legs:
		var seg := _mode_shortest_path(str(leg.from), str(leg.to), str(leg.mode))
		for i in range(1, seg.size()):
			tiles.append(seg[i])
	return {"turns": int(dist[dest_tile]), "path": path, "legs": legs, "tiles": tiles}

func _mode_shortest_path(from_tile: String, to_tile: String, mode: String) -> Array:
	# BFS shortest tile path from->to staying on one mode's network.
	if from_tile == to_tile:
		return [from_tile]
	var prev: Dictionary = {}
	var visited: Dictionary = {from_tile: true}
	var queue: Array = [from_tile]
	var head := 0
	while head < queue.size():
		var u: String = queue[head]
		head += 1
		if u == to_tile:
			break
		for nb in tile_neighbours(u):
			if visited.has(nb) or not _tile_supports_mode(nb, mode):
				continue
			visited[nb] = true
			prev[nb] = u
			queue.append(nb)
	if not prev.has(to_tile):
		return [from_tile, to_tile]  # fallback (shouldn't happen for a valid leg)
	var out: Array = [to_tile]
	var cur := to_tile
	while prev.has(cur):
		cur = prev[cur]
		out.push_front(cur)
	return out

# =========================================================================
# GOODS
# =========================================================================

func _load_goods() -> void:
	if not FileAccess.file_exists(GOODS_CSV_PATH):
		push_error("Catalog: goods CSV not found at %s" % GOODS_CSV_PATH)
		return
	
	var file := FileAccess.open(GOODS_CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var good := _parse_good_row(headers, line)
		if good.is_empty():
			continue
		_all_goods.append(good)
		_goods_by_id[good.id] = good
		if good.internal_name != "":
			_goods_by_internal_name[good.internal_name] = good
	
	file.close()
	print("Catalog: loaded %d goods" % _all_goods.size())


func _parse_good_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var raw := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		raw[key] = val
	
	return {
		"id": raw.get("id", ""),
		"internal_name": raw.get("internal_name", ""),
		"display_name": raw.get("display_name", raw.get("internal_name", "")),
		"category": raw.get("category", ""),
		"transport_class": raw.get("transport_class", EconomyConfig.DEFAULT_TRANSPORT_WEIGHT_CLASS),
		"good_type": raw.get("good_type", ""),
		"base_price": float(raw.get("base_price", "1")),
		"decay_rate": float(raw.get("decay_rate", "0")),
		"is_buyable": raw.get("is_buyable", "").to_upper() == "TRUE",
		"is_sellable": raw.get("is_sellable", "").to_upper() == "TRUE",
		"is_fossil_fuel": raw.get("is_fossil_fuel", "").to_lower() == "yes",
	}

# Public API: goods
func all_goods() -> Array:
	return _all_goods

func get_good(good_id: String) -> Dictionary:
	return _goods_by_id.get(good_id, {})

func buyable_goods() -> Array:
	return _all_goods.filter(func(g: Dictionary) -> bool: return bool(g.get("is_buyable", false)))

func sellable_goods() -> Array:
	return _all_goods.filter(func(g: Dictionary) -> bool: return bool(g.get("is_sellable", false)))

func is_good_buyable(good_id: String) -> bool:
	return bool(get_good(good_id).get("is_buyable", false))

func is_good_sellable(good_id: String) -> bool:
	return bool(get_good(good_id).get("is_sellable", false))

func get_good_by_internal_name(internal_name: String) -> Dictionary:
	return _goods_by_internal_name.get(internal_name, {})

func get_display_name(good_id: String) -> String:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("display_name", good_id)

func get_internal_name(good_id: String) -> String:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("internal_name", "")

func get_base_price(good_id: String) -> float:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("base_price", 1.0)

func get_transport_class(good_id: String) -> String:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	var weight_class: String = g.get("transport_class", "")
	return EconomyConfig.DEFAULT_TRANSPORT_WEIGHT_CLASS if weight_class == "" else weight_class

func is_raw(good_id: String) -> bool:
	var g: Dictionary = _goods_by_id.get(good_id, {})
	return g.get("good_type", "") == "raw"

# =========================================================================
# RECIPES
# =========================================================================

func _load_recipes() -> void:
	if not FileAccess.file_exists(RECIPES_CSV_PATH):
		push_error("Catalog: recipes CSV not found at %s" % RECIPES_CSV_PATH)
		return
	
	var file := FileAccess.open(RECIPES_CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var recipe := _parse_recipe_row(headers, line)
		if recipe.is_empty():
			continue
		_all_recipes.append(recipe)
		_recipes_by_id[recipe.recipe_id] = recipe
		var building_id: String = recipe.get("building_id", "")
		if building_id != "":
			if not _recipes_by_building.has(building_id):
				_recipes_by_building[building_id] = []
			_recipes_by_building[building_id].append(recipe)
	
	file.close()
	print("Catalog: loaded %d recipes" % _all_recipes.size())

func _parse_recipe_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var raw := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		raw[key] = val
	
	# Inputs: input_1/qty_1 .. input_6/qty_6
	var inputs: Array = []
	for i in range(1, 7):
		var input_name: String = raw.get("input_%d" % i, "")
		var input_qty_str: String = raw.get("qty_%d" % i, "")
		if input_name == "" or input_qty_str == "":
			continue
		var good: Dictionary = get_good_by_internal_name(input_name)
		inputs.append({
			"good_id": good.get("id", ""),
			"internal_name": input_name,
			"qty": int(input_qty_str),
		})

	# Outputs: output_1/output_qty_1 .. output_5/output_qty_5
	var outputs: Array = []
	for i in range(1, 6):
		var output_name: String = raw.get("output_%d" % i, "")
		var output_qty_str: String = raw.get("output_qty_%d" % i, "")
		if output_name == "" or output_qty_str == "":
			continue
		var parsed_output_qty: int = int(output_qty_str)
		if parsed_output_qty <= 0:
			continue
		var output_good_data: Dictionary = get_good_by_internal_name(output_name)
		outputs.append({
			"good_id": output_good_data.get("id", ""),
			"internal_name": output_name,
			"qty": parsed_output_qty,
		})

	# --- Promotion gate ---
	# Active only if the building resolves, there's at least one output, and EVERY
	# input + output is an existing good. Otherwise the recipe stays dormant.
	var resolved_building_id := _resolve_building_id(raw.get("building_id", ""))
	if resolved_building_id == "" or outputs.is_empty():
		return {}
	for inp in inputs:
		if inp.good_id == "":
			return {}
	for outp in outputs:
		if outp.good_id == "":
			return {}

	return {
		"recipe_id": raw.get("recipe_id", ""),
		"display_name": raw.get("display_name", ""),
		"building_id": resolved_building_id,
		"recipe_type": raw.get("category", ""),
		"inputs": inputs,
		"outputs": outputs,
		"output_name": outputs[0].internal_name,
		"output_good_id": outputs[0].good_id,
		"output_qty": outputs[0].qty,
		"energy_req": int(raw.get("energy_req", "0")),
		"requirements": _parse_requirements(raw.get("requirements", "")),
		"required_research": raw.get("required_research", ""),
	}

# Parses the requirements string into a list of typed entries.
# Format: "type:value" entries joined by ";" (or "|"). Bare "wind"/"solar"
# tokens are treated as potential requirements. Supported types: deposit,
# produces, potential. Unknown tokens are kept as {"type": "other", ...}.
func _parse_requirements(raw_str: String) -> Array:
	var out: Array = []
	if raw_str == "":
		return out
	var parts: PackedStringArray = raw_str.replace("|", ";").split(";", false)
	for part in parts:
		var token: String = part.strip_edges()
		if token == "":
			continue
		if token.ends_with("_deposit"):
			out.append({"type": "deposit", "value": token.trim_suffix("_deposit")})
			continue
		if token == "wind" or token == "solar":
			out.append({"type": "potential", "value": token})
			continue
		var colon: int = token.find(":")
		if colon < 0:
			out.append({"type": "other", "value": token})
			continue
		var key: String = token.substr(0, colon).strip_edges()
		var val: String = token.substr(colon + 1).strip_edges()
		match key:
			"deposit", "produces":
				out.append({"type": key, "value": val})
			"potential":
				out.append({"type": "potential", "value": val})
			_:
				out.append({"type": "other", "value": token})
	return out

# Public API: recipes
func all_recipes() -> Array:
	return _all_recipes

func get_recipe(recipe_id: String) -> Dictionary:
	return _recipes_by_id.get(recipe_id, {})

func get_recipes_for_building(building_id: String) -> Array:
	# Feature 1: hide recipes gated behind un-researched tech (required_research
	# column). Base recipes (empty column) are always available.
	var out: Array = []
	for r in _recipes_by_building.get(building_id, []):
		var req: String = str(r.get("required_research", ""))
		if req == "" or MatchState.is_unlocked(req):
			out.append(r)
	return out

func recipe_produces(recipe: Dictionary, good_id: String) -> bool:
	if str(recipe.get("output_good_id", "")) == good_id:
		return true
	for o in recipe.get("outputs", []):
		if str(o.get("good_id", "")) == good_id:
			return true
	return false

func recipes_producing(good_id: String) -> Array:
	if good_id == "":
		return []
	return _all_recipes.filter(func(r: Dictionary) -> bool: return recipe_produces(r, good_id))

func recipe_output_qty(recipe: Dictionary, good_id: String) -> int:
	for o in recipe.get("outputs", []):
		if str(o.get("good_id", "")) == good_id:
			return int(o.get("qty", 0))
	if str(recipe.get("output_good_id", "")) == good_id:
		return int(recipe.get("output_qty", 0))
	return 0
	
	
# =========================================================================
# BUILDINGS
# =========================================================================
func _load_buildings() -> void:
	if not FileAccess.file_exists(BUILDINGS_CSV_PATH):
		push_error("Catalog: buildings CSV not found at %s" % BUILDINGS_CSV_PATH)
		return
	
	var file := FileAccess.open(BUILDINGS_CSV_PATH, FileAccess.READ)
	var headers := file.get_csv_line()
	
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var building := _parse_building_row(headers, line)
		if building.is_empty():
			continue
		_all_buildings.append(building)
		_buildings_by_id[building.id] = building
		if building.internal_name != "":
			_buildings_by_internal_name[building.internal_name] = building
	
	file.close()
	print("Catalog: loaded %d buildings" % _all_buildings.size())

func _parse_building_row(headers: PackedStringArray, line: PackedStringArray) -> Dictionary:
	var raw := {}
	for i in headers.size():
		var key := headers[i].strip_edges().to_lower().replace(" ", "_")
		var val: String = line[i].strip_edges() if i < line.size() else ""
		raw[key] = val
	
	var materials: Array = []
	for n in range(1, 8):   # up to 7 build materials (was 5)
		var mat_name: String = raw.get("build_material_%d" % n, "")
		var mat_qty_str: String = raw.get("build_qty_%d" % n, "")
		if mat_name != "" and mat_qty_str != "":
			materials.append({"name": mat_name, "qty": int(mat_qty_str)})

	return {
		"id": raw.get("id", ""),
		"internal_name": raw.get("internal_name", ""),
		"display_name": raw.get("display_name", raw.get("internal_name", "")),
		"category": raw.get("building_category", "production").to_lower(),
		"building_type": _split_types(raw.get("building_type", "")),
		"required_research": raw.get("required_research", ""),
		"materials": materials,
		"base_price": float(raw.get("build_cost_money", "0")),
		"tile_size_used": 1 if raw.get("tile_size_used", "") == "" else int(raw.get("tile_size_used", "1")),
		"build_duration": 0 if raw.get("build_duration", "") == "" else int(raw.get("build_duration", "0")),
		"maintenance_cost": null if raw.get("maintenance_cost", "") == "" else MAINTENANCE_MULTIPLIER * float(raw.get("maintenance_cost", "0")),
		"labour_unskilled_required": int(raw.get("labour_unskilled_required", "0")),
		"labour_skilled_required": int(raw.get("labour_skilled_required", "0")),
		"labour_h_skilled_required": int(raw.get("labour_h_skilled_required", "0")),
		"storage_boost": int(raw.get("storage_boost", "0")) if str(raw.get("storage_boost", "0")).is_valid_int() else 0,
		"energy_cost": int(raw.get("energy_cost", "0")) if str(raw.get("energy_cost", "0")).is_valid_int() else 0,
	}

# Public API
func all_buildings() -> Array:
	return _all_buildings

func get_building(building_id: String) -> Dictionary:
	return _buildings_by_id.get(building_id, {})

func get_building_by_internal_name(internal_name: String) -> Dictionary:
	return _buildings_by_internal_name.get(internal_name, {})

func get_building_display_name(building_id: String) -> String:
	var b: Dictionary = _buildings_by_id.get(building_id, {})
	return b.get("display_name", building_id)

# Resolve a recipe's building reference (internal_name, possibly aliased) to a b_id.
func _resolve_building_id(building_field: String) -> String:
	if building_field == "":
		return ""
	var internal: String = BUILDING_ALIAS.get(building_field, building_field)
	var b: Dictionary = _buildings_by_internal_name.get(internal, {})
	return b.get("id", "")

# Split a pipe-separated building_type field into an array of trimmed tokens.
func _split_types(s: String) -> Array:
	var result: Array = []
	for t in s.split("|", false):
		var tt: String = t.strip_edges()
		if tt != "":
			result.append(tt)
	return result
