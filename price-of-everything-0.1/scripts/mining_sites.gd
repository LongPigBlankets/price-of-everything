extends RefCounted
## Seams with working limits (docs/pacing-labour-mining-licensing-spec.md §8, design stance A5).
##
## A site is one deposit good on one tile; its workings are the player's buildings mining that good there. A
## site draws the sum of its workings' level (1, 2, 3.5) × throughput × staffing run fraction, in level 1
## workings, and a working down after an accident, offline under a seam card or paused draws nothing. NPC
## buildings never draw. Endless seams (no amount in the CSV, water included) are free to 2 and end at 4; finite
## seams are free to 3 and end at 6.
##
## Over the free cap, M = 1 + c × (min(draw, max) − free), c = 1 unless `extraction_cap_cost` modifiers change
## it, multiplies the labour (after the labour floor) and the maintenance of every working on the site. Past the
## max, every working runs at max / draw, its inputs, outputs, power and the seam's charge together
## (MatchState.run_multiplier). Everything here is derived when asked and never saved.

const BuildingLevels := preload("res://scripts/building_levels.gd")
const Staffing := preload("res://scripts/staffing.gd")

const ENDLESS := "endless"
const FINITE := "finite"


## The deposit good a recipe mines, or "".
static func token_of(recipe: Dictionary) -> String:
	for req in recipe.get("requirements", []):
		if str((req as Dictionary).get("type", "")) == "deposit":
			return str((req as Dictionary).get("value", ""))
	return ""


## The deposit good a building mines, or "".
static func building_token(building: Dictionary) -> String:
	return token_of(Catalog.get_recipe(str(building.get("recipe_id", ""))))


## "finite" when the tile's seam of `token` has a size (MatchState.deposit_remaining tracks it), else "endless".
static func kind(tile_id: String, token: String) -> String:
	return FINITE if MatchState.deposit_remaining_for(tile_id, token) >= 0 else ENDLESS


## One working's draw in level 1 workings: level × throughput × staffing run fraction. Nothing while it is down
## after an accident, offline under a seam card, paused or retooling.
static func working_draw(building: Dictionary) -> float:
	var iid := str(building.get("instance_id", ""))
	if iid != "":
		if LabourState.unrest.is_down(iid) or BuildingWorks.is_building_paused(iid) or BuildingWorks.is_retooling(iid):
			return 0.0
		if MatchState.seams.is_offline(str(building.get("tile_id", "")), building_token(building)):
			return 0.0
	return BuildingLevels.mult("output", int(building.get("level", 1))) * MatchState.throughput_multiplier(building) \
		* Staffing.run_fraction(building)


## The over-cap cost of one full working (c): +100% unless `extraction_cap_cost` modifiers change it.
static func cap_cost(tile_id: String, token: String) -> float:
	if not Modifiers.has_domain("extraction_cap_cost"):
		return EconomyConfig.SEAM_OVER_CAP_COST
	return maxf(0.0, Modifiers.apply("extraction_cap_cost", token, EconomyConfig.SEAM_OVER_CAP_COST,
		{"good_internal": token, "tile_id": tile_id}))


## A site's figures, counting the player's workings on it plus `extra`, a building not yet on the map (a
## forecast's stand-in or a build preview, its instance id empty):
## {tile_id, token, kind, draw, free, max, over, m, scale, workings: [instance ids]}.
static func site(tile_id: String, token: String, extra: Dictionary = {}) -> Dictionary:
	var k := kind(tile_id, token)
	var free := float(EconomyConfig.SEAM_FREE[k])
	var top := float(EconomyConfig.SEAM_MAX[k])
	var draw := 0.0
	var workings: Array = []
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile_id):
		if not BuildingState.is_player_owned(b) or building_token(b) != token:
			continue
		workings.append(str(b.get("instance_id", "")))
		draw += working_draw(b)
	if not extra.is_empty():
		draw += working_draw(extra)
	var over := maxf(0.0, minf(draw, top) - free)
	return {"tile_id": tile_id, "token": token, "kind": k, "draw": draw, "free": free, "max": top, "over": over,
		"m": 1.0 + cap_cost(tile_id, token) * over, "scale": minf(1.0, top / draw) if draw > top else 1.0,
		"workings": workings}


## The site a building works, with it counted (a building not yet on the map as one more working), or {} for a
## building that mines nothing or belongs to another company.
static func site_of(building: Dictionary) -> Dictionary:
	var token := building_token(building)
	if token == "":
		return {}
	var iid := str(building.get("instance_id", ""))
	if iid != "" and not BuildingState.is_player_owned(building):
		return {}
	var on_map := iid != "" and BuildingState.buildings.has(iid)
	return site(str(building.get("tile_id", "")), token, {} if on_map else building)


## M for a building's labour and maintenance: 1 for one that mines nothing.
static func m_for(building: Dictionary) -> float:
	var s := site_of(building)
	return 1.0 if s.is_empty() else float(s.m)


## The share of its run a building keeps past its site's max: 1 for one that mines nothing.
static func scale_for(building: Dictionary) -> float:
	var s := site_of(building)
	return 1.0 if s.is_empty() else float(s.scale)


## Every site the player works, {"tile|token": site}.
static func player_sites() -> Dictionary:
	var out := {}
	for b: Dictionary in BuildingState.buildings.values():
		if not BuildingState.is_player_owned(b):
			continue
		var token := building_token(b)
		if token == "":
			continue
		var key := "%s|%s" % [str(b.get("tile_id", "")), token]
		if not out.has(key):
			out[key] = site(str(b.get("tile_id", "")), token)
	return out


## The site after adding `building` at `level` (a build) or raising it to `level` (an upgrade): the site as it
## would stand, for the construct and upgrade dialogs. {} for a building that mines nothing.
static func site_after(building_id: String, recipe_id: String, tile_id: String, level: int, instance_id := "") -> Dictionary:
	var token := token_of(Catalog.get_recipe(recipe_id))
	if token == "":
		return {}
	var probe := {"instance_id": "", "building_id": building_id, "recipe_id": recipe_id, "tile_id": tile_id, "level": level}
	if instance_id == "":
		return site(tile_id, token, probe)
	var b := BuildingState.get_building(instance_id)
	var s := site(tile_id, token)
	if b.is_empty():
		return s
	var before := working_draw(b)
	var after_b := b.duplicate()
	after_b["level"] = level
	var draw := float(s.draw) - before + working_draw(after_b)
	var over := maxf(0.0, minf(draw, float(s.max)) - float(s.free))
	s["draw"] = draw
	s["over"] = over
	s["m"] = 1.0 + cap_cost(tile_id, token) * over
	s["scale"] = minf(1.0, float(s.max) / draw) if draw > float(s.max) else 1.0
	return s


## Whether adding to a site that stood at `before` draw adds anything: refused when it already stands at its max.
static func adds_nothing(before: Dictionary) -> bool:
	return not before.is_empty() and float(before.draw) >= float(before.max) - 0.0001


## The site as a player reads it: "Takes the seam to 4 of 3 free. Labour and upkeep here ×2."
static func after_words(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	var words := "Takes the seam to %s of %s free." % [figure(float(s.draw)), figure(float(s.free))]
	if float(s.m) > 1.0001:
		words += " Labour and upkeep here ×%s." % figure(float(s.m))
	if float(s.draw) > float(s.max) + 0.0001:
		words += " Past its limit of %s, every working here runs at %d%%." % [figure(float(s.max)), roundi(float(s.scale) * 100.0)]
	return words


## A seam as the tile view reads it: "Coal seam. Drawing 2.5 of 3 free. Limit 6. 4,120 left." (`named` false
## leaves off "Coal seam."), an endless one "Never runs out." in place of its amount.
static func seam_words(tile_id: String, token: String, named := true) -> String:
	var words := draw_words(tile_id, token)
	var left := MatchState.deposit_remaining_for(tile_id, token)
	words += (" %s left." % thousands(left)) if left >= 0 else " Never runs out."
	if named:
		var good := Catalog.get_good_by_internal_name(token)
		words = "%s seam. %s" % [str(good.get("display_name", token)), words]
	return words


## A site's draw against its caps: "Drawing 2.5 of 3 free. Limit 6."
static func draw_words(tile_id: String, token: String) -> String:
	var s := site(tile_id, token)
	return "Drawing %s of %s free. Limit %s." % [figure(float(s.draw)), figure(float(s.free)), figure(float(s.max))]


## A whole number with thousands commas: 4,120.
static func thousands(n: int) -> String:
	var digits := str(absi(n))
	var out := ""
	while digits.length() > 3:
		out = "," + digits.substr(digits.length() - 3) + out
		digits = digits.substr(0, digits.length() - 3)
	return ("-" if n < 0 else "") + digits + out


## A draw or a multiplier as the panels print it: whole numbers plain, else one decimal.
static func figure(v: float) -> String:
	return str(roundi(v)) if absf(v - roundf(v)) < 0.05 else "%.1f" % v
