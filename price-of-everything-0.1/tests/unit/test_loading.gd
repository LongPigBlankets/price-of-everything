extends "res://tests/test_base.gd"

const FEATURE := "loading"
const Screen := preload("res://scripts/loading_screen.gd")
const Carousel := preload("res://scripts/loading_carousel.gd")

class BuildFixture extends Node:
	var build_complete := false


func _test_loading_readiness_does_not_wait_for_carousel() -> void:
	var previous_scene := get_tree().current_scene
	var previous_pending := SaveLoad._pending_snapshot.duplicate(true)
	SaveLoad._pending_snapshot = {}
	var fixture := BuildFixture.new()
	get_tree().root.add_child(fixture)
	get_tree().current_scene = fixture
	var screen := Screen.new()
	screen.set_process(false)
	add_child(screen)
	screen._carousel.set_process(false)
	_check(not screen._ready_to_begin(), "loading: a scene change alone does not expose an unfinished world")
	_check(not screen._ready_to_begin(), "loading: Begin waits for build_complete")
	fixture.build_complete = true
	SaveLoad._pending_snapshot = {"fixture": true}
	_check(not screen._ready_to_begin(), "loading: Begin waits for a pending snapshot to apply")
	SaveLoad._pending_snapshot = {}
	screen._process(0.1)
	_check(screen._morphed and screen._begin.visible,
		"loading: a ready world exposes Begin during the first tile, without a cinematic minimum")
	_check(screen._carousel.current_index == 0, "loading: readiness does not advance the artwork")
	get_tree().current_scene = previous_scene
	SaveLoad._pending_snapshot = previous_pending
	screen.queue_free()
	fixture.queue_free()
	await get_tree().process_frame


func _test_loading_carousel_wrap_and_release() -> void:
	var carousel := Carousel.new()
	carousel.set_process(false)
	add_child(carousel)
	carousel.seek(29.8)
	_check(carousel.current_index == 5 and carousel._next.visible,
		"loading: the last sea hex slides toward the first building")
	carousel.seek(30.2)
	_check(carousel.current_index == 0 and not carousel._next.visible,
		"loading: the thirty-second cycle resumes at the first building's daylight")
	_check(carousel.get_child_count() == 2,
		"loading: a full cycle retains two tile surfaces rather than all six pairs")
	var old_day: Texture2D = carousel._current.texture
	var old_night: Texture2D = carousel._current.material.get_shader_parameter("night_texture")
	var day_ref: WeakRef = weakref(old_day)
	var night_ref: WeakRef = weakref(old_night)
	old_day = null
	old_night = null
	carousel.seek(15.2)
	_check(day_ref.get_ref() == null and night_ref.get_ref() == null,
		"loading: leaving a building releases both of its textures")
	carousel.queue_free()
	await get_tree().process_frame
