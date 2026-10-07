extends Control
## The DS2 top bar's mission: a cream key holding the mission's title and, beside it, a brass piston
## head riding in a painted steel track with the mission's count (x/y) printed on its face. When a
## mission completes the piston strokes to the far end of its track with steam venting from its gland,
## the key changes to the next mission, and the piston snaps back.
## Art: res://assets/ui/bdp_v3/mission_track.png, mission_rod.png and mission_head.png, rendered by
## tools/button_mockup/cluster.html?export&only=missionslot (layout.json, mission_slot).

signal celebration_finished

const ModKey := preload("res://scripts/bdp_v3_mod_key.gd")
const Light := preload("res://scripts/bdp_v3_light.gd")
const Plate := preload("res://scripts/bdp_v3_plate.gd")
const TRACK: Texture2D = preload("res://assets/ui/bdp_v3/mission_track.png")
const ROD: Texture2D = preload("res://assets/ui/bdp_v3/mission_rod.png")
const HEAD: Texture2D = preload("res://assets/ui/bdp_v3/mission_head.png")
const CAPTURE_SCALE := 1.875
const TEXELS_PER_PIXEL := 2.0
## From layout.json (mission_slot), in layout pixels: the slot the head rides in, the gland the rod
## leaves through, the head's frame and the padding round its block, and the head's cream face.
const SLOT_X0 := 44.0
const SLOT_X1 := 252.0
const GLAND_X := 30.0
const GLAND_LIP := 11.0
const HEAD_PAD := 8.0
const FACE := Vector2(76.0, 28.0)
## The key is drawn smaller than Building Detail's, so its keycap stands as tall as the track's plate.
const KEY_SCALE := 0.68
const GAP := 6.0
## The key is never narrower than this, so a short title still reads as a key.
const KEY_MIN_W := 170.0
## Nor wider than this title needs at full print size; a longer title is cut short with an ellipsis.
const REFERENCE_TITLE := "Secure lasting coal and iron deposits"
const NAVY := Color("#0b2340")

const STROKE_SEC := 0.55
const HOLD_SEC := 0.35
const TITLE_FADE_SEC := 0.15
const SNAP_SEC := 0.12
const KNOCK_SEC := 0.14
const KNOCK := 0.035
## The shine that points the player at the missions: a slanted band of light swept across the slot.
const SHINE_SEC := 0.9
const SHINE_GAP_SEC := 0.25
const SHINE_PASSES := 2
const SHINE_W := 64.0
const SHINE_SLANT := 22.0

var key: Control
## Collapsed, the key is hidden: the top bar shows the missions icon in `lead_width` at the left and the
## piston beside it, and the mission's text only on hover.
var collapsed := false
var lead_width := 0.0
var _full_title := ""
## How far the head has travelled along the slot, 0 at rest by the gland to 1 at the far end.
var stroke := 0.0
var _have := 0
var _need := 0
var _anim: Tween
var _steam: Array[Dictionary] = []
var _venting := false
var _fx: Control
var _shine: Control
## Where the shine's band is across the slot, 0 off its left edge to 1 off its right; -1 when not shining.
var _shine_at := -1.0
var _shine_anim: Tween
var _puff: Texture2D
## Steam's own generator: cosmetic, and kept off the global one the sim must never share.
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	name = "MissionSlot"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	key = ModKey.new()
	key.openable = false
	key.key_scale = KEY_SCALE
	key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(key)
	_fx = Control.new()
	_fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx.draw.connect(_draw_steam)
	add_child(_fx)
	_shine = Control.new()
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.clip_contents = true
	_shine.material = Light.across_material(Light.glow_material())
	_shine.draw.connect(_draw_shine)
	add_child(_shine)
	_puff = _make_puff()
	set_process(false)


## The mission to show: its title, and its count when it asks for more than one of something.
func set_mission(title: String, progress: Vector2i) -> void:
	_full_title = title
	_have = progress.x
	_need = progress.y
	_fit_title()
	queue_redraw()
	update_minimum_size()


## Hides the key (the top bar shows its icon in `lead` px at the left instead) or shows it again.
func set_collapsed(value: bool, lead: float) -> void:
	collapsed = value
	lead_width = lead
	key.visible = not value
	update_minimum_size()
	queue_redraw()


## The track's size in logical pixels.
static func track_size() -> Vector2:
	return TRACK.get_size() / TEXELS_PER_PIXEL


## The width the slot wants: the key wide enough for its title at full print size, between KEY_MIN_W and
## the width REFERENCE_TITLE needs, then the track. Collapsed, the icon's room and the track.
func ideal_width() -> float:
	if collapsed:
		return ceilf(lead_width + GAP + track_size().x)
	return ceilf(clampf(_key_width_for(_full_title), KEY_MIN_W, max_key_width()) + GAP + track_size().x)


## The widest the key gets: REFERENCE_TITLE at full print size.
static func max_key_width() -> float:
	return _key_width_for(REFERENCE_TITLE)


static func _print_size() -> int:
	return roundi(22 * KEY_SCALE)


## The key's print inset on each side, as BdpV3ModKey draws it (no chevron).
static func _print_margin() -> float:
	return ModKey.FACE_INSET / CAPTURE_SCALE * KEY_SCALE + 6.0 * KEY_SCALE


static func _key_width_for(title: String) -> float:
	var text_w: float = Plate.FONT_BOLD.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, _print_size()).x
	return text_w + 2.0 * _print_margin() + 6.0 * KEY_SCALE


## Puts the title on the key at full print size, cut short with an ellipsis where the key ends.
func _fit_title() -> void:
	var room := (key.size.x if key.size.x > 1.0 else clampf(_key_width_for(_full_title), KEY_MIN_W, max_key_width())) \
		- 2.0 * _print_margin() - 6.0 * KEY_SCALE
	key.summary = ellipsize(_full_title, room, _print_size())
	key.queue_redraw()


## `text` cut short with an ellipsis to fit `room` px at `font_size` in the key's bold print.
static func ellipsize(text: String, room: float, font_size: int) -> String:
	var font: Font = Plate.FONT_BOLD
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
		return text
	var cut := text
	while cut.length() > 1:
		cut = cut.substr(0, cut.length() - 1).strip_edges()
		if font.get_string_size(cut + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= room:
			return cut + "…"
	return "…"


func _get_minimum_size() -> Vector2:
	var lead := lead_width if collapsed else 80.0
	return Vector2(track_size().x + GAP + lead, maxf(track_size().y, key.get_combined_minimum_size().y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		var t := track_size()
		var kh: float = key.get_combined_minimum_size().y
		key.position = Vector2(0.0, roundf((size.y - kh) * 0.5))
		key.size = Vector2(maxf(0.0, size.x - t.x - GAP), kh)
		_fx.position = Vector2.ZERO
		_fx.size = size
		_shine.position = Vector2.ZERO
		_shine.size = size
		_fit_title()


## Plays the completion: the stroke with steam, a hold of `hold` seconds, `swap` (which sets the next mission)
## behind a fade of the key's print, and the snap back. Emits celebration_finished at the end.
func celebrate(swap: Callable, hold: float = HOLD_SEC) -> void:
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_venting = true
	set_process(true)
	_anim = create_tween()
	_anim.tween_method(_set_stroke, stroke, 1.0, STROKE_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim.tween_callback(func() -> void:
		_venting = false
		_burst(_head_rect().get_center() + Vector2(_head_rect().size.x * 0.5, 0.0), 5))
	_anim.tween_interval(hold)
	_anim.tween_property(key, "modulate:a", 0.0, TITLE_FADE_SEC)
	_anim.tween_callback(swap)
	_anim.tween_property(key, "modulate:a", 1.0, TITLE_FADE_SEC)
	_anim.tween_method(_set_stroke, 1.0, 0.0, SNAP_SEC).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	_anim.tween_callback(func() -> void: _burst(_gland_point(), 3))
	_anim.tween_method(_set_stroke, 0.0, KNOCK, KNOCK_SEC * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_anim.tween_method(_set_stroke, KNOCK, 0.0, KNOCK_SEC * 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_anim.tween_callback(func() -> void: celebration_finished.emit())


## Sweeps a band of light across the slot SHINE_PASSES times, to draw the eye to it.
func shine() -> void:
	if _shine_anim != null and _shine_anim.is_valid():
		_shine_anim.kill()
	_shine_anim = create_tween()
	for i in SHINE_PASSES:
		if i > 0:
			_shine_anim.tween_interval(SHINE_GAP_SEC)
		_shine_anim.tween_method(_set_shine, 0.0, 1.0, SHINE_SEC).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_shine_anim.tween_callback(_set_shine.bind(-1.0))


func is_shining() -> bool:
	return _shine_at >= 0.0


func _set_shine(v: float) -> void:
	_shine_at = v
	_shine.queue_redraw()


func _draw_shine() -> void:
	if _shine_at < 0.0:
		return
	var h := size.y
	var x := lerpf(-SHINE_W - SHINE_SLANT, size.x + SHINE_SLANT, _shine_at)
	var clear := Color(1.0, 0.97, 0.88, 0.0)
	var bright := Color(1.0, 0.97, 0.88, 0.8)
	# Two quads, clear at the band's edges and bright down its middle, leaning right as they rise.
	for half in 2:
		var x0 := x + SHINE_W * 0.5 * float(half)
		var x1 := x0 + SHINE_W * 0.5
		var c0 := clear if half == 0 else bright
		var c1 := bright if half == 0 else clear
		_shine.draw_polygon(
			PackedVector2Array([Vector2(x0, h), Vector2(x1, h), Vector2(x1 + SHINE_SLANT, 0.0), Vector2(x0 + SHINE_SLANT, 0.0)]),
			PackedColorArray([c0, c1, c1, c0]))


## True while a completion is playing.
func is_celebrating() -> bool:
	return _anim != null and _anim.is_valid() and _anim.is_running()


func _set_stroke(v: float) -> void:
	stroke = v
	queue_redraw()


# --- drawing ------------------------------------------------------------------------------------

func _track_rect() -> Rect2:
	var t := track_size()
	return Rect2(Vector2(size.x - t.x, roundf((size.y - t.y) * 0.5)), t)


## The head's frame (its render, shadow room included) at the current stroke.
func _head_rect() -> Rect2:
	var tr := _track_rect()
	var h := HEAD.get_size() / TEXELS_PER_PIXEL
	var pad := HEAD_PAD / CAPTURE_SCALE
	var block_w := h.x - 2.0 * pad
	var x0 := tr.position.x + SLOT_X0 / CAPTURE_SCALE + 1.0
	var x1 := tr.position.x + SLOT_X1 / CAPTURE_SCALE - 1.0 - block_w
	var x := lerpf(x0, x1, stroke) - pad
	return Rect2(Vector2(x, tr.get_center().y - h.y * 0.5), h)


func _gland_point() -> Vector2:
	var tr := _track_rect()
	return Vector2(tr.position.x + (GLAND_X + GLAND_LIP) / CAPTURE_SCALE, tr.get_center().y)


func _draw() -> void:
	var tr := _track_rect()
	draw_texture_rect(TRACK, tr, false)
	var head := _head_rect()
	var pad := HEAD_PAD / CAPTURE_SCALE
	# The rod: from the gland to the head's block, a run from the middle of its render stretched along x.
	var rod_from := _gland_point().x
	var rod_to := head.position.x + pad + 4.0
	if rod_to > rod_from + 1.0:
		var rh := ROD.get_height() / TEXELS_PER_PIXEL
		var src := Rect2(ROD.get_width() * 0.25, 0.0, ROD.get_width() * 0.5, ROD.get_height())
		draw_texture_rect_region(ROD, Rect2(rod_from, tr.get_center().y - rh * 0.5, rod_to - rod_from, rh), src)
	draw_texture_rect(HEAD, head, false)
	if _need > 1:
		var face := Rect2(head.get_center() - FACE / CAPTURE_SCALE * 0.5, FACE / CAPTURE_SCALE).grow(-2.0)
		var text := "%d/%d" % [mini(_have, _need), _need]
		var bold: Font = Plate.FONT_BOLD
		var fs := Plate._fit(bold, text, 14, face.size.x)
		var w := bold.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var base := face.get_center().y + (bold.get_ascent(fs) - bold.get_descent(fs)) * 0.5
		draw_string(bold, Vector2(face.get_center().x - w * 0.5, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, NAVY)


# --- steam --------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if _venting:
		_emit(_gland_point(), 1 if _rng.randf() < 0.5 else 0)
	for p: Dictionary in _steam:
		p.age = float(p.age) + delta
		p.pos = (p.pos as Vector2) + (p.vel as Vector2) * delta
		p.vel = (p.vel as Vector2) * (1.0 - 1.6 * delta) + Vector2(0.0, -18.0 * delta)
	_steam = _steam.filter(func(p: Dictionary) -> bool: return float(p.age) < float(p.life))
	_fx.queue_redraw()
	if _steam.is_empty() and not _venting:
		set_process(false)


func _emit(at: Vector2, n: int) -> void:
	for i in n:
		_steam.append({
			"pos": at + Vector2(_rng.randf_range(-2.0, 2.0), _rng.randf_range(-3.0, 3.0)),
			"vel": Vector2(_rng.randf_range(-30.0, -10.0), _rng.randf_range(-34.0, -12.0)),
			"r": _rng.randf_range(4.0, 6.0), "grow": _rng.randf_range(16.0, 28.0),
			"age": 0.0, "life": _rng.randf_range(0.6, 1.1),
		})


func _burst(at: Vector2, n: int) -> void:
	_emit(at, n)
	set_process(true)


func _draw_steam() -> void:
	for p: Dictionary in _steam:
		var t := float(p.age) / float(p.life)
		var r := float(p.r) + float(p.grow) * t
		var a := 0.22 * (1.0 - t) * minf(1.0, t * 6.0 + 0.3)
		_fx.draw_texture_rect(_puff, Rect2((p.pos as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.93, 0.95, 0.97, a))


static func _make_puff() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.4, Color(1, 1, 1, 0.5))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex
