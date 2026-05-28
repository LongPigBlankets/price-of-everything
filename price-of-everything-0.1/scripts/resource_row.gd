extends HBoxContainer

signal potentials_pressed(good_id: String)
signal producing_pressed(good_id: String)
signal consuming_pressed(good_id: String)

@onready var name_label: Label = $NameLabel
@onready var potentials_button: Button = $PotentialsButton
@onready var producing_button: Button = $ProducingButton
@onready var consuming_button: Button = $ConsumingButton
@onready var produced_label: Label = $ProducedLabel
@onready var consumed_label: Label = $ConsumedLabel
@onready var surplus_label: Label = $SurplusLabel
@onready var stockpile_label: Label = $StockpileLabel

var good_id: String = ""
var good_type: String = ""
var _cost_label: Label = null

func _ready() -> void:
	Stockpile.stockpile_changed.connect(_refresh_stockpile)
	_refresh_stockpile()
	_cost_label = Label.new()
	_cost_label.text = "--"
	_cost_label.custom_minimum_size = Vector2(48, 0)
	_cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cost_label.tooltip_text = "Production cost per unit"
	_cost_label.visible = false
	add_child(_cost_label)
	CostSolver.costs_updated.connect(_refresh_cost)

func setup(good_data: Dictionary) -> void:
	good_id = good_data.id
	good_type = good_data.good_type
	name_label.text = good_data.display_name
	
	potentials_button.text = "Potentials"
	producing_button.text = "Producing"
	consuming_button.text = "Consuming"
	
	produced_label.text = "0"
	consumed_label.text = "0"
	surplus_label.text = "0"
	
	if not potentials_button.pressed.is_connected(_on_potentials_pressed):
		potentials_button.pressed.connect(_on_potentials_pressed)
		producing_button.pressed.connect(_on_producing_pressed)
		consuming_button.pressed.connect(_on_consuming_pressed)
	
	update_button_states()
	_refresh_stockpile()
	_refresh_cost()

func _refresh_stockpile() -> void:
	if good_id == "":
		return
	stockpile_label.text = str(Stockpile.get_total(good_id))

func _refresh_cost() -> void:
	if _cost_label == null or good_id == "":
		return
	var uc: float = CostSolver.get_good_unit_cost(good_id)
	_cost_label.text = "--" if uc < 0.0 else "£%.2f" % uc

func update_button_states() -> void:
	var potentials_permanent_disable := good_type != "raw"
	var is_selected := MapMode.is_selected(good_id)
	var can_potentials := MapMode.can_select_in_mode(MapMode.Mode.POTENTIALS)
	var can_producing := MapMode.can_select_in_mode(MapMode.Mode.TILES_PRODUCING)
	var can_consuming := MapMode.can_select_in_mode(MapMode.Mode.TILES_CONSUMING)
	
	potentials_button.disabled = (
		potentials_permanent_disable
		or is_selected
		or not can_potentials
	)
	producing_button.disabled = is_selected or not can_producing
	consuming_button.disabled = is_selected or not can_consuming

func set_mode(is_economy: bool) -> void:
	potentials_button.visible = not is_economy
	producing_button.visible = not is_economy
	consuming_button.visible = not is_economy
	produced_label.visible = is_economy
	consumed_label.visible = is_economy
	surplus_label.visible = is_economy
	stockpile_label.visible = is_economy
	if _cost_label != null:
		_cost_label.visible = is_economy

func _on_potentials_pressed() -> void:
	potentials_pressed.emit(good_id)

func _on_producing_pressed() -> void:
	producing_pressed.emit(good_id)

func _on_consuming_pressed() -> void:
	consuming_pressed.emit(good_id)
