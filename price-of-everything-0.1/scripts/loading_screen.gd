extends CanvasLayer
class_name LoadingScreen
## Loading screen shown while a New Game / Load spins up. Parented to the tree
## ROOT (not the current scene) so it survives the change_scene_to_file that the
## load performs. It shows an animated hex-field background (the grey lattice draws
## in, then a wavy gold wavefront sweeps a corner path) behind a metallic octagonal
## "Loading…" plate carrying a gameplay tip. Once the
## map scene is up and any pending snapshot has applied, the plate morphs (1 s
## crossfade) into a steel "Begin your industrial legacy" button. Clicking it
## fades the whole screen out over 1 s while the map camera eases from the full-
## map view to mid-range — so the reveal *is* the zoom-in.

const SAFETY_TIMEOUT := 60.0   # last-resort: offer Begin even if build_complete never arrives
const DOT_PERIOD := 0.45       # seconds per "Loading…" dot step
const MORPH_SECS := 1.0        # plate → Begin button crossfade
const EXIT_SECS := 1.0         # fade-out + camera zoom on Begin
const ZOOM_FRAC := 0.5         # how far between full-out and full-in the intro zoom lands

## The loading film, when one has been rendered. ABSENT IS NORMAL: with no file here the
## screen is exactly what it was — the hex lattice drawing in under the plate — so the film is
## something the screen gains, never something it depends on.
const FILM_PATH := "res://assets/loading/film.ogv"
## What the film was authored at (FILM_RUNBOOK.md). Used to frame it before the first decoded
## frame arrives; after that the real texture size wins.
const FILM_SIZE := Vector2(2400.0, 1080.0)
## Seconds the film is given to put its first frame up before the heavy load is allowed to
## start. It is a beat, not a wait: the load begins the moment a frame is presented.
const FILM_HEAD_START := 1.5

## THE INTRO PLATES — the film's opening composition, assembling itself.
##
## The first seconds of a load are the ones the main thread cannot share: the scene
## instantiation alone is a ~1.3 s frame, and a video frozen for 1.3 s is a shot frozen for
## 1.3 s. Still images do not have that problem. A tween that misses a frame resumes where it
## was; a video that misses a frame has lost that frame for good, which is why the film used to
## finish 4.4 s behind the wall clock.
##
## So the load opens on plates — sky, then skyline, then street, then ground, then the whole
## frame — cross-fading one into the next, and the film starts only once the sequence has
## finished AND the build is done. The last plate IS the film's first frame, so the cut into
## video is on an identical picture.
##
## Absent is normal: with no plates on disk the screen behaves exactly as it did before.
const INTRO_DIR := "res://assets/loading/intro"
const PLATE_FADE := 0.5    # seconds to bring the next layer in
const PLATE_HOLD := 1.0    # seconds to sit on it before the next starts

## WHEN THE FILM STARTS — the one setting worth understanding here.
##
## Theora decodes on the MAIN THREAD, so the film runs at speed only while the main thread is
## free. Loading a new game leaves it free for the first stretch (the map scene is read on a
## worker) and then takes it three times. Measured on a 1280x720 window with
## tools/loading_film_check.tscn, as stream time the film LOSES — a frozen film does not catch
## up, it falls behind:
##
##   IMMEDIATE    5.5 s of clean play while the scene loads on the worker, then freezes of
##                ~1.8 s (scene instantiation), ~1.4 s (world build) and ~1.2 s (first paint
##                of the revealed map). Total drift 4.1 s.
##   AFTER_SCENE  starts once the map scene exists (~7.5 s in), so the instantiation freeze is
##                already behind it — but the other two are not. Drift 3.0 s, and the hex
##                lattice covers the first ~7 s.
##   AFTER_BUILD  starts when the world is ready. The build is over, so there is nothing left
##                to freeze it: the lattice covers the whole load and the film plays clean
##                end to end. With the load down to ~12 s and the film 45 s long, this makes
##                it an intro rather than a loading screen — which is arguably what a 45 s
##                film now is.
##
## There is no "right" answer here, only a trade between how soon the film appears and how
## smoothly it plays; this is a presentation decision, so it is one word in one place.
##   AFTER_INTRO  the default when plates exist: the film waits for the plate sequence AND
##                the build, so it only ever starts on a main thread that is free. This is
##                what the plates are for.
enum FilmStart { IMMEDIATE, AFTER_SCENE, AFTER_BUILD, AFTER_INTRO }
const FILM_START := FilmStart.AFTER_INTRO
## How long the film takes to fade up over the lattice, and to fade back down when it ends.
const FILM_FADE := 0.6

const TIP := "Tip: Some goods are interchangeable in recipes, like coal, petroleum needle coke and carbonised biomass. Change which one you use in recipes from the Construct menu."
const HEAD_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const LoadingHexBg := preload("res://scripts/loading_hex_bg.gd")

# Plate / button geometry. Both sit bottom-centred, BOTTOM_MARGIN px above the
# screen bottom; the button is centred on the plate's footprint so the morph is a
# clean crossfade in place.
const PLATE_W := 740.0
const PLATE_H := 176.0
const BTN_W := 480.0
const BTN_H := 72.0
const BOTTOM_MARGIN := 40.0

var _from_scene: Node
var _elapsed := 0.0
var _scene_changed := false
var _morphed := false
var _exiting := false

var _root: Control            # holds everything; its modulate is faded on exit
var _hex_bg: Control          # animated hex-field background (draw-in + gold sweep)
var _film_box: Control        # clips the film to the window (see _layout_film)
var _film: VideoStreamPlayer  # null when no film has been rendered yet
var _film_box_size := Vector2.ZERO   # last size the film was framed for
var _plate_box: Control = null      # clips the intro plates, same fit as the film
var _plate_box_size := Vector2.ZERO
var _plate_paths := PackedStringArray()
var _film_started := false          # a deferred film (FILM_START) has been kicked off
var _plates: Array[TextureRect] = []   # intro plates, back to front
var _intro_done := false               # the plate sequence has finished (or there were none)

var _plate: LoadingPlate
var _begin: Button


static func show_global(tree: SceneTree) -> LoadingScreen:
	var screen := LoadingScreen.new()
	screen._from_scene = tree.current_scene
	tree.root.add_child(screen)
	return screen


## Drive the transition to `scene_path` WITHOUT freezing the game. The map scene
## (and its textures/tilesets) is the heavy part of a new game — loading it inline
## blocks for ~0.6–0.9 s, during which nothing renders, so the menu just hangs and
## the loading screen only flashes at the very end. Instead we let this screen paint
## a frame, load the scene on a worker thread while the posters + dots keep
## animating, and only swap scenes once it's ready. Falls back to a blocking load if
## threaded loading can't start. The pending snapshot must already be set by the
## caller (e.g. SaveLoad.prepare_new_game) — apply_pending runs in the map's _ready.
func begin_load(scene_path: String) -> void:
	# Let the loading screen actually paint before we touch the heavy load.
	await get_tree().process_frame
	await get_tree().process_frame
	# And, when there is a film, let it get a frame on screen before the load starts
	# competing for the main thread. Theora decodes on the MAIN thread, so a film that
	# starts underneath a busy build opens on a stutter instead of a shot.
	await _await_film_started()
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


func _ready() -> void:
	layer = 100
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow input to the map underneath
	# Theme inheritance doesn't cross the CanvasLayer reliably, so pin the shared DS
	# theme on our root explicitly — the Begin button needs its steel-blue surface.
	if DS != null and DS.theme != null:
		_root.theme = DS.theme
	add_child(_root)

	_build_backgrounds()
	_build_intro_plates()
	_build_film()
	_build_plate()
	_build_begin_button()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _build_backgrounds() -> void:
	# Animated hex-field background (its own navy fill + grey→gold lines), full-bleed
	# behind the metallic "Loading…" plate. z 0 so the plate (z 10) sits over it.
	# IT STAYS when there is a film. The film is layered OVER it (z 5), fades up rather than
	# cutting, and fades back down when it ends — so the lattice is what the screen opens on,
	# what it returns to, and the whole screen when no film has been rendered.
	_hex_bg = LoadingHexBg.new()
	_hex_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hex_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hex_bg.z_index = 0
	_root.add_child(_hex_bg)


## The film, if one has been rendered. It is COVER-fitted and clipped, never letterboxed:
## FILM_RUNBOOK.md renders 2400x1080 so that a 16:9 window shows the approved 1920x1080
## composition at 1:1 and an ultrawide gets more street — which is a centre crop, and a
## letterbox would throw away exactly the framing the render was set up to give.
## Stack the intro plates in the same cover-fitted box the film uses, all transparent but the
## first, and start the sequence. Each plate is the whole picture up to that layer, so they
## simply stack — no masks, no ordering rules, and a missing one costs a step and nothing else.
func _build_intro_plates() -> void:
	var paths := _intro_plate_paths()
	if paths.is_empty():
		_intro_done = true
		return
	_plate_box = Control.new()
	_plate_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate_box.clip_contents = true
	_plate_box.z_index = 4   # over the lattice, under the film (5) and the plate (10)
	_root.add_child(_plate_box)
	# The first is wanted this frame; the rest are wanted a second apart, so they are read on
	# worker threads rather than costing four PNG loads before the screen has painted once.
	for i in range(1, paths.size()):
		ResourceLoader.load_threaded_request(paths[i])
	for i in paths.size():
		var rect := TextureRect.new()
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.modulate.a = 1.0 if i == 0 else 0.0
		if i == 0:
			rect.texture = load(paths[i]) as Texture2D
		_plates.append(rect)
		_plate_box.add_child(rect)
	_plate_paths = paths
	_layout_plates()
	# The plates cover the lattice from the first frame, and the lattice is ~1,832 draw calls
	# of something nobody can see. (_tick_film does this too, but only when there is a film.)
	if _hex_bg != null:
		_hex_bg.visible = false
	_run_intro()


## The plates, in name order — 01_, 02_, ... The numbering IS the sequence.
func _intro_plate_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(INTRO_DIR)
	if dir == null:
		return out
	var names := dir.get_files()
	names.sort()
	for n in names:
		var name := String(n).trim_suffix(".remap").trim_suffix(".import")
		if name.ends_with(".png") and not out.has(INTRO_DIR + "/" + name):
			out.append(INTRO_DIR + "/" + name)
	return out


## Bring each plate up in turn. Tweens, not video: a frame lost to a busy main thread pauses
## this sequence, it does not desynchronise it, which is the whole reason the load opens on
## stills rather than on the film.
func _run_intro() -> void:
	for i in _plates.size():
		if not is_inside_tree():
			return
		if i > 0:
			if _plates[i].texture == null:
				_plates[i].texture = load(_plate_paths[i]) as Texture2D
				_layout_plates()
			var tw := create_tween()
			tw.tween_property(_plates[i], "modulate:a", 1.0, PLATE_FADE)
			await tw.finished
		if i < _plates.size() - 1:
			await get_tree().create_timer(PLATE_HOLD).timeout
	_intro_done = true


## Cover-fit every plate the way the film is fitted, so the hand-off between the last plate and
## the first frame of video does not move the picture.
func _layout_plates() -> void:
	if _plate_box == null:
		return
	var box := _plate_box.size
	if box.x <= 1.0 or box.y <= 1.0:
		return
	for rect in _plates:
		var native := FILM_SIZE
		if rect.texture != null and rect.texture.get_size().x > 1.0:
			native = rect.texture.get_size()
		var scale := maxf(box.x / native.x, box.y / native.y)
		rect.size = native * scale
		rect.position = (box - native * scale) * 0.5
	_plate_box_size = box


func _build_film() -> void:
	if not ResourceLoader.exists(FILM_PATH):
		return   # not rendered yet: the lattice is the screen, exactly as before
	var stream: VideoStream = load(FILM_PATH) as VideoStream
	if stream == null:
		push_warning("LoadingScreen: %s is not a video stream — showing the hex field only." % FILM_PATH)
		return
	_film_box = Control.new()
	_film_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_film_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film_box.clip_contents = true
	_film_box.z_index = 5   # over the lattice, under the plate (z 10) and the button (z 11)
	_root.add_child(_film_box)

	_film = VideoStreamPlayer.new()
	_film.stream = stream
	_film.expand = true
	_film.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_film.modulate.a = 0.0   # faded up by _process once the first frame is decoded
	_film_box.add_child(_film)
	_layout_film()
	if FILM_START == FilmStart.IMMEDIATE:
		_film.play()


## Frame the film to COVER the window, centred, with the overflow clipped by _film_box.
func _layout_film() -> void:
	if _film == null or _film_box == null:
		return
	var box := _film_box.size
	if box.x <= 1.0 or box.y <= 1.0:
		return
	var native := FILM_SIZE
	var tex := _film.get_video_texture()
	if tex != null and tex.get_size().x > 1.0:
		native = tex.get_size()
	var scale := maxf(box.x / native.x, box.y / native.y)
	var shown := native * scale
	_film.size = shown
	_film.position = (box - shown) * 0.5
	_film_box_size = box


## Hand the film a beat to put its first frame up before the caller starts the heavy load.
## Returns immediately when there is no film, and gives up after FILM_HEAD_START either way —
## a film that will not start must not hold the game hostage.
## Start a deferred film once the thing it was waiting for has happened. No-op for
## IMMEDIATE (already playing) and once it is running.
func _maybe_start_film() -> void:
	if _film == null or _film.is_playing() or _film_started:
		return
	var ready_now := false
	match FILM_START:
		FilmStart.AFTER_SCENE:
			ready_now = _scene_changed
		FilmStart.AFTER_BUILD:
			ready_now = _ready_to_begin()
		FilmStart.AFTER_INTRO:
			ready_now = _intro_done and _ready_to_begin()
		_:
			ready_now = true
	if ready_now:
		_film_started = true
		_film.play()


func _await_film_started() -> void:
	if _film == null or FILM_START != FilmStart.IMMEDIATE:
		return   # a deferred film is waiting on the load, so the load must not wait on it
	var waited := 0.0
	while waited < FILM_HEAD_START and is_inside_tree():
		var tex := _film.get_video_texture()
		if _film.is_playing() and tex != null and tex.get_size().x > 1.0:
			return
		waited += get_process_delta_time()
		await get_tree().process_frame


func _build_plate() -> void:
	_plate = LoadingPlate.new()
	_plate.tip = TIP
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.z_index = 10
	_bottom_box(_plate, PLATE_W, PLATE_H, BOTTOM_MARGIN)
	_root.add_child(_plate)


func _build_begin_button() -> void:
	_begin = Button.new()
	_begin.text = "Begin your industrial legacy"
	_begin.add_theme_font_override("font", HEAD_FONT)   # Bebas — matches END TURN / title
	_begin.add_theme_font_size_override("font_size", 26)
	_begin.z_index = 11
	_begin.visible = false
	_begin.modulate.a = 0.0
	# Centre the button on the plate's footprint so the morph crossfades in place.
	_bottom_box(_begin, BTN_W, BTN_H, BOTTOM_MARGIN + (PLATE_H - BTN_H) * 0.5)
	_begin.pressed.connect(_on_begin_pressed)
	_root.add_child(_begin)


func _bottom_box(c: Control, w: float, h: float, bottom_margin: float) -> void:
	# Anchor bottom-centre: horizontally centred, bottom edge `bottom_margin` px above
	# the screen bottom.
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_bottom = -bottom_margin
	c.offset_top = -bottom_margin - h


# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_elapsed += delta
	_tick_film(delta)
	if not _morphed:
		_plate.set_header("Loading" + ".".repeat(1 + int(_elapsed / DOT_PERIOD) % 3))
		if _ready_to_begin():
			_show_begin()


## Fade the film up on its first decoded frame, keep it framed if the window changes, and
## fade it back down to the lattice when it runs out. Cheap: two compares and a lerp.
func _tick_film(delta: float) -> void:
	if _film == null:
		return
	_maybe_start_film()
	if _film_box != null and _film_box.size != _film_box_size:
		_layout_film()
	if _plate_box != null and _plate_box.size != _plate_box_size:
		_layout_plates()
	var tex := _film.get_video_texture()
	var showing := _film.is_playing() and tex != null and tex.get_size().x > 1.0
	var target := 1.0 if showing else 0.0
	if not is_equal_approx(_film.modulate.a, target):
		_film.modulate.a = move_toward(_film.modulate.a, target, delta / maxf(0.01, FILM_FADE))
	# STOP DRAWING THE LATTICE UNDER AN OPAQUE FILM. The hex field is ~1,832 draw calls and the
	# film covers every pixel of it (cover-fitted, no alpha), so once the fade is done it is
	# pure cost — and an expensive loading screen is not just a slow loading screen: the build
	# hands a frame back between steps, so the SCREEN'S frame cost is charged to every one of
	# those yields. It comes straight back when the film fades out or fails.
	if _hex_bg != null:
		# The plates cover it too, and they are up from the first frame.
		_hex_bg.visible = _film.modulate.a < 1.0 and _plates.is_empty()
	# Once the film is fully up the plates underneath it are pure cost, exactly like the lattice.
	if _plate_box != null:
		_plate_box.visible = _film.modulate.a < 1.0


func _ready_to_begin() -> bool:
	if _elapsed > SAFETY_TIMEOUT:
		return true   # don't strand the player if a transition goes sideways
	var current := get_tree().current_scene
	if not _scene_changed:
		if current != null and current != _from_scene:
			_scene_changed = true   # the new map scene now exists
		return false
	if SaveLoad.has_pending():
		return false
	# The map scene builds its visuals progressively across frames (so this screen can
	# keep animating its background), so "scene exists" ≠ "world ready" — wait for the
	# map's build_complete flag if it exposes one.
	if current != null:
		var bc: Variant = current.get("build_complete")
		if bc != null:
			return bool(bc)
	return true


# ── Morph + exit ──────────────────────────────────────────────────────────────

func _show_begin() -> void:
	_morphed = true
	_plate.set_header("Ready")
	_begin.visible = true
	_begin.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_plate, "modulate:a", 0.0, MORPH_SECS)
	tw.tween_property(_begin, "modulate:a", 1.0, MORPH_SECS)
	tw.set_parallel(false)
	tw.tween_callback(func() -> void: _plate.visible = false)


func _on_begin_pressed() -> void:
	if _exiting:
		return
	_exiting = true
	# Fade the theme as the game begins (it played through loading), then bring the
	# playlist back ~3 s later so gameplay isn't left silent.
	Audio.fade_music(2.0, 5.0)
	_begin.disabled = true
	_start_camera_intro()
	var tw := create_tween()
	tw.tween_property(_root, "modulate:a", 0.0, EXIT_SECS)
	tw.tween_callback(queue_free)


func _start_camera_intro() -> void:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		cam = get_tree().get_first_node_in_group("camera")
	if cam != null and cam.has_method("start_intro_zoom"):
		cam.start_intro_zoom(ZOOM_FRAC, EXIT_SECS)


# ── The metallic octagonal "Loading…" plate ───────────────────────────────────
## Replicates the End Turn dock's treatment: a squarish silver under-plate with a
## navy octagon inset on top (so the silver reads as a riveted frame), diagonal
## lighting, and a cream rim. Draws its own header (Bebas) + wrapped tip text.
class LoadingPlate extends Control:
	const F_HEAD := preload("res://assets/fonts/BebasNeue-Regular.ttf")
	const F_BODY := preload("res://assets/fonts/IBMPlexSans-Regular.ttf")
	const NAVY_TL := Color(0.025, 0.18, 0.34)
	const NAVY_TR := Color(0.0, 0.12156863, 0.24313726)
	const NAVY_BL := Color(0.0, 0.105, 0.215)
	const NAVY_BR := Color(0.0, 0.067, 0.145)
	const SILVER_LT := Color("#b3bcc6")
	const SILVER_MD := Color("#8b95a1")
	const SILVER_DK := Color("#5b636e")
	const RIM := Color("#f4e6c0")          # cream metallic rim / header
	const ACCENT := Color("#e6b34a")       # gold
	const OFF_WHITE := Color("#eef1ea")    # tip body
	const INSET := 6.0                     # navy inset inside the silver plate (= silver band width)
	const RADIUS := 24.0                   # rounded-rect corner radius (was an octagon corner cut)
	const RIVET_EDGE := 9.0                # bolts sit this far in from each edge — on the silver band

	var header := "Loading"
	var tip := ""

	func set_header(s: String) -> void:
		if s == header:
			return
		header = s
		queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)

		# Drop shadow under the whole plate.
		draw_colored_polygon(_round_rect(Rect2(r.position + Vector2(0, 4), r.size), RADIUS), Color(0, 0, 0, 0.35))

		# Silver under-plate (the riveted frame) — a rounded rectangle so its corners
		# extend out under the bolts (an octagon chamfered them away).
		var sp := _round_rect(r, RADIUS)
		draw_polygon(sp, _grad(sp, r, SILVER_LT, SILVER_MD, SILVER_DK, SILVER_MD))
		var so := sp.duplicate()
		so.append(sp[0])
		draw_polyline(so, Color("#3a4048"), 1.5, true)

		# Navy plate on top, inset, with diagonal lighting + sheen + cream rim.
		var nr := r.grow(-INSET)
		var np := _round_rect(nr, RADIUS - INSET)
		draw_polygon(np, _grad(np, nr, NAVY_TL, NAVY_TR, NAVY_BR, NAVY_BL))
		draw_polygon(np, _grad(np, nr, Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.03), Color(0, 0, 0, 0.0), Color(1, 1, 1, 0.02)))
		var no := np.duplicate()
		no.append(np[0])
		draw_polyline(no, Color(RIM, 0.6), 1.5, true)

		# Four corner rivets on the silver frame.
		_rivets(r)

		# Header — Bebas, cream, with a soft drop shadow.
		var hx := nr.position.x + 30.0
		var hy := nr.position.y + 22.0
		draw_string(F_HEAD, Vector2(hx + 1, hy + 1 + F_HEAD.get_ascent(28)), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(0, 0, 0, 0.5))
		draw_string(F_HEAD, Vector2(hx, hy + F_HEAD.get_ascent(28)), header,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, RIM)

		# Hairline divider under the header.
		var dy := hy + 42.0
		draw_line(Vector2(nr.position.x + 26, dy), Vector2(nr.end.x - 26, dy), Color(RIM, 0.22), 1.0)

		# Tip — off-white, wrapped to the plate width.
		var tip_w := nr.size.x - 60.0
		draw_multiline_string(F_BODY, Vector2(nr.position.x + 30, dy + 16 + F_BODY.get_ascent(16)),
			tip, HORIZONTAL_ALIGNMENT_LEFT, tip_w, 16, -1, OFF_WHITE)

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

	func _rivets(r: Rect2) -> void:
		# Corners plus the midpoints of the long top/bottom edges (reads better on a
		# wide plate), all sitting on the silver frame band.
		var e := RIVET_EDGE
		var mx := r.size.x * 0.5
		for c in [
			Vector2(e, e), Vector2(mx, e), Vector2(r.size.x - e, e),
			Vector2(e, r.size.y - e), Vector2(mx, r.size.y - e), Vector2(r.size.x - e, r.size.y - e),
		]:
			_rivet(r.position + c, 4.0)

	func _rivet(c: Vector2, rad: float) -> void:
		draw_circle(c, rad, Color("#5a636e"))
		draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, Color("#c9d4df"))
		draw_arc(c, rad, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.0)
