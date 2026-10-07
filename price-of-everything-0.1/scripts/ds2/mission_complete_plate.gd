extends Control
## A mission's completion, under the DS2 top bar: a dark metal plate that runs down out of the bar on two silver
## rails, glowing gold, says MISSION COMPLETE, the mission and its reward, holds HOLD_SEC, then runs back up.
## This Control is the window the plate shows through: it sits against the bar's lower edge and clips, so the
## plate comes out from under the bar rather than appearing over it. The rails stand in it while the plate runs.
## Art: dark_metal_plate.png and screw_silver.png (bdp_v3).

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")
const SCREW: Texture2D = preload("res://assets/ui/bdp_v3/screw_silver.png")
## The dark metal plate's 9-slice corner in texels and the shadow room beyond its slab (layout.json).
const PLATE_CORNER := (10.0 + 44.0) * 2.0 / 1.875
const PLATE_OUTSET := 10.0 / 1.875

const DROP_SEC := 0.45
const HOLD_SEC := 4.0
const RETRACT_SEC := 0.35
const PLATE_MIN_W := 360.0
const PAD := Vector2(26.0, 14.0)
## The glow's reach beyond the plate, and the room the window keeps for it.
const GLOW := 16.0
const GLOW_RINGS := 8
const GLOW_GOLD := Color("#f2c14e")
## The rails: their width, how far outside the plate they run, and the silver they are drawn in.
const RAIL_W := 6.0
const RAIL_OUT := 5.0
const RAIL_HI := Color("#eef1f4")
const RAIL_LO := Color("#7d8791")
const SCREW_PX := 12.0

var _plate: Control
var _title: Label
var _mission: Label
var _reward: Label
var _drop := 0.0
var _clock := 0.0
var _anim: Tween


func _init() -> void:
	name = "MissionCompletePlate"
	# Placed on the screen, not by the bar's container.
	top_level = true
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_plate = Control.new()
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plate)
	var metal: Control = Nine.make("dark_metal_plate", PLATE_CORNER, PLATE_OUTSET)
	metal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_plate.add_child(metal)
	var screws := Control.new()
	screws.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screws.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screws.draw.connect(func() -> void:
		for c: Vector2 in [Vector2(12, 12), Vector2(screws.size.x - 12, 12), Vector2(12, screws.size.y - 12),
				Vector2(screws.size.x - 12, screws.size.y - 12)]:
			screws.draw_texture_rect(SCREW, Rect2(c - Vector2.ONE * SCREW_PX * 0.5, Vector2.ONE * SCREW_PX), false))
	_plate.add_child(screws)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.add_child(col)
	_title = _label(UIFonts.BEBAS, 24, DS.PALETTE.ACCENT)
	_title.text = "MISSION COMPLETE"
	col.add_child(_title)
	_mission = _label(null, 16, DS.PALETTE.TEXT)
	col.add_child(_mission)
	_reward = _label(null, 14, DS.PALETTE.OK)
	col.add_child(_reward)
	set_process(false)


## Plays the completion for `mission` and its `reward`, the plate centred under `centre_x` on the screen with
## this window's top at `top_y`, the bar's lower edge. Returns how long it runs.
func play(mission: String, reward: String, centre_x: float, top_y: float) -> float:
	_mission.text = mission
	_reward.text = "Reward: %s" % reward if reward != "" else ""
	_reward.visible = reward != ""
	var col: Control = _plate.get_child(2)
	var inner := col.get_combined_minimum_size()
	var plate_size := Vector2(maxf(PLATE_MIN_W, inner.x + PAD.x * 2.0), inner.y + PAD.y * 2.0).round()
	_plate.size = plate_size
	col.position = PAD
	col.size = plate_size - PAD * 2.0
	var room := GLOW + RAIL_OUT + RAIL_W
	size = Vector2(plate_size.x + room * 2.0, plate_size.y + GLOW * 2.0)
	position = Vector2(roundf(centre_x - size.x * 0.5), top_y)
	visible = true
	_clock = 0.0
	set_process(true)
	if _anim != null and _anim.is_valid():
		_anim.kill()
	_set_drop(0.0)
	_anim = create_tween()
	_anim.tween_method(_set_drop, 0.0, 1.0, DROP_SEC).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_anim.tween_interval(HOLD_SEC)
	_anim.tween_method(_set_drop, 1.0, 0.0, RETRACT_SEC).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_anim.tween_callback(func() -> void:
		visible = false
		set_process(false))
	return DROP_SEC + HOLD_SEC + RETRACT_SEC


func is_playing() -> bool:
	return _anim != null and _anim.is_valid() and _anim.is_running()


func _set_drop(v: float) -> void:
	_drop = v
	var room := GLOW + RAIL_OUT + RAIL_W
	# At 0 the plate (and its glow) sits wholly above the window, under the bar; at 1 it hangs clear of it.
	_plate.position = Vector2(room, lerpf(-_plate.size.y - GLOW, GLOW * 0.5, v)).round()
	queue_redraw()


func _process(delta: float) -> void:
	_clock += delta
	queue_redraw()


func _draw() -> void:
	var r := Rect2(_plate.position, _plate.size)
	# The glow, breathing gently, behind the plate.
	var breathe := 0.75 + 0.25 * sin(_clock * 3.0)
	for i in GLOW_RINGS:
		var t := float(i + 1) / float(GLOW_RINGS)
		draw_rect(r.grow(GLOW * t), Color(GLOW_GOLD, 0.28 * (1.0 - t) * breathe * _drop_light()), false, GLOW / GLOW_RINGS + 1.0)
	# The rails: one each side, run out from the bar with the plate and a little past it, a silver bar each.
	var rail_bottom := clampf(r.end.y + 6.0, 0.0, size.y)
	for x: float in [r.position.x - RAIL_OUT - RAIL_W, r.end.x + RAIL_OUT]:
		_rail(Rect2(x, 0.0, RAIL_W, rail_bottom))
		# The plate's shoe on the rail at its top and bottom.
		for y: float in [r.position.y + 8.0, r.end.y - 16.0]:
			var shoe := Rect2(x - 2.0, y, RAIL_W + 4.0, 8.0)
			draw_rect(shoe, RAIL_LO)
			draw_rect(shoe.grow(-1.0), RAIL_HI.lerp(RAIL_LO, 0.4))


func _drop_light() -> float:
	return clampf(_drop, 0.0, 1.0)


func _rail(r: Rect2) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([RAIL_HI, RAIL_LO, RAIL_LO, RAIL_HI]))
	draw_line(Vector2(r.position.x + 1.5, r.position.y), Vector2(r.position.x + 1.5, r.end.y), Color(1, 1, 1, 0.6), 1.0)


static func _label(font: Font, px: int, colour: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if font != null:
		l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_color", colour)
	return l
