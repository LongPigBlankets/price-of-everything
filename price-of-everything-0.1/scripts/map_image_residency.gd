extends RefCounted
## The 2D map's large pictures in video memory while a full-screen view covers the map: the
## streamed authored tiles, the in-match repaints and the far-zoom hill picture. Hidden layers
## keep their textures, so a covered map is released explicitly and streams back on return.
## The cached meshes stay: they are small, and slow to triangulate again.
const AuthoredBake := preload("res://scripts/authored_bake.gd")
## How long a covered map stays ready to show again at once, for a quick look at another view.
const WARM_MSEC := 5000
const LAYERS := ["AuthoredFabricVisuals", "AuthoredRoadVisuals", "HillVisuals"]

static func _layers(root: Node) -> Array:
	var found: Array = []
	if root == null:
		return found
	for name in LAYERS:
		var layer := root.get_node_or_null(NodePath(name))
		if layer != null and layer.has_method("release_images"):
			found.append(layer)
	return found


## Returns how many streamed tiles were let go.
static func release(root: Node) -> int:
	for layer in _layers(root):
		layer.call("release_images")
	return AuthoredBake.release()


static func restore(root: Node) -> void:
	for layer in _layers(root):
		layer.call("restore_images")
