extends Control
## One picker tile: a shape on an off-white plate, 50x50.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## The tile DRAWS THE REAL THING — a mass form comes from `MassFormShapes`, a wood from the
## same tree shapes the map uses — scaled into the plate. A hand-drawn icon set would be a
## second vocabulary to keep in step, and the first time a form changed the palette would
## start lying about what it stamps.
##
## No labels: seventeen names in a narrow column is a wall of text, and the shapes are the
## thing being chosen. Identity comes from the silhouette, selection from a heavy outline.

signal picked(key: String)

const MassFormShapes := preload("res://scripts/mass_form_shapes.gd")
const TreeShapesRef := preload("res://scripts/tree_shapes.gd")
const AuthoredSpecialShapes := preload("res://scripts/authored_special_shapes.gd")

const TILE := 50.0
## Inset from the plate edge to the shape's bounding box, so nothing touches the corner
## radius and every tile reads as the same size regardless of its aspect.
const PAD := 8.0

const PLATE := Color(0.94, 0.92, 0.86)
const PLATE_HOVER := Color(0.99, 0.98, 0.94)
const SHAPE := Color(0.42, 0.42, 0.44)
const SHAPE_HOVER := Color(0.56, 0.57, 0.60)
const OUTLINE := Color(0.60, 0.95, 0.75)
const OUTLINE_WIDTH := 3.0
const CORNER := 6

## "form" draws a mass from the vocabulary; "area" draws farmland, woodland or a park.
var kind := "form"
var key := "solid"
var selected := false

var _hovered := false
var _plate: StyleBoxFlat


func _ready() -> void:
	custom_minimum_size = Vector2(TILE, TILE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_plate = StyleBoxFlat.new()
	_plate.set_corner_radius_all(CORNER)
	mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		picked.emit(key)
		accept_event()


func _draw() -> void:
	_plate.bg_color = PLATE_HOVER if _hovered else PLATE
	draw_style_box(_plate, Rect2(Vector2.ZERO, size))
	var ink := SHAPE_HOVER if _hovered else SHAPE
	match kind:
		"form":
			_draw_form(ink)
		"special":
			_draw_special(ink)
		_:
			_draw_area(ink)
	if selected:
		# Drawn inside the plate so a selected tile does not overlap its neighbours.
		var inset := OUTLINE_WIDTH * 0.5
		var box := StyleBoxFlat.new()
		box.bg_color = Color(0, 0, 0, 0)
		box.set_corner_radius_all(CORNER)
		box.border_color = OUTLINE
		box.set_border_width_all(int(OUTLINE_WIDTH))
		draw_style_box(box, Rect2(Vector2(inset, inset), size - Vector2(inset, inset) * 2.0))


## The mass form itself, built at a nominal size and then fitted to the plate. Fitting after
## construction rather than building at plate size keeps the proportions the constructors
## actually produce — several forms have minimum limb widths that a 50-unit parcel would
## trip, and the fallback ladder would quietly show a different shape than the one named.
func _draw_form(ink: Color) -> void:
	var parcel := PackedVector2Array([Vector2(0, 0), Vector2(120, 0), Vector2(120, 96),
		Vector2(0, 96)])
	var built: Dictionary = MassFormShapes.build_form(key, parcel, 0, "palette|%s" % key)
	var polys: Array = built.get("polys", [])
	if polys.is_empty():
		return
	var bounds := Rect2()
	var started := false
	for poly_value in polys:
		for point in (poly_value as PackedVector2Array):
			if not started:
				bounds = Rect2(point, Vector2.ZERO)
				started = true
			else:
				bounds = bounds.expand(point)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var span := TILE - PAD * 2.0
	var scale := minf(span / bounds.size.x, span / bounds.size.y)
	var offset := Vector2(TILE, TILE) * 0.5 - bounds.get_center() * scale
	for poly_value in polys:
		var screen := PackedVector2Array()
		for point in (poly_value as PackedVector2Array):
			screen.append(point * scale + offset)
		if screen.size() >= 3:
			draw_colored_polygon(screen, ink)


## A parametric primitive at its default proportions — the shape you get by clicking, so the
## tile is a promise rather than a decoration.
func _draw_special(ink: Color) -> void:
	var outline := AuthoredSpecialShapes.build(key, AuthoredSpecialShapes.defaults_for(key))
	if outline.size() < 3:
		return
	var bounds := Rect2(outline[0], Vector2.ZERO)
	for point in outline:
		bounds = bounds.expand(point)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return
	var span := TILE - PAD * 2.0
	var scale := minf(span / bounds.size.x, span / bounds.size.y)
	var offset := Vector2(TILE, TILE) * 0.5 - bounds.get_center() * scale
	var screen := PackedVector2Array()
	for point in outline:
		screen.append(point * scale + offset)
	draw_colored_polygon(screen, ink)


## Farmland, woodland and parks get a miniature of what they actually draw: strips for a
## field, canopies for a wood, a plain green for a park.
func _draw_area(ink: Color) -> void:
	var box := Rect2(Vector2(PAD, PAD), Vector2(TILE - PAD * 2.0, TILE - PAD * 2.0))
	match key:
		"farms":
			draw_rect(box, ink.darkened(0.25), true)
			var strips := 4
			for i in strips:
				var width := box.size.x / float(strips)
				if i % 2 == 0:
					draw_rect(Rect2(box.position + Vector2(width * i, 0.0),
						Vector2(width * 0.72, box.size.y)), ink.lightened(0.28), true)
		"forests":
			for spot_value in [Vector2(0.28, 0.62), Vector2(0.52, 0.34), Vector2(0.74, 0.66),
					Vector2(0.44, 0.78)]:
				var spot: Vector2 = spot_value
				var centre := box.position + box.size * spot
				draw_circle(centre, box.size.x * 0.19, ink.darkened(0.18))
				draw_circle(centre - Vector2(0.0, box.size.x * 0.06),
					box.size.x * 0.15, ink.lightened(0.10))
		"plazas":
			# Paving: a plain slab with a seam, distinct from the park's inset green.
			draw_rect(box, ink.lightened(0.34), true)
			draw_line(box.position + Vector2(0.0, box.size.y * 0.5),
				box.position + Vector2(box.size.x, box.size.y * 0.5), ink.darkened(0.1), 1.5)
			draw_line(box.position + Vector2(box.size.x * 0.5, 0.0),
				box.position + Vector2(box.size.x * 0.5, box.size.y), ink.darkened(0.1), 1.5)
		_:
			# A park: an inset green with a rounded feel, distinct from the field's strips.
			draw_rect(box, ink.lightened(0.18), true)
			draw_rect(box.grow(-4.0), ink.darkened(0.10), true)
