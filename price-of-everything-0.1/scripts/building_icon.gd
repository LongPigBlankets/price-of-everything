extends RefCounted
## Runtime cleaner for the building-type icons (assets/icons/buildings/*). Mirrors the goods
## icon bake's colour-keying (tools/bake_good_icons.gd): keys the dark navy background out to
## transparent, trims to the off-white artwork, and centres it in a square so every building
## icon is uniformly square-bounded by its content. Results are cached per building_id.
##
## Done at runtime (not a baked asset) so it stays scoped to the ledger and leaves the source
## PNGs — shared with the infrastructure mapmode — untouched. Consumers preload this as
## `const BuildingIcon := preload("res://scripts/building_icon.gd")`.

const InfraIcons := preload("res://scripts/infra_icons.gd")

# A pixel whose brightest channel is below this is treated as navy background (the icons are
# off-white line art on a ~#001739 navy; off-white sits ~230+, the navy ~60, so this cleanly
# separates them and clears the dark half of the anti-aliased fringe).
const _DARK_MAX := 110

static var _cache: Dictionary = {}

static func clean_texture(building_id: String, internal_name: String) -> Texture2D:
	if _cache.has(building_id):
		return _cache[building_id]
	var tex := _bake(building_id, internal_name)
	_cache[building_id] = tex
	return tex

static func _bake(building_id: String, internal_name: String) -> Texture2D:
	var src := InfraIcons.texture_for(building_id, internal_name)
	if src == null:
		return null
	var img := src.get_image()
	if img == null:
		return src
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	img.clear_mipmaps()  # else get_data() returns base + mipmap levels and the size won't match
	var w := img.get_width()
	var h := img.get_height()

	# Chroma-key the navy background → transparent (byte-array pass, like the goods bake).
	var data := img.get_data()
	var n := w * h
	for idx in n:
		var o := idx * 4
		if data[o + 3] == 0:
			continue
		var maxc := maxi(maxi(int(data[o]), int(data[o + 1])), int(data[o + 2]))
		if maxc < _DARK_MAX:
			data[o + 3] = 0
	var keyed := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)

	# Trim to the artwork's bounding box, then centre it in a square sized by its longest side.
	var used := keyed.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		return src
	var sub := keyed.get_region(used)
	var side := maxi(sub.get_width(), sub.get_height())
	var out := Image.create(side, side, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 0))
	var ox := int(floor(float(side - sub.get_width()) / 2.0))
	var oy := int(floor(float(side - sub.get_height()) / 2.0))
	out.blit_rect(sub, Rect2i(0, 0, sub.get_width(), sub.get_height()), Vector2i(ox, oy))
	out.fix_alpha_edges()
	out.generate_mipmaps()  # crisp when the ~300px art is shown at the row's icon size
	return ImageTexture.create_from_image(out)
