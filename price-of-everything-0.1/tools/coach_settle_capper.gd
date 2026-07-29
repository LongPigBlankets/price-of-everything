extends Node
## Root-parented capper for coach_settle_shot.gd. Waits for the world build, lets the
## opening step settle, then jumps to a spotlight step and samples the coach overlay every
## SAMPLE_DT while it settles — PNG plus the overlay's own reveal/hole state, so the curve
## can be read numerically instead of eyeballed.

const SETTLE_AFTER_BUILD := 1.6   # matches tutorial_shot_capper: overlay + panels settle
const SAMPLE_DT := 0.12
const SAMPLES := 12
const SPOTLIGHT_STEP := 3         # "build_open" — spotlights BLBuildButton on the tile panel

var _elapsed := 0.0
var _built := false
var _built_time := 0.0
var _phase := "opening"           # opening → spotlight → done
var _next_sample := 0.0
var _taken := 0
var _done := false

func _process(delta: float) -> void:
	if _done:
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
			print("[COACH] built · tutorial active=%s · camera ui_focus_duration=%s"
				% [str(Tutorial.active), str(cam.get("ui_focus_duration")) if cam else "n/a"])
		return
	if _elapsed - _built_time < SETTLE_AFTER_BUILD:
		return
	if _elapsed < _next_sample:
		return
	_next_sample = _elapsed + SAMPLE_DT
	_sample()
	if _elapsed > 40.0:
		_finish()


func _sample() -> void:
	var overlay := get_tree().root.find_child("CoachOverlay", true, false)
	if overlay == null:
		print("[COACH] no CoachOverlay in tree — aborting")
		_finish()
		return
	var reveal: float = overlay._reveal
	var eased: float = overlay._reveal_eased()
	var drawn: Rect2 = overlay._drawn_hole(eased)
	var img := get_viewport().get_texture().get_image()
	print("[COACH] %-9s n=%02d reveal=%.2f eased=%.2f dim=%.2f luma=%.1f drawn=(%.0f,%.0f %.0fx%.0f)" % [
		_phase, _taken, reveal, eased, float(overlay._dim_level), _map_luma(img),
		drawn.position.x, drawn.position.y, drawn.size.x, drawn.size.y])
	img.save_png("/tmp/poe_coach_%s_%02d.png" % [_phase, _taken])
	_taken += 1
	if _taken < SAMPLES:
		return
	# Opening step sampled — hand ownership over and jump to a spotlight step so the
	# NEXT batch shows the light travelling onto a real HUD target.
	if _phase == "opening":
		for iid in MatchState.buildings:
			var inst: Dictionary = MatchState.buildings[iid]
			if str(inst.get("tile_id", "")) == "tile_5_9" and str(inst.get("building_id", "")) == "b_007":
				inst["owner"] = MatchState.LOCAL_PLAYER
		_phase = "spotlight"
		_taken = 0
		Tutorial._enter(SPOTLIGHT_STEP)
		return
	_finish()


## Mean brightness of a patch of open map, clear of the HUD and the coach card, so it
## tracks the dim and nothing else.
func _map_luma(img: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(260, 560, 20):
		for x in range(700, 1400, 20):
			var c := img.get_pixel(x, y)
			total += (c.r + c.g + c.b) / 3.0 * 255.0
			n += 1
	return total / maxf(1.0, float(n))


func _finish() -> void:
	_done = true
	get_tree().quit(0)
