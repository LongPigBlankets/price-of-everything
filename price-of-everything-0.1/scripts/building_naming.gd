extends RefCounted
## Single source of truth for a building's full identifying name:
##   "<Building type> - <Output> - <Letter>"  e.g. "Mine - Coal - A"
## The letter distinguishes multiple buildings of the same kind on a tile. This
## is the name assigned when a building is first created (during the under-
## construction period) and shown in the building detail panel and chart tooltips.

const _ALPHABET := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

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
	if output == "":
		return "%s - %s" % [type_name, letter]
	return "%s - %s - %s" % [type_name, output, letter]

## Full label for a building/project on a tile, deriving the letter from its order
## among the tile's buildings (built first, then under-construction projects).
static func label_for_tile(tile_id: String, instance_id: String, building_id: String, recipe_id: String) -> String:
	var idx := -1
	var blds: Array = MatchState.get_buildings_on_tile(tile_id)
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
