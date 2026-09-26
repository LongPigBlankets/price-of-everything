extends Control
## DS2 (the tile view's Transport tab): a building's emblem (Building Detail's building emblem, the building's icon raised in
## polished metal, res://assets/ui/bdp_v3/bld_emblem_<id>.png and its shadow) over its pilot lamp, as the
## diagnostics' indicator shows a check. A link not yet built has no lamp: there is nothing to judge, and
## a key latched with its own lamp says when one is being built.
##
## Emblems are sized by their drawn art, not their canvas (DS2): each is fitted to one cap height, CAP_H,
## and no longer than BOX_W, which is what holds the long flat pipe emblems (their art is three times as
## long as it is tall, so at the cap height they would run 100 px). OPTICAL tables a factor for the ones
## that still read light, on both limits, so a pipe may reach a few px past the box into the gaps beside
## it. The art stands on the midline of the row it heads (`row_h`, the height of the keys beside it), so
## it lines up with the link's name whatever the module holds below, and every emblem takes the same box.
## The lamp stands under the art, level with the first line it judges when the tab says where that is (a
## link's first meter), so the lamps of every module stand at the same place.

const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const EMBLEM := "res://assets/ui/bdp_v3/bld_emblem_%s.png"
const BOX_W := 66.0
const CAP_H := 36.0
const LAMP_GAP := 4.0
const LAMP_SCALE := 0.62
## Building id -> a factor on the cap height and the box's length. Cables' pylons and the rail's sleepers
## are mostly air (under half their outline is metal, against two thirds for roads), so they stand a little
## taller to weigh as much as the solid emblems; the plain pipe, the thinnest line of the set, runs a
## little longer.
const OPTICAL := {"b_006": 1.08, "b_019": 1.1, "b_017": 1.06}
## A hovered emblem is drawn this much brighter, as the indicator's is.
const HOT_MODULATE := Color(1.2, 1.2, 1.2)

var icon: Texture2D
var shadow: Texture2D
## The art's height and the longest it may run, CAP_H and BOX_W unless a card asks for more (fit_to).
var cap_h := CAP_H
var box_w := BOX_W
var factor := 1.0
var row_h := CAP_H
var lit := true
var lamp_mid := -1.0
var hot := false:
	set(v):
		hot = v
		queue_redraw()
var lamp: Control


func _init() -> void:
	name = "TransportEmblem"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	lamp = Lamp.new()
	lamp.lamp_scale = LAMP_SCALE
	add_child(lamp)
	_fit_box()
	resized.connect(_place_lamp)


## The link's building (its emblem), its lamp's tone (ok, warn, bad or off), the height of the row the
## emblem heads, whether it has a lamp at all, and the height its lamp's middle stands at (below the art;
## just under it when not given).
func set_link(building_id: String, tone: String, head_h := CAP_H, with_lamp := true, mid := -1.0) -> void:
	var path := EMBLEM % building_id
	icon = load(path) if building_id != "" and ResourceLoader.exists(path) else null
	var shadow_path := path.replace(".png", "_shadow.png")
	shadow = load(shadow_path) if icon != null and ResourceLoader.exists(shadow_path) else null
	factor = float(OPTICAL.get(building_id, 1.0))
	row_h = maxf(head_h, cap_h)
	lit = with_lamp
	lamp_mid = mid
	lamp.visible = with_lamp
	lamp.set_tone(tone)
	_fit_box()
	queue_redraw()


## Fits the art to `cap` px tall and no longer than `box` (a card that gives its emblem its full height).
func fit_to(cap: float, box: float) -> void:
	cap_h = cap
	box_w = box
	row_h = maxf(row_h, cap)
	_fit_box()
	queue_redraw()


func _fit_box() -> void:
	var side: Vector2 = lamp.custom_minimum_size
	custom_minimum_size = Vector2(box_w, _lamp_top() + side.y if lit else row_h)
	_place_lamp()


func _lamp_top() -> float:
	var side: Vector2 = lamp.custom_minimum_size
	return maxf(row_h + LAMP_GAP, lamp_mid - side.y * 0.5)


func _place_lamp() -> void:
	var side: Vector2 = lamp.custom_minimum_size
	lamp.size = side
	lamp.position = Vector2((size.x - side.x) * 0.5, _lamp_top())


## Where the whole render is drawn so that its art stands CAP_H tall (or BOX_W long) on the row's
## midline. The shadow is drawn to the same rect, so it falls where it was rendered.
func art_dest() -> Rect2:
	var art := Indicator.art_rect(icon)
	var k := cap_h * factor / maxf(art.size.y, 1.0)
	if art.size.x * k > box_w * factor:
		k = box_w * factor / art.size.x
	var art_size := art.size * k
	var at := Vector2((size.x - art_size.x) * 0.5, (row_h - art_size.y) * 0.5)
	return Rect2(at - art.position * k, icon.get_size() * k)


func _draw() -> void:
	if icon == null:
		return
	var rect := art_dest()
	if shadow != null:
		draw_texture_rect(shadow, rect, false)
	draw_texture_rect(icon, rect, false, HOT_MODULATE if hot else Color.WHITE)
