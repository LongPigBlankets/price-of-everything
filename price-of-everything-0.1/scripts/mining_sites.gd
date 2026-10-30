extends RefCounted
## Seams with working limits (docs/pacing-labour-mining-licensing-spec.md §8, design stance A5).
##
## A site is one deposit good on one tile; its workings are the player's buildings mining that good there. A
## site draws the sum of its workings' level (1, 2, 3.5) × throughput × staffing run fraction, in level 1
## workings (throughput is 1 at mines and oil wells, so only a water pump's counts, §3.2a), and a working down after an accident, offline under a seam card or paused draws nothing. NPC
## buildings never draw. Every seam, endless (no amount in the CSV, water included) or finite, is free to 1.5 and
## may collapse past 3 (EconomyConfig.SEAM_FREE, SEAM_MAX).
##
## Over the free cap, M = 1 + c × (draw − free), c = 1 unless `extraction_cap_cost` modifiers change it, multiplies the
## labour (after the labour floor) and the maintenance of every working on the site. Past the max nothing is held
## back: the seam may collapse instead (owner ruling, 26 October 2026), a chance each turn of COLLAPSE_PER_WORKING
## for each working's worth over it (MatchState.seams rolls it). Players read every figure in units dug a turn:
## a working's draw × its recipe's base output. Everything here is derived when asked and never saved.

const BuildingLevels := preload("res://scripts/building_levels.gd")
const Staffing := preload("res://scripts/staffing.gd")

const ENDLESS := "endless"
const FINITE := "finite"
## The chance a turn that a seam worked past its limit collapses, for each level 1 working's worth over it.
const COLLAPSE_PER_WORKING := 0.05


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


## One working's draw in level 1 workings: level × throughput (1 at mines and oil wells) × staffing run fraction. Nothing while it is down
## after an accident, offline under a seam card, paused or retooling, or once its seam is empty.
static func working_draw(building: Dictionary) -> float:
	var iid := str(building.get("instance_id", ""))
	if MatchState.deposit_depleted(str(building.get("tile_id", "")), building_token(building)):
		return 0.0
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


## A level 1 working's output a turn under `recipe`, before yield: what one working digs.
static func base_rate(recipe: Dictionary) -> float:
	var best := 0.0
	for o in recipe.get("outputs", []):
		best = maxf(best, float((o as Dictionary).get("qty", 0)))
	return best


## A site's figures, counting the player's workings on it plus `extra`, a building not yet on the map (a
## forecast's stand-in or a build preview, its instance id empty): {tile_id, token, kind, workings, draw and
## units (what it digs a turn), free, max and their units, over, m, past (workings over the max) and collapse
## (its chance a turn)}.
static func site(tile_id: String, token: String, extra: Dictionary = {}) -> Dictionary:
	var draw := 0.0
	var units := 0.0
	var rate := 0.0
	var workings: Array = []
	for b: Dictionary in BuildingState.get_buildings_on_tile(tile_id):
		if not BuildingState.is_player_owned(b) or building_token(b) != token:
			continue
		workings.append(str(b.get("instance_id", "")))
		var recipe := Catalog.get_recipe(str(b.get("recipe_id", "")))
		var d := working_draw(b)
		draw += d
		units += d * base_rate(recipe)
		rate = maxf(rate, base_rate(recipe))
	if not extra.is_empty():
		var recipe := Catalog.get_recipe(str(extra.get("recipe_id", "")))
		var d := working_draw(extra)
		draw += d
		units += d * base_rate(recipe)
		rate = maxf(rate, base_rate(recipe))
	var k := kind(tile_id, token)
	return _settle({"tile_id": tile_id, "token": token, "kind": k, "workings": workings, "rate": rate,
		"free": float(EconomyConfig.SEAM_FREE[k]), "max": float(EconomyConfig.SEAM_MAX[k])}, draw, units)


## A site's figures for `draw` workings digging `units` a turn.
static func _settle(s: Dictionary, draw: float, units: float) -> Dictionary:
	s["draw"] = draw
	s["units"] = units
	s["free_units"] = float(s.free) * float(s.rate)
	s["max_units"] = float(s.max) * float(s.rate)
	s["over"] = maxf(0.0, draw - float(s.free))
	s["m"] = 1.0 + cap_cost(str(s.tile_id), str(s.token)) * float(s.over)
	s["past"] = maxf(0.0, draw - float(s.max))
	s["collapse"] = minf(1.0, COLLAPSE_PER_WORKING * float(s.past))
	return s


## The site a building works, with it counted, or {} for a building that mines nothing or belongs to another
## company. A building not yet on the map counts as one more working; a copy of one on the map at another level
## (Production.stats_at_level) counts in its place.
static func site_of(building: Dictionary) -> Dictionary:
	var token := building_token(building)
	if token == "":
		return {}
	var iid := str(building.get("instance_id", ""))
	if iid != "" and not BuildingState.is_player_owned(building):
		return {}
	var tile_id := str(building.get("tile_id", ""))
	if iid == "" or not BuildingState.buildings.has(iid):
		return site(tile_id, token, building)
	var s := site(tile_id, token)
	var stored := BuildingState.get_building(iid)
	if int(stored.get("level", 1)) == int(building.get("level", 1)):
		return s
	var rate := base_rate(Catalog.get_recipe(str(building.get("recipe_id", ""))))
	var swing := working_draw(building) - working_draw(stored)
	return _settle(s, float(s.draw) + swing, float(s.units) + swing * rate)


## M for a building's labour and maintenance: 1 for one that mines nothing.
static func m_for(building: Dictionary) -> float:
	var s := site_of(building)
	return 1.0 if s.is_empty() else float(s.m)


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


## The site after adding `building` at `level` (a build) or raising it to `level` (an upgrade), for the construct
## and upgrade dialogs, with `before_units`, what the site digs today. {} for a building that mines nothing.
static func site_after(building_id: String, recipe_id: String, tile_id: String, level: int, instance_id := "") -> Dictionary:
	var token := token_of(Catalog.get_recipe(recipe_id))
	if token == "":
		return {}
	var before := float(site(tile_id, token).units)
	var s: Dictionary
	if instance_id == "" or not BuildingState.buildings.has(instance_id):
		s = site(tile_id, token, {"instance_id": "", "building_id": building_id, "recipe_id": recipe_id, "tile_id": tile_id, "level": level})
	else:
		var b := BuildingState.get_building(instance_id).duplicate()
		b["level"] = level
		s = site_of(b)
	s["before_units"] = before
	return s


## A build or an upgrade as the dialogs say it, in units a turn: "Seam output will increase from 60 to 120. Above
## 360, deposit may collapse."
static func after_words(s: Dictionary) -> String:
	if s.is_empty():
		return ""
	return "Seam output will increase from %s to %s. Above %s, deposit may collapse." % [
		units_text(float(s.get("before_units", 0.0))), units_text(float(s.units)), units_text(float(s.max_units))]


## A seam as the tile view reads it: "Coal seam. Digging 150 a turn. Costs rise above 180. May collapse above
## 360. 4,120 left." (`named` false leaves off "Coal seam."), an endless one "Never runs out." in place of its amount.
static func seam_words(tile_id: String, token: String, named := true) -> String:
	var words := draw_words(tile_id, token)
	var left := MatchState.deposit_remaining_for(tile_id, token)
	words += (" %s left." % thousands(left)) if left >= 0 else " Never runs out."
	if named:
		var good := Catalog.get_good_by_internal_name(token)
		words = "%s seam. %s" % [str(good.get("display_name", token)), words]
	return words


## A site's digging against its limits, in units a turn: "Digging 150 a turn. Costs rise above 180. May collapse
## above 360."
static func draw_words(tile_id: String, token: String) -> String:
	return ". ".join(draw_lines(tile_id, token)) + "."


## The same, a figure a line, for a narrow column: ["Digging 150 a turn", "Costs rise above 180", "May collapse
## above 360"].
static func draw_lines(tile_id: String, token: String) -> PackedStringArray:
	var s := site(tile_id, token)
	return PackedStringArray(["Digging %s a turn" % units_text(float(s.units)), "Costs rise above %s" % units_text(float(s.free_units)),
		"May collapse above %s" % units_text(float(s.max_units))])


## Units a turn as the panels print them: whole, with thousands commas.
static func units_text(v: float) -> String:
	return thousands(roundi(v))


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
