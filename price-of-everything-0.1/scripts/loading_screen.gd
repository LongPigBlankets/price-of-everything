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

## Last-resort: offer Begin even if build_complete never arrives. In WALL seconds, like
## BEGIN_MIN_WALL and for the same reason — a net measured in clamped delta is not a net.
const SAFETY_TIMEOUT := 60.0
const DOT_PERIOD := 0.45       # seconds per "Loading…" dot step
const MORPH_SECS := 1.0        # plate → Begin button crossfade
const EXIT_SECS := 1.0         # fade-out + camera zoom on Begin
const ZOOM_FRAC := 0.5         # how far between full-out and full-in the intro zoom lands
## Start the match already at the playing zoom instead of zoomed fully out, and skip the intro
## zoom (there would be nowhere to travel to).
##
## This is a LOOK decision with a measured price, which is why it is a switch and not a fix.
## Zoomed out frames the whole map at ~24,450 draw calls; the playing view is ~7,700. With the
## reveal repaint already gone, turning this on halved the worst frame after Begin again —
## 465 -> 244 ms and 488 -> 251 ms, interleaved. What it costs is the opening zoom itself.
const START_AT_PLAY_ZOOM := true

## The loading film, when one has been rendered. ABSENT IS NORMAL: with no file here the
## screen is exactly what it was — the hex lattice drawing in under the plate — so the film is
## something the screen gains, never something it depends on.
const FILM_PATH := "res://assets/loading/film.ogv"
## What the film was authored at. Used to frame it before the first decoded frame arrives;
## after that the real texture size wins.
##
## THE 16:9 MASTER, NOT THE WIDESCREEN ONE. FILM_RUNBOOK.md renders 2400x1080 so ultrawides
## get ~12.5% more street, and the centre 1920x1080 of it is the approved composition at 1:1.
## But Theora decodes on one thread and the wide frame costs 52-94 ms of it — 8-12 fps, which
## is not a film. The 16:9 master costs ~10 ms (measured against the same screen with decode
## paused, 31 ms either way), and on a 16:9 window it is pixel-for-pixel what the wide one
## would have shown after cropping. The trade is only for ultrawide players, who now get the
## same frame with the top and bottom cropped rather than a slideshow with more street.
const FILM_SIZE := Vector2(1920.0, 1080.0)
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
## So the load opens on plates cross-fading one into the next, and the film starts only once
## the sequence has finished AND the build is done.
##
## STACKING ORDER AND REVEAL ORDER ARE NOT THE SAME THING, which is the one subtlety here.
## The plates are cutouts stacked back to front — sky behind, props in front — because that
## is where those things are. But they arrive front to back: road, then the trees and cars,
## then the near buildings, then the far ones, then the city, and the sky last. A building
## revealed after the road still has to sit behind it. So the z order is the file order and
## the arrival order is sequence.json, and neither is derived from the other.
##
## Absent is normal: with no plates on disk the screen behaves exactly as it did before.
const INTRO_DIR := "res://assets/loading/intro"
const PLATE_FADE := 0.45   # seconds to bring the next layer in
const PLATE_HOLD := 0.55   # seconds to sit on it before the next starts

## A CROSS-FADE IS THE ONLY MOVING THING ON THIS SCREEN, so it is the only thing a stalled
## frame can visibly ruin. A plate that just sits there for a second is invisible; a fade
## frozen half way through is not.
##
## The load's remaining big steps cannot be divided — the scene instantiates in one engine
## call, a panel builds in one call, the world's first paint is one frame — so they cannot be
## made to fit between transitions. What they CAN do is land during a hold, and that only
## needs the sequence to refuse to START a fade while the main thread is busy.
##
## Busy is measured from the frames themselves rather than agreed with the build: it needs no
## cooperation, and it catches a stall from any source, including ones nobody has thought of.
## A frame over CALM_FRAME_MS means something is holding the thread; the sequence waits for
## quiet, up to CALM_MAX_WAIT so a permanently busy machine still gets its intro.
const CALM_FRAME_MS := 120.0
const CALM_MAX_WAIT := 6.0

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
##   AFTER_INTRO  the default when plates exist: the film starts when the plate sequence ends,
##                whether or not the build has finished. The plates cover the part of the load
##                that cannot share a main thread at all; whatever is left over runs UNDER the
##                film, which costs it a little (measured below) and buys two things — the
##                player sees the film from the moment there is nothing better to show, and a
##                load that grows in future eats into the film rather than into the wait.
enum FilmStart { IMMEDIATE, AFTER_SCENE, AFTER_BUILD, AFTER_INTRO }
const FILM_START := FilmStart.AFTER_INTRO
## How long the film takes to fade up over the lattice, and to fade back down when it ends.
const FILM_FADE := 0.6

const HEAD_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")
const LoadingHexBg := preload("res://scripts/loading_hex_bg.gd")

# Plate / button geometry. Both sit dead centre of the screen and share a centre, so the
# morph from one to the other is a clean crossfade in place.
const PLATE_W := 250.0
const PLATE_H := 72.0
## The label the plate turns into. It is MEASURED against the plate at build time rather than
## trusted to fit: Bebas 26 puts it at 154 px inside 190 px of clear navy, but a longer wording
## would silently run under the bolts, so _build_begin_button steps the size down until it fits.
const BEGIN_TEXT := "Begin your legacy"
const BEGIN_FONT_SIZE := 26
const BEGIN_FONT_MIN := 14

var _from_scene: Node
var _elapsed := 0.0
## Real milliseconds since this screen went up. `_elapsed` cannot answer that (see
## BEGIN_MIN_WALL), and everything the PLAYER waits for is measured in real seconds.
var _wall_t0 := 0
## Wall duration of the last frame, ms. The clock the calm check reads — `delta` is clamped
## while the main thread is blocked, so it cannot see the very stalls this is looking for.
var _last_frame_ms := 0.0
var _frame_mark := 0
var _fade_waits := 0
var _fade_wait_ms := 0
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
var _plate_reveal: Array[int] = []   # arrival order; see _reveal_order
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
	_wall_t0 = Time.get_ticks_msec()
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
	_plate_reveal = _reveal_order(paths)
	_layout_plates()
	# The plates cover the lattice from the first frame, and the lattice is ~1,832 draw calls
	# of something nobody can see. (_tick_film does this too, but only when there is a film.)
	if _hex_bg != null:
		_hex_bg.visible = false
	_run_intro()


## The plates in name order — 01_, 02_, ... The numbering is the STACKING order, back to
## front. What arrives when is sequence.json; see _reveal_order.
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


## Hold here until the main thread looks calm, so a transition does not start into a stall.
## See CALM_FRAME_MS. Waiting is in WALL time — the whole point is that the other clock stops
## during exactly the frames being waited out.
func _wait_for_calm() -> void:
	if _last_frame_ms <= CALM_FRAME_MS:
		return
	var t0 := Time.get_ticks_msec()
	while _last_frame_ms > CALM_FRAME_MS and is_inside_tree():
		if float(Time.get_ticks_msec() - t0) / 1000.0 >= CALM_MAX_WAIT:
			break
		await get_tree().process_frame
	_fade_waits += 1
	_fade_wait_ms += Time.get_ticks_msec() - t0


## The order the plates ARRIVE in, as indices into `_plates` (which is stacking order).
## Read from sequence.json beside them; without one, they arrive bottom to top, which is what
## a set of plates with no opinion should do.
func _reveal_order(paths: PackedStringArray) -> Array[int]:
	var order: Array[int] = []
	var file := FileAccess.open(INTRO_DIR + "/sequence.json", FileAccess.READ)
	if file != null:
		var parsed: Variant = JSON.parse_string(file.get_as_text())
		file.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			for name_value in ((parsed as Dictionary).get("reveal", []) as Array):
				var want := INTRO_DIR + "/" + str(name_value)
				var idx := -1
				for i in paths.size():
					if paths[i] == want:
						idx = i
						break
				if idx >= 0 and not order.has(idx):
					order.append(idx)
				elif idx < 0:
					push_warning("LoadingScreen: sequence.json names '%s', which is not there." % str(name_value))
	# Anything the manifest did not mention still has to arrive, or it would never be seen.
	for i in paths.size():
		if i != 0 and not order.has(i):
			order.append(i)
	return order


## Bring each plate up in turn. Tweens, not video: a frame lost to a busy main thread pauses
## this sequence, it does not desynchronise it, which is the whole reason the load opens on
## stills rather than on the film.
func _run_intro() -> void:
	var _t_wall := Time.get_ticks_msec()
	await get_tree().create_timer(PLATE_HOLD).timeout   # a beat on the empty world first
	for step in _plate_reveal:
		if not is_inside_tree():
			return
		if _plates[step].texture == null:
			_plates[step].texture = load(_plate_paths[step]) as Texture2D
			_layout_plates()
		await _wait_for_calm()
		if not is_inside_tree():
			return
		var tw := create_tween()
		tw.tween_property(_plates[step], "modulate:a", 1.0, PLATE_FADE)
		await tw.finished
		await get_tree().create_timer(PLATE_HOLD).timeout
	_intro_done = true
	if OS.get_environment("LOAD_PROF") != "":
		print("INTRO done: %.2f s of process time, %.2f s of WALL time; %d fade(s) waited for calm, %d ms total" % [
			_elapsed, float(Time.get_ticks_msec() - _t_wall) / 1000.0, _fade_waits, _fade_wait_ms])


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
			# The intro has run AND the world is built — but NOT that the button is allowed
			# yet. The film starting is about having a free main thread; the button appearing
			# is about giving the player a reason to have watched it. Different questions.
			ready_now = _intro_done and _world_ready()
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
	_begin = Button.new()
	_begin.text = BEGIN_TEXT
	# THE DESIGN SYSTEM'S CTA, not a local imitation of one. "Primary" is what every other
	# call to action in the game uses — Buy, Upgrade, New Game — so the button that starts the
	# match is the same object the player will meet everywhere else.
	_begin.theme_type_variation = &"Primary"
	_begin.z_index = 11
	_begin.visible = false
	_begin.modulate.a = 0.0
	_begin.focus_mode = Control.FOCUS_NONE              # no focus ring inside the panel
	_begin.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_plate.add_child(_begin)                           # in the tree first, or the theme lookups miss

	var box: Rect2 = _plate.content_rect()
	# Fit the DS CTA to the plate rather than the other way round, and MEASURE it against the
	# theme's own font and padding instead of assuming: the variation brings its own typeface
	# and its own content margins, and both move if the design system changes.
	var f: Font = _begin.get_theme_font("font")
	var sb: StyleBox = _begin.get_theme_stylebox("normal")
	var pad := 8.0
	if sb != null:
		pad = sb.content_margin_left + sb.content_margin_right + 4.0
	var avail := box.size.x - pad
	var fsize := BEGIN_FONT_SIZE
	if f != null:
		while fsize > BEGIN_FONT_MIN and f.get_string_size(
				BEGIN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x > avail:
			fsize -= 1
	_begin.add_theme_font_size_override("font_size", fsize)
	if OS.get_environment("LOAD_PROF") != "":
		print("LOADPROF begin CTA: %.0f px of %.0f available at size %d"
			% [f.get_string_size(BEGIN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
				if f != null else 0.0, avail, fsize])

	_begin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_begin.offset_left = box.position.x
	_begin.offset_top = box.position.y
	_begin.offset_right = box.position.x + box.size.x
	_begin.offset_bottom = box.position.y + box.size.y
	_begin.pressed.connect(_on_begin_pressed)


func _centre_box(c: Control, w: float, h: float) -> void:
	# Dead centre of the screen, both axes.
	c.anchor_left = 0.5
	c.anchor_right = 0.5
	c.anchor_top = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -w * 0.5
	c.offset_right = w * 0.5
	c.offset_top = -h * 0.5
	c.offset_bottom = h * 0.5


# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _frame_mark > 0:
		_last_frame_ms = float(now - _frame_mark)
	_frame_mark = now
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


## The earliest "Begin" may appear, in seconds since this screen went up. The button waits for
## the LATER of this and a finished world.
##
## Two jobs. It gives the player a reason to have watched the film — a button offered on a
## shot's first frame is the same as not showing the shot. And it is a BUFFER: the load is
## ~13 s today, so there is ~7 s of slack, and a future load that grows into that slack costs
## the player nothing at all, because they were never going to be allowed to leave before 20 s
## anyway. It only starts costing time once the load exceeds it.
##
## The safety timeout below still overrides everything, so a transition that goes sideways
## cannot strand anyone behind this.
##
## MEASURED IN WALL CLOCK, not in `_elapsed`. `_elapsed` accumulates `_process` delta, and
## delta is CLAMPED while the main thread is blocked — 10.0 s of it measured 18.9 s of real
## time across this load. A twenty-second promise made in that currency is not twenty seconds.
const BEGIN_MIN_WALL := 20.0

## Is the world built and the pending snapshot applied? Says nothing about whether the player
## may leave yet — see _ready_to_begin.
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
	var wall := float(Time.get_ticks_msec() - _wall_t0) / 1000.0
	if wall > SAFETY_TIMEOUT:
		return true   # don't strand the player if a transition goes sideways
	if not _world_ready():
		return false
	# Built. The button still waits for the 20 s mark — see BEGIN_MIN_WALL.
	return wall >= BEGIN_MIN_WALL


# ── Morph + exit ──────────────────────────────────────────────────────────────

func _show_begin() -> void:
	_morphed = true
	if OS.get_environment("LOAD_PROF") != "":
		print("BEGIN offered at %.2f s wall (film at %.2f s)" % [
			float(Time.get_ticks_msec() - _wall_t0) / 1000.0,
			_film.stream_position if _film != null else -1.0])
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
	# The world has been painted once already and then hidden again so the film could have the
	# main thread (world_map._hide_world_after_warm). Bring it back now, one frame before the
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
## Replicates the End Turn dock's treatment: a squarish silver under-plate with a
## navy panel inset on top (so the silver reads as a riveted frame), diagonal
## lighting, and a cream rim. It says "Loading" and nothing else — it is a caption
## under a film now, not a place to put reading matter.
class LoadingPlate extends Control:
	const F_HEAD := preload("res://assets/fonts/BebasNeue-Regular.ttf")
	const NAVY_TL := Color(0.025, 0.18, 0.34)
	const NAVY_TR := Color(0.0, 0.12156863, 0.24313726)
	const NAVY_BL := Color(0.0, 0.105, 0.215)
	const NAVY_BR := Color(0.0, 0.067, 0.145)
	const SILVER_LT := Color("#b3bcc6")
	const SILVER_MD := Color("#8b95a1")
	const SILVER_DK := Color("#5b636e")
	const RIM := Color("#f4e6c0")          # cream metallic rim / header
	const ACCENT := Color("#e6b34a")       # gold
	const INSET := 5.0                     # navy inset inside the silver plate (= silver band width)
	const RADIUS := 14.0                   # rounded-rect corner radius
	const FONT_SIZE := 26
	const RIVET_R := 4.0
	## Bolt centres, in from each edge. They sit ON THE NAVY PANEL, not on the silver band:
	## INSET + RIVET_R is where a bolt would just clear the band, and the rest is the gap that
	## keeps it looking seated rather than balanced on the edge.
	const RIVET_EDGE := INSET + RIVET_R + 8.0
	## Text keeps clear of the bolts — their outer edge plus a breath. With the word centred
	## this is the minimum the plate has to be wide enough for, not where the text starts.
	const TEXT_PAD := RIVET_EDGE + RIVET_R + 9.0
	## The longest the header ever gets. The text is centred on THIS so the dots do not move it.
	const WIDEST_HEADER := "Loading..."

	var header := "Loading"
	## The header fades on its own, INDEPENDENTLY of the plate. The plate does not leave when
	## the load ends any more — the button arrives inside it — so the thing that has to go is
	## the word, not the panel it is written on.
	var text_alpha := 1.0

	## The navy area clear of the bolts: where the header is centred, and exactly where the
	## Begin button goes. ONE definition, so the button cannot land somewhere the text never
	## was, or overlap a rivet if the plate is ever resized.
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

		# Four corner bolts, seated on the navy.
		_rivets(r)

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

	func _rivets(r: Rect2) -> void:
		# Four corners only. The mid-edge pair read well across a 740 px plate and crowd a
		# 250 px one, where they would sit almost on top of the word.
		var e := RIVET_EDGE
		for c in [
			Vector2(e, e), Vector2(r.size.x - e, e),
			Vector2(e, r.size.y - e), Vector2(r.size.x - e, r.size.y - e),
		]:
			_rivet(r.position + c, RIVET_R)

	func _rivet(c: Vector2, rad: float) -> void:
		draw_circle(c, rad, Color("#5a636e"))
		draw_circle(c - Vector2(rad * 0.3, rad * 0.3), rad * 0.55, Color("#c9d4df"))
		draw_arc(c, rad, 0, TAU, 16, Color(0, 0, 0, 0.5), 1.0)
