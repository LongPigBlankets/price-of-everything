extends RefCounted
## Single source of truth for a building's name. Every name follows the owner's convention (docs/ds2-owner-decisions.md,
## Construct): a building is named by what it makes, and carries its letter once it stands on a tile.
##   "<qualifier> <output word> <building word> <Letter>"
##   "Iron Furnace A", "Coal Mine B", "Steel Furnace", "HIsarna Steel Furnace", "SynRM Motor Assembly Plant"
## Farms and forests are named by their kind instead (KIND_NAMES): "Strip Farm", "Logging Forest A".
##
## The OUTPUT WORD is the main output's plain name, without the form word the building already implies
## ("Iron Ingots" makes "Iron Furnace", "Iron Ore" makes "Iron Mine"). Where the building's own word already says
## what it makes, the output is left out ("Water Pump", "Oil Well", "Hydroelectric Dam").
##
## The QUALIFIER is there only when several recipes of the same building make the same main output. It is a word or
## two from the recipe's name ("Basic Oxygen", "HIsarna"), taken by dropping the output's and the building's words and
## the generic process words ("Manufacturing", "Smelting"). The plain, basic recipe of such a group has none.
## QUALIFIERS overrides the derivation where it reads wrong; "" marks the plain recipe.
##
## The kinds the owner named first keep their own form (family_name): the factories ("Motor Factory A"), chemical
## plants ("Chlor Alkali Complex A"), refineries ("Oil Processing Refinery A"), polymerisation plants
## ("Plastics Plant C"), power plants ("Coal Power Plant A") and wind and solar ("Offshore Wind Farm A").
##
## A building TYPE before a recipe is chosen (a construct catalogue card, "made in" lines) keeps its type name,
## type_name(). A building with a recipe is named by name_for() and, on a tile, label_for_tile() / of().
## docs/building-names.md lists every name; tools/building_names_table.tscn writes it.

const _ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
## The chlor-alkali process's main output, and the refinery outputs of the needle coke line (the coke, and
## the graphite its calcination makes).
const CHLOR_ALKALI_OUTPUT := "chlorine"
const NEEDLE_COKE_OUTPUTS := ["pet_coke", "graphite"]
## A polymerisation plant's name by what it makes, where the good's own name is longer than the plant's.
const PLANT_WORDS := {"rubber": "Rubber"}
## A power plant's fuel, by a word in its recipe's name, in the order they are tried.
const POWER_FUELS := [["Needle Coke", "Coke"], ["Coal", "Coal"], ["Gas", "Gas"], ["Oil", "Oil"],
	["Hydrogen", "Hydrogen"], ["Waste", "Waste"]]
## The kinds whose recipes already tell them apart in their own form, so they take no qualifier.
const NO_QUALIFIER_KINDS := ["petro_refinery", "power_plant"]

## The word for each kind of building, by internal name. A kind missing here uses its type's display name.
const BUILDING_WORDS := {
	"mine": "Mine",
	"furnace": "Furnace",
	"eaf": "Electric Furnace",
	"assembly_plant": "Assembly Plant",
	"high_tech_manufactory": "Manufactory",
	"electrolyser": "Electrolyser",
	"recycling_plant": "Recycling Plant",
	"farm": "Farm",
	"new_forest": "Forest",
	"old_forest": "Forest",
	"desal": "Desalination Plant",
	"water_recycling": "Water Recycling Plant",
	"water_pump": "Water Pump",
	"oil_well": "Oil Well",
	"fracking_oil_well": "Fracking Oil Well",
	"offshore_oil_platform": "Oil Platform",
	"hydro_power_plant": "Hydroelectric Dam",
}
## Kinds whose word already says what they make, so the output is left out.
const OUTPUT_IMPLIED := ["desal", "water_recycling", "water_pump", "oil_well", "fracking_oil_well",
	"offshore_oil_platform", "hydro_power_plant"]
## A good's plain word where dropping " Ingots" / " Ore" is not enough.
const OUTPUT_WORDS := {
	"alloy_ingots": "Alloy Metal",
	"alloy_ore": "Alloy Metal",
	"basic_salt": "Salt",
	"refined_ree": "Rare Earth",
	"lithium_carbonate": "Lithium",
	"industrial_acids": "Acid",
}
## Form words a building's word implies, dropped from the end of an output's name.
const FORM_SUFFIXES := [" Ingots", " Ore"]
## Recipe words that describe the process in general and so never tell two recipes apart.
const GENERIC_WORDS := ["manufacturing", "manufacture", "production", "smelting", "making", "steelmaking",
	"glassmaking", "mining", "assembly", "process", "refining", "fabbing", "extraction", "generation", "power",
	"farming", "forestry", "electrolysis", "automated", "of", "and", "the"]
## Farms and forests are named by the kind of husbandry, not by what they make, whole: recipe id to name.
## Rows for recipes the game does not load yet are here so they are named when they do.
const KIND_NAMES := {
	# Farms
	"r_208": "Sustainable Farm",   # Sustainable Biomass Production
	"r_209": "Strip Farm",         # Strip Farming - Biomass
	"r_211": "Agrisolar Farm",     # Agri Solar Farming - Biomass
	"r_212": "Livestock Farm",     # Livestock Farming - Biomass
	"r_090": "Sustainable Farm",   # Sustainable Food Production
	"r_091": "Strip Farm",         # Strip Farming
	"r_092": "Sustainable Farm",   # Mixed Crop Sustainable Farming
	"r_093": "Agrisolar Farm",     # Agri Solar Farming
	"r_094": "Livestock Farm",     # Livestock Farming
	"r_168": "Sustainable Farm",   # Fabric Crops Farming, the plain counterpart of the intensive one
	"r_170": "Strip Farm",         # Intensive Fabric Crops Farming
	"r_169": "Sustainable Farm",   # Oil Crops Farming, the plain counterpart of the intensive one
	"r_171": "Strip Farm",         # Intensive Oil Crops Farming
	# Forests
	"r_213": "Logging Forest",     # Aggressive Logging - Biomass
	"r_214": "Sustainable Forest", # Sustainable Forestry - Biomass
	"r_215": "Gently Pruned Forest", # Gentle Pruning - Biomass
	"r_216": "Tourist Forest",     # National Park Tourism - Biomass
	"r_095": "Logging Forest",     # Aggressive Logging
	"r_096": "Sustainable Forest", # Sustainable Forestry
	"r_097": "Gently Pruned Forest", # Gentle Pruning
	"r_098": "Tourist Forest",     # National Park Tourism
}
## Qualifiers where derivation from the recipe's name reads wrong, by recipe id; "" is the plain recipe.
const QUALIFIERS := {
	# Furnace
	"r_050": "",                   # Aluminium (Hall Heroult) Smelting
	"r_232": "Carbochlorination",  # Bauxite Carbochlorination
	"r_007": "",                   # Copper Blistering
	"r_026": "",                   # Copper Pipe Hot Rolling
	"r_219": "Moulded",            # Copper Pipe Moulding
	"r_053": "",                   # Industrial Glassmaking
	"r_005": "",                   # Pig Iron Smelting
	# Arc furnace
	"r_084": "Carbothermic",       # Aluminium Direct Carbothermic Electrolysis
	"r_106": "Scrap",              # Scrap Recycling
	# Assembly plant
	"r_122": "",                   # Semiconductor Fabbing
	"r_089": "Hydrogen",           # Direct Injection Hydrogen Engines
	"r_205": "Automated",          # Heavy Vehicles Automated Manufacturing
	"r_073": "",                   # Large Vehicle Engine Manufacturing
	"r_207": "Electric",           # Heavy Electric Motor
	"r_065": "SynRM",              # SynRM Magnetless Motors
	"r_066": "Axial",              # Axial Flux Motors
	"r_060": "Perovskite",         # Durable Perovskite Solar Panels
	# High tech manufactory
	"r_123": "Fabless",            # Fabless Semiconductors
	"r_124": "3D Printed",         # Semiconductor 3D Printing
	"r_128": "Inert Atmosphere",   # Inert-Atmosphere Precision Components
	# Electrolyser
	"r_079": "",                   # Water Electrolysis
	"r_041": "",                   # Rare Earth Reduction
	# Factory
	"r_071": "",                   # ICE Engine Manufacturing
	# Chemical plant
	"r_116": "",                   # Generic Acid Production
	"r_081": "Fluidised Bed",      # Fluidised Bed Reactor + CZ Silicon
	# Oil platform
	"r_178": "",                   # Offshore Oil Extraction
}

static func letter_from_index(index: int) -> String:
	if index < _ALPHABET.length():
		return _ALPHABET.substr(index, 1)
	var first := floori(float(index) / float(_ALPHABET.length())) - 1
	return _ALPHABET.substr(first, 1) + _ALPHABET.substr(index % _ALPHABET.length(), 1)

## Full label from explicit parts: the name and the letter, "Coal Mine A".
static func label(building_id: String, recipe_id: String, letter_index: int) -> String:
	return "%s %s" % [name_for(building_id, recipe_id), letter_from_index(maxi(0, letter_index))]

## A building type's own name, for a catalogue before a recipe is chosen: "Furnace", "Mine".
static func type_name(building_id: String) -> String:
	return str(Catalog.get_building(building_id).get("display_name", building_id))

## A building's name on a recipe, without its letter: "Iron Furnace", "HIsarna Steel Furnace". With no recipe,
## the type's name.
static func name_for(building_id: String, recipe_id: String) -> String:
	var bd: Dictionary = Catalog.get_building(building_id)
	var internal := str(bd.get("internal_name", ""))
	var recipe: Dictionary = Catalog.get_recipe(recipe_id) if recipe_id != "" else {}
	if recipe.is_empty():
		return str(bd.get("display_name", building_id))
	if KIND_NAMES.has(recipe_id):
		return str(KIND_NAMES[recipe_id])
	var out_id := str(recipe.get("output_name", ""))
	var output := ""
	if out_id != "":
		output = str(Catalog.get_good_by_internal_name(out_id).get("display_name", out_id))
	var base := family_name(internal, recipe, output)
	if base == "":
		base = _plain_name(internal, str(bd.get("display_name", building_id)), out_id, output)
	var qualifier := qualifier_for(building_id, recipe) if internal not in NO_QUALIFIER_KINDS else ""
	return base if qualifier == "" else "%s %s" % [qualifier, base]

## A recipe's building name, without its letter, for a recipe row: "Basic Oxygen Steel Furnace".
static func name_for_recipe(recipe_id: String) -> String:
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	return name_for(str(recipe.get("building_id", "")), recipe_id)

## The name of a building instance or construction project dictionary, with its letter on its tile.
static func of(b: Dictionary) -> String:
	return label_for_tile(str(b.get("tile_id", "")), str(b.get("instance_id", "")), str(b.get("building_id", "")),
		str(b.get("recipe_id", "")))

## The owner's name for the kinds named first, without the letter, or "" for the rest. `output` is the main output's
## display name.
static func family_name(internal: String, recipe: Dictionary, output: String) -> String:
	var out_id := str(recipe.get("output_name", ""))
	match internal:
		"industrial_factory", "consumer_factory":
			return ("%s Factory" % _output_word(out_id, output)) if output != "" else ""
		"chem_plant":
			if out_id == CHLOR_ALKALI_OUTPUT:
				return "Chlor Alkali Complex"
			return ("%s Chemical Plant" % _output_word(out_id, output)) if output != "" else ""
		"petro_refinery":
			return "Needle Coke Plant" if out_id in NEEDLE_COKE_OUTPUTS else "Oil Processing Refinery"
		"poly_plant":
			return ("%s Plant" % str(PLANT_WORDS.get(out_id, output))) if output != "" else ""
		"power_plant":
			var recipe_name := str(recipe.get("display_name", ""))
			for pair: Array in POWER_FUELS:
				if recipe_name.contains(str(pair[0])):
					return "%s Power Plant" % pair[1]
			return "Power Plant"
		"onshore_wind_farm":
			return "Wind Farm"
		"offshore_wind_farm":
			return "Offshore Wind Farm"
		"solar_farm":
			return "Solar Farm"
	return ""

## "<output word> <building word>" for the kinds outside the first families.
static func _plain_name(internal: String, type_display: String, out_id: String, output: String) -> String:
	var word := str(BUILDING_WORDS.get(internal, type_display))
	if output == "" or internal in OUTPUT_IMPLIED:
		return word
	var out_word := _output_word(out_id, output)
	if out_word == "" or (" %s " % word.to_lower()).contains(" %s " % out_word.to_lower()):
		return word
	return "%s %s" % [out_word, word]

## The main output's plain word: "Iron" for Iron Ingots, "Salt" for Basic Salt.
static func _output_word(out_id: String, output: String) -> String:
	if OUTPUT_WORDS.has(out_id):
		return str(OUTPUT_WORDS[out_id])
	for suffix: String in FORM_SUFFIXES:
		if output.ends_with(suffix):
			return output.trim_suffix(suffix)
	return output

## The words that tell this recipe from the building's other recipes for the same main output, or "" when it is
## the only one, or the plain one.
static func qualifier_for(building_id: String, recipe: Dictionary) -> String:
	var rid := str(recipe.get("recipe_id", ""))
	var out_id := str(recipe.get("output_name", ""))
	if rid == "" or out_id == "":
		return ""
	var shared := false
	for other: Dictionary in Catalog.all_recipes_for_building(building_id):
		if str(other.get("recipe_id", "")) != rid and str(other.get("output_name", "")) == out_id:
			shared = true
			break
	if not shared:
		return ""
	if QUALIFIERS.has(rid):
		return str(QUALIFIERS[rid])
	return derive_qualifier(str(recipe.get("display_name", "")),
		str(Catalog.get_good_by_internal_name(out_id).get("display_name", out_id)),
		type_name(building_id) + " " + str(BUILDING_WORDS.get(str(Catalog.get_building(building_id).get("internal_name", "")), "")))

## A recipe name's distinctive words: "Basic Oxygen Steelmaking" gives "Basic Oxygen", "Steelmaking (Petro)" gives
## "Petro". Words of the output and the building and generic process words are dropped, as is anything after a
## " - " (the old "Strip Farming - Biomass" style).
static func derive_qualifier(recipe_name: String, output: String, building_words: String) -> String:
	var name := recipe_name
	var cut := name.find(" - ")
	if cut > 0:
		name = name.substr(0, cut)
	for ch: String in ["(", ")", "+", "-", ","]:
		name = name.replace(ch, " ")
	var drop: Dictionary = {}
	for w: String in GENERIC_WORDS:
		drop[w] = true
	for w: String in (output + " " + building_words).to_lower().split(" ", false):
		drop[w] = true
		drop[w + "s"] = true
		drop[w + "es"] = true
		if w.ends_with("y"):
			drop[w.trim_suffix("y") + "ies"] = true
		if w.ends_with("s"):
			drop[w.trim_suffix("s")] = true
	var kept: PackedStringArray = []
	for w: String in name.split(" ", false):
		if not drop.has(w.to_lower()):
			kept.append(w)
	return " ".join(kept)


## A full label without the letter that tells one building of a kind from another: "Coal Mine", "Motor Factory".
## Older names in the "Mine - Coal - A" form lose their last part the same way.
static func without_letter(full: String) -> String:
	var cut := full.rfind(" - ")
	if cut > 0:
		return full.substr(0, cut)
	cut = full.rfind(" ")
	if cut > 0 and _is_letter(full.substr(cut + 1)):
		return full.substr(0, cut)
	return full


static func _is_letter(word: String) -> bool:
	if word.length() < 1 or word.length() > 2:
		return false
	for ch in word:
		if not _ALPHABET.contains(ch):
			return false
	return true


## Full label for a building/project on a tile, deriving the letter from its order
## among the tile's buildings (built first, then under-construction projects).
static func label_for_tile(tile_id: String, instance_id: String, building_id: String, recipe_id: String) -> String:
	var idx := -1
	var blds: Array = BuildingState.get_buildings_on_tile(tile_id)
	for i in blds.size():
		if str(blds[i].get("instance_id", "")) == instance_id:
			idx = i
			break
	if idx == -1:
		var base := blds.size()
		var projs: Array = Construction.projects_on_tile(tile_id)
		for j in projs.size():
			if str(projs[j].get("instance_id", "")) == instance_id:
				idx = base + j
				break
	return label(building_id, recipe_id, maxi(0, idx))
