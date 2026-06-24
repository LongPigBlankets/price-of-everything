extends SceneTree

# Bake a fresh batch of source art (in ~/Downloads) into the game's goods-icon
# format, reusing bake_new_icons.gd's chroma-key strip + watermark removal: clean
# the solid background (seeded from the top-left corner), drop the corner
# watermark + specks, trim to the subject, and emit a medium master (<=2048) plus
# a small variant (<=256) under assets/icons/goods/{medium,small}/g_XXX_<name>.png.
#
# Saves via globalize_path so an overwrite of an already-imported icon persists
# (see the note in tools/strip_icon_bg.gd). Run:
#   Godot --headless --path . --script res://tools/bake_icons_batch.gd
#   Godot --headless --path . --import

const BN := preload("res://tools/bake_new_icons.gd")
const MEDIUM_DIR := "res://assets/icons/goods/medium"
const SMALL_DIR := "res://assets/icons/goods/small"
const MEDIUM_MAX := 2048
const SMALL_MAX := 256
const TRIM_PAD_FRAC := 0.04
# A drop shadow cast onto a magenta screen survives the flood-fill as "darkened
# magenta" (R,B high, G low — too far from the pure-magenta seed to flood). After
# the normal strip, clear any pixel that still reads magenta-hued (R-G and B-G both
# large); the goods themselves are never magenta, so the subject is untouched.
const SHADOW_CHROMA := 45

# [absolute source path, "g_XXX_internal_name"]
const JOBS := [
	["/Users/crisu/Downloads/nitrogen.png", "g_068_nitrogen"],
	["/Users/crisu/Downloads/sodium hydroxide.png", "g_013_sodium_hydroxide"],
]


func _initialize() -> void:
	for job in JOBS:
		var src: String = job[0]
		var stem: String = job[1]
		var img := Image.load_from_file(src)
		if img == null:
			print("FAIL load ", src)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var data := img.get_data()

		var corner := img.get_pixel(0, 0)
		var has_bg := corner.a > 0.5
		if has_bg:
			var sr := int(corner.r * 255.0)
			var sg := int(corner.g * 255.0)
			var sb := int(corner.b * 255.0)
			BN._flood_fill_background(data, w, h, sr, sg, sb)
			BN._clear_bg_pockets(data, w, h, sr, sg, sb)
			BN._erode_bg_fringe(data, w, h, sr, sg, sb)
			if corner.r > 0.6 and corner.b > 0.6 and corner.g < 0.35:  # magenta screen
				_clear_magenta_shadow(data, w, h)
		BN._drop_small_components(data, w, h)

		var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		var used := out.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var pad := int(round(maxi(used.size.x, used.size.y) * TRIM_PAD_FRAC))
			used = used.grow(pad).intersection(Rect2i(0, 0, w, h))
			out = out.get_region(used)
		out.fix_alpha_edges()

		_emit(out, "%s/%s.png" % [MEDIUM_DIR, stem], MEDIUM_MAX)
		_emit(out, "%s/%s.png" % [SMALL_DIR, stem], SMALL_MAX)
		print("OK ", stem, " bg=", has_bg, " seed=", Vector3i(int(corner.r * 255), int(corner.g * 255), int(corner.b * 255)),
				" src=", w, "x", h, " -> ", out.get_width(), "x", out.get_height())
	quit()


static func _clear_magenta_shadow(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	for idx in n:
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		var r := int(data[o])
		var g := int(data[o + 1])
		var b := int(data[o + 2])
		if r - g > SHADOW_CHROMA and b - g > SHADOW_CHROMA:
			data[o + 3] = 0


func _emit(img: Image, path: String, cap: int) -> void:
	var copy := img.duplicate() as Image
	var longest := maxi(copy.get_width(), copy.get_height())
	if longest > cap:
		var s := float(cap) / float(longest)
		copy.resize(int(round(copy.get_width() * s)), int(round(copy.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		copy.fix_alpha_edges()
	var err := copy.save_png(ProjectSettings.globalize_path(path))
	if err != OK:
		print("  save FAIL ", path, " err=", err)
