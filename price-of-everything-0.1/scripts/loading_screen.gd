extends CanvasLayer
class_name LoadingScreen
## Simple black loading screen with an animated "Loading…" label. Parented to the
## tree ROOT (not the current scene) so it survives the change_scene_to_file that
## a load / new game performs, and frees itself once the new map scene is up and
## any pending snapshot has been applied.

const DOT_PERIOD := 0.35      # seconds per dot step
const SAFETY_TIMEOUT := 30.0  # never linger forever if a transition goes sideways

var _label: Label
var _from_scene: Node
var _elapsed := 0.0
var _scene_changed := false


static func show_global(tree: SceneTree) -> LoadingScreen:
	var screen := LoadingScreen.new()
	screen._from_scene = tree.current_scene
	tree.root.add_child(screen)
	return screen


func _ready() -> void:
	layer = 100
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	_label = Label.new()
	_label.text = "Loading"
	_label.theme_type_variation = &"Title"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)


func _process(delta: float) -> void:
	_elapsed += delta
	_label.text = "Loading" + ".".repeat(1 + int(_elapsed / DOT_PERIOD) % 3)
	if _elapsed > SAFETY_TIMEOUT:
		queue_free()
		return
	var current := get_tree().current_scene
	if not _scene_changed:
		if current != null and current != _from_scene:
			_scene_changed = true  # new scene's _ready ran (apply_pending included)
	elif not SaveLoad.has_pending():
		queue_free()
