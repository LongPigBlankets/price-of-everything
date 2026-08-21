extends Node
## Sampling half of tools/loading_film_check.gd. Parented to the tree ROOT so it outlives the
## scene change and can watch the whole load.
##
## It samples the one number that matters: how far the film's own playback clock has advanced
## against wall clock. A film that stutters loses stream time it never gets back, so `drift`
## — wall elapsed minus stream position — is the whole story:
##
##   drift flat near 0    the film is playing at speed; the load is not in its way
##   drift steps up       the main thread was busy for that long and the film froze
##   drift climbing       decode cannot keep up at all (wrong resolution for the box)

const SAMPLE_MS := 250
const SHOT_AT_MS := 4000

var screen: Node = null

var _film: VideoStreamPlayer = null
var _t0 := 0
var _play_t0 := -1
var _last_sample := 0
var _last_frame := 0
var _worst_gap := 0
var _worst_gap_at := 0
var _shot_taken := false
var _done := false
var _last_drift := -1.0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	_last_sample = _t0
	_last_frame = _t0


func _process(_delta: float) -> void:
	if _done:
		return
	var now := Time.get_ticks_msec()
	var gap := now - _last_frame
	_last_frame = now
	if gap > _worst_gap:
		_worst_gap = gap
		_worst_gap_at = now - _t0
	if _film == null and screen != null and is_instance_valid(screen):
		_film = screen.get("_film") as VideoStreamPlayer
	# Latched separately from finding the player: a film can be built and left paused (see
	# LoadingScreen.FILM_START), so "when it started" is not "when we first saw it".
	if _play_t0 < 0 and _film != null and is_instance_valid(_film) and _film.is_playing():
		_play_t0 = now
		print("FILM started at t+%d ms" % (now - _t0))
	if not _shot_taken and now - _t0 >= SHOT_AT_MS and OS.get_environment("FILM_SHOT") != "":
		_shot_taken = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_environment("FILM_SHOT"))
		print("FILM shot at t+%d ms -> %s" % [now - _t0, OS.get_environment("FILM_SHOT")])
	if now - _last_sample >= SAMPLE_MS:
		_last_sample = now
		_sample(now)
	var cur := get_tree().current_scene
	if cur != null and cur.get("build_complete") != null and bool(cur.get("build_complete")):
		_report(now)


func _sample(now: int) -> void:
	if _film == null or not is_instance_valid(_film) or _play_t0 < 0:
		print("FILM t+%5d ms  (no film playing yet)  worst frame gap %d ms" % [now - _t0, _worst_gap])
		return
	var wall := float(now - _play_t0) / 1000.0
	var pos := _film.stream_position
	_last_drift = wall - pos
	print("FILM t+%5d ms  wall %6.2f s  stream %6.2f s  drift %6.2f s  worst gap %4d ms" %
		[now - _t0, wall, pos, _last_drift, _worst_gap])


func _report(now: int) -> void:
	_done = true
	print("FILM ==== build_complete at t+%d ms ====" % (now - _t0))
	print("FILM drift by then: %.2f s (stream time the film lost to a busy main thread)" % _last_drift)
	print("FILM worst single frame gap: %d ms, at t+%d ms" % [_worst_gap, _worst_gap_at])
	get_tree().quit(0)
