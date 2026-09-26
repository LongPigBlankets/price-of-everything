extends "res://scripts/bdp_v3_value_bar.gd"
## Tile view v3, the Goods tab: Building Detail's value bars (scripts/bdp_v3_value_bar.gd), the tile's revenue
## against its costs under the Revenue and costs key, with each bar's name printed at the caption standard
## (CAPTION_PX, Barlow Condensed SemiBold capitals) where the shared bars print it at their LABEL_SIZE.
## Everything else is the shared bars' own: the screens, the slices, the icons and the hover.

const CAPTION_PX := 15


func _draw() -> void:
	# The shared bars draw everything but the names, which are printed here at the caption size.
	var names: Array = []
	for row: Dictionary in _rows:
		names.append(str(row.label))
		row.label = ""
	super._draw()
	for i in _rows.size():
		_rows[i].label = names[i]
	var font: Font = Plate.FONT_SEMI
	var line_h := font.get_height(CAPTION_PX)
	for r in _rows.size():
		var lines := caption_lines(r)
		var y := _bar_rect(r).get_center().y - line_h * lines.size() * 0.5 + font.get_ascent(CAPTION_PX)
		for ln in lines:
			draw_string(font, Vector2(1.0, y + 1.0), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX, Color(0, 0, 0, 0.8))
			draw_string(font, Vector2(0.0, y), ln, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX, DS.PALETTE["TEXT"])
			y += line_h


## A bar's name as printed beside it, in capitals: its first word on one line, the rest on the next.
func caption_lines(row: int) -> PackedStringArray:
	var words := str(_rows[row].label).to_upper().split(" ")
	if words.size() <= 1:
		return words
	return PackedStringArray([words[0], " ".join(words.slice(1))])


## The widest line of the names, for checking they stand clear of the bars (LABEL_W, less the room the
## shared bars keep before their screens).
func widest_caption() -> float:
	var w := 0.0
	for r in _rows.size():
		for ln in caption_lines(r):
			w = maxf(w, Plate.FONT_SEMI.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, CAPTION_PX).x)
	return w
