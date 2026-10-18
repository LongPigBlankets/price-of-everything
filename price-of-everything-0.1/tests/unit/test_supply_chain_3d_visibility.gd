extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Visibility := preload("res://scripts/empire_board_visibility.gd")
const Board := preload("res://scripts/supply_chain_3d/board.gd")

## Every tickbox in the supply chain view is either drawn over the scene (applied at once) or
## part of what the scene is built from (fixed while the whole map is shown). A tickbox in
## neither list would rebuild whatever is on screen, the whole map included.
func _test_visibility_switches_are_classified() -> void:
	var rows: Array = Visibility.ROWS.map(func(row: Array) -> String: return str(row[0]))
	var classified: Array = Board.LIVE_SHOW_KEYS + Board.CONTENT_SHOW_KEYS
	rows.sort(); classified.sort()
	_check(rows == classified, "supply chain visibility: every tickbox is a live switch or a content switch %s" % [rows])
	_check(Board.LIVE_SHOW_KEYS.has("names"), "supply chain visibility: tile names are drawn over the scene, never rebuilt")

func _test_visibility_rows_lock_with_a_reason() -> void:
	var menu: Control = Visibility.new()
	add_child(menu)
	menu.setup({"decor": true, "names": true})
	menu.set_locked(["decor"], true, "Fixed while all tiles are shown.")
	var decor: Button = menu.get("_boxes")["decor"]
	var names: Button = menu.get("_boxes")["names"]
	_check(decor.disabled and decor.tooltip_text == "Fixed while all tiles are shown." and not names.disabled,
		"supply chain visibility: a locked row cannot be ticked and says why; other rows stay live")
	menu.set_locked(["decor"], false)
	_check(not decor.disabled and decor.tooltip_text == "", "supply chain visibility: an unlocked row is live again")
	menu.queue_free()
