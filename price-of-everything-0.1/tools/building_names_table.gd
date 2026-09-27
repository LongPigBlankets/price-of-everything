extends Node
## Writes docs/building-names.md: every building and recipe with the name BuildingNaming gives it, beside the name it
## had before, for the owner to review. Run headless:
##   $G --headless --path . res://tools/building_names_table.tscn --quit-after 600

const BuildingNaming := preload("res://scripts/building_naming.gd")
const OUT := "res://docs/building-names.md"

## Names worth the owner's second look, by recipe id or, for a whole kind, by building internal name.
const FLAGS := {
	"eaf": "\"Arc Furnace\" shortens Electric Arc Furnace so the name stays at three or four words.",
	"high_tech_manufactory": "\"Manufactory\" drops \"High Tech\" to keep the names short.",
	"new_forest": "Forest names carry \"Biomass\", the only good a forest makes in the game.",
	"fracking_oil_well": "\"Fracking Oil Well\" rather than the type's \"Hydraulic Fracking Oil Wells\".",
	"offshore_oil_platform": "\"Oil Platform\": the sea already says offshore.",
	"battery": "Stores power and makes nothing, so it keeps its type name.",
	"heat_battery": "Stores heat and makes nothing, so it keeps its type name.",
	"water_recycling": "The type's display name is misspelt (\"Recyling\"). The building name spells it right.",
	"r_065": "The owner's example names a plain \"Motor Assembly Plant\", but all three motor recipes here are named processes, so each carries its own word. Axial Flux (the earliest research) could be the plain one.",
	"r_066": "See SynRM.",
	"r_203": "See SynRM.",
	"r_107": "Named by its main output, copper wiring, though it recycles electronic waste.",
	"r_108": "Named by its main output, biomass, though it recycles bio waste.",
	"r_223": "Floating is the qualifier. The owner's wind farm names otherwise kept.",
	"r_034": "Keeps the good's own word order, \"Construction Equipment EV\".",
	"r_033": "Keeps the good's own word order, \"Construction Equipment ICE\".",
	"r_018": "Sand is dug, not mined, but keeps the Mine word with its kind.",
	"r_019": "Limestone is quarried, but keeps the Mine word with its kind.",
}

func _ready() -> void:
	var lines: PackedStringArray = []
	lines.append("# Building names")
	lines.append("")
	lines.append("Every building and recipe with its name under the owner's convention (`docs/ds2-owner-decisions.md`, Construct):")
	lines.append("a building is named by what it makes, \"<qualifier> <output word> <building word>\", with its letter once it stands")
	lines.append("on a tile (\"Iron Furnace A\"). The qualifier appears only where several recipes of the same building make the same")
	lines.append("main output, and the plain recipe of such a group has none. The rule and its table of exceptions live in")
	lines.append("`scripts/building_naming.gd`. This file is written by `tools/building_names_table.tscn`. Regenerate it rather than editing by hand.")
	lines.append("")
	lines.append("A building type in a catalogue, before a recipe is chosen, keeps its type name (the Type column).")
	lines.append("Names shown here are without the letter. **Was** is the name the building had before, with letter A.")
	lines.append("Rows marked **check** carry a note for the owner.")
	lines.append("")
	var loaded := {}
	var buildings: Array = Catalog.all_buildings().duplicate()
	buildings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("id", "")) < str(b.get("id", "")))
	lines.append("## Buildings with recipes")
	lines.append("")
	lines.append("| Type | Recipe | Main output | Name | Was | Note |")
	lines.append("|---|---|---|---|---|---|")
	var no_recipe: Array = []
	var flagged := 0
	for bd: Dictionary in buildings:
		var bid := str(bd.get("id", ""))
		var internal := str(bd.get("internal_name", ""))
		var recipes: Array = Catalog.all_recipes_for_building(bid).duplicate()
		if recipes.is_empty():
			no_recipe.append(bd)
			continue
		recipes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ka := str(a.get("output_name", "")) + str(a.get("recipe_id", ""))
			var kb := str(b.get("output_name", "")) + str(b.get("recipe_id", ""))
			return ka < kb)
		for r: Dictionary in recipes:
			var rid := str(r.get("recipe_id", ""))
			loaded[rid] = true
			var out_id := str(r.get("output_name", ""))
			var output := str(Catalog.get_good_by_internal_name(out_id).get("display_name", out_id)) if out_id != "" else ""
			var note := str(FLAGS.get(rid, FLAGS.get(internal, "")))
			if note == "" and _no_plain_sibling(bid, r):
				note = "No recipe of this group is the plain one, so each carries its own word."
			if note != "":
				note = "**check** " + note
				flagged += 1
			lines.append("| %s | %s (%s) | %s | **%s** | %s | %s |" % [str(bd.get("display_name", bid)),
				str(r.get("display_name", "")), rid, output, BuildingNaming.name_for(bid, rid),
				_old_label(bid, rid), note])
	lines.append("")
	lines.append("## Buildings without recipes")
	lines.append("")
	lines.append("These keep their type name, with a letter where one stands on a tile (\"Port A\").")
	lines.append("")
	lines.append("| Type | Name |")
	lines.append("|---|---|")
	for bd: Dictionary in no_recipe:
		lines.append("| %s | **%s** |" % [str(bd.get("display_name", "")), BuildingNaming.name_for(str(bd.get("id", "")), "")])
	lines.append("")
	lines.append("## Recipes the game does not load")
	lines.append("")
	lines.append("`data/recipes_all.csv` rows the catalogue drops, because their building or one of their goods is not in the game.")
	lines.append("They have no name until they load. The rule will name them then.")
	lines.append("")
	lines.append("| Recipe | Building field | Main output |")
	lines.append("|---|---|---|")
	var f := FileAccess.open("res://data/recipes_all.csv", FileAccess.READ)
	var header := f.get_csv_line()
	var i_id := header.find("recipe_id")
	var i_name := header.find("display_name")
	var i_b := header.find("building_id")
	var i_out := header.find("output_1")
	var dormant := 0
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() <= i_out or row[i_id] == "" or loaded.has(row[i_id]):
			continue
		dormant += 1
		lines.append("| %s (%s) | %s | %s |" % [row[i_name], row[i_id], row[i_b], row[i_out]])
	lines.append("")
	FileAccess.open(OUT, FileAccess.WRITE).store_string("\n".join(lines))
	print("building_names_table: %d loaded recipes, %d flagged, %d without recipes, %d not loaded -> %s" % [
		loaded.size(), flagged, no_recipe.size(), dormant, OUT])
	get_tree().quit()

## True when this recipe shares its main output with others of its building and none of them is the plain one.
static func _no_plain_sibling(building_id: String, recipe: Dictionary) -> bool:
	var out_id := str(recipe.get("output_name", ""))
	var group: Array = Catalog.all_recipes_for_building(building_id).filter(
		func(o: Dictionary) -> bool: return str(o.get("output_name", "")) == out_id)
	if group.size() < 2 or str(Catalog.get_building(building_id).get("internal_name", "")) in BuildingNaming.NO_QUALIFIER_KINDS:
		return false
	for o: Dictionary in group:
		if BuildingNaming.qualifier_for(building_id, o) == "":
			return false
	return true

## The name before the owner's convention, for the Was column.
static func _old_label(building_id: String, recipe_id: String) -> String:
	var bd: Dictionary = Catalog.get_building(building_id)
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var on := str(recipe.get("output_name", ""))
	var output := str(Catalog.get_good_by_internal_name(on).get("display_name", on)) if on != "" else ""
	var internal := str(bd.get("internal_name", ""))
	if internal in ["industrial_factory", "consumer_factory", "chem_plant", "petro_refinery", "poly_plant",
			"power_plant", "onshore_wind_farm", "offshore_wind_farm", "solar_farm"]:
		var fam := BuildingNaming.family_name(internal, recipe, output)
		if internal == "chem_plant" and fam != "" and on != BuildingNaming.CHLOR_ALKALI_OUTPUT:
			fam = "%s Chemical Plant" % output
		if fam != "":
			return fam + " A"
	var type_name := str(bd.get("display_name", building_id))
	return ("%s %s A" % [type_name, "-"]) if output == "" else ("%s - %s - A" % [type_name, output])
