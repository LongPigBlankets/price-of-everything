extends "res://scripts/bdp_v3_plate.gd"
## Building Detail v3: the four main controls (Inputs, Outputs, Upgrade, Change recipes) on one worn
## steel plate, as approved in tools/button_mockup/cluster.html. Each control is a cream keycap with
## navy text next to a raised cream icon on the plate. The upgrade arrow glows green when the upgrade
## is available and is embossed like the other icons when it is not. A side that is entirely on the
## logistics intermediary (once Open Logistics Contracts is unlocked) shows a raised lorry after its
## label, and its key reads "Manage Logistics".
##
## configure() takes plain values; the panel computes them (see building_detail_panel_v2.gd). The
## static rules below are what those values mean, and are what the tests check.

const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingReadout := preload("res://scripts/building_readout.gd")
## The block's frame and its keys, in layout pixels (assets/ui/bdp_v3/layout.json).
const FRAME := Vector2(863, 379)
const KEYS := {
	"inputs": [Rect2(141, 62, 280, 104), Rect2(156.6, 77.6, 248.8, 72.8)],
	"outputs": [Rect2(563, 62, 280, 104), Rect2(578.6, 77.6, 248.8, 72.8)],
	"upgrade": [Rect2(141, 196, 280, 139), Rect2(156.6, 211.6, 248.8, 107.8)],
	"recipe": [Rect2(563, 196, 280, 139), Rect2(578.6, 211.6, 248.8, 107.8)],
}
const ALWAYS_RAISED: Array[String] = ["icon_input", "icon_output", "kicker_input", "kicker_output", "icon_recipe"]

func _init() -> void:
	super()
	name = "BdpV3Block"
	set_frame(FRAME)


## state: input_value, output_value (String); input_managed, output_managed (bool);
## upgrade_title, upgrade_detail, upgrade_tooltip (String), upgrade_lit (bool), upgrade_tip (a dot-matrix
## card, dot_card.gd; when set it replaces upgrade_tooltip);
## recipe_title, recipe_detail, recipe_tooltip (String), recipe_enabled (bool).
func configure(state: Dictionary) -> void:
	var lit := bool(state.get("upgrade_lit", false))
	var raised: Array[String] = ALWAYS_RAISED.duplicate()
	if bool(state.get("input_managed", false)):
		raised.append("lorry_input")
	if bool(state.get("output_managed", false)):
		raised.append("lorry_output")
	var back: Array[Texture2D] = [tex("block_plate")]
	for layer in raised:
		back.append(tex("block_shadow_" + layer))
	if not lit:
		back.append(tex("block_shadow_arrow"))
	for layer in raised:
		back.append(tex("block_" + layer))
	var front: Array[Texture2D] = [tex("block_arrow_lit" if lit else "block_arrow")]
	set_layers(back, tex("block_glow_arrow") if lit else null, front)

	for side in ["inputs", "outputs"]:
		var managed := bool(state.get("input_managed" if side == "inputs" else "output_managed", false))
		var value := "Manage Logistics" if managed else str(state.get("input_value" if side == "inputs" else "output_value", ""))
		_add_key(side, value_lines(value), true, true, str(state.get(side.trim_suffix("s") + "_tooltip", "")))
	_add_key("upgrade", two_lines(str(state.get("upgrade_title", "")), str(state.get("upgrade_detail", ""))), false,
		lit, str(state.get("upgrade_tooltip", "")), state.get("upgrade_tip", {}))
	_add_key("recipe", two_lines(str(state.get("recipe_title", "")), str(state.get("recipe_detail", ""))), false,
		bool(state.get("recipe_enabled", true)), str(state.get("recipe_tooltip", "")))


func _add_key(key: String, lines: Array, caret: bool, enabled: bool, tooltip: String, tip: Dictionary = {}) -> void:
	var r: Array = KEYS[key]
	set_key(key, r[0], r[1], tex("block_key_" + key), tex("block_key_%s_pressed" % key), lines, caret, enabled, tooltip, tip)


# --- rules ---------------------------------------------------------------------------------------

## A route summary on the value key: one line, or two when it carries a bracketed qualifier
## ("Tile stockpile (same tile)") or is already several lines (a split output; beyond two, the
## second line ends in an ellipsis and the Outputs sheet has the rest).
static func value_lines(value: String) -> Array:
	var face_h: float = KEYS.inputs[1].size.y
	var parts := value.split("\n", false)
	if parts.size() >= 2:
		var second := parts[1] + (" …" if parts.size() > 2 else "")
		return [{"text": parts[0], "y": 0.28, "size": face_h * 0.44}, {"text": second, "y": 0.72, "size": face_h * 0.44}]
	var cut := value.find("(")
	if cut > 0:
		return [{"text": value.substr(0, cut).strip_edges(), "y": 0.28, "size": face_h * 0.44},
			{"text": value.substr(cut), "y": 0.72, "size": face_h * 0.44}]
	return [{"text": value, "y": 0.5, "size": face_h * 0.52}]


static func two_lines(title: String, detail: String) -> Array:
	return [{"text": title, "y": 0.34, "size": 40.0}, {"text": detail, "y": 0.72, "size": 30.0, "semi": true}]


## "Construction Equipment" -> "Constructi...": ten characters, then an ellipsis from eleven on.
static func truncate10(good_name: String) -> String:
	return good_name.substr(0, 10) + "..." if good_name.length() > 10 else good_name


## The output gain of the next level, e.g. "+100% Output" for level 1 -> 2.
static func upgrade_detail(level: int) -> String:
	var now := BuildingLevels.mult("output", level)
	var next := BuildingLevels.mult("output", level + 1)
	return "+%d%% Output" % roundi((next / now - 1.0) * 100.0) if now > 0.0 else ""


## How many of the building's other recipes earn more per turn than its current one, by the panel's
## own net estimate (BuildingReadout.economics). Each recipe is valued on this building as it stands.
static func better_recipe_count(building: Dictionary) -> int:
	var bdata: Dictionary = Catalog.get_building(str(building.get("building_id", "")))
	var current := str(building.get("recipe_id", ""))
	var here := float(BuildingReadout.economics(building, Catalog.get_recipe(current), bdata).get("net", 0.0))
	var count := 0
	for recipe: Dictionary in Catalog.get_recipes_for_building(str(building.get("building_id", ""))):
		var rid := str(recipe.get("recipe_id", ""))
		if rid == current:
			continue
		var as_it := building.duplicate()
		as_it["recipe_id"] = rid
		if float(BuildingReadout.economics(as_it, recipe, bdata).get("net", 0.0)) > here:
			count += 1
	return count


## The display name of the first good the recipe makes.
static func main_output_name(recipe: Dictionary) -> String:
	var outs: Array = recipe.get("outputs", [])
	if outs.is_empty():
		return ""
	var good: Dictionary = Catalog.get_good(str((outs[0] as Dictionary).get("good_id", "")))
	return str(good.get("display_name", good.get("internal_name", "")))
