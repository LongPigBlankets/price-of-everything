extends SceneTree
# One-off: downscale the goods-frame plate to a small version for the market-row
# icon slots, so a thin 9-slice margin renders a slim frame around a ~54px icon.
#
#   <godot> --headless --path . --script res://tools/make_goods_icon_frame.gd

const SRC := "res://assets/ui/goods_frame_plate.png"
const DST := "C:/Users/urigi/price-of-everything/price-of-everything-0.1/assets/ui/goods_frame_plate_sm.png"
const TARGET_LONGEST := 120

func _initialize() -> void:
	var tex := load(SRC) as Texture2D
	if tex == null:
		print("FAIL load ", SRC)
		quit()
		return
	var img := tex.get_image()
	img.convert(Image.FORMAT_RGBA8)
	var longest := maxi(img.get_width(), img.get_height())
	var s := float(TARGET_LONGEST) / float(longest)
	img.resize(int(round(img.get_width() * s)), int(round(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	img.fix_alpha_edges()
	var err := img.save_png(DST)
	print("saved ", DST, " -> %dx%d err=%d" % [img.get_width(), img.get_height(), err])
	quit()
