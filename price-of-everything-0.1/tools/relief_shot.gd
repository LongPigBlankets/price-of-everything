extends Node2D
## Wide view of the whole landmass to eyeball the elevation-band palette
## (flatland -> hill -> mountain -> snow peaks) against the reference relief map.
##   Godot --path . res://tools/relief_shot.tscn --quit-after 800
var _wm
var _terrain
var _frame := 0

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	for _i in 24:   # let the hill texture bake + roads settle
		await get_tree().process_frame
	_terrain = _wm.get_node("%TerrainLayer")
	var mn := Vector2(1e30, 1e30)
	var mx := Vector2(-1e30, -1e30)
	for coord in _terrain.tiles:
		var p: Vector2 = _terrain.map_to_local(_terrain.map_coord_for_tile_coord(coord))
		mn = mn.min(p)
		mx = mx.max(p)
	var center := (mn + mx) * 0.5
	var span := mx - mn
	var vp := get_viewport().get_visible_rect().size
	var zoom := minf(vp.x / (span.x + 1200.0), vp.y / (span.y + 1200.0))
	var cam := Camera2D.new()
	cam.position = center
	cam.zoom = Vector2(zoom, zoom)
	add_child(cam)
	cam.make_current()
	print("[AUTO] span=%s center=%s zoom=%.3f vp=%s" % [str(span), str(center), zoom, str(vp)])

func _process(_d: float) -> void:
	_frame += 1
	if _frame == 20:
		get_viewport().get_texture().get_image().save_png("res://relief_shot.png")
		print("SAVED relief_shot.png")
		get_tree().quit()
