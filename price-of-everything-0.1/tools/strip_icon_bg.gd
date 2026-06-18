extends SceneTree
# One-off: strip the (cyan/blue) solid background from the biomass + fertiliser good icons and make it
# transparent. Reuses bake_good_icons' corner flood-fill (seeds from the corner colour, works for any
# background) + keep-largest-component (drops trapped bg islands + the watermark sparkle).
# IMPORTANT: save to the ABSOLUTE path (globalize_path) — save_png("res://...") did NOT persist to the
# real source file in a `-s` run. Run:
#   Godot --headless --path . -s tools/strip_icon_bg.gd   then  Godot --headless --path . --import

const Bake = preload("res://tools/bake_good_icons.gd")
const FILES := [
	"res://assets/icons/goods/medium/g_062_biomass.png",
	"res://assets/icons/goods/medium/g_064_fertilisers.png",
]
const TOL := 96   # corner-colour tolerance per channel (0-255)

func _initialize() -> void:
	for res_path in FILES:
		var abs_path := ProjectSettings.globalize_path(res_path)
		var img := Image.load_from_file(abs_path)
		if img == null:
			print("FAIL load ", abs_path)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var data := img.get_data()
		_flood_bg(data, w, h, TOL)        # corner-seeded flood (all 4 corners)
		Bake._keep_largest_component(data, w, h)
		var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		var err := out.save_png(abs_path)
		# report remaining opaque coverage so a failed strip is obvious
		var opaque := 0
		for i in range(0, w * h, 64):
			if data[i * 4 + 3] != 0:
				opaque += 1
		print("stripped ", abs_path.get_file(), " save_err=", err, " opaque~", opaque, "/", (w * h) / 64)
	quit()

# Flood transparent from all four corners, removing pixels within `tol` per-channel of the seed colour.
func _flood_bg(data: PackedByteArray, w: int, h: int, tol: int) -> void:
	var sr := data[0]
	var sg := data[1]
	var sb := data[2]
	var stack := PackedInt32Array([0, w - 1, (h - 1) * w, (h - 1) * w + (w - 1)])
	while stack.size() > 0:
		var idx := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		if absi(data[o] - sr) > tol or absi(data[o + 1] - sg) > tol or absi(data[o + 2] - sb) > tol:
			continue
		data[o + 3] = 0
		var x := idx % w
		var y := idx / w
		if x > 0:
			stack.push_back(idx - 1)
		if x < w - 1:
			stack.push_back(idx + 1)
		if y > 0:
			stack.push_back(idx - w)
		if y < h - 1:
			stack.push_back(idx + w)
