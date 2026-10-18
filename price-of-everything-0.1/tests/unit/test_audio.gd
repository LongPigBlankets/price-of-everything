extends "res://tests/test_base.gd"

const FEATURE := "audio"


func _test_headless_audio_does_not_retain_active_playback() -> void:
	var previous_track: int = Audio._track_idx
	Audio.play_music()
	Audio.tile_ambience("urban")
	Audio.hint()
	for _frame: int in 2:
		await get_tree().process_frame
	var idle := true
	var detached := true
	for node: Node in Audio.get_children():
		if node is AudioStreamPlayer:
			idle = idle and not node.playing
			detached = detached and node.stream == null
	_check(idle, "headless audio: music, ambience and effects do not start dummy playback")
	_check(detached, "headless audio: players do not retain active playback streams at shutdown")
	Audio._track_idx = previous_track
