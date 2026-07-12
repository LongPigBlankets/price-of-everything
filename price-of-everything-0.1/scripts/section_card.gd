# Reusable section card: header row (icon + title) + content slot.
# Children added via `content.add_child(...)` or `add_content(...)` go into the
# content area beneath the title.
#
# Usage from code:
#   var card := preload("res://scenes/section_card.tscn").instantiate()
#   card.title = "Buildings"
#   card.icon = preload("res://assets/icons/ui_icons/alt/building_ledger.png")
#   card.content.add_child(some_label)
#
# Usage in .tscn: instance section_card.tscn, set `title` / `icon` exports.

@tool
class_name SectionCard
extends PanelContainer

@export var title: String = "SECTION":
	set(value):
		title = value
		_refresh_title()
@export var icon: Texture2D:
	set(value):
		icon = value
		_refresh_icon()

@onready var title_label: Label = %Title
@onready var icon_rect: TextureRect = %Icon
@onready var content: VBoxContainer = %Content

func _ready() -> void:
	_refresh_title()
	_refresh_icon()

func _refresh_title() -> void:
	if is_inside_tree() and title_label:
		title_label.text = title.to_upper()

func _refresh_icon() -> void:
	if is_inside_tree() and icon_rect:
		icon_rect.texture = icon
		icon_rect.visible = icon != null

# Convenience for chaining
func add_content(node: Node) -> SectionCard:
	content.add_child(node)
	return self
