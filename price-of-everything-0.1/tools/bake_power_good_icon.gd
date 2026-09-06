extends SceneTree

# Re-bake the POWER good's icon (g_010_power) from new master art.
#
# Same pipeline as tools/bake_new_icons.gd — whose helpers this reuses rather than copying —
# but for a single good, and it writes ALL THREE tiers. bake_new_icons emits medium + small
# only, which is right for a NEW good: nothing stale exists below them, and good_icons.gd's
# _TIER_ORDER falls back to small when very_small is missing. Power is not new. It already has
# a very_small on disk, and a thumbnail left behind would keep serving the OLD bolt in
# every list row and chip while the larger tiers showed the new one.
#
#   <godot> --headless --path . --script res://tools/bake_power_good_icon.gd -- <source.png>
#
# The source is the raw pop-art master on its magenta chroma screen; the background is seeded
# from the corner pixel, so it needs no preparation beyond being a format Godot can load
# (convert .jfif to .png first).

const BN := preload("res://tools/bake_new_icons.gd")

const STEM := "g_010_power"
const TRIM_PAD_FRAC := 0.04
## Tier caps, longest edge. A 256px thumbnail avoids upscaling at the 128px display limit. Matched to
## good_icons.gd's TIER_MAX_DISPLAY: very_small serves thumbnails, small is the working tier and
## is capped at 450 -- good_icons.gd names that as the largest size any good icon is drawn at,
## and 70 of the 74 icons already in that folder are built to it. bake_new_icons.gd uses 256,
## which is right for the recipe-diagram goods it was written for but would leave power softer
## than its neighbours. medium is master art.
const TIERS := {
	"res://assets/icons/goods/medium": 2048,
	"res://assets/icons/goods/small": 450,
	"res://assets/icons/goods/very_small": 256,
}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		print("usage: --script res://tools/bake_power_good_icon.gd -- <source.png>")
		quit(1)
		return
	var src := String(args[0])
	var img := Image.load_from_file(src)
	if img == null:
		print("FAIL load ", src)
		quit(1)
		return
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
	BN._drop_small_components(data, w, h)   # also takes the corner sparkle watermark

	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	var used := out.get_used_rect()
	if used.size.x > 0 and used.size.y > 0:
		var pad := int(round(maxi(used.size.x, used.size.y) * TRIM_PAD_FRAC))
		used = used.grow(pad).intersection(Rect2i(0, 0, w, h))
		out = out.get_region(used)
	out.fix_alpha_edges()

	for dir in TIERS:
		var copy := out.duplicate() as Image
		var cap: int = TIERS[dir]
		var longest := maxi(copy.get_width(), copy.get_height())
		if longest > cap:
			var s := float(cap) / float(longest)
			copy.resize(int(round(copy.get_width() * s)), int(round(copy.get_height() * s)),
				Image.INTERPOLATE_LANCZOS)
			copy.fix_alpha_edges()
		var path := "%s/%s.png" % [dir, STEM]
		var err := copy.save_png(path)
		print("%s %s  %dx%d" % ["OK  " if err == OK else "FAIL", path,
			copy.get_width(), copy.get_height()])
	print("source ", w, "x", h, " bg=", has_bg, " trimmed -> ", out.get_width(), "x", out.get_height())
	quit()
