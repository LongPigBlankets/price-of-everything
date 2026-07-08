extends Node
## Root-parented capper for tutorial_shot.gd: survives the scene change to main.tscn,
## waits for the world build + the coach overlay to appear, disables edge-pan (scripted
## windowed runs idle the mouse in the corner), then saves a screenshot and quits.

var _elapsed := 0.0
var _built := false
var _built_time := 0.0
var _shot := false

func _process(delta: float) -> void:
	if _shot:
		return
	_elapsed += delta
	if not _built:
		var scene := get_tree().current_scene
		if scene != null and bool(scene.get("build_complete")):
			_built = true
			_built_time = _elapsed
			var cam := get_tree().get_first_node_in_group("camera")
			if cam != null:
				cam.set("edge_pan_enabled", false)
			# Optional: jump the tutorial to a step index (arg) to shoot a later beat.
			var jump := _arg_index()
			if jump > 0 and Tutorial.active:
				# Simulate the buy so player-owned-building steps can open the BDP.
				for iid in MatchState.buildings:
					var inst: Dictionary = MatchState.buildings[iid]
					if str(inst.get("tile_id", "")) == "tile_5_9" and str(inst.get("building_id", "")) == "b_007":
						inst["owner"] = MatchState.LOCAL_PLAYER
				Tutorial._enter(jump)
	elif _elapsed - _built_time > 1.6:   # let the overlay + panels settle
		_capture()
	if _elapsed > 25.0:                   # hard fallback
		_capture()

func _arg_index() -> int:
	for a in OS.get_cmdline_user_args():
		if a.is_valid_int():
			return a.to_int()
	return 0

func _capture() -> void:
	_shot = true
	var out := ProjectSettings.globalize_path("res://tutorial_shot.png")
	get_viewport().get_texture().get_image().save_png(out)
	var overlay := get_tree().root.find_child("CoachOverlay", true, false)
	print("saved ", out, " | overlay_present=", overlay != null, " | active=", Tutorial.active)
	get_tree().quit(0)
