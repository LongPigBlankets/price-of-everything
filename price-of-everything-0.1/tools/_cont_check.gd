extends SceneTree
const EGD := preload("res://scripts/end_game_data.gd")
func _init() -> void:
	for r in ["victory", "continuity", "defeat"]:
		print("%-11s title=%-16s epithet=%s" % [r, EGD._title(r, 0, []), EGD._epithet(r, 0, 300)])
	var copy: Array = EGD._copy("continuity", 0, 300, [])
	var t: String = str(copy[0])
	print("continuity copy paragraphs: %d, %d chars" % [copy.size(), t.length()])
	print("  starts: %s" % t.substr(0, 58))
	print("  ends:   %s" % t.substr(t.length() - 44))
	quit(0)
