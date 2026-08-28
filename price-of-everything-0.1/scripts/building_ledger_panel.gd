extends PanelContainer
## Building Ledger — a read-only table of all the player's buildings with live status/cost
## columns, plus search, filter chips and click-to-sort headers. Clicking a row pans the
## camera to that building and opens its detail panel (the ledger hides itself first). The
## multi-select action bar comes in a later phase.
##
## Opened by the BuildingsButton (factory icon) in the bottom menu. Header is drag-to-move.

const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")  # navy-keyed, square-cropped building icons
const LedgerRowStyle := preload("res://scripts/ledger_row_style.gd")  # metallic, top-left-lit row plate

const ROW_INSET := 12  # row cell inset (LedgerRowStyle BORDER 5 + PAD_H 7); header inset matches it

const ICON_SIZE := 76   # framed goods-icon size in the Output column (sets the row height)
const BICON_SIZE := 56  # building-type icon in the leading column
const BICON_CELL_W := BICON_SIZE + 30  # icon centred in a wider cell → ~15px padding each side

signal close_requested

@onready var _layout: VBoxContainer = $MarginContainer/Layout
@onready var header: HBoxContainer = $MarginContainer/Layout/Header
@onready var title_label: Label = $MarginContainer/Layout/Header/Title
@onready var close_button: Button = %CloseButton

# key → VM field; label; column width (px); text alignment; sortable?
const COLUMNS := [
	{"key": "bicon",   "label": "",         "w": 86.0,  "align": HORIZONTAL_ALIGNMENT_CENTER, "sort": false},  # == BICON_CELL_W
	{"key": "name",    "label": "Building", "w": 196.0, "align": HORIZONTAL_ALIGNMENT_LEFT,   "sort": true},
	{"key": "tile",    "label": "Tile",     "w": 90.0,  "align": HORIZONTAL_ALIGNMENT_LEFT,   "sort": true},
	{"key": "output",  "label": "Output",   "w": 76.0,  "align": HORIZONTAL_ALIGNMENT_CENTER, "sort": true},
	{"key": "power",   "label": "Power",    "w": 110.0, "align": HORIZONTAL_ALIGNMENT_LEFT,   "sort": true},
	{"key": "status",  "label": "Status",   "w": 90.0,  "align": HORIZONTAL_ALIGNMENT_LEFT,   "sort": true},
	{"key": "cost",    "label": "Cost/u",   "w": 82.0,  "align": HORIZONTAL_ALIGNMENT_RIGHT,  "sort": true},
	{"key": "net",     "label": "Net/t",    "w": 92.0,  "align": HORIZONTAL_ALIGNMENT_RIGHT,  "sort": true},
	{"key": "land",    "label": "Land",     "w": 50.0,  "align": HORIZONTAL_ALIGNMENT_RIGHT,  "sort": true},
	{"key": "upgrade", "label": "Upg",      "w": 52.0,  "align": HORIZONTAL_ALIGNMENT_CENTER, "sort": false},
]

var _body: VBoxContainer = null
var _count_label: Label = null
var _all_vms: Array = []         # cached row-model; recomputed on data change, re-rendered on filter/sort
var _dirty := false

# Filters.
var _search: LineEdit = null
var _search_text := ""
var _chips := {}                 # name -> Button
var _f := {
	"running": false, "starved": false, "unpowered": false, "loss": false,
	"profitable": false, "upgradable": false,
	"cat_production": false, "cat_power": false, "cat_infrastructure": false,
	"green_intermittent": false, "green_steady": false,
}

# Sort.
var _sort_key := "name"
var _sort_asc := true
var _header_cells := {}          # key -> Label (click-to-sort)

# Upgrade dialog (lazily built on a high CanvasLayer, as the detail panel does).
var _upgrade_dialog: Control = null
var _upgrade_dialog_layer: CanvasLayer = null

# Header drag state.
var _dragging := false
var _drag_panel_start := Vector2.ZERO
var _drag_mouse_start := Vector2.ZERO

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	add_theme_stylebox_override("panel", preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(8.0))
	title_label.text = "Buildings"
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.gui_input.connect(_on_header_gui_input)
	_build_chrome()

	# Refresh wiring: structural changes + per-turn. The status/power/cost columns are
	# recomputed on every rebuild, and turn_resolution_completed fires once per turn — so
	# the power column is rechecked every turn against the latest production/cabling state.
	MatchState.building_added.connect(func(_i: Dictionary) -> void: _request_refresh())
	MatchState.building_removed.connect(func(_i: String) -> void: _request_refresh())
	# A bought NPC building becomes player-owned → it should appear in the ledger right away.
	MatchState.building_owner_changed.connect(func(_i: String) -> void: _request_refresh())
	MatchState.building_upgraded.connect(func(_i: String, _l: int) -> void: _request_refresh())
	MatchState.building_upgrade_started.connect(func(_i: String, _l: int) -> void: _request_refresh())
	MatchState.building_upgrade_progress.connect(func(_i: String) -> void: _request_refresh())
	MatchState.building_upgrade_cancelled.connect(func(_i: String) -> void: _request_refresh())
	MatchState.workforce_policies_changed.connect(_request_refresh)
	TurnManager.turn_resolution_completed.connect(_request_refresh)
	Construction.construction_completed.connect(func(_i: String, _t: String) -> void: _request_refresh())
	Construction.construction_cancelled.connect(func(_i: String, _t: String) -> void: _request_refresh())
	visibility_changed.connect(_on_visibility_changed)

	call_deferred("_center_on_screen")
	_rebuild()

# ── Chrome (toolbar + filter bar + header row + scrolling body) ─────────────────────────
func _build_chrome() -> void:
	# Toolbar: building count on the left, routing-objective selector on the right.
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", DS.SP["MD"])
	_count_label = Label.new()
	_count_label.theme_type_variation = "Caption"
	_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_count_label)
	toolbar.add_child(_build_routing_control())
	_layout.add_child(toolbar)

	_layout.add_child(_build_filters())
	# Inset the header to match each data row's content margin (the metallic plate's rim + pad),
	# so header labels line up exactly over the row cells below them.
	var header_wrap := MarginContainer.new()
	header_wrap.add_theme_constant_override("margin_left", ROW_INSET)
	header_wrap.add_theme_constant_override("margin_right", ROW_INSET)
	header_wrap.add_child(_build_header_row())
	_layout.add_child(header_wrap)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 7)  # gap between row plates
	scroll.add_child(_body)
	_layout.add_child(scroll)

func _build_routing_control() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", DS.SP["SM"])
	var lbl := Label.new()
	lbl.theme_type_variation = "Caption"
	lbl.text = "Routing:"
	box.add_child(lbl)
	var dd := OptionButton.new()
	dd.add_item("Fastest", MatchState.RouteObjective.FASTEST)
	dd.add_item("Cheapest", MatchState.RouteObjective.CHEAPEST)
	dd.add_item("Blended", MatchState.RouteObjective.BLENDED)
	dd.select(dd.get_item_index(MatchState.route_objective))
	dd.item_selected.connect(func(idx: int) -> void: MatchState.set_route_objective(dd.get_item_id(idx)))
	box.add_child(dd)
	return box

# ── Filter bar (two rows) ───────────────────────────────────────────────────────────────
func _build_filters() -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)

	# Row 1: search + state/cost chips.
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name or output…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(200, 0)
	_search.text_changed.connect(func(t: String) -> void:
		_search_text = t.strip_edges().to_lower()
		_render())
	r1.add_child(_search)
	for spec in [["running", "Running"], ["starved", "Starved"], ["unpowered", "Unpowered"],
			["loss", "Loss-making"], ["upgradable", "Upgradable"]]:
		var chip := _make_chip(str(spec[1]), str(spec[0]))
		_chips[str(spec[0])] = chip
		r1.add_child(chip)
	col.add_child(r1)

	# Row 2: profitability + category chips, right-aligned under row 1's chips.
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r2.add_child(spacer)
	for spec in [["profitable", "Profitable"], ["cat_production", "Production"],
			["cat_power", "Power"], ["cat_infrastructure", "Infrastructure"],
			["green_intermittent", "Intermittent green power"], ["green_steady", "Steady green power"]]:
		var chip := _make_chip(str(spec[1]), str(spec[0]))
		_chips[str(spec[0])] = chip
		r2.add_child(chip)
	col.add_child(r2)
	return col

func _make_chip(text: String, key: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_stylebox_override("normal", _chip_box(DS.PALETTE.BG_INSET, DS.PALETTE.BORDER_SOFT))
	b.add_theme_stylebox_override("hover", _chip_box(DS.PALETTE.BG_HIGHLIGHT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("pressed", _chip_box(DS.PALETTE.ACCENT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("hover_pressed", _chip_box(DS.PALETTE.ACCENT, DS.PALETTE.ACCENT))
	b.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", DS.PALETTE.TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.toggled.connect(func(pressed: bool) -> void: _on_chip(key, pressed))
	return b

func _chip_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 5
	s.content_margin_bottom = 5
	return s

func _on_chip(key: String, pressed: bool) -> void:
	_f[key] = pressed
	# Running and Starved are mutually exclusive (a building can't be both).
	if pressed and key == "running" and _chips["starved"].button_pressed:
		_chips["starved"].set_pressed_no_signal(false)
		_f["starved"] = false
	elif pressed and key == "starved" and _chips["running"].button_pressed:
		_chips["running"].set_pressed_no_signal(false)
		_f["running"] = false
	# Profitable and Loss-making are likewise mutually exclusive.
	elif pressed and key == "profitable" and _chips["loss"].button_pressed:
		_chips["loss"].set_pressed_no_signal(false)
		_f["loss"] = false
	elif pressed and key == "loss" and _chips["profitable"].button_pressed:
		_chips["profitable"].set_pressed_no_signal(false)
		_f["profitable"] = false
	_render()

# Public: open the ledger showing ONLY the given filter (used by deep-links such as the
# tile-view intermittency "see more"). Clears the other chips so the view is unambiguous.
func set_filter_preset(key: String) -> void:
	if not _f.has(key):
		return
	for k in _f.keys():
		_f[k] = false
		if _chips.has(k):
			_chips[k].set_pressed_no_signal(false)
	_f[key] = true
	if _chips.has(key):
		_chips[key].set_pressed_no_signal(true)
	_rebuild()

func _passes_filters(vm: Dictionary) -> bool:
	if _search_text != "" and not (str(vm.name_l).contains(_search_text) or str(vm.output_l).contains(_search_text)):
		return false
	if _f["running"] and not vm.is_running:
		return false
	if _f["starved"] and not vm.is_starved:
		return false
	if _f["unpowered"] and not vm.unpowered:
		return false
	if _f["loss"] and not vm.loss:
		return false
	if _f["profitable"] and not vm.profit:
		return false
	if _f["upgradable"] and not vm.upgradable:
		return false
	# Green-power chips: building must consume green power of that quality. Intermittent =
	# drew unfirmed intermittent green (i.e. it is taking an intermittency hit).
	if _f["green_intermittent"] and not vm.green_intermittent:
		return false
	if _f["green_steady"] and not vm.green_steady:
		return false
	# Category chips act as an OR-group: if any is on, the building must match one of them.
	if _f["cat_production"] or _f["cat_power"] or _f["cat_infrastructure"]:
		var c: String = str(vm.category)
		var ok: bool = (_f["cat_production"] and c == "production") \
			or (_f["cat_power"] and c == "power") \
			or (_f["cat_infrastructure"] and c == "infrastructure")
		if not ok:
			return false
	return true

# ── Sortable header row ─────────────────────────────────────────────────────────────────
func _build_header_row() -> HBoxContainer:
	# Headers are plain Labels (NOT Buttons) so their text geometry — width, alignment,
	# zero internal padding — matches the data cells exactly and the columns line up.
	# Click-to-sort is wired via gui_input.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_header_cells.clear()
	for col in COLUMNS:
		var key: String = str(col.key)
		var l := Label.new()
		l.custom_minimum_size = Vector2(float(col.w), 0)
		l.horizontal_alignment = int(col.align)
		l.theme_type_variation = "Caption"
		l.clip_text = true
		_header_cells[key] = l
		if bool(col.get("sort", true)):
			l.mouse_filter = Control.MOUSE_FILTER_STOP
			l.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			l.gui_input.connect(_on_header_sort_input.bind(key))
		else:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(l)
	_update_header_labels()
	return row

func _on_header_sort_input(event: InputEvent, key: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_sort_pressed(key)

func _on_sort_pressed(key: String) -> void:
	if _sort_key == key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = true
	_update_header_labels()
	_render()

func _update_header_labels() -> void:
	for col in COLUMNS:
		var key: String = str(col.key)
		var l: Label = _header_cells.get(key)
		if l == null:
			continue
		var active := _sort_key == key
		var arrow := ""
		if active:
			arrow = " ▲" if _sort_asc else " ▼"
		l.text = str(col.label) + arrow
		l.add_theme_color_override("font_color", DS.PALETTE.ACCENT if active else DS.PALETTE.TEXT_MUTED)

func _sort_value(vm: Dictionary):
	match _sort_key:
		"name":   return vm.name
		"tile":   return vm.sort_tile
		"type":   return vm.type
		"output": return vm.output
		"level":  return vm.level
		"power":  return vm.sort_power
		"status": return vm.sort_status
		"cost":   return vm.sort_cost
		"net":    return vm.sort_net
		"land":   return vm.land_value
	return vm.name

func _compare(a: Dictionary, b: Dictionary) -> bool:
	var av = _sort_value(a)
	var bv = _sort_value(b)
	var c := 0
	if av is String:
		c = String(av).naturalnocasecmp_to(String(bv))
	elif float(av) < float(bv):
		c = -1
	elif float(av) > float(bv):
		c = 1
	if c == 0:
		c = String(a.name).naturalnocasecmp_to(String(b.name))  # stable tiebreak by name
	return c < 0 if _sort_asc else c > 0

# ── Rebuild (data) / render (filter + sort) ─────────────────────────────────────────────
func _request_refresh() -> void:
	if _dirty:
		return
	_dirty = true
	call_deferred("_rebuild_if_dirty")

func _rebuild_if_dirty() -> void:
	_dirty = false
	if not visible:
		return  # skip work while hidden; _on_visibility_changed rebuilds on next show
	_rebuild()

func _on_visibility_changed() -> void:
	if visible:
		_rebuild()

func _rebuild() -> void:
	if _body == null:
		return
	_all_vms = _collect_vms()
	_render()

func _render() -> void:
	if _body == null:
		return
	# remove_child BEFORE queue_free: queue_free is deferred to end-of-frame, so freeing alone
	# leaves the old rows in the tree for one frame while the new rows are added — the buildings
	# would visibly double for a frame (e.g. after turn resolution). Detaching is synchronous.
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var shown: Array = _all_vms.filter(_passes_filters)
	shown.sort_custom(_compare)
	for vm in shown:
		_body.add_child(_build_row(vm))
	if _count_label != null:
		if shown.size() == _all_vms.size():
			_count_label.text = "%d building%s" % [_all_vms.size(), "" if _all_vms.size() == 1 else "s"]
		else:
			_count_label.text = "%d of %d buildings" % [shown.size(), _all_vms.size()]

func _collect_vms() -> Array:
	var out: Array = []
	for instance_id in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[instance_id]
		if not MatchState.is_player_owned(b):
			continue
		out.append(_row_vm(b))
	return out

func _row_vm(b: Dictionary) -> Dictionary:
	var instance_id: String = str(b.get("instance_id", ""))
	var building_id: String = str(b.get("building_id", ""))
	var tile_id: String = str(b.get("tile_id", ""))
	var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
	var bdata: Dictionary = Catalog.get_building(building_id)
	var category: String = str(bdata.get("category", "production"))
	var is_infra: bool = category == "infrastructure"
	var level: int = int(b.get("level", 1))

	# Cost/unit: -1.0 when unsolved or the deposit is mined out → grey "—".
	var uc: float = CostSolver.get_building_unit_cost(instance_id)
	if BuildingStatus.recipe_deposit_exhausted(b, recipe):
		uc = -1.0
	var per_b: Dictionary = CostSolver.last_result.get("per_building", {}).get(instance_id, {})
	var out_gid: String = str(per_b.get("output_good_id", ""))
	var base_price: float = Catalog.get_base_price(out_gid) if out_gid != "" else 0.0
	var cost_color: Color = BuildingStatus.cost_rag_color(uc, base_price)

	var land: float = float(bdata.get("tile_size_used", 1)) * BuildingLevels.mult("size", level)
	var name_str: String = BuildingNaming.label_for_tile(tile_id, instance_id, building_id, str(b.get("recipe_id", "")))
	var output_str: String = BuildingStatus.primary_output_display_name(recipe)
	var power: Dictionary = _power_cell(b, recipe, is_infra)
	var status: Dictionary = _status_cell(b, recipe, is_infra)

	# Output icon + post-modifier output qty (for the quantity pill).
	var icon_gid: String = BuildingStatus.primary_output_good_id(recipe)
	var icon_internal: String = BuildingStatus.primary_output_internal(recipe)
	var out_qty: int = BuildingStatus.effective_output_qty(b, recipe)
	if icon_internal == "power":  # power isn't a tradeable good — no Output icon (it's in the Power column)
		icon_gid = ""
		out_qty = 0

	# Net per turn (gross margin) = (sale price − unit cost) × output qty, when a cost is solved.
	var net_text: String = "—"
	var net_color: Color = BuildingStatus.STATUS_GREY
	var sort_net: float = -1.0e18
	if uc >= 0.0 and icon_gid != "" and out_qty > 0:
		var net: float = (MarketState.get_price(icon_gid) - uc) * float(out_qty)
		sort_net = net
		net_color = BuildingStatus.STATUS_GREEN if net > 0.0 else (BuildingStatus.STATUS_RED if net < 0.0 else DS.PALETTE.TEXT)
		net_text = "%s£%.0f" % ["+" if net >= 0.0 else "−", absf(net)]

	# Intermittency: did this building draw unfirmed intermittent (taking a hit) / steady green?
	var im: Dictionary = Production.get_building_intermittency(instance_id)

	return {
		"instance_id": instance_id,
		"building_id": building_id, "binternal": str(bdata.get("internal_name", "")),
		"name": name_str, "name_l": name_str.to_lower(),
		"tile": _tile_short(tile_id), "sort_tile": _tile_sort(tile_id),
		"type": _type_label(category),
		"output": output_str, "output_l": output_str.to_lower(),
		"out_good_id": icon_gid, "out_internal": icon_internal, "out_qty": out_qty,
		"level": level,
		"power": power, "status": status,
		"cost_text": ("£%.2f" % uc) if uc >= 0.0 else "—",
		"cost_color": cost_color,
		"net_text": net_text, "net_color": net_color, "sort_net": sort_net,
		"land": "%.1f" % land, "land_value": land,
		# Derived for filters / sort.
		"category": category,
		"is_running": str(status.text) == "Running",
		"is_starved": str(status.text) == "Starved",
		"unpowered": power.color == BuildingStatus.STATUS_RED,  # red = needs power, no cable
		"loss": cost_color == BuildingStatus.STATUS_RED,
		"profit": cost_color == BuildingStatus.STATUS_GREEN,
		"upgradable": (not is_infra) and level < BuildingLevels.MAX_LEVEL,
		"green_intermittent": float(im.get("unfirmed_intermittent", 0.0)) > 0.0,
		"green_steady": float(im.get("steady_consumed", 0.0)) > 0.0,
		"sort_cost": uc if uc >= 0.0 else 1.0e18,  # unknown costs sink to the bottom ascending
		"sort_power": int(power.value),
		"sort_status": _status_rank(str(status.text)),
	}

# Per-turn power snapshot — recomputed on each rebuild (turn_resolution_completed drives a
# rebuild every turn). Consumers show "<consumption> (self|grid|no cable)"; power buildings
# show their generation as a positive "+<gen> (self)" in green. `value` drives the sort.
func _power_cell(b: Dictionary, recipe: Dictionary, is_infra: bool) -> Dictionary:
	if is_infra:
		return {"color": BuildingStatus.STATUS_GREY, "text": "—", "value": -1}
	# Power producers: count generation as positive, self-supplied (green).
	if str(recipe.get("output_name", "")) == "power":
		var gen: int = BuildingStatus.effective_power_output(b, recipe)
		if gen <= 0:
			return {"color": BuildingStatus.STATUS_GREY, "text": "—", "value": -1}
		return {"color": BuildingStatus.STATUS_GREEN, "text": "+%d (self)" % gen, "value": gen}
	# Consumers: show the consumption + where the power comes from.
	var req: int = BuildingStatus.effective_energy_req(b, recipe)
	if req <= 0:
		return {"color": BuildingStatus.STATUS_GREY, "text": "—", "value": -1}
	var supply: String = BuildingStatus.power_supply(b)
	if supply == "Owned Supply":
		return {"color": BuildingStatus.STATUS_GREEN, "text": "%d (self)" % req, "value": req}
	elif supply == "Grid":
		return {"color": BuildingStatus.STATUS_YELLOW, "text": "%d (grid)" % req, "value": req}
	return {"color": BuildingStatus.STATUS_RED, "text": "%d (no cable)" % req, "value": req}

func _status_cell(b: Dictionary, recipe: Dictionary, is_infra: bool) -> Dictionary:
	if is_infra:
		return {"color": BuildingStatus.STATUS_GREY, "text": "—"}
	var id: String = str(b.get("instance_id", ""))
	var text: String = "Idle"
	if Production.last_turn_run.has(id):
		text = "Running"
	elif Production.missing_by_building.has(id) or BuildingStatus.recipe_deposit_exhausted(b, recipe):
		text = "Starved"
	return {"color": BuildingStatus.input_status_color(b, recipe, is_infra), "text": text}

func _status_rank(text: String) -> int:
	match text:
		"Starved": return 0
		"Idle": return 1
		"Running": return 2
		_: return 3

# ── Row widgets ──────────────────────────────────────────────────────────────────────────
func _build_row(vm: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.gui_input.connect(_on_row_gui_input.bind(str(vm.instance_id)))
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", _row_style(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", _row_style(false)))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)
	for col in COLUMNS:
		hbox.add_child(_build_cell(col, vm))
	return row

func _build_cell(col: Dictionary, vm: Dictionary) -> Control:
	var key: String = str(col.key)
	var w: float = float(col.w)
	var align: int = int(col.align)
	if key == "bicon":
		return _bicon_cell(vm)
	if key == "output":
		return _output_cell(vm)
	if key == "upgrade":
		return _upgrade_cell(vm)
	# Power and Status are coloured text (the word/number carries its own RAG colour).
	if key == "power":
		return _text_cell(str(vm["power"].text), w, align, vm["power"].color)
	if key == "status":
		return _text_cell(str(vm["status"].text), w, align, vm["status"].color)
	if key == "cost":
		return _text_cell(str(vm.cost_text), w, align, vm.cost_color)
	if key == "net":
		return _text_cell(str(vm.net_text), w, align, vm.net_color)
	return _text_cell(str(vm.get(key, "")), w, align)

func _text_cell(text: String, w: float, align: int, color: Color = Color.TRANSPARENT) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.theme_type_variation = "Body"
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT if color.a == 0.0 else color)
	return l

# Leading column: the building-type icon (same art as the build menu / map), embossed — a dark
# drop to the bottom-right + a light lift to the top-left under the off-white art, so it reads
# as a raised, metallic engraving lit from the top-left (matching the row plate). Empty if missing.
func _bicon_cell(vm: Dictionary) -> Control:
	var holder := Control.new()
	# Wider than the icon so the centred art gets padding left and right.
	holder.custom_minimum_size = Vector2(BICON_CELL_W, BICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = BuildingIcon.clean_texture(str(vm.building_id), str(vm.binternal))
	if tex == null:
		return holder
	# Strong cast shade like the bottom-menu icons: a stacked dark drop to the bottom-right (light
	# from the top-left), in the bottom menu's shadow colour. A top-left lift keeps the emboss.
	holder.add_child(_emboss_layer(tex, Vector2(6.0, 6.0), Color(0.02, 0.035, 0.045, 0.38)))   # soft outer shade
	holder.add_child(_emboss_layer(tex, Vector2(3.5, 3.5), Color(0.01, 0.02, 0.03, 0.65)))     # mid shade
	holder.add_child(_emboss_layer(tex, Vector2(2.0, 2.0), Color(0.0, 0.0, 0.0, 0.85)))        # core shade (strong)
	holder.add_child(_emboss_layer(tex, Vector2(-1.0, -1.0), Color(1, 1, 1, 0.45)))            # top-left lift
	holder.add_child(_emboss_layer(tex, Vector2.ZERO, Color(0.93, 0.96, 1.0)))                 # the icon
	return holder

func _emboss_layer(tex: Texture2D, offset: Vector2, tint: Color) -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = offset.x
	t.offset_top = offset.y
	t.offset_right = offset.x
	t.offset_bottom = offset.y
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

# Output column: the market panel's framed goods icon with a quantity pill showing the
# building's post-modifier output. Empty for power/infra (no goods output).
func _output_cell(vm: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gid: String = str(vm.out_good_id)
	if gid == "":
		return holder
	var icon := UIHelpers.make_framed_good_icon(gid, str(vm.out_internal), ICON_SIZE)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	var qty: int = int(vm.out_qty)
	if qty > 0:
		holder.add_child(_qty_pill(qty))
	return holder

func _qty_pill(qty: int) -> Control:
	var lbl := Label.new()
	lbl.text = str(qty)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.06, 0.12, 0.92)
	box.border_color = DS.PALETTE.BORDER_SOFT
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 5
	box.content_margin_right = 5
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	lbl.add_theme_stylebox_override("normal", box)
	# Pin to the icon's bottom-right corner.
	var w: float = maxf(16.0, 9.0 + float(str(qty).length()) * 8.0)
	lbl.custom_minimum_size = Vector2(w, 17)
	lbl.position = Vector2(float(ICON_SIZE) - w - 1.0, float(ICON_SIZE) - 18.0)
	return lbl

# Per-row upgrade button: shows the level it would reach (L1 → "2", L2 → "3"); "MAX" and
# disabled at L3. Clicking opens the shared upgrade dialog for that building.
func _upgrade_cell(vm: Dictionary) -> Control:
	var holder := CenterContainer.new()
	holder.custom_minimum_size = Vector2(52, 0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE  # padding clicks fall through to the row
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(42, 34)
	var level: int = int(vm.level)
	if level >= BuildingLevels.MAX_LEVEL:
		btn.text = "MAX"
		btn.disabled = true
		btn.tooltip_text = "Already at maximum level"
	else:
		btn.text = str(level + 1)
		btn.tooltip_text = "Upgrade to level %d" % (level + 1)
		btn.pressed.connect(_open_upgrade.bind(str(vm.instance_id)))
	holder.add_child(btn)
	return holder

func _open_upgrade(instance_id: String) -> void:
	_ensure_upgrade_dialog()
	_upgrade_dialog.open(instance_id)

func _ensure_upgrade_dialog() -> void:
	if _upgrade_dialog != null and is_instance_valid(_upgrade_dialog):
		return
	if _upgrade_dialog_layer == null or not is_instance_valid(_upgrade_dialog_layer):
		_upgrade_dialog_layer = CanvasLayer.new()
		_upgrade_dialog_layer.layer = 128
		get_tree().root.add_child(_upgrade_dialog_layer)
	_upgrade_dialog = (load("res://scripts/upgrade_dialog.gd") as Script).new()
	_upgrade_dialog_layer.add_child(_upgrade_dialog)
	_upgrade_dialog.committed.connect(func(_id: String) -> void: _request_refresh())

func _row_style(hover: bool) -> StyleBox:
	var s := LedgerRowStyle.new()
	s.hover = hover
	return s

func _on_row_gui_input(event: InputEvent, instance_id: String) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Deep-link to the building: pan + open its detail panel, then hide the ledger so
		# the focused tile/detail panel aren't hidden behind us (world_map.gd:983).
		MatchState.focus_building_requested.emit(instance_id)
		close_requested.emit()

# ── Helpers ─────────────────────────────────────────────────────────────────────────────
func _tile_short(tile_id: String) -> String:
	return tile_id.trim_prefix("tile_") if tile_id.begins_with("tile_") else tile_id

func _tile_sort(tile_id: String) -> int:
	var parts := _tile_short(tile_id).split("_")
	if parts.size() == 2 and parts[0].is_valid_int() and parts[1].is_valid_int():
		return int(parts[0]) * 10000 + int(parts[1])
	return 0

func _type_label(category: String) -> String:
	match category:
		"power": return "Power"
		"infrastructure": return "Infra"
		"battery": return "Battery"
		_: return "Production"

func _center_on_screen() -> void:
	# Centred horizontally; biased 20px up so the added height sits toward the top
	# (the bottom edge stays roughly where the shorter panel's was).
	position = (get_viewport_rect().size - size) / 2.0
	position.y -= 20.0

func _on_header_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_panel_start = position
			_drag_mouse_start = get_global_mouse_position()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		position = _drag_panel_start + (get_global_mouse_position() - _drag_mouse_start)
