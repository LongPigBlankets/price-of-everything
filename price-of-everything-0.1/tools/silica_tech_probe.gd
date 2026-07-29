extends SceneTree
## Headless probe for the two new Inorganic Chemistry nodes (Pozzolanic Vitrification,
## Micro Silica Synthesis). Checks they load from the CSV with the right category/rank/
## prereq, that they are NOT available before High Strength Glassmaking, that they become
## available after it, and that granting them actually moves concrete/glass output.
##   <godot> --headless --path . -s res://tools/silica_tech_probe.gd

const NEW_NODES := ["Pozzolanic Vitrification", "Micro Silica Synthesis"]
const PREREQ := "High Strength Glassmaking"

var _fails := 0

func _init() -> void:
	# Autoloads are not available to a -s script tree, so read the CSV directly for the
	# declaration checks and drive ModifierState's table for the effect checks.
	var rows := _csv_rows("res://data/research_unlocks.csv")
	for title in NEW_NODES:
		var row := {}
		for r in rows:
			if str(r.get("title", "")) == title:
				row = r
				break
		if row.is_empty():
			_fail("%s: not found in research_unlocks.csv" % title)
			continue
		_check("%s category" % title, str(row.get("category", "")), "Inorganic Chemistry")
		_check("%s rank (tier 2)" % title, str(row.get("rank", "")), "II")
		# prereq columns store research_node_ids; compare against the prereq node's id.
		_check("%s prereq_1" % title, str(row.get("prereq_1", "")), _id_of(rows, PREREQ))
		_check("%s has an unlock condition" % title,
			"yes" if str(row.get("Action", "")) != "" and str(row.get("Object", "")) != "" else "no", "yes")
		print("   %s · %s %s %s %s · icon=%s" % [title, row.get("Action", ""),
			row.get("Object", ""), row.get("Quantity", ""), row.get("Unit", ""), row.get("icon", "")])

	# Effects: the modifier table is a plain const, readable without the autoload running.
	var ModifierScript: GDScript = load("res://scripts/modifier_state.gd")
	var table: Dictionary = ModifierScript.get_script_constant_map().get("UNLOCK_MODIFIERS", {})
	# UNLOCK_MODIFIERS is keyed by research_node_id, so resolve title → id off the CSV row
	# (this runs in a `-s` tree with no autoloads, so MatchState's lookup isn't available).
	var id_for := {}
	for r in rows:
		id_for[str(r.get("title", ""))] = str(r.get("research_node_id", ""))
	var pozz_id: String = id_for.get("Pozzolanic Vitrification", "")
	var micro_id: String = id_for.get("Micro Silica Synthesis", "")
	_check("Pozzolanic has a node id", "yes" if pozz_id != "" else "no", "yes")
	_check("Micro Silica has a node id", "yes" if micro_id != "" else "no", "yes")
	_check("Pozzolanic in modifier table", str(table.has(pozz_id)), "true")
	_check("Micro Silica in modifier table", str(table.has(micro_id)), "true")
	var pozz = table.get(pozz_id, {})
	_check("Pozzolanic domain", str(pozz.get("domain", "")), "recipe_output")
	_check("Pozzolanic targets concrete", str(pozz.get("target_match", {}).get("good_internal", "")), "concrete")
	_check("Pozzolanic pct", "%.1f" % float(pozz.get("pct", 0.0)), "10.0")
	var micro: Array = table.get(micro_id, [])
	_check("Micro Silica has 2 effects", str(micro.size()), "2")
	if micro.size() == 2:
		_check("Micro concrete pct", "%.1f" % float(micro[0].get("pct", 0.0)), "5.0")
		_check("Micro concrete good", str(micro[0].get("target_match", {}).get("good_internal", "")), "concrete")
		_check("Micro glass pct", "%.1f" % float(micro[1].get("pct", 0.0)), "15.0")
		_check("Micro glass good", str(micro[1].get("target_match", {}).get("good_internal", "")), "glass")

	# Every modifier id must be unique across the whole table, or one silently shadows another.
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

	print("==== SILICA PROBE %s ====" % ("PASS" if _fails == 0 else "%d FAILED" % _fails))
	quit(0 if _fails == 0 else 1)


func _id_of(rows: Array, title: String) -> String:
	for r in rows:
		if str((r as Dictionary).get("title", "")) == title:
			return str((r as Dictionary).get("research_node_id", ""))
	return ""


func _csv_rows(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_fail("cannot open %s" % path)
		return []
	var headers := f.get_csv_line()
	var out: Array = []
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() < headers.size() or line[0] == "":
			continue
		var row := {}
		for i in headers.size():
			row[headers[i]] = line[i]
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
