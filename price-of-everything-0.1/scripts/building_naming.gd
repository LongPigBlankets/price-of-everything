extends RefCounted
## Single source of truth for a building's full identifying name. Most kinds read
##   "<Building type> - <Output> - <Letter>"  e.g. "Mine - Coal - A"
## and the kinds the owner has named after what they do read without dashes (family_name):
##   factories        "<Main output> Factory A"            ("Motor Factory A")
##   chemical plants  "<Main output> Chemical Plant B", or "Chlor Alkali Complex A" on the chlor-alkali process
##   refineries       "Oil Processing Refinery A", or "Needle Coke Plant B" on the needle coke recipes
##   polymerisation   "<Main output> Plant C"               ("Plastics Plant C", "Rubber Plant A")
##   power plants     "<Fuel> Power Plant A"                ("Coal Power Plant A", "Gas Power Plant B")
##   wind and solar   "Wind Farm A", "Offshore Wind Farm A", "Solar Farm B"
## The letter distinguishes multiple buildings of the same kind on a tile. This
## is the name assigned when a building is first created (during the under-
## construction period) and shown in the building detail panel and chart tooltips.

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

static func letter_from_index(index: int) -> String:
	if index < _ALPHABET.length():
		return _ALPHABET.substr(index, 1)
	var first := floori(float(index) / float(_ALPHABET.length())) - 1
	return _ALPHABET.substr(first, 1) + _ALPHABET.substr(index % _ALPHABET.length(), 1)

## Full label from explicit parts.
static func label(building_id: String, recipe_id: String, letter_index: int) -> String:
	var bd: Dictionary = Catalog.get_building(building_id)
	var type_name := str(bd.get("display_name", building_id))
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var output := ""
	var on := str(recipe.get("output_name", ""))
	if on != "":
		output = str(Catalog.get_good_by_internal_name(on).get("display_name", on))
	var letter := letter_from_index(maxi(0, letter_index))
	var family := family_name(str(bd.get("internal_name", "")), recipe, output)
	if family != "":
		return "%s %s" % [family, letter]
	if output == "":
		return "%s - %s" % [type_name, letter]
	return "%s - %s - %s" % [type_name, output, letter]

## The owner's name for a kind of building on a recipe, without its letter, or "" for the kinds that keep
## "<Building type> - <Output>". `output` is the main output's display name.
static func family_name(internal: String, recipe: Dictionary, output: String) -> String:
	var out_id := str(recipe.get("output_name", ""))
	match internal:
		"industrial_factory", "consumer_factory":
			return ("%s Factory" % output) if output != "" else ""
		"chem_plant":
			if out_id == CHLOR_ALKALI_OUTPUT:
				return "Chlor Alkali Complex"
			return ("%s Chemical Plant" % output) if output != "" else ""
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


## A full label without the letter that tells one building of a kind from another: "Mine - Coal",
## "Motor Factory".
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
