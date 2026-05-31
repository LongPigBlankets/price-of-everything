extends PanelContainer

const LegendEntryScene: PackedScene = preload("res://scenes/legend_entry.tscn")

# Power state legend rows. Fixed colours + labels for power balance mode.
const POWER_LEGEND_ROWS: Array = [
	{"color": Color(0.2, 0.8, 0.2), "text": "+N  Surplus (exporting)"},
	{"color": Color(0.8, 0.2, 0.2), "text": "-N  Deficit (importing)"},
	{"color": Color(0.05, 0.05, 0.05), "text": "(-N)  Cables required"},
	{"color": Color(0.5, 0.5, 0.5), "text": "Cables unused"},
]

@onready var entries_vbox: VBoxContainer = $MarginContainer/VBoxContainer/EntriesVBox
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel

func _ready() -> void:
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	call_deferred("hide")

func _on_selections_changed(mode: int, selections: Array) -> void:
	title_label.text = "Legend - " + _get_mode_name(mode)
	if mode == MapMode.Mode.POWER_BALANCE:
		_rebuild_power()
	elif mode == MapMode.Mode.LOGISTICS:
		_rebuild_logistics()
	else:
		_rebuild_resource(selections)
	show()

func _on_mode_cleared() -> void:
	_clear_entries()
	hide()

func _clear_entries() -> void:
	for child in entries_vbox.get_children():
		child.queue_free()

# --- Resource mode (existing) ---

func _rebuild_resource(selections: Array) -> void:
	_clear_entries()
	for s in selections:
		var entry := LegendEntryScene.instantiate()
		entries_vbox.add_child(entry)
		var swatch: ColorRect = entry.get_node("ColourSwatch")
		var label: Label = entry.get_node("NameLabel")
		swatch.color = s.color
		label.text = _display_name_for(s.good_id)

# --- Power mode (new) ---

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

# --- Helpers ---

func _display_name_for(good_id: String) -> String:
	return Catalog.get_display_name(good_id)

func _get_mode_name(mode: int) -> String:
	match mode:
		MapMode.Mode.POTENTIALS:
			return "Potentials"
		MapMode.Mode.TILES_PRODUCING:
			return "Producing"
		MapMode.Mode.TILES_CONSUMING:
			return "Consuming"
		MapMode.Mode.POWER_BALANCE:
			return "Power"
		MapMode.Mode.LOGISTICS:
			return "Logistics"
		_:
			return "Overlay"
