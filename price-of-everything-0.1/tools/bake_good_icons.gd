extends SceneTree

# One-time bake: clean the magenta chroma-key goods icons (flood-fill the
# background transparent from the corners, drop walled-off background pockets,
# erode the pink fringe, strip the watermark by keeping the main subject), fix
# the colour under transparent pixels, downscale, and overwrite the source PNG.
# After this the game just loads ready-made transparent icons - no work at start.
# Idempotent: an already-cleaned (non-magenta) icon is skipped.

const BG_TOLERANCE := 80
# Longest-side cap for the "medium" master. 2048 (the source size) means no
# downscale at all, so the thin navy outlines stay pixel-perfect; mipmaps keep
# it smooth when minified. Used by the encyclopedia detail view.
const MEDIUM_MAX := 2048
# Longest-side cap for the "small" variant served to the recipe / construction
# material requirement diagrams, where 2-6 icons are crammed into ~50px cells
# (largest small-dir use is the 92px flow-single cell). 256 stays crisp there
# at 2x DPI while costing ~0.35MB vs ~22MB for a medium master.
const SMALL_MAX := 256
# Transparent margin left around the trimmed subject, as a fraction of its
# longest side. Trimming the empty background lets the artwork fill the frame
# instead of wasting texels, which sharpens the outlines for free.
const TRIM_PAD_FRAC := 0.04

const MEDIUM_DIR := "res://assets/icons/goods/medium"

func _initialize() -> void:
	# Scan the medium folder and process any icon still on a magenta/pink chroma
	# background; already-cleaned (transparent) icons are skipped automatically.
	var dir := DirAccess.open(MEDIUM_DIR)
	if dir == null:
		print("FAIL open ", MEDIUM_DIR)
		quit()
		return
	var files := []
	for fname in dir.get_files():
		if fname.get_extension().to_lower() == "png":
			files.append("%s/%s" % [MEDIUM_DIR, fname])
	files.sort()
	for f in files:
		var img := Image.load_from_file(f)
		if img == null:
			print("FAIL load ", f)
			continue
		img.convert(Image.FORMAT_RGBA8)
		var w := img.get_width()
		var h := img.get_height()
		if not _is_chroma_pink(img.get_pixel(0, 0)):
			print("SKIP (already clean) ", f)
			continue
		var data := img.get_data()
		_flood_fill_background(data, w, h)
		_clear_chroma_pockets(data, w, h)
		_erode_pink_fringe(data, w, h)
		_keep_largest_component(data, w, h)
		var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		# Trim the transparent margin down to the subject (+ a little padding) so
		# the artwork fills the texture instead of wasting resolution on empty
		# space - this is the "zoom in" and it sharpens the outlines.
		var used := out.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var pad := int(round(maxi(used.size.x, used.size.y) * TRIM_PAD_FRAC))
			used = used.grow(pad).intersection(Rect2i(0, 0, w, h))
			out = out.get_region(used)
		out.fix_alpha_edges()
		# Emit the medium master in place, plus a downscaled small variant for the
		# requirement diagrams (same filename, under .../small/).
		_emit(out, f, MEDIUM_MAX)
		_emit(out, String(f).replace("/medium/", "/small/"), SMALL_MAX)
	quit()


# Save a copy of `img` capped to `cap` on its longest side, with the colour under
# transparent pixels re-fixed after any resize so mipmaps never bleed a fringe.
func _emit(img: Image, path: String, cap: int) -> void:
	var copy := img.duplicate() as Image
	var longest := maxi(copy.get_width(), copy.get_height())
	if longest > cap:
		var s := float(cap) / float(longest)
		copy.resize(int(round(copy.get_width() * s)), int(round(copy.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		copy.fix_alpha_edges()
	var err := copy.save_png(path)
	print("baked ", path, " -> ", copy.get_width(), "x", copy.get_height(), " err=", err)


static func _is_chroma_pink(c: Color) -> bool:
	var r := int(c.r * 255.0)
	var g := int(c.g * 255.0)
	var b := int(c.b * 255.0)
	return c.a > 0.5 and (r - g) > 50 and (b - g) > 20


static func _flood_fill_background(data: PackedByteArray, w: int, h: int) -> void:
	var sr := data[0]
	var sg := data[1]
	var sb := data[2]
	var stack := PackedInt32Array()
	stack.push_back(0)
	stack.push_back(w - 1)
	stack.push_back((h - 1) * w)
	stack.push_back((h - 1) * w + (w - 1))
	while stack.size() > 0:
		var idx := stack[stack.size() - 1]
		stack.remove_at(stack.size() - 1)
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		if absi(data[o] - sr) > BG_TOLERANCE \
				or absi(data[o + 1] - sg) > BG_TOLERANCE \
				or absi(data[o + 2] - sb) > BG_TOLERANCE:
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


static func _clear_chroma_pockets(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	for idx in n:
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		var r := data[o]
		var g := data[o + 1]
		var b := data[o + 2]
		if (r - g) > 50 and (b - g) > 20:
			data[o + 3] = 0


static func _erode_pink_fringe(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	for _pass in 2:
		var to_clear := PackedInt32Array()
		for idx in n:
			var o := idx * 4
			if data[o + 3] == 0:
				continue
			var r := data[o]
			var g := data[o + 1]
			var b := data[o + 2]
			if (r - g) <= 24 or (b - g) <= 10:
				continue
			var x := idx % w
			var y := idx / w
			var border := (x > 0 and data[(idx - 1) * 4 + 3] == 0) \
					or (x < w - 1 and data[(idx + 1) * 4 + 3] == 0) \
					or (y > 0 and data[(idx - w) * 4 + 3] == 0) \
					or (y < h - 1 and data[(idx + w) * 4 + 3] == 0)
			if border:
				to_clear.push_back(idx)
		if to_clear.size() == 0:
			break
		for idx in to_clear:
			data[idx * 4 + 3] = 0


static func _keep_largest_component(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var best_label := -1
	var best_size := 0
	var cur := 0
	for start in n:
		if data[start * 4 + 3] == 0 or labels[start] != -1:
			continue
		var size := 0
		var stack := PackedInt32Array()
		stack.push_back(start)
		labels[start] = cur
		while stack.size() > 0:
			var idx := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			size += 1
			var x := idx % w
			var y := idx / w
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
					if data[nidx * 4 + 3] != 0 and labels[nidx] == -1:
						labels[nidx] = cur
						stack.push_back(nidx)
		if size > best_size:
			best_size = size
			best_label = cur
		cur += 1
	if best_label == -1:
		return
	for idx in n:
		if data[idx * 4 + 3] != 0 and labels[idx] != best_label:
			data[idx * 4 + 3] = 0
