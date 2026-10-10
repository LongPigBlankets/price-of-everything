extends "res://tests/test_base.gd"
const FEATURE := "supply_chain_3d"
const Package := preload("res://tools/supply_chain_3d/bake_package.gd")
const Sprites := preload("res://scripts/supply_chain_3d/far_sprites.gd")
const Geo := preload("res://scripts/supply_chain_3d/geometry.gd")
const Builder := preload("res://scripts/supply_chain_3d/world_builder.gd")

class Slope extends RefCounted:
	func height(p: Vector2) -> float: return 30.0 + p.x * 0.10
	func gradient(_p: Vector2) -> Vector2: return Vector2(0.10, 0)

func _test_targeted_atlases_match_runtime_grid() -> void:
	for key in ["pylon_lvl1", "towers_lvl1", "towers_lvl2"]:
		var data := Sprites.entry(key, 1)
		var mat := Sprites.material_for(key, 1)
		var grid: Vector2 = mat.get_shader_parameter("atlas_grid")
		var colour: Texture2D = mat.get_shader_parameter("artwork")
		var depth: Texture2D = mat.get_shader_parameter("depth_art")
		_check(colour.get_size() == Vector2.ONE * float(data.cell) * grid and depth.get_size() == colour.get_size(),
			"3D medium tall art: %s colour/depth and runtime angle grid agree" % key)
	_check(Sprites.material_for("pylon_lvl1", 1).get_shader_parameter("atlas_grid").x == 32.0
		and Sprites.material_for("pylon_lvl1").get_shader_parameter("atlas_grid").x == 16.0,
		"3D pylon rotation: finer medium angles preserve the independent far atlas")

func _test_foundations_fit_narrow_buildings_and_touch_ground() -> void:
	var builder := Builder.new()
	builder.ground = Slope.new()
	var s := {"side": 80.0, "pos": Vector2.ZERO}
	var frame := {"key": "house_lvl1", "plinth_depth": 10.0, "position": Vector3(0, 40, 0), "dimension": Vector3(80, 40, 30)}
	var batch := Geo.Batch.new()
	builder._append_foundation(batch, s, frame)
	var mesh := batch.mesh()
	_check(mesh.get_aabb().size.z < 33.0 and mesh.get_aabb().size.x <= 82.0,
		"3D foundations: long narrow terraces do not receive a square platform")
	var grounded := true
	var walls := 0
	for v in batch.vertices:
		if v.y < -0.01:
			walls += 1
			if not is_equal_approx(v.y + 40.0, builder.surface_height(Vector2(v.x, v.z)) - 1.0): grounded = false
	_check(grounded and walls > 0, "3D foundations: segmented wall bottoms meet the hillside with a small buried skirt")

func _test_package_gate_rejects_corruption_and_stale_metadata() -> void:
	var directory := "user://supply_chain_3d_package_test_%d" % Time.get_ticks_usec()
	var cache := Package.Cache.new()
	cache.enabled = true
	cache.directory = directory
	cache.bundled_directory = directory
	cache.defer_trim = true
	var batch := Geo.Batch.new()
	batch.box(Vector3.ZERO, Vector3.ONE * 10.0, Color.WHITE)
	var mesh := batch.mesh()
	var picture := Image.create(1024, 912, false, Image.FORMAT_RGBA8)
	picture.fill(Color.GRAY)
	picture.generate_mipmaps()
	var hull := PackedVector3Array([Vector3.ZERO])
	for x in [-20, 20]:
		for y in [-20, 20]:
			for z in [-20, 20]: hull.append(Vector3(x, y, z))
	cache.write("base", {"mesh": mesh, "rim_mesh": ArrayMesh.new(), "lip_mesh": ArrayMesh.new(), "roads_mesh": ArrayMesh.new(),
		"detail_source": Package.Cache.source_key("detail"), "pick_shape": mesh.create_trimesh_shape(),
		"local_detail": {"clutter_mesh": ArrayMesh.new(), "glint_mesh": ArrayMesh.new(), "tree_cards": {}}})
	cache.write("medium", {"mesh": mesh, "texture": ImageTexture.create_from_image(picture), "pick_shape": mesh.create_trimesh_shape()})
	var near_picture := Image.create(2048, 1824, false, Image.FORMAT_RGBA8)
	near_picture.fill(Color.GRAY)
	near_picture.generate_mipmaps()
	cache.write("near", {"mesh": mesh, "texture": ImageTexture.create_from_image(near_picture), "pick_shape": mesh.create_trimesh_shape()})
	cache.write("root", {"tile_chunks": {"tile": "base"}, "metadata": {"visibility": {"version": Package.VISIBILITY_VERSION, "hulls": {"tile": hull}}}})
	cache.write("scenery", {"trees": {}})
	var manifest := {"schema": Package.MANIFEST_SCHEMA, "complete": true, "storage": "zstd", "tile_count": 1, "continent_key": "root", "scenery_key": "scenery",
		"tiles": {"tile": {"base": "base", "medium": "medium", "near": "near"}}, "resources": {}}
	for key in ["base", "medium", "near", "root", "scenery"]: manifest.resources[key] = Package.file_record(directory, key)
	FileAccess.open(directory.path_join("source_fingerprints.json"), FileAccess.WRITE).store_string(JSON.stringify(Package.Cache.source_fingerprints()))
	FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	var report := await Package.validate(directory, self)
	_check(report.ok and report.tiles == 1 and report.near_decoded_bytes == near_picture.get_data_size(),
		"3D package gate: complete medium/near fixture validates without runtime-cache fallback")
	manifest.storage = "raw"
	FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	report = await Package.validate(directory, self)
	_check(not report.ok and "Wrong resource storage format: near" in report.errors,
		"3D package gate: declared storage must match the resource compression header")
	manifest.storage = "zstd"
	manifest.tiles.tile.erase("near")
	FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	report = await Package.validate(directory, self)
	_check(not report.ok and "Incomplete resource index" in report.errors,
		"3D package gate: a medium-only tile cannot masquerade as a complete closest-LOD package")
	manifest.tiles.tile.near = "medium"
	FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	report = await Package.validate(directory, self)
	_check(not report.ok and "Wrong near resolution/mipmaps: tile" in report.errors,
		"3D package gate: closest terrain must use its own full-resolution bake")
	manifest.tiles.tile.near = "near"
	manifest.resources.medium.sha256 = "corrupt"
	FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	report = await Package.validate(directory, self)
	_check(not report.ok and "Missing or changed resource: medium" in report.errors,
		"3D package gate: a changed/missing file is rejected even when a resource is already in memory")
	manifest.resources.medium = Package.file_record(directory, "medium")
	FileAccess.open(directory.path_join("manifest.json"), FileAccess.WRITE).store_string(JSON.stringify(manifest))
	var stale := Package.Cache.source_fingerprints().duplicate(true)
	stale.layers.terrain = "obsolete"
	FileAccess.open(directory.path_join("source_fingerprints.json"), FileAccess.WRITE).store_string(JSON.stringify(stale))
	report = await Package.validate(directory, self)
	_check(not report.ok and "Missing/stale export source fingerprints" in report.errors,
		"3D package gate: stale compiled-export fingerprints cannot be shipped as a valid package")
	manifest.complete = false
	_check(not Package.validate_header(manifest), "3D package gate: interrupted package is not release-ready")
	for file in DirAccess.get_files_at(directory): DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
