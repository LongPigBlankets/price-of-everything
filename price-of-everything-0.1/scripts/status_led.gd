class_name StatusLed
extends Control
## A small glass lamp: dark and visibly OFF, or lit in its colour with a soft glow.
##
## Began as top_bar's inner `_Led`, which was red-only. The tile-view tabs needed the same
## lamp in green / amber / red, and two implementations of one look drift apart the first
## time either is touched — so there is one, and it takes a colour.
##
## The unlit state matters as much as the lit one: a dead bulb reads as PRESENT and off,
## where a missing lamp reads as nothing at all, and that contrast is what makes the lit
## colour mean something.

const R := 5.0                  # the lamp itself; the glow rings extend past it
const GLOW := [[2.6, 0.28], [1.9, 0.16], [1.35, 0.09]]   # [radius x R, alpha]
const GLASS := Color("#3a4048")       # unlit — the top bar's EDGE_SEAM

var color: Color = Color("#e2604a"):
	set(v):
		if v == color:
			return
		color = v
		queue_redraw()

var lit := false:
	set(v):
		if v == lit:
			return
		lit = v
		queue_redraw()

## Flashes the lit colour on/off once a second (top bar v3.1: power's intermittency
## lamp) instead of holding it steady. No-op while `lit` is false — a blinking lamp
## that was never on would just read as a lamp with a stuck timer.
var blink := false:
	set(v):
		if v == blink:
			return
		blink = v
		_update_blink_timer()

var _blink_on := true
var _blink_timer: Timer


func _init(lamp_color: Color = Color("#e2604a")) -> void:
	color = lamp_color
	# Sized for the widest glow ring so neighbouring text never clips it.
	custom_minimum_size = Vector2(R * 2.0 + 6.0, R * 2.0 + 6.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _update_blink_timer() -> void:
	if not blink:
		if _blink_timer != null:
			_blink_timer.stop()
		_blink_on = true
		queue_redraw()
		return
	if _blink_timer == null:
		_blink_timer = Timer.new()
		_blink_timer.wait_time = 0.5   # two ticks = one flash per second
		_blink_timer.timeout.connect(func() -> void:
			_blink_on = not _blink_on
			queue_redraw())
		add_child(_blink_timer)
	_blink_on = true
	queue_redraw()
	_blink_timer.start()


func _draw() -> void:
	var c := size * 0.5
	if not lit or (blink and not _blink_on):
		draw_circle(c, R, GLASS)
		draw_arc(c, R, 0.0, TAU, 16, Color(1, 1, 1, 0.10), 1.0, true)
		return
	for ring: Array in GLOW:
		draw_circle(c, R * float(ring[0]), Color(color, float(ring[1])))
	draw_circle(c, R, color)
	draw_circle(c, R * 0.45, color.lightened(0.45))   # hot filament
