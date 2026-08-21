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
	_build_plate()
	_build_begin_button()


# ── Setup ─────────────────────────────────────────────────────────────────────

func _build_backgrounds() -> void:
	# Animated hex-field background (its own navy fill + grey→gold lines), full-bleed
	# behind the metallic "Loading…" plate. z 0 so the plate (z 10) sits over it.
	_hex_bg = LoadingHexBg.new()
	_hex_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hex_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hex_bg.z_index = 0
	_root.add_child(_hex_bg)


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
	if not _morphed:
		_plate.set_header("Loading" + ".".repeat(1 + int(_elapsed / DOT_PERIOD) % 3))
		if _ready_to_begin():
			_show_begin()


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
