extends SceneTree
# Copy under res://tools/ (artifacts/ is .gdignored) and run:
#   godot --headless --path . --script res://tools/<copy>.gd
# Loads each installed tier and checks its size and mipmaps. GoodIcons searches every alternate tier before the main
# art, so the alternate file existing at the expected name is what makes it the icon in game.
func _init() -> void:
	var want := {"very_small": 256, "small": 450, "medium": 800}
	var bad := 0
	for tier in want:
		var p := "res://assets/icons/goods/alternate_icons/%s/g_045_car_body.png" % tier
		var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
		var ok: bool = t != null and t.get_width() == want[tier] and t.get_height() == want[tier]
		var mips: bool = ok and t.get_image().has_mipmaps()
		print(tier, " ", t.get_width() if t else -1, " mipmaps=", mips)
		if not (ok and mips):
			bad += 1
	print("RESULT ", "PASS" if bad == 0 else "FAIL")
	quit(1 if bad else 0)
