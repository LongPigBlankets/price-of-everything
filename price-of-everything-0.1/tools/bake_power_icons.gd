extends SceneTree

# Bake the green/grey power bolt icons. The art is three lightning bolts on a BLUE
# screen; the grey + green centre bolts sit close to that blue, so the usual
# corner flood-fill eats them. Instead strip by blue-chroma (background is
# B-dominant; grey/green/amber fills and the navy outline are not), then segment
# the three bolts as connected components and recolour the rightmost bolt to the
# leftmost bolt's amber (so each icon = two amber bolts flanking a green/grey core).
# Preview run writes to /tmp.
#   Godot --headless --path . --script res://tools/bake_power_icons.gd

const BN := preload("res://tools/bake_new_icons.gd")
const MEDIUM_DIR := "res://assets/icons/goods/medium"
const SMALL_DIR := "res://assets/icons/goods/small"
const MEDIUM_MAX := 2048
const SMALL_MAX := 256
const TRIM_PAD_FRAC := 0.04
const BLUE_T := 34          # B - R and B - G both above this => blue screen
const FRINGE_T := 18        # weaker blue at the subject edge
const FILL_LUM := 0.42      # above = coloured fill (recolour); below = navy outline (keep)

# [absolute source path, "g_XXX_internal_name"]
const JOBS := [
	["/Users/crisu/Downloads/Gemini_Generated_Image_pyvgf3pyvgf3pyvg.png", "g_077_green_power"],
	["/Users/crisu/Downloads/Gemini_Generated_Image_5k56ti5k56ti5k56 (1).png", "g_078_grey_power"],
]


func _initialize() -> void:
	for job in JOBS:
		var img := Image.load_from_file(job[0])
		if img == null:
			print("FAIL load ", job[0])
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		var data := img.get_data()
		_strip_blue(data, w, h)
		BN._drop_small_components(data, w, h)  # remove the corner sparkle watermark
		_recolour_right_bolt(data, w, h)

		var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		var used := out.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var pad := int(round(maxi(used.size.x, used.size.y) * TRIM_PAD_FRAC))
			used = used.grow(pad).intersection(Rect2i(0, 0, w, h))
			out = out.get_region(used)
		out.fix_alpha_edges()
		_emit(out, "%s/%s.png" % [MEDIUM_DIR, job[1]], MEDIUM_MAX)
		_emit(out, "%s/%s.png" % [SMALL_DIR, job[1]], SMALL_MAX)
		print("OK ", job[1], " -> ", out.get_width(), "x", out.get_height())
	quit()


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


func _strip_blue(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	for idx in n:
		var o := idx * 4
		var r := int(data[o])
		var g := int(data[o + 1])
		var b := int(data[o + 2])
		if b - r > BLUE_T and b - g > BLUE_T:
			data[o + 3] = 0
	# Erode the weaker-blue anti-aliased halo left at the outline edge.
	for _pass in 2:
		var clear := PackedInt32Array()
		for idx in n:
			var o := idx * 4
			if data[o + 3] == 0:
				continue
			var b := int(data[o + 2])
			if b - int(data[o]) <= FRINGE_T or b - int(data[o + 1]) <= FRINGE_T:
				continue
			var x := idx % w
			var y := idx / w
			var edge := (x > 0 and data[(idx - 1) * 4 + 3] == 0) \
					or (x < w - 1 and data[(idx + 1) * 4 + 3] == 0) \
					or (y > 0 and data[(idx - w) * 4 + 3] == 0) \
					or (y < h - 1 and data[(idx + w) * 4 + 3] == 0)
			if edge:
				clear.push_back(idx)
		if clear.is_empty():
			break
		for idx in clear:
			data[idx * 4 + 3] = 0


# Recolour the rightmost bolt (a connected component) to the leftmost bolt's amber,
# preserving per-pixel brightness and leaving the dark navy outline alone.
func _recolour_right_bolt(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var sizes := PackedInt32Array()
	var sumx := PackedFloat32Array()
	var cur := 0
	for start in n:
		if data[start * 4 + 3] < 32 or labels[start] != -1:
			continue
		var size := 0
		var sx := 0.0
		var stack := PackedInt32Array()
		stack.push_back(start)
		labels[start] = cur
		while stack.size() > 0:
			var idx := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			var x := idx % w
			var y := idx / w
			sx += x
			for dy in range(-1, 2):
				var ny := y + dy
				if ny < 0 or ny >= h:
					continue
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					if nx < 0 or nx >= w:
						continue
					var nidx := ny * w + nx
					if data[nidx * 4 + 3] >= 32 and labels[nidx] == -1:
						labels[nidx] = cur
						stack.push_back(nidx)
		sizes.push_back(size)
		sumx.push_back(sx)
		cur += 1
	if cur == 0:
		return
	var biggest := 0
	for i in cur:
		biggest = maxi(biggest, sizes[i])
	# The bolts are the components above 15% of the largest; flag if not exactly 3.
	var bolts := []
	for i in cur:
		if sizes[i] > int(biggest * 0.15):
			bolts.append(i)
	if bolts.size() < 3:
		print("  WARN found ", bolts.size(), " bolt components (expected 3) - left as-is")
		return
	bolts.sort_custom(func(a, b): return (sumx[a] / sizes[a]) < (sumx[b] / sizes[b]))
	var left_label: int = bolts[0]
	var right_label: int = bolts[bolts.size() - 1]

	var ar := 0.0
	var ag := 0.0
	var ab := 0.0
	var an := 0
	for idx in n:
		if labels[idx] != left_label:
			continue
		var o := idx * 4
		var lum := (0.299 * data[o] + 0.587 * data[o + 1] + 0.114 * data[o + 2]) / 255.0
		if lum > 0.45:
			ar += data[o]
			ag += data[o + 1]
			ab += data[o + 2]
			an += 1
	if an == 0:
		return
	ar /= an
	ag /= an
	ab /= an
	var amber_lum := maxf((0.299 * ar + 0.587 * ag + 0.114 * ab) / 255.0, 0.01)

	for idx in n:
		if labels[idx] != right_label:
			continue
		var o := idx * 4
		var lum := (0.299 * data[o] + 0.587 * data[o + 1] + 0.114 * data[o + 2]) / 255.0
		if lum <= FILL_LUM:
			continue  # keep the dark navy outline
		var scale := lum / amber_lum
		data[o] = clampi(int(ar * scale), 0, 255)
		data[o + 1] = clampi(int(ag * scale), 0, 255)
		data[o + 2] = clampi(int(ab * scale), 0, 255)
