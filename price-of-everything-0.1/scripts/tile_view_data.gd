extends RefCounted
const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")


## Room a building actually occupies, INCLUDING its level. A levelled-up building is bigger
## (BuildingLevels "size" mult) and MatchState.get_tile_space_used — the figure the build and
## upgrade gates test against — has always counted it that way. The land chart and its
## built|buyable|max readout did not: they drew every building at its level-1 footprint, so a
## tile of upgraded buildings looked far emptier than it was and an upgrade could be refused
## for want of room the player could see going spare (owner 2026-08-01).
static func footprint_of(building: Dictionary, bd: Dictionary) -> float:
	var base := maxf(0.0, float(bd.get("tile_size_used", 1)))
	return base * BuildingLevels.mult("size", int(building.get("level", 1)))
## Stateless data helpers for the Tile View Panels. Pure functions that read the
## canonical autoloads (MatchState, Production, Stockpile, Catalog, MarketState,
## CostSolver) and return plain dictionaries the UI can render. Keeping the maths
## here means TVP v1 and v2 can derive identical numbers.
##
## Status strings used throughout: "ok" (green), "warn" (amber), "problem" (red),
## "muted" (no activity / neutral).

# ─────────────────────────────────────────────────────────────────────────────
# POWER
# ─────────────────────────────────────────────────────────────────────────────
static func power_summary(tile_id: String) -> Dictionary:
	var produced := 0
	var consumed := 0
	var drawing: Array = []        # [{name, amount}]
	var producers: Array = []      # [{name, amount}]
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		var name := _building_name(building)
		var ran: bool = Production.last_turn_run.get(str(building.get("instance_id", "")), false)
		if not ran:
			continue
		for output in _recipe_outputs(recipe):
			if _output_internal(output) == "power":
				var pq := int(output.get("qty", 0))
				produced += pq
				if pq > 0:
					producers.append({"name": name, "amount": pq})
		var energy := int(recipe.get("energy_req", 0))
		if energy > 0:
			consumed += energy
			drawing.append({"name": name, "amount": energy})
	var net := produced - consumed
	# A tile connected to the grid (has cables) never shows red even in deficit —
	# the grid covers it (amber). Red is reserved for a tile that isn't on the grid.
	var connected := Power.is_supplied(tile_id)
	var status := "ok"
	if produced == 0 and consumed == 0:
		status = "muted"
	elif net >= 0:
		status = "ok"
	else:
		status = "warn" if connected else "problem"
	return {
		"produced": produced,
		"consumed": consumed,
		"net": net,
		"status": status,
		"connected": connected,
		# A cabled tile is on the National Grid; without cables it has no grid.
		"grid_name": "National Grid" if connected else "",
		"drawing": drawing,
		"producers": producers,
	}

# Any solar/wind generation anywhere on the (national) grid — gates the
# "Reduce intermittency" battery options.
static func grid_has_intermittent() -> bool:
	for iid in MatchState.buildings:
		var internal := str(Catalog.get_building(MatchState.buildings[iid].get("building_id", "")).get("internal_name", ""))
		if internal in ["solar_farm", "onshore_wind_farm", "offshore_wind_farm"]:
			return true
	return false

# Resolve a power-build button to a (building, recipe) and decide if it's
# buildable on this tile. Disabled reasons: recipe missing (coming soon), not
# enough land, or not enough money.
static func power_build_option(internal: String, hint: String, tile_id: String, _tile_data: Dictionary) -> Dictionary:
	var bd: Dictionary = Catalog.get_building_by_internal_name(internal)
	if bd.is_empty():
		return {"enabled": false, "building_id": "", "recipe_id": "", "reason": "This power source isn't available yet"}
	var bid := str(bd.get("id", ""))
	var rid := ""
	var recipes: Array = Catalog.get_recipes_for_building(bid)
	if hint == "":
		if not recipes.is_empty():
			rid = str(recipes[0].get("recipe_id", recipes[0].get("id", "")))
	else:
		var hint_gid := str(Catalog.get_good_by_internal_name(hint).get("id", ""))
		for r in recipes:
			for inp in r.get("inputs", []):
				if str(inp.get("good_id", "")) == hint_gid:
					rid = str(r.get("recipe_id", r.get("id", "")))
					break
			if rid != "":
				break
	if rid == "":
		return {"enabled": false, "building_id": bid, "recipe_id": "", "reason": "This power source isn't available yet"}
	# Terrain rule: offshore-only on sea/deep_sea, land-only otherwise.
	if not Catalog.is_building_allowed_on_tile_type(bid, str(_tile_data.get("type", ""))):
		var sea := str(_tile_data.get("type", "")) in ["sea", "deep_sea"]
		return {"enabled": false, "building_id": bid, "recipe_id": rid,
			"reason": "Can't build at sea" if sea else "Offshore only — needs a sea tile"}
	# Land / money checks (mirrors world_map._space_check_for_build): physical room
	# counts every building; the owned-land gate only the player's estate.
	var footprint := maxf(0.0, float(bd.get("tile_size_used", 1)))
	var projected := MatchState.get_tile_space_used(tile_id) + footprint
	var player_used := MatchState.get_tile_player_space_used(tile_id)
	var owned := MatchState.get_tile_land_owned(tile_id)
	if projected > float(MatchState.MAX_TILE_LAND) or player_used + footprint > float(owned):
		var free := maxi(0, owned - int(round(player_used)))
		return {"enabled": false, "building_id": bid, "recipe_id": rid, "reason": "Not enough land on this tile — needs %d, %d free" % [int(round(footprint)), free]}
	var mult := 1.5 if projected > 100.0 else 1.0
	var cost := float(bd.get("base_price", 0.0)) * mult
	if cost > MatchState.money:
		return {"enabled": false, "building_id": bid, "recipe_id": rid, "reason": "Not enough money — need £%.0f, you have £%.0f" % [cost, MatchState.money]}
	return {"enabled": true, "building_id": bid, "recipe_id": rid, "reason": ""}

# ─────────────────────────────────────────────────────────────────────────────
# BUILDINGS & LAND
# ─────────────────────────────────────────────────────────────────────────────
static func buildings_land_summary(tile_id: String, tile_data: Dictionary) -> Dictionary:
	var power := power_summary(tile_id)
	var power_deficit: bool = int(power.get("net", 0)) < 0
	var rows: Array = []
	var built_size := 0.0
	var infra_size := 0.0
	var npc_size := 0.0
	var stalled := 0
	var problems := 0
	for building in MatchState.get_buildings_on_tile(tile_id):
		var bd: Dictionary = Catalog.get_building(building.get("building_id", ""))
		var is_infra := str(bd.get("category", "")) == "infrastructure"
		var size := maxf(0.0, float(bd.get("tile_size_used", 1)))
		# NPC buildings sit on their own land — kept out of the player's built/used
		# figures so the land readouts track what the player actually owns.
		if not MatchState.is_player_owned(building):
			npc_size += size
		elif is_infra:
			infra_size += size
		else:
			built_size += size
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		var ran: bool = Production.last_turn_run.get(str(building.get("instance_id", "")), true)
		var consumes_power := int(recipe.get("energy_req", 0)) > 0
		var status := "ok"
		if not is_infra and not recipe.is_empty():
			if power_deficit and consumes_power and not ran:
				status = "problem"
				problems += 1
			elif not ran:
				status = "warn"
				stalled += 1
		var instance_id := str(building.get("instance_id", ""))
		rows.append({
			"instance_id": instance_id,
			"building_id": str(building.get("building_id", "")),
			"recipe_id": str(building.get("recipe_id", "")),
			"name": BuildingNaming.label_for_tile(tile_id, instance_id, str(building.get("building_id", "")), str(building.get("recipe_id", ""))),
			"subtitle": _building_subtitle(building, bd, recipe),
			"status": status,
			"land": size,
			"is_infra": is_infra,
			"production_cost": _production_cost_text(instance_id, recipe),
			"transport_cost": _inbound_transport(instance_id),
			"activity": _activity_for(instance_id, tile_id, recipe, is_infra),
			"power_status": _power_status_for(tile_id, recipe, is_infra, int(power.get("produced", 0)), int(power.get("consumed", 0))),
			"inputs_status": _inputs_status_for(instance_id, tile_id, recipe, is_infra),
			"duration_status": _transport_duration_status_for(instance_id, tile_id, recipe, is_infra),
			"transport_cost_status": _transport_cost_status_for(instance_id, tile_id, recipe, is_infra),
			"produce_cost_status": _produce_cost_status_for(instance_id, is_infra),
			"route_label": _output_route_label(instance_id, tile_id, recipe, is_infra),
		})
	var owned := MatchState.get_tile_land_owned(tile_id)
	var max_land := int(maxf(1.0, float(_tile_max_capacity(tile_data)) - npc_size))
	var total_used := built_size + infra_size
	var tile_status := "ok"
	if problems > 0 or total_used > float(owned):
		tile_status = "problem" if problems > 0 else "warn"
	elif stalled > 0:
		tile_status = "warn"
	return {
		"count": rows.size(),
		"buildings": rows,
		"built_size": built_size,
		"infra_size": infra_size,
		"npc_size": npc_size,
		"used_size": total_used,
		"owned": owned,
		"max": max_land,
		"stalled": stalled,
		"problems": problems,
		"status": tile_status,
	}

# ─────────────────────────────────────────────────────────────────────────────
# LAND OWNERSHIP CHART (vertical, per-building chunks)
# ─────────────────────────────────────────────────────────────────────────────
const CAT_INFRA := Color("#8FA3AE")        # light blue-grey
const CAT_MANUFACTURING := Color("#E08A3C")  # orange
const CAT_MINES := Color("#141414")        # black
const CAT_POWER := Color("#E3C84A")        # yellow
const CAT_REFINERY := Color("#8E5BC0")     # purple
const CAT_ELECTRO := Color("#A6E22E")      # lime green
const CAT_FARM := Color("#7FC97F")         # medium-light green
const CAT_FOREST := Color("#2E7D32")       # forest green
const CAT_WATER := Color("#3A7BD5")        # medium blue
const CAT_METALLURGY := Color("#4A7A9B")   # steel blue
const CAT_RUINS := Color("#7A5230")        # brown
const CAT_DEFAULT := Color("#6B7682")

static func land_chart_data(tile_id: String, tile_data: Dictionary) -> Dictionary:
	var other_segments: Array = []   # not-for-sale (other player) → bottom
	var player_segments: Array = []
	var bought_segments: Array = []  # ex-NPC purchases → top of the pile
	var other_footprint := 0.0
	var built := 0.0   # player-owned building footprint
	for building in MatchState.get_buildings_on_tile(tile_id):
		var bd: Dictionary = Catalog.get_building(building.get("building_id", ""))
		var size := footprint_of(building, bd)
		if size <= 0.0:
			continue
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		var is_ruins := _is_ruins(bd)
		var is_other := str(building.get("owner", MatchState.LOCAL_PLAYER)) != MatchState.LOCAL_PLAYER
		var iid := str(building.get("instance_id", ""))
		var stalled := not is_other and not recipe.is_empty() and not Production.last_turn_run.has(iid)
		var seg := {
			"size": size, "color": _category_color(bd), "is_other": is_other,
			"is_ruins": is_ruins, "is_construction": false, "instance_id": iid,
			"name": _building_full_name(bd, recipe), "value": int(round(size)),
			"icon": _building_icon_tex(bd), "stalled": stalled,
			"tooltip": BuildingNaming.label_for_tile(tile_id, iid, str(building.get("building_id", "")), str(building.get("recipe_id", ""))),
		}
		if is_other:
			other_footprint += size
			other_segments.append(seg)
		elif bool(building.get("acquired_from_npc", false)):
			built += size
			bought_segments.append(seg)
		else:
			built += size
			player_segments.append(seg)
	# Under-construction projects (navy hatch).
	for project in Construction.projects_on_tile(tile_id):
		var bd: Dictionary = Catalog.get_building(project.get("building_id", ""))
		var recipe: Dictionary = Catalog.get_recipe(project.get("recipe_id", ""))
		var size := maxf(0.0, float(project.get("reserved_space", bd.get("tile_size_used", 1))))
		if size <= 0.0:
			continue
		built += size
		player_segments.append({
			"size": size, "color": _category_color(bd), "is_other": false,
			"is_ruins": false, "is_construction": true, "instance_id": str(project.get("instance_id", "")),
			"name": _building_full_name(bd, recipe), "value": int(round(size)),
			"icon": _building_icon_tex(bd), "stalled": false,
			"tooltip": BuildingNaming.label_for_tile(tile_id, str(project.get("instance_id", "")), str(project.get("building_id", "")), str(project.get("recipe_id", ""))),
		})

	# Room an IN-PROGRESS upgrade has already reserved on this tile. The gate counts it and
	# so does land_totals (the BUILT caption) — but the BAR did not, so it drew empty space
	# that was already spoken for. A player looking at a tile with a big gap under the cap
	# line was told there was room, and then refused (owner 2026-08-23).
	var reserved := MatchState.reserved_upgrade_space_on_tile(tile_id)
	if reserved > 0.0:
		built += reserved
		player_segments.append({
			"size": reserved, "color": DS.PALETTE["ACCENT_DIM"], "is_other": false,
			"is_ruins": false, "is_construction": true, "instance_id": "",
			"name": "Upgrade in progress", "value": int(round(reserved)),
			"icon": null, "stalled": false,
			"tooltip": "Reserved by an upgrade in progress on this tile",
		})
	var owned := MatchState.get_tile_land_owned(tile_id)
	var type_cap := _tile_max_capacity(tile_data)
	# One axis for both chart modes: the terrain-adjusted cap the game actually
	# enforces. Land under not-for-sale (other-player) buildings can't be purchased.
	var axis_max := float(type_cap)
	var max_possible := int(maxf(1.0, axis_max - other_footprint))
	return {
		"segments": other_segments + player_segments + bought_segments,
		"owned": owned,
		"max_possible": max_possible,
		"axis_max": axis_max,
		"built": int(round(built)),
		"type_cap": type_cap,
		"npc_footprint": int(round(other_footprint)),
	}

# Shared land figures used in BOTH the tile-overview chips and the land rail:
# built (player footprint), buyable (max − owned), max (type cap − NPC land).
static func land_totals(tile_id: String, tile_data: Dictionary) -> Dictionary:
	var built := 0.0
	var npc := 0.0
	for building in MatchState.get_buildings_on_tile(tile_id):
		var bd: Dictionary = Catalog.get_building(building.get("building_id", ""))
		var size := footprint_of(building, bd)
		if str(building.get("owner", MatchState.LOCAL_PLAYER)) != MatchState.LOCAL_PLAYER:
			npc += size
		else:
			built += size
	for project in Construction.projects_on_tile(tile_id):
		built += maxf(0.0, float(project.get("reserved_space", 1)))
	# In-progress upgrades have already reserved the room they are growing into — the gate
	# counts it, so the readout must too or the two disagree while an upgrade is running.
	built += MatchState.reserved_upgrade_space_on_tile(tile_id)
	var max_cap := int(maxf(1.0, float(_tile_max_capacity(tile_data)) - npc))
	var owned := MatchState.get_tile_land_owned(tile_id)
	var buyable := maxi(0, max_cap - owned)
	# FREE is the figure that decides whether anything can go up, and it was the one the
	# readout made the player derive: a tile showing "BUILT 114 | BUYABLE 0 | MAX 122" reads
	# as having room, when it has 8 (owner 2026-08-23). Two gates bound it — the land you own
	# and the tile's physical space, which the NPC buildings are already sitting in — so the
	# smaller of the two is the honest answer.
	var free := maxi(0, mini(owned, max_cap) - int(round(built)))
	return {"built": int(round(built)), "buyable": buyable, "max": max_cap, "free": free}

static func _building_icon_tex(bd: Dictionary):
	var building_id := str(bd.get("id", ""))
	var internal := str(bd.get("internal_name", ""))
	var paths: Array[String] = []
	if building_id != "" and internal != "":
		paths.append("res://assets/icons/buildings/%s_%s.png" % [building_id, internal])
	if building_id != "":
		paths.append("res://assets/icons/buildings/%s.png" % building_id)
	if internal != "":
		paths.append("res://assets/icons/buildings/%s.png" % internal)
	for p in paths:
		if ResourceLoader.exists(p):
			return load(p)
	return null

static func _is_ruins(bd: Dictionary) -> bool:
	return str(bd.get("id", "")) == "b_031" or str(bd.get("internal_name", "")).to_lower() == "ruins"

## Public: the size-chart category colour for a catalog building dict. Reused by
## the polygon building renderer so footprints match the tile size chart.
static func category_color(bd: Dictionary) -> Color:
	return _category_color(bd)

## Public: a stable category KEY for a catalog building dict, mirroring the colour
## priority above. The polygon layout uses it to cluster same-type buildings.
static func category_key(bd: Dictionary) -> String:
	if _is_ruins(bd):
		return "ruins"
	var types: Array = bd.get("building_type", [])
	var internal := str(bd.get("internal_name", "")).to_lower()
	for t in ["infrastructure", "extraction", "metallurgy", "electrochemistry", "refinery", "manufacturing", "water", "power"]:
		if types.has(t):
			return t
	if types.has("farm_forests"):
		return "forest" if internal.contains("forest") else "farm"
	return str(bd.get("category", "default"))

static func _category_color(bd: Dictionary) -> Color:
	if _is_ruins(bd):
		return CAT_RUINS
	var types: Array = bd.get("building_type", [])
	var internal := str(bd.get("internal_name", "")).to_lower()
	if types.has("infrastructure"):
		return CAT_INFRA
	if types.has("extraction"):
		return CAT_MINES
	if types.has("metallurgy"):
		return CAT_METALLURGY
	if types.has("electrochemistry"):
		return CAT_ELECTRO
	if types.has("refinery"):
		return CAT_REFINERY
	if types.has("manufacturing"):
		return CAT_MANUFACTURING
	if types.has("water"):
		return CAT_WATER
	if types.has("power"):
		return CAT_POWER
	if types.has("farm_forests"):
		return CAT_FOREST if internal.contains("forest") else CAT_FARM
	# Fall back to the building's broad category.
	match str(bd.get("category", "")):
		"power": return CAT_POWER
		"infrastructure": return CAT_INFRA
		_: return CAT_DEFAULT

# Max tile space capacity for a tile, by terrain. The table itself lives in MatchState,
# because the BUILD GATE reads it — this used to be a private copy here expressed as bonuses
# on a base of 200, which the clamp to MAX_TILE_LAND then erased for every terrain but
# mountain, and which nothing outside the panel ever consulted.
const BASE_TILE_CAPACITY := 200
static func _tile_max_capacity(tile_data: Dictionary) -> int:
	var tile_id := str(tile_data.get("id", ""))
	if tile_id != "":
		return MatchState.max_tile_land(tile_id)
	# No id (a preview row): fall back to the terrain string the row carries.
	var terrain := str(tile_data.get("type", "")).strip_edges().to_lower()
	return clampi(int(MatchState.TILE_LAND_BY_TERRAIN.get(terrain, MatchState.MAX_TILE_LAND)),
		1, MatchState.MAX_TILE_LAND)

## Public wrapper so panels can hand the terrain-adjusted cap to MatchState land calls.
static func tile_max_capacity(tile_data: Dictionary) -> int:
	return _tile_max_capacity(tile_data)

# "20 land · → market, 3 turns" — footprint + where the primary output goes and
# how long it takes to get there.
static func _output_route_label(instance_id: String, tile_id: String, recipe: Dictionary, is_infra: bool) -> String:
	if is_infra:
		return ""
	var good_id := ""
	for output in _recipe_outputs(recipe):
		good_id = _output_good_id(output)
		if good_id != "":
			break
	if good_id == "":
		return ""
	if Catalog.get_internal_name(good_id) == "power":
		return "→ grid"
	var label := ""
	var dest_tile := ""
	if MatchState.is_output_market(instance_id, good_id):
		label = "market"
		dest_tile = TransportService.nearest_port_tile(tile_id)
	else:
		var explicit := MatchState.get_output_stockpile_destination(instance_id, good_id)
		if explicit == MatchState.MARKET_DESTINATION:
			label = "market"
			dest_tile = TransportService.nearest_port_tile(tile_id)
		elif explicit != "":
			label = Catalog.tile_label(explicit)
			dest_tile = explicit
		else:
			match MatchState.sell_mode:
				MatchState.SellMode.SELL_ALL:
					label = "market"
					dest_tile = TransportService.nearest_port_tile(tile_id)
				_:
					label = "this tile"
					dest_tile = tile_id
	var turns := 0
	if dest_tile != "" and dest_tile != tile_id:
		var r: Dictionary = TransportService.route(tile_id, dest_tile, good_id)
		turns = int(r.get("turns", 0))
	if turns > 0:
		return "→ %s, %d turn%s" % [label, turns, "" if turns == 1 else "s"]
	return "→ %s" % label

# Full, descriptive building name for lists: the recipe's name when it has one
# (e.g. "Coal Mining" instead of the generic "Mine"), else the building name.
static func _building_full_name(bd: Dictionary, recipe: Dictionary) -> String:
	var rname := str(recipe.get("display_name", "")).strip_edges()
	if rname != "":
		return rname
	return str(bd.get("display_name", bd.get("id", "")))

# RAG for OUTPUT transport duration — mirrors building_detail_panel: grey until
# the building has run a turn; green if no off-tile destination; amber if the
# shipment takes more than one turn.
# A mined-out (non-water) deposit means the building can't run — used to keep
# these RAG strings in step with building_detail_panel._recipe_deposit_exhausted.
static func deposit_exhausted_for(tile_id: String, recipe: Dictionary) -> bool:
	if tile_id == "":
		return false
	for req in recipe.get("requirements", []):
		if str(req.get("type", "")) != "deposit":
			continue
		var token := str(req.get("value", ""))
		if token == "" or token == "water":
			continue
		if MatchState.deposit_remaining_for(tile_id, token) == 0:
			return true
	return false

static func _transport_duration_status_for(instance_id: String, tile_id: String, recipe: Dictionary, is_infra: bool) -> String:
	if is_infra:
		return "muted"
	if not Production.last_turn_run.has(instance_id) or deposit_exhausted_for(tile_id, recipe):
		return "muted"
	var route := _output_route(instance_id, tile_id, recipe)
	if route.is_empty():
		return "ok"
	return "warn" if int(route.get("turns", 0)) > 1 else "ok"

# RAG for OUTPUT transport cost — mirrors building_detail_panel: grey until run;
# green if no shipping cost; amber if paying to ship.
static func _transport_cost_status_for(instance_id: String, tile_id: String, recipe: Dictionary, is_infra: bool) -> String:
	if is_infra:
		return "muted"
	if not Production.last_turn_run.has(instance_id) or deposit_exhausted_for(tile_id, recipe):
		return "muted"
	var route := _output_route(instance_id, tile_id, recipe)
	if route.is_empty():
		return "ok"
	return "warn" if float(route.get("cost", 0.0)) > 0.0 else "ok"

static func _output_route(instance_id: String, tile_id: String, recipe: Dictionary) -> Dictionary:
	var good_id := ""
	for output in _recipe_outputs(recipe):
		good_id = _output_good_id(output)
		if good_id != "":
			break
	if good_id == "":
		return {}
	var dest := MatchState.get_output_stockpile_destination(instance_id, good_id)
	if dest == "":
		return {}
	var r: Dictionary = TransportService.route(tile_id, dest, good_id)
	var turns := int(r.get("turns", 0))
	var qty := 0
	for output in _recipe_outputs(recipe):
		if _output_good_id(output) == good_id:
			qty = int(output.get("qty", 0))
			break
	return {"turns": turns, "cost": TransportService.transport_cost_for_route(good_id, qty, r)}

# RAG for cost to produce — mirrors building_detail_panel._update_cost_label:
# grey if unknown; green if < 90% of base price, amber 90–110%, red above.
static func _produce_cost_status_for(instance_id: String, is_infra: bool) -> String:
	if is_infra:
		return "muted"
	# Exhausted deposit → not producing → no cost to compute (match the BDP).
	var b: Dictionary = MatchState.get_building(instance_id)
	if deposit_exhausted_for(str(b.get("tile_id", "")), Catalog.get_recipe(str(b.get("recipe_id", "")))):
		return "muted"
	var uc := CostSolver.get_building_unit_cost(instance_id)
	if uc < 0.0:
		return "muted"
	var bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(instance_id, {})
	var output_good_id := str(bd.get("output_good_id", ""))
	var base := Catalog.get_base_price(output_good_id) if output_good_id != "" else 0.0
	if base <= 0.0:
		return "muted"
	var pct := uc / base * 100.0
	if pct < 90.0:
		return "ok"
	if pct <= 110.0:
		return "warn"
	return "problem"

# Per-output production cost, pipe-separated (e.g. "£1.20 | £0.80"), or "—".
static func _production_cost_text(instance_id: String, recipe: Dictionary) -> String:
	var parts: Array[String] = []
	for output in _recipe_outputs(recipe):
		var gid := _output_good_id(output)
		if gid == "":
			continue
		var cost := CostSolver.get_building_output_cost(instance_id, gid)
		parts.append("£%.2f" % cost if cost >= 0.0 else "—")
	return " | ".join(parts) if not parts.is_empty() else "—"

# Transport cost paid to bring this building's inputs in last turn, or -1.
static func _inbound_transport(instance_id: String) -> float:
	var bd: Dictionary = CostSolver.last_result.get("per_building", {}).get(instance_id, {})
	return float(bd.get("inbound_transport", -1.0))

# Coarse activity for the TVP status pill: "running" if it produced last turn,
# "stalled" if it tried and failed (starved / mined-out deposit / player-paused),
# "starting" if there's no run record yet (just built — first pass pending).
# Infrastructure gets "" (no pill).
static func _activity_for(instance_id: String, tile_id: String, recipe: Dictionary, is_infra: bool) -> String:
	if is_infra or recipe.is_empty():
		return ""
	if MatchState.paused_buildings.has(instance_id):
		return "stalled"
	if Production.last_turn_run.has(instance_id):
		return "running"
	if Production.missing_by_building.has(instance_id) or deposit_exhausted_for(tile_id, recipe):
		return "stalled"
	return "starting"

# RAG for power — mirrors building_detail_panel._power_status_color: grey if no
# power need; RED only when the tile is NOT connected to the grid (no cables);
# green when self-supplied on-tile, amber when drawn from the grid.
static func _power_status_for(tile_id: String, recipe: Dictionary, is_infra: bool, produced: int, consumed: int) -> String:
	if is_infra:
		return "muted"
	var energy_req := int(recipe.get("energy_req", 0))
	if energy_req <= 0 and not _recipe_produces_power(recipe):
		return "muted"
	if not Power.is_supplied(tile_id, energy_req):
		return "problem"  # not connected to the grid
	# Connected: self-supplied (own production covers demand) → green, else grid → amber.
	return "ok" if (produced > 0 and produced >= consumed) else "warn"

static func _recipe_produces_power(recipe: Dictionary) -> bool:
	if str(recipe.get("output_name", "")) == "power":
		return true
	for output in _recipe_outputs(recipe):
		if str(output.get("internal_name", "")) == "power" or Catalog.get_internal_name(_output_good_id(output)) == "power":
			return true
	return false

# RAG for inputs — mirrors building_detail_panel._input_status_color: green if it
# ran last turn; red if flagged missing inputs or the tile lacks enough of any
# input; amber if present-but-idle; grey for infrastructure; green if no inputs.
static func _inputs_status_for(instance_id: String, tile_id: String, recipe: Dictionary, is_infra: bool) -> String:
	if is_infra:
		return "muted"
	if deposit_exhausted_for(tile_id, recipe):
		return "problem"  # mined-out deposit — same as the BDP input dot
	if instance_id != "" and Production.last_turn_run.has(instance_id):
		return "ok"
	if instance_id != "" and Production.missing_by_building.has(instance_id):
		return "problem"
	var inputs: Array = recipe.get("inputs", [])
	if inputs.is_empty():
		return "ok"
	for input in inputs:
		var gid := str(input.get("good_id", ""))
		if gid == "":
			gid = str(Catalog.get_good_by_internal_name(str(input.get("internal_name", ""))).get("id", ""))
		if gid != "" and Stockpile.get_at_tile(tile_id, gid) < int(input.get("qty", 0)):
			return "problem"
	return "warn"

# ─────────────────────────────────────────────────────────────────────────────
# PRODUCTION & GOODS
# ─────────────────────────────────────────────────────────────────────────────
static func production_summary(tile_id: String) -> Dictionary:
	var by_good: Dictionary = {}
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		if recipe.is_empty():
			continue
		var instance_id := str(building.get("instance_id", ""))
		var ran: bool = Production.last_turn_run.get(instance_id, false)
		for output in _recipe_outputs(recipe):
			var good_id := _output_good_id(output)
			var qty := int(output.get("qty", 0))
			if good_id == "" or qty <= 0:
				continue
			var rec: Dictionary = by_good.get(good_id, {
				"good_id": good_id,
				"display_name": Catalog.get_display_name(good_id),
				"qty": 0,
				"value": 0.0,
				"cost_weight": 0.0,
				"cost_qty": 0.0,
				"ran": false,
			})
			rec.qty = int(rec.qty) + qty
			rec.value = float(rec.value) + float(qty) * MarketState.get_price(good_id)
			rec.ran = bool(rec.ran) or ran
			var unit_cost := _output_unit_cost(instance_id, good_id)
			if unit_cost >= 0.0:
				rec.cost_weight = float(rec.cost_weight) + unit_cost * float(qty)
				rec.cost_qty = float(rec.cost_qty) + float(qty)
			rec["destination"] = _destination_text(building, good_id)
			by_good[good_id] = rec
	var rows: Array = []
	var net_value := 0.0
	for good_id in by_good:
		var rec: Dictionary = by_good[good_id]
		var cq := float(rec.cost_qty)
		rec.unit_cost = (float(rec.cost_weight) / cq) if cq > 0.0 else -1.0
		net_value += float(rec.value) - float(rec.cost_weight)
		rows.append(rec)
	rows.sort_custom(func(a, b): return float(a.value) > float(b.value))
	var status := "ok"
	if rows.is_empty():
		status = "muted"
	elif net_value < 0.0:
		status = "problem"
	elif is_zero_approx(net_value):
		status = "warn"
	return {
		"rows": rows,
		"outputs": rows.size(),
		"net_value": net_value,
		"status": status,
	}

# Realised market sales shipped from this tile this turn (units + £).
static func sales_summary(tile_id: String) -> Dictionary:
	var s := MatchState.get_tile_sales(tile_id)
	return {"units": int(s.get("units", 0)), "revenue": float(s.get("revenue", 0.0))}

# ─────────────────────────────────────────────────────────────────────────────
# STOCKPILE
# ─────────────────────────────────────────────────────────────────────────────
static func stockpile_summary(tile_id: String) -> Dictionary:
	var used := Stockpile.get_used_capacity(tile_id)
	var capacity := Stockpile.get_capacity(tile_id)
	var goods := Stockpile.get_top_goods(tile_id, -1)  # all goods, qty desc
	var pct := (float(used) / float(capacity)) if capacity > 0 else 0.0
	var is_full := Stockpile.get_free_capacity(tile_id) <= 0 and used > 0
	var status := "ok"
	if is_full:
		status = "problem"
	elif pct >= 0.9:
		status = "warn"
	elif used == 0:
		status = "muted"
	var enriched: Array = []
	for g in goods:
		enriched.append({
			"good_id": str(g.get("good_id", "")),
			"qty": int(g.get("qty", 0)),
			"display_name": Catalog.get_display_name(str(g.get("good_id", ""))),
		})
	return {
		"used": used,
		"capacity": capacity,
		"pct": pct,
		"is_full": is_full,
		"goods": enriched,
		"status": status,
	}

# ─────────────────────────────────────────────────────────────────────────────
# DEPOSITS (shown under Production)
# ─────────────────────────────────────────────────────────────────────────────
static func deposits_summary(tile_id: String, tile_data: Dictionary) -> Array:
	var rows: Array = []
	for deposit in tile_data.get("deposits", []):
		var token := ""           # bare deposit name, used for recipe-requirement matching
		var qty := -1
		if deposit is Dictionary:
			token = str(deposit.get("internal_name", deposit.get("good", deposit.get("good_id", ""))))
			qty = int(deposit.get("amount", deposit.get("qty", deposit.get("remaining", -1))))
		else:
			token = _deposit_token(str(deposit))
			qty = _deposit_qty(str(deposit))
		if token == "":
			continue
		var good_internal := _deposit_good_internal(token)
		var good: Dictionary = Catalog.get_good_by_internal_name(good_internal)
		if good.is_empty():
			good = Catalog.get_good(good_internal)
		var good_id := str(good.get("id", good_internal))
		var instance_id := _building_extracting_good(tile_id, good_id, good_internal)
		rows.append({
			"good_id": good_id,
			"deposit_token": token,
			"internal_name": good_internal,
			"display_name": str(good.get("display_name", token)).capitalize(),
			"qty": qty,
			"has_building": instance_id != "",
			"instance_id": instance_id,
		})
	return rows

## Deposits gated by the tile's survey status, for the Tile View Panel.
## Returns {status, rows}. Each row adds to a deposits_summary row:
##   - is_water:   water (Pure Water) is permanent and always shown.
##   - size_qty:   -1 unknown/water, -2 "size ?" (partial), else the surveyed amount.
##   - chip_label: ready-to-show label, e.g. "Coal (480)", "Coal (size ?)", "Pure Water".
## Unsurveyed: only water is returned; the panel shows a "Deposits Unknown" line.
## Depleted (mined-out) non-water deposits are dropped entirely.
static func survey_gated_deposits(tile_id: String, tile_data: Dictionary) -> Dictionary:
	var status := MatchState.survey_status(tile_id, str(tile_data.get("type", "")))
	var rows: Array = []
	for r in deposits_summary(tile_id, tile_data):
		var token := str(r.get("deposit_token", ""))
		var is_water := token == "water"
		var remaining := MatchState.deposit_remaining_for(tile_id, token)
		if not is_water and remaining == 0:
			continue  # mined out — the deposit is gone
		var row: Dictionary = (r as Dictionary).duplicate()
		row["is_water"] = is_water
		if is_water:
			row["display_name"] = "Pure Water"
			row["size_qty"] = -1
			row["chip_label"] = "Pure Water"
		elif status == "unsurveyed":
			# A deposit individually revealed (by building a mine on it) shows
			# its existence with an unknown size; the rest stay hidden.
			if not MatchState.is_deposit_revealed(tile_id, token):
				continue
			row["size_qty"] = -2
			row["chip_label"] = "%s (size ?)" % str(r.get("display_name", token))
		elif status == "partial":
			row["size_qty"] = -2
			row["chip_label"] = "%s (size ?)" % str(r.get("display_name", token))
		else:  # surveyed: show the (depleting) amount when one is tracked
			var n := remaining if remaining > 0 else int(r.get("qty", -1))
			row["size_qty"] = n
			row["chip_label"] = ("%s (%d)" % [str(r.get("display_name", token)), n]) if n >= 0 else str(r.get("display_name", token))
		rows.append(row)
	return {"status": status, "rows": rows}

## Bare deposit name: strips any "(1000)" amount and surrounding whitespace.
static func _deposit_token(raw: String) -> String:
	var name := raw
	var paren := name.find("(")
	if paren >= 0:
		name = name.substr(0, paren)
	return name.strip_edges().to_lower()

## Amount inside the brackets of e.g. "coal (1000)", or -1 if none.
static func _deposit_qty(raw: String) -> int:
	var open := raw.find("(")
	var close := raw.find(")")
	if open >= 0 and close > open:
		var inner := raw.substr(open + 1, close - open - 1).strip_edges()
		var digits := ""
		for ch in inner:
			if ch >= "0" and ch <= "9":
				digits += ch
		if digits != "":
			return int(digits)
	return -1

## Maps a deposit token to a goods catalog internal name. The deposits CSV uses
## "water" while the goods catalog uses "pure_water"; map it here rather than
## renaming the CSV (recipe r_011 and tile_properties.csv both rely on "water").
static func _deposit_good_internal(token: String) -> String:
	var t := token.strip_edges().to_lower()
	if t == "water":
		return "pure_water"
	return t

## (building, recipe) pairs whose recipe requires this deposit token.
static func deposit_build_options(deposit_token: String) -> Array:
	var tokens := {}
	var t := deposit_token.strip_edges().to_lower()
	tokens[t] = true
	tokens[t.replace(" ", "_")] = true
	tokens[t.replace("_", " ")] = true
	var opts: Array = []
	for recipe in Catalog.all_recipes():
		var rec_req := str(recipe.get("tech_unlock_req", ""))
		if rec_req != "" and not MatchState.is_unlocked(rec_req):
			continue
		var bid := str(recipe.get("building_id", ""))
		if bid == "":
			continue
		var building := Catalog.get_building(bid)
		if building.is_empty():
			continue
		var bld_req := str(building.get("required_research", ""))
		if bld_req != "" and not MatchState.is_unlocked(bld_req):
			continue
		for req in recipe.get("requirements", []):
			if str(req.get("type", "")).to_lower() != "deposit":
				continue
			if tokens.has(str(req.get("value", "")).strip_edges().to_lower()):
				opts.append({
					"building_id": bid,
					"recipe_id": str(recipe.get("recipe_id", recipe.get("id", ""))),
					"building_name": str(building.get("display_name", bid)),
					"recipe_name": str(recipe.get("display_name", "")),
				})
				break
	return opts

static func _building_extracting_good(tile_id: String, good_id: String, internal: String) -> String:
	for building in MatchState.get_buildings_on_tile(tile_id):
		var recipe: Dictionary = Catalog.get_recipe(building.get("recipe_id", ""))
		for output in _recipe_outputs(recipe):
			if _output_good_id(output) == good_id or _output_internal(output) == internal:
				return str(building.get("instance_id", ""))
	return ""

# ─────────────────────────────────────────────────────────────────────────────
# INFRASTRUCTURE (its own section under Buildings & Land)
# ─────────────────────────────────────────────────────────────────────────────
const INFRA_SLOTS := [
	{"key": "cables", "label": "Cables"},
	{"key": "roads", "label": "Roads"},
	{"key": "pipes", "label": "Pipework"},
	{"key": "hvdc", "label": "HVDC"},
	{"key": "rails", "label": "Rail"},
	{"key": "reinf_pipes", "label": "Reinf. pipes"},
]
# Goods-transport slots that carry a throughput cap (slot key -> routing mode). Cables
# are power, not goods, so they stay uncapped here.
const CAPPED_MODES := {"roads": "roads", "rails": "rail", "pipes": "pipes", "reinf_pipes": "reinf_pipes"}

static func infrastructure_summary(tile_id: String, tile_data: Dictionary) -> Array:
	# 1) Resolve each slot's state + building data.
	var slots: Array = []
	var existing_capped: Array = []
	for def in INFRA_SLOTS:
		var key := str(def.key)
		var building_data := _infra_building_data_for_key(key)
		var instance := _infra_instance_for_tile(tile_id, tile_data, key, building_data)
		var state := "exists" if not instance.is_empty() else ("add" if not building_data.is_empty() else "unavailable")
		slots.append({
			"key": key,
			"label": str(def.label),
			"state": state,
			"internal_name": str(building_data.get("internal_name", key)),
			"instance": instance,
			"building_data": building_data,
		})
		if state == "exists" and CAPPED_MODES.has(key):
			existing_capped.append(key)

	# 2) Attach real transit vs capacity to each slot. Capacity is the live cap —
	# base mode cap × infra level (L1×1 / L2×2 / L3×3.5) × throughput research — and
	# transit is the actual per-tile-link flow this turn.
	for slot in slots:
		var key: String = slot.key
		var state: String = slot.state
		var capped: bool = CAPPED_MODES.has(key)
		slot["capped"] = capped
		slot["cap"] = 0
		if state != "exists":
			slot["transit"] = {"dial": "track", "tooltip": "Not built"}
			continue
		# Cables carry POWER, hard-capped per tile by cable level (produce + draw each).
		if key == "cables":
			var pcap := Power.tile_power_cap(tile_id)
			var produced := int(Power.tile_produced.get(tile_id, 0))
			var drawn := int(Power.tile_drawn.get(tile_id, 0))
			var worst := maxi(produced, drawn)
			slot["capped"] = pcap > 0
			slot["cap"] = pcap
			slot["transit"] = {
				"dial": "fill" if pcap > 0 else "full_green",
				"pct": (float(worst) / float(pcap)) if pcap > 0 else 0.0,
				"used": worst,
				"cap": pcap,
				"tooltip": "Power: produce %d / %d, draw %d / %d per turn" % [produced, pcap, drawn, pcap],
			}
			continue
		if not capped:
			slot["transit"] = {"dial": "full_green", "tooltip": "%s · no transit cap" % slot.label}
			continue
		var mode: String = CAPPED_MODES[key]
		var level := int(tile_data.get("infrastructure_levels", {}).get(key, 1))
		var cap := int(round(MatchState.tile_mode_capacity(mode, level)))
		var used := MatchState.tile_mode_flow(tile_id, mode)
		var pct := (float(used) / float(cap)) if cap > 0 else 0.0
		slot["cap"] = cap
		var tip := "%s: %d / %d per turn  (Level %d)" % [slot.label, used, cap, level]
		if cap > 0 and used > cap:
			var l1 := float(EconomyConfig.TRANSPORT_LINK_CAP_BY_MODE.get(mode, 0))
			var over := "+200% over cap" if float(used) > float(cap) + l1 else "+100% over cap"
			tip += "\nCongestion: %s transport cost" % over
		slot["transit"] = {
			"dial": "fill",
			"pct": pct,
			"used": used,
			"cap": cap,
			"tooltip": tip,
		}
	return slots

static func _through_units(tile_id: String) -> int:
	var total := 0
	for shipment in MatchState.pending_transport_shipments:
		var tiles: Array = shipment.get("tiles", [])
		if tiles.has(tile_id):
			total += int(shipment.get("qty", 0))
	return total

static func _normalise_infra(internal_name: String) -> String:
	match internal_name.strip_edges().to_lower():
		"railway", "railways", "rails", "rail": return "rails"
		"pipework", "pipeworks", "pipes": return "pipes"
		"reinf_pipes", "reinforced_pipes", "reinforced pipework": return "reinf_pipes"
		"hvdc", "high voltage cables": return "hvdc"
		_: return internal_name.strip_edges().to_lower()

static func _infra_building_data_for_key(key: String) -> Dictionary:
	var building_data := Catalog.get_building_by_internal_name(key)
	if not building_data.is_empty():
		return building_data
	for candidate in Catalog.all_buildings():
		if str(candidate.get("category", "")) != "infrastructure":
			continue
		if _normalise_infra(str(candidate.get("internal_name", ""))) == key:
			return candidate
	return {}

static func _infra_instance_for_tile(tile_id: String, tile_data: Dictionary, key: String, building_data: Dictionary) -> Dictionary:
	for building in MatchState.get_buildings_on_tile(tile_id):
		var bd: Dictionary = Catalog.get_building(building.get("building_id", ""))
		if str(bd.get("category", "")) != "infrastructure":
			continue
		if _normalise_infra(str(bd.get("internal_name", ""))) == key:
			return building
	for infra_name in tile_data.get("infrastructure_present", []):
		if _normalise_infra(str(infra_name)) == key:
			return {
				"instance_id": "tile_%s_%s" % [tile_id, key],
				"building_id": str(building_data.get("id", "")),
				"tile_id": tile_id,
				"owner": "tile_data",
				"level": int(tile_data.get("infrastructure_levels", {}).get(key, 1)),
			}
	return {}

# ─────────────────────────────────────────────────────────────────────────────
# Internal helpers
# ─────────────────────────────────────────────────────────────────────────────
static func _building_name(building: Dictionary) -> String:
	var bd: Dictionary = Catalog.get_building(building.get("building_id", ""))
	return str(bd.get("display_name", building.get("building_id", "")))

static func _building_subtitle(building: Dictionary, bd: Dictionary, recipe: Dictionary) -> String:
	if str(bd.get("category", "")) == "infrastructure":
		return "Infrastructure"
	# All outputs on one line, pipe-separated (multi-output buildings).
	var parts: Array[String] = []
	for output in _recipe_outputs(recipe):
		var gid := _output_good_id(output)
		if gid != "":
			parts.append("%d %s per turn" % [int(output.get("qty", 0)), Catalog.get_display_name(gid)])
	if not parts.is_empty():
		return " | ".join(parts)
	return str(bd.get("category", ""))

static func _recipe_outputs(recipe: Dictionary) -> Array:
	if recipe.has("outputs"):
		return recipe.get("outputs", [])
	var name := str(recipe.get("output_name", ""))
	var qty := int(recipe.get("output_qty", 0))
	if name == "" or qty <= 0:
		return []
	return [{"internal_name": name, "qty": qty}]

static func _output_internal(output: Dictionary) -> String:
	var internal := str(output.get("internal_name", ""))
	if internal != "":
		return internal
	var good: Dictionary = Catalog.get_good(str(output.get("good_id", "")))
	return str(good.get("internal_name", ""))

static func _output_good_id(output: Dictionary) -> String:
	var gid := str(output.get("good_id", ""))
	if gid != "":
		return gid
	var internal := str(output.get("internal_name", ""))
	if internal == "":
		return ""
	var good: Dictionary = Catalog.get_good_by_internal_name(internal)
	return str(good.get("id", ""))

static func _output_unit_cost(instance_id: String, good_id: String) -> float:
	var cost := CostSolver.get_building_output_cost(instance_id, good_id)
	if cost >= 0.0:
		return cost
	return CostSolver.get_building_unit_cost(instance_id)

static func _destination_text(building: Dictionary, good_id: String) -> String:
	if Catalog.get_internal_name(good_id) == "power":
		return "grid"
	var inst_id := str(building.get("instance_id", ""))
	if MatchState.is_output_market(inst_id, good_id):
		return "market"
	var explicit := MatchState.get_output_stockpile_destination(inst_id, good_id)
	if explicit != "":
		return explicit
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL:
			return "this tile"
		MatchState.SellMode.BUILDING_BY_BUILDING:
			return "by building"
		_:
			return "market"
