extends Node
## Bind all texture-based goods, including dynamically built dialogs and recipe rows.
## GoodIcons marks its textures; unrelated textures and tooltips are untouched.
const Hover := preload("res://scripts/good_icon_hover.gd")
func _ready() -> void:
	get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if node is TextureRect or node is Sprite2D:
		_bind.call_deferred(node.get_instance_id())

func _bind(instance_id: int) -> void:
	var node := instance_from_id(instance_id) as Node
	if not is_instance_valid(node) or not node.is_inside_tree(): return
	var texture: Texture2D = node.texture
	if texture == null or not texture.has_meta("encyclopedia_good_id"): return
	# Framed goods already have a complete slot target, including quantity pills.
	var parent := node.get_parent()
	while parent != null:
		if parent.get_script() == Hover: return
		parent = parent.get_parent()
	if node is TextureRect:
		Hover.attach(node)
	else:
		Hover.drawn(node, node.get_rect(), str(texture.get_meta("encyclopedia_good_id")))
