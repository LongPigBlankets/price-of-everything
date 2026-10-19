@tool
extends RefCounted
## The rows a demo build ships without, taken out of the data files at export. Kept rows are
## copied byte for byte. The rule matches what a demo run skips at load (Catalog,
## ResearchState), and tests/unit/test_demo_build.gd holds the two together:
##   buildings   DemoBuild.HIDDEN_BUILDING_IDS and RECYCLING_BUILDING_IDS
##   goods       DemoBuild.RECYCLING_GOOD_IDS (the waste goods)
##   recipes     made in one of those buildings, or making or consuming a waste good;
##               a waste by-product is cleared from the recipe instead
##   research    the Recycling branch, the Survey nodes, and the nodes ResearchState hides
##               in every build
##   missions    the boards switched off in every build (enabled: false)

const DemoBuild := preload("res://scripts/demo_build.gd")
const BUILDINGS := "res://data/Buildings - buildingsMVP.csv"
const GOODS := "res://data/Goods - goodsMVP.csv"
const RECIPES := "res://data/recipes_all.csv"
const RESEARCH := "res://data/research_unlocks.csv"
const PRESENTATION := "res://data/research_presentation.json"
const MISSION_BOARDS := "res://data/mission_boards.json"
const FILTERED := [BUILDINGS, GOODS, RECIPES, RESEARCH, PRESENTATION, MISSION_BOARDS]
const OUTPUT_SLOTS := 5


## The filtered text of a FILTERED file; any other path comes back unchanged.
static func filter(path: String, text: String) -> String:
	match path:
		BUILDINGS:
			return _keep_rows(text, func(row: Dictionary) -> bool:
				return not DemoBuild.is_gated_building(str(row.get("ID", ""))))
		GOODS:
			return _keep_rows(text, func(row: Dictionary) -> bool:
				return not DemoBuild.RECYCLING_GOOD_IDS.has(str(row.get("ID", ""))))
		RECIPES:
			var buildings := gated_building_names()
			var goods := gated_good_names()
			var alias: Dictionary = load("res://scripts/catalog.gd").BUILDING_ALIAS
			var kept := _keep_rows(text, func(row: Dictionary) -> bool:
				var building := str(row.get("building_id", "")).strip_edges()
				if buildings.has(alias.get(building, building)):
					return false
				for col in ["output_1", "input_1", "input_2", "input_3", "input_4", "input_5", "input_6"]:
					if goods.has(str(row.get(col, "")).strip_edges()):
						return false
				return true)
			return _rewrite_rows(kept, func(row: Dictionary) -> Dictionary:
				for i in range(2, OUTPUT_SLOTS + 1):
					if goods.has(str(row.get("output_%d" % i, "")).strip_edges()):
						row["output_%d" % i] = ""
						row["output_qty_%d" % i] = ""
				return row)
		RESEARCH:
			var dropped := gated_research_ids()
			return _keep_rows(text, func(row: Dictionary) -> bool:
				return not dropped.has(str(row.get("research_node_id", "")).strip_edges()))
		PRESENTATION:
			var parsed: Variant = JSON.parse_string(text)
			if not parsed is Dictionary:
				return text
			var rows: Dictionary = parsed
			for node_id in gated_research_ids():
				rows.erase(node_id)
			return JSON.stringify(rows, "  ") + "\n"
		MISSION_BOARDS:
			var doc: Variant = JSON.parse_string(text)
			if not doc is Dictionary or not (doc as Dictionary).get("boards") is Array:
				return text
			(doc as Dictionary)["boards"] = ((doc as Dictionary)["boards"] as Array).filter(
				func(board: Variant) -> bool: return not (board is Dictionary and board.get("enabled", true) == false))
			(doc as Dictionary).erase("_comment")
			return JSON.stringify(doc, "  ") + "\n"
	return text


## Internal names of the gated buildings, read from the buildings CSV.
static func gated_building_names() -> Dictionary:
	var out := {}
	for row in _rows(FileAccess.get_file_as_string(BUILDINGS)):
		if DemoBuild.is_gated_building(str(row.fields.get("ID", ""))):
			out[str(row.fields.get("internal_name", ""))] = true
	return out


## Internal names of the recycling goods, read from the goods CSV.
static func gated_good_names() -> Dictionary:
	var out := {}
	for row in _rows(FileAccess.get_file_as_string(GOODS)):
		if DemoBuild.RECYCLING_GOOD_IDS.has(str(row.fields.get("ID", ""))):
			out[str(row.fields.get("internal_name", ""))] = true
	return out


## Research nodes the demo leaves out: the Recycling branch and every always-hidden node.
static func gated_research_ids() -> Dictionary:
	var out: Dictionary = (load("res://scripts/research_state.gd").HIDDEN_RESEARCH_IDS as Dictionary).duplicate()
	for row in _rows(FileAccess.get_file_as_string(RESEARCH)):
		if DemoBuild.is_gated_research(str(row.fields.get("category", "")), str(row.fields.get("Action", ""))):
			out[str(row.fields.get("research_node_id", "")).strip_edges()] = true
	return out


static func _keep_rows(text: String, keep: Callable) -> String:
	var rows := _rows(text, true)
	if rows.is_empty():
		return text
	var out := PackedStringArray([rows[0].raw])
	for i in range(1, rows.size()):
		if rows[i].fields.is_empty() or keep.call(rows[i].fields):
			out.append(rows[i].raw)
	return "".join(out)


## Rows `change` alters are written again from their fields; untouched rows keep their bytes.
static func _rewrite_rows(text: String, change: Callable) -> String:
	var rows := _rows(text, true)
	if rows.is_empty():
		return text
	var header: PackedStringArray = rows[0].values
	var out := PackedStringArray([rows[0].raw])
	for i in range(1, rows.size()):
		var row: Dictionary = rows[i]
		if row.fields.is_empty():
			out.append(row.raw)
			continue
		var before: Dictionary = row.fields.duplicate()
		var after: Dictionary = change.call(row.fields.duplicate())
		if after == before:
			out.append(row.raw)
			continue
		var values: PackedStringArray = row.values.duplicate()
		for c in mini(header.size(), values.size()):
			values[c] = _csv_field(str(after.get(header[c].strip_edges(), values[c])))
		var ending := "\r\n" if row.raw.ends_with("\r\n") else ("\n" if row.raw.ends_with("\n") else "")
		out.append(",".join(values) + ending)
	return "".join(out)


static func _csv_field(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n") or value.contains("\r"):
		return "\"" + value.replace("\"", "\"\"") + "\""
	return value


## Rows of a CSV as {fields: {header: value}, values, raw: the row's original text with its line
## ending}. Handles quoted fields, doubled quotes and line breaks inside quotes. The header
## row comes first when include_header is true; blank rows have empty fields.
static func _rows(text: String, include_header := false) -> Array:
	var records: Array = []
	var fields := PackedStringArray()
	var field := ""
	var quoted := false
	var start := 0
	var i := 0
	var n := text.length()
	while i < n:
		var c := text[i]
		if quoted:
			if c == "\"":
				if i + 1 < n and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					quoted = false
			else:
				field += c
		elif c == "\"":
			quoted = true
		elif c == ",":
			fields.append(field)
			field = ""
		elif c == "\n" or c == "\r":
			if c == "\r" and i + 1 < n and text[i + 1] == "\n":
				i += 1
			fields.append(field)
			field = ""
			records.append({"values": fields, "raw": text.substr(start, i + 1 - start)})
			fields = PackedStringArray()
			start = i + 1
		else:
			field += c
		i += 1
	if start < n:
		fields.append(field)
		records.append({"values": fields, "raw": text.substr(start)})
	if records.is_empty():
		return []
	var header: PackedStringArray = records[0].values
	var out: Array = []
	if include_header:
		out.append({"fields": {}, "values": header, "raw": records[0].raw})
	for r in range(1, records.size()):
		var values: PackedStringArray = records[r].values
		var named := {}
		if not (values.size() == 1 and values[0].strip_edges() == ""):
			for c2 in mini(header.size(), values.size()):
				named[header[c2].strip_edges()] = values[c2]
		out.append({"fields": named, "values": values, "raw": records[r].raw})
	return out
