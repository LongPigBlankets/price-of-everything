extends RefCounted
## Offline terrain encoding. Geometry, UV extent and the seam gutter stay intact.
const VERSION := 1
const SIMPLE_TYPES := ["rural", "hill", "mountain"]
const MAX_RMSE := 1.5 # RGB levels out of 255, measured at original resolution
const MAX_PATCH_RMSE := 4.0 # Prevent small detailed areas hiding in a large plain tile.
const PATCH_SIZE := 128

static func package_eligibility(tile_ids: Array) -> Dictionary:
	# Include neighbours outside a regional preview so its urban buffer is intact.
	var tiles := {}
	for tid in tile_ids:
		tiles[tid]={"type":Catalog.tile_type(tid)}
		for neighbour in Catalog.tile_neighbours(tid): tiles[neighbour]={"type":Catalog.tile_type(neighbour)}
	return eligible_tiles(tiles)

static func eligible_tiles(tiles: Dictionary) -> Dictionary:
	var protected := {}
	for tid in tiles:
		if str(tiles[tid].type) != "urban": continue
		protected[tid] = true
		for neighbour in Catalog.tile_neighbours(tid): protected[neighbour] = true
	var result := {}
	for tid in tiles:
		result[tid] = str(tiles[tid].type) in SIMPLE_TYPES and not protected.has(tid)
	return result

static func quality(reference: Image, candidate: Image) -> Dictionary:
	var decoded := candidate.duplicate() as Image
	if decoded.is_compressed(): assert(decoded.decompress() == OK)
	decoded.clear_mipmaps()
	decoded.convert(Image.FORMAT_RGB8)
	if decoded.get_size() != reference.get_size():
		decoded.resize(reference.get_width(), reference.get_height(), Image.INTERPOLATE_BILINEAR)
	var metrics := reference.compute_image_metrics(decoded, false)
	var worst := 0.0
	for y in range(0, reference.get_height(), PATCH_SIZE):
		for x in range(0, reference.get_width(), PATCH_SIZE):
			var rect := Rect2i(x, y, mini(PATCH_SIZE, reference.get_width()-x), mini(PATCH_SIZE, reference.get_height()-y))
			worst = maxf(worst, reference.get_region(rect).compute_image_metrics(decoded.get_region(rect), false).root_mean_squared)
	return {"rmse":metrics.root_mean_squared, "worst_patch_rmse":worst, "max_error":metrics.max}

static func acceptable(metrics: Dictionary) -> bool:
	return float(metrics.rmse) <= MAX_RMSE and float(metrics.worst_patch_rmse) <= MAX_PATCH_RMSE

static func target_size(source: Vector2i, scale: float) -> Vector2i:
	return Vector2i(ceili(source.x*scale/4.0)*4,ceili(source.y*scale/4.0)*4)

static func _compress(reference: Image, scale: float) -> Image:
	var image := reference.duplicate() as Image
	var size := target_size(image.get_size(),scale)
	# Godot otherwise pads unaligned dimensions during compression. Resample the
	# complete extent first, so normalized UVs still address the same geography.
	if image.get_size()!=size: image.resize(size.x,size.y,Image.INTERPOLATE_LANCZOS)
	image.generate_mipmaps()
	assert(image.compress(Image.COMPRESS_BPTC) == OK)
	assert(image.get_format() == Image.FORMAT_BPTC_RGBA)
	return image

static func encode(source: Texture2D, allow_reduction: bool) -> Dictionary:
	var result := encode_image(source.get_image(),allow_reduction)
	result.texture=ImageTexture.create_from_image(result.image)
	result.erase("image")
	return result

static func encode_image(reference: Image, allow_reduction: bool) -> Dictionary:
	# CPU-only images can be encoded independently by the offline worker pool.
	# Do not repeatedly re-encode a lossy bake. Migrations start from original art.
	assert(reference != null and not reference.is_compressed())
	var original_bytes := reference.get_data_size()
	var original_size := reference.get_size()
	reference.clear_mipmaps()
	reference.convert(Image.FORMAT_RGB8)
	var scale := 1.0
	var trials := {}
	var measured := {}
	var image: Image
	if allow_reduction:
		for candidate in [0.5, 0.75]:
			image = _compress(reference, candidate)
			measured = quality(reference, image)
			trials[str(candidate)] = measured
			if acceptable(measured):
				scale = candidate
				break
	if scale == 1.0:
		image = _compress(reference, 1.0)
		measured = quality(reference, image)
	return {"image":image, "terrain_texture":{
		"version":VERSION, "format":Image.FORMAT_BPTC_RGBA, "bytes":image.get_data_size(),
		"source_bytes":original_bytes, "source_size":original_size, "size":image.get_size(),
		"eligible":allow_reduction, "reduced":scale<1.0, "scale":scale, "quality":measured, "trials":trials}}
