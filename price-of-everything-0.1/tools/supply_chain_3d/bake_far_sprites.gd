extends Node
## Deterministic tiny impostors from the game's editable 3D artwork, not new designs.
## AGENT_GODOT_WINDOW=1 godot --path . res://tools/supply_chain_3d/bake_far_sprites.tscn
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Rig := preload("res://scripts/supply_chain_3d/orbit_camera.gd")
const OUT := "res://assets/supply_chain_3d/far_sprites/"
const YAWS := 16
const PITCHES := 5
const DEPTH_CODE := """shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec3 center;
uniform vec3 direction;
uniform float span;
varying vec3 p;
void vertex() { p = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
 float d = clamp(dot(p-center, direction)/span + 0.5, 0.0, 1.0);
 ALBEDO = vec3(d);
}
"""
var output := OUT
var medium := false
var colour_only := false
var selected_keys := PackedStringArray()
var viewport: SubViewport
var camera: Camera3D
var source: MeshInstance3D
var contour: MeshInstance3D

func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Far sprites require a rendered run through AGENT_GODOT_WINDOW=1 godot")
		get_tree().quit(1)
		return
	TelemetryState.enabled = false
	SaveLoad.autosave_enabled = false
	preload("res://tools/shot_harness.gd").arm_watchdog(self, 900.0)
	medium = "--medium" in OS.get_cmdline_user_args()
	colour_only = "--colour-only" in OS.get_cmdline_user_args()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--asset-keys="): selected_keys = arg.trim_prefix("--asset-keys=").split(",")
	if medium: output = "res://assets/supply_chain_3d/medium_sprites/"
	DirAccess.make_dir_recursive_absolute(output)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.near = 0.01
	camera.far = 50.0
	viewport.add_child(camera)
	camera.current = true
	source = MeshInstance3D.new()
	viewport.add_child(source)
	contour = MeshInstance3D.new()
	viewport.add_child(contour)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Assets.DIRECTORY + "manifest.json"))
	var manifest := {"schema": 1, "yaws": YAWS, "pitches": PITCHES, "min_pitch": Rig.MIN_PITCH,
		"max_pitch": Rig.MAX_PITCH, "max_ppu": 1.75 if medium else 0.33, "assets": {}}
	if (colour_only or "--trees-only" in OS.get_cmdline_user_args() or not selected_keys.is_empty()) and FileAccess.file_exists(output + "manifest.json"):
		manifest = JSON.parse_string(FileAccess.get_file_as_string(output + "manifest.json"))
	var depth := ShaderMaterial.new()
	depth.shader = Shader.new()
	depth.shader.code = DEPTH_CODE
	var outline := ShaderMaterial.new()
	outline.shader = Shader.new()
	outline.shader.code = FileAccess.get_file_as_string("res://scripts/supply_chain_3d/contour.gdshader").replace(
		"ink *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);", "")
	if outline.shader.get_shader_uniform_list().is_empty():
		push_error("Outline shader failed to compile; sprite bake aborted")
		get_tree().quit(1)
		return
	contour.material_override = outline
	var keys: Array = catalog.keys()
	keys.sort()
	for key in keys:
		if not selected_keys.is_empty() and key not in selected_keys: continue
		if "--trees-only" in OS.get_cmdline_user_args() and not str(key).begins_with("tree_"): continue
		Assets.key_for(str(key).get_slice("_lvl", 0), 3)
		source.mesh = Assets.mesh_for(key)
		contour.mesh = Assets.contour_for(key)
		var bounds := source.mesh.get_aabb()
		var center := bounds.get_center()
		# The same camera square at every angle: no auto-fit scale pumping on orbit.
		var cell := (64 if medium else 16) if str(key).begins_with("tree_") else (128 if medium else 64)
		# Tall, thin structures need more samples at the close end of medium.
		if medium and key in ["pylon_lvl1", "towers_lvl1", "towers_lvl2"]: cell = 192
		var yaws := 32 if medium and key == "pylon_lvl1" else YAWS
		var span := bounds.size.length() * 1.10
		if colour_only:
			if not manifest.assets.has(key):
				push_error("Colour-only bake needs existing framing: " + str(key))
				get_tree().quit(1)
				return
			var saved: Dictionary = manifest.assets[key]
			cell = int(saved.cell)
			yaws = int(saved.get("yaws", YAWS))
			span = float(saved.span)
			center = Vector3(saved.center[0], saved.center[1], saved.center[2])
		viewport.size = Vector2i.ONE * cell
		camera.size = span
		var paint := ShaderMaterial.new()
		paint.shader = Shader.new()
		paint.shader.code = FileAccess.get_file_as_string("res://scripts/supply_chain_3d/building_print.gdshader").replace(
			"paint *= mix(vec3(0.66, 0.74, 1.0), vec3(1.0, 0.92, 0.72), t);", "")
		paint.set_shader_parameter("stipple_strength", 0.10 if medium else 0.04)
		paint.set_shader_parameter("detail_level", 1 if medium else 0)
		# Small decorative sprites collect too much dark ink after minification.
		# Apply this only to far houses/towers; medium and live meshes keep their art.
		var far_decor := not medium and (str(key).begins_with("house_") or str(key).begins_with("towers_"))
		paint.set_shader_parameter("stroke_width_scale", 0.65 if far_decor else 1.0)
		paint.set_shader_parameter("stroke_opacity", 0.70 if far_decor else 0.88)
		paint.set_shader_parameter("ink", Color("48505a") if far_decor else Color(0.20, 0.25, 0.36, 1.0))
		outline.set_shader_parameter("outline_width_scale", 0.60 if far_decor else 1.0)
		outline.set_shader_parameter("outline_ink", Vector3(64, 72, 82) / 255.0 if far_decor else Vector3(47, 59, 89) / 255.0)
		if str(key).begins_with("tree_"):
			paint.set_shader_parameter("foliage_tint", Vector3(0.81, 0.74, 0.83) if key == "tree_lvl2" else Vector3(0.835, 0.735, 0.865))
		var colour_image := Image.create(cell * yaws, cell * PITCHES, false, Image.FORMAT_RGBA8)
		var depth_image := Image.create(cell * yaws, cell * PITCHES, false, Image.FORMAT_RGBA8)
		var home_size := Vector2i.ZERO
		for pitch_index in PITCHES:
			var pitch := lerpf(Rig.MIN_PITCH, Rig.MAX_PITCH, float(pitch_index) / (PITCHES - 1))
			for yaw_index in yaws:
				var yaw := TAU * yaw_index / yaws
				var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
				camera.position = center + direction * 12.0
				camera.look_at(center)
				camera.force_update_transform()
				source.material_override = paint
				contour.visible = true
				await get_tree().process_frame
				RenderingServer.force_draw(false)
				var frame := viewport.get_texture().get_image()
				# Transparent edge RGB is extruded before filtering. Tiny crowns must not
				# acquire a black fringe when downscaled below one screen pixel.
				_straight_alpha(frame)
				colour_image.blit_rect(frame, Rect2i(0, 0, cell, cell), Vector2i(yaw_index, pitch_index) * cell)
				if pitch_index == 1 and yaw_index == yaws / 8: home_size = frame.get_used_rect().size
				if colour_only: continue
				source.material_override = depth
				depth.set_shader_parameter("center", center)
				depth.set_shader_parameter("direction", direction)
				depth.set_shader_parameter("span", span)
				contour.visible = false
				await get_tree().process_frame
				RenderingServer.force_draw(false)
				frame = viewport.get_texture().get_image()
				_straight_alpha(frame)
				depth_image.blit_rect(frame, Rect2i(0, 0, cell, cell), Vector2i(yaw_index, pitch_index) * cell)
		assert(colour_image.save_png(output + key + ".png") == OK)
		if colour_only:
			# Framing/depth are unchanged. Keep the same manifest (and continent
			# cache key); the existing opaque extent remains a conservative bound.
			print("[SPRITE COLOUR] ", key, " opaque=", home_size)
			continue
		depth_image.convert(Image.FORMAT_L8)
		assert(depth_image.save_png(output + key + "_depth.png") == OK)
		var scale := 72.0
		if str(key).begins_with("tree_"):
			scale = float({"tree_lvl1": 22.0, "tree_lvl2": 32.0, "tree_lvl3": 30.0}[key]) / Assets.projected_height(key)
		elif str(key).begins_with("warehouse_"): scale = 61.2
		elif str(key).begins_with("towers_"): scale = 36.8
		elif str(key).begins_with("pylon_"): scale = 62.0
		manifest.assets[key] = {"cell": cell, "yaws": yaws, "pitches": PITCHES, "span": span, "center": [center.x, center.y, center.z],
			"dimensions": [bounds.size.x, bounds.size.y, bounds.size.z], "home_opaque_pixels": [home_size.x, home_size.y],
			"reference_scale": scale, "source_sha256": FileAccess.get_sha256(Assets.DIRECTORY + key + ".glb")}
		print("[MEDIUM SPRITE] " if medium else "[FAR SPRITE] ", key, " cell=", cell, " opaque=", home_size)
		# Save incremental metadata so an interrupted offline bake remains reviewable.
		FileAccess.open(output + "manifest.json", FileAccess.WRITE).store_string(JSON.stringify(manifest, "\t") + "\n")
	print("[FAR SPRITE] complete ", manifest.assets.size(), " assets x ", YAWS * PITCHES, " views")
	get_tree().quit()

func _straight_alpha(image: Image) -> void:
	# SubViewport readback is premultiplied even though PNG/import sampling is not.
	# Undo it for both paint and depth before filtering, then extend edge colours.
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.0 and c.a < 1.0:
				image.set_pixel(x, y, Color(minf(1.0, c.r / c.a), minf(1.0, c.g / c.a), minf(1.0, c.b / c.a), c.a))
	image.fix_alpha_edges()
