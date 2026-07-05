extends Control
## Root node for a framed good icon (see UIHelpers.make_framed_good_icon). It
## participates in hover only to supply a tooltip: the good's display name, then
## any tooltip the surrounding row/card would have shown ("Good, then existing
## tooltip text"). MOUSE_FILTER_PASS keeps clicks flowing to clickable parents.

var good_id: String = ""

func _get_tooltip(_at_position: Vector2) -> String:
	var good_name := Catalog.get_display_name(good_id) if good_id != "" else ""
	# Nearest ancestor with a non-empty tooltip = the "existing" tooltip text.
	var parent_tip := ""
	var p := get_parent()
	while p != null:
		if p is Control and (p as Control).tooltip_text != "":
			parent_tip = (p as Control).tooltip_text
			break
		p = p.get_parent()
	if good_name == "":
		return parent_tip
	if parent_tip != "":
		return "%s\n%s" % [good_name, parent_tip]
	return good_name
