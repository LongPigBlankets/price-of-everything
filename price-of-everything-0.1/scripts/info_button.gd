extends Button
## A flat "ⓘ" button whose hover tooltip is capped at 150px wide (variable height),
## which the default Godot tooltip can't do. Set `tooltip_text` as usual.

const MAX_TOOLTIP_WIDTH := 150.0

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	if DS != null and DS.theme != null:
		panel.theme = DS.theme
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(margin)
	var label := Label.new()
	label.text = for_text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(MAX_TOOLTIP_WIDTH, 0)
	margin.add_child(label)
	return panel
