extends Node
## Close inspection of the shipped sprite beside its rotatable mesh.
const Assets := preload("res://scripts/supply_chain_3d/assets.gd")
const Harness := preload("res://tools/shot_harness.gd")
func _ready() -> void:
	Harness.prepare_window(get_window(), Vector2i(1600, 900))
	Harness.arm_watchdog(self, 90)
	TelemetryState.enabled = false
	AudioServer.set_bus_mute(0, true)
	var root := Control.new()
	add_child(root)
	var bg := ColorRect.new()
	bg.color = Color("2b3757")
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	for text_position in [["Approved sprite", Vector2(260, 45)], ["3D with printed shading", Vector2(1110, 45)]]:
		var label := Label.new()
		label.text = text_position[0]
		label.position = text_position[1]
		label.add_theme_font_size_override("font_size", 28)
		root.add_child(label)
	var reference := TextureRect.new()
	reference.position = Vector2(70, 140)
	reference.size = Vector2(780, 780)
	reference.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	reference.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	reference.texture = load("res://assets/icons/buildings/sprites/industrial_factory_lvl3.png")
	root.add_child(reference)
	var container := SubViewportContainer.new()
	container.position = Vector2(910, 140)
	container.size = Vector2(780, 780)
	container.stretch = true
	root.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	container.add_child(viewport)
	var mesh := MeshInstance3D.new()
	mesh.mesh = Assets.mesh_for("industrial_factory_lvl3")
	viewport.add_child(mesh)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 1.28
	viewport.add_child(camera)
	camera.position = Vector3(3, 3.35, 3)
	camera.look_at(Vector3(0, 0.35, 0))
	for i in 12: await get_tree().process_frame
	Harness.prepare_window(get_window(), Vector2i(1600, 900))
	for i in 5: await get_tree().process_frame
	Harness.capture(self, "/private/tmp/supply3d_material_comparison.png", get_window().size)
	get_tree().quit()
