extends RefCounted
## The price of land. One rule set, read by every surface that buys or quotes land; nothing else multiplies by
## BuildingState.LAND_PATCH_COST.
##
##   S(tile)   = LAND_PATCH_COST x LAND_BAND_MULT[band]           the tile's starting price per patch
##   share     = 1 + LAND_RAMP_PER_BUILDING x n + a + e
##   per_patch = S x share, doubled for a stand-alone purchase
##   total     = AdvisorState.purchase_cost_after_advisor(per_patch x patches, {tile_id})
##
## n counts the player's own buildings on the tile, standing or under construction, except infrastructure and
## buildings flagged land_exempt (bought from another company, the starting estate, an older save's estate).
## a is LAND_ADJACENT_STANDALONE beside a tile bought stand-alone, else LAND_ADJACENT beside land the player
## bought, once per tile however many neighbours qualify. e is LAND_ECONOMY_STEP per latched doubling of global
## revenue, on urban bands only. Every rise is a share of S, so rises add and never compound.
##
## A stand-alone purchase is land bought without a build or an upgrade: the tile panel's Buy Land.
##
## Stateless: the state it reads lives in BuildingState (tile_land_priced, tile_land_standalone,
## land_economy_level) and CompanyRankings. Quotes are pure reads; tick_economy is the one per-turn write.

const MiddlemanLocations := preload("res://scripts/middleman_locations.gd")
const URBAN_BANDS := ["hub_city", "city", "town"]
const BAND_WORDS := {"hub_city": "Hub city", "city": "City", "town": "Town"}
const REST_WORDS := {"countryside": "Countryside", "mountain": "Mountain", "sea": "Sea"}


## The land price band of a tile: "hub_city", "city", "town" or "rest". Fixed for the match.
static func band(tile_id: String) -> String:
	return MiddlemanLocations.land_band(tile_id)

## The band's multiple of the base patch price.
static func band_mult(tile_id: String) -> float:
	return float(EconomyConfig.LAND_BAND_MULT.get(band(tile_id), EconomyConfig.LAND_BAND_MULT["rest"]))

## The tile's starting price per patch, S.
static func starting_price(tile_id: String) -> float:
	return BuildingState.LAND_PATCH_COST * band_mult(tile_id)

## The band in words, as Local Suppliers name the settlement: Hub city, City, Town, or the ground outside one.
static func band_label(tile_id: String) -> String:
	var b := band(tile_id)
	if BAND_WORDS.has(b):
		return str(BAND_WORDS[b])
	return str(REST_WORDS.get(MiddlemanLocations.settlement_class(tile_id), "Countryside"))

## Whether the building counts toward the tile's ramp.
static func counts(instance: Dictionary) -> bool:
	if not BuildingState.is_player_owned(instance) or bool(instance.get("land_exempt", false)):
		return false
	return _counts_type(str(instance.get("building_id", "")))

static func _counts_type(building_id: String) -> bool:
	return str(Catalog.get_building(building_id).get("category", "")) != "infrastructure"

## n(tile): the player's counted buildings on the tile, standing or under construction.
static func counted_buildings(tile_id: String) -> int:
	var n := 0
	for instance: Dictionary in BuildingState.get_buildings_on_tile(tile_id):
		if counts(instance):
			n += 1
	for project: Dictionary in Construction.construction_projects.values():
		if str(project.get("tile_id", "")) == tile_id and _counts_type(str(project.get("building_id", ""))):
			n += 1
	return n

## a(tile): the neighbour term, as a share of S.
static func adjacency_share(tile_id: String) -> float:
	var priced := false
	for neighbour: String in Catalog.tile_neighbours(tile_id):
		if BuildingState.tile_land_standalone.has(neighbour):
			return EconomyConfig.LAND_ADJACENT_STANDALONE
		if int(BuildingState.tile_land_priced.get(neighbour, 0)) > 0:
			priced = true
	return EconomyConfig.LAND_ADJACENT if priced else 0.0

## e(tile): the economy term, as a share of S. Urban bands only.
static func economy_share(tile_id: String) -> float:
	if not band(tile_id) in URBAN_BANDS:
		return 0.0
	return EconomyConfig.LAND_ECONOMY_STEP * float(economy_level())

## The price of `patches` patches on the tile, on the state before the purchase:
## {per_patch, total, patches, standalone, starting_price, share,
##  terms: [{id, label, share, amount}] (the lines a readout prints; their amounts sum to per_patch),
##  advisor_pct (the purchase_cost modifier applied to the total)}.
static func quote(tile_id: String, patches: int, standalone: bool) -> Dictionary:
	var s := starting_price(tile_id)
	var n := counted_buildings(tile_id)
	var a := adjacency_share(tile_id)
	var e := economy_share(tile_id)
	var terms: Array = [{"id": "band", "label": "%s ×%d" % [band_label(tile_id), roundi(band_mult(tile_id))],
		"share": 1.0, "amount": s}]
	if n > 0:
		var ramp := EconomyConfig.LAND_RAMP_PER_BUILDING * float(n)
		terms.append({"id": "buildings", "label": "%d %s here" % [n, "building" if n == 1 else "buildings"],
			"share": ramp, "amount": s * ramp})
	if a > 0.0:
		var beside := "Next to land bought on its own" if a >= EconomyConfig.LAND_ADJACENT_STANDALONE else "Next to your land"
		terms.append({"id": "adjacent", "label": beside, "share": a, "amount": s * a})
	if e > 0.0:
		terms.append({"id": "economy", "label": "Economy doubled %s" % times_word(economy_level()), "share": e, "amount": s * e})
	var share := 1.0 + EconomyConfig.LAND_RAMP_PER_BUILDING * float(n) + a + e
	var per_patch := s * share
	if standalone:
		var extra := per_patch * (EconomyConfig.LAND_STANDALONE_MULT - 1.0)
		terms.append({"id": "standalone", "label": "Bought on its own", "share": share * (EconomyConfig.LAND_STANDALONE_MULT - 1.0),
			"amount": extra})
		per_patch += extra
	var count := maxi(0, patches)
	var ctx := {"tile_id": tile_id}
	var total := AdvisorState.purchase_cost_after_advisor(per_patch * float(count), ctx)
	return {
		"per_patch": per_patch, "total": total, "patches": count, "standalone": standalone,
		"starting_price": s, "share": share, "terms": terms,
		"advisor_pct": float(Modifiers.resolve_pct("purchase_cost", "*", ctx).get("net", 0.0)),
	}

## The quote's price for one patch after the adviser, what a single patch actually costs.
static func patch_price(tile_id: String, standalone: bool) -> float:
	return float(quote(tile_id, 1, standalone).total)

## The neighbours a stand-alone purchase on the tile would raise to LAND_ADJACENT_STANDALONE: those not
## already there.
static func standalone_rises(tile_id: String) -> Array:
	var out: Array = []
	for neighbour: String in Catalog.tile_neighbours(tile_id):
		if adjacency_share(neighbour) < EconomyConfig.LAND_ADJACENT_STANDALONE:
			out.append(neighbour)
	return out

## [label, figure] rows a readout prints for a quote: the band, each rise with a plus, any adviser or decision
## change, then the price of one patch. The rises sum to the patch price before the adviser.
static func lines(q: Dictionary) -> Array:
	var out: Array = []
	for term: Dictionary in q.terms:
		var figure := pounds(float(term.amount))
		out.append([str(term.label), figure if str(term.id) == "band" else "+" + figure])
	var pct := float(q.advisor_pct)
	if absf(pct) > 0.0001:
		out.append(["Purchase discount" if pct < 0.0 else "Purchase premium", ("%d%%" if pct < 0.0 else "+%d%%") % roundi(pct)])
	var patches := maxi(1, int(q.patches))
	out.append(["Per patch", pounds(float(q.total) / float(patches))])
	return out

## The quote's lines as one block of text, for a hover.
static func lines_text(q: Dictionary) -> String:
	var rows: Array = []
	for line: Array in lines(q):
		rows.append("%s  %s" % [str(line[0]), str(line[1])])
	return "\n".join(rows)

## A land price as a readout prints it: whole pounds with thousands separators, pence only when there are some.
static func pounds(value: float) -> String:
	var v := absf(value)
	var minus := "-" if value < -0.004 else ""
	if absf(v - roundf(v)) < 0.005:
		var digits := str(roundi(v))
		var grouped := ""
		while digits.length() > 3:
			grouped = "," + digits.right(3) + grouped
			digits = digits.left(digits.length() - 3)
		return "%s£%s%s" % [minus, digits, grouped]
	return "%s£%.2f" % [minus, v]

static func times_word(n: int) -> String:
	match n:
		1: return "once"
		2: return "twice"
	return "%d times" % n


# --- The economy index ---------------------------------------------------------------------------------------

## The revenue every firm started from together: G0.
static func base_revenue() -> float:
	return float(CompanyRankings.TOTAL_COMPANIES) * CompanyRankings.STARTING_REVENUE

## Whole doublings of `revenue` over G0, never below 0.
static func doublings(revenue: float) -> int:
	var g0 := base_revenue()
	if revenue <= 0.0 or g0 <= 0.0:
		return 0
	return maxi(0, floori(log(revenue / g0) / log(2.0) + 1e-9))

## The latched economy level. An older save without one takes today's standings.
static func economy_level() -> int:
	if BuildingState.land_economy_level < 0:
		BuildingState.land_economy_level = doublings(CompanyRankings.global_revenue())
	return BuildingState.land_economy_level

## Global revenue at which the next doubling lands.
static func next_threshold() -> float:
	return base_revenue() * pow(2.0, float(economy_level() + 1))

## Once a turn, after the rivals have moved: latch any new doubling and tell the player, or warn them once when
## revenue nears the next one. Returns the level.
static func tick_economy() -> int:
	var before := economy_level()
	var revenue := CompanyRankings.global_revenue()
	var now := maxi(before, doublings(revenue))
	if now > before:
		BuildingState.land_economy_level = now
		BuildingState.land_economy_warned = maxi(BuildingState.land_economy_warned, now)
		EventScheduler.emit_event({
			"kind": "land_prices", "severity": "info", "source": "government",
			"title": "City land prices rise",
			"body": "The economy has doubled %s since the start. Land in towns and cities now costs %d%% more of its starting price." % [
				times_word(now), roundi(EconomyConfig.LAND_ECONOMY_STEP * 100.0 * float(now))],
		})
	elif revenue >= EconomyConfig.LAND_ECONOMY_FOREWARN * next_threshold() and BuildingState.land_economy_warned <= now:
		BuildingState.land_economy_warned = now + 1
		EventScheduler.emit_event({
			"kind": "land_prices", "severity": "info", "source": "government",
			"title": "City land prices will rise soon",
			"body": "Global revenue is %d%% of the way to the next doubling. Land in towns and cities will then rise." % roundi(
				100.0 * revenue / next_threshold()),
		})
	return BuildingState.land_economy_level
