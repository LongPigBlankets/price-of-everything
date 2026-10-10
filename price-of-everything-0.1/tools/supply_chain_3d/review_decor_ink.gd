extends "res://tools/supply_chain_3d/review_medium_range.gd"
## Optional --before-sprites=/path/to/old-far-atlases enables matched before/after captures.
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
var before_sprites := ""
var original_textures: Dictionary = {}
var before_textures: Dictionary = {}

func _set_previous_ink(previous: bool) -> void:
	for key in Sprites._materials:
		if not str(key).begins_with("house_") and not str(key).begins_with("towers_"): continue
		var material: ShaderMaterial = Sprites._materials[key]
		if not original_textures.has(key): original_textures[key] = material.get_shader_parameter("artwork")
		if not previous:
			material.set_shader_parameter("artwork", original_textures[key])
			continue
		if not before_textures.has(key):
			var path: String = before_sprites.path_join(original_textures[key].resource_path.get_file())
			var image := Image.load_from_file(path)
			assert(image != null, "Missing previous atlas: " + path)
			image.generate_mipmaps()
			before_textures[key] = ImageTexture.create_from_image(image)
		material.set_shader_parameter("artwork", before_textures[key])

func _pair(board: Control, state: Dictionary, name: String) -> void:
	await _view(board, state, name + "_after")
	if before_sprites.is_empty(): return
	_set_previous_ink(true)
	await _draw_view(board, name + "_before")
	_set_previous_ink(false)
	await _draw_view(board, name + "_after")

func _continent_review(board: Control, _home: Dictionary) -> void:
	output = "res://../outputs/supply-chain-3d/far-decor-outline-trim/"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--before-sprites="): before_sprites = arg.trim_prefix("--before-sprites=")
		if arg.begins_with("--range-output="): output = arg.trim_prefix("--range-output=")
	DirAccess.make_dir_recursive_absolute(output)
	await board.set_all_tiles(true, false)
	while not board.detail_ready():
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	board.set_process(false)
	board._labels.hide()
	board.animate_goods = false
	var builder: RefCounted = board._builder
	board.fit_view()
	await _pair(board, board.capture_camera(), "continent_far")
	var state: Dictionary = board.capture_camera()
	for tile in builder.tiles.values():
		if "Stoneshore Coast" in str(tile.label): state.target = builder.point(tile.center); break
	state.span = board.size.y / 0.20
	await _pair(board, state, "far_towns")
	state.span = board.size.y / 0.30
	await _pair(board, state, "far_closest")
	state.yaw += PI * 0.5
	await _pair(board, state, "far_rotated")
	state.yaw = PI / 4.0
	state.span = board.size.y
	await _view(board, state, "medium_restored")
	state.span = board.size.y / 3.2
	await _view(board, state, "near_restored")
