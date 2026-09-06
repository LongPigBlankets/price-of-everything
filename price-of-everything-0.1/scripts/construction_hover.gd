extends CanvasLayer
## Read-only site preview, active only while the player is choosing where to build.
## Quotes refresh when the site, selection or economy changes, not every frame.

const Forecast := preload("res://scripts/build_forecast.gd")
const ForecastTable := preload("res://scripts/build_forecast_table.gd")
var terrain: HexMap
var card: PanelContainer
var _key := ""

func _ready() -> void:
	name = "ConstructionHover"
	layer = 0 # Below the HUD; the card cannot cover or intercept its controls.
	card = PanelContainer.new()
	card.name = "ConstructionHoverCard"
	card.theme = DS.theme
	card.custom_minimum_size.x = 440
	# Logistics hover's navy plate, cream bevel and diagonal lighting, using DS's
	# existing bevel generator so the card stays crisp at any camera zoom.
	card.add_theme_stylebox_override("panel", DS._button_stylebox(
		DS.PALETTE.BG_CARD.lightened(0.10), DS.PALETTE.BG_CARD,
		DS.PALETTE.BORDER, 12, 5, 18, 14))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	card.minimum_size_changed.connect(card.reset_size)
	card.hide()
	set_process(false)
	BuildMode.mode_entered.connect(_on_entered)
	BuildMode.mode_exited.connect(_on_exited)
	Stockpile.stockpile_changed.connect(_invalidate)
	MatchState.construct_settings_changed.connect(_invalidate)
	MatchState.advisors_changed.connect(_invalidate)
	MatchState.power_priority_changed.connect(_invalidate)
	MatchState.money_changed.connect(func(_amount: float): _invalidate())
	MatchState.tile_land_owned_changed.connect(func(_tile: String): _invalidate())
	Construction.construction_started.connect(func(_id: String, _tile: String): _invalidate())
	if BuildMode.is_active:
		_on_entered("", "")

func _invalidate() -> void:
	_key = ""

func _on_entered(_building: String, _recipe: String) -> void:
	_key = ""
	set_process(true)

func _on_exited() -> void:
	card.hide()
	_key = ""
	set_process(false)

func _over_ui() -> bool:
	var control := get_viewport().gui_get_hovered_control()
	while control != null:
		if control.mouse_filter == Control.MOUSE_FILTER_STOP:
			return true
		control = control.get_parent() as Control
	return false

func _process(_delta: float) -> void:
	var over_ui := _over_ui()
	var tile_id := terrain.tile_id_under_mouse() if not over_ui else ""
	if not BuildMode.is_active or tile_id == "":
		card.hide()
		_key = ""
		return
	var building_id := BuildMode.current_building_id
	if BuildMode.kind == BuildMode.Kind.INFRASTRUCTURE:
		building_id = str(Catalog.get_building_by_internal_name(BuildMode.current_infrastructure_type).get("id", ""))
	var key := "%s|%s|%s|%d" % [tile_id, building_id, BuildMode.current_recipe_id, TurnManager.current_turn]
	if key != _key:
		_key = key
		show_preview(tile_id, building_id, BuildMode.current_recipe_id)
	var coord := terrain.id_to_coord(tile_id)
	var world := terrain.to_global(terrain.map_to_local(terrain.map_coord_for_tile_coord(coord)))
	var center := get_viewport().get_canvas_transform() * world
	var zoom := get_viewport().get_canvas_transform().get_scale().x
	var viewport_size := get_viewport().get_visible_rect().size
	var origin := center - Vector2(card.size.x * 0.5, card.size.y + 160 * zoom)
	# Keep the hover readable near the screen edges; fall below the tile if needed.
	if origin.y < 70:
		origin.y = center.y + 100 * zoom
	card.position = Vector2(clampf(origin.x, 8, maxf(8, viewport_size.x - card.size.x - 8)),
		clampf(origin.y, 70, maxf(70, viewport_size.y - card.size.y - 65)))

static func preview(tile_id: String, building_id: String, recipe_id: String) -> Dictionary:
	var building := Catalog.get_building(building_id)
	var ledger := Construction.materials_ledger(building_id, tile_id)
	var materials := 0.0
	var transport := 0.0
	var arrival := 0
	var missing := false
	for row in ledger.rows:
		materials += float(row.goods_cost)
		transport += float(row.transport_cost)
		arrival = maxi(arrival, int(row.market_turns))
		missing = missing or int(row.short) > 0
	var needed := roundi(float(building.get("tile_size_used", 1)))
	var free := maxi(0, MatchState.get_tile_land_owned(tile_id) - roundi(MatchState.get_tile_player_space_used(tile_id)))
	var patches := maxi(0, ceili(float(needed - free) / MatchState.LAND_PATCH_SIZE))
	var land := MatchState.purchase_cost_after_advisor(float(patches) * MatchState.LAND_PATCH_COST, {"tile_id": tile_id}) if patches > 0 else 0.0
	var fee := maxf(0.0, float(building.get("base_price", 0.0)))
	return {"materials": materials, "transport": transport, "land": land, "fee": fee,
		"total": materials + transport + land + fee, "arrival": arrival, "missing": missing,
		"land_available": patches <= MatchState.get_tile_land_patches_available(tile_id),
		"forecast": Forecast.project(building_id, recipe_id, tile_id)}

func show_preview(tile_id: String, building_id: String, recipe_id: String) -> void:
	for child in card.get_children():
		card.remove_child(child)
		child.queue_free()
	var data := preview(tile_id, building_id, recipe_id)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 7)
	card.add_child(content)
	content.add_child(_label(Catalog.tile_label(tile_id), 20, DS.PALETTE.ACCENT))
	content.add_child(_label("Construction Cost", 17, DS.PALETTE.ACCENT))
	var costs := GridContainer.new()
	costs.columns = 2
	costs.add_theme_constant_override("h_separation", 16)
	content.add_child(costs)
	for field in ["materials", "land", "transport"]:
		_cost_row(costs, str(field).capitalize(), float(data[field]))
	if float(data.fee) > 0:
		_cost_row(costs, "Construction fee", float(data.fee))
	content.add_child(DS.section_rule())
	var total := GridContainer.new()
	total.columns = 2
	_cost_row(total, "Total", float(data.total))
	content.add_child(total)
	if not bool(data.land_available):
		_note(content, "Not enough land available on this tile.", DS.PALETTE.DANGER)
	elif float(data.land) > 0 and not MatchState.construct_auto_buy_land:
		_note(content, "Buy the land before building (automatic buying is off).", DS.PALETTE.WARN)
	if bool(data.missing):
		_note(content, "Construction materials are missing from this tile.", DS.PALETTE.DANGER)
	var forecast: Dictionary = data.forecast
	if not (forecast.get("phases", []) as Array).is_empty():
		content.add_child(DS.section_rule())
		content.add_child(_label("Timeline of Revenue", 17, DS.PALETTE.ACCENT))
		content.add_child(ForecastTable.timeline(forecast))
		content.add_child(ForecastTable.payback(forecast))
	_ignore_mouse(content)
	card.reset_size()
	card.show()

func _cost_row(grid: GridContainer, title: String, amount: float) -> void:
	var label := _label(title, 14)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	var value := _label(_money(amount), 14)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)

func _note(content: Control, text: String, tone: Color = Color("e8eef7")) -> void:
	var label := _label(text, 12, tone)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(label)

func _label(text: String, font_size: int, tone: Color = Color("e8eef7")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", tone)
	return label

static func _money(amount: float) -> String:
	return "£%.2f" % amount

func _ignore_mouse(node: Node) -> void:
	if node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		_ignore_mouse(child)
