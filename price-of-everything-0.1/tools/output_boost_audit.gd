extends SceneTree
## Audits which GOODS can ever receive a recipe_output boost from research, and by which
## route. A good is covered if some unlocked research raises output on:
##   · the good itself      (target_match.good_internal)
##   · a building that makes it (target_match.building_id → recipes → outputs)
##   · a recipe_type it uses    (target_match.recipe_type)
## Reports per goods CATEGORY (the "family"), because that is the level at which a gap is
## a design gap rather than a single missing node.
##   <godot> --headless --path . -s res://tools/output_boost_audit.gd

const GOODS_CSV := "res://data/Goods - goodsMVP.csv"
const RECIPES_CSV := "res://data/recipes_all.csv"
const BUILDINGS_CSV := "res://data/Buildings - buildingsMVP.csv"

var _unresolved := {}   # building_id values in recipes_all.csv that resolve to nothing

func _init() -> void:
	var goods := _rows(GOODS_CSV)         # internal_name, display_name, category
	var recipes := _rows(RECIPES_CSV)
	var buildings := _rows(BUILDINGS_CSV)

	# building internal_name → id, and id → internal_name
	var bid_by_internal := {}
	var binternal_by_id := {}
	for b in buildings:
		bid_by_internal[str(b.get("internal_name", ""))] = str(b.get("ID", ""))
		binternal_by_id[str(b.get("ID", ""))] = str(b.get("internal_name", ""))
	# recipes_all.csv's building_id column is NOT always a catalog internal_name: Catalog
	# runs it through BUILDING_ALIAS first ("factory" → "industrial_factory", "desal_plant"
	# → "desal", …). Skipping that step makes every aliased building look unresearched and
	# invents gaps that do not exist — read the real table rather than hardcoding it.
	var CatalogScript: GDScript = load("res://scripts/catalog.gd")
	var alias: Dictionary = CatalogScript.get_script_constant_map().get("BUILDING_ALIAS", {})
	if alias.is_empty():
		print("WARNING: BUILDING_ALIAS came back empty — results would be wrong; aborting")
		quit(1)
		return

	# good internal → producing building ids, and → recipe categories
	var producers := {}
	var recipe_types_for := {}
	for r in recipes:
		var b_ref := str(r.get("building_id", ""))
		var b_internal: String = str(alias.get(b_ref, b_ref))
		var bid: String = b_ref if b_ref.begins_with("b_") else str(bid_by_internal.get(b_internal, ""))
		if bid == "" and b_ref != "":
			_unresolved[b_ref] = true   # reported below: a recipe Catalog would drop entirely
		var rtype := str(r.get("category", "")).to_lower()
		for i in range(1, 6):
			var g := str(r.get("output_%d" % i, ""))
			if g == "":
				continue
			var plist: Array = producers.get(g, [])
			if bid != "" and not plist.has(bid):
				plist.append(bid)
			producers[g] = plist
			var tlist: Array = recipe_types_for.get(g, [])
			if rtype != "" and not tlist.has(rtype):
				tlist.append(rtype)
			recipe_types_for[g] = tlist

	# recipe_output modifiers, split by how they target
	# NOTE: modifier_state.gd references autoloads (EventScheduler) that do not exist in a
	# `-s` SceneTree, so loading it prints a compile error. The CONSTANT map still resolves;
	# the counts printed below exist to prove the table was read whole rather than partially.
	var ModifierScript: GDScript = load("res://scripts/modifier_state.gd")
	var table: Dictionary = ModifierScript.get_script_constant_map().get("UNLOCK_MODIFIERS", {})
	var n_output := 0
	var by_good := {}       # good_internal → [node titles]
	var by_building := {}   # building_id   → [node titles]
	var by_rtype := {}      # recipe_type   → [node titles]
	for title in table:
		var entry = table[title]
		for m in (entry if entry is Array else [entry]):
			var md: Dictionary = m
			if str(md.get("domain", "")) != "recipe_output":
				continue
			n_output += 1
			var tm: Dictionary = md.get("target_match", {})
			if tm.has("good_internal"):
				_push(by_good, str(tm["good_internal"]), str(title))
			elif tm.has("building_id"):
				_push(by_building, str(tm["building_id"]), str(title))
			elif tm.has("recipe_type"):
				_push(by_rtype, str(tm["recipe_type"]).to_lower(), str(title))

	# Walk goods by category
	var by_category := {}
	for g in goods:
		var internal := str(g.get("internal_name", ""))
		if internal == "" or internal == "power":
			continue          # power is settled by the grid, not a recipe_output target
		if not producers.has(internal):
			continue          # no recipe makes it — nothing to boost
		var cat := str(g.get("category", "uncategorised"))
		var rec: Array = by_category.get(cat, [])
		rec.append(g)
		by_category[cat] = rec

	var covered_total := 0
	var uncovered_total := 0
	var gaps := {}
	print("\n==== TABLE READ ====")
	print("research titles=%d · recipe_output modifiers=%d (by good=%d, by building=%d, by recipe_type=%d)"
		% [table.size(), n_output, by_good.size(), by_building.size(), by_rtype.size()])
	print("==== RECIPE-OUTPUT BOOST COVERAGE BY GOODS FAMILY ====")
	var cats: Array = by_category.keys()
	cats.sort()
	for cat in cats:
		var direct: Array = []
		var via_building: Array = []
		var via_rtype: Array = []
		var none: Array = []
		for g in by_category[cat]:
			var internal := str(g.get("internal_name", ""))
			var name := str(g.get("display_name", internal))
			if by_good.has(internal):
				direct.append(name)
			else:
				var hit := ""
				for bid in producers.get(internal, []):
					if by_building.has(bid):
						hit = str(binternal_by_id.get(bid, bid))
						break
				if hit != "":
					via_building.append("%s (%s)" % [name, hit])
				else:
					var thit := ""
					for t in recipe_types_for.get(internal, []):
						if by_rtype.has(t):
							thit = t
							break
					if thit != "":
						via_rtype.append("%s (%s)" % [name, thit])
					else:
						none.append(name)
		var total: int = direct.size() + via_building.size() + via_rtype.size() + none.size()
		covered_total += total - none.size()
		uncovered_total += none.size()
		print("\n%s — %d/%d covered" % [cat.to_upper(), total - none.size(), total])
		if not direct.is_empty():
			print("   direct   : %s" % ", ".join(direct))
		if not via_building.is_empty():
			print("   building : %s" % ", ".join(via_building))
		if not via_rtype.is_empty():
			print("   recipe   : %s" % ", ".join(via_rtype))
		if not none.is_empty():
			print("   *** NO BOOST: %s" % ", ".join(none))
			gaps[cat] = none

	if not _unresolved.is_empty():
		print("\n==== UNRESOLVED building_id (Catalog would drop these recipes) ====")
		print("   %s" % ", ".join(_unresolved.keys()))

	print("\n==== SUMMARY ====")
	print("covered %d · uncovered %d" % [covered_total, uncovered_total])
	var gk: Array = gaps.keys()
	gk.sort()
	for cat in gk:
		print("  GAP %-16s %d good(s): %s" % [cat, (gaps[cat] as Array).size(), ", ".join(gaps[cat])])
	quit(0)


func _push(d: Dictionary, key: String, val: String) -> void:
	var l: Array = d.get(key, [])
	if not l.has(val):
		l.append(val)
	d[key] = l


func _rows(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		print("cannot open ", path)
		return []
	var headers := f.get_csv_line()
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < 2 or line[0] == "":
			continue
		var row := {}
		for i in headers.size():
			row[headers[i].strip_edges()] = line[i].strip_edges() if i < line.size() else ""
		out.append(row)
	return out
