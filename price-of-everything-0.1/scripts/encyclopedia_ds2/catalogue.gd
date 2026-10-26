extends RefCounted
## The encyclopedia's catalogue: what each page of the DS2 encyclopedia lists, read from the Catalog and the live
## state, with no drawing. scripts/encyclopedia_ds2/encyclopedia_ds2.gd lays it out as the pages of a trade catalogue.
##
## A recipe is shown as a row: {kind "recipe", id, name, plant (the building's id), research (true while it still
## needs research), inputs [[good_id, qty]], outputs [[good_id, qty]]}. A good, a building, a tile or a mechanic
## named in a list is an item: {kind, id, name, note}. Recipes hidden with their building (a demo's) and goods the
## match does not show are left out everywhere, as the search always did.

const MParts := preload("res://scripts/market_ds2/parts.gd")
const SearchOverlay := preload("res://scripts/search_overlay.gd")

const SECTIONS := ["goods", "recipes", "buildings", "mechanics"]
const SECTION_TITLES := {"goods": "GOODS", "recipes": "RECIPES", "buildings": "BUILDINGS", "mechanics": "MECHANICS"}
## The Mechanics entry the Price impact line opens.
const PRICE_IMPACT_ENTRY := "market_price_mechanics"


# --- what is shown ----------------------------------------------------------------------------

static func recipes() -> Array:
	return Catalog.all_recipes().filter(func(r: Dictionary) -> bool:
		return MatchState.is_building_available(str(r.get("building_id", ""))))


static func goods() -> Array:
	return MatchState.visible_goods()


static func buildings() -> Array:
	return Catalog.all_buildings().filter(func(b: Dictionary) -> bool:
		var bid := str(b.get("id", ""))
		return MatchState.is_building_available(bid) \
			and (MatchState.is_recycling_available() or not MatchState.RECYCLING_BUILDING_IDS.has(bid)))


static func mechanics() -> Array:
	return SearchOverlay.MECHANIC_ENTRIES


## The long-form articles are cut from the demo: their tab is greyed and says so on hover.
static func mechanics_locked() -> bool:
	return str(MatchState.ruleset.get("victory_set", "")) == "demo_itch"


# --- a recipe as a row ------------------------------------------------------------------------

static func needs_research(recipe: Dictionary) -> bool:
	var req := str(recipe.get("tech_unlock_req", ""))
	if req != "" and not ResearchState.is_unlocked(req):
		return true
	var bld_req := str(Catalog.get_building(str(recipe.get("building_id", ""))).get("required_research", ""))
	return bld_req != "" and not ResearchState.is_unlocked(bld_req)


static func row_for(recipe: Dictionary) -> Dictionary:
	var ins: Array = []
	for i: Dictionary in recipe.get("inputs", []):
		ins.append([str(i.get("good_id", "")), int(i.get("qty", 0))])
	var outs: Array = []
	for o: Dictionary in recipe.get("outputs", []):
		outs.append([str(o.get("good_id", "")), int(o.get("qty", 0))])
	return {"kind": "recipe", "id": str(recipe.get("recipe_id", "")), "name": str(recipe.get("display_name", "")),
		"plant": str(recipe.get("building_id", "")), "research": needs_research(recipe), "inputs": ins, "outputs": outs}


static func _uses(recipe: Dictionary, good_id: String) -> int:
	for i: Dictionary in recipe.get("inputs", []):
		if str(i.get("good_id", "")) == good_id:
			return int(i.get("qty", 0))
	return 0


static func _makes(recipe: Dictionary, good_id: String) -> bool:
	for o: Dictionary in recipe.get("outputs", []):
		if str(o.get("good_id", "")) == good_id:
			return true
	return false


# --- a good's entry ---------------------------------------------------------------------------

## Every recipe that makes the good, as rows.
static func made_by(good_id: String) -> Array:
	var out: Array = []
	for r: Dictionary in recipes():
		if _makes(r, good_id):
			out.append(row_for(r))
	return out


## Every recipe that uses the good, grouped by what it makes (its first output): [{good, name, rows}], the
## largest group first, then by name. A used-in row shows only this good going in, then what comes out.
static func used_in_groups(good_id: String) -> Array:
	var by_good: Dictionary = {}
	var order: Array = []
	for r: Dictionary in recipes():
		var qty := _uses(r, good_id)
		if qty <= 0:
			continue
		var row := row_for(r)
		row["inputs"] = [[good_id, qty]]
		var out_id := str(r.get("output_good_id", ""))
		if out_id == "":
			out_id = "_none"
		if not by_good.has(out_id):
			by_good[out_id] = []
			order.append(out_id)
		(by_good[out_id] as Array).append(row)
	var groups: Array = []
	for gid: String in order:
		var name := "Nothing made" if gid == "_none" else Catalog.get_display_name(gid)
		groups.append({"good": "" if gid == "_none" else gid, "name": name, "rows": by_good[gid]})
	groups.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var na := (a.rows as Array).size()
		var nb := (b.rows as Array).size()
		return na > nb if na != nb else str(a.name) < str(b.name))
	return groups


static func used_in_count(good_id: String) -> int:
	var n := 0
	for g: Dictionary in used_in_groups(good_id):
		n += (g.rows as Array).size()
	return n


## The buildings whose recipes make the good: [{id, count}] in the order they first appear.
static func makers(good_id: String) -> Array:
	var counts: Dictionary = {}
	var order: Array = []
	for row: Dictionary in made_by(good_id):
		var bid := str(row.plant)
		if not counts.has(bid):
			counts[bid] = 0
			order.append(bid)
		counts[bid] = int(counts[bid]) + 1
	return order.map(func(bid: String) -> Dictionary: return {"id": bid, "count": counts[bid]})


## What goes into the good, every recipe's inputs once each, in the order they appear.
static func inputs_of(good_id: String) -> Array:
	var out: Array = []
	for row: Dictionary in made_by(good_id):
		for pair: Array in row.inputs:
			var gid := str(pair[0])
			if gid != good_id and not out.has(gid):
				out.append(gid)
	return out


## "Metals. Intermediate good."
static func describe_good(good: Dictionary) -> String:
	var cat := _words(str(good.get("category", "")))
	var kind := _words(str(good.get("good_type", "")))
	var parts: Array = []
	if cat != "":
		parts.append(cat + ".")
	if kind != "":
		parts.append(kind + " good.")
	return " ".join(parts)


## "solid_heavy" -> "Solid, heavy".
static func freight_text(transport_class: String) -> String:
	var bits := transport_class.split("_", false)
	if bits.is_empty():
		return "Ordinary"
	var out := ", ".join(bits).to_lower()
	return out.substr(0, 1).to_upper() + out.substr(1)


## The good's specification lines: [label, value, link]. The price impact is the good's live impact, as the market
## shows it; its line opens Mechanics at Price impact.
static func good_facts(good_id: String) -> Array:
	var good: Dictionary = Catalog.get_good(good_id)
	var impact := float(MarketState.impact_pct.get(good_id, 0.0))
	return [
		["Freight", freight_text(str(good.get("transport_class", ""))), ""],
		["Price impact", MParts.impact_text(impact), PRICE_IMPACT_ENTRY],
		["Buyable", "YES" if bool(good.get("is_buyable", false)) else "NO", ""],
		["Sellable", "YES" if bool(good.get("is_sellable", false)) else "NO", ""],
		["Base price", "£%.2f a unit" % float(good.get("base_price", 0.0)), ""],
	]


# --- a building's entry -----------------------------------------------------------------------

static func building_recipes(building_id: String) -> Array:
	var out: Array = []
	for r: Dictionary in recipes():
		if str(r.get("building_id", "")) == building_id:
			out.append(row_for(r))
	return out


## What it is built from: [[good_id, qty]].
static func building_materials(building_id: String) -> Array:
	var out: Array = []
	for m: Dictionary in Catalog.get_building(building_id).get("materials", []):
		var gid := str(Catalog.get_good_by_internal_name(str(m.get("name", ""))).get("id", ""))
		if gid != "":
			out.append([gid, int(m.get("qty", 0))])
	return out


## What its recipes make, each good once.
static func building_outputs(building_id: String) -> Array:
	var out: Array = []
	for row: Dictionary in building_recipes(building_id):
		for pair: Array in row.outputs:
			if not out.has(str(pair[0])):
				out.append(str(pair[0]))
	return out


static func building_facts(building_id: String) -> Array:
	var b: Dictionary = Catalog.get_building(building_id)
	var maint: Variant = b.get("maintenance_cost", null)
	var lines := [
		["Build cost", "£%s" % _thousands(float(b.get("base_price", 0.0))), ""],
		["Land", str(int(Catalog.land_units(b))), ""],
		["Build time", "%d %s" % [int(b.get("build_duration", 0)), "turn" if int(b.get("build_duration", 0)) == 1 else "turns"], ""],
		["Upkeep", "None" if maint == null else "£%.2f a turn" % float(maint), ""],
	]
	var req := str(b.get("required_research", ""))
	if req != "":
		var title := ResearchState.research_title_for_node_id(req)
		lines.append(["Research", title if title != "" else _words(req), ""])
	return lines


static func describe_building(b: Dictionary) -> String:
	var cat := _words(str(b.get("category", "")))
	return (cat + ". A building.") if cat != "" else "A building."


# --- a recipe's entry -------------------------------------------------------------------------

static func recipe_facts(recipe: Dictionary) -> Array:
	var b: Dictionary = Catalog.get_building(str(recipe.get("building_id", "")))
	var labour := []
	for pair in [["labour_unskilled_required", "unskilled"], ["labour_skilled_required", "skilled"], ["labour_h_skilled_required", "highly skilled"]]:
		var n := int(recipe.get(pair[0], -1))
		if n < 0:
			n = int(b.get(pair[0], 0))
		if n > 0:
			labour.append("%s %s" % [_thousands(n), pair[1]])
	var req := str(recipe.get("tech_unlock_req", ""))
	var research := "None"
	if req != "":
		var title := ResearchState.research_title_for_node_id(req)
		research = title if title != "" else _words(req)
	return [
		["Made in", str(b.get("display_name", "")), ""],
		["Power", "%d MW" % int(recipe.get("energy_req", 0)), ""],
		["Labour", ", ".join(labour) if not labour.is_empty() else "None", ""],
		["Research", research, ""],
	]


static func describe_recipe(recipe: Dictionary) -> String:
	var cat := str(recipe.get("recipe_type", ""))
	return (cat + ". A recipe.") if cat != "" else "A recipe."


## Other recipes in the same building.
static func sibling_recipes(recipe: Dictionary) -> Array:
	var rid := str(recipe.get("recipe_id", ""))
	return building_recipes(str(recipe.get("building_id", ""))).filter(func(row: Dictionary) -> bool: return str(row.id) != rid)


## Other recipes that make its main output.
static func rival_recipes(recipe: Dictionary) -> Array:
	var rid := str(recipe.get("recipe_id", ""))
	var gid := str(recipe.get("output_good_id", ""))
	if gid == "":
		return []
	return made_by(gid).filter(func(row: Dictionary) -> bool: return str(row.id) != rid)


# --- the look up ------------------------------------------------------------------------------

## Scored as the search always was: the name exactly 100, its start 80, anywhere in it 50; a recipe also by what it
## makes, its building and what it uses, each lower, so a recipe named for the look up comes first. Every match is kept, best first.
static func score(query: String, text: String) -> int:
	if text == "" or query == "":
		return 0
	var t := text.to_lower()
	if t == query:
		return 100
	if t.begins_with(query):
		return 80
	return 50 if t.contains(query) else 0


static func look_up(query: String) -> Dictionary:
	var q := query.strip_edges().to_lower()
	var found := {"goods": [], "recipes": [], "buildings": [], "tiles": [], "mechanics": []}
	if q == "":
		return found
	for g: Dictionary in goods():
		var s := maxi(score(q, str(g.get("display_name", ""))), score(q, str(g.get("internal_name", ""))))
		if s > 0:
			found.goods.append({"kind": "good", "id": str(g.get("id", "")), "name": str(g.get("display_name", "")), "score": s})
	for r: Dictionary in recipes():
		var s := score(q, str(r.get("display_name", "")))
		for o: Dictionary in r.get("outputs", []):
			s = maxi(s, score(q, Catalog.get_display_name(str(o.get("good_id", "")))) - 25)
		for i: Dictionary in r.get("inputs", []):
			s = maxi(s, score(q, Catalog.get_display_name(str(i.get("good_id", "")))) - 40)
		s = maxi(s, score(q, Catalog.get_building_display_name(str(r.get("building_id", "")))) - 30)
		if s > 0:
			var row := row_for(r)
			row["score"] = s
			found.recipes.append(row)
	for b: Dictionary in buildings():
		var s := maxi(score(q, str(b.get("display_name", ""))), score(q, str(b.get("internal_name", ""))))
		if s > 0:
			found.buildings.append({"kind": "building", "id": str(b.get("id", "")), "name": str(b.get("display_name", "")), "score": s})
	for t: Dictionary in Catalog.named_tiles():
		var s := score(q, str(t.get("name", "")))
		if s > 0:
			found.tiles.append({"kind": "tile", "id": str(t.get("id", "")), "name": str(t.get("name", "")), "note": "Go to this tile", "score": s})
	if not mechanics_locked():
		for m: Dictionary in mechanics():
			var s := score(q, str(m.get("title", "")))
			if s > 0:
				found.mechanics.append({"kind": "mechanic", "id": str(m.get("id", "")), "name": str(m.get("title", "")), "score": s})
	for k: String in found:
		(found[k] as Array).sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.score) > int(b.score) if int(a.score) != int(b.score) else str(a.name) < str(b.name))
	return found


static func entry_count(found: Dictionary) -> int:
	var n := 0
	for k: String in found:
		n += (found[k] as Array).size()
	return n


## The best match the index opens on: the best good or building (a good on a tie), or {}.
static func best_match(found: Dictionary) -> Dictionary:
	var g: Dictionary = (found.goods as Array)[0] if not (found.goods as Array).is_empty() else {}
	var b: Dictionary = (found.buildings as Array)[0] if not (found.buildings as Array).is_empty() else {}
	if g.is_empty():
		return b
	if b.is_empty():
		return g
	return b if int(b.score) > int(g.score) else g


# --- paging -----------------------------------------------------------------------------------

## Lays a flow of parts down pages. `parts` are dictionaries with `h` (their height, gap included) and optionally
## `bar` (a section's heading) or `head` (a group's heading); `room(i)` is page i's height. A heading never ends a
## page: it moves over with the part after it. A section or group carried over starts the next page under its
## heading again, marked continued. Returns the pages, each an array of parts.
static func paginate(parts: Array, room: Callable) -> Array:
	var pages: Array = [[]]
	var y := 0.0
	var bar: Dictionary = {}
	var head: Dictionary = {}
	var i := 0
	while i < parts.size():
		var p: Dictionary = parts[i]
		var need := float(p.h)
		if p.has("bar") or p.has("head"):
			# Keep a heading with the next part that is not a heading.
			var j := i + 1
			while j < parts.size() and ((parts[j] as Dictionary).has("bar") or (parts[j] as Dictionary).has("head")):
				need += float((parts[j] as Dictionary).h)
				j += 1
			if j < parts.size():
				need += float((parts[j] as Dictionary).h)
		var limit := float(room.call(pages.size() - 1))
		if y > 0.0 and y + need > limit:
			pages.append([])
			y = 0.0
			if not p.has("bar") and not bar.is_empty():
				var again := bar.duplicate()
				again["bar"] = str(bar.bar) + ", continued"
				(pages[-1] as Array).append(again)
				y += float(again.h)
				if not p.has("head") and not head.is_empty():
					var again_head := head.duplicate()
					again_head["head_name"] = str(head.get("head_name", "")) + ", continued"
					(pages[-1] as Array).append(again_head)
					y += float(again_head.h)
		if p.has("bar"):
			bar = p
			head = {}
		elif p.has("head"):
			head = p
		(pages[-1] as Array).append(p)
		y += float(p.h)
		i += 1
	return pages


static func _words(s: String) -> String:
	var out := s.replace("_", " ").strip_edges().to_lower()
	return out.substr(0, 1).to_upper() + out.substr(1) if out != "" else ""


static func _thousands(v: float) -> String:
	var whole := str(int(round(v)))
	var out := ""
	while whole.length() > 3:
		out = "," + whole.substr(whole.length() - 3) + out
		whole = whole.substr(0, whole.length() - 3)
	return whole + out
