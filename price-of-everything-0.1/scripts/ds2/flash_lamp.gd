extends "res://scripts/bdp_v3_lamp.gd"
## DS2: a pilot lamp that can alternate between tones, for a state between two others: amber and green
## for intermittent power sold to the national grid, amber and red for intermittent power only partly
## firmed. set_tone gives a steady lamp as before; set_cycle(["warn", "bad"], 1.5) changes tone evenly
## round a cycle of that many seconds and repeats.

var _cycle: Array = []
var _period := 1.5
var _clock := 0.0
var _shown := -1


func _init() -> void:
	super()
	name = "FlashLamp"
	set_process(false)


func set_tone(tone: String) -> void:
	_cycle = []
	set_process(false)
	super(tone)


## Alternates round `tones` (lamp tones: ok, warn, bad, off), the whole round taking `seconds`.
func set_cycle(tones: Array, seconds: float = 1.5) -> void:
	if tones.size() <= 1:
		set_tone(str(tones[0]) if not tones.is_empty() else "off")
		return
	_cycle = tones
	_period = maxf(0.2, seconds)
	_clock = 0.0
	_shown = -1
	set_process(true)
	_step()


## The tones this lamp shows, one when steady.
func tones() -> Array:
	return _cycle.duplicate() if not _cycle.is_empty() else [colour]


## Godot turns processing on at ready for any script with _process, so a steady lamp turns it off again.
func _ready() -> void:
	set_process(not _cycle.is_empty())


func _process(delta: float) -> void:
	if _cycle.is_empty():
		set_process(false)
		return
	_clock = fposmod(_clock + delta, _period)
	_step()


func _step() -> void:
	var i := int(_clock / (_period / _cycle.size())) % _cycle.size()
	if i != _shown:
		_shown = i
		colour = colour_for(str(_cycle[i]))
		queue_redraw()
		_glow.queue_redraw()
