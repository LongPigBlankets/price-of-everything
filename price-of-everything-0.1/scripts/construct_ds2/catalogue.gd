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
const Parts := preload("res://scripts/ds2/parts.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")

const S := 1.0 / 1.875
const E := 2.0 / 1.875
## layout.json construct_catplate: the plate at (80, 152) on the panel, its render's origin and size, the search
## glass and the key bed (x, y, width, key height, gap).
const PLATE := Vector2(1005.0, 306.0) * S
const PLATE_LAYER := Rect2(-8.0, -8.0, 1025.0, 328.0)
const SEARCH := Rect2(447.0, 21.0, 191.0, 50.0)
const KEYS := Rect2(18.0, 110.0, 969.0, 84.0)
const KEY_GAP := 10.0
## The category keys' two rows, as the study set them.
const KEY_ROWS := [["extraction", "refinery", "metallurgy", "electrochemistry", "farm_forests"],
	["power", "infrastructure", "water", "manufacturing"]]
## The building card as a shipping container (owner): layout.json construct_container, the blue corrugated side
## drawn long and cropped to the card's width (its ends kept whole, its ribs never stretched), and
## construct_card_plate, the enamel plate bolted to its left end holding the icon, the name and the price.
const CARD_H := 180.0 * S
const BOX_LAYER := Rect2(-6.0, -6.0, 1023.0, 200.0)
const BOX_CAP := 44.0
const PLATE_AT := Vector2(36.0, 15.0)
const CARD_PLATE_LAYER := Rect2(-6.0, -6.0, 396.0, 168.0)
const PLATE_W := 380.0
## In the plate: the navy blueprint field and the icon in it, where the words start.
const CARD_FIELD := Rect2(16.0, 15.0, 120.0, 120.0)
const CARD_ICON_INSET := 10.0
const CARD_TEXT_X := 152.0
const CARD_GAP := 16.0 * S
## The hover glow on a recipe tag's diagram: the amber lamp glow, this strong at full, in and out this fast.
const HOVER_GLOW := 1.0
## The glow is added this many times at full: once reads faint over cream enamel.
const HOVER_PASSES := 2
const HOVER_TIME := 0.14
## layout.json construct_tag: the tag, its render reaching up past its top by its chains, the tab rising between
## the chains that carries the recipe's name (the owner: the name sits outside the diagram), the body below it that
## is the diagram's alone, and how far it hangs below what it hangs from.
const TAG := Vector2(1005.0, 266.0) * S
const TAG_LAYER := Rect2(-6.0, -64.0, 1023.0, 344.0)
const TAG_TAB := Rect2(92.0, 0.0, 821.0, 46.0)
const TAG_BODY := Rect2(0.0, 46.0, 1005.0, 220.0)
const TAG_DROP := 40.0 * S
## The room the recipe has in the body, inside the enamel's band.
const TAG_ROOM := Vector2(1005.0 * S - 48.0, 220.0 * S - 14.0)
const NAVY := Color("#0b2340")
const SEMI: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const NAME_PX := 15
## A card's name: two lines of it stand over the price, both within the icon tile's height.
const CARD_NAME_PX := 13
const CARD_NAME_LINE := 17
const TAG_NAME_PX := 16
const POUND_PX := 18
## A card that can't be built or paid for is grey (owner): its container and plate through the grey shader, its
## words and price in grey.
const GREY_SHADER := preload("res://scripts/construct_ds2/grey.gdshader")
const GREY_INK := Color("#5d6166")
const GREY_LED := Color("#9aa0a6")
## The price is white while the cash covers it this many times over (owner), red below.
const COMFORT := 2.0
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
	var grey := dim_reason != ""
	if grey:
		var m := ShaderMaterial.new()
		m.shader = GREY_SHADER
		card.material = m
	card.pressed.connect(on_press)
	var plate := PLATE_AT * S
	var field := Rect2(plate + CARD_FIELD.position * S, CARD_FIELD.size * S)
	var icon := BuildOrder.BlueprintIcon.new(bid)
	if grey:
		icon.modulate = Color(0.75, 0.75, 0.75)
	icon.position = field.position + Vector2.ONE * CARD_ICON_INSET * S
	icon.size = field.size - Vector2.ONE * 2.0 * CARD_ICON_INSET * S
	card.add_child(icon)
	var text_x := plate.x + CARD_TEXT_X * S
	var text_w := plate.x + PLATE_W * S - 10.0 - text_x
	var name := Label.new()
	name.name = "Name"
	name.text = str(building.get("display_name", ""))
	name.add_theme_font_override("font", SEMI)
	name.add_theme_font_size_override("font_size", CARD_NAME_PX)
	name.add_theme_constant_override("line_spacing", -3)
	name.add_theme_color_override("font_color", GREY_INK if grey else NAVY)
	name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name.max_lines_visible = 2
	name.position = Vector2(text_x, field.position.y - 3.0)
	name.size = Vector2(text_w, 2.0 * CARD_NAME_LINE)
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name)
	var shown: Dictionary = MoneyFigure.screen(price, 2)
	var money := Parts.money(str(shown.figure), GREY_LED if grey else price_colour(price, MatchState.money), 5, str(shown.suffix))
	money.name = "Price"
	var pound: Label = money.get_child(0)
	pound.add_theme_color_override("font_color", GREY_INK if grey else NAVY)
	pound.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.3))
	money.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(money)
	# The price's foot level with the foot of the icon's tile (owner).
	money.position = Vector2(text_x - 2.0, field.end.y - money.get_combined_minimum_size().y)
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
	name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name.clip_text = true
	name.position = TAG_TAB.position * S + Vector2(0, 3.0)
	name.size = TAG_TAB.size * S
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tag.add_child(name)
	# The recipe fills the body under the tab, inside the enamel's band.
	var row := BuildOrder.recipe_row(recipe, condensed, [], TAG_ROOM)
	var body := Rect2(TAG_BODY.position * S, TAG_BODY.size * S)
	row.position = Vector2(0, body.get_center().y - TAG_ROOM.y * 0.5)
	row.size = Vector2(TAG.x, TAG_ROOM.y)
	# Hovered, the diagram glows.
	var glow := HoverGlow.new(body)
	tag.add_child(glow)
	tag.mouse_entered.connect(func() -> void: glow.fade(true))
	tag.mouse_exited.connect(func() -> void: glow.fade(false))
	tag.add_child(row)
	return tag


## A price's colour against the cash: white while the cash covers it COMFORT times over, red below (owner).
static func price_colour(price: float, cash: float) -> Color:
	return DS.PALETTE["TEXT"] if cash >= COMFORT * price else DS.PALETTE["DANGER"]


## A board's price: the quote's total for the building on the site (with no site, its fee and its materials).
static func price(building_id: String, tile_id: String, tile_data: Dictionary, source: String) -> float:
	return float(Rules.quote(building_id, "", tile_id, tile_data, {"source": source, "buy_land": false}).get("total", 0.0))


## The card's container, cropped to the card's width (its ends whole, its ribs cropped, never stretched), and the
## plate bolted to its left end.
class SiteCard extends Button:
	func _draw() -> void:
		var box := Plate.tex("construct_container")
		if box != null:
			var dest := Rect2(BOX_LAYER.position * S, Vector2(size.x + (BOX_LAYER.size.x - 1005.0) * S, BOX_LAYER.size.y * S))
			var th := float(box.get_height())
			var cap := (BOX_CAP - BOX_LAYER.position.x) * E
			var dcap := cap / 2.0
			var mid := dest.size.x - 2.0 * dcap
			draw_texture_rect_region(box, Rect2(dest.position, Vector2(dcap, dest.size.y)), Rect2(0, 0, cap, th))
			draw_texture_rect_region(box, Rect2(dest.position + Vector2(dcap, 0), Vector2(mid, dest.size.y)), Rect2(cap, 0, mid * 2.0, th))
			draw_texture_rect_region(box, Rect2(Vector2(dest.end.x - dcap, dest.position.y), Vector2(dcap, dest.size.y)),
				Rect2(box.get_width() - cap, 0, cap, th))
		var plate := Plate.tex("construct_card_plate")
		if plate != null:
			draw_texture_rect(plate, Rect2((PLATE_AT + CARD_PLATE_LAYER.position) * S, CARD_PLATE_LAYER.size * S), false)


## A recipe tag's glow while hovered: the amber lamp glow added over its diagram.
class HoverGlow extends Control:
	var _area := Rect2()
	var strength := 0.0:
		set(v):
			strength = v
			queue_redraw()
	var _tween: Tween

	func _init(area: Rect2) -> void:
		name = "HoverGlow"
		_area = area
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_FULL_RECT)
		material = preload("res://scripts/bdp_v3_light.gd").glow_material()

	func fade(on: bool) -> void:
		if _tween != null and _tween.is_valid():
			_tween.kill()
		_tween = create_tween()
		_tween.tween_property(self, "strength", HOVER_GLOW if on else 0.0, HOVER_TIME).set_trans(Tween.TRANS_SINE)

	func _draw() -> void:
		if strength <= 0.0:
			return
		var tex := Plate.tex("lamp_glow_amber")
		if tex != null:
			for i in HOVER_PASSES:
				draw_texture_rect(tex, _area.grow_individual(-10.0, 10.0, -10.0, 10.0), false, Color(1, 1, 1, strength))


## The recipe tag's enamel and its chains, reaching up past its top to the board it hangs from.
class HungTag extends Button:
	func _draw() -> void:
		var tex := Plate.tex("construct_tag")
		if tex != null:
			draw_texture_rect(tex, Rect2(TAG_LAYER.position * S, TAG_LAYER.size * S), false)
