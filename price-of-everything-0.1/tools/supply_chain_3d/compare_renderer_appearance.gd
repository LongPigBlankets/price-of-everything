extends "res://tools/supply_chain_3d/profile_renderers.gd"
## Matched static-art captures. Transient goods, cars, smoke and water glints are
## hidden only in this disposable run so animation timing cannot mask differences.

func _continent_review(board: Control, home: Dictionary) -> void:
	var view: Control = get_tree().current_scene.find_child("EmpireView", true, false)
	view.hide()
	for i in 3:
		RenderingServer.force_draw(false)
		await get_tree().process_frame
	assert(get_viewport().get_texture().get_image().save_png(output.path_join("regular_map.png")) == OK)
	view.show()
	await super._continent_review(board, home)
	var close := home.duplicate()
	close.span = board.Rig.MIN_SIZE
	await _view(board, close, "closest_buildings")

func _draw_view(board: Control, name: String) -> void:
	for item in board._goods: item.sprite.hide()
	for car in board._effects: car.node.hide()
	for particle in board._world.find_children("*", "CPUParticles3D", true, false):
		particle.hide()
	for mesh in board._world.find_children("*", "MeshInstance3D", true, false):
		var material: Material = mesh.material_override
		if material is ShaderMaterial and material.shader != null and material.shader.resource_path.ends_with("water_glints.gdshader"):
			mesh.hide()
	await super._draw_view(board, name)
