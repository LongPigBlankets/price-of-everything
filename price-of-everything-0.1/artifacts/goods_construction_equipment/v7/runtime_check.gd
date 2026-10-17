extends SceneTree
# Copy under res://tools/ (artifacts/ is .gdignored) and run:
#   godot --headless --path . --script res://tools/<copy>.gd
# Loads each installed tier for both construction equipment goods and checks size and mipmaps.
func _init() -> void:
	var want := {"very_small": 256, "small": 450, "medium": 800}
	var bad := 0
	for stem in ["g_071_construction_equipment_ice", "g_072_construction_equipment_ev"]:
		for tier in want:
			var p := "res://assets/icons/goods/alternate_icons/%s/%s.png" % [tier, stem]
			var t: Texture2D = load(p) if ResourceLoader.exists(p) else null
			var ok: bool = t != null and t.get_width() == want[tier] and t.get_height() == want[tier]
			var mips: bool = ok and t.get_image().has_mipmaps()
			print(stem, " ", tier, " ", t.get_width() if t else -1, " mipmaps=", mips)
			if not (ok and mips):
				bad += 1
	print("RESULT ", "PASS" if bad == 0 else "FAIL")
	quit(1 if bad else 0)
