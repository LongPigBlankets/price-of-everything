extends RefCounted
## The tile view's building-card glyph: the building art with its plate keyed out to
## transparency and the raised-emboss lighting baked in.
##
## Extracted from tile_info_panel_v2.gd (owner 2026-08-24: "when using building icons,
## make the background transparent and use the metallic offwhite version that the tile
## view panel's building cards use") so the end screen shows the same object, not a
## second one that looks nearly like it.
##
## The plate is keyed by distance from the corner pixel, not by an exact match, so the
## art's own anti-aliased edge fades out instead of leaving a halo. The lighting is baked
## INTO the texture rather than layered at draw time: layered rects plus an additive
## material tripped a GL-compat blend quirk that rendered the keyed alpha as opaque navy.

const _KEY_MAX := 200               # downsample before keying — cards render <= 90px
static var _cache: Dictionary = {}  # building_id -> ImageTexture (null = no art)


## The raw art for a building, by the catalog's own naming fallbacks.
static func raw_texture(bd: Dictionary) -> Texture2D:
	var building_id := str(bd.get("id", ""))
	var internal := str(bd.get("internal_name", ""))
	var paths: Array[String] = []
	if building_id != "" and internal != "":
		paths.append("res://assets/icons/buildings/%s_%s.png" % [building_id, internal])
	if building_id != "":
		paths.append("res://assets/icons/buildings/%s.png" % building_id)
	if internal != "":
		paths.append("res://assets/icons/buildings/%s.png" % internal)
	for p in paths:
		if ResourceLoader.exists(p):
			return load(p) as Texture2D
	return null


static func keyed(bd: Dictionary) -> Texture2D:
	var building_id := str(bd.get("id", ""))
	if _cache.has(building_id):
		return _cache[building_id]
	var tex := raw_texture(bd)
	if tex == null:
		_cache[building_id] = null
		return null
	var img: Image = tex.get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() > _KEY_MAX:
		img.resize(_KEY_MAX,
			int(round(img.get_height() * float(_KEY_MAX) / float(img.get_width()))),
			Image.INTERPOLATE_LANCZOS)
	var bg := img.get_pixel(2, 2)
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			var d := absf(c.r - bg.r) + absf(c.g - bg.g) + absf(c.b - bg.b)
			var a := clampf((d - 0.28) / 0.45, 0.0, 1.0) * c.a
			if a < c.a:
				img.set_pixel(x, y, Color(c.r, c.g, c.b, a))
	# Raised emboss, baked in: shadow silhouette to the bottom-right, off-white light
	# catch to the top-left, the glyph on top. Light from the top-left, as everywhere.
	var w := img.get_width()
	var h := img.get_height()
	var pad := 8
	var shadow := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var catch := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var a := img.get_pixel(x, y).a
			if a > 0.01:
				shadow.set_pixel(x, y, Color(0.0, 0.0, 0.0, a * 0.5))
				catch.set_pixel(x, y, Color(0.88, 0.93, 1.0, a * 0.85))
	var canvas := Image.create(w + pad * 2, h + pad * 2, false, Image.FORMAT_RGBA8)
	var full := Rect2i(0, 0, w, h)
	canvas.blend_rect(shadow, full, Vector2i(pad + 4, pad + 5))
	canvas.blend_rect(catch, full, Vector2i(pad - 2, pad - 2))
	canvas.blend_rect(img, full, Vector2i(pad, pad))
	var out := ImageTexture.create_from_image(canvas)
	_cache[building_id] = out
	return out
