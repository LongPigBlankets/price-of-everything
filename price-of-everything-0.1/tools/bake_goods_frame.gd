extends SceneTree
# One-off: strip the magenta chroma background off the goods-frame plate art and
# write a transparent PNG into the project. Mirrors tools/bake_good_icons.gd's
# chroma handling (flood-fill the background transparent from the corners, clear
# any stray pink pockets, erode the pink fringe), but keeps the whole frame +
# cream centre (no largest-component trim — the frame is one piece).
#
#   <godot> --headless --path . --script res://tools/bake_goods_frame.gd

const SRC := "C:/Users/urigi/Downloads/goods_frame_proto.PNG"
const DST := "C:/Users/urigi/price-of-everything/price-of-everything-0.1/assets/ui/goods_frame_plate.png"
const BG_TOLERANCE := 80
const TARGET_LONGEST := 330   # downscale so 9-slice corners cut thin on a small card

func _initialize() -> void:
	var img := Image.load_from_file(SRC)
	if img == null:
		print("FAIL load ", SRC)
		quit()
		return
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	print("loaded %dx%d" % [w, h])
	var data := img.get_data()
	_flood_fill_background(data, w, h)
	_clear_chroma_pockets(data, w, h)
	_erode_pink_fringe(data, w, h)
	var out := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	out.fix_alpha_edges()
	# Downscale so the ornate corners (bolts) sit only ~25px from the edge in source
	# pixels — then a small 9-slice margin renders a thin frame on a small card.
	var longest := maxi(out.get_width(), out.get_height())
	var s := float(TARGET_LONGEST) / float(longest)
	out.resize(int(round(out.get_width() * s)), int(round(out.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	out.fix_alpha_edges()
	var err := out.save_png(DST)
	print("baked ", DST, " -> %dx%d err=%d" % [out.get_width(), out.get_height(), err])
	quit()


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
	for idx in (w * h):
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		if (data[o] - data[o + 1]) > 50 and (data[o + 2] - data[o + 1]) > 20:
			data[o + 3] = 0


static func _erode_pink_fringe(data: PackedByteArray, w: int, h: int) -> void:
	var n := w * h
	for _pass in 2:
		var to_clear := PackedInt32Array()
		for idx in n:
			var o := idx * 4
			if data[o + 3] == 0:
				continue
			if (data[o] - data[o + 1]) <= 24 or (data[o + 2] - data[o + 1]) <= 10:
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
