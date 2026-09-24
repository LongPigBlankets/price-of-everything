extends Control
## Building Detail v3: the header's emblem, the building's icon raised in polished metal at the top left,
## two title lines tall (res://assets/ui/bdp_v3/bld_emblem_<building id>.png and its shadow, rendered by
## tools/button_mockup/cluster.html?export&only=emblem). The render is scaled so its art, not its frame,
## fills the box, standing on its foot, as the diagnostics' icons are.

const Indicator := preload("res://scripts/bdp_v3_indicator.gd")
const Title := preload("res://scripts/bdp_v3_title.gd")
const PATH := "res://assets/ui/bdp_v3/bld_emblem_%s.png"

var face: Texture2D
var shadow: Texture2D


## The emblem's side: the title's height set in two lines.
static func side() -> float:
	return Title.two_lines_height()


static func has_emblem(building_id: String) -> bool:
	return building_id != "" and ResourceLoader.exists(PATH % building_id)


func _init() -> void:
	name = "BdpV3Emblem"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	custom_minimum_size = Vector2(side(), side())


## Shows this building's emblem; false (and nothing drawn) when it has none.
func set_building(building_id: String) -> bool:
	face = null
	shadow = null
	if has_emblem(building_id):
		face = load(PATH % building_id)
		shadow = load((PATH % building_id).replace(".png", "_shadow.png"))
	queue_redraw()
	return face != null


func _draw() -> void:
	if face == null:
		return
	var art := Indicator.art_rect(face)
	var box := side()
	var k := box / maxf(art.size.x, art.size.y)
	var art_size := art.size * k
	var at := Vector2((size.x - art_size.x) * 0.5, box - art_size.y)
	var rect := Rect2(at - art.position * k, face.get_size() * k)
	if shadow != null:
		draw_texture_rect(shadow, rect, false)
	draw_texture_rect(face, rect, false)
