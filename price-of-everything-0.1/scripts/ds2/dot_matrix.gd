extends Control
## DS2: text on a dot-matrix display, five by seven dots a character, lit white over faint unlit dots, as on
## the message boards of a factory floor. For figures that aren't money: money and unit costs keep the
## seven-segment LED (scripts/bdp_v3_led.gd). Set `text` for one colour, or `set_runs` for runs in their own
## colours (a status mark in amber or red before a white figure). With `framed` it sits in the mini screen's
## gunmetal bezel under its glass; unframed, it draws only its dots, for a strip that holds several.
## Letters print in capitals; characters the font lacks print as blanks.

const Nine := preload("res://scripts/bdp_v3_nine.gd")
const SCREEN: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen.png")
const GLASS: Texture2D = preload("res://assets/ui/bdp_v3/mini_screen_glass.png")
const CAPTURE_SCALE := 1.875
## From layout.json (mini_screen), in layout pixels: the render's shadow room, the bezel and the pane's corner.
const MARGIN := 8.0
const RIM := 7.0
const RADIUS := 5.0
const PANE := Color("#0b0d10")
const UNLIT_ALPHA := 0.09
const COLUMNS := 5
const ROWS := 7
## A narrow space, for a gap between a figure and its unit ("531 MW"): one dot column wide where a character
## cell is six, so the words keep together. Plain spaces stay a full cell, which the cards that line their
## columns up by padding with spaces rely on.
const THIN := "\u2009"
const THIN_COLUMNS := 1

## Five bits a row, top row first.
const FONT := {
	"0": [14, 17, 19, 21, 25, 17, 14], "1": [4, 12, 4, 4, 4, 4, 14], "2": [14, 17, 1, 2, 4, 8, 31],
	"3": [31, 2, 4, 2, 1, 17, 14], "4": [2, 6, 10, 18, 31, 2, 2], "5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14], "7": [31, 1, 2, 4, 8, 8, 8], "8": [14, 17, 17, 14, 17, 17, 14],
	"9": [14, 17, 17, 15, 1, 2, 12],
	"A": [14, 17, 17, 31, 17, 17, 17], "B": [30, 17, 17, 30, 17, 17, 30], "C": [14, 17, 16, 16, 16, 17, 14],
	"D": [28, 18, 17, 17, 17, 18, 28], "E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
	"G": [14, 17, 16, 23, 17, 17, 15], "H": [17, 17, 17, 31, 17, 17, 17], "I": [14, 4, 4, 4, 4, 4, 14],
	"J": [7, 2, 2, 2, 2, 18, 12], "K": [17, 18, 20, 24, 20, 18, 17], "L": [16, 16, 16, 16, 16, 16, 31],
	"M": [17, 27, 21, 21, 17, 17, 17], "N": [17, 17, 25, 21, 19, 17, 17], "O": [14, 17, 17, 17, 17, 17, 14],
	"P": [30, 17, 17, 30, 16, 16, 16], "Q": [14, 17, 17, 17, 21, 18, 13], "R": [30, 17, 17, 30, 20, 18, 17],
	"S": [15, 16, 16, 14, 1, 1, 30], "T": [31, 4, 4, 4, 4, 4, 4], "U": [17, 17, 17, 17, 17, 17, 14],
	"V": [17, 17, 17, 17, 17, 10, 4], "W": [17, 17, 17, 21, 21, 21, 10], "X": [17, 17, 10, 4, 10, 17, 17],
	"Y": [17, 17, 17, 10, 4, 4, 4], "Z": [31, 1, 2, 4, 8, 16, 31],
	" ": [0, 0, 0, 0, 0, 0, 0], "%": [24, 25, 2, 4, 8, 19, 3], "+": [0, 4, 4, 31, 4, 4, 0],
	"-": [0, 0, 0, 31, 0, 0, 0], ".": [0, 0, 0, 0, 0, 12, 12], ",": [0, 0, 0, 0, 12, 4, 8],
	"/": [0, 1, 2, 4, 8, 16, 0], ":": [0, 12, 12, 0, 12, 12, 0], "£": [6, 9, 8, 28, 8, 8, 31],
	"(": [2, 4, 8, 8, 8, 4, 2], ")": [8, 4, 2, 2, 2, 4, 8], ">": [8, 4, 2, 1, 2, 4, 8],
	"→": [0, 4, 2, 31, 2, 4, 0], "!": [4, 4, 4, 4, 4, 0, 4], "?": [14, 17, 1, 2, 4, 0, 4],
	"'": [12, 4, 8, 0, 0, 0, 0], "●": [0, 14, 31, 31, 31, 14, 0],
}

## Centre distance between dots, in logical pixels; each character is five dots wide and one dot apart.
var pitch := 2.2:
	set(v):
		pitch = maxf(v, 1.0)
		_resize()
var framed := true:
	set(v):
		framed = v
		_resize()
var align := HORIZONTAL_ALIGNMENT_CENTER:
	set(v):
		align = v
		queue_redraw()
var colour := Color.WHITE:
	set(v):
		colour = v
		if _runs.size() <= 1:
			_runs = [{"text": text, "colour": v}]
		queue_redraw()
var text := "":
	set(v):
		text = v
		_runs = [{"text": v, "colour": colour}]
		_resize()
var _runs: Array = []


func _init() -> void:
	name = "DotMatrix"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_resize()


## Text in runs, each [{text, colour}], printed one after another.
func set_runs(runs: Array) -> void:
	_runs = runs
	var joined := ""
	for r: Dictionary in runs:
		joined += str(r.text)
	text = joined
	_runs = runs
	_resize()


## Width of `count` characters' dots, in logical pixels, at pitch `p`.
static func text_width(count: int, p: float) -> float:
	return maxf(0.0, count * (COLUMNS + 1) * p - p)


## Width of `t`'s dots at pitch `p`, a narrow space (THIN) counting its own columns.
static func string_width(t: String, p: float) -> float:
	var thin := t.count(THIN)
	return maxf(0.0, text_width(t.length() - thin, p) + thin * (THIN_COLUMNS + 1) * p - (p if thin == t.length() else 0.0))


func _padding() -> Vector2:
	return Vector2(4.0, 3.0) + (Vector2.ONE * RIM / CAPTURE_SCALE if framed else Vector2.ZERO)


func _resize() -> void:
	custom_minimum_size = Vector2(string_width(text, pitch), ROWS * pitch) + 2.0 * _padding()
	queue_redraw()


func _draw() -> void:
	var box := Rect2(Vector2.ZERO, size)
	var corner := (MARGIN + RIM + RADIUS + 2.0) * 2.0 / CAPTURE_SCALE
	if framed:
		Nine.paint(self, SCREEN, box.grow(MARGIN / CAPTURE_SCALE), corner)
		draw_rect(box.grow(-RIM / CAPTURE_SCALE), PANE)
	var width := string_width(text, pitch)
	var x0 := (size.x - width) * 0.5
	if align == HORIZONTAL_ALIGNMENT_LEFT:
		x0 = _padding().x
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x0 = size.x - _padding().x - width
	var y0 := (size.y - ROWS * pitch) * 0.5
	var r := pitch * 0.44
	var cx := x0 + pitch * 0.5
	for run: Dictionary in _runs:
		var lit: Color = run.colour
		var glow := Color(lit, 0.3)
		var unlit := Color(1, 1, 1, UNLIT_ALPHA)
		for ch in str(run.text).to_upper():
			var rows: Array = FONT.get(ch, FONT[" "])
			var cols := THIN_COLUMNS if ch == THIN else COLUMNS
			for row in ROWS:
				var bits := int(rows[row]) if ch != THIN else 0
				for col in cols:
					var p := Vector2(cx + col * pitch, y0 + row * pitch + pitch * 0.5)
					if bits & (1 << (COLUMNS - 1 - col)):
						draw_circle(p, r * 1.7, glow)
						draw_circle(p, r, lit)
					else:
						draw_circle(p, r * 0.8, unlit)
			cx += (cols + 1) * pitch
	if framed:
		Nine.paint(self, GLASS, box.grow(MARGIN / CAPTURE_SCALE), corner)
