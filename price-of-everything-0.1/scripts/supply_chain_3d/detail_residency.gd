extends RefCounted
## A small exact hex occupancy map shared by the joined continent materials.
var anchor := Vector2.ZERO
var low := Vector2i.ZERO
var cells: Dictionary = {}
var image: Image
var texture: ImageTexture
var _resident: Dictionary = {}

func configure(tiles: Dictionary, origin: Vector2) -> void:
	if tiles.is_empty(): return
	cells.clear()
	_resident.clear()
	low = Vector2i.ZERO
	anchor = tiles.values()[0].center - origin
	var high := Vector2i.ZERO
	for tid in tiles:
		var p: Vector2 = tiles[tid].center - origin - anchor
		var q := roundi(p.x / 405.0)
		var r := roundi(p.y / 480.0 - posmod(q, 2) * 0.5)
		var cell := Vector2i(q, r)
		cells[tid] = cell
		low = low.min(cell)
		high = high.max(cell)
	var dimensions := high - low + Vector2i.ONE
	image = Image.create(dimensions.x, dimensions.y, false, Image.FORMAT_L8)
	texture = ImageTexture.create_from_image(image)

func bind(material: ShaderMaterial) -> void:
	material.set_shader_parameter("resident_tiles", texture)
	material.set_shader_parameter("residency_origin", anchor)
	material.set_shader_parameter("residency_grid", Vector4(low.x, low.y, image.get_width(), image.get_height()))

func update(resident: Dictionary) -> bool:
	# A blend-only change must not re-upload a texture still in use by the GPU.
	# Store IDs only, never the tile records and their large resource references.
	var changed := resident.size() != _resident.size()
	if not changed:
		for tid in resident:
			if not _resident.has(tid): changed = true; break
	if not changed: return false
	_resident.clear()
	image.fill(Color.BLACK)
	for tid in resident:
		_resident[tid] = true
		var p: Vector2i = cells[tid] - low
		image.set_pixel(p.x, p.y, Color.WHITE)
	texture.update(image)
	return true
