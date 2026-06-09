extends HBoxContainer
# A single good's economy line in the Resources panel: name, stockpile, unit cost.
# Map-overlay selection (producing / consuming / deposits) now lives in the
# Mapmodes panel, so this row is purely informational.

@onready var name_label: Label = $NameLabel
@onready var stockpile_label: Label = $StockpileLabel
@onready var cost_label: Label = $CostLabel

var good_id: String = ""
var good_type: String = ""

func _ready() -> void:
	Stockpile.stockpile_changed.connect(_refresh_stockpile)
	CostSolver.costs_updated.connect(_refresh_cost)
	_refresh_stockpile()
	_refresh_cost()

func setup(good_data: Dictionary) -> void:
	good_id = good_data.id
	good_type = good_data.good_type
	name_label.text = good_data.display_name
	_refresh_stockpile()
	_refresh_cost()

func _refresh_stockpile() -> void:
	if good_id == "":
		return
	stockpile_label.text = str(Stockpile.get_total(good_id))

func _refresh_cost() -> void:
	if good_id == "":
		return
	var uc: float = CostSolver.get_good_unit_cost(good_id)
	cost_label.text = "--" if uc < 0.0 else "£%.2f" % uc
