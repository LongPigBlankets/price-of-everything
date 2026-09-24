extends Control
## Building Detail v3: one check in the diagnostics' visual view. A raised cream icon and its shadow
## (res://assets/ui/bdp_v3/diag_icon_*.png) with pilot lamps under it: one lit for the check's tone, or,
## for a check over several goods, one for each tone among them (at most three, worst first). The icon is
## trimmed: the render is scaled so its art, not its frame, fills the icon's box, sitting on the lamps. It
## says nothing itself: hovering it sends its name and detail to the case's readout.

signal hovered(indicator: Control)
signal unhovered(indicator: Control)

const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const LAMP_GAP := 3.0
## The gap between lamps side by side, and the most a check shows.
const LAMP_SPACING := 3.0
const MAX_LAMPS := 3
## A hovered icon is drawn this much brighter.
const HOT_MODULATE := Color(1.2, 1.2, 1.2)

## Each render's art rect (its opaque pixels, in texels), found once per texture.
static var _art_rects := {}

var stage := ""
var label := ""
var detail := ""
var tone := "off"
## The tones its lamps show, worst first; [tone] for a check about one thing.
var tones: Array = ["off"]
var icon: Texture2D
var shadow: Texture2D
## The first lamp, and all of them.
var lamp: Control
var lamps: Array[Control] = []
var hot := false
## The icon's side, and the lamps' size as a share of the status lamp's (the text rows' lamps are 0.72).
var icon_px := 28.0
var _lamp_scale := 0.55


func _init() -> void:
	name = "BdpV3Indicator"
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	# PASS, not STOP: the pointer's wheel still reaches the panel's scroll.
	mouse_filter = Control.MOUSE_FILTER_PASS
	lamp = Lamp.new()
	add_child(lamp)
	lamps.append(lamp)
	configure(icon_px, _lamp_scale)
	mouse_entered.connect(_on_enter)
	mouse_exited.connect(_on_exit)


## The icon's side and the lamps' scale.
func configure(px: float, lamp_scale: float) -> void:
	icon_px = px
	_lamp_scale = lamp_scale
	for l in lamps:
		l.lamp_scale = lamp_scale
	_fit()


func _fit() -> void:
	var side: Vector2 = lamp.custom_minimum_size
	var row := lamps.size() * side.x + (lamps.size() - 1) * LAMP_SPACING
	custom_minimum_size = Vector2(maxf(icon_px, row), icon_px + LAMP_GAP + side.y)
	_place_lamp()
	queue_redraw()


## The check this indicator shows: {stage, label, detail, tone}, and the icon to draw for it.
func set_check(check: Dictionary, face: Texture2D, face_shadow: Texture2D) -> void:
	stage = str(check.get("stage", ""))
	label = str(check.get("label", ""))
	detail = str(check.get("detail", ""))
	tone = str(check.get("tone", "off"))
	tones = (check.get("tones", [tone]) as Array).slice(0, MAX_LAMPS)
	if tones.is_empty():
		tones = [tone]
	icon = face
	shadow = face_shadow
	while lamps.size() < tones.size():
		var extra: Control = Lamp.new()
		extra.lamp_scale = _lamp_scale
		add_child(extra)
		lamps.append(extra)
	while lamps.size() > tones.size():
		var gone: Control = lamps.pop_back()
		remove_child(gone)
		gone.queue_free()
	for i in lamps.size():
		lamps[i].set_tone(str(tones[i]))
	_fit()
	queue_redraw()


func _on_enter() -> void:
	hot = true
	queue_redraw()
	hovered.emit(self)


func _on_exit() -> void:
	hot = false
	queue_redraw()
	unhovered.emit(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place_lamp()


## The lamps side by side, centred under the icon.
func _place_lamp() -> void:
	var side: Vector2 = lamp.custom_minimum_size
	var row := lamps.size() * side.x + (lamps.size() - 1) * LAMP_SPACING
	var x := (size.x - row) * 0.5
	for l in lamps:
		l.position = Vector2(x, icon_px + LAMP_GAP)
		l.size = side
		x += side.x + LAMP_SPACING


## The part of a render that holds its art: the rect of its opaque pixels, in texels.
static func art_rect(tex: Texture2D) -> Rect2:
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_rid())
	if not _art_rects.has(key):
		var r := Rect2(Vector2.ZERO, tex.get_size())
		var img := tex.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			var used := img.get_used_rect()
			if used.size.x > 0 and used.size.y > 0:
				r = Rect2(used)
		_art_rects[key] = r
	return _art_rects[key]


## Where the whole render is drawn so that its art fits the icon's box, centred across and standing on
## the box's foot. The shadow is drawn to the same rect, so it falls where it was rendered.
func art_dest() -> Rect2:
	var art := art_rect(icon)
	var k := icon_px / maxf(art.size.x, art.size.y)
	var art_size := art.size * k
	var at := Vector2((size.x - art_size.x) * 0.5, icon_px - art_size.y)
	return Rect2(at - art.position * k, icon.get_size() * k)


func _draw() -> void:
	if icon == null:
		return
	var rect := art_dest()
	if shadow != null:
		draw_texture_rect(shadow, rect, false)
	draw_texture_rect(icon, rect, false, HOT_MODULATE if hot else Color.WHITE)
