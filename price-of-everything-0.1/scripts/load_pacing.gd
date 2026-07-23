extends Node
## Load-pacing gate (autoload "LoadPacing"). Heavy node _ready code — e.g. HillVisuals' contour
## triangulation and its texture bake — calls bg_yield() / checks is_background_build() against
## this so that WHILE A LOADING SCREEN IS UP (the new-game and load-game paths) it spreads its work
## across frames instead of freezing the loading animation. With no loading screen up (unit tests,
## the e2e harness) it stays fully synchronous, so those paths are unchanged.


# Cheat `swap loading_screen` (debug terminal): when true the new-game build reproduces
# the PRE-optimization procedure — start buildings placed one per frame (each redrawing
# the whole layer), start forests re-emitted one per frame, and the match-start toasts
# left visible — so the slow old load can be recorded side-by-side with the fast one.
# Default false (the shipped fast path). Lives here because the toggle is set in one
# match's terminal but read by world_map on the NEXT new game (this autoload survives
# the scene change; the terminal does not).
var legacy_load := false

func toggle_legacy_load() -> bool:
	legacy_load = not legacy_load
	return legacy_load


func is_background_build() -> bool:
	return _loading_up()


func _loading_up() -> bool:
	for c in get_tree().root.get_children():
		if c is LoadingScreen:
			return true
	return false


## Hand a frame back mid-build, but only while a loading screen is up.
func bg_yield() -> void:
	if is_background_build():
		await get_tree().process_frame
