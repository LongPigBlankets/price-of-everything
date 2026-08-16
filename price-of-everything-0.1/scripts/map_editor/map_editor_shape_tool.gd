extends RefCounted
## The ground and fabric tools: farm/forest/park POLYGONS, and decorative mass STAMPS.
##
## EDITOR-ONLY (see the header of `map_editor.gd`).
##
## POLYGON — click each corner, Enter closes it. Capped at eight vertices (the owner's rule
## for authored ground): the cap is enforced at the point of clicking, with the status line
## saying so, rather than by rejecting the shape at save time when the work is already done.
##
## STAMP — press, drag to size, release. The drag sets the box the form is fitted into, so
## the same gesture produces a small terrace and a large courtyard; rotation comes from the
## drag's direction, which means a mass laid along a street faces the street without any
## extra step.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")
const MassFormShapes := preload("res://scripts/mass_form_shapes.gd")

## The vocabulary comes from `MassFormShapes.ALL_FORMS` rather than a copy: a hand-kept list
## drifts the day a form is added, and would offer names the constructors do not know.
## Ordered large-then-small-then-solid, which is how the addendum groups them.
static func forms() -> Array:
	return MassFormShapes.ALL_FORMS

## Anything smaller than this in either direction is a mis-drag, not a building.
const MIN_STAMP := 10.0
## Default box when a stamp is placed with a click rather than a drag.
const CLICK_STAMP := Vector2(46.0, 32.0)

var _points: Array = []
var _kind := "forests"
var _form := "solid"
var _drag_origin := Vector2.INF
var _drag_to := Vector2.INF


func kind() -> String:
	return _kind


func set_kind(value: String) -> void:
	if value in ["farms", "forests", "parks"]:
		_kind = value
		_points = []


func form() -> String:
	return _form


func set_form(value: String) -> void:
	if MassFormShapes.ALL_FORMS.has(value):
		_form = value


func cycle_form(step: int) -> String:
	var all: Array = MassFormShapes.ALL_FORMS
	var index := all.find(_form)
	_form = str(all[wrapi(index + step, 0, all.size())])
	return _form


# ── Polygons ────────────────────────────────────────────────────────────────────

func is_drawing() -> bool:
	return not _points.is_empty()


func polygon_points() -> Array:
	return _points


## Add a corner. Returns a message when the cap stops it, else "".
func add_point(world: Vector2) -> String:
	if _points.size() >= AuthoredMap.AREA_MAX_VERTICES:
		return "%s corners maximum — press Enter to close." % AuthoredMap.AREA_MAX_VERTICES
	_points.append([world.x, world.y])
	return ""


func undo_point() -> void:
	if not _points.is_empty():
		_points.remove_at(_points.size() - 1)


func abandon() -> void:
	_points = []
	_drag_origin = Vector2.INF
	_drag_to = Vector2.INF


## Close the polygon into a document record, or {} when it is not a shape.
func finish_polygon(settlement_key: String, next_id: int) -> Dictionary:
	if _points.size() < 3:
		abandon()
		return {}
	var prefix: String = str({"farms": "fa", "forests": "fo", "parks": "p"}.get(_kind, "x"))
	var record := {
		"id": "%s:%s:%d" % [prefix, settlement_key, next_id],
		"outline": _points.duplicate(true),
	}
	if _kind == "parks":
		record["kind"] = "green"
	abandon()
	return record


# ── Stamps ──────────────────────────────────────────────────────────────────────

func begin_stamp(world: Vector2) -> void:
	_drag_origin = world
	_drag_to = world


func drag_stamp(world: Vector2) -> void:
	if _drag_origin != Vector2.INF:
		_drag_to = world


func is_stamping() -> bool:
	return _drag_origin != Vector2.INF


## The stamp being dragged, as a document record — used for the live preview and for the
## commit, so what is previewed is exactly what lands.
func stamp_preview(id: String) -> Dictionary:
	if _drag_origin == Vector2.INF:
		return {}
	var span := _drag_to - _drag_origin
	var size := CLICK_STAMP
	var rotation := 0.0
	if span.length() >= MIN_STAMP:
		# The drag is the mass's long axis: its length is the frontage width and its
		# direction is the rotation, so a mass dragged along a street faces the street.
		size = Vector2(span.length(), maxf(span.length() * 0.62, MIN_STAMP))
		rotation = span.angle()
	return {
		"id": id,
		"form": _form,
		"pos": [_drag_origin.x + span.x * 0.5, _drag_origin.y + span.y * 0.5],
		"rot": rotation,
		"size": [size.x, size.y],
		"sacrificial": false,
	}


func finish_stamp(settlement_key: String, next_id: int) -> Dictionary:
	var record := stamp_preview("d:%s:%d" % [settlement_key, next_id])
	_drag_origin = Vector2.INF
	_drag_to = Vector2.INF
	if record.is_empty():
		return {}
	# A form that cannot be built at these proportions falls back inside MassFormShapes, so
	# the only failure left is a box too small to be anything.
	if AuthoredFabricPainter.mass_polygons(record).is_empty():
		return {}
	return record
