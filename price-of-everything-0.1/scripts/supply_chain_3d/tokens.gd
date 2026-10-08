extends RefCounted
var _cache: Dictionary = {}
func texture_for(icon: Texture2D) -> Texture2D:
	if icon == null: return null
	var key := icon.get_instance_id()
	if _cache.has(key): return _cache[key]
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var source := icon.get_image()
	if source.is_compressed(): source.decompress()
	source.convert(Image.FORMAT_RGBA8)
	source.resize(88, 88, Image.INTERPOLATE_LANCZOS)
	for y in 128:
		for x in 128:
			var d := Vector2(x + 0.5 - 64, y + 0.5 - 64).length()
			var color := Color(0.015, 0.058, 0.105)
			color = color.lerp(Color(0.995, 0.931, 0.763), 1.0 - smoothstep(57.0, 58.0, d))
			color.a = 1.0 - smoothstep(62.0, 63.0, d)
			image.set_pixel(x, y, color)
	image.blend_rect(source, Rect2i(0, 0, 88, 88), Vector2i(20, 20))
	image.generate_mipmaps()
	_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]
