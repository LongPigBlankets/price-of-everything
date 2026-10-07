extends PanelContainer
## The market panel: the exchange (scripts/market_ds2/market_ds2.gd, docs/market-ds2-plan.md) in its own margin
## over the steel backing, and the sell panel (scripts/market_sell_panel.gd) laid over it while open.

const MarketDs2 := preload("res://scripts/market_ds2/market_ds2.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")
## The panel's one width, every tab (docs/market-ds2-plan.md §8, decision 2).
const DS2_WIDTH := MarketDs2.WIDTH
const HEADER_HEIGHT := 40.0

var _dragging := false
var _drag_offset := Vector2.ZERO
## The sell panel (scripts/market_sell_panel.gd), made on the first Sell and laid over the panel while open.
var _sell_panel: PanelContainer = null
## The exchange, in its own margin over the backing.
var _ds2: Control = null
# Buying now lives in the per-good "Purchase" flow on the world map (world_map.gd).

# Coalesced refresh (notification_bell pattern): prices_updated, orders_changed
# and turn_processed each set a dirty flag and defer ONE refresh; a hidden panel
# stays dirty and repaints once on show.
var _refresh_queued := false
var _dirty := false


func _ready() -> void:
	MarketState.prices_updated.connect(_queue_refresh)
	MatchState.show_construct_for_good.connect(_on_show_construct_for_good)
	MatchState.transfer_for_good_requested.connect(func(_g: String) -> void: hide())
	MatchState.purchase_for_good_requested.connect(func(_g: String) -> void: hide())
	SpecialOrderState.orders_changed.connect(_queue_refresh)
	visibility_changed.connect(_on_panel_visibility_changed)
	Production.turn_processed.connect(_queue_refresh)
	MarketState.prices_updated.connect(func() -> void:
		if visible:
			_ds2.call("ring"))
	_build()


## Dresses the panel in the steel backing and builds the exchange over it.
func _build() -> void:
	LedgerV3.dress(self).name = "MarketBacking"
	var margin := MarginContainer.new()
	margin.name = "MarketDs2Margin"
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, LedgerV3.CONTENT_MARGIN)
	_ds2 = MarketDs2.new()
	_ds2.set("host", self)
	_ds2.connect("close_requested", hide)
	_ds2.connect("drag_input", _on_ds2_drag)
	margin.add_child(_ds2)
	add_child(margin)
	# The lamp over the whole panel, the sell panel's sheet too (docs/ds2-theme.md §4).
	LampOverlay.attach(self)


## The exchange, for tests and tools.
func ds2() -> Control:
	return _ds2


func _on_ds2_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = global_position - get_global_mouse_position()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset

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
	_ds2.call("refresh")

func _on_show_construct_for_good(_good_id: String) -> void:
	hide()  # close the market panel; the construct panel opens itself filtered

func _centre_and_resize() -> void:
	# The exchange's one width, centred on screen (capped to the viewport on narrow displays).
	var vp := get_viewport_rect().size
	var w := minf(DS2_WIDTH, vp.x - 60.0)
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
		if _sell_panel != null and _sell_panel.visible:
			_sell_panel.call("close")
		# The tile filter is temporary — drop it when the Market closes so a normal reopen
		# (via the Market button) shows every building again.
		_ds2.call("clear_tile_filter")
		return
	_centre_and_resize()
	if str(_ds2.call("current_tab")) == "":
		_ds2.call("show_tab", "prices")
	_dirty = false
	_ds2.call("refresh")

## The tabs' keys, in the order they show (captures and tests page through them).
func tab_keys() -> Array:
	return _ds2.call("tab_keys")


## Shows the tab `key`, building it first if need be.
func show_tab(key: String) -> void:
	_ds2.call("show_tab", key)


# Open the Market on the Buildings tab, filtered to a single tile's buildings (a temporary
# filter that the player can clear). Called from the tile view's "Buy Buildings" button.
func open_buildings_for_tile(tile_id: String) -> void:
	_ds2.call("open_buildings_for_tile", tile_id)

## Opens the sell panel for a good over the panel (a row's Sell key).
func open_sell_panel(good_id: String) -> void:
	if _sell_panel == null:
		_sell_panel = preload("res://scripts/market_sell_panel.gd").new()
		add_child(_sell_panel)
		_sell_panel.connect("sold", func(_r: Dictionary) -> void: _queue_refresh())
	_sell_panel.call("open", good_id)


func sell_panel() -> PanelContainer:
	return _sell_panel


## Views the capture tool shows beyond the tabs (the exchange's hovers).
func capture_views() -> Array:
	return _ds2.call("capture_views")


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
