extends SceneTree

# Bake a specific batch of source art (in ~/Downloads) into the game's goods-icon
# format: clean the solid chroma-key background (whatever colour it is - this
# batch mixes magenta and green screens), strip the small corner watermark, trim
# to the subject, and emit a medium master (<=2048) plus a small variant (<=256)
# under assets/icons/goods/{medium,small}/g_XXX_<name>.png.
#
# Generalises tools/bake_good_icons.gd (which is magenta-only): the background
# colour is seeded from the top-left corner pixel, so any solid screen works.
# Disconnected components below MIN_COMPONENT_FRAC of the largest are erased,
# which removes the Gemini sparkle watermark while keeping multi-part subjects
# (battery cells, fibreglass rolls).
#
# Run: Godot --headless --path . --script res://tools/bake_new_icons.gd

const FLOOD_TOL := 80      # corner-connected background removal
const POCKET_TOL := 78     # walled-off background pockets (handle holes, etc.)
const FRINGE_TOL := 110    # anti-aliased halo at the subject edge
const MEDIUM_MAX := 2048
const SMALL_MAX := 256
const TRIM_PAD_FRAC := 0.04
const MIN_COMPONENT_FRAC := 0.02

const MEDIUM_DIR := "res://assets/icons/goods/medium"
const SMALL_DIR := "res://assets/icons/goods/small"

# [absolute source path, "g_XXX_internal_name"]
const JOBS := [
	["/Users/crisu/Downloads/Lithium ore.png", "g_050_lithium_ore"],
	["/Users/crisu/Downloads/Lithium Carbonate.png", "g_051_lithium_carbonate"],
	["/Users/crisu/Downloads/large engine.png", "g_052_large_engine"],
	["/Users/crisu/Downloads/Wind Turbine.png", "g_053_wind_turbine"],
	["/Users/crisu/Downloads/Solar Panel.png", "g_054_solar_panel"],
	["/Users/crisu/Downloads/Heavy Vehicle.png", "g_055_heavy_vehicle"],
	["/Users/crisu/Downloads/Diesel ICE Car.png", "g_056_ice_car"],
	["/Users/crisu/Downloads/Electric Car.png", "g_057_ev_car"],
	["/Users/crisu/Downloads/Fibreglass.png", "g_058_fibreglass"],
	["/Users/crisu/Downloads/Lithium Ion batteries.png", "g_059_lithium_battery"],
	["/Users/crisu/Downloads/Sodium Ion Batteries.png", "g_060_sodium_battery"],
	["/Users/crisu/Downloads/Gemini_Generated_Image_dmvta3dmvta3dmvt.png", "g_061_iron_battery"],
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
			_flood_fill_background(data, w, h, sr, sg, sb)
			_clear_bg_pockets(data, w, h, sr, sg, sb)
			_erode_bg_fringe(data, w, h, sr, sg, sb)
		_drop_small_components(data, w, h)

		var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
		var used := out.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var pad := int(round(maxi(used.size.x, used.size.y) * TRIM_PAD_FRAC))
			used = used.grow(pad).intersection(Rect2i(0, 0, w, h))
			out = out.get_region(used)
		out.fix_alpha_edges()

		_emit(out, "%s/%s.png" % [MEDIUM_DIR, stem], MEDIUM_MAX)
		_emit(out, "%s/%s.png" % [SMALL_DIR, stem], SMALL_MAX)
		print("OK ", stem, " bg=", has_bg, " seed=", Vector3i(int(corner.r*255), int(corner.g*255), int(corner.b*255)),
				" src=", w, "x", h, " -> ", out.get_width(), "x", out.get_height())
	quit()


func _emit(img: Image, path: String, cap: int) -> void:
	var copy := img.duplicate() as Image
	var longest := maxi(copy.get_width(), copy.get_height())
	if longest > cap:
		var s := float(cap) / float(longest)
		copy.resize(int(round(copy.get_width() * s)), int(round(copy.get_height() * s)), Image.INTERPOLATE_LANCZOS)
		copy.fix_alpha_edges()
	var err := copy.save_png(path)
	if err != OK:
		print("  save FAIL ", path, " err=", err)


static func _near(data: PackedByteArray, o: int, sr: int, sg: int, sb: int, tol: int) -> bool:
	return absi(data[o] - sr) <= tol and absi(data[o + 1] - sg) <= tol and absi(data[o + 2] - sb) <= tol


static func _flood_fill_background(data: PackedByteArray, w: int, h: int, sr: int, sg: int, sb: int) -> void:
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
		if not _near(data, o, sr, sg, sb, FLOOD_TOL):
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


static func _clear_bg_pockets(data: PackedByteArray, w: int, h: int, sr: int, sg: int, sb: int) -> void:
	var n := w * h
	for idx in n:
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		if _near(data, o, sr, sg, sb, POCKET_TOL):
			data[o + 3] = 0


static func _erode_bg_fringe(data: PackedByteArray, w: int, h: int, sr: int, sg: int, sb: int) -> void:
	var n := w * h
	for _pass in 2:
		var to_clear := PackedInt32Array()
		for idx in n:
			var o := idx * 4
			if data[o + 3] == 0:
				continue
			if not _near(data, o, sr, sg, sb, FRINGE_TOL):
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


# Label connected opaque components, then erase any whose area is below
# MIN_COMPONENT_FRAC of the largest. Removes the corner watermark + stray specks
# while keeping every substantial part of the subject.
static func _drop_small_components(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	var labels := PackedInt32Array()
	labels.resize(n)
	labels.fill(-1)
	var sizes := PackedInt32Array()
	var cur := 0
	var best_size := 0
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
		sizes.push_back(size)
		if size > best_size:
			best_size = size
		cur += 1
	if best_size == 0:
		return
	var threshold := int(float(best_size) * MIN_COMPONENT_FRAC)
	for idx in n:
		var lbl := labels[idx]
		if lbl != -1 and sizes[lbl] < threshold:
			data[idx * 4 + 3] = 0
