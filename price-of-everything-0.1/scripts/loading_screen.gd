extends CanvasLayer
class_name LoadingScreen
## Loading screen shown while a New Game / Load spins up. Parented to the tree
## ROOT (not the current scene) so it survives the change_scene_to_file that the
## load performs. It cycles a set of full-bleed posters with a slow crossfade and
## shows a metallic octagonal "Loading…" plate carrying a gameplay tip. Once the
## map scene is up and any pending snapshot has applied, the plate morphs (1 s
## crossfade) into a steel "Begin your industrial legacy" button. Clicking it
## fades the whole screen out over 1 s while the map camera eases from the full-
## map view to mid-range — so the reveal *is* the zoom-in.

const SAFETY_TIMEOUT := 60.0   # last-resort: offer Begin even if build_complete never arrives
const DOT_PERIOD := 0.45       # seconds per "Loading…" dot step
const BG_HOLD := 4.0           # seconds each poster is held before the next fades in
const BG_FADE := 1.0           # crossfade duration between posters
const MORPH_SECS := 1.0        # plate → Begin button crossfade
const EXIT_SECS := 1.0         # fade-out + camera zoom on Begin
const ZOOM_FRAC := 0.5         # how far between full-out and full-in the intro zoom lands
const IMG_COUNT := 5

const TIP := "Tip: Some goods are interchangeable in recipes, like coal, petroleum needle coke and carbonised biomass. Change which one you use in recipes from the Construct menu."
const HEAD_FONT := preload("res://assets/fonts/BebasNeue-Regular.ttf")

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
var _frames := 0
var _rest_loaded := false
var _scene_changed := false
var _morphed := false
var _exiting := false

var _root: Control            # holds everything; its modulate is faded on exit
var _imgs: Array = []
var _bg_front: TextureRect    # base poster layer (the current poster)
var _bg_back: TextureRect     # overlay layer (the next poster), crossfaded in over the front
var _bg_idx := 0
var _bg_start_ms := 0

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
	if ResourceLoader.load_threaded_request(scene_path) != OK:
		get_tree().change_scene_to_file(scene_path)   # fallback: blocking load
		return
	while is_inside_tree():
		var progress: Array = []
		var status := ResourceLoader.load_threaded_get_status(scene_path, progress)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var packed: Variant = ResourceLoader.load_threaded_get(scene_path)
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

	_load_images()
	_build_backgrounds()
	_build_plate()
	_build_begin_button()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _load_images() -> void:
	# Only the first poster is loaded up front so the screen can paint immediately;
	# posters 2..N stream in after the first frame (see _process), well before the
	# 4 s rotation needs them. Loading all five here would block the first paint.
	_load_image(1)


func _load_image(i: int) -> void:
	var path := "res://assets/loading/loading_screen_%d.png" % i
	if ResourceLoader.exists(path):
		var tex: Texture2D = load(path)
		if tex != null:
			_imgs.append(tex)


func _load_rest_images() -> void:
	for i in range(2, IMG_COUNT + 1):
		_load_image(i)


func _build_backgrounds() -> void:
	# Navy base shows through if the posters are missing.
	var base := ColorRect.new()
	base.color = Color(0, 0.07, 0.14)
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(base)

	_bg_front = _make_bg_layer()
	_bg_back = _make_bg_layer()
	_root.add_child(_bg_front)
	_root.add_child(_bg_back)
	if _imgs.size() > 0:
		_bg_front.texture = _imgs[0]
	_bg_front.modulate.a = 1.0
	_bg_front.z_index = 0
	_bg_back.modulate.a = 0.0
	_bg_back.z_index = 1   # the next poster always crossfades in ABOVE the current one
	_bg_start_ms = Time.get_ticks_msec()

	# Dark scrim so the metallic plate + tip stay legible over bright posters.
	var scrim := ColorRect.new()
	scrim.color = Color(0, 0, 0, 0.30)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scrim.z_index = 5
	_root.add_child(scrim)


func _make_bg_layer() -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


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
	_frames += 1
	# Stream in the remaining posters once the first frame has painted.
	if not _rest_loaded and _frames >= 2:
		_rest_loaded = true
		_load_rest_images()
	if not _morphed:
		_plate.set_header("Loading" + ".".repeat(1 + int(_elapsed / DOT_PERIOD) % 3))
		if _ready_to_begin():
			_show_begin()
	_tick_backgrounds(delta)


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
	# keep animating its slideshow), so "scene exists" ≠ "world ready" — wait for the
	# map's build_complete flag if it exposes one.
	if current != null:
		var bc: Variant = current.get("build_complete")
		if bc != null:
			return bool(bc)
	return true


func _tick_backgrounds(_delta: float) -> void:
	# Wall-clock-driven crossfade slideshow. Each poster holds for BG_HOLD then fades
	# to the next over BG_FADE. Driving it off elapsed time (not accumulated frame
	# delta) keeps an even pace even when the map build hitches the main thread between
	# frames — a frozen 0.5 s frame just resumes at the right place rather than flipping
	# several posters at once.
	if _imgs.size() < 2 or _exiting:
		return
	var n := _imgs.size()
	var cycle := BG_HOLD + BG_FADE
	var elapsed := float(Time.get_ticks_msec() - _bg_start_ms) / 1000.0
	var idx := int(elapsed / cycle) % n
	var nxt := (idx + 1) % n
	var phase := fmod(elapsed, cycle)
	_bg_idx = idx
	_bg_front.texture = _imgs[idx]
	_bg_front.modulate.a = 1.0
	_bg_back.texture = _imgs[nxt]
	_bg_back.modulate.a = 0.0 if phase <= BG_HOLD else clampf((phase - BG_HOLD) / BG_FADE, 0.0, 1.0)


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
	const INSET := 6.0                     # navy octagon inset inside the silver plate
	const CUT := 28.0                      # octagon corner cut
	const RIVET_EDGE := 9.0

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
		draw_colored_polygon(_octa(Rect2(r.position + Vector2(0, 4), r.size), CUT), Color(0, 0, 0, 0.35))

		# Silver under-plate (the riveted frame).
		var sp := _octa(r, CUT)
		draw_polygon(sp, _grad(sp, r, SILVER_LT, SILVER_MD, SILVER_DK, SILVER_MD))
		var so := sp.duplicate()
		so.append(sp[0])
		draw_polyline(so, Color("#3a4048"), 1.5, true)

		# Navy octagon on top, inset, with diagonal lighting + sheen + cream rim.
		var nr := r.grow(-INSET)
		var np := _octa(nr, CUT - INSET)
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

	func _octa(r: Rect2, cut: float) -> PackedVector2Array:
		var x0 := r.position.x
		var y0 := r.position.y
		var x1 := r.end.x
		var y1 := r.end.y
		return PackedVector2Array([
			Vector2(x0 + cut, y0), Vector2(x1 - cut, y0),
			Vector2(x1, y0 + cut), Vector2(x1, y1 - cut),
			Vector2(x1 - cut, y1), Vector2(x0 + cut, y1),
			Vector2(x0, y1 - cut), Vector2(x0, y0 + cut),
		])

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
