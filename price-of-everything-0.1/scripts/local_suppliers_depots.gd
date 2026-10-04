extends Node2D
## Local Suppliers' depots on the map: a white level 1 warehouse, an NPC building, in a corner of every tile where
## the player has a building Local Suppliers serve (scripts/middleman_service.gd). It stands for where their
## inputs come from and their outputs go. It is drawn only: no building in BuildingState, no land, nothing saved.
##
## Hovering one shows what it is; clicking one opens the Local Suppliers panel (local_suppliers_panel.gd), which
## lists the buildings that send it their outputs or still take their inputs from it.
##
## A child of the terrain layer, so it shares its coordinates and sees a click before the tile does.

const Service := preload("res://scripts/middleman_service.gd")
const SuppliersPanel := preload("res://scripts/local_suppliers_panel.gd")

const HOVER_TITLE := "Local Suppliers"
const HOVER_BODY := "Acts as the source of inputs when 'Local Suppliers' is selected as a logistics provider and likewise the destination for outputs."
## The warehouse's footprint in world units, its roof plate's share of it, and how far out from the tile's centre
## towards a corner it stands (a share of the centre-to-corner distance).
const SIZE := Vector2(60.0, 38.0)
const ROOF := 0.74
const CORNER_REACH := 0.66
## The flat-top hex's corners from its centre (540 x 480 tiles), in the order they are tried: the lower corners
## first, so the depot sits at the front of the tile.
const CORNERS := [Vector2(-135.0, 240.0), Vector2(135.0, 240.0), Vector2(-270.0, 0.0), Vector2(270.0, 0.0),
	Vector2(-135.0, -240.0), Vector2(135.0, -240.0)]
const SHADOW_OFFSET := Vector2(2.2, 2.8)
const SHADOW := Color("4a4036", 0.74)
const INK := Color("40382f")
## The hover card's width on screen in px and its text sizes.
const CARD_W := 300.0
const CARD_TITLE_PX := 16
const CARD_BODY_PX := 13

var _terrain: Node
var _visuals: Node
## [{tile_id, rect}] in this node's coordinates.
var _depots: Array = []
var _hovered := -1
var _armed := -1
var _dirty := false


func setup(terrain: Node, building_visuals: Node) -> void:
	_terrain = terrain
	_visuals = building_visuals
	z_index = 59
	for sig: Signal in [BuildingState.building_added, BuildingState.building_removed, BuildingState.building_owner_changed]:
		sig.connect(_mark_dirty.unbind(1))
	for sig: Signal in [TransportState.transport_shipments_changed, TurnManager.turn_resolution_completed,
			SaveLoad.match_loaded, MatchState.state_reset]:
		sig.connect(_mark_dirty)
	if building_visuals != null and building_visuals.has_signal("footprints_changed"):
		building_visuals.connect("footprints_changed", _mark_dirty.unbind(2))
	_mark_dirty()


## Coalesced: any number of changes in a frame rebuild the depots once.
func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_rebuild.call_deferred()


## Every tile with a player building Local Suppliers serve gets one depot.
func _rebuild() -> void:
	if not _dirty or _terrain == null:
		return
	_dirty = false
	var tiles := {}
	for iid in BuildingState.buildings:
		var b: Dictionary = BuildingState.buildings[iid]
		if BuildingState.is_player_owned(b) and Service.enabled(str(iid)):
			tiles[str(b.get("tile_id", ""))] = true
	_depots.clear()
	for tile_id: String in tiles:
		var spot := _spot_for(tile_id)
		if spot != Vector2.INF:
			_depots.append({"tile_id": tile_id, "rect": Rect2(spot - SIZE * 0.5, SIZE)})
	_hovered = -1
	queue_redraw()


## The first corner of the tile whose spot no building stands on; the first corner when every one is taken.
func _spot_for(tile_id: String) -> Vector2:
	var coord: Vector2i = _terrain.call("id_to_coord", tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	var centre: Vector2 = _terrain.map_to_local(_terrain.call("map_coord_for_tile_coord", coord))
	var taken: Array = _visuals.call("footprint_rects_on_tile", coord) if _visuals != null and _visuals.has_method("footprint_rects_on_tile") else []
	for corner: Vector2 in CORNERS:
		var at := centre + corner * CORNER_REACH
		var rect := Rect2(at - SIZE * 0.5, SIZE).grow(4.0)
		if not taken.any(func(r: Rect2) -> bool: return r.intersects(rect)):
			return at
	return centre + (CORNERS[0] as Vector2) * CORNER_REACH


func _draw() -> void:
	var white: Color = MapStyle.block_top("npc")
	for i in _depots.size():
		var r: Rect2 = _depots[i].rect
		draw_rect(Rect2(r.position + SHADOW_OFFSET, r.size), SHADOW)
		draw_rect(r, white.darkened(0.06) if i == _hovered else white)
		draw_rect(r, INK, false, 1.0)
		# The roof: a plate inset over the walls with its ridge along the long side, and a loading door.
		var roof := Rect2(r.get_center() - r.size * ROOF * 0.5, r.size * ROOF)
		draw_rect(roof, white.lightened(0.25))
		draw_rect(roof, INK, false, 1.0)
		draw_line(Vector2(roof.position.x, roof.get_center().y), Vector2(roof.end.x, roof.get_center().y), INK, 1.0)
		var door := Rect2(Vector2(r.get_center().x - r.size.x * 0.12, r.end.y - 3.0), Vector2(r.size.x * 0.24, 3.0))
		draw_rect(door, INK)
	if _hovered >= 0 and _hovered < _depots.size():
		_draw_card((_depots[_hovered].rect as Rect2))


## The hover card above the depot, the same size on screen whatever the zoom: a navy plate with the name in the
## accent colour over what the depot does.
func _draw_card(over: Rect2) -> void:
	var zoom := maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	var font: Font = ThemeDB.fallback_font
	var pad := 10.0
	var body_h := font.get_multiline_string_size(HOVER_BODY, HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 2.0 * pad, CARD_BODY_PX).y
	var size := Vector2(CARD_W, pad * 2.0 + CARD_TITLE_PX * 1.4 + body_h)
	var anchor := Vector2(over.get_center().x, over.position.y) * zoom
	var origin := anchor - Vector2(size.x * 0.5, size.y + 8.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE / zoom)
	draw_rect(Rect2(origin, size), DS.PALETTE.BG_PANEL)
	draw_rect(Rect2(origin, size), DS.PALETTE.ACCENT, false, 1.5)
	draw_string(font, origin + Vector2(pad, pad + CARD_TITLE_PX), HOVER_TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, CARD_TITLE_PX, DS.PALETTE.ACCENT)
	draw_multiline_string(font, origin + Vector2(pad, pad + CARD_TITLE_PX * 1.4 + CARD_BODY_PX), HOVER_BODY,
		HORIZONTAL_ALIGNMENT_LEFT, CARD_W - 2.0 * pad, CARD_BODY_PX, -1, DS.PALETTE.TEXT)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _depot_under_mouse() -> int:
	var at := get_local_mouse_position()
	for i in _depots.size():
		if (_depots[i].rect as Rect2).grow(2.0).has_point(at):
			return i
	return -1


## The map's own click modes (building, surveying, picking a stockpile) keep the click.
func _map_busy() -> bool:
	return BuildMode.is_active or MapMode.current_mode == MapMode.Mode.SURVEYING \
		or bool(_terrain.get("_stockpile_destination_selection_active"))


func _unhandled_input(event: InputEvent) -> void:
	if _depots.is_empty() or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var now := _depot_under_mouse()
		if now != _hovered:
			_hovered = now
			queue_redraw()
		return
	if not (event is InputEventMouseButton) or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT or _map_busy():
		return
	var at := _depot_under_mouse()
	if event.pressed:
		_armed = at
		if at >= 0:
			get_viewport().set_input_as_handled()
		return
	if at >= 0 and at == _armed:
		get_viewport().set_input_as_handled()
		SuppliersPanel.open(get_tree().root.find_child("HUD", true, false), str(_depots[at].tile_id))
	_armed = -1
