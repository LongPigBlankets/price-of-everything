extends RefCounted
## The construct panel's catalogue in DS2 (docs/construct-ds2-plan.md §4, the construction lot): under the crane,
## the black control plate (the search in its tab under the jib, the category keys in two rows below), then an
## enamel site board per building on the hoarding, two to a row: its icon printed as a blueprint on the navy
## field, its name and its price on an LED. A building opened shows its board across the width with its
## recipes hung under it as enamel tags on chains, each drawn out, condensed or expanded as the Construct
## setting says. The boards keep the names the tutorial looks up (BuildingCard_<id>, RecipeRow_<id>).
## A board's price is ConstructionRules.quote()'s for the building on the site, or with no site its fee and
## materials.

const BuildOrder := preload("res://scripts/construct_ds2/build_order.gd")
const Rules := preload("res://scripts/construction_rules.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

const S := 1.0 / 1.875
const E := 2.0 / 1.875
## layout.json construct_catplate: the plate at (80, 152) on the panel, its render's origin and size, the search
## glass and the key bed (x, y, width, key height, gap).
const PLATE := Vector2(1005.0, 306.0) * S
const PLATE_LAYER := Rect2(-8.0, -8.0, 1025.0, 328.0)
const SEARCH := Rect2(373.0, 21.0, 265.0, 50.0)
const KEYS := Rect2(18.0, 110.0, 969.0, 84.0)
const KEY_GAP := 10.0
## The category keys' two rows, as the study set them.
const KEY_ROWS := [["extraction", "refinery", "metallurgy", "electrochemistry", "farm_forests"],
	["power", "infrastructure", "water", "manufacturing"]]
## layout.json construct_card: the board (a horizontal three-slice), its navy field and the icon in it, where the
## words start, and the ends kept whole.
const CARD_H := 180.0 * S
const CARD_MARGIN := 6.0
## The render reaches 6 past the board on the left and top, 10 on the right and 12 below (its shadow).
const CARD_LAYER_GROW := Vector2(16.0, 18.0)
const CARD_RIGHT_ROOM := 10.0
const CARD_CAP_L := 206.0
const CARD_CAP_R := 46.0
const CARD_ICON := Rect2(38.0, 32.0, 116.0, 116.0)
const CARD_TEXT_X := 186.0
const CARD_GAP := 16.0 * S
## layout.json construct_tag: the tag, its render reaching up past its top by its chains, where its name and
## its recipe sit, and how far it hangs below what it hangs from.
const TAG := Vector2(1005.0, 250.0) * S
const TAG_LAYER := Rect2(-6.0, -64.0, 1023.0, 328.0)
const TAG_DROP := 40.0 * S
const TAG_NAME_Y := 52.0 * S
const TAG_ROW_Y := 156.0 * S
const NAVY := Color("#0b2340")
const SEMI: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const NAME_PX := 15
const TAG_NAME_PX := 16
const POUND_PX := 18
const MUTED := Color(0.72, 0.72, 0.72)
## The category keys' print: the latching key's own size, its words fitted.
const KEY_LABELS := {"farm_forests": "FARM FORESTS"}


## The control plate: the plate drawn under the search glass and the key bed; `search` (the panel's LineEdit)
## set into the glass; one latching key per category, `pick` called with its id when pressed.
static func control_plate(search: LineEdit, pick: Callable) -> Control:
	var p := Control.new()
	p.name = "CataloguePlate"
	p.custom_minimum_size = PLATE
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	p.draw.connect(func() -> void:
		var tex := Plate.tex("construct_catplate")
		if tex != null:
			p.draw_texture_rect(tex, Rect2(PLATE_LAYER.position * S, PLATE_LAYER.size * S), false))
	if search.get_parent() != null:
		search.get_parent().remove_child(search)
	search.position = SEARCH.position * S
	search.size = SEARCH.size * S
	search.custom_minimum_size = Vector2.ZERO
	search.flat = true
	var clear := StyleBoxEmpty.new()
	clear.content_margin_left = 8
	clear.content_margin_right = 6
	for s in ["normal", "focus", "read_only"]:
		search.add_theme_stylebox_override(s, clear)
	search.add_theme_font_override("font", SEMI)
	search.add_theme_font_size_override("font_size", 14)
	search.add_theme_color_override("font_color", Color("#4fe38a"))
	search.add_theme_color_override("caret_color", Color("#4fe38a"))
	search.add_theme_color_override("font_placeholder_color", DS.PALETTE["TEXT"])
	search.placeholder_text = "Search"
	p.add_child(search)
	# Centred on the glass whatever height the field settles at.
	var centre := (SEARCH.position.y + SEARCH.size.y * 0.5) * S
	search.resized.connect(func() -> void: search.position.y = centre - search.size.y * 0.5)
	search.size = SEARCH.size * S
	search.position.y = centre - search.size.y * 0.5
	var bed := VBoxContainer.new()
	bed.name = "CategoryKeys"
	bed.position = KEYS.position * S
	bed.size = Vector2(KEYS.size.x * S, 2.0 * KEYS.size.y * S + KEY_GAP * S)
	bed.add_theme_constant_override("separation", roundi(KEY_GAP * S))
	p.add_child(bed)
	for ids: Array in KEY_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", roundi(KEY_GAP * S))
		bed.add_child(row)
		for id: String in ids:
			var key: Control = LatchKey.new()
			key.name = "Filter_%s" % id
			var words := str(KEY_LABELS.get(id, id.to_upper()))
			key.set("text", words)
			key.size_flags_stretch_ratio = Parts.caption_width(words, 15) + 30.0
			key.connect("pressed", func() -> void: pick.call(id))
			row.add_child(key)
	return p


## Latches the key of the category shown and unlatches the rest.
static func show_filter(plate: Control, active: Dictionary) -> void:
	for key in plate.find_children("Filter_*", "", true, false):
		key.set("latched", active.has(str(key.name).trim_prefix("Filter_")))


## A building's site board, `width` wide: its blueprint icon, its name, its price on a red LED. Pressed, `on_press`.
## Dimmed when it cannot be built (no recipe here, or the money short), with the reason on its hover.
static func site_card(building: Dictionary, width: float, price: float, dim_reason: String, on_press: Callable) -> Button:
	var bid := str(building.get("id", ""))
	var card := SiteCard.new()
	card.name = "BuildingCard_%s" % bid
	card.custom_minimum_size = Vector2(width, CARD_H)
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	card.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	card.tooltip_text = dim_reason
	if dim_reason != "":
		card.modulate = MUTED
	card.pressed.connect(on_press)
	var icon := BuildOrder.BlueprintIcon.new(bid)
	icon.position = CARD_ICON.position * S
	icon.size = CARD_ICON.size * S
	card.add_child(icon)
	var name := Label.new()
	name.name = "Name"
	name.text = str(building.get("display_name", ""))
	name.add_theme_font_override("font", SEMI)
	name.add_theme_font_size_override("font_size", NAME_PX)
	name.add_theme_color_override("font_color", NAVY)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.position = Vector2(CARD_TEXT_X * S, 9.0)
	name.size = Vector2(width - CARD_TEXT_X * S - 12.0, 42.0)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name)
	var shown: Dictionary = MoneyFigure.screen(price, 2)
	var money := Parts.money(str(shown.figure), DS.PALETTE["DANGER"], 5, str(shown.suffix))
	money.name = "Price"
	var pound: Label = money.get_child(0)
	pound.add_theme_color_override("font_color", NAVY)
	pound.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.3))
	money.position = Vector2(CARD_TEXT_X * S - 2.0, CARD_H - 38.0)
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(money)
	return card


## A recipe's tag, hung under its building's opened board: the name the building will take, the recipe drawn out.
static func recipe_tag(building_id: String, recipe: Dictionary, condensed: bool, on_press: Callable) -> Button:
	var rid := str(recipe.get("recipe_id", ""))
	var tag := HungTag.new()
	tag.name = "RecipeRow_%s" % rid
	tag.custom_minimum_size = TAG
	tag.flat = true
	tag.focus_mode = Control.FOCUS_NONE
	tag.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tag.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	tag.tooltip_text = str(recipe.get("display_name", ""))
	tag.pressed.connect(on_press)
	var name := Label.new()
	name.name = "RecipeName"
	name.text = BuildingNaming.name_for(building_id, rid)
	name.add_theme_font_override("font", SEMI)
	name.add_theme_font_size_override("font_size", TAG_NAME_PX)
	name.add_theme_color_override("font_color", NAVY)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name.position = Vector2(0, TAG_NAME_Y - 12.0)
	name.size = Vector2(TAG.x, 24.0)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(name)
	# The recipe fits the tag under its name, inside the enamel's band.
	var room := Vector2(TAG.x - 48.0, 86.0)
	var row := BuildOrder.recipe_row(recipe, condensed, [], room)
	row.position = Vector2(0, TAG_ROW_Y - room.y * 0.5)
	row.size = Vector2(TAG.x, room.y)
	tag.add_child(row)
	return tag


## A board's price: the quote's total for the building on the site (with no site, its fee and its materials).
static func price(building_id: String, tile_id: String, tile_data: Dictionary, source: String) -> float:
	return float(Rules.quote(building_id, "", tile_id, tile_data, {"source": source, "buy_land": false}).get("total", 0.0))


## The site board's enamel, drawn as a horizontal three-slice at the render's scale.
class SiteCard extends Button:
	func _draw() -> void:
		var tex := Plate.tex("construct_card")
		if tex == null:
			return
		var m := CARD_MARGIN * S
		var dest := Rect2(Vector2(-m, -m), size + CARD_LAYER_GROW * S)
		var tw := float(tex.get_width())
		var th := float(tex.get_height())
		var cl := (CARD_CAP_L + CARD_MARGIN) * E
		var cr := (CARD_CAP_R + CARD_RIGHT_ROOM) * E
		var dl := cl / 2.0
		var dr := cr / 2.0
		draw_texture_rect_region(tex, Rect2(dest.position, Vector2(dl, dest.size.y)), Rect2(0, 0, cl, th))
		draw_texture_rect_region(tex, Rect2(dest.position + Vector2(dl, 0), Vector2(dest.size.x - dl - dr, dest.size.y)), Rect2(cl, 0, tw - cl - cr, th))
		draw_texture_rect_region(tex, Rect2(Vector2(dest.end.x - dr, dest.position.y), Vector2(dr, dest.size.y)), Rect2(tw - cr, 0, cr, th))


## The recipe tag's enamel and its chains, reaching up past its top to the board it hangs from.
class HungTag extends Button:
	func _draw() -> void:
		var tex := Plate.tex("construct_tag")
		if tex != null:
			draw_texture_rect(tex, Rect2(TAG_LAYER.position * S, TAG_LAYER.size * S), false)
