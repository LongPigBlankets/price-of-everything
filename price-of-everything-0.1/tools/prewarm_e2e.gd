extends Node
## End-to-end: stand in for the menu — prewarm the base, raise a real loading screen, then
## reveal+finish coal_baron behind it (this node is freed as the old scene, like the real menu).
## A root-parented watcher does the asserts.  <godot> --path . res://tools/prewarm_e2e.tscn --quit-after 2500
const LoadingScreenScript := preload("res://scripts/loading_screen.gd")
const Watcher := preload("res://tools/prewarm_e2e_watcher.gd")

func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	MapPrewarm.start_prewarm()
	await MapPrewarm.warmed
	print("E2E base warm — revealing behind loading screen")
	var screen: Node = LoadingScreenScript.show_global(get_tree())   # captures THIS node as _from_scene
	var w := Watcher.new()
	w.set("screen", screen)
	get_tree().root.add_child(w)            # survives the reveal
	MapPrewarm.reveal_and_finish("res://data/starts/coal_baron.json", true)
