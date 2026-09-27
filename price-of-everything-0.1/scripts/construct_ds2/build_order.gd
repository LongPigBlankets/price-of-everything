extends RefCounted
## The construct panel's build order in DS2 (docs/construct-ds2-plan.md §4, the construction lot): one layout
## for every recipe, in the owner's order of priority.
##   Pinned: the site board lowered on the hook (the building's name raised on worn steel, its icon printed
##     flat as a blueprint on a navy enamel tile, the recipe on an enamel sign sunk into the board) and the
##     verdict on the site cabin's desk (the total and the cash after on LEDs, the turns to build on a drum
##     counter, when the materials arrive, the Build key), the seam under them. The Build key is a plain cream
##     key high in the verdict (the owner: a quick decision, not an armed one); refused, it prints red and a
##     press makes the part that blocks glow instead (`blocker_for`).
##   Scrolling: the site's requirements as lamps on the feeder pillar; the cost in the cabin; the materials
##     yard (each good on its pallet in its well, a label with what is on the tile and elsewhere, the
##     Materials from knob in the sixth bay); the outlook on the programme board; the land lot, last.
## Every figure and the refusal are ConstructionRules.quote()'s (`q`), the forecast BuildForecast's.

const Rules := preload("res://scripts/construction_rules.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const Nine := preload("res://scripts/bdp_v3_nine.gd")
const Section := preload("res://scripts/bdp_v3_section.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const Enamel := preload("res://scripts/bdp_v3_enamel.gd")
const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Parts := preload("res://scripts/tvp_v3/buildings_parts.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const InfrastructureInfo := preload("res://scripts/infrastructure_info.gd")
const MoneyFigure := preload("res://scripts/ds2/money_figure.gd")
const Metrics := preload("res://scripts/ds2/metrics.gd")
const Rotary := preload("res://scripts/rotary_selector.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildForecast := preload("res://scripts/build_forecast.gd")
const BuildForecastTable := preload("res://scripts/build_forecast_table.gd")

const S := 1.0 / 1.875
const E := 2.0 / 1.875
## layout.json construct_board: the board, its render's origin and size, the blueprint tile, the icon's inset
## on it, the enamel sign's recess and the name's place.
const BOARD := Vector2(1005.0, 336.0) * S
const BOARD_LAYER := Rect2(-8.0, -8.0, 1027.0, 360.0)
const BOARD_TILE := Rect2(24.0, 94.0, 216.0, 216.0)
const BOARD_ICON_INSET := 28.0
const BOARD_ENAMEL := Rect2(260.0, 94.0, 721.0, 216.0)
const BOARD_TITLE := Vector2(24.0, 8.0)
const BLUEPRINT_INK := Color("#e3ebf5")
## The recipe on the enamel: navy print, a good at 64 px (48 beside two others), the arrow's yellow bolt.
const ENAMEL_NAVY := Color("#0a2140")
const BOLT_YELLOW := Color("#f2c230")
## layout.json construct_pillar, construct_yard, construct_pallet, construct_lot, construct_slab, construct_stake,
## construct_tape.
const PILLAR := Vector2(1005.0, 132.0) * S
const PILLAR_LAYER := Rect2(-6.0, -6.0, 1023.0, 152.0)
const PILLAR_LAMP_X := [54.0, 494.0]
const YARD := Vector2(1005.0, 744.0) * S
const YARD_LAYER := Rect2(-6.0, -6.0, 1023.0, 764.0)
const YARD_PAD := 18.0
const YARD_GAP := 12.0
const YARD_ROWS := [206.0, 206.0, 272.0]
const PALLET := 176.0
const PALLET_LAYER := 206.0
const LABEL_H := 150.0
const LOT := Vector2(470.0, 206.0) * S
const LOT_LAYER := Rect2(-6.0, -6.0, 488.0, 226.0)
const SLAB_PITCH := 35.0
const SLAB := 30.0
const SLAB_LAYER := 50.0
const STAKE_LAYER := 40.0
const TAPE_W := 24.0
## The white plastic sheet (sheet_white, 9-slice) the labels and the programme board are moulded in.
const SHEET_MARGIN := 14.0 * S
const SHEET_CORNER := (14.0 + 40.0) * E
const NAVY_INK := Color("#0b2340")
const INK := {"ok": Color("#1d6b3a"), "warn": Color("#7a4a00"), "bad": Color("#8f1f19")}
## The Build key: the cabinet's cream key in a brass bezel (owner), at least this wide.
const BUILD_KEY_W := 112.0
## What a refused Build points at: a block's key to the part that glows (the money on the verdict, else the
## requirement's row on the feeder pillar; the land's blocks all point at its row).
const LAND_BLOCKS := ["full", "cannot_buy_land", "land_short", "terrain"]
## The materials' sources on the knob, as the Construct setting names them.
const SOURCES := [
	["middleman", "res://assets/icons/ui_icons/route_lorry.png", "Logistics Intermediary"],
	["market", "res://assets/icons/ui_icons/route_port.png", "Global market"],
	["same_tile", "res://assets/icons/ui_icons/ds2/source_this_tile.png", "This tile's stockpile"],
	["any_tile", "res://assets/icons/ui_icons/ds2/source_other_tiles.png", "Any tile with surplus"],
]
const KNOB_PX := 82.0
const SEMI: FontFile = preload("res://assets/fonts/IBMPlexSans-SemiBold.ttf")
const MEDIUM: FontFile = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")
const FLAT_SHADER := preload("res://scripts/construct_ds2/flat_print.gdshader")


## Fills the panel's pinned band and body with the build order for `q`.
static func build(panel: Control, q: Dictionary) -> void:
	var pinned: VBoxContainer = panel.get("_pinned")
	var content: VBoxContainer = panel.get("_content")
	var building: Dictionary = panel.get("_selected_building")
	var recipe: Dictionary = panel.get("_selected_recipe")
	var infra := recipe.is_empty()
	pinned.add_child(site_board(building, recipe))
	pinned.add_child(_gap(10))
	pinned.add_child(verdict(panel, q))
	pinned.add_child(LedgerV3.seam())
	content.add_theme_constant_override("separation", 0)
	content.add_child(_gap(10))
	content.add_child(_section("SITE REQUIREMENTS", requirements(panel, q)))
	content.add_child(_section("COST", cost(q)))
	# Roads, pipes and rails take no materials: no yard to stock.
	if not ((panel.get("_v3_ledger") as Dictionary).get("rows", []) as Array).is_empty():
		var materials := _section("MATERIALS", yard(panel, q))
		materials.name = "ConstructionMaterialsSection"
		content.add_child(materials)
	if infra:
		content.add_child(_section("LEVELS", levels(building)))
	else:
		var outlook := outlook(panel, q)
		if outlook != null:
			content.add_child(_section("OUTLOOK", outlook))
	if bool(q.get("site_known", false)) and not infra:
		content.add_child(_section("LAND", land(q)))
	content.add_child(_gap(8))


# --- the site board --------------------------------------------------------------------------------------

## The site board: the enamel recipe in its recess, the worn steel board over it, the name raised on the
## steel and the building's icon printed as a blueprint on its navy tile.
static func site_board(building: Dictionary, recipe: Dictionary) -> Control:
	var bid := str(building.get("id", ""))
	var rid := str(recipe.get("recipe_id", ""))
	var board := Control.new()
	board.name = "SiteBoard"
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.custom_minimum_size = BOARD
	var sign := enamel_recipe(recipe, BOARD_ENAMEL.size * S) if not recipe.is_empty() \
		else enamel_purpose(building, BOARD_ENAMEL.size * S)
	sign.position = BOARD_ENAMEL.position * S
	board.add_child(sign)
	var face := Control.new()
	face.name = "BoardFace"
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.set_anchors_preset(Control.PRESET_FULL_RECT)
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.draw.connect(func() -> void:
		var tex := Plate.tex("construct_board")
		if tex != null:
			face.draw_texture_rect(tex, Rect2(BOARD_LAYER.position * S, BOARD_LAYER.size * S), false))
	board.add_child(face)
	var name := BuildingNaming.name_for(bid, rid)
	if Title.can_show(name.to_upper()):
		var title: Control = Title.new()
		title.name = "BoardTitle"
		title.call("set_text", name.to_upper())
		title.position = BOARD_TITLE * S
		title.size = Vector2(BOARD.x - 2.0 * BOARD_TITLE.x * S, Title.line_height())
		board.add_child(title)
	else:
		var l := Parts.caption(name, 26)
		l.name = "BoardTitle"
		l.position = BOARD_TITLE * S
		board.add_child(l)
	var icon := BlueprintIcon.new(bid)
	icon.position = (BOARD_TILE.position + Vector2.ONE * BOARD_ICON_INSET) * S
	icon.size = (BOARD_TILE.size - Vector2.ONE * 2.0 * BOARD_ICON_INSET) * S
	board.add_child(icon)
	board.tooltip_text = str(recipe.get("display_name", ""))
	board.mouse_filter = Control.MOUSE_FILTER_PASS
	return board


## The recipe on an enamel sign `size` big: the inputs with their quantities, a plus between them, the navy
## arrow carrying the power it draws, the output larger. The sign's grunge keeps off the icons and the arrow.
static func enamel_recipe(recipe: Dictionary, size: Vector2) -> Control:
	var card := PanelContainer.new()
	card.name = "RecipeSign"
	card.custom_minimum_size = size
	card.size = size
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var enamel: Control = Enamel.new()
	card.add_child(enamel)
	var clear: Array[Control] = []
	card.add_child(recipe_row(recipe, false, clear, size - Vector2(20.0, 14.0)))
	enamel.call("watch", clear)
	return card


## Infrastructure's enamel sign: what it is for, printed navy (it has no recipe).
static func enamel_purpose(building: Dictionary, size: Vector2) -> Control:
	var card := PanelContainer.new()
	card.name = "PurposeSign"
	card.custom_minimum_size = size
	card.size = size
	card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(Enamel.new())
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_" + side, 22)
	card.add_child(pad)
	var words := _ink(InfrastructureInfo.purpose(InfrastructureInfo.key_for(building)), 16, NAVY_INK, true)
	words.name = "Purpose"
	words.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	words.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	words.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pad.add_child(words)
	return card


## Infrastructure's levels on the programme board, level by level across: what one tile carries a turn, how far
## goods go in a turn and what moving them costs (the router's own tables: EconomyConfig, TransportService).
static func levels(building: Dictionary) -> Control:
	var key := InfrastructureInfo.key_for(building)
	var sheet := PanelContainer.new()
	sheet.name = "LevelsBoard"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(14)
	sheet.add_theme_stylebox_override("panel", pad)
	sheet.draw.connect(func() -> void:
		Nine.paint(sheet, Plate.tex("sheet_white"), Rect2(Vector2.ZERO, sheet.size).grow(SHEET_MARGIN), SHEET_CORNER))
	if not InfrastructureInfo.has_level_stats(key):
		sheet.add_child(_ink("No levels yet.", 14, NAVY_INK))
		return sheet
	var grid := GridContainer.new()
	grid.name = "LevelsTable"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 6)
	sheet.add_child(grid)
	grid.add_child(_ink("", 14, NAVY_INK))
	for level in range(1, 4):
		var h := _ink("Level %d" % level, 14, NAVY_INK, true)
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(h)
	for row: Array in level_rows(key):
		var l := _ink(str(row[0]), 14, NAVY_INK)
		l.custom_minimum_size.x = 150
		grid.add_child(l)
		for v in row.slice(1):
			var c := _ink(str(v), 14, NAVY_INK, true)
			c.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_child(c)
	return sheet


## [label, level 1, level 2, level 3] rows for infrastructure `key`.
static func level_rows(key: String) -> Array:
	if key == "cables":
		var caps: Array = [key]
		for level in range(1, 4):
			caps.append("%d MW" % int(round(float(EconomyConfig.CABLE_POWER_CAP.get(level, 0)))))
		caps[0] = "Power/tile/turn"
		return [caps, ["Reach", "Network", "Network", "Network"], ["Transmission", "Free", "Free", "Free"]]
	var carry: Array = ["Units/tile/turn"]
	var reach: Array = ["Tiles/turn"]
	var cost: Array = ["Cost/unit"]
	for level in range(1, 4):
		var stats: Dictionary = InfrastructureInfo.level_stats(key, level)
		carry.append(str(int(round(TransportService.link_capacity(key, level)))))
		var r := EconomyConfig.infra_range_for_level(key, level)
		reach.append(str(r if r > 0 else Catalog.infra_range(key)))
		cost.append(str(stats.get("cost", "")).replace("–", " to ").replace(" / unit / turn", "").replace(" / unit / tile", "/tile"))
	return [carry, reach, cost]


## The recipe drawn out: the inputs, a plus between them, the navy arrow, the output(s). Expanded, each good
## carries its quantity and the arrow the power it draws; condensed (`condensed`), the bare icons and a plain
## arrow, as the Construct setting says. It fits `room` (fit_plan): one row while each side has two goods at most
## and they keep 48 px or more; a side of three or more in two rows of a grid, a side of one or two beside it
## drawn larger. Recipes run to six inputs and four outputs, seven in all; the grid takes up to six a side. `clear` collects the icons
## and the arrow (the enamel's grunge keeps off them).
static func recipe_row(recipe: Dictionary, condensed: bool, clear: Array[Control] = [], room := Vector2(536.0, 86.0)) -> HBoxContainer:
	var flow := recipe_flow(recipe)
	var inputs: Array = flow.inputs
	var outputs: Array = flow.outputs
	var power := 0 if condensed else int(flow.power_in)
	var arrow_w := RecipeArrow.width_for(power)
	var plan := fit_plan(inputs.size(), outputs.size(), arrow_w, room)
	var row := HBoxContainer.new()
	row.name = "RecipeDiagram"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", ROW_SEP)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_meta("plan", plan)
	var s := float(plan.icon)
	row.add_child(_side(inputs, s, bool(plan.grid_in), true, not condensed, clear))
	var arrow := RecipeArrow.new(power)
	row.add_child(arrow)
	clear.append(arrow)
	var so := float(plan.out_icon)
	row.add_child(_side(outputs, so, bool(plan.grid_out), false, not condensed, clear))
	return row


## The recipe's goods, every output included (RecipeDiagram.flow_from_recipe gives the first alone, which hides
## co-products: E-Waste Recycling's rubber, aluminium and alloy ingots, Chlor-Alkali's hydrogen).
static func recipe_flow(recipe: Dictionary) -> Dictionary:
	var side := func(list: Array) -> Array:
		var out: Array = []
		for g: Dictionary in list:
			out.append({"good_id": str(g.get("good_id", "")), "internal": str(g.get("internal_name", "")), "qty": int(g.get("qty", 0))})
		return out
	return {"inputs": side.call(recipe.get("inputs", [])), "outputs": side.call(recipe.get("outputs", [])),
		"power_in": int(recipe.get("energy_req", 0))}


const ROW_SEP := 6.0
const PLUS_W := 13.0
const GRID_GAP := 4.0
## The goods' sizes tried in one row, largest first (never under 48 px, the owner), then in a grid of two rows.
const ROW_SIZES := [64.0, 56.0, 48.0]
const GRID_SIZES := [56.0, 52.0, 48.0, 44.0, 40.0, 36.0, 32.0]


## How a recipe of `n_in` inputs and `n_out` outputs fits `room`: {icon, out_icon, grid_in, grid_out}, `icon` and
## `out_icon` the size of each side's goods. One row while each side has two goods at most and they keep 48 px
## (the owner); a side of three or more goes into two rows, and a side of one or two beside a grid stands larger:
## one good as tall as the grid (a good's full size at most), two at a grid cell's size and a bit.
static func fit_plan(n_in: int, n_out: int, arrow_w: float, room: Vector2) -> Dictionary:
	if n_in <= 2 and n_out <= 2:
		for s: float in ROW_SIZES:
			var so := s + 8.0 if n_out <= 1 else s
			var w := _row_width(n_in, s, true) + ROW_SEP + arrow_w + ROW_SEP + _row_width(n_out, so, false)
			if w <= room.x and so <= room.y:
				return {"icon": s, "out_icon": so, "grid_in": false, "grid_out": false}
	for s: float in GRID_SIZES:
		var tall := 2.0 * s + GRID_GAP
		if tall > room.y and s > GRID_SIZES[-1]:
			continue
		var grid_in := n_in >= 3 or (n_in == 2 and n_out <= 2)
		var grid_out := n_out >= 3
		var si := s if grid_in else _lone(n_in, s, tall)
		var so := s if grid_out else _lone(n_out, s, tall)
		var w_in := _grid_width(n_in, s) if grid_in else _row_width(n_in, si, true)
		var w_out := _grid_width(n_out, s) if grid_out else _row_width(n_out, so, false)
		if w_in + ROW_SEP + arrow_w + ROW_SEP + w_out <= room.x:
			return {"icon": si, "out_icon": so, "grid_in": grid_in, "grid_out": grid_out}
	var last: float = GRID_SIZES[-1]
	return {"icon": last, "out_icon": last, "grid_in": n_in >= 2, "grid_out": n_out >= 3}


## The size of a side of one or two goods standing beside a grid of cells `s`, the grid `tall`.
static func _lone(n: int, s: float, tall: float) -> float:
	if n <= 1:
		return minf(Metrics.GOOD_ICON, tall)
	return minf(64.0, s + 12.0)


static func _row_width(n: int, s: float, pluses: bool) -> float:
	if n <= 0:
		return 0.0
	var between := (PLUS_W + 2.0 * ROW_SEP) if pluses else ROW_SEP
	return n * s + (n - 1) * between


static func _grid_width(n: int, s: float) -> float:
	var cols := ceili(n / 2.0)
	return cols * s + (cols - 1) * GRID_GAP


## One side of the recipe: the goods in a row (a plus between inputs), or in two rows, the longer on top and
## the shorter centred under it (three goods read two over one).
static func _side(items: Array, s: float, grid: bool, pluses: bool, with_qty: bool, clear: Array[Control]) -> Control:
	if not grid:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", roundi(ROW_SEP))
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		for i in items.size():
			if i > 0 and pluses:
				h.add_child(_plus())
			var ic := _recipe_good(items[i], s, with_qty)
			h.add_child(ic)
			clear.append(ic)
		return h
	var rows := VBoxContainer.new()
	rows.name = "TwoRows"
	rows.add_theme_constant_override("separation", roundi(GRID_GAP))
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var top := ceili(items.size() / 2.0)
	for part: Array in [items.slice(0, top), items.slice(top)]:
		var line := HBoxContainer.new()
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		line.add_theme_constant_override("separation", roundi(GRID_GAP))
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for it: Dictionary in part:
			var ic := _recipe_good(it, s, with_qty)
			line.add_child(ic)
			clear.append(ic)
		rows.add_child(line)
	return rows


static func _recipe_good(item: Dictionary, px: float, with_qty := true) -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(px, px)
	slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slot.mouse_filter = Control.MOUSE_FILTER_PASS
	var gid := str(item.get("good_id", ""))
	slot.tooltip_text = Catalog.get_display_name(gid)
	var tex := GoodIcons.texture_for_size(gid, str(item.get("internal", "")), px)
	if tex != null:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture = tex
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tr)
	else:
		# A good with no icon yet: its name on a cream tile, so the recipe still says what it takes.
		var tile := PanelContainer.new()
		var st := StyleBoxFlat.new()
		st.bg_color = Color("#fbeac0")
		st.set_corner_radius_all(6)
		st.set_border_width_all(1)
		st.border_color = Color(0.043, 0.137, 0.25, 0.5)
		tile.add_theme_stylebox_override("panel", st)
		tile.set_anchors_preset(Control.PRESET_FULL_RECT)
		tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
		st.content_margin_left = 3
		st.content_margin_right = 3
		st.content_margin_top = 4
		st.content_margin_bottom = 20   # the quantity pill's corner
		var l := _ink(Catalog.get_display_name(gid), 9 if px < 60.0 else 10, NAVY_INK, true)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		tile.add_child(l)
		slot.add_child(tile)
	if with_qty:
		slot.add_child(Parts.pill(int(item.get("qty", 0)), px < 60.0))
	return slot


static func _plus() -> Label:
	var l := Label.new()
	l.text = "+"
	l.add_theme_font_override("font", SEMI)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", ENAMEL_NAVY)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- the verdict -----------------------------------------------------------------------------------------

## The verdict on the cabin desk: Total, Cash after and Turns to build over their screens, the guarded Build
## key and its word, and when the materials arrive under them.
static func verdict(panel: Control, q: Dictionary) -> Control:
	var desk: MarginContainer = Section.new()
	desk.name = "V3VerdictStrip"
	desk.set("style", "slab")
	var vb: VBoxContainer = desk.get("content")
	vb.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	vb.add_child(row)
	var total := float(q.get("total", 0.0))
	var after := float(q.get("cash_after", 0.0))
	var digits := maxi(_cells(total), _cells(after))
	var t := _figure("Total", total, DS.PALETTE["DANGER"], digits)
	t.name = "V3Total"
	row.add_child(t)
	var cash := _figure("Cash after", after, DS.PALETTE["OK"] if after >= 0.0 else DS.PALETTE["DANGER"], digits)
	cash.name = "CashAfter"
	cash.get_child(1).set_meta("blocker", "funds")
	row.add_child(cash)
	var turns := VBoxContainer.new()
	turns.name = "V3DurationBox"
	turns.add_theme_constant_override("separation", 4)
	turns.add_child(Parts.caption("Turns to build"))
	var n := int(q.get("build_turns", 0))
	turns.add_child(Parts.drum(n, str(n).length()))
	row.add_child(turns)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	var reason := _refusal(q)
	var width := maxf(BUILD_KEY_W, CreamKey.width_for("Build", "", false, false))
	var key: Button = CreamKey.make("BuildConfirmButton", "Build", "", width)
	key.set("rim", "brass")
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	key.tooltip_text = reason if reason != "" else _build_words(q)
	if reason != "":
		key.set("title_ink", CreamKey.RED_INK)
	# Refused, a press shows what blocks it; otherwise it builds, as Confirm always has.
	key.pressed.connect(func() -> void:
		if str(panel.call("_v3_confirm_block_reason")) != "":
			panel.call("flag_blocker")
		else:
			panel.call("_on_confirm_pressed"))
	row.add_child(key)
	var foot := _foot_line(q, reason)
	if foot != "":
		var l := Parts.body(foot)
		l.name = "V3ConfirmReason" if reason != "" else "MaterialsArrive"
		if reason != "":
			l.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
		vb.add_child(l)
	return desk


## The line under the verdict: why it cannot be built, else when the materials arrive, else where it goes.
static func _foot_line(q: Dictionary, reason: String) -> String:
	if reason != "":
		return reason
	if not bool(q.get("site_known", false)):
		return "The site is chosen on the map."
	var m := int(q.get("materials_turns", 0))
	if m > 0:
		return "Materials arrive in %d turn%s." % [m, "" if m == 1 else "s"]
	return ""


static func _build_words(q: Dictionary) -> String:
	return "Pick the site on the map." if not bool(q.get("site_known", false)) else "Starts construction on this tile."


## The part a refused build points at for block `key`: "funds" for the money, "land" for the land's blocks,
## else the block's own requirement row.
static func blocker_for(key: String) -> String:
	if key in LAND_BLOCKS:
		return "land"
	return key


## The quote's first block, which refuses the build.
static func _refusal(q: Dictionary) -> String:
	var blocks: Array = q.get("blocks", [])
	return str((blocks[0] as Dictionary).get("text", "")) if not blocks.is_empty() else ""


static func _figure(caption: String, value: float, colour: Color, digits: int) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.add_child(Parts.caption(caption))
	vb.add_child(_money(value, colour, digits))
	return vb


static func _money(value: float, colour: Color, digits: int, whole := false) -> HBoxContainer:
	var shown: Dictionary = MoneyFigure.screen(value, 0 if whole else 2)
	return Parts.money(str(shown.figure), colour, digits, str(shown.suffix))


static func _cells(value: float, whole := false) -> int:
	return MoneyFigure.cells(str(MoneyFigure.screen(value, 0 if whole else 2).figure))


# --- requirements ----------------------------------------------------------------------------------------

## The site's requirements as lamps on the feeder pillar, two a pillar: the site, the land, the pipes and
## cables it needs, and every other warning or block the quote carries (funds are the Build key's).
static func requirements(panel: Control, q: Dictionary) -> Control:
	var rows := requirement_rows(panel, q)
	var vb := VBoxContainer.new()
	vb.name = "RequirementGrid"
	vb.add_theme_constant_override("separation", 8)
	# Two lamps a pillar; a row with a key of its own (Buy land) takes a pillar to itself.
	var pair: Array = []
	for r: Dictionary in rows:
		if r.has("action"):
			if not pair.is_empty():
				vb.add_child(_pillar(pair))
				pair = []
			vb.add_child(_pillar([r]))
			continue
		pair.append(r)
		if pair.size() == 2:
			vb.add_child(_pillar(pair))
			pair = []
	if not pair.is_empty():
		vb.add_child(_pillar(pair))
	return vb


## [{key, tone, title, detail}] for the pillar, in order: the site, the land, the links it needs, the rest.
static func requirement_rows(panel: Control, q: Dictionary) -> Array:
	var out: Array = []
	var blocks: Array = q.get("blocks", [])
	var warnings: Array = q.get("warnings", [])
	var said := {}
	if not bool(q.get("site_known", false)):
		out.append({"key": "site", "tone": "", "title": "Site", "detail": "Chosen on the map"})
	else:
		var lp: Dictionary = q.get("land_plan", {})
		var land_block := _find(blocks, ["full", "cannot_buy_land", "land_short", "terrain"])
		if not land_block.is_empty():
			var row := {"key": "land", "tone": "bad", "title": "Land", "detail": str(land_block.text)}
			# Short, with land for sale here to cover it: the player can buy it for this build.
			var land: Dictionary = panel.get("_v3_land")
			if bool(land.get("purchasable", false)) and not bool(panel.get("_buy_land_wanted")):
				row.detail = "Short %d land. Buys %d for %s." % [int(land.get("short", 0)), int(land.get("units", 0)), MoneyFigure.text(float(land.get("cost", 0.0)))]
				row["action"] = Callable(panel, "buy_land")
				row["action_title"] = "Buy land"
			out.append(row)
			said[str(land_block.key)] = true
		elif bool(lp.get("will_buy", false)):
			out.append({"key": "land", "tone": "warn", "title": "Land",
				"detail": "Buys %d land for %s" % [int(lp.get("units", 0)), MoneyFigure.text(float(lp.get("cost", 0.0)))]})
			said["buys_land"] = true
		else:
			out.append({"key": "land", "tone": "ok", "title": "Land", "detail": "Takes %d of %d free" % [int(lp.get("needed", 0)), int(lp.get("free", 0))]})
		var seen := {}
		for need: Dictionary in Rules.site_needs(panel.get("_selected_recipe"), str(q.get("tile_id", ""))):
			var k := str(need.get("infra_key", ""))
			if k == "" or seen.has(k):
				continue
			seen[k] = true
			var ok := bool(need.get("satisfied", false))
			out.append({"key": k, "tone": "ok" if ok else "warn", "title": _infra_word(k), "detail": "In place" if ok else "Missing"})
			said["needs_" + k] = true
	for b: Dictionary in blocks:
		var k := str(b.get("key", ""))
		if said.has(k) or k == "funds":
			continue
		out.append({"key": k, "tone": "bad", "title": _block_word(k), "detail": str(b.get("text", ""))})
	for w: Dictionary in warnings:
		var k := str(w.get("key", ""))
		if said.has(k) or k in ["site_unknown", "buys_land", "needs_cables", "needs_pipes", "needs_reinf_pipes"]:
			continue
		out.append({"key": k, "tone": "warn", "title": _block_word(k), "detail": str(w.get("text", ""))})
	return out


static func _find(list: Array, keys: Array) -> Dictionary:
	for d: Dictionary in list:
		if str(d.get("key", "")) in keys:
			return d
	return {}


static func _infra_word(key: String) -> String:
	match key:
		"cables":
			return "Cables"
		"pipes":
			return "Pipes"
		"reinf_pipes":
			return "Reinforced pipes"
	return key.capitalize()


static func _block_word(key: String) -> String:
	match key:
		"tutorial_area":
			return "Tutorial"
		"tendering":
			return "Tendering"
		"deposit", "blind_deposit":
			return "Deposit"
		"requirement":
			return "Requirement"
		"already_built", "in_progress":
			return "Already here"
		"materials_short", "no_surplus", "source_changed":
			return "Materials"
		"density":
			return "Planning"
		"intermittent":
			return "Power"
	return key.capitalize()


## One feeder pillar with up to two lamps and their words.
static func _pillar(rows: Array) -> Control:
	var p := Control.new()
	p.name = "FeederPillar"
	p.custom_minimum_size = PILLAR
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	p.draw.connect(func() -> void:
		var tex := Plate.tex("construct_pillar")
		if tex != null:
			p.draw_texture_rect(tex, Rect2(PILLAR_LAYER.position * S, PILLAR_LAYER.size * S), false))
	for i in rows.size():
		var r: Dictionary = rows[i]
		var line := HBoxContainer.new()
		line.name = "Requirement_%s" % str(r.key)
		line.set_meta("blocker", str(r.key))
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lamp: Control = Lamp.new()
		lamp.name = "RequirementIcon"
		lamp.set("lamp_scale", 0.85)
		lamp.call("set_tone", str(r.tone))
		line.add_child(lamp)
		var words := VBoxContainer.new()
		words.add_theme_constant_override("separation", 0)
		var t := Parts.body(str(r.title))
		t.name = "RequirementCaption"
		t.add_theme_font_override("font", SEMI)
		t.autowrap_mode = TextServer.AUTOWRAP_OFF
		words.add_child(t)
		var d := Parts.body(str(r.detail))
		d.name = "RequirementDetail_%s" % str(r.key)
		d.custom_minimum_size.x = (PILLAR_LAMP_X[1] - PILLAR_LAMP_X[0] - 70.0) * S if rows.size() > 1 else 200.0
		d.max_lines_visible = 2
		words.add_child(d)
		line.add_child(words)
		if r.has("action"):
			var act: Button = CreamKey.make("RequirementAction_%s" % str(r.key), str(r.action_title), "", CreamKey.width_for(str(r.action_title), "", false, false, 0.8), false, false, 0.8)
			act.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			act.pressed.connect(r.action)
			line.add_child(act)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.position = Vector2(PILLAR_LAMP_X[i] * S - 14.0, 8.0)
		# One row alone spans the pillar up to its vents; two share it.
		var span := (PILLAR_LAMP_X[1] - PILLAR_LAMP_X[0]) * S - 10.0 if rows.size() > 1 else PILLAR.x - PILLAR_LAMP_X[0] * S - 64.0
		line.size = Vector2(span, PILLAR.y - 16.0)
		line.alignment = BoxContainer.ALIGNMENT_CENTER
		p.add_child(line)
	return p


# --- cost ------------------------------------------------------------------------------------------------

## The cost in the site cabin: the materials in whole pounds, the fee, the land and the total, one screen width.
static func cost(q: Dictionary) -> Control:
	var cabin: MarginContainer = Section.new()
	cabin.name = "CostCabin"
	cabin.set("style", "slab")
	var vb: VBoxContainer = cabin.get("content")
	vb.add_theme_constant_override("separation", 8)
	# Only what informs: no materials line for what takes none, no land line before a site is chosen.
	var lines: Array = []
	if float(q.get("materials", 0.0)) > 0.0:
		lines.append(["Materials", float(q.get("materials", 0.0)), true])
	lines.append(["Fee", float(q.get("fee", 0.0)), false])
	if bool(q.get("site_known", false)):
		lines.append(["Land", float(q.get("land", 0.0)), false])
	var total := float(q.get("total", 0.0))
	var digits := _cells(total)
	for l: Array in lines:
		digits = maxi(digits, _cells(float(l[1]), bool(l[2])))
	for l: Array in lines:
		vb.add_child(_cost_line(str(l[0]), float(l[1]), digits, bool(l[2]), false))
	var rule := Control.new()
	rule.custom_minimum_size = Vector2(0, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rule.draw.connect(func() -> void:
		rule.draw_rect(Rect2(0, 0, rule.size.x, 1), Color(0, 0, 0, 0.55))
		rule.draw_rect(Rect2(0, 1.5, rule.size.x, 1), Color(0.82, 0.85, 0.9, 0.28)))
	vb.add_child(rule)
	vb.add_child(_cost_line("Total", total, digits, false, true))
	return cabin


static func _cost_line(word: String, value: float, digits: int, whole: bool, bold: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Cost_%s" % word
	var l := Parts.body(word)
	if bold:
		l.add_theme_font_override("font", SEMI)
	row.add_child(l)
	row.add_child(_money(value, DS.PALETTE["DANGER"], digits, whole))
	return row


# --- materials -------------------------------------------------------------------------------------------

## The materials yard: two columns of three bays on one gravel laydown; a good on its pallet in each of the
## first five (its well, its quantity, and a white label with what is on the tile and elsewhere), the knob
## that picks where they come from in the sixth.
static func yard(panel: Control, q: Dictionary) -> Control:
	var y := Control.new()
	y.name = "MaterialsYard"
	y.custom_minimum_size = YARD
	y.mouse_filter = Control.MOUSE_FILTER_PASS
	y.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var ledger: Dictionary = panel.get("_v3_ledger")
	var rows: Array = ledger.get("rows", [])
	y.draw.connect(func() -> void:
		var ground := Plate.tex("construct_yard")
		if ground != null:
			y.draw_texture_rect(ground, Rect2(YARD_LAYER.position * S, YARD_LAYER.size * S), false)
		var pallet := Plate.tex("construct_pallet")
		if pallet != null:
			for i in mini(rows.size(), 5):
				var b := _bay(i)
				var at := Vector2(b.position.x, b.position.y + (b.size.y - PALLET) * 0.5) - Vector2.ONE * 10.0
				y.draw_texture_rect(pallet, Rect2(at * S, Vector2.ONE * PALLET_LAYER * S), false))
	for i in mini(rows.size(), 5):
		var r: Dictionary = rows[i]
		var b := _bay(i)
		var well := Parts.good_in_well(str(r.good_id), int(r.need), str(r.name))
		well.name = "Material_%s" % str(r.good_id)
		var centre := Vector2(b.position.x + PALLET * 0.5, b.position.y + b.size.y * 0.5) * S
		well.position = centre - Vector2.ONE * Metrics.GOOD_ICON * 0.5
		y.add_child(well)
		var label := _label(str(r.name), int(r.get("have", 0)), int(r.get("elsewhere", 0)))
		var lw := b.size.x - PALLET - 16.0 - 12.0
		label.position = Vector2(b.position.x + PALLET + 16.0, b.position.y + (b.size.y - LABEL_H) * 0.5) * S
		label.size = Vector2(lw, LABEL_H) * S
		label.custom_minimum_size = label.size
		y.add_child(label)
	var knob_bay := _bay(5)
	var box: MarginContainer = Section.new()
	box.name = "MaterialsFrom"
	box.set("style", "slab")
	box.position = knob_bay.position * S
	box.size = knob_bay.size * S
	box.custom_minimum_size = knob_bay.size * S
	var vb: VBoxContainer = box.get("content")
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	var centre_box := CenterContainer.new()
	centre_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre_box.add_child(source_knob(panel))
	vb.add_child(centre_box)
	y.add_child(box)
	return y


## A bay's rectangle in the yard (layout px).
static func _bay(i: int) -> Rect2:
	var col := i % 2
	var row := i / 2
	var col_w := (YARD.x / S - 2.0 * YARD_PAD - YARD_GAP) * 0.5
	var top := YARD_PAD
	for k in row:
		top += float(YARD_ROWS[k]) + YARD_GAP
	return Rect2(YARD_PAD + col * (col_w + YARD_GAP), top, col_w, float(YARD_ROWS[row]))


## A good's white label: its name, and how many are on this tile and elsewhere.
static func _label(name: String, on_tile: int, elsewhere: int) -> Control:
	var sheet := PanelContainer.new()
	sheet.name = "MaterialLabel"
	var pad := StyleBoxEmpty.new()
	pad.content_margin_left = 8
	pad.content_margin_right = 8
	pad.content_margin_top = 6
	pad.content_margin_bottom = 6
	sheet.add_theme_stylebox_override("panel", pad)
	sheet.draw.connect(func() -> void:
		Nine.paint(sheet, Plate.tex("sheet_white"), Rect2(Vector2.ZERO, sheet.size).grow(SHEET_MARGIN), SHEET_CORNER))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	sheet.add_child(vb)
	var n := _ink(name, 14, NAVY_INK, true)
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 60
	n.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(n)
	vb.add_child(_ink_pair("On tile", str(on_tile)))
	vb.add_child(_ink_pair("Elsewhere", str(elsewhere)))
	return sheet


static func _ink(text: String, px: int, colour: Color, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", SEMI if bold else MEDIUM)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _ink_pair(word: String, figure: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	var l := _ink(word, 13, NAVY_INK)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var f := _ink(figure, 13, NAVY_INK, true)
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(f)
	return row


## The Materials from knob: the four sources on its arc, those the research has not opened greyed.
static func source_knob(panel: Control) -> Control:
	var current := str(panel.call("_current_material_source"))
	var intermediary := str(MatchState.ruleset.get("logistics_model", "")) == "middleman_v1"
	var options: Array = []
	for spec: Array in SOURCES:
		var id := str(spec[0])
		if id == "middleman" and not ResearchState.logistics_progression_active():
			continue
		var enabled := true
		if intermediary and id == "market":
			enabled = ResearchState.global_trade_license_available()
		elif intermediary and id in ["same_tile", "any_tile"]:
			enabled = ResearchState.open_logistics_contracts_available()
		options.append({"id": id, "icon": load(str(spec[1])), "name": str(spec[2]), "enabled": enabled})
	var knob: Control = Rotary.new()
	knob.name = "MaterialsKnob"
	knob.set("knob_size", KNOB_PX)
	knob.set("option_plates", true)
	knob.set("option_scale", 0.9)
	knob.set("label_gap", 6.0)
	knob.set("option_ink", Color("#f4f1e8"))
	knob.set("label", "Materials from")
	knob.set("label_colour", DS.PALETTE["TEXT"])
	knob.set("options", options)
	for i in options.size():
		if str(options[i].id) == current:
			knob.call("set_value_no_signal", i + 1)
	knob.connect("value_changed", func(v: int) -> void:
		var o: Dictionary = options[v - 1]
		if bool(o.enabled):
			panel.call("pick_material_source", str(o.id))
		else:
			for i in options.size():
				if str(options[i].id) == current:
					knob.call("set_value_no_signal", i + 1))
	return knob


# --- outlook ---------------------------------------------------------------------------------------------

## The outlook on the programme board: the payback, the turns ahead with their cash in the light surface's
## inks, and the buffer to keep before the first sales. Only with a site; the demo shows the payback alone.
static func outlook(panel: Control, _q: Dictionary) -> Control:
	var tile := str(panel.get("_locked_tile_id"))
	var f: Dictionary = panel.get("_v3_forecast")
	if tile == "" or (f.get("phases", []) as Array).is_empty():
		return null
	var sheet := PanelContainer.new()
	sheet.name = "ProgrammeBoard"
	var pad := StyleBoxEmpty.new()
	pad.set_content_margin_all(14)
	sheet.add_theme_stylebox_override("panel", pad)
	sheet.draw.connect(func() -> void:
		Nine.paint(sheet, Plate.tex("sheet_white"), Rect2(Vector2.ZERO, sheet.size).grow(SHEET_MARGIN), SHEET_CORNER))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	sheet.add_child(vb)
	var band: Dictionary = BuildForecast.payback_band(float(f.get("steady_net", 0.0)), bool(f.get("no_supply", false)))
	var head := _ink("Payback %s" % str(band.text).replace("–", " to "), 17, NAVY_INK, true)
	head.name = "ForecastPayback"
	vb.add_child(head)
	if BuildForecastTable.show_balance_impact():
		var grid := GridContainer.new()
		grid.name = "V3CashTimeline"
		grid.columns = 3
		grid.add_theme_constant_override("h_separation", 16)
		grid.add_theme_constant_override("v_separation", 4)
		var no_supply := bool(f.get("no_supply", false))
		for phase: Dictionary in f.get("phases", []):
			if str(phase.kind) == "building":
				continue
			_timeline_row(grid, "Turn " + str(phase.range).replace("t", "").trim_suffix(" onwards"),
				str(BuildForecastTable.PHASE_NAMES.get(str(phase.kind), phase.label)), float(phase.per_turn), no_supply)
		_timeline_row(grid, "Turn %d onwards" % int(f.get("first_selling_turn", 0)), "Stable production", float(f.get("steady_net", 0.0)), no_supply)
		vb.add_child(grid)
		var rule := Control.new()
		rule.custom_minimum_size = Vector2(0, 2)
		rule.draw.connect(func() -> void: rule.draw_rect(Rect2(0, 0, rule.size.x, 2), Color(0.043, 0.137, 0.25, 0.32)))
		vb.add_child(rule)
		var buf := HBoxContainer.new()
		buf.name = "RecommendedBuffer"
		var bl := _ink("Recommended buffer before first sales", 14, NAVY_INK)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		buf.add_child(bl)
		var need := float(f.get("cash_needed", 0.0))
		var m := _money(need, DS.PALETTE["TEXT"], _cells(need))
		m.name = "RecommendedBufferAmount"
		var pound: Label = m.get_child(0)
		pound.add_theme_color_override("font_color", NAVY_INK)
		pound.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.35))
		buf.add_child(m)
		vb.add_child(buf)
	return sheet


static func _timeline_row(grid: GridContainer, turn: String, stage: String, net: float, no_supply: bool) -> void:
	grid.add_child(_ink(turn, 14, NAVY_INK, true))
	var s := _ink(stage, 14, NAVY_INK)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(s)
	var word := "No supply" if no_supply else str(BuildForecastTable._cash_direction(net))
	var tone := "bad" if no_supply or net < 0.0 else ("ok" if net > 0.0 else "warn")
	grid.add_child(_ink(word.substr(0, 1) + word.substr(1).to_lower(), 14, INK[tone], true))


# --- land ------------------------------------------------------------------------------------------------

## The land lot, small and last: gravel inside hazard tape on four stakes, a concrete slab for each square the
## building takes, a square it buys spare marked out, and how much it takes.
static func land(q: Dictionary) -> Control:
	var lp: Dictionary = q.get("land_plan", {})
	var needed := int(lp.get("needed", 0))
	var spare := 0
	if bool(lp.get("will_buy", false)):
		spare = clampi(int(lp.get("units", 0)) - int(lp.get("shortfall", 0)), 0, 8)
	var lot := LandLot.new(needed, spare)
	lot.name = "LandLot"
	return lot


# --- shared ----------------------------------------------------------------------------------------------

## A section: its raised heading, then its body.
static func _section(heading: String, body: Control) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.name = heading.capitalize().replace(" ", "") + "Section"
	vb.add_theme_constant_override("separation", 8)
	vb.add_child(Parts.heading(heading))
	vb.add_child(body)
	vb.add_child(_gap(10))
	return vb


static func _gap(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## The building's icon printed flat in the blueprint's light ink, from its emblem's silhouette.
class BlueprintIcon extends Control:
	var _face: Texture2D

	func _init(building_id: String) -> void:
		name = "BlueprintIcon"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		var path := "res://assets/ui/bdp_v3/bld_emblem_%s.png" % building_id
		if ResourceLoader.exists(path):
			_face = load(path)
		var m := ShaderMaterial.new()
		m.shader = FLAT_SHADER
		m.set_shader_parameter("ink", BLUEPRINT_INK)
		material = m

	func _draw() -> void:
		if _face == null:
			return
		var art := Indicator.art_rect(_face)
		var k := minf(size.x / art.size.x, size.y / art.size.y)
		var at := (size - art.size * k) * 0.5
		draw_texture_rect(_face, Rect2(at - art.position * k, _face.get_size() * k), false)


## The recipe's navy arrow on the enamel, the power it draws printed on it beside a yellow bolt.
class RecipeArrow extends Control:
	const BOLT := [Vector2(0.60, 0.04), Vector2(0.22, 0.56), Vector2(0.47, 0.56), Vector2(0.36, 0.96), Vector2(0.78, 0.40), Vector2(0.53, 0.40), Vector2(0.66, 0.04)]
	var power := 0

	func _init(power_in: int) -> void:
		name = "RecipeArrow"
		power = power_in
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		custom_minimum_size = Vector2(width_for(power), 56.0)

	## The arrow's width: room for the power it draws and its bolt, or a plain arrow.
	static func width_for(power_in: int) -> float:
		return 92.0 if power_in > 0 else 52.0

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := h * 0.6
		var head := minf(30.0, w * 0.34)
		var pts := PackedVector2Array([Vector2(0, (h - body) * 0.5), Vector2(w - head, (h - body) * 0.5), Vector2(w - head, 0),
			Vector2(w, h * 0.5), Vector2(w - head, h), Vector2(w - head, (h + body) * 0.5), Vector2(0, (h + body) * 0.5)])
		draw_colored_polygon(pts, ENAMEL_NAVY)
		if power <= 0:
			return
		var fig := str(power)
		var px := 20
		var fw := SEMI.get_string_size(fig, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		var x := 6.0
		draw_string(SEMI, Vector2(x, h * 0.5 + px * 0.36), fig, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color("#f4f1e8"))
		var bs := 20.0
		var bx := x + fw + 2.0
		var by := h * 0.5 - bs * 0.5
		var bolt := PackedVector2Array()
		for p: Vector2 in BOLT:
			bolt.append(Vector2(bx + p.x * bs, by + p.y * bs))
		draw_colored_polygon(bolt, BOLT_YELLOW)


## The land lot: the gravel patch, the slabs in a grid inside the tape, the stakes, and the words.
class LandLot extends Control:
	var needed := 0
	var spare := 0
	var _cols := 1
	var _rows := 1
	var _pitch := SLAB_PITCH

	func _init(n: int, extra: int) -> void:
		needed = maxi(0, n)
		spare = maxi(0, extra)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		custom_minimum_size = LOT
		var cells := maxi(1, needed + spare)
		_cols = clampi(ceili(sqrt(float(cells))), 1, 8)
		_rows = ceili(float(cells) / _cols)
		_pitch = minf(SLAB_PITCH, (206.0 - 72.0) / _rows)
		var words := Parts.body("Takes %d land" % needed)
		words.name = "LandWords"
		words.autowrap_mode = TextServer.AUTOWRAP_OFF
		words.position = Vector2(_grid_origin().x + _cols * _pitch + 34.0 + 34.0, 206.0 * 0.5 - 12.0) * S
		add_child(words)

	func _grid_origin() -> Vector2:
		return Vector2(42.0, (206.0 - _rows * _pitch + (_pitch - SLAB)) * 0.5)

	func _draw() -> void:
		var ground := Plate.tex("construct_lot")
		if ground != null:
			draw_texture_rect(ground, Rect2(LOT_LAYER.position * S, LOT_LAYER.size * S), false)
		var slab := Plate.tex("construct_slab")
		var o := _grid_origin()
		var scale := _pitch / SLAB_PITCH
		for i in _cols * _rows:
			var at := o + Vector2(i % _cols, i / _cols) * _pitch
			if i < needed and slab != null:
				var pad := (SLAB_LAYER - SLAB) * 0.5 * scale
				draw_texture_rect(slab, Rect2((at - Vector2.ONE * pad) * S, Vector2.ONE * SLAB_LAYER * scale * S), false)
			elif i < needed + spare:
				_dashed(Rect2((at + Vector2.ONE) * S, Vector2.ONE * (SLAB * scale - 2.0) * S))
		# The tape round the grid, then a stake at each corner.
		var gw := _cols * _pitch - (_pitch - SLAB * scale)
		var gh := _rows * _pitch - (_pitch - SLAB * scale)
		var r := Rect2(o - Vector2.ONE * 14.0, Vector2(gw, gh) + Vector2.ONE * 28.0)
		var tape := Plate.tex("construct_tape")
		if tape != null:
			_tape(tape, r.position, Vector2(r.size.x, 0))
			_tape(tape, r.position + Vector2(0, r.size.y), Vector2(r.size.x, 0))
			_tape(tape, r.position, Vector2(0, r.size.y))
			_tape(tape, r.position + Vector2(r.size.x, 0), Vector2(0, r.size.y))
		var stake := Plate.tex("construct_stake")
		if stake != null:
			for c: Vector2 in [r.position, r.position + Vector2(r.size.x, 0), r.position + Vector2(0, r.size.y), r.end]:
				draw_texture_rect(stake, Rect2((c - Vector2.ONE * STAKE_LAYER * 0.5) * S, Vector2.ONE * STAKE_LAYER * S), false)

	## A run of tape from `from` along `along` (layout px), cut from the render's strip.
	func _tape(tex: Texture2D, from: Vector2, along: Vector2) -> void:
		var length := along.length()
		var src := Rect2(0, 0, minf(length * E, tex.get_width()), tex.get_height())
		if along.x != 0.0:
			draw_texture_rect_region(tex, Rect2((from - Vector2(0, TAPE_W * 0.5)) * S, Vector2(length, TAPE_W) * S), src)
		else:
			draw_set_transform((from + Vector2(TAPE_W * 0.5, 0)) * S, PI * 0.5)
			draw_texture_rect_region(tex, Rect2(Vector2.ZERO, Vector2(length, TAPE_W) * S), src)
			draw_set_transform(Vector2.ZERO)

	func _dashed(r: Rect2) -> void:
		var c := Color(0.93, 0.92, 0.88, 0.75)
		for side: Array in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
				[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
			draw_dashed_line(side[0], side[1], c, 1.2, 3.0)
