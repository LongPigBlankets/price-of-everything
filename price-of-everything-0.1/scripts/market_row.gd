extends VBoxContainer
## A market goods row: 60x60 icon + name button + market/cost columns, with an
## expandable Sell / Purchase / Move / Expand action block underneath.

const UIHelpers := preload("res://scripts/ui_helpers.gd")

const ICON_SIZE := 98      # outer plate; icon fills ICON_SIZE - 2×12px frame margin
const NAME_W := 240.0
const NAME_MAX_CHARS := 24
# Name font is sized as large as possible while the longest real name still fits
# the button with NAME_RIGHT_PAD px clear of the right edge.
const NAME_BOUND := "Electrical Components"
const NAME_RIGHT_PAD := 20.0
const NAME_FS_MAX := 30
const NAME_FS_MIN := 14
const COL_PRICE := 70.0
const COL_EST := 80.0
const COL_SOLD := 60.0
const COL_BOUGHT := 64.0
const COL_COST := 100.0
const COL_PROFIT := 110.0
const FIELD_FS := 19  # larger per-field text
const FORECAST := 10  # "price in 10 turns"

const COST_GREEN := Color(0.36, 0.82, 0.40)
const COST_AMBER := Color(0.95, 0.72, 0.22)
const COST_RED := Color(0.90, 0.38, 0.38)
const COST_GREY := Color(0.62, 0.62, 0.62)
const COST_LEGEND := "Green: cheaper than market (<90%) · Amber: about even (90–110%) · Red: dearer than market (>110%)"
# Column tints: the sale pair (light grey) and the purchase pair (medium grey).
const SALE_TINT := Color(0.82, 0.85, 0.90, 0.10)
const BUY_TINT := Color(0.50, 0.53, 0.58, 0.22)

var good_id: String = ""
var internal_name: String = ""

var _price_label: Label = null
var _est_label: Label = null
var _buy_price_label: Label = null
var _buy_est_label: Label = null
var _sold_label: Label = null
var _bought_label: Label = null
var _cost_label: Label = null
var _profit_label: Label = null
var _expand_section: VBoxContainer = null
var _expanded := false

func setup(good_data: Dictionary) -> void:
	good_id = str(good_data.get("id", ""))
	internal_name = str(good_data.get("internal_name", ""))

	var main := HBoxContainer.new()
	main.custom_minimum_size = Vector2(0, ICON_SIZE)  # row height == icon == name button
	main.add_theme_constant_override("separation", 10)
	add_child(main)

	# Icon sits inside the off-white pipe-frame slot. Shared with the mapmode good
	# picker (UIHelpers) so both stay identical. The 98px row uses the small art.
	main.add_child(UIHelpers.make_framed_good_icon(good_id, internal_name, ICON_SIZE))

	# Name button, truncated to NAME_MAX_CHARS so long names don't blow out the column.
	var disp := str(good_data.get("display_name", good_id))
	if disp.length() > NAME_MAX_CHARS:
		disp = disp.substr(0, NAME_MAX_CHARS) + "…"
	var name_btn := Button.new()
	name_btn.text = disp
	name_btn.clip_text = true
	name_btn.custom_minimum_size = Vector2(NAME_W, ICON_SIZE)
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.pressed.connect(_toggle_expand)
	main.add_child(name_btn)
	name_btn.add_theme_font_size_override("font_size", _fit_name_font_size(name_btn))

	_price_label = _make_col(COL_PRICE)
	_est_label = _make_col(COL_EST)
	_buy_price_label = _make_col(COL_PRICE)
	_buy_est_label = _make_col(COL_EST)
	_sold_label = _make_col(COL_SOLD)
	_bought_label = _make_col(COL_BOUGHT)
	_cost_label = _make_col(COL_COST)
	_profit_label = _make_col(COL_PROFIT)
	# Sale pair (light grey) then purchase pair (medium grey).
	_tint_col(_price_label, SALE_TINT)
	_tint_col(_est_label, SALE_TINT)
	_tint_col(_buy_price_label, BUY_TINT)
	_tint_col(_buy_est_label, BUY_TINT)
	for l in [_price_label, _est_label, _buy_price_label, _buy_est_label, _sold_label, _bought_label, _cost_label, _profit_label]:
		main.add_child(l)

	_expand_section = VBoxContainer.new()
	_expand_section.visible = false
	_expand_section.add_theme_constant_override("separation", 4)
	for action in ["Sell", "Purchase", "Move", "Expand"]:
		var b := Button.new()
		b.text = action
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if action == "Expand":
			b.pressed.connect(_on_expand_to_construct)
		elif action == "Move":
			b.pressed.connect(_on_move)
		elif action == "Purchase":
			b.pressed.connect(_on_purchase)
			if not Catalog.is_good_buyable(good_id):
				b.disabled = true
				b.tooltip_text = "This good can't be bought from the market."
		_expand_section.add_child(b)
	add_child(_expand_section)

	if not CostSolver.costs_updated.is_connected(_on_costs_updated):
		CostSolver.costs_updated.connect(_on_costs_updated)
	if not Production.turn_processed.is_connected(_on_turn_processed):
		Production.turn_processed.connect(_on_turn_processed)
	visibility_changed.connect(_on_row_visibility_changed)
	_refresh()

# ── Filter helpers (used by the market panel's filter bar) ───────────────────
## True when the player actually produces this good (a unit cost has been solved).
func is_produced() -> bool:
	return CostSolver.get_good_unit_cost(good_id) >= 0.0

## Profit per unit sold to market last turn, or NAN when there were no sales.
func profit_per_unit() -> float:
	var summary: Dictionary = Production.last_turn_summary
	var sold_entry: Dictionary = summary.get("sold", {}).get(good_id, {})
	var sold_qty := int(sold_entry.get("qty", 0))
	if sold_qty <= 0:
		return NAN
	var uc: float = CostSolver.get_good_unit_cost(good_id)
	var sale_price := float(sold_entry.get("revenue", 0.0)) / float(sold_qty)
	return sale_price - (uc if uc >= 0.0 else 0.0)

func _fit_name_font_size(btn: Button) -> int:
	# Largest font size (<= NAME_FS_MAX) at which NAME_BOUND fits the button width
	# with NAME_RIGHT_PAD px clear of the right edge. Measured against the button's
	# actual theme font + left content margin so it stays correct if the theme changes.
	var font := btn.get_theme_font("font")
	if font == null:
		return NAME_FS_MAX
	var left_margin := 8.0
	var sb := btn.get_theme_stylebox("normal")
	if sb != null:
		left_margin = maxf(0.0, sb.get_margin(SIDE_LEFT))
	var avail := NAME_W - left_margin - NAME_RIGHT_PAD
	var fs := NAME_FS_MAX
	while fs > NAME_FS_MIN:
		if font.get_string_size(NAME_BOUND, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= avail:
			break
		fs -= 1
	return fs


func _make_col(width: float) -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(width, ICON_SIZE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", FIELD_FS)
	return l

func _tint_col(l: Label, tint: Color) -> void:
	var box := StyleBoxFlat.new()
	box.bg_color = tint
	box.content_margin_left = 6
	box.content_margin_right = 6
	l.add_theme_stylebox_override("normal", box)

func _toggle_expand() -> void:
	_expanded = not _expanded
	_expand_section.visible = _expanded

func _on_expand_to_construct() -> void:
	MatchState.show_construct_for_good.emit(good_id)

func _on_move() -> void:
	MatchState.transfer_for_good_requested.emit(good_id)

func _on_purchase() -> void:
	MatchState.purchase_for_good_requested.emit(good_id)

# Off-screen rows don't repaint — once built, every row used to refresh twice
# per turn (costs_updated + turn_processed) whether or not the Market panel was
# even open. Off-screen rows now just mark themselves stale and catch up when
# they actually become visible (panel opened / tab switched).
var _stale := false

func _on_turn_processed(_summary: Dictionary) -> void:
	_queue_row_refresh()

func _on_costs_updated() -> void:
	_queue_row_refresh()

func _queue_row_refresh() -> void:
	if not is_visible_in_tree():
		_stale = true
		return
	_refresh()

func _on_row_visibility_changed() -> void:
	if _stale and is_visible_in_tree():
		_stale = false
		_refresh()

func _refresh() -> void:
	if _price_label == null:
		return
	_price_label.text = "£%.2f" % MarketState.get_price(good_id)
	_est_label.text = "£%.2f" % MarketState.get_estimated_price_in_n_turns(good_id, FORECAST)
	var markup: float = 1.0 + EconomyConfig.MARKET_BUY_MARKUP
	_buy_price_label.text = "£%.2f" % MarketState.get_buy_price(good_id)
	_buy_est_label.text = "£%.2f" % (MarketState.get_estimated_price_in_n_turns(good_id, FORECAST) * markup)

	var summary: Dictionary = Production.last_turn_summary
	var sold_entry: Dictionary = summary.get("sold", {}).get(good_id, {})
	var sold_qty := int(sold_entry.get("qty", 0))
	var sold_rev := float(sold_entry.get("revenue", 0.0))
	var bought_qty := int(summary.get("purchased", {}).get(good_id, 0))
	_sold_label.text = str(sold_qty)
	_bought_label.text = str(bought_qty)

	var uc: float = CostSolver.get_good_unit_cost(good_id)
	var price: float = MarketState.get_price(good_id)
	if uc < 0.0:
		_cost_label.text = "—"
		_cost_label.add_theme_color_override("font_color", COST_GREY)
		_cost_label.tooltip_text = "Not produced yet.\n" + COST_LEGEND
	else:
		var pct: float = (uc / price * 100.0) if price > 0.0 else 0.0
		var color := COST_AMBER
		if pct < 90.0:
			color = COST_GREEN
		elif pct > 110.0:
			color = COST_RED
		_cost_label.text = "£%.2f" % uc
		_cost_label.add_theme_color_override("font_color", color)
		_cost_label.tooltip_text = "Production cost per unit: £%.2f (%.1f%% of market)\n%s" % [uc, pct, COST_LEGEND]

	if sold_qty > 0:
		var sale_price := sold_rev / float(sold_qty)
		var profit := sale_price - (uc if uc >= 0.0 else 0.0)
		_profit_label.text = "£%.2f" % profit
		_profit_label.add_theme_color_override("font_color", COST_GREEN if profit > 0.0 else COST_RED)
		_profit_label.tooltip_text = "Profit per unit = avg sale £%.2f − cost £%.2f" % [sale_price, maxf(0.0, uc)]
	else:
		_profit_label.text = "No sales"
		_profit_label.add_theme_color_override("font_color", COST_GREY)
		_profit_label.tooltip_text = "No units sold to market last turn."
