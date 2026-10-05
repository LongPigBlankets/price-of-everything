extends "res://tests/test_base.gd"
const FEATURE := "resources"
const Figures := preload("res://scripts/goods_figures.gd")
const View := preload("res://scripts/resources_ds2/resources_ds2.gd")

var backup: Dictionary

func setup() -> void:
	backup = SaveLoad.export_snapshot().duplicate(true)
	MatchState.reset()
	Stockpile.clear_all()
	TransportState.pending_transport_shipments.clear()
	Production.last_turn_summary = {}
	TurnManager.current_turn = 1

func cleanup() -> void:
	SaveLoad.import_snapshot(backup)

func _row(rows: Array, gid: String) -> Dictionary:
	for r: Dictionary in rows:
		if str(r.good_id) == gid: return r
	return {}

## The counts the table shows come from the turn's summary, the stockpiles and the shipments on the road.
func _test_figures_read_the_engine() -> void:
	setup()
	Stockpile.add("tile_5_4", "g_006", 40)
	Production.last_turn_summary = {"produced": {"g_006": 12}, "consumed": {"g_006": 7}, "sold": {"g_006": {"qty": 5, "revenue": 50.0}},
		"good_costs": {"g_006": {"transport": 6.0, "transport_units": 12, "intermediary": 3.0, "intermediary_units": 5}}}
	TransportState.queue_transport_shipment({"source_tile": "tile_5_4", "destination_tile": "tile_5_5", "good_id": "g_006", "qty": 9, "turns_remaining": 2})
	TransportState.queue_transport_shipment({"is_sale": true, "source_tile": "tile_5_4", "destination_tile": "tile_5_5", "turns_remaining": 1,
		"sale_record": {"tile_id": "tile_5_4", "items": [{"good_id": "g_006", "qty": 4, "revenue": 40.0}], "total_qty": 4, "total_revenue": 40.0}})
	var r := _row(Figures.rows(), "g_006")
	_check(int(r.produced) == 12 and int(r.used) == 7 and int(r.sold) == 5, "produced, used and sold are last turn's")
	_check(int(r.stored) == 40, "stored is what the stockpiles hold")
	_check(int(r.transit) == 13, "in transit counts moves between tiles and sales on the way to a port (%d)" % int(r.transit))
	_check(not Figures.goods().any(func(g: Dictionary) -> bool: return str(g.get("internal_name", "")) == "power"), "power has no row")
	var c: Dictionary = Figures.costs("g_006")
	_check(is_equal_approx(float(c.transport.total), 6.0) and is_equal_approx(float(c.transport.per_unit), 0.5), "transport is a total and a unit")
	_check(is_equal_approx(float(c.intermediary.per_unit), 0.6) and int(c.storage.units) == 0
		and is_equal_approx(float(c.storage.per_unit), EconomyConfig.warehousing_cost_per_unit("g_006")), "the storage unit figure is the fee a stored unit pays")
	cleanup()

## The turn books what it charged on each good, without changing what it charged.
func _test_note_good_cost_splits_by_units() -> void:
	setup()
	var s := {"good_costs": {}}
	Production.note_goods_cost(s, {"g_006": 30, "g_007": 10}, "transport", 8.0)
	Production.note_good_cost(s, "g_006", "storage", 1.5, 30)
	_check(is_equal_approx(float(s.good_costs.g_006.transport), 6.0) and is_equal_approx(float(s.good_costs.g_007.transport), 2.0),
		"a shared charge is split by units")
	_check(int(s.good_costs.g_006.transport_units) == 30 and is_equal_approx(float(s.good_costs.g_006.storage), 1.5), "each kind keeps its own total and units")
	cleanup()

## The view: every good by default, the filters narrow, a heading sorts, a row opens its costs, and the Carbon
## tax column is there only while the levy is in force.
func _test_view_filters_sorts_and_opens() -> void:
	setup()
	Stockpile.add("tile_5_4", "g_006", 40)
	Production.last_turn_summary = {"produced": {"g_007": 3}, "consumed": {}, "sold": {}}
	var view: Control = View.new()
	get_tree().root.add_child(view)
	var all: int = Figures.goods().size()
	_check((view.call("shown_rows") as Array).size() == all and all > 1, "every good shows by default (%d)" % all)
	view.call("set_filter", "stored", true)
	var stocked: Array = view.call("shown_rows")
	_check(stocked.size() == 1 and str(stocked[0].good_id) == "g_006", "In stock leaves the goods you hold")
	view.call("set_filter", "stored", false)
	view.call("sort_by", "produced")
	_check(str((view.call("shown_rows") as Array)[0].good_id) == "g_007", "a count column sorts largest first")
	var cols: Array = (view.call("columns") as Array).map(func(c: Dictionary) -> String: return str(c.key))
	_check(not cols.has("carbon") == not Figures.carbon_in_force(), "the Carbon tax column follows the levy")
	_check(not cols.has("power") and cols.has("transit") and cols.has("stored"), "the columns are the owner's counts")
	view.call("toggle_good", "g_006")
	var detail := view.find_child("ResourceDetail_g_006", true, false)
	_check(detail != null and detail.find_child("Total_transport", true, false) != null and detail.find_child("Unit_storage", true, false) != null
		and detail.find_child("Freight", true, false) != null, "an opened good shows its costs as totals and units, and its freight")
	_check(View.count_text(3, 40) == "3/40 SHOWN" and View.thousands(12345) == "12,345", "the count and figures read as printed")
	view.free()
	cleanup()

## The panel keeps its v2 table with the switch off, and builds the DS2 view with it on.
func _test_panel_switches_look() -> void:
	var was := UiPrefs.use_resources_ds2
	UiPrefs.set_use_resources_ds2(false)
	var panel: Control = load("res://scenes/resource_panel.tscn").instantiate()
	get_tree().root.add_child(panel)
	_check(panel.find_child("ResourcesDs2", true, false) == null and (panel.get_node("MarginContainer") as Control).visible, "off: the v2 table")
	UiPrefs.set_use_resources_ds2(true)
	_check(panel.find_child("ResourcesDs2", true, false) != null and not (panel.get_node("MarginContainer") as Control).visible
		and is_equal_approx(panel.custom_minimum_size.x, View.WIDTH), "on: the DS2 view, 1080 wide")
	UiPrefs.set_use_resources_ds2(false)
	_check(panel.find_child("ResourcesDs2", true, false) == null and (panel.get_node("MarginContainer") as Control).visible, "off again: the v2 table is back")
	panel.free()
	UiPrefs.set_use_resources_ds2(was)
