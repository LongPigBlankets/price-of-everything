extends CanvasLayer
class_name LoadingScreen
## A light day/night carousel of capsule hexes while New Game / Load builds the world.
## Parented to the tree root so it survives scene changes. Begin follows world readiness.

const DOT_PERIOD := 0.45
const MORPH_SECS := 1.0
const EXIT_SECS := 1.0
const ZOOM_FRAC := 0.5
# Keep the measured playing-zoom startup optimisation; Begin need not draw the whole map.
const START_AT_PLAY_ZOOM := true
const Carousel := preload("res://scripts/loading_carousel.gd")
const CreamKey := preload("res://scripts/ds2/cream_key.gd")
const PLATE_W := 250.0
const PLATE_H := 72.0
const BEGIN_TEXT := "Begin your legacy"

var _from_scene: Node
var _elapsed := 0.0
var _wall_t0 := 0
var _scene_changed := false
var _morphed := false
var _exiting := false
var _root: Control
var _carousel: Control
var _plate: LoadingPlate
var _begin: Button


static func show_global(tree: SceneTree) -> LoadingScreen:
	var screen := LoadingScreen.new()
	screen._from_scene = tree.current_scene
	tree.root.add_child(screen)
	return screen


## Paint the first still, warm scripts on the main thread, then request the map on a worker.
func begin_load(scene_path: String) -> void:
	# Let the loading screen actually paint before we touch the heavy load.
	await get_tree().process_frame
	await get_tree().process_frame
	await _warm_scene_scripts(scene_path)
	var _lp_t := Time.get_ticks_msec()
	if ResourceLoader.load_threaded_request(scene_path) != OK:
		get_tree().change_scene_to_file(scene_path)   # fallback: blocking load
		return
	while is_inside_tree():
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed: Variant = ResourceLoader.load_threaded_get(scene_path)
			if OS.get_environment("LOAD_PROF") != "":
				print("LOADPROF threaded scene load %d ms   abs=%d" % [Time.get_ticks_msec() - _lp_t, Time.get_ticks_msec()])
			if packed is PackedScene:
				get_tree().change_scene_to_packed(packed)
			else:
				get_tree().change_scene_to_file(scene_path)
			return
		if status != ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			get_tree().change_scene_to_file(scene_path)   # failed / invalid → fallback
			return
		await get_tree().process_frame


# Preload-dependent scripts must compile on the main thread before scene loading.
func _warm_scene_scripts(scene_path: String) -> void:
	var t0 := Time.get_ticks_msec()
	var warmed := 0
	for dep in ResourceLoader.get_dependencies(scene_path):
		# Entries are either "res://path" or "uid://x::::res://path".
		var at := String(dep).rfind("res://")
		if at < 0:
			continue
		var path := String(dep).substr(at)
		# Scripts and sub-scenes only. Textures, tilesets and audio load perfectly well on a
		# worker thread, and leaving them to it is exactly the parallelism this buys back.
		if not (path.ends_with(".gd") or path.ends_with(".tscn")):
			continue
		if not is_inside_tree():
			return
		ResourceLoader.load(path)
		warmed += 1
		await get_tree().process_frame   # let the carousel advance between compiles
	if OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF warmed %d scene scripts in %d ms   abs=%d" % [
			warmed, Time.get_ticks_msec() - t0, Time.get_ticks_msec()])


func _ready() -> void:
	_wall_t0 = Time.get_ticks_msec()
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	if DS != null and DS.theme != null:
		_root.theme = DS.theme
	add_child(_root)
	_carousel = Carousel.new()
	_carousel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_carousel)
	_build_plate()
	_build_begin_button()


func _build_plate() -> void:
	_plate = LoadingPlate.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.z_index = 10
	_centre_box(_plate, PLATE_W, PLATE_H)
	_root.add_child(_plate)


## The button is a CHILD OF THE PLATE, filling the same box the header was centred in.
##
## The plate used to fade out and hand over to a 480-wide button floating where it had been.
## That threw away the one solid object on screen at the exact moment the player is asked to
## act on it. Now the panel stays put and only its CONTENTS change — the word dissolves, the
## button arrives in the space it left — so the thing they click is the thing they have been
## watching for twenty seconds.
##
## Being a child also means it cannot drift: it is anchored to the plate's own content_rect,
## so it tracks the plate and stays clear of the bolts by construction rather than by a
## second set of numbers that has to be kept in step.
func _build_begin_button() -> void:
	# The DS2 cream key, the call to action every DS2 panel uses, sized to fit the plate's face.
	var box: Rect2 = _plate.content_rect()
	var k := clampf(box.size.y / CreamKey.height_for(), 0.6, 1.0)
	_begin = CreamKey.make("BeginKey", BEGIN_TEXT, "", box.size.x, false, false, k)
	_begin.z_index = 11
	_begin.visible = false
	_begin.modulate.a = 0.0
	_begin.focus_mode = Control.FOCUS_NONE
	_begin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_plate.add_child(_begin)
	var h := CreamKey.height_for(k)
	_begin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_begin.offset_left = box.position.x
	_begin.offset_right = box.position.x + box.size.x
	_begin.offset_top = box.position.y + (box.size.y - h) * 0.5
	_begin.offset_bottom = _begin.offset_top + h
	_begin.pressed.connect(_on_begin_pressed)


func _centre_box(c: Control, w: float, h: float) -> void:
	# Keep the call to action below the floating hex.
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.95
	c.anchor_bottom = 0.95
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = -h * 0.5
	c.offset_bottom = h * 0.5


func _process(delta: float) -> void:
	_elapsed += delta
	if not _morphed:
		_plate.set_header("Loading" + ".".repeat(1 + int(_elapsed / DOT_PERIOD) % 3))
		if _ready_to_begin():
			_show_begin()


## Is the world built and the pending snapshot applied?
func _world_ready() -> bool:
	var current := get_tree().current_scene
	if not _scene_changed:
		if current != null and current != _from_scene:
			_scene_changed = true   # the new map scene now exists
		return false
	if SaveLoad.has_pending():
		return false
	if current != null:
		var bc: Variant = current.get("build_complete")
		if bc != null:
			return bool(bc)
	return true


func _ready_to_begin() -> bool:
	# Readiness follows actual work: no cinematic minimum, and no timeout that
	# exposes the map while generation is still blocking its camera.
	return _world_ready()


# ── Morph + exit ──────────────────────────────────────────────────────────────

func _show_begin() -> void:
	_morphed = true
	if OS.get_environment("LOAD_PROF") != "":
		print("BEGIN offered at %.2f s wall" % (float(Time.get_ticks_msec() - _wall_t0) / 1000.0))
	# THE PANEL STAYS. Only what is written on it changes: the word goes, the button arrives in
	# the space it left. The word leaves faster than the button arrives, and the button starts
	# after the word is mostly gone, so the two never sit on top of each other mid-cross-fade.
	_begin.visible = true
	_begin.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_method(_plate.set_text_alpha, 1.0, 0.0, MORPH_SECS * 0.45)
	tw.tween_property(_begin, "modulate:a", 1.0, MORPH_SECS * 0.65).set_delay(MORPH_SECS * 0.35)


func _on_begin_pressed() -> void:
	if _exiting:
		return
	_exiting = true
	# The world has been painted once already and then hidden again beneath the loading screen
	# (world_map._hide_world_after_warm) Bring it back now, one frame before the
	# fade starts over it.
	var scene := get_tree().current_scene
	if scene != null and scene.has_method("reveal_for_play"):
		scene.call("reveal_for_play")
	# Fade the theme as the game begins (it played through loading), then bring the
	# playlist back ~3 s later so gameplay isn't left silent.
	Audio.fade_music(2.0, 5.0)
	_begin.disabled = true
	_start_camera_intro()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, EXIT_SECS)
	tw.tween_callback(queue_free)


func _start_camera_intro() -> void:
	# With START_AT_PLAY_ZOOM the camera is already where this would have landed, and running it
	# would throw the view back out to the whole map — the expensive framing that setting exists
	# to avoid — only to travel back in.
	if START_AT_PLAY_ZOOM:
		return
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		cam = get_tree().get_first_node_in_group("camera")
	if cam != null and cam.has_method("start_intro_zoom"):
		cam.start_intro_zoom(ZOOM_FRAC, EXIT_SECS)


# ── The metallic "Loading…" plate ─────────────────────────────────────────────
## The DS2 panel's look, as the tutorial card's: a dark metal face with a faint brushed grain in a polished
## silver frame, its bevel lit from the top left. It says "Loading" and nothing else (it is a caption under the
## carousel, not a place to put reading matter), then holds the Begin key.
class LoadingPlate extends Control:
	const F_HEAD := preload("res://assets/fonts/BebasNeue-Regular.ttf")
	const SILVER_LT := Color("#b3bcc6")
	const SILVER_MD := Color("#8b95a1")
	const SILVER_DK := Color("#5b636e")
	const SILVER_HI := Color("#eef1f4")
	const FACE_TOP := Color("#2a2e35")
	const FACE_FOOT := Color("#15181c")
	const RIM := Color("#f4e6c0")          # cream metallic rim / header
	const ACCENT := Color("#e6b34a")       # gold
	const INSET := 6.0                     # the dark face's inset inside the silver frame (= the frame's width)
	const RADIUS := 14.0                   # rounded-rect corner radius
	const FONT_SIZE := 26
	## Text keeps clear of the frame. With the word centred this is the minimum the plate has to be wide
	## enough for, not where the text starts.
	const TEXT_PAD := INSET + 14.0
	## The longest the header ever gets. The text is centred on THIS so the dots do not move it.
	const WIDEST_HEADER := "Loading..."

	var header := "Loading"
	## The header fades on its own, INDEPENDENTLY of the plate. The plate does not leave when
	## the load ends any more — the button arrives inside it — so the thing that has to go is
	## the word, not the panel it is written on.
	var text_alpha := 1.0

	## The face clear of the frame: where the header is centred, and exactly where the
	## Begin button goes. ONE definition, so the button cannot land somewhere the text never
	## was, or overlap the frame if the plate is ever resized.
	func content_rect() -> Rect2:
		return Rect2(Vector2(TEXT_PAD, INSET + 3.0),
			Vector2(size.x - TEXT_PAD * 2.0, size.y - (INSET + 3.0) * 2.0))

	func set_text_alpha(a: float) -> void:
		if is_equal_approx(a, text_alpha):
			return
		text_alpha = a
		queue_redraw()

	func set_header(s: String) -> void:
		if s == header:
			return
		header = s
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)

		# Drop shadow under the whole plate.
		draw_colored_polygon(_round_rect(Rect2(r.position + Vector2(0, 4), r.size), RADIUS), Color(0, 0, 0, 0.35))

		# Silver under-plate (the frame), a rounded rectangle.
		var sp := _round_rect(r, RADIUS)
		draw_polygon(sp, _grad(sp, r, SILVER_LT, SILVER_MD, SILVER_DK, SILVER_MD))
		var so := sp.duplicate()
		so.append(sp[0])
		draw_polyline(so, Color("#3a4048"), 1.5, true)

		# The silver frame's bevel: lit along the top and left, shaded along the bottom and right.
		draw_polyline(_round_rect(r.grow(-1.0), RADIUS - 1.0).slice(6, 14), Color(SILVER_HI, 0.85), 1.5, true)
		draw_polyline(_round_rect(r.grow(-1.0), RADIUS - 1.0).slice(20, 28), Color(SILVER_DK, 0.9), 1.5, true)

		# The dark metal face, set into the frame: a shade lighter at the top, a faint brushed grain, a dark cut
		# where the frame overhangs it. The DS2 panels' metal (the tutorial card's), clean of scuffs.
		var nr := r.grow(-INSET)
		var np := _round_rect(nr, RADIUS - INSET)
		draw_polygon(np, _grad(np, nr, FACE_TOP, FACE_TOP, FACE_FOOT, FACE_FOOT))
		var y := nr.position.y + 3.0
		while y < nr.end.y - 3.0:
			draw_line(Vector2(nr.position.x + RADIUS * 0.5, y), Vector2(nr.end.x - RADIUS * 0.5, y), Color(1, 1, 1, 0.03), 1.0)
			y += 3.0
		var no := np.duplicate()
		no.append(np[0])
		draw_polyline(no, Color("#0e1013"), 1.2, true)

		# Header — Bebas, cream, with a soft drop shadow. Centred on the WIDEST state the
		# word ever reaches, not on itself: the trailing dots animate, and centring each
		# state in turn makes the whole word shuffle sideways as they come and go. So the
		# text box is fixed and the dots grow into it.
		if text_alpha <= 0.002:
			return
		var widest := F_HEAD.get_string_size(WIDEST_HEADER, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var hx := r.position.x + (r.size.x - widest) * 0.5
		var hy := r.position.y + (r.size.y - F_HEAD.get_height(FONT_SIZE)) * 0.5
		var base := hy + F_HEAD.get_ascent(FONT_SIZE)
		draw_string(F_HEAD, Vector2(hx + 1, base + 1), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0, 0, 0, 0.5 * text_alpha))
		draw_string(F_HEAD, Vector2(hx, base), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(RIM, text_alpha))

	# A rounded-rectangle outline (clockwise), arc-traced at each corner. Fed to
	# draw_polygon/_grad exactly like the old octagon was.
	func _round_rect(r: Rect2, radius: float) -> PackedVector2Array:
		var rad := clampf(radius, 0.0, minf(r.size.x, r.size.y) * 0.5)
		var segs := 6
		var pts := PackedVector2Array()
		# corner arc centres + sweep, in order TL, TR, BR, BL.
		var corners := [
			[r.position + Vector2(rad, rad), PI, PI * 1.5],
			[Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5, TAU],
			[r.end - Vector2(rad, rad), 0.0, PI * 0.5],
			[Vector2(r.position.x + rad, r.end.y - rad), PI * 0.5, PI],
		]
		for cnr in corners:
			var c: Vector2 = cnr[0]
			var a0: float = cnr[1]
			var a1: float = cnr[2]
			for i in range(segs + 1):
				var t := a0 + (a1 - a0) * float(i) / float(segs)
				pts.append(c + Vector2(cos(t), sin(t)) * rad)
		return pts

	func _grad(pts: PackedVector2Array, r: Rect2, tl: Color, tr: Color, br: Color, bl: Color) -> PackedColorArray:
		var cols := PackedColorArray()
		for p in pts:
			var u := (p.x - r.position.x) / maxf(1.0, r.size.x)
			var v := (p.y - r.position.y) / maxf(1.0, r.size.y)
			cols.append(tl.lerp(tr, u).lerp(bl.lerp(br, u), v))
		return cols
