extends RefCounted
## The top bar's Power and Transport modules, judged once. Each status is {tone, name, detail}: the
## lamp lights from the tone and the hover readout shows the name and detail, so the two can never
## say different things. Tones are "ok", "warn", "bad" and "off" (nothing to judge), as Building
## Detail's checks use them. The figures come from the turn the engine last settled.

## A tile counts as nearly full at this share of its capacity: close enough that the next shipment is
## the one that gets refused.
const NEAR_FULL_FRACTION := 0.95


## Power across the company: MW made, MW bought from the grid, buildings the engine left without power,
## and buildings intermittency cut short.
static func power_stats() -> Dictionary:
	var s: Dictionary = Production.last_turn_summary
	var unpowered := 0
	for iid in Production.missing_by_building:
		var b: Dictionary = BuildingState.buildings.get(iid, {})
		if b.is_empty() or not BuildingState.is_player_owned(b):
			continue
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		if str(recipe.get("output_name", "")) == "power":
			continue   # a producer's "power" entry is the cable-cap marker, not starvation
		for m in (Production.missing_by_building[iid] as Array):
			if str(m.get("good_id", "")) == "power":
				unpowered += 1
				break
	return {
		"self_gen": int(s.get("power_supply", 0)),
		"grid_draw": int(s.get("grid_bought", 0)),
		"unpowered": unpowered,
		"derated": Production.intermittency_derated_count(),
	}


## The Power module's status. Red beats a blinking amber (intermittency cutting buildings short) beats a
## steady amber (buying from the grid) beats green. `blink` is true for the intermittency case.
static func power() -> Dictionary:
	var p := power_stats()
	var made := "%d MW made" % int(p.self_gen)
	var bought := "%d MW bought from the national grid" % int(p.grid_draw)
	var out := {"stats": p, "blink": false}
	if int(p.unpowered) > 0:
		out.merge({"tone": "bad", "name": "Buildings without power",
			"detail": "%s without power last turn. Build cables or generation on their tiles." % _count(int(p.unpowered), "building")})
	elif int(p.derated) > 0:
		out.merge({"tone": "warn", "name": "Intermittent supply", "blink": true,
			"detail": "%s ran short when the wind or sun dropped. %s." % [_count(int(p.derated), "building"), made]}, true)
	elif int(p.grid_draw) > 0:
		out.merge({"tone": "warn", "name": "Drawing from the grid", "detail": "%s. %s." % [made, bought]})
	elif int(p.self_gen) > 0:
		out.merge({"tone": "ok", "name": "Self sufficient", "detail": "%s. Nothing bought from the grid." % made})
	else:
		out.merge({"tone": "off", "name": "No power in use", "detail": "No building makes or draws power yet."})
	return out


## Transport across the company: units riding to market, links over capacity, tiles nearly full and
## tiles refusing goods, and shipments stuck with nowhere to unload.
static func transport_stats() -> Dictionary:
	var to_market := 0
	for s in TransportState.pending_transport_shipments:
		var ship: Dictionary = s
		if not bool(ship.get("is_sale", false)):
			continue
		for it in (ship.get("sale_record", {}) as Dictionary).get("items", []):
			to_market += int((it as Dictionary).get("qty", 0))
	var full := 0
	var rejecting := 0
	for tile_key in Stockpile.tiles_with_stock():
		var cap := float(Stockpile.get_capacity(tile_key))
		if cap <= 0.0:
			continue
		if float(Stockpile.get_used_capacity(tile_key)) / cap >= NEAR_FULL_FRACTION:
			full += 1
		if Stockpile.get_refused(tile_key) > 0:
			rejecting += 1
	return {"to_market": to_market, "over": TransportState.congested_links().size(), "full": full,
		"rejecting": rejecting, "stuck": TransportState.overflow_shipments.size()}


## The Transport module's three lamps, each owning one failure: storage (tiles refusing goods, or more
## than one nearly full), links (more than three over capacity) and freight (shipments stuck on arrival).
static func transport() -> Dictionary:
	var t := transport_stats()
	var storage: Dictionary
	if int(t.rejecting) > 0:
		storage = {"tone": "bad", "name": "Storage full",
			"detail": "%s refusing goods. %s at 95%% of storage or more." % [_count(int(t.rejecting), "tile"), _count(int(t.full), "tile")]}
	elif int(t.full) > 1:
		storage = {"tone": "bad", "name": "Storage nearly full", "detail": "%s at 95%% of storage or more." % _count(int(t.full), "tile")}
	else:
		storage = {"tone": "ok", "name": "Storage",
			"detail": ("%s at 95%% of storage or more." % _count(int(t.full), "tile")) if int(t.full) > 0 else "Every tile has room."}
	var links: Dictionary
	if int(t.over) > 3:
		links = {"tone": "bad", "name": "Links over capacity", "detail": "%s carrying more than they can." % _count(int(t.over), "link")}
	else:
		links = {"tone": "ok", "name": "Links",
			"detail": ("%s over capacity." % _count(int(t.over), "link")) if int(t.over) > 0 else "No link over capacity."}
	var freight: Dictionary
	if int(t.stuck) > 0:
		freight = {"tone": "bad", "name": "Freight stuck", "detail": "%s arrived with nowhere to unload." % _count(int(t.stuck), "shipment")}
	else:
		freight = {"tone": "ok", "name": "Freight",
			"detail": ("%s riding to market." % _count(int(t.to_market), "unit")) if int(t.to_market) > 0 else "Nothing riding to market."}
	return {"stats": t, "storage": storage, "links": links, "freight": freight}


## Whether a status lights its lamp.
static func lit(status: Dictionary) -> bool:
	return str(status.get("tone", "off")) in ["warn", "bad"]


static func _count(n: int, noun: String) -> String:
	return "%d %s%s" % [n, noun, "" if n == 1 else "s"]
