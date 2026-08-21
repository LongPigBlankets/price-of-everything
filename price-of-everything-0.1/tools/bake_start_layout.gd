extends Node
## Offline bake of the START LAYOUT — where the ~417 match-start buildings stand, and every
## per-tile working set their placement produced. Run WINDOWED (placement reads NavGrid and
## the authored document, and the subcomponent pass wants a real renderer):
##     <godot> --path . res://tools/bake_start_layout.tscn --quit-after 240000
##
## It runs a REAL new-game build with the bake forced off (NO_LAYOUT_BAKE, set here before
## the map scene loads), waits for build_complete, and writes what the placement passes
## produced to data/start_layout_bake.bin. There is no second implementation of placement to
## drift out of step: the bake is the output of the shipped code path, taken once.
##
## RE-RUN IT after anything that moves where buildings stand — a new authored map document,
## a roads or hills re-bake, an edit to tile_properties.csv, or a change to the placement
## code itself (bump StartLayoutBaked.BAKE_VERSION at the same time). If you forget, the
## content hash refuses the file and the game lays the map out live: slower, never wrong.
##
## Verify a fresh bake by dumping both paths and diffing them — same placements, same
## subcomponents, byte for byte:
##     NO_LAYOUT_BAKE=1 LAYOUT_DUMP=live.json  <godot> --path . res://tools/load_phase_check.tscn
##     LAYOUT_DUMP=baked.json                  <godot> --path . res://tools/load_phase_check.tscn

const LoadingScreenScript := preload("res://scripts/loading_screen.gd")

## Which start the bake is taken from. It only decides WHICH player buildings exist at the end
## of the pass — the NPC ports, ruins and start companies that make up the bulk are the same
## for every start, and a start whose own buildings differ simply places those few live.
const BAKE_START := "res://data/starts/coal_baron.json"


func _ready() -> void:
	get_window().size = Vector2i(1280, 720)
	# Force the live path even if a bake already exists — otherwise the tool would faithfully
	# re-bake whatever it just restored.
	OS.set_environment("NO_LAYOUT_BAKE", "1")
	await get_tree().process_frame
	SaveLoad.prepare_new_game(BAKE_START)
	# The writer is parented to the tree ROOT, not to this scene: begin_load swaps the current
	# scene out and frees everything in it, this node included.
	var writer := Node.new()
	writer.set_script(preload("res://tools/bake_start_layout_writer.gd"))
	get_tree().root.add_child(writer)
	# A loading screen is what puts the build on its paced, frame-yielding path — the same one
	# a player gets. Placement is seeded, so the pacing cannot change the layout, but baking
	# what the shipped path produces beats baking what a special path produces.
	var screen: Node = LoadingScreenScript.show_global(get_tree())
	screen.begin_load(SaveLoad.MAIN_SCENE)
