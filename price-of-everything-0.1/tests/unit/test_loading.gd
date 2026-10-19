extends "res://tests/test_base.gd"

const FEATURE := "loading"
const Screen := preload("res://scripts/loading_screen.gd")
const Carousel := preload("res://scripts/loading_carousel.gd")

class BuildFixture extends Node:
	var build_complete := false


func _test_loading_day_to_night_takes_three_seconds() -> void:
	_check(is_zero_approx(Carousel.night_mix_at(0.5)), "loading: daylight holds for half a second")
	_check(is_equal_approx(Carousel.night_mix_at(2.0), 0.5), "loading: dusk is halfway through the three-second fade")
	_check(is_equal_approx(Carousel.night_mix_at(3.5), 1.0), "loading: full night arrives three seconds after the fade starts")
	_check(is_zero_approx(Carousel.slide_at(3.5)), "loading: the completed night look holds before the slide")


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


func _test_loading_smoke_moves_during_the_night_hold() -> void:
	var carousel := Carousel.new()
	carousel.set_process(false)
	add_child(carousel)
	carousel.seek(3.6)
	var position := carousel._current.position
	var frame: float = carousel._current.material.get_shader_parameter("smoke_frame")
	_check(bool(carousel._current.material.get_shader_parameter("smoke_enabled")),
		"loading: the factory has its separate smoke layer")
	carousel.seek(3.9)
	_check(carousel._current.position == position, "loading: the building stays fixed during the night hold")
	_check(not is_equal_approx(frame, carousel._current.material.get_shader_parameter("smoke_frame")),
		"loading: smoke continues rising while the building and night lighting hold")
	carousel.seek(2.1)
	_check(is_equal_approx(frame, carousel._current.material.get_shader_parameter("smoke_frame")),
		"loading: the baked smoke repeats on its one-and-a-half-second boundary")
	carousel.queue_free()
	await get_tree().process_frame


func _test_loading_smoke_layouts_are_in_release_exports() -> void:
	var presets := ConfigFile.new()
	presets.load("res://export_presets.cfg")
	for section in ["preset.0", "preset.1", "preset.2"]:
		_check(str(presets.get_value(section, "include_filter", "")).contains("assets/loading/carousel/smoke-layouts.json"),
			"loading: %s includes the non-resource smoke metadata" % presets.get_value(section, "name", section))


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
	var smoke_day: Texture2D = carousel._current.material.get_shader_parameter("smoke_day_atlas")
	var smoke_night: Texture2D = carousel._current.material.get_shader_parameter("smoke_night_atlas")
	var smoke_day_ref: WeakRef = weakref(smoke_day)
	var smoke_night_ref: WeakRef = weakref(smoke_night)
	old_day = null
	old_night = null
	smoke_day = null
	smoke_night = null
	carousel.seek(15.2)
	_check(day_ref.get_ref() == null and night_ref.get_ref() == null,
		"loading: leaving a building releases both of its textures")
	_check(smoke_day_ref.get_ref() == null and smoke_night_ref.get_ref() == null,
		"loading: leaving a smoking building also releases both atlases")
	_check(not bool(carousel._current.material.get_shader_parameter("smoke_enabled")),
		"loading: the farm does not retain a stale smoke layer")
	carousel.queue_free()
	await get_tree().process_frame
