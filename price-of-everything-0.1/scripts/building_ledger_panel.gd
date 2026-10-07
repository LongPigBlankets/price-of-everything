extends PanelContainer
## Building Ledger — a read-only table of all the player's buildings with live status/cost
## columns, plus search, filter keys and click-to-sort headings, in DS2 (scripts/ledger_v3/ledger_v3.gd
## builds the parts). Clicking a row pans the camera to that building and opens its detail panel (the
## ledger hides itself first).
##
## Opened by the BuildingsButton (factory icon) in the bottom menu. The title row is drag-to-move.

const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingLevels := preload("res://scripts/building_levels.gd")
const BuildingNaming := preload("res://scripts/building_naming.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")

signal close_requested

@onready var _layout: VBoxContainer = $MarginContainer/Layout
@onready var header: HBoxContainer = $MarginContainer/Layout/Header

var _body: VBoxContainer = null
var _all_vms: Array = []         # cached row-model; recomputed on data change, re-rendered on filter/sort
var _dirty := false

# Filters.
var _search: LineEdit = null
var _search_text := ""
var _chips := {}                 # name -> latching key
var _f := {
	"running": false, "starved": false, "unpowered": false, "loss": false,
	"profitable": false, "upgradable": false,
	"cat_production": false, "cat_power": false, "cat_infrastructure": false,
	"green_intermittent": false, "green_steady": false,
}

# Sort.
var _sort_key := "name"
var _sort_asc := true
var _header_cells := {}          # key -> heading (click-to-sort)

# Upgrade dialog (lazily built on a high CanvasLayer, as the detail panel does).
var _upgrade_dialog: Control = null
var _upgrade_dialog_layer: CanvasLayer = null

# The count display, the headings' sort marks and the cells every money screen takes.
var _count_display: Control = null
var _sort_marks := {}
var _money_digits := 4

# Header drag state.
var _dragging := false
var _drag_panel_start := Vector2.ZERO
var _drag_mouse_start := Vector2.ZERO

func _ready() -> void:
	if DS and DS.theme:
		theme = DS.theme
	_build_chrome()

	# Refresh wiring: structural changes + per-turn. The status/power/cost columns are
	# recomputed on every rebuild, and turn_resolution_completed fires once per turn — so
	# the power column is rechecked every turn against the latest production/cabling state.
	BuildingState.building_added.connect(func(_i: Dictionary) -> void: _request_refresh())
	BuildingState.building_removed.connect(func(_i: String) -> void: _request_refresh())
	# A bought NPC building becomes player-owned → it should appear in the ledger right away.
	BuildingState.building_owner_changed.connect(func(_i: String) -> void: _request_refresh())
	BuildingWorks.building_upgraded.connect(func(_i: String, _l: int) -> void: _request_refresh())
	BuildingWorks.building_upgrade_started.connect(func(_i: String, _l: int) -> void: _request_refresh())
	BuildingWorks.building_upgrade_progress.connect(func(_i: String) -> void: _request_refresh())
	BuildingWorks.building_upgrade_cancelled.connect(func(_i: String) -> void: _request_refresh())
	LabourState.workforce_policies_changed.connect(_request_refresh)
	TurnManager.turn_resolution_completed.connect(_request_refresh)
	Construction.construction_completed.connect(func(_i: String, _t: String) -> void: _request_refresh())
	Construction.construction_cancelled.connect(func(_i: String, _t: String) -> void: _request_refresh())
	MatchState.output_stockpile_destination_changed.connect(func(_i: String, _t: String, _g: String) -> void: _request_refresh())
	TransportState.transport_shipments_changed.connect(_request_refresh)
	visibility_changed.connect(_on_visibility_changed)

	call_deferred("_center_on_screen")
	_rebuild()

# ── Chrome (title, toolbar, filter keys, headings and the scrolling table) ──────────────
## The scene's plain header gives way to the raised title row; the backing goes behind the panel.
func _build_chrome() -> void:
	header.visible = false
	var margin := $MarginContainer as MarginContainer
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, LedgerV3.CONTENT_MARGIN)
	LedgerV3.dress(self)
	_layout.add_theme_constant_override("separation", 12)
	_layout.add_child(LedgerV3.title_row(func() -> void: close_requested.emit(), _on_header_gui_input))
	var bar := LedgerV3.toolbar(func(t: String) -> void:
		_search_text = t.strip_edges().to_lower()
		_render())
	_layout.add_child(bar.row)
	_count_display = bar.count
	_search = bar.search
	var f := LedgerV3.filters(func(key: String) -> void: _on_chip(key, not bool(_f[key])))
	_layout.add_child(f.bed)
	_chips = f.keys
	_layout.add_child(LedgerV3.seam())
	var heads := LedgerV3.heading_row(_on_sort_pressed)
	_layout.add_child(heads.row)
	_header_cells = heads.cells
	_sort_marks = heads.marks
	var t := LedgerV3.table()
	_layout.add_child(t.scroll)
	_body = t.rows
	_update_header_labels()
	# The lamp over the whole panel, its upgrade sheet's too (docs/ds2-theme.md §4).
	LampOverlay.attach(self)


## A filter key on or off, without running its handler.
func _set_chip(key: String, on: bool) -> void:
	if not _chips.has(key):
		return
	(_chips[key] as Control).set("latched", on)


func _on_chip(key: String, pressed: bool) -> void:
	_f[key] = pressed
	_set_chip(key, pressed)
	# Running and Starved are mutually exclusive (a building can't be both), as are Profitable and
	# Loss-making.
	for pair in [["running", "starved"], ["profitable", "loss"]]:
		if pressed and key in pair:
			var other: String = pair[1] if key == pair[0] else pair[0]
			_f[other] = false
			_set_chip(other, false)
	_render()

# Public: open the ledger showing ONLY the given filter (used by deep-links such as the
# tile-view intermittency "see more"). Clears the other chips so the view is unambiguous.
func set_filter_preset(key: String) -> void:
	if not _f.has(key):
		return
	for k in _f.keys():
		_f[k] = false
		_set_chip(k, false)
	_f[key] = true
	_set_chip(key, true)
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

# ── Sorting ─────────────────────────────────────────────────────────────────────────────
func _on_sort_pressed(key: String) -> void:
	if _sort_key == key:
		_sort_asc = not _sort_asc
	else:
		_sort_key = key
		_sort_asc = true
	_update_header_labels()
	_render()

func _update_header_labels() -> void:
	LedgerV3.show_sort(_header_cells, _sort_marks, _sort_key, _sort_asc)

func _sort_value(vm: Dictionary):
	match _sort_key:
		"name":   return vm.name
		"output": return vm.output
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
	_money_digits = LedgerV3.money_digits(shown)
	for vm in shown:
		_body.add_child(_build_row(vm))
	_count_display.set("text", LedgerV3.count_text(shown.size(), _all_vms.size()))

func _collect_vms() -> Array:
	var out: Array = []
	for instance_id in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[instance_id]
		if not BuildingState.is_player_owned(b):
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
	var net_color: Color = BuildingStatus.STATUS_GREY
	var sort_net: float = -1.0e18
	if uc >= 0.0 and icon_gid != "" and out_qty > 0:
		var net: float = (MarketState.get_price(icon_gid) - uc) * float(out_qty)
		sort_net = net
		net_color = BuildingStatus.STATUS_GREEN if net > 0.0 else (BuildingStatus.STATUS_RED if net < 0.0 else DS.PALETTE.TEXT)

	# Intermittency: did this building draw unfirmed intermittent (taking a hit) / steady green?
	var im: Dictionary = Production.get_building_intermittency(instance_id)

	return {
		"instance_id": instance_id,
		"building_id": building_id,
		"name": name_str, "name_l": name_str.to_lower(),
		"tile_name": _tile_name(tile_id),
		"output": output_str, "output_l": output_str.to_lower(),
		"out_good_id": icon_gid, "out_qty": out_qty,
		"level": level,
		"power": power, "status": status,
		"cost_value": uc, "net_value": sort_net if sort_net > -1.0e17 else NAN,
		"cost_color": cost_color,
		"net_color": net_color, "sort_net": sort_net,
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
		return {"color": BuildingStatus.STATUS_GREEN, "text": "+%d (self)" % gen, "value": gen,
			"tone": "ok", "figure": "+%d MW" % gen, "words": ""}
	# Consumers: show the consumption + where the power comes from.
	var req: int = BuildingStatus.effective_energy_req(b, recipe)
	if req <= 0:
		return {"color": BuildingStatus.STATUS_GREY, "text": "—", "value": -1}
	var supply: String = BuildingStatus.power_supply(b)
	if supply == "Owned Supply":
		return {"color": BuildingStatus.STATUS_GREEN, "text": "%d (self)" % req, "value": req,
			"tone": "ok", "figure": "%d MW" % req, "words": "Your supply"}
	elif supply == "Grid":
		return {"color": BuildingStatus.STATUS_YELLOW, "text": "%d (grid)" % req, "value": req,
			"tone": "warn", "figure": "%d MW" % req, "words": "Grid"}
	return {"color": BuildingStatus.STATUS_RED, "text": "%d (no cable)" % req, "value": req,
		"tone": "bad", "figure": "%d MW" % req, "words": "No cable"}

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

# ── Rows ─────────────────────────────────────────────────────────────────────────────────
## A row (scripts/ledger_v3/ledger_v3.gd): clicking it opens the building; its route icons open its logistics,
## its Upgrade key the upgrade dialog.
func _build_row(vm: Dictionary) -> Control:
	var iid := str(vm.instance_id)
	return LedgerV3.row(vm, func() -> void:
		close_requested.emit()
		MatchState.building_logistics_requested.emit(iid), _money_digits, func() -> void:
		MatchState.focus_building_requested.emit(iid)
		close_requested.emit(), _open_upgrade)

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
	_upgrade_dialog = (load("res://scripts/ledger_v3/upgrade_dialog_ds2.gd") as Script).new()
	_upgrade_dialog_layer.add_child(_upgrade_dialog)
	_upgrade_dialog.committed.connect(func(_id: String) -> void: _request_refresh())

# ── Helpers ─────────────────────────────────────────────────────────────────────────────
func _tile_short(tile_id: String) -> String:
	return tile_id.trim_prefix("tile_") if tile_id.begins_with("tile_") else tile_id

## A tile's name, or its coordinates in words where it has none, as the tile view's nameplate says them.
func _tile_name(tile_id: String) -> String:
	var named := Catalog.tile_name(tile_id)
	if named != "":
		return named
	var parts := _tile_short(tile_id).split("_")
	return "Coordinates %s, %s" % [parts[0], parts[1]] if parts.size() == 2 else tile_id

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
