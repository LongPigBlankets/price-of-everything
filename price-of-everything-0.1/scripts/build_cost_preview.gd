extends Node2D
## Build-mode hover preview (owner 2026-08-26): building cost / transport cost /
## land cost for the tile under the cursor, drawn directly over it — off-white
## text, sized to cover roughly a third of the tile, centred on it.
##
## World-space Node2D + _draw(), not a Control/Label: a Label child of a Node2D
## does not inherit the parent's 2D scale, so it would stay a fixed screen size
## regardless of zoom. Raw _draw() text does scale with it — the same reason
## build_mode_hex_overlay.gd (the viability mask this sits alongside) draws its
## polygon instead of using a ColorRect.

var tile_size := Vector2(540, 480)
var rows: Array[String] = []

const TEXT_COLOR := Color(0.91, 0.94, 0.97)   # DS.PALETTE.TEXT — off-white
const OUTLINE_COLOR := Color(0, 0, 0, 0.8)     # legibility over arbitrary terrain art


func _draw() -> void:
	if rows.is_empty():
		return
	var font := ThemeDB.fallback_font
	# "Cover roughly a third of the tile": the whole row block's height targets
	# tile_size.y / 3, so the font (and therefore legibility) scales with the
	# tile itself — and with it, camera zoom — the same way the hex mask does.
	var block_height: float = tile_size.y / 3.0
	var font_size: int = maxi(12, roundi(block_height / (float(rows.size()) * 1.35)))
	var line_height: float = float(font_size) * 1.35
	var outline_size: int = maxi(2, roundi(float(font_size) * 0.14))
	var top: float = -line_height * float(rows.size()) * 0.5
	for i in rows.size():
		var text: String = rows[i]
		var width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var pos := Vector2(-width * 0.5, top + line_height * float(i + 1) - line_height * 0.28)
		draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, outline_size, OUTLINE_COLOR)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, TEXT_COLOR)
