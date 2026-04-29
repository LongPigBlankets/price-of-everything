extends PanelContainer

const LegendEntryScene: PackedScene = preload("res://scenes/legend_entry.tscn")

@onready var entries_vbox: VBoxContainer = $MarginContainer/VBoxContainer/EntriesVBox
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel

func _ready() -> void:
	MapMode.selections_changed.connect(_on_selections_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	# Defer hide so layout resolves first
	call_deferred("hide")

func _on_selections_changed(mode: int, selections: Array) -> void:
	_rebuild(selections)
	
	# Update the title dynamically based on the current mode
	title_label.text = "Legend - " + _get_mode_name(mode)
	
	show()

func _on_mode_cleared() -> void:
	_clear_entries()
	hide()

func _clear_entries() -> void:
	for child in entries_vbox.get_children():
		child.queue_free()

func _rebuild(selections: Array) -> void:
	_clear_entries()
	for s in selections:
		var entry := LegendEntryScene.instantiate()
		entries_vbox.add_child(entry)
		var swatch: ColorRect = entry.get_node("ColourSwatch")
		var label: Label = entry.get_node("NameLabel")
		swatch.color = s.color
		label.text = _display_name_for(s.good_id)

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
		_:
			return "Overlay"
