extends PanelContainer

const LegendEntryScene: PackedScene = preload("res://scenes/legend_entry.tscn")

# Power state legend rows. Fixed colours + labels for power balance mode.
const POWER_LEGEND_ROWS: Array = [
	{"color": Color(0.2, 0.8, 0.2), "text": "+N  Surplus (exporting)"},
	{"color": Color(0.8, 0.2, 0.2), "text": "-N  Deficit (importing)"},
	{"color": Color(0.05, 0.05, 0.05), "text": "(-N)  Cables required"},
	{"color": Color(0.5, 0.5, 0.5), "text": "Cables unused"},
]

# Deposits mode has no per-good selection — explain the hover pill instead.
const DEPOSITS_LEGEND_ROWS: Array = [
	"Hover a tile for its deposit size",
	"500 / 1000  surveyed amount",
	"∞  permanent deposit",
	"???  survey the tile to reveal",
]

# Water mode highlights tiles by colour (no per-good selection).
const WATER_RIVER_COLOR := Color(0.45, 0.95, 0.5, 0.95)
const WATER_DESAL_COLOR := Color(0.90, 0.72, 0.36, 0.95)
const WATER_LEGEND_ROWS: Array = [
	{"color": WATER_RIVER_COLOR, "text": "Rivers"},
	{"color": WATER_DESAL_COLOR, "text": "Coastal — desalination sites"},
]

@onready var entries_vbox: VBoxContainer = $MarginContainer/VBoxContainer/EntriesVBox
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel

func _ready() -> void:
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	call_deferred("hide")

func _on_selections_changed(mode: int, _selections: Array) -> void:
	# Producing / Consuming have no legend here — their goods live in the tick-list
	# panel and the instruction has its own bottom-centre panel (GoodSelectPanel).
	if mode == MapMode.Mode.TILES_PRODUCING or mode == MapMode.Mode.TILES_CONSUMING:
		_clear_entries()
		hide()
		return
	title_label.text = "Legend - " + _get_mode_name(mode)
	if mode == MapMode.Mode.POWER_BALANCE:
		_rebuild_power()
	elif mode == MapMode.Mode.LOGISTICS:
		_rebuild_logistics()
	elif mode == MapMode.Mode.SURVEYING:
		_rebuild_survey()
	elif mode == MapMode.Mode.DEPOSITS:
		_rebuild_deposits()
	elif mode == MapMode.Mode.WATER:
		_rebuild_water()
	show()

func _on_mode_cleared() -> void:
	_clear_entries()
	hide()

func _clear_entries() -> void:
	for child in entries_vbox.get_children():
		child.queue_free()

# --- Power mode ---

func _rebuild_power() -> void:
	_clear_entries()
	for row in POWER_LEGEND_ROWS:
		var entry := LegendEntryScene.instantiate()
		entries_vbox.add_child(entry)
		var swatch: ColorRect = entry.get_node("ColourSwatch")
		var label: Label = entry.get_node("NameLabel")
		swatch.color = row.color
		label.text = row.text

# --- Logistics mode ---

func _rebuild_logistics() -> void:
	_clear_entries()
	var overlay := get_tree().get_first_node_in_group("logistics_overlay")
	if overlay == null or not overlay.has_method("get_routes"):
		return
	for r in overlay.get_routes():
		var entry := LegendEntryScene.instantiate()
		entries_vbox.add_child(entry)
		var swatch: ColorRect = entry.get_node("ColourSwatch")
		var label: Label = entry.get_node("NameLabel")
		swatch.color = r.color
		label.text = Catalog.tile_label(str(r.source))

# --- Surveying mode ---

func _rebuild_survey() -> void:
	_clear_entries()
	var entry := LegendEntryScene.instantiate()
	entries_vbox.add_child(entry)
	var swatch: ColorRect = entry.get_node("ColourSwatch")
	var label: Label = entry.get_node("NameLabel")
	swatch.color = Color(0.45, 0.04, 0.12)  # burgundy
	label.text = "Maximum limit of surveys"

# --- Deposits mode ---

func _rebuild_deposits() -> void:
	_clear_entries()
	for text in DEPOSITS_LEGEND_ROWS:
		var entry := LegendEntryScene.instantiate()
		entries_vbox.add_child(entry)
		var swatch: ColorRect = entry.get_node("ColourSwatch")
		var label: Label = entry.get_node("NameLabel")
		swatch.visible = false
		label.text = text

# --- Water mode ---

func _rebuild_water() -> void:
	_clear_entries()
	for row in WATER_LEGEND_ROWS:
		var entry := LegendEntryScene.instantiate()
		entries_vbox.add_child(entry)
		var swatch: ColorRect = entry.get_node("ColourSwatch")
		var label: Label = entry.get_node("NameLabel")
		swatch.color = row.color
		label.text = row.text

# --- Helpers ---

func _get_mode_name(mode: int) -> String:
	match mode:
		MapMode.Mode.TILES_PRODUCING:
			return "Producing"
		MapMode.Mode.TILES_CONSUMING:
			return "Consuming"
		MapMode.Mode.DEPOSITS:
			return "Deposits"
		MapMode.Mode.WATER:
			return "Water"
		MapMode.Mode.POWER_BALANCE:
			return "Power"
		MapMode.Mode.LOGISTICS:
			return "Logistics"
		MapMode.Mode.SURVEYING:
			return "Surveying"
		_:
			return "Overlay"
