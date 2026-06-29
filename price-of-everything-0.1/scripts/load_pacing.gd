extends Node
## Load-pacing gate (autoload "LoadPacing"). Heavy node _ready code — e.g. HillVisuals' contour
## triangulation and its texture bake — calls bg_yield() / checks is_background_build() against
## this so that WHILE A LOADING SCREEN IS UP (the new-game and load-game paths) it spreads its work
## across frames instead of freezing the loading animation. With no loading screen up (unit tests,
## the e2e harness) it stays fully synchronous, so those paths are unchanged.


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
