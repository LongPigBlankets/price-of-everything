extends SceneTree
## Probe for the oil-extraction research pass:
##   1. the two repurposed nodes carry their new name/effect/unlock condition
##   2. no node is left pointing at a prereq title that no longer exists
##   3. every oil node that claims a numeric effect is wired into UNLOCK_MODIFIERS
##   4. no recipe was orphaned by the repurposing (its gate title must still exist)
##   5. modifier ids stay unique
##   <godot> --headless --path . -s res://tools/oil_tech_probe.gd

const OIL_NODES := [
	"Directional & Horizontal Drilling", "Microseismic Monitoring", "Reservoir Stimulation",
	"Subsea Tieback Systems", "Multiphase Subsea Boosting", "Enhanced Oil Recovery",
	"Remote Platform Operations",
]

var _fails := 0

func _init() -> void:
	var rows := _csv_rows("res://data/research_unlocks.csv")
	var titles := {}
	var node_ids := {}
	for r in rows:
		titles[str(r.get("title", ""))] = r
		var nid0 := str(r.get("research_node_id", ""))
		if nid0 != "":
			node_ids[nid0] = true

	print("── 1. repurposed nodes ──")
	_row_is(titles, "Directional & Horizontal Drilling", "Build", "oil_well", "3")
	_row_is(titles, "Subsea Tieback Systems", "Build", "offshore_oil_platform", "5")
	_check("old 'Hydraulic Fracturing' title is gone", str(titles.has("Hydraulic Fracturing")), "false")

	print("\n── 2. dangling prereqs (whole tree) ──")
	# Prereqs store research_node_ids since phase 3 of the id migration.
	var dangling: Array = []
	for r in rows:
		for col in ["prereq_1", "prereq_2", "prereq_3", "prereq_othercategory"]:
			var p := str(r.get(col, "")).strip_edges()
			if p != "" and not node_ids.has(p):
				dangling.append("%s → %s" % [r.get("title", ""), p])
	_check("no dangling prereq references", "none" if dangling.is_empty() else str(dangling), "none")

	print("\n── 3. oil nodes wired into UNLOCK_MODIFIERS ──")
	var ModifierScript: GDScript = load("res://scripts/modifier_state.gd")
	var table: Dictionary = ModifierScript.get_script_constant_map().get("UNLOCK_MODIFIERS", {})
	if table.is_empty():
		_fail("UNLOCK_MODIFIERS came back empty — results would be meaningless")
	for title in OIL_NODES:
		_check("declared in CSV: %s" % title, str(titles.has(title)), "true")
		# The table is keyed by research_node_id; resolve through the node's CSV row.
		var nid := "" if not titles.has(title) else str((titles[title] as Dictionary).get("research_node_id", ""))
		_check("has a node id: %s" % title, "yes" if nid != "" else "no", "yes")
		_check("wired: %s" % title, str(table.has(nid)), "true")
		if table.has(nid):
			var entry = table[nid]
			for m in (entry if entry is Array else [entry]):
				var md: Dictionary = m
				var tm: Dictionary = md.get("target_match", {})
				print("      %s %+.0f%% → %s%s" % [
					md.get("domain", "?"), float(md.get("pct", 0.0)),
					str(tm.get("building_id", tm.get("good_internal", "?"))),
					"" if not md.has("duration_turns") else (" for %d turns" % int(md.duration_turns))])

	print("\n── 4. recipe gates still resolve to a real node ──")
	var recipes := _csv_rows("res://data/recipes_all.csv")
	# Pre-existing orphans, verified against git HEAD: 'consumer' and 'hydro' have never been
	# research titles. They are unrelated to the oil pass, so they are reported but not failed
	# — the check exists to catch a gate THIS pass breaks (renaming a node out from under a
	# recipe), not to re-litigate known content gaps.
	var known_orphan_gates := ["consumer", "hydro"]
	var orphaned: Array = []
	var preexisting: Array = []
	for r in recipes:
		var gate := str(r.get("tech_unlock_req", "")).strip_edges()
		if gate == "" or node_ids.has(gate):   # gates store node ids now
			continue
		var entry := "%s (%s) → '%s'" % [r.get("recipe_id", ""), r.get("display_name", ""), gate]
		if gate in known_orphan_gates:
			preexisting.append(entry)
		else:
			orphaned.append(entry)
	_check("no recipe newly orphaned by this pass", "none" if orphaned.is_empty() else str(orphaned), "none")
	if not preexisting.is_empty():
		print("  NOTE  %d pre-existing orphan(s), unrelated: %s" % [preexisting.size(), str(preexisting)])

	print("\n── 5. modifier id uniqueness ──")
	var seen := {}
	var dupes: Array = []
	for key in table:
		var entry = table[key]
		for m in (entry if entry is Array else [entry]):
			var mid := str((m as Dictionary).get("id", ""))
			if seen.has(mid):
				dupes.append(mid)
			seen[mid] = true
	_check("no duplicate modifier ids", "none" if dupes.is_empty() else str(dupes), "none")

	print("\n==== OIL PROBE %s ====" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(0 if _fails == 0 else 1)


func _row_is(titles: Dictionary, title: String, action: String, obj: String, qty: String) -> void:
	if not titles.has(title):
		_fail("%s: row not found" % title)
		return
	var r: Dictionary = titles[title]
	_check("%s · action" % title, str(r.get("Action", "")), action)
	_check("%s · object" % title, str(r.get("Object", "")), obj)
	_check("%s · quantity" % title, str(r.get("Quantity", "")), qty)
	print("      desc: %s" % r.get("description", ""))


func _csv_rows(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot open %s" % path)
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


func _check(what: String, got: String, want: String) -> void:
	if got == want:
		print("  PASS  %s = %s" % [what, got])
	else:
		_fail("%s = '%s' (expected '%s')" % [what, got, want])


func _fail(msg: String) -> void:
	_fails += 1
	print("  FAIL  %s" % msg)
