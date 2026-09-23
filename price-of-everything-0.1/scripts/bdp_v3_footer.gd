extends "res://scripts/bdp_v3_plate.gd"
## Building Detail v3: Sell building and Demolish as guarded buttons on a steel plate the width of the
## control block. Each is a glowing cap (amber with coins, red with a bulldozer) under a hinged clear
## cover, with its name in white raised letters beside it. The first click lifts the cover; the
## second presses the button and opens the supply-chain review, as in v2. An untouched lifted cover
## drops again after OPEN_SECONDS.

const FRAME := Vector2(863, 204)
const KEYS := {
	"sell": Rect2(62, 68, 116, 116),
	"demolish": Rect2(493.5, 68, 116, 116),
}
const OPEN_SECONDS := 4.0

var _open := {}   # key -> seconds before its cover drops


func _init() -> void:
	super()
	name = "BdpV3Footer"
	set_frame(FRAME)
	set_layers([tex("footer_plate")], tex("footer_glow"), [])
	for key in KEYS:
		set_key(key, KEYS[key], KEYS[key], tex("guard_" + key), tex("guard_%s_pressed" % key), [], false, true,
			"%s: lift the cover, then press" % ("Sell building" if key == "sell" else "Demolish"))
	set_process(false)


func is_open(key: String) -> bool:
	return _open.has(key)


func lift(key: String) -> void:
	_open[key] = OPEN_SECONDS
	set_process(true)
	_redraw()


func drop(key: String) -> void:
	_open.erase(key)
	set_process(not _open.is_empty())
	_redraw()


func _process(delta: float) -> void:
	for key in _open.keys():
		_open[key] = float(_open[key]) - delta
		if float(_open[key]) <= 0.0 and key != _held:
			drop(key)


func _draw_front() -> void:
	super._draw_front()
	for key in KEYS:
		_front_layer.draw_texture_rect(tex("guard_%s_cover_open" % key if is_open(key) else "guard_%s_cover" % key), _frame_rect(), false)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		var at := _key_at(mb.position)
		if mb.pressed:
			if at != "" and is_open(at):
				_held = at
				_redraw()
			if at != "":
				accept_event()
		else:
			if _held != "":
				var pressed_key := _held
				_held = ""
				drop(pressed_key)
				accept_event()
				if at == pressed_key:
					key_pressed.emit(pressed_key)
			elif at != "":
				lift(at)
				accept_event()
		return
	super._gui_input(event)
