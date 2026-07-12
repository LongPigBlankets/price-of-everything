extends PanelContainer

@onready var title_label: Label = $MarginContainer/VBoxContainer/HeaderRow/TitleLabel
@onready var close_button: Button = $MarginContainer/VBoxContainer/HeaderRow/CloseButton
@onready var content_vbox: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ContentVBox
@onready var main_vbox: VBoxContainer = $MarginContainer/VBoxContainer
@onready var header_static: HBoxContainer = $MarginContainer/VBoxContainer/HeaderRowStatic
@onready var scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer

const MarketRowScene: PackedScene = preload("res://scenes/market_row.tscn")
const UIHelpers := preload("res://scripts/ui_helpers.gd")
const BuildingMarketTab := preload("res://scripts/building_market_panel.gd")  # NPC buildings-for-sale tab
const HEADER_HEIGHT := 40.0
const TAB_PRICES := "prices"
const TAB_BUILDINGS := "buildings"
const TAB_SPECIAL_ORDERS := "special_orders"
const TAB_SALES := "sales"
const TAB_TRANSACTIONS := "transactions"
const TAB_MOVEMENTS := "movements"

var rows: Array = []
var _tabs: TabContainer = null
var _buildings_tab: Control = null   # the BuildingMarketTab (NPC buildings for sale)
var _special_orders_tab: VBoxContainer = null
var _special_orders_count_label: Label = null
var _special_orders_body: VBoxContainer = null
var _dragging := false
var _drag_offset := Vector2.ZERO
var _good_option: OptionButton = null
var _finished_check: CheckBox = null
var _recurring_check: CheckBox = null
var _keep_spin: SpinBox = null
var _ledger_refreshers: Array = []  # Callables that rebuild the Transactions/Movements tabs
# Buying now lives in the per-good "Purchase" flow on the world map (world_map.gd).

# Filter bar (Good prices tab): search + three exclusive-ish toggle filters.
var _search: LineEdit = null
var _filter_produce_btn: Button = null
var _filter_profit_btn: Button = null
var _filter_unprofit_btn: Button = null
var _filter_produce := false
var _filter_profitable := false
var _filter_unprofitable := false

var _built := false   # lightweight tab shell exists; each tab's real controls build on first selection
var _tab_roots: Dictionary = {}
var _tab_built: Dictionary = {}
var _pending_buildings_tile_filter := ""

# Coalesced refresh (notification_bell pattern): prices_updated, orders_changed
# and turn_processed each triggered their own full refresh — ~130 row updates
# plus a complete special-orders rebuild, several times per turn, even while
# the panel was hidden. Signals now set a dirty flag and defer ONE refresh; a
# hidden panel stays dirty and repaints once on show.
var _refresh_queued := false
var _dirty := false


## Build only the tab shell on first open. The old eager path built every Market tab
## synchronously; the selected tab now pays only for its own controls.
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	_build_tabs()


func _ready() -> void:
	add_theme_stylebox_override("panel", preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(8.0))
	title_label.text = "Market"
	close_button.pressed.connect(hide)
	MarketState.prices_updated.connect(_queue_refresh)
	MatchState.show_construct_for_good.connect(_on_show_construct_for_good)
	MatchState.transfer_for_good_requested.connect(func(_g: String) -> void: hide())
	MatchState.purchase_for_good_requested.connect(func(_g: String) -> void: hide())
	SpecialOrderState.orders_changed.connect(_queue_refresh)
	visibility_changed.connect(_on_panel_visibility_changed)
	Production.turn_processed.connect(_queue_refresh)

func _queue_refresh(_a: Variant = null) -> void:
	_dirty = true
	if _refresh_queued:
		return
	_refresh_queued = true
	call_deferred("_apply_queued_refresh")

func _apply_queued_refresh() -> void:
	_refresh_queued = false
	if not _dirty or not visible:
		return  # hidden panels stay dirty and repaint once on show
	_dirty = false
	for row in rows:
		if is_instance_valid(row) and row.has_method("_refresh"):
			row._refresh()
	_update_filter_availability()
	_refresh_special_orders()
	_refresh_ledgers()

func _rebuild_header() -> void:
	for c in header_static.get_children():
		header_static.remove_child(c)
		c.queue_free()
	header_static.add_theme_constant_override("separation", 10)
	header_static.add_child(_header_spacer(98.0))             # framed icon column
	header_static.add_child(_header_label("Product", 240.0, Color(0, 0, 0, 0), false))
	header_static.add_child(_header_label("Sale now", 70.0, SALE_TINT))
	header_static.add_child(_header_label("Sale +10t", 80.0, SALE_TINT))
	header_static.add_child(_header_label("Buy now", 70.0, BUY_TINT))
	header_static.add_child(_header_label("Buy +10t", 80.0, BUY_TINT))
	header_static.add_child(_header_label("Impact\nthresholds", 110.0))
	header_static.add_child(_header_label("Sold", 60.0))
	header_static.add_child(_header_label("Bought", 64.0))
	header_static.add_child(_header_label("Cost/unit", 100.0))
	header_static.add_child(_header_label("Profit/unit", 110.0))

const SALE_TINT := Color(0.82, 0.85, 0.90, 0.10)
const BUY_TINT := Color(0.50, 0.53, 0.58, 0.22)
const SPECIAL_ORDER_ICON_SIZE := 98
const SPECIAL_ORDER_PRODUCT_W := 240.0
const SPECIAL_ORDER_NAME_BOUND := "Electrical Components"
const SPECIAL_ORDER_NAME_RIGHT_PAD := 20.0
const SPECIAL_ORDER_NAME_FS_MAX := 30
const SPECIAL_ORDER_NAME_FS_MIN := 14
const SPECIAL_ORDER_FIELD_FS := 19
const SPECIAL_ORDER_COLUMNS := [
	{"key": "target", "label": "Target", "w": 80.0, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "committed", "label": "Committed", "w": 90.0, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "delivered", "label": "Delivered", "w": 100.0, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "due", "label": "Due", "w": 90.0, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "premium", "label": "Premium", "w": 80.0, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "bonus", "label": "Bonus", "w": 100.0, "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "producer", "label": "Producer", "w": 180.0, "align": HORIZONTAL_ALIGNMENT_LEFT},
]

func _header_label(text: String, width: float, tint: Color = Color(0, 0, 0, 0), center: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(width, 0)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if tint.a > 0.0:
		var box := StyleBoxFlat.new()
		box.bg_color = tint
		box.content_margin_left = 6
		box.content_margin_right = 6
		l.add_theme_stylebox_override("normal", box)
	return l

func _header_spacer(width: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 0)
	return c

func _on_show_construct_for_good(_good_id: String) -> void:
	hide()  # close the market panel; the construct panel opens itself filtered

func _on_building_for_sale_selected(instance_id: String) -> void:
	# Open the building detail panel (world_map pans + shows it), then close this panel so it
	# isn't left covering the focused building — mirrors the Building Ledger's row click.
	MatchState.focus_building_requested.emit(instance_id)
	hide()

func _centre_and_resize() -> void:
	# Wide enough to show every column without sideways scrolling, centred on
	# screen (capped to the viewport on narrow displays).
	var vp := get_viewport_rect().size
	var w := minf(1220.0, vp.x - 60.0)
	var base_h := minf(640.0, vp.y - 80.0)
	# 30% taller than the old (base_h + 40) panel, with ALL the extra height added
	# upward — the bottom edge stays put and the top grows up — so the rows get more room.
	var h := (base_h + 40.0) * 1.30
	var centred_top := maxf(40.0, (vp.y - base_h) / 2.0)
	var bottom := centred_top + base_h  # where the old panel's bottom sat — keep it fixed
	offset_left = maxf(0.0, (vp.x - w) / 2.0)
	# grow upward, but never above the top bar (owner 2026-07-11: was clamped to 8).
	offset_top = maxf(86.0, bottom - h)
	offset_right = offset_left + w
	offset_bottom = bottom

func _on_panel_visibility_changed() -> void:
	if not visible:
		# The tile filter is temporary — drop it when the Market closes so a normal reopen
		# (via the Market button) shows every building again.
		if _buildings_tab != null:
			_buildings_tab.clear_tile_filter(false)
		return
	_ensure_built()   # first open builds the cheap tab shell
	_centre_and_resize()
	if _dirty:
		_queue_refresh()  # catch up on turns that passed while hidden
	_ensure_current_tab_built()
	_refresh_ledgers()
	_refresh_special_orders()
	_update_filter_availability()
	# Fresh open: clear the stale "recurring" choice on the Sales tab.
	if _recurring_check != null:
		_recurring_check.set_pressed_no_signal(false)

func _build_tabs() -> void:
	var tabs := TabContainer.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL

	tabs.add_child(_make_lazy_tab(TAB_PRICES, "Good prices"))
	tabs.add_child(_make_lazy_tab(TAB_BUILDINGS, "Buildings"))
	tabs.add_child(_make_lazy_tab(TAB_SPECIAL_ORDERS, "Special Orders"))
	tabs.add_child(_make_lazy_tab(TAB_SALES, "Sales"))
	tabs.add_child(_make_lazy_tab(TAB_TRANSACTIONS, "Transactions"))
	tabs.add_child(_make_lazy_tab(TAB_MOVEMENTS, "Movements"))
	tabs.tab_changed.connect(_on_tab_changed)

	_tabs = tabs
	main_vbox.add_child(tabs)

	# Keep the scene-authored price table controls owned by the Good Prices tab, but
	# leave its rows/filter unbuilt until that tab is the first visible tab.
	var prices_tab := _tab_roots.get(TAB_PRICES, null) as VBoxContainer
	if prices_tab != null:
		_detach(header_static)
		_detach(scroll)
		prices_tab.add_child(header_static)
		prices_tab.add_child(scroll)

func _make_lazy_tab(key: String, title: String) -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = title
	tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab.add_theme_constant_override("separation", 6)
	tab.set_meta("market_tab_key", key)
	_tab_roots[key] = tab
	_tab_built[key] = false
	return tab

func _on_tab_changed(tab: int) -> void:
	_ensure_tab_built(_tab_key_for_index(tab))

func _ensure_current_tab_built() -> void:
	if _tabs == null:
		return
	_ensure_tab_built(_tab_key_for_index(_tabs.current_tab))

func _tab_key_for_index(tab: int) -> String:
	if _tabs == null or tab < 0 or tab >= _tabs.get_child_count():
		return ""
	var control := _tabs.get_child(tab) as Control
	if control == null:
		return ""
	return str(control.get_meta("market_tab_key", ""))

func _ensure_tab_built(key: String) -> void:
	if key == "" or bool(_tab_built.get(key, false)):
		return
	var root := _tab_roots.get(key, null) as VBoxContainer
	if root == null:
		return
	match key:
		TAB_PRICES:
			_build_prices_tab(root)
		TAB_BUILDINGS:
			_build_buildings_tab(root)
		TAB_SPECIAL_ORDERS:
			_build_special_orders_lazy_tab(root)
		TAB_SALES:
			_build_sales_tab(root)
		TAB_TRANSACTIONS:
			_build_ledger_lazy_tab(root, "Transactions",
				MatchState.get_recurring_transaction_rows, MatchState.get_oneoff_transaction_rows)
		TAB_MOVEMENTS:
			_build_movements_tab(root)
	_tab_built[key] = true

func _build_prices_tab(root: VBoxContainer) -> void:
	for child in root.get_children():
		if child != header_static and child != scroll:
			child.queue_free()
	_rebuild_header()
	_build_content()
	_detach(header_static)
	_detach(scroll)
	root.add_child(_build_filter_row())
	root.add_child(header_static)
	root.add_child(scroll)
	_update_filter_availability()

func _build_buildings_tab(root: VBoxContainer) -> void:
	_buildings_tab = BuildingMarketTab.new()
	_buildings_tab.name = "BuildingsContent"
	_buildings_tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_buildings_tab.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_buildings_tab.building_selected.connect(_on_building_for_sale_selected)
	root.add_child(_buildings_tab)
	if _pending_buildings_tile_filter != "":
		_buildings_tab.set_tile_filter(_pending_buildings_tile_filter)
		_pending_buildings_tile_filter = ""
	elif _buildings_tab.has_method("ensure_built"):
		_buildings_tab.ensure_built()

func _build_special_orders_lazy_tab(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", 8)
	_adopt_children(_build_special_orders_tab(), root)
	_refresh_special_orders()

func _build_sales_tab(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", 12)
	root.add_child(_build_recurring_orders_section("sells"))
	var sep := HSeparator.new()
	root.add_child(sep)
	_build_bulk_sell_section(root)

func _build_movements_tab(root: VBoxContainer) -> void:
	root.add_theme_constant_override("separation", 12)
	root.add_child(_build_recurring_orders_section("moves"))
	# One-off moves remain a view-only accordion (they can't be "cancelled" — they fire once).
	# Wrapped in its own scroll so a turn with many one-offs fills the remaining space and
	# scrolls internally rather than clipping under the fixed panel height.
	var oneoff_scroll := ScrollContainer.new()
	oneoff_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	oneoff_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	oneoff_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var oneoff := _make_accordion()
	oneoff_scroll.add_child(oneoff.root)
	root.add_child(oneoff_scroll)
	var refresh := func() -> void:
		_populate_accordion(oneoff, "One-off", MatchState.get_oneoff_move_rows())
	_ledger_refreshers.append(refresh)
	refresh.call()

func _build_ledger_lazy_tab(root: VBoxContainer, title: String, recurring_getter: Callable, oneoff_getter: Callable) -> void:
	_adopt_children(_build_ledger_tab(title, recurring_getter, oneoff_getter), root)

func _adopt_children(source: Control, target: Control) -> void:
	for child in source.get_children():
		source.remove_child(child)
		target.add_child(child)
	source.queue_free()

func _detach(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)

# Open the Market on the Buildings tab, filtered to a single tile's buildings (a temporary
# filter that the player can clear). Called from the tile view's "Buy Buildings" button.
func open_buildings_for_tile(tile_id: String) -> void:
	_pending_buildings_tile_filter = tile_id
	_ensure_built()   # may be opened before the market was ever shown
	if _tabs == null:
		return
	var buildings_root := _tab_roots.get(TAB_BUILDINGS, null) as Control
	if buildings_root == null:
		return
	_tabs.current_tab = buildings_root.get_index()
	_ensure_tab_built(TAB_BUILDINGS)
	if _buildings_tab != null:
		_buildings_tab.set_tile_filter(tile_id)

func _build_ledger_tab(title: String, recurring_getter: Callable, oneoff_getter: Callable) -> VBoxContainer:
	# View-only ledger: a "Recurring" accordion + a "One-off" accordion, each a small table.
	var tab := VBoxContainer.new()
	tab.name = title
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	tab.add_child(scroll)

	var recurring := _make_accordion()
	var oneoff := _make_accordion()
	body.add_child(recurring.root)
	body.add_child(oneoff.root)

	var refresh := func() -> void:
		_populate_accordion(recurring, "Recurring", recurring_getter.call())
		_populate_accordion(oneoff, "One-off", oneoff_getter.call())
	_ledger_refreshers.append(refresh)
	refresh.call()
	return tab

func _make_accordion() -> Dictionary:
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := Button.new()
	header.toggle_mode = true
	header.button_pressed = true
	header.alignment = HORIZONTAL_ALIGNMENT_LEFT
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(header)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(content)
	var acc := {"root": root, "header": header, "content": content, "title": ""}
	header.toggled.connect(func(pressed: bool) -> void:
		content.visible = pressed
		header.text = ("▾ " if pressed else "▸ ") + str(acc.get("title", ""))
	)
	return acc

func _populate_accordion(acc: Dictionary, label: String, rows: Array) -> void:
	var content: VBoxContainer = acc.content
	for c in content.get_children():
		c.queue_free()
	acc["title"] = "%s (%d)" % [label, rows.size()]
	var expanded: bool = acc.header.button_pressed
	acc.header.text = ("▾ " if expanded else "▸ ") + str(acc.title)
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "  None"
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.7, 0.7, 0.7)
		content.add_child(empty)
		return
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	content.add_child(grid)
	for h in ["Type", "From", "To", "Good", "Qty", "Started", "Ended"]:
		grid.add_child(_ledger_cell(h, true))
	for r in rows:
		grid.add_child(_ledger_cell(str(r.get("type", "")), false))
		grid.add_child(_ledger_cell(str(r.get("from", "")), false))
		grid.add_child(_ledger_cell(str(r.get("to", "")), false))
		grid.add_child(_ledger_cell(str(r.get("good", "")), false))
		grid.add_child(_ledger_cell("—" if int(r.get("qty", 0)) < 0 else str(int(r.get("qty", 0))), false))
		grid.add_child(_ledger_cell("T%d" % int(r.get("turn_started", 0)), false))
		grid.add_child(_ledger_cell(_format_turn_ended(int(r.get("turn_ended", -1))), false))

func _ledger_cell(text: String, is_header: bool) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	if is_header:
		lbl.modulate = Color(0.7, 0.85, 1.0)
	return lbl

func _format_turn_ended(ended: int) -> String:
	if ended < 0 or ended > int(TurnManager.current_turn):
		return "Ongoing"
	return "T%d" % ended

func _refresh_ledgers(_summary: Dictionary = {}) -> void:
	# Accept the optional summary arg so the turn_processed signal (which emits one)
	# can connect directly without an arg-count error.
	if not visible:
		return
	for refresh in _ledger_refreshers:
		refresh.call()

func _build_bulk_sell_section(parent: VBoxContainer) -> void:
	# Stories 4 & 5: sell across many/all tiles to market, with good / finished / threshold filters.
	var header := Label.new()
	header.text = "Sell to market (bulk)"
	header.add_theme_font_size_override("font_size", 16)
	parent.add_child(header)

	_good_option = OptionButton.new()
	_good_option.add_item("All goods")
	_good_option.set_item_metadata(0, "")
	for g in Catalog.sellable_goods():
		_good_option.add_item(str(g.display_name))
		_good_option.set_item_metadata(_good_option.item_count - 1, str(g.id))
	parent.add_child(_make_labeled_row("Good", _good_option))

	_finished_check = UIHelpers.make_custom_checkbox()
	parent.add_child(UIHelpers.make_setting_row("Finished goods only (non-raw)", _finished_check))

	_keep_spin = SpinBox.new()
	_keep_spin.min_value = 0
	_keep_spin.max_value = 100000
	_keep_spin.step = 1
	_keep_spin.value = 0
	parent.add_child(_make_labeled_row("Keep per tile", _keep_spin))

	_recurring_check = UIHelpers.make_custom_checkbox()
	parent.add_child(UIHelpers.make_setting_row("Make recurring every turn", _recurring_check))

	var sell_btn := Button.new()
	sell_btn.text = "Sell from all tiles"
	sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell_btn.pressed.connect(_on_bulk_sell_pressed)
	parent.add_child(sell_btn)

func _make_labeled_row(label_text: String, control: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row

func _on_bulk_sell_pressed() -> void:
	var params := {
		"good_id": str(_good_option.get_item_metadata(_good_option.selected)),
		"finished_only": _finished_check.button_pressed,
		"per_tile_keep": int(_keep_spin.value),
	}
	var result: Dictionary = MatchState.sell_all_to_market(params)
	var qty := int(result.get("total_qty", 0))
	var tiles := int(result.get("tiles", 0))
	if qty > 0:
		MatchState.request_toast("Selling %d units from %d tile%s to market" % [
			qty, tiles, "" if tiles == 1 else "s"], "success")
	else:
		MatchState.request_toast("Nothing to sell with those filters", "warning")
	if _recurring_check != null and _recurring_check.button_pressed:
		MatchState.add_recurring_bulk_sell(params)

# ── Recurring orders list (Movements + Sales tabs) ───────────────────────────
# A searchable, filterable list of standing orders — one card per recurring move /
# sell / bulk-sell — each with a double-width good-icon slot (up to two icons) and a
# Cancel button. `kind` is "moves" (recurring_moves) or "sells" (recurring_sells +
# recurring_bulk_sells). Refreshes on recurring_orders_changed and every turn.
const REC_ROW_H := 56.0
const REC_ICON := 40            # frame_size is int (UIHelpers.make_framed_good_icon)
const REC_ICON_SLOT_W := 92.0   # double-width: fits two REC_ICON frames + gap

func _build_recurring_orders_section(kind: String) -> Control:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Recurring moves" if kind == "moves" else "Recurring sales"
	title.add_theme_font_size_override("font_size", 16)
	section.add_child(title)

	# Per-section filter state, shared (by reference) between the widgets and the
	# refresh closure so edits are visible to the rebuild.
	var state := {"q": "", "good": ""}

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	var search := LineEdit.new()
	search.placeholder_text = "Search good or tile…"
	search.clear_button_enabled = true
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size = Vector2(180, 0)
	bar.add_child(search)
	var good_opt := OptionButton.new()
	good_opt.custom_minimum_size = Vector2(150, 0)
	bar.add_child(good_opt)
	section.add_child(bar)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 210)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	section.add_child(scroll)

	var refresh := func() -> void:
		_refresh_recurring_list(kind, list, good_opt, state)
	search.text_changed.connect(func(t: String) -> void:
		state["q"] = t.strip_edges().to_lower()
		refresh.call())
	good_opt.item_selected.connect(func(i: int) -> void:
		state["good"] = str(good_opt.get_item_metadata(i))
		refresh.call())
	_ledger_refreshers.append(refresh)
	if not MatchState.recurring_orders_changed.is_connected(refresh):
		MatchState.recurring_orders_changed.connect(refresh)
	refresh.call()
	return section

func _refresh_recurring_list(kind: String, list: VBoxContainer, good_opt: OptionButton, state: Dictionary) -> void:
	var entries := _recurring_entries(kind)
	_sync_recurring_good_filter(good_opt, entries, state)
	for c in list.get_children():
		c.queue_free()
	var shown := 0
	for item in entries:
		if not _recurring_matches(item, state):
			continue
		list.add_child(_recurring_row(item))
		shown += 1
	if shown == 0:
		var empty := Label.new()
		var noun := "moves" if kind == "moves" else "sales"
		var filtered: bool = str(state.get("q", "")) != "" or str(state.get("good", "")) != ""
		empty.text = "  No recurring %s%s" % [noun, " match your search" if filtered else " yet"]
		empty.add_theme_font_size_override("font_size", 12)
		empty.modulate = Color(0.7, 0.7, 0.7)
		list.add_child(empty)

# Flatten the raw recurring arrays into uniform view items:
#   {entry, sub: "move"|"sell"|"bulk", source, dest, goods: {good_id:qty}, params?}
# `entry` is the exact dict held by MatchState, so Cancel can erase-by-value.
func _recurring_entries(kind: String) -> Array:
	var out: Array = []
	if kind == "moves":
		for m in MatchState.recurring_moves:
			out.append({"entry": m, "sub": "move",
				"source": str(m.get("source", "")), "dest": str(m.get("dest", "")),
				"goods": m.get("goods", {})})
	else:
		for s in MatchState.recurring_sells:
			out.append({"entry": s, "sub": "sell",
				"source": str(s.get("source", "")), "dest": "",
				"goods": s.get("goods", {})})
		for b in MatchState.recurring_bulk_sells:
			var p: Dictionary = b.get("params", {})
			var gid := str(p.get("good_id", ""))
			out.append({"entry": b, "sub": "bulk", "source": "", "dest": "",
				"goods": ({gid: 0} if gid != "" else {}), "params": p})
	return out

# Rebuild the good dropdown from the goods present in the current orders, preserving
# the selection where possible (and clearing it if that good is gone).
func _sync_recurring_good_filter(good_opt: OptionButton, entries: Array, state: Dictionary) -> void:
	var goods := {}
	for item in entries:
		for gid in (item.get("goods", {}) as Dictionary).keys():
			if str(gid) != "":
				goods[str(gid)] = true
	var keys := goods.keys()
	keys.sort()
	good_opt.clear()
	good_opt.add_item("All goods")
	good_opt.set_item_metadata(0, "")
	var sel := 0
	for gid in keys:
		good_opt.add_item(Catalog.get_display_name(str(gid)))
		good_opt.set_item_metadata(good_opt.item_count - 1, str(gid))
		if str(gid) == str(state.get("good", "")):
			sel = good_opt.item_count - 1
	if str(state.get("good", "")) != "" and sel == 0:
		state["good"] = ""   # the filtered good no longer has a standing order
	good_opt.select(sel)

func _recurring_matches(item: Dictionary, state: Dictionary) -> bool:
	var good_filter := str(state.get("good", ""))
	var goods: Dictionary = item.get("goods", {})
	if good_filter != "" and not goods.has(good_filter):
		return false
	var q := str(state.get("q", ""))
	if q == "":
		return true
	var blob := ""
	for gid in goods.keys():
		blob += Catalog.get_display_name(str(gid)).to_lower() + " "
	if str(item.get("source", "")) != "":
		blob += Catalog.tile_label(str(item.source)).to_lower() + " "
	if str(item.get("dest", "")) != "":
		blob += Catalog.tile_label(str(item.dest)).to_lower() + " "
	if str(item.get("sub", "")) == "bulk":
		blob += "bulk all goods every tile"
	return blob.contains(q)

func _recurring_row(item: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BG_INSET
	sb.border_color = DS.PALETTE.BORDER_SOFT
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	card.add_theme_stylebox_override("panel", sb)

	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(0, REC_ROW_H)
	hb.add_theme_constant_override("separation", 10)
	card.add_child(hb)

	# Double-width icon slot: up to two good icons, then a "+N" if more.
	var slot := HBoxContainer.new()
	slot.custom_minimum_size = Vector2(REC_ICON_SLOT_W, 0)
	slot.add_theme_constant_override("separation", 4)
	slot.alignment = BoxContainer.ALIGNMENT_BEGIN
	var gids: Array = (item.get("goods", {}) as Dictionary).keys()
	for i in mini(2, gids.size()):
		var gid := str(gids[i])
		slot.add_child(UIHelpers.make_framed_good_icon(gid, Catalog.get_internal_name(gid), REC_ICON))
	if gids.size() > 2:
		var more := Label.new()
		more.text = "+%d" % (gids.size() - 2)
		more.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		more.add_theme_font_size_override("font_size", 12)
		more.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
		slot.add_child(more)
	hb.add_child(slot)

	# Two-line description: route/target on top, goods summary below.
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 1)
	var line1 := Label.new()
	line1.text = _recurring_title(item)
	line1.add_theme_font_size_override("font_size", 14)
	line1.clip_text = true
	col.add_child(line1)
	var line2 := Label.new()
	line2.text = _recurring_goods_summary(item)
	line2.theme_type_variation = "Caption"
	line2.add_theme_font_size_override("font_size", 11)
	line2.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	line2.clip_text = true
	col.add_child(line2)
	hb.add_child(col)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.focus_mode = Control.FOCUS_NONE
	cancel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cancel.tooltip_text = "Stop this recurring order"
	var entry: Dictionary = item.get("entry", {})
	var sub := str(item.get("sub", ""))
	cancel.pressed.connect(func() -> void: _cancel_recurring(sub, entry))
	hb.add_child(cancel)
	return card

func _cancel_recurring(sub: String, entry: Dictionary) -> void:
	var ok := false
	match sub:
		"move":
			ok = MatchState.remove_recurring_move(entry)
		"sell":
			ok = MatchState.remove_recurring_sell(entry)
		"bulk":
			ok = MatchState.remove_recurring_bulk_sell(entry)
	if ok:
		MatchState.request_toast("Recurring order cancelled", "success")

func _recurring_title(item: Dictionary) -> String:
	match str(item.get("sub", "")):
		"move":
			return "%s  →  %s" % [Catalog.tile_label(str(item.source)), Catalog.tile_label(str(item.dest))]
		"sell":
			return "Sell from %s" % Catalog.tile_label(str(item.source))
		"bulk":
			var gid := str((item.get("params", {}) as Dictionary).get("good_id", ""))
			return "Bulk sell: %s" % ("all goods" if gid == "" else Catalog.get_display_name(gid))
	return ""

func _recurring_goods_summary(item: Dictionary) -> String:
	if str(item.get("sub", "")) == "bulk":
		var p: Dictionary = item.get("params", {})
		var extra := " · finished only" if bool(p.get("finished_only", false)) else ""
		return "keep %d per tile%s · every turn" % [int(p.get("per_tile_keep", 0)), extra]
	var parts: Array = []
	var goods: Dictionary = item.get("goods", {})
	for gid in goods.keys():
		parts.append("%s ×%d" % [Catalog.get_display_name(str(gid)), int(goods[gid])])
	if parts.is_empty():
		return "every turn"
	return ", ".join(parts) + " · every turn"

# ── Special Orders tab ───────────────────────────────────────────────────────
func _build_special_orders_tab() -> VBoxContainer:
	var tab := VBoxContainer.new()
	tab.name = "Special Orders"
	tab.add_theme_constant_override("separation", 8)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	_special_orders_count_label = Label.new()
	_special_orders_count_label.theme_type_variation = "Body"
	_special_orders_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_special_orders_count_label)
	tab.add_child(top)

	var header_wrap := MarginContainer.new()
	header_wrap.add_theme_constant_override("margin_left", 8)
	header_wrap.add_theme_constant_override("margin_right", 8)
	header_wrap.add_child(_build_special_orders_header_row())
	tab.add_child(header_wrap)

	var scroll_orders := ScrollContainer.new()
	scroll_orders.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_orders.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_special_orders_body = VBoxContainer.new()
	_special_orders_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_special_orders_body.add_theme_constant_override("separation", 6)
	scroll_orders.add_child(_special_orders_body)
	tab.add_child(scroll_orders)
	return tab

func _build_special_orders_header_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(_header_spacer(SPECIAL_ORDER_ICON_SIZE))
	row.add_child(_header_label("Product", SPECIAL_ORDER_PRODUCT_W, Color(0, 0, 0, 0), false))
	for col in SPECIAL_ORDER_COLUMNS:
		row.add_child(_special_orders_header_label(str(col.label), float(col.w), int(col.align)))
	return row

func _special_orders_header_label(text: String, w: float, align: int) -> Label:
	var lbl := _header_label(text, w, Color(0, 0, 0, 0), align == HORIZONTAL_ALIGNMENT_CENTER)
	lbl.horizontal_alignment = align
	lbl.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

func _refresh_special_orders() -> void:
	if _special_orders_body == null:
		return
	for child in _special_orders_body.get_children():
		_special_orders_body.remove_child(child)
		child.queue_free()
	var orders: Array = SpecialOrderState.get_active_orders()
	orders.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_expires := int(a.get("expires_turn", 0))
		var b_expires := int(b.get("expires_turn", 0))
		if a_expires != b_expires:
			return a_expires < b_expires
		return str(a.get("good_internal", "")).naturalnocasecmp_to(str(b.get("good_internal", ""))) < 0
	)
	if _special_orders_count_label != null:
		_special_orders_count_label.text = "Active special orders: %d" % orders.size()
	if orders.is_empty():
		_special_orders_body.add_child(_special_orders_empty_state())
		return
	for order in orders:
		_special_orders_body.add_child(_build_special_order_row(order as Dictionary))

func _special_orders_empty_state() -> Label:
	var empty := Label.new()
	empty.text = "No active special orders"
	empty.theme_type_variation = "Body"
	empty.add_theme_color_override("font_color", DS.PALETTE.TEXT_DIM)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	empty.custom_minimum_size = Vector2(0, SPECIAL_ORDER_ICON_SIZE)
	return empty

func _build_special_order_row(order: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.tooltip_text = _special_order_tooltip(order)

	var hbox := HBoxContainer.new()
	hbox.custom_minimum_size = Vector2(0, SPECIAL_ORDER_ICON_SIZE)
	hbox.add_theme_constant_override("separation", 10)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)
	hbox.add_child(UIHelpers.make_framed_good_icon(
		str(order.get("good_id", "")),
		str(order.get("good_internal", "")),
		SPECIAL_ORDER_ICON_SIZE
	))
	hbox.add_child(_special_order_product_button(order))
	for col in SPECIAL_ORDER_COLUMNS:
		hbox.add_child(_build_special_order_cell(col as Dictionary, order))
	return row

func _build_special_order_cell(col: Dictionary, order: Dictionary) -> Control:
	var key := str(col.get("key", ""))
	var w := float(col.get("w", 80.0))
	var align := int(col.get("align", HORIZONTAL_ALIGNMENT_LEFT))
	match key:
		"target":
			return _special_order_text_cell(str(int(order.get("qty_required", 0))), w, align)
		"committed":
			return _special_order_text_cell(str(int(order.get("qty_committed", 0))), w, align, _commitment_color(order))
		"delivered":
			return _special_order_text_cell("%d / %d" % [
				int(order.get("qty_delivered", 0)),
				int(order.get("qty_required", 0)),
			], w, align)
		"due":
			return _special_order_text_cell(_special_order_due_text(order), w, align, _deadline_color(order))
		"premium":
			return _special_order_text_cell("+%d%%" % int(round(float(order.get("premium_pct", 0.0)) * 100.0)), w, align)
		"bonus":
			return _special_order_text_cell(_money_text(_special_order_bonus_estimate(order)), w, align)
		"producer":
			return _special_order_text_cell(_special_order_producer_text(order), w, align)
	return _special_order_text_cell("", w, align)

func _special_order_product_button(order: Dictionary) -> Button:
	var btn := Button.new()
	btn.text = _special_order_good_name(order)
	btn.clip_text = true
	btn.custom_minimum_size = Vector2(SPECIAL_ORDER_PRODUCT_W, SPECIAL_ORDER_ICON_SIZE)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.focus_mode = Control.FOCUS_NONE
	btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.tooltip_text = "Created T%d, expires T%d" % [
		int(order.get("created_turn", 0)),
		int(order.get("expires_turn", 0)),
	]
	btn.add_theme_font_size_override("font_size", _fit_special_order_name_font_size(btn))
	return btn

func _fit_special_order_name_font_size(btn: Button) -> int:
	var font := btn.get_theme_font("font")
	if font == null:
		return SPECIAL_ORDER_NAME_FS_MAX
	var left_margin := 8.0
	var sb := btn.get_theme_stylebox("normal")
	if sb != null:
		left_margin = maxf(0.0, sb.get_margin(SIDE_LEFT))
	var avail := SPECIAL_ORDER_PRODUCT_W - left_margin - SPECIAL_ORDER_NAME_RIGHT_PAD
	var fs := SPECIAL_ORDER_NAME_FS_MAX
	while fs > SPECIAL_ORDER_NAME_FS_MIN:
		if font.get_string_size(SPECIAL_ORDER_NAME_BOUND, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail:
			break
		fs -= 1
	return fs

func _special_order_text_cell(text: String, w: float, align: int, color: Color = Color.TRANSPARENT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(w, SPECIAL_ORDER_ICON_SIZE)
	lbl.horizontal_alignment = align
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.theme_type_variation = "Body"
	lbl.clip_text = true
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", SPECIAL_ORDER_FIELD_FS)
	lbl.add_theme_color_override("font_color", DS.PALETTE.TEXT if color.a == 0.0 else color)
	return lbl

func _special_order_good_name(order: Dictionary) -> String:
	var display := str(order.get("display_name", ""))
	if display != "":
		return display
	var gid := str(order.get("good_id", ""))
	return Catalog.get_display_name(gid)

func _special_order_due_text(order: Dictionary) -> String:
	var expires := int(order.get("expires_turn", 0))
	var left := expires - int(TurnManager.current_turn)
	if left < 0:
		return "Expired"
	if left == 0:
		return "T%d now" % expires
	return "T%d (%dt)" % [expires, left]

func _deadline_color(order: Dictionary) -> Color:
	var left := int(order.get("expires_turn", 0)) - int(TurnManager.current_turn)
	if left <= 2:
		return Color(0.95, 0.72, 0.22)
	return Color.TRANSPARENT

func _commitment_color(order: Dictionary) -> Color:
	if int(order.get("qty_committed", 0)) <= 0:
		return DS.PALETTE.TEXT_DIM
	return Color.TRANSPARENT

func _special_order_bonus_estimate(order: Dictionary) -> float:
	var gid := str(order.get("good_id", ""))
	if gid == "":
		return 0.0
	var internal := str(order.get("good_internal", ""))
	var unit_price := MarketState.get_price(gid)
	unit_price = Modifiers.apply("market_price", gid, unit_price, {
		"good_id": gid,
		"good_internal": internal,
	})
	return float(order.get("qty_required", 0)) * unit_price * float(order.get("premium_pct", 0.0))

func _special_order_producer_text(order: Dictionary) -> String:
	var building_id := str(order.get("baseline_building_id", ""))
	var building := Catalog.get_building(building_id)
	var name := str(building.get("display_name", ""))
	if name == "":
		name = str(building.get("internal_name", ""))
	var turns := int(order.get("target_production_turns", 0))
	if name == "":
		return "%dt" % turns
	return "%s, %dt" % [name, turns]

func _special_order_tooltip(order: Dictionary) -> String:
	return "%s: %d required, %d committed, %d delivered" % [
		_special_order_good_name(order),
		int(order.get("qty_required", 0)),
		int(order.get("qty_committed", 0)),
		int(order.get("qty_delivered", 0)),
	]

func _money_text(value: float) -> String:
	return "£%.0f" % value

# ── Filter bar ───────────────────────────────────────────────────────────────
func _build_filter_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	_search = LineEdit.new()
	_search.placeholder_text = "Search products…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL  # pushes filters to the right
	_search.custom_minimum_size = Vector2(180, 0)
	_search.text_changed.connect(func(_t: String) -> void: _apply_filters())
	row.add_child(_search)

	_filter_produce_btn = _make_filter_button("Goods you produce")
	_filter_profit_btn = _make_filter_button("Profitable Goods")
	_filter_unprofit_btn = _make_filter_button("Unprofitable Goods")
	_filter_produce_btn.toggled.connect(func(p: bool) -> void: _on_filter_toggled("produce", p))
	_filter_profit_btn.toggled.connect(func(p: bool) -> void: _on_filter_toggled("profit", p))
	_filter_unprofit_btn.toggled.connect(func(p: bool) -> void: _on_filter_toggled("unprofit", p))
	row.add_child(_filter_produce_btn)
	row.add_child(_filter_profit_btn)
	row.add_child(_filter_unprofit_btn)

	_update_filter_availability()
	return row

func _make_filter_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.add_theme_stylebox_override("normal", _filter_box(DS.PALETTE.BG_INSET, DS.PALETTE.BORDER_SOFT))
	b.add_theme_stylebox_override("hover", _filter_box(DS.PALETTE.BG_HIGHLIGHT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("pressed", _filter_box(DS.PALETTE.ACCENT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("hover_pressed", _filter_box(DS.PALETTE.ACCENT, DS.PALETTE.ACCENT))
	b.add_theme_stylebox_override("disabled", _filter_box(DS.PALETTE.BG_PANEL, DS.PALETTE.BORDER_SOFT))
	b.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	b.add_theme_color_override("font_hover_color", DS.PALETTE.TEXT)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)        # selected
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", DS.PALETTE.TEXT_DIM)
	return b

func _filter_box(bg: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _on_filter_toggled(which: String, pressed: bool) -> void:
	match which:
		"produce":
			_filter_produce = pressed
		"profit":
			_filter_profitable = pressed
			# Profitable and Unprofitable are mutually exclusive.
			if pressed and _filter_unprofit_btn.button_pressed:
				_filter_unprofit_btn.set_pressed_no_signal(false)
				_filter_unprofitable = false
		"unprofit":
			_filter_unprofitable = pressed
			if pressed and _filter_profit_btn.button_pressed:
				_filter_profit_btn.set_pressed_no_signal(false)
				_filter_profitable = false
	_apply_filters()

func _apply_filters() -> void:
	var q := _search.text.strip_edges().to_lower() if _search != null else ""
	for row in rows:
		if not is_instance_valid(row):
			continue
		var show := true
		if q != "" and not Catalog.get_display_name(row.good_id).to_lower().contains(q):
			show = false
		if show and _filter_produce and not row.is_produced():
			show = false
		if show and _filter_profitable:
			var p: float = row.profit_per_unit()
			if is_nan(p) or p <= 0.0:
				show = false
		if show and _filter_unprofitable:
			var p2: float = row.profit_per_unit()
			if is_nan(p2) or p2 >= 0.0:
				show = false
		row.visible = show

func _update_filter_availability() -> void:
	if _filter_produce_btn == null:
		return
	var any_produce := false
	var any_profit := false
	var any_unprofit := false
	for row in rows:
		if not is_instance_valid(row):
			continue
		if row.is_produced():
			any_produce = true
		var p: float = row.profit_per_unit()
		if not is_nan(p):
			if p > 0.0:
				any_profit = true
			elif p < 0.0:
				any_unprofit = true
	_set_filter_enabled(_filter_produce_btn, any_produce, "You don't produce any goods yet.")
	_set_filter_enabled(_filter_profit_btn, any_profit, "No goods were sold at a profit last turn.")
	_set_filter_enabled(_filter_unprofit_btn, any_unprofit, "No goods were sold at a loss last turn.")
	_apply_filters()

func _set_filter_enabled(btn: Button, enabled: bool, reason: String) -> void:
	btn.disabled = not enabled
	btn.tooltip_text = "" if enabled else reason
	if not enabled and btn.button_pressed:
		btn.set_pressed_no_signal(false)
		if btn == _filter_produce_btn:
			_filter_produce = false
		elif btn == _filter_profit_btn:
			_filter_profitable = false
		elif btn == _filter_unprofit_btn:
			_filter_unprofitable = false

func _build_content() -> void:
	for child in content_vbox.get_children():
		child.queue_free()
	rows.clear()
	
	var all_goods = Catalog.all_goods()
	for good_data in all_goods:
		var row := MarketRowScene.instantiate()
		content_vbox.add_child(row)
		row.setup(good_data)
		rows.append(row)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			# Only start drag if click is in the top strip
			if event.position.y > HEADER_HEIGHT:
				return
			_dragging = true
			_drag_offset = global_position - get_global_mouse_position()
			accept_event()
		else:
			_dragging = false
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
