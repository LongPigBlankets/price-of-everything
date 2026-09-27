extends Control
## The People panel's advisors tab in DS2 (docs/people-ds2-plan.md). Until its body is built, today's tab.

func _ready() -> void:
	var old: Control = load("res://scripts/advisor_council_tab.gd").new()
	old.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(old)
