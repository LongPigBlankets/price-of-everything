extends Control
## Supply chain board — the view.
##
## Draws the model (empire_board_model.gd) as an isometric plate over dark space: only the
## tiles the company stands on, stores in or routes through, each at the map's own tile size
## and place. The board's ground is one surface over all of them (empire_board_ground.gd): each
## tile at its own height, stepping up or down to a neighbour of another height along the map's own
## contours, rising where the map's bands stand well above it, and with its rivers in valleys.
## Everything stands on that one ground (_height_at), and its colours are the map's own bands,
## water and shores laid over it. On the tiles stand the company's buildings, each tile's warehouse
## and any port it trades through. The lines between them are the transport routes, drawn as
## the road, rail, pipe or cable that carries them, with goods travelling along.
##
## BOARD SPACE. Everything static is built once in board space, the isometric projection of
## the map at zoom 1 (see iso()). The projection is linear, so pan and zoom are one canvas
## transform and nothing is rebuilt while the player moves the view.
##
## Presentation only: it reads the sim and never changes it.

signal building_picked(iid: String)
## Local Suppliers' depot was clicked: the view opens their chart.
signal suppliers_picked

## The last three parts of the key art plate's look, each switchable so they can be judged apart.
static var plate_lamps := true       # street lamps; and where the air is dirty, their light, pools before the works, bloom
static var plate_sea := true         # open water pale toward the sun and deep away from it
static var plate_town := true        # housing on free slots and cars on the streets
## What the player has chosen to see, set from the visibility key's tickboxes. Kept for the session.
static var show := {"decor": true, "trees": true, "roads": true, "rails": true, "pipes": true, "reinf_pipes": true,
	"cables": true, "goods": true, "pollution": true, "names": true}

const Model := preload("res://scripts/empire_board_model.gd")
const Pipes := preload("res://scripts/empire_board_pipes.gd")
const Atlas := preload("res://scripts/empire_board_atlas.gd")
const Streets := preload("res://scripts/empire_board_streets.gd")
const Rails := preload("res://scripts/empire_board_rails.gd")
const Visibility := preload("res://scripts/empire_board_visibility.gd")
const EmpireFx := preload("res://scripts/empire_fx.gd")
const Relief := preload("res://scripts/empire_board_relief.gd")
const Ground := preload("res://scripts/empire_board_ground.gd")

const ISO_X := 0.70710678
const ISO_Y := 0.40824829          # 0.7071 * tan(30 deg): a true isometric squash
const ISO_RISE := 0.81649658

## How finely the ground under a way is read, and how closely the reading is kept.
const PROFILE_STEP := 3.0
const PROFILE_KEEP := 0.25
## A river that falls this much on its way down a slope runs white.
const RAPIDS_DROP := 10.0
## A slope is shaded fully from this steepness up: half a lowland step over a slope's width, so even
## the gentlest step is shaded fully across its width and its crest and foot stay sharp.
const SLOPE_SHADE_FULL := 4.5 / 34.0
## A junction piece lies flat where the ground round it is no more off level than this.
const JUNCTION_TILT := 1.5
## A building whose footprint's ground differs by more than this stands on a plinth.
const PLINTH_MIN := 0.75
## A bridge: how far beyond its valley's reach its banks are looked for, how wide its deck is, the
## least its deck stands over the river (a street along the valley's floor has no bridge to raise),
## and how deep the deck's edge hangs.
const BRIDGE_LOOK := 8.0
const BRIDGE_HALF := 12.0
const BRIDGE_MIN_RISE := 4.0
const BRIDGE_FASCIA := 3.0
const _PIER := Color("5a6273")

## How much of its frame's width a level 3 sprite fills (sprite_export pads 6 px a side).
const SPRITE_FILL := 0.985

const _NAVY := Color(0.015, 0.058, 0.105)
const _CREAM := Color(0.995, 0.931, 0.763)
const _WALL := Color("5d4a37")
const _WALL_SEA := Color("0f2a5c")
const _PAD := Color("cdc4aa")
const _PAD_EDGE := Color("8c8470")
const _BOX_ROOF := Color("efe6ce")
const _BOX_SOUTH := Color("b9ae93")
const _BOX_EAST := Color("d6ccb1")
const _ASPHALT := Color("5c5c59")
const _KERB := Color("b9b4a6")
const _DASH := Color("f4f1e6")
const _BALLAST := Color("756a5c")
const _TIE := Color("3d2f22")
const _RAIL := Color("c9ccd0")
const _GIRDER := Color("4a566e")
const _GIRDER_DECK := Color("6b6558")
const _BUFFER := Color("b5402c")
const _RAIL_INK := 1.0               # the inked edge of the ballast
const _RAIL_GAUGE := 5.2
const _RAIL_TIE := 8.4
const _RAIL_TIE_GAP := 4.6
const _RAIL_TIE_W := 1.5
const _RAIL_W := 0.8
const _RAIL_CURVE := 26.0            # how far from a corner the track starts to turn
const _RAIL_CURVE_STEPS := 7
const _RAIL_SPAN := 20.0             # a girder deck reaches this far either side of the water
const _PIPE := Color("b5763e")
const _PIPE_REINF := Color("8f979e")
const _PIPE_EDGE := Color("3a2a1c")
const _TRACK := Color("7a6444")
const _CABLE := Color("e8c66a")
const _CABLE_DARK := Color("1b2030")
const _CABLE_STRIPE := Color("d9c27a")

const _CONCRETE := Color("a7a294")
const _ROAD_HALF := 8.0
const _DRIVE_HALF := 4.0
const _JUNCTION_GROW := 1.12         # a junction patch against the widest road into it
const _ROAD_OVERLAP := 6.0           # a straight runs this far under a junction piece
const _UNPAVED := Color(0.86, 0.74, 0.56)    # a way over bare ground: the same pieces, in earth
const _SIGN_MIN_RUN := 40.0          # a stretch shorter than this carries no sign of its own
const _SIGN_OFFSET := 15.0
const _SIGN_POST := 15.0
const _SIGN_PLATE := 13.0
const _SIGN_MIN_PX := 15.0
const _CABLE_SAG := 0.06
const _CABLE_STEPS := 10
const _LIVE_CREEP_SECS := 4.0

## The slab the tiles are cut from goes this far down below the lowest ground, showing strata.
const SLAB_DEPTH := 150.0
const _STRATA_TOP := 100.0           # the height the strata texture's top edge stands at
const _TURF := 4.0                   # the dark lip of turf over a cut-away wall
const _INK := Color("2f3b59")
const _INK_W := 1.5
const _SAND := Color("e6d6a6")
const _STRAND := 15.0                # how wide the sand lies along a shore
const _SHALLOWS_OUT := 13.0          # how far out the pale shallows are centred
const _SHALLOWS_W := 30.0
const _FOAM := Color(0.97, 0.97, 0.93, 0.85)
const _BANK := Color("c9c08f")       # a river's bank: pale, between the grass and the sand
const _MOUTH := 4.0                  # how far past the shoreline a river runs on into the sea, over the foam
const _MOUTH_SHORE_REACH := 8.0      # a shore edge this near where a river leaves the land is the one it crosses
## A river's estuary: how far up from the shore it starts to widen (in river widths), how wide it is at the
## shore and where it fans out into the shallows (in river widths), how far it runs on into the sea, and how
## many steps each stretch is drawn in.
const _ESTUARY_UP := 3.0
const _ESTUARY_SHORE_W := 1.6
const _ESTUARY_SEA_W := 4.2
const _ESTUARY_OUT := 22.0
const _ESTUARY_STEPS := 10
## How a river meets the sea: its last stretch (in river widths) bends to cross the shoreline square on, by
## at most this much, so its mouth opens straight onto the water and not along the beach or into a corner.
const _MOUTH_AIM_STRETCH := 3.0
const _MOUTH_AIM_MAX := deg_to_rad(30.0)
const _INK_SOFT := Color(0.18, 0.23, 0.35, 0.55)
## The light of the key art's plate, a low golden sun and a cool shade away from it. The sun
## stands in the SOUTH-EAST: on the board that is straight toward the viewer, so the near side
## is the gold one and shadows fall away up the screen, to the north-west.
const _SUN_SCREEN := Vector2(0.0, 1.0)
const _SHADOW := Color(0.04, 0.06, 0.14, 0.12)
const _SHADOW_REACH := 0.38           # a building's shadow, as a share of its footprint
const _SHADOW_NW := Vector2(-0.70710678, -0.70710678)
const _GOLD_LIGHT := Color(1.0, 0.80, 0.44)
const _COOL_SHADE := Color(0.05, 0.08, 0.22)
const _LIGHT_GOLD_ALPHA := 0.26
const _LIGHT_SHADE_ALPHA := 0.10
## What stands in the light is left almost as it is: the grade over the whole tile does the colouring.
const _TINT_SUN := Color(1.0, 1.0, 0.98)
const _TINT_SHADE := Color(0.90, 0.92, 0.96)
## The grade multiplied over a baked tile: amber in the sun, blue in the shade.
const _GRADE_SUN := Color(1.0, 0.92, 0.72)
const _GRADE_SHADE := Color(0.66, 0.74, 1.0)
const _WARM_HUE := 0.17              # yellow-olive; greens beyond it are pulled back toward it
const _WARM_PULL := 0.55
const _GLINTS_PER_TILE := 16
const _GLINT := Color(1.0, 0.96, 0.82)
const _LAMP_GAP := 62.0              # between street lamps
const _LAMP_HEIGHT := 13.0
const _LAMP_LIGHT := Color(1.0, 0.70, 0.34)
const _LAMP_HEAD := Color(1.0, 0.93, 0.72)
const _CAR_GAP := 150.0              # a stretch carries one car each way for every this much road
const _CAR_SPEED := 16.0             # map units a second
const _SEA_PALE := Color(1.0, 0.93, 0.78)
const _SEA_DEEP := Color(0.03, 0.06, 0.22)
const _SEA_PALE_ALPHA := 0.26
const _SEA_DEEP_ALPHA := 0.36
const _SOOT := Color(0.072, 0.07, 0.072)
const _WINDOW_DIR := "res://assets/fx/windows/"
const _WINDOW_LIGHT := Color(1.0, 0.90, 0.66)     # amber-white
const _FOG_PER_WORKS := 26
const _FOG_ARMS := 4
const _FOG_WIND := Vector2(-0.4, -1.0)   # in plan: the mist leans north, the way the smoke does
const _FOG_WORKS_REACH := 142.0      # how far a dirty works' mist spreads round it
const _FOG_WORKS_ALPHA := 0.28
const _FOG_PER_TILE := 130           # wisps tried for a tile's pall and its spill
const _FOG_TILE_ALPHA := 0.34
const _SMOG_INSET := 0.10            # the pall is full to this share of a tile inside its edge
const _SMOG_SPILL := 0.375           # and gone this share of a tile into a clean neighbour
const _TILE_SPAN := 480.0
const _PUFFS := 7
const _PUFF_SECS := 7.0
const _PUFF_RISE := 11.0             # how far a puff climbs in its life, in chimney radii
const _TREES_PER_TILE := 26
const _TREE_HEIGHT := {"large": 30.0, "small": 22.0, "fir": 32.0}
const _ROADSIDE_GAP := 34.0
const _ROADSIDE_KEEP := 0.55
const _TREE_DIR := "res://assets/iso/trees/"
const _MINE_DIR := "res://assets/iso/mine/"
const _MINE_EARTH := Color("5a4c3d")
const _MINE_EARTH_EDGE := Color("77684f")

## A tile's two layers (_draw_tile), named by these after the tile's id; and how far every things
## layer's depth stands over every ground layer's, more than the whole board's depth.
const _GROUND := "#ground"
const _THINGS := "#things"
const _THINGS_Z := 1.0e7

## The zooms a tile's picture is baked at. The board zooms smoothly; a tile is drawn from the
## bake at or just above the present zoom, so it is only ever reduced, never enlarged, and by
## less than half. The change from one bake to the next happens as the zoom passes each of these.
const BAKE_ZOOMS := [0.3, 0.6, 1.2]
const _ZOOM_MIN := 0.1
const _ZOOM_MAX := 1.5
const _ZOOM_STEP := 1.12
## Bakes are let go, least recently drawn first, once they hold more than this many bytes.
const _BAKE_BUDGET := 280 * 1024 * 1024
## A tile is baked at this many times its shown size and reduced, so small things are drawn
## from more than one sample each.
const _BAKE_OVERSAMPLE := 2.0
const _TILE_HEADROOM := 150.0        # board units kept above a tile's top for what stands on it
const _TILE_MARGIN := 34.0
const _BAKE_GRID := 5.0              # board units a tile's picture is snapped to
const _EDGE_PARTS := 18              # stretches a cliff edge is cut into, to tell land from water
const _WATER_DEPTH := 22.0           # how deep the sea shows in the cut-away
const _FIT_PAD := 90.0
const _TOKEN_SPEED := 80.0          # board units per second
const _TOKEN_SPACING := 1100.0      # between tokens of one flow
const _PULSE_SPACING := 120.0       # between slugs in a pipe and pulses on a cable
const _DRAG_SLOP := 5.0

## The sun in the south-east, in plan: the faces toward the camera are the lit ones.
const _SUN := Vector2(0.70710678, 0.70710678)

static var _hill_polys: Array = []           # [{b, p, box}] parsed once
static var _sea_polys: Array = []
static var _lake_polys: Array = []
static var _relief_cache: Dictionary = {}    # tile_id -> {sea: [], land: [], lakes: []}
## Each tile's ground meshes, kept from one opening of the board to the next while nothing round
## them changes: "tile|what the meshes depend on" -> {walls, ground}; and its light, -> ArrayMesh.
static var _ground_meshes: Dictionary = {}
static var _light_meshes: Dictionary = {}
const _GROUND_MESHES_KEPT := 240
## How far a tile's ground runs on under a neighbour drawn over it.
const _SKIRT := 2.0

var _model: Dictionary = {}
## A build under way (_build): which one, and whether it hands frames back as it goes.
var _build_gen := 0
var _building := false
var _paced := false
var _slice_from := 0
const _PACE_MS := 6
## Bake the layers in view at the board's zoom while the view is closed (after build_async).
var bake_while_hidden := false
var _ground: Ground                          # the one ground everything stands on (empire_board_ground.gd)
var _spans: Dictionary = {}                  # tile_id -> [bridge deck]: where a street crosses a river's valley
var _near_tiles: Dictionary = {}             # tile_id -> it and the drawn tiles beside it
var _piers: Array = []                       # [{tile, polys: [[points, colour]]}] what holds the decks up
var _tile_order: Array = []                  # the drawn tiles, far to near
var _tile_gfx: Dictionary = {}               # tile_id -> {walls, ground, light}: its meshes, in board space
var _tile_parts: Dictionary = {}             # tile_id -> everything else that is drawn on it, see _sort_parts
var _tile_sig: Dictionary = {}               # layer (_unit) -> a hash of what its picture is made of
var _units: Array = []                       # every tile's two layers, "tile_id" + _GROUND or _THINGS, in the order drawn
var _unit_z: Dictionary = {}                 # layer -> its depth: drawn in order of it, far to near
var _things_rects: Dictionary = {}           # tile_id -> the part of the board its things layer covers
## Baked pictures of tiles: "tile|zoom" -> {tex, sig, rect}. A picture is kept for as long as
## what the tile is made of does not change, across turns and across openings of the view.
static var _bakes: Dictionary = {}
var _bake_view: SubViewport
var _painter: Control
var _grade: Control
var _bake_layer: Control
var _baking := false
static var _ground_textures: Dictionary = {}
var _fog: Array = []                         # [{at, r, a, phase}] wisps of dirty air, in board space
var _lights: Array = []                      # [{tex, rect, col, phase}] lit windows and fires
var _glows: Array = []                       # [{at, rx, ry, a}] pools and blooms of lamp light, in board space
var _cars: Array = []                        # [{a, b, length, k, colour, phase, pace}]
var _glow_layer: Control
static var _glow_tex: GradientTexture2D = null
static var _window_tex: Dictionary = {}
static var _wisp: GradientTexture2D = null
var _glints: Array = []                      # [{at, phase, rate}] where the sun catches water
var _stacks: Array = []                      # [{at, r, smoke, phase}] chimneys, in board space
static var _glint_cache: Dictionary = {}     # tile_id -> [[plan point, phase, rate]]
static var _tree_cache: Dictionary = {}       # tile_id -> every place a tree might stand on it
static var _tree_tex: Dictionary = {}
var _standing: Array = []                    # model standing + {at: Vector2 board, h, rect}
var _rails: Array = []                       # [{tile, pts: [{p, h}], stops}] track, tile by tile
var _links: Array = []                       # road-like ways: [{mode, pts: PackedVector2Array board}]
var _road_plan: Array = []                   # [{a, b, half}] road segments in plan, for pipes to cross
var _junctions: Array = []                   # [{at, arms, width}] where roads and drives meet
var _rivers: Dictionary = {}                  # tile_id -> [PackedVector2Array] in plan
var _road_fits: Array = []                   # [{name, at, tint}] junction pieces
var _road_polys: Array = []                  # [{points, uvs, tint}] the straights, tile by tile
var _road_joints: Array = []                 # [{tile, points, colour}] where roads turn on a slope
var _road_lights: Array = []                 # [{tile, points, colours}] light over roads run on past an edge
var _pipes: Array = []                       # plain lines, drawn only when the pieces are not baked
var _pipe_items: Array = []                  # baked pieces and run tiles, far to near
var _signs: Array = []                       # [{foot, top, icon, depth}] sorted far to near
var _cables: Array = []                      # [PackedVector2Array board]
var _flows: Array = []                       # [{pts, cum, total, icon, power, phase}]
var _labels: Array = []                      # [{at: Vector2 board, text}]
var _bounds := Rect2()
var _zoom := 1.0
var _offset := Vector2.ZERO
var _fitted := false
var _clock := 0.0
## Goods on the move along their routes, or (false) the board at rest: each good on the building that makes it.
var animate_goods := true
## Moving goods: how far around a good its group reaches (in token widths), how alike two headings must be to
## count as one way, and how faint a good gets while it crosses a bigger group.
const MOVING_GROUP_REACH := 1.6
const MOVING_SAME_WAY := 0.5
const MOVING_FADED := 0.08
var _press_pos := Vector2.INF
var _dragging := false
## Local Suppliers' depot on hover, under its name, as lines the card can hold.
const SUPPLIERS_HOVER := ["Acts as the source of inputs when 'Local Suppliers'",
	"is selected as a logistics provider and likewise", "the destination for outputs."]
var _hover: Dictionary = {}
var _tokens: Control
var _visibility: Control
var _last_graph: Dictionary = {}
var _last_terrain: Node


static func iso(p: Vector2, h: float = 0.0) -> Vector2:
	return Vector2((p.x - p.y) * ISO_X, (p.x + p.y) * ISO_Y - h * ISO_RISE)


class TokenLayer extends Control:
	var board: Control
	func _draw() -> void:
		board.call("_draw_tokens", self)


## Draws the lamps' light, added to the picture under it.
class GlowLayer extends Control:
	var board: Control
	func _draw() -> void:
		board.call("_draw_glows", self)


## Draws the baked pictures of the tiles, one to one with the screen.
class BakeLayer extends Control:
	var board: Control
	func _draw() -> void:
		board.call("_draw_bakes", self)


## Draws ONE layer of a tile (_unit) into the bake viewport, at the zoom being baked.
class Painter extends Control:
	var board: Control
	var tile := ""
	var zoom := 1.0
	var origin := Vector2.ZERO
	func _draw() -> void:
		if tile == "":
			return
		draw_set_transform(-origin * zoom, 0.0, Vector2(zoom, zoom))
		board.call("_draw_tile", self, tile, zoom)


## Lays the light's colour over everything the painter drew, by multiplying: amber where the
## sun reaches and blue where it does not, on ground, buildings and trees alike.
class Grade extends Control:
	var painter: Control
	func _draw() -> void:
		if str(painter.get("tile")) == "":
			return
		var zoom := float(painter.get("zoom"))
		draw_set_transform(-(painter.get("origin") as Vector2) * zoom, 0.0, Vector2(zoom, zoom))
		(painter.get("board") as Control).call("_draw_grade", self, str(painter.get("tile")))


func _ready() -> void:
	clip_contents = true
	_bake_view = SubViewport.new()
	_bake_view.name = "BakeView"
	_bake_view.transparent_bg = true
	_bake_view.disable_3d = true
	_bake_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_bake_view.size = Vector2i(16, 16)
	add_child(_bake_view)
	_painter = Painter.new()
	_painter.set("board", self)
	_bake_view.add_child(_painter)
	_grade = Grade.new()
	_grade.set("painter", _painter)
	var multiply := CanvasItemMaterial.new()
	multiply.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	_grade.material = multiply
	_painter.add_child(_grade)
	# A transparent viewport's picture comes out with its colour already multiplied by its
	# alpha, so it is laid back down the same way; blended as ordinary colour its soft edges
	# would darken.
	_bake_layer = BakeLayer.new()
	_bake_layer.set("board", self)
	_bake_layer.name = "Bakes"
	_bake_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bake_layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_bake_layer.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_bake_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var premult := CanvasItemMaterial.new()
	premult.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	_bake_layer.material = premult
	add_child(_bake_layer)
	# Light is added to what lies under it, so it has a layer of its own.
	_glow_layer = GlowLayer.new()
	_glow_layer.set("board", self)
	_glow_layer.name = "Glow"
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glow_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var adding := CanvasItemMaterial.new()
	adding.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = adding
	add_child(_glow_layer)
	_tokens = TokenLayer.new()
	_tokens.set("board", self)
	_tokens.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	_tokens.name = "Tokens"
	_tokens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tokens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_tokens)
	_visibility = Visibility.new()
	add_child(_visibility)
	_visibility.setup(show)
	_visibility.changed.connect(func(_key: String, _on: bool) -> void: refresh())
	resized.connect(func() -> void:
		if not _fitted:
			fit_view())


## Rebuild the board from the live sim. `graph` is empire_graph.build(); `terrain` the HexMap.
## Build the board again from what it was last given: a visibility switch has changed.
func refresh() -> void:
	if _last_terrain != null and is_instance_valid(_last_terrain):
		set_graph(_last_graph, _last_terrain)


func set_graph(graph: Dictionary, terrain: Node) -> void:
	_paced = false
	_build(graph, terrain)


## The same build as set_graph, spread over frames a few milliseconds at a time, so it can run
## behind the loading screen or while the view is closed without the game missing a frame; then
## every layer in view at the zoom the board will open at is baked, one a frame. A set_graph, or
## another build, while it runs takes over from it. Returns once the build is done; the bakes
## carry on in _process.
func build_async(graph: Dictionary, terrain: Node) -> void:
	_paced = true
	_slice_from = Time.get_ticks_msec()
	await _build(graph, terrain)
	bake_while_hidden = true


## Is the board built from the latest graph it was given, and every layer in view baked.
func is_ready() -> bool:
	return not _building and has_content() and _next_bake() == "" and not _baking


## Hand a frame back to the game when the present build is paced and has had its time this frame.
func _pace() -> void:
	if not _paced or Time.get_ticks_msec() - _slice_from < _PACE_MS:
		return
	await get_tree().process_frame
	_slice_from = Time.get_ticks_msec()


func _build(graph: Dictionary, terrain: Node) -> void:
	_build_gen += 1
	var gen := _build_gen
	_building = true
	_last_graph = graph
	_last_terrain = terrain
	_model = {}
	_tile_order = []
	_tile_gfx.clear()
	_tile_parts.clear()
	_tile_sig.clear()
	_glints.clear()
	_stacks.clear()
	_lights.clear()
	_standing.clear()
	_links.clear()
	_rails.clear()
	_road_plan.clear()
	_junctions.clear()
	_pipes.clear()
	_road_fits.clear()
	_road_polys.clear()
	_road_joints.clear()
	_road_lights.clear()
	_pipe_items.clear()
	_signs.clear()
	_cables.clear()
	_flows.clear()
	_labels.clear()
	_hover = {}
	_spans.clear()
	_near_tiles.clear()
	_piers.clear()
	if terrain == null or not terrain.has_method("id_to_coord"):
		_building = false
		queue_redraw()
		return
	var rivers: Dictionary = _rivers_by_tile(terrain)
	_rivers = _river_lines(rivers)
	if _paced:
		# Every tile's height, read off the map a few at a time before they are settled together.
		for tid in Catalog.all_tile_ids():
			var coord: Vector2i = terrain.id_to_coord(str(tid))
			if coord.x >= 0:
				Relief.tile_level(Model.tile_center(terrain, str(tid)))
				await _pace()
				if gen != _build_gen:
					return
	var plates: Dictionary = Relief.plates(terrain, _rivers)
	await _pace()
	if gen != _build_gen:
		return
	_model = Model.build(terrain, graph, _true_positions(graph, terrain), _rivers, plate_town and bool(show["decor"]),
		_water_test(terrain))
	await _pace()
	if gen != _build_gen:
		return
	_ground = Ground.for_map(terrain, rivers, plates, Callable(get_script(), "_relief_of")) as Ground
	await _pace()
	if gen != _build_gen:
		return
	await _build_ground(rivers, gen)
	if gen != _build_gen:
		return
	_mark_bridges()
	await _pace()
	if gen != _build_gen:
		return
	_build_standing()
	await _pace()
	if gen != _build_gen:
		return
	await _build_lines(gen)
	if gen != _build_gen:
		return
	await _pace()
	if gen != _build_gen:
		return
	_build_fog()
	_build_lamps()
	_build_trees()
	_build_cars()
	_build_piers()
	_sort_parts()
	_building = false
	if not _fitted:
		fit_view()
	if is_visible_in_tree():
		_hold_until_baked()
	queue_redraw()
	_bake_layer.queue_redraw()


## Tiles not yet baked are drawn live under the baked ones, so a board opening with none baked would
## shuffle its tiles in front of each other as the bakes land. Until every tile in view has a picture the
## board is held back, then fades in; a board already baked shows at once.
const _REVEAL_FADE := 0.15
const _REVEAL_LIMIT := 2.0           # seconds: show the board anyway if the bakes are slow
var _revealing := false
var _reveal_wait := 0.0


func _hold_until_baked() -> void:
	var view := Rect2(Vector2.ZERO, size)
	for unit in _units:
		var r := _unit_rect(str(unit))
		if _best_bake(str(unit)).is_empty() and view.intersects(Rect2(r.position * _zoom + _offset, r.size * _zoom)):
			_revealing = true
			_reveal_wait = 0.0
			modulate.a = 0.0
			return


func _reveal_when_baked(delta: float) -> void:
	if not _revealing:
		return
	_reveal_wait += delta
	if (_next_bake() != "" or _baking) and _reveal_wait < _REVEAL_LIMIT:
		return
	_revealing = false
	create_tween().tween_property(self, "modulate:a", 1.0, _REVEAL_FADE)


func has_content() -> bool:
	return not (_model.get("tiles", {}) as Dictionary).is_empty()


func capture_camera() -> Dictionary:
	return {"offset": _offset, "zoom": _zoom}


## The standing things with their screen rects, for tools and tests.
func standing_screen_rects() -> Array:
	var out: Array = []
	for s in _standing:
		var r: Rect2 = s["rect"]
		out.append({"iid": s["iid"], "kind": s["kind"],
			"rect": Rect2(r.position * _zoom + _offset, r.size * _zoom)})
	return out


func fit_view() -> void:
	if _bounds.size.x <= 0.0 or size.x <= 0.0:
		return
	var avail := size - Vector2(_FIT_PAD, _FIT_PAD) * 2.0
	_zoom = clampf(minf(avail.x / _bounds.size.x, avail.y / _bounds.size.y), _ZOOM_MIN, BAKE_ZOOMS[BAKE_ZOOMS.size() - 1])
	_offset = size * 0.5 - _bounds.get_center() * _zoom
	_fitted = true
	_view_changed()


func _view_changed() -> void:
	queue_redraw()
	_bake_layer.queue_redraw()


# ------------------------------------------------------------------ source data

func _rivers_by_tile(terrain: Node) -> Dictionary:
	var out: Dictionary = {}
	var rv: Node = terrain.get_parent().get_node_or_null("RiverVisuals") if terrain.get_parent() != null else null
	if rv == null:
		rv = get_tree().get_first_node_in_group("river_visuals")
	if rv == null or not rv.has_method("get_river_polylines"):
		return out
	for rec in rv.call("get_river_polylines"):
		var c: Vector2i = rec["coord"]
		var tid := "tile_%d_%d" % [c.x + 1, c.y + 1]
		(out.get_or_add(tid, []) as Array).append(rec)
	return out


func _river_lines(rivers: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for tid in rivers:
		var lines: Array = []
		for rec in rivers[tid]:
			lines.append(rec["points"])
		out[tid] = lines
	return out


## Is a point of a tile open water, as the ground draws it: (tile_id, point) -> bool, for the
## model to keep what stands and the streets off the sea.
static func _water_test(terrain: Node) -> Callable:
	var centers: Dictionary = {}
	return func(tile: String, p: Vector2) -> bool:
		var kind := str(Catalog.tile_type(tile))
		if kind == "sea" or kind == "deep_sea":
			return true
		if not centers.has(tile):
			centers[tile] = Model.tile_center(terrain, tile)
		return Ground.is_water(_relief_of(tile, centers[tile]), p)


func _true_positions(graph: Dictionary, terrain: Node) -> Dictionary:
	var out: Dictionary = {}
	var bv: Node = get_tree().get_first_node_in_group("building_footprints")
	if bv == null or not bv.has_method("footprint_center_for"):
		return out
	for n in graph.get("nodes", []):
		var tile := str((n as Dictionary).get("tile_id", ""))
		if tile == "":
			continue
		out[str(n["iid"])] = bv.call("footprint_center_for", str(n["iid"]), terrain.id_to_coord(tile))
	return out


static func _load_relief() -> void:
	if not _hill_polys.is_empty():
		return
	for e in HillBaked.polys():
		_hill_polys.append({"b": int(e["b"]), "p": e["p"], "box": _box_of(e["p"])})
	for e in HillBaked.sea():
		if int(e["b"]) < 5:
			_sea_polys.append({"b": int(e["b"]), "p": e["p"], "box": _box_of(e["p"])})
	for p in HillBaked.lakes():
		_lake_polys.append({"p": p, "box": _box_of(p)})


static func _box_of(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r


## The tile's relief: its water and its land bands clipped to the hex, in the map's paint order:
## the colours its ground is drawn in. Cached for good; the relief never changes in a game.
static func _relief_of(tile_id: String, center: Vector2) -> Dictionary:
	if _relief_cache.has(tile_id):
		return _relief_cache[tile_id]
	_load_relief()
	var hexp := Model.hex_points(center)
	var box := _box_of(hexp)
	var sea: Array = []
	for e in _sea_polys:
		if (e["box"] as Rect2).intersects(box):
			for piece in _clip(e["p"], hexp):
				sea.append({"b": int(e["b"]), "p": piece})
	var land: Array = []
	for e in _hill_polys:
		if not (e["box"] as Rect2).intersects(box):
			continue
		for piece in _clip(e["p"], hexp):
			land.append({"b": int(e["b"]), "p": piece})
	var lakes: Array = []
	for e in _lake_polys:
		if (e["box"] as Rect2).intersects(box):
			lakes.append_array(_clip(e["p"], hexp))
	var rel := {"sea": sea, "land": land, "lakes": lakes}
	_relief_cache[tile_id] = rel
	return rel


static func _clip(poly: PackedVector2Array, hexp: PackedVector2Array) -> Array:
	var out: Array = []
	if poly.size() < 3:
		return out
	for piece in Geometry2D.intersect_polygons(poly, hexp):
		var pts: PackedVector2Array = piece
		if pts.size() >= 3 and not Geometry2D.is_polygon_clockwise(pts):
			out.append(pts)
	return out


## The ground at a map point, the one height everything on the board stands on.
func _height_at(p: Vector2) -> float:
	return _ground.height(p)


## The height a way stands at, at a point of a tile: the ground, or a bridge's deck over a valley.
## Only the decks a way crosses on are built (_mark_bridges); one reaching on over a tile edge carries
## the way on the other side too.
func _way_h(tile: String, p: Vector2) -> float:
	var h := _height_at(p)
	for t in _with_neighbours(tile):
		for span in _spans_of(str(t)):
			if bool(span["used"]) and Geometry2D.get_closest_point_to_segment(p, span["a"], span["b"]).distance_to(p) <= float(span["half"]):
				h = maxf(h, float(span["deck"]))
	return h


## Put in use every deck a street in use or a railway crosses a river on: those, and only those, are
## built, with their piers.
func _mark_bridges() -> void:
	var runs: Array = []                      # [tile, a, b]
	for r in _model.get("roads", []):
		runs.append([str(r["tile"]), r["a"], r["b"]])
	for l in _model.get("lines", []):
		var mode := str(l["mode"])
		if mode == Model.MODE_CABLE or Model.PIPE_MODES.has(mode):
			continue
		var path: Array = l["pts"]
		for i in range(path.size() - 1):
			if str(path[i]["tile"]) == str(path[i + 1]["tile"]):
				runs.append([str(path[i]["tile"]), path[i]["p"], path[i + 1]["p"]])
	for run in runs:
		var a: Vector2 = run[1]
		var b: Vector2 = run[2]
		if a.distance_to(b) < 0.01:
			continue
		for span in _spans_of(str(run[0])):
			if Geometry2D.get_closest_point_to_segment(span["at"], a, b).distance_to(span["at"]) < 1.0 \
					and absf((b - a).normalized().dot(span["dir"])) > 0.9:
				span["used"] = true


## A drawn tile and the drawn tiles beside it.
func _with_neighbours(tile: String) -> Array:
	if _near_tiles.has(tile):
		return _near_tiles[tile]
	var tiles: Dictionary = _model.get("tiles", {})
	var out: Array = [tile]
	if tiles.has(tile):
		var c: Vector2 = tiles[tile]["center"]
		for other in tiles:
			if str(other) != tile and (tiles[other]["center"] as Vector2).distance_to(c) < Model.ADJACENT_REACH:
				out.append(str(other))
	_near_tiles[tile] = out
	return out


## Does a plan point lie on a tile the board draws.
func _drawn_at(p: Vector2) -> bool:
	var tiles: Dictionary = _model.get("tiles", {})
	for t in tiles:
		if Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[t]["center"])):
			return true
	return false


## The ground under a straight way from `a` to `b`, as [[share of the way, height]]: it follows the
## ground up and down every slope, and with `tile` given, it crosses a river's valley on a bridge.
func _profile(a: Vector2, b: Vector2, tile: String = "") -> Array:
	var length := a.distance_to(b)
	var at := func(p: Vector2) -> float: return _way_h(tile, p) if tile != "" else _height_at(p)
	if length < 0.01:
		var h0: float = at.call(a)
		return [[0.0, h0], [1.0, h0]]
	var n := maxi(1, ceili(length / PROFILE_STEP))
	var out: Array = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		out.append([t, at.call(a.lerp(b, t))])
	return _simplify(out)


## A profile with the points that lie near the line between their neighbours left out.
static func _simplify(prof: Array) -> Array:
	if prof.size() <= 2:
		return prof
	var out: Array = [prof[0]]
	for i in range(1, prof.size() - 1):
		var p0: Array = out[out.size() - 1]
		var p1: Array = prof[i + 1]
		var t := (float(prof[i][0]) - float(p0[0])) / maxf(float(p1[0]) - float(p0[0]), 0.000001)
		if absf(float(prof[i][1]) - lerpf(float(p0[1]), float(p1[1]), t)) > PROFILE_KEEP:
			out.append(prof[i])
	out.append(prof[prof.size() - 1])
	return out


## Where a tile's streets cross its rivers, the decks that carry them over the valley: for every
## stretch of the street plan that crosses a river, a level deck at the height of the lower of its
## two banks, reaching from where the ground drops below that on one side to where it rises back on
## the other. [{a, b, deck, half, at, dir, river_half, used}] in plan; worked out once per tile, so
## a road, a railway and the goods on them all cross on one deck.
func _spans_of(tile: String) -> Array:
	if _spans.has(tile):
		return _spans[tile]
	var out: Array = []
	_spans[tile] = out
	var tiles: Dictionary = _model.get("tiles", {})
	if not tiles.has(tile):
		return out
	var c: Vector2 = tiles[tile]["center"]
	var runs: Array = _ground.river_runs(tile)
	for e in Streets.edges():
		var a: Vector2 = c + Streets.node_pos(str(e[0]))
		var b: Vector2 = c + Streets.node_pos(str(e[1]))
		var dir := (b - a).normalized()
		for run in runs:
			var river: PackedVector2Array = run["pts"]
			for i in range(river.size() - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, river[i], river[i + 1])
				if hit == null:
					continue
				var x: Vector2 = hit
				var sine := maxf(absf(dir.cross((river[i + 1] - river[i]).normalized())), 0.4)
				var reach := (float(run["half"]) + Ground.BANK + Ground.SLOPE_W) / sine + BRIDGE_LOOK
				var banks: Array = []
				for way in [-1.0, 1.0]:
					var top := -INF
					var s := 0.0
					while s <= reach:
						top = maxf(top, _height_at(x + dir * s * float(way)))
						s += 2.0
					banks.append(top)
				var deck := minf(float(banks[0]), float(banks[1]))
				if deck < _height_at(x) + BRIDGE_MIN_RISE:
					continue                          # a street along the valley's floor: no deck to raise
				var ends: Array = []
				for way in [-1.0, 1.0]:
					# No further than the stretch of street it carries.
					var limit := minf(reach, x.distance_to(a if way < 0.0 else b))
					var s := 0.0
					while s < limit and _height_at(x + dir * s * float(way)) < deck - 0.05:
						s += 1.0
					ends.append(x + dir * s * float(way))
				out.append({"a": ends[0], "b": ends[1], "deck": deck, "half": BRIDGE_HALF, "at": x, "dir": dir,
					"river_half": float(run["half"]) / sine, "used": false, "tile": tile})
	return out


## What holds up every deck a way crosses on: a pier each side of the river, down to the valley's
## floor, and the deck's edge on the side toward the viewer; none of it out over the dark beyond the
## board's rim.
func _build_piers() -> void:
	for tile in _spans:
		for span in _spans[tile]:
			if not bool(span["used"]):
				continue
			var deck := float(span["deck"])
			var dir: Vector2 = span["dir"]
			var side := dir.orthogonal()
			if side.x + side.y < 0.0:
				side = -side
			var polys: Array = []
			var a: Vector2 = span["a"]
			var b: Vector2 = span["b"]
			var off_a := not _drawn_at(a)
			var off_b := not _drawn_at(b)
			if off_a or off_b:
				var own := Model.hex_points((_model["tiles"] as Dictionary)[span["tile"]]["center"])
				for piece in Geometry2D.intersect_polyline_with_polygon(PackedVector2Array([a, b]), own):
					var kept: PackedVector2Array = piece
					if kept.size() < 2 or Geometry2D.get_closest_point_to_segment(span["at"], kept[0], kept[kept.size() - 1]) \
							.distance_to(span["at"]) > 0.5:
						continue
					if off_a:
						a = kept[0]
					if off_b:
						b = kept[kept.size() - 1]
			if a.distance_to(b) < 1.0:
				continue
			for way in [-1.0, 1.0]:
				var at: Vector2 = (span["at"] as Vector2) + dir * (float(span["river_half"]) + 3.0) * float(way)
				var foot := _height_at(at)
				if deck - foot < 1.0 or not _drawn_at(at):
					continue
				for across in [-0.6, 0.6]:
					var p: Vector2 = at + side * _ROAD_HALF * float(across)
					var hs := 1.8
					var corners := [p + Vector2(-hs, -hs), p + Vector2(hs, -hs), p + Vector2(hs, hs), p + Vector2(-hs, hs)]
					# The faces toward the viewer, south and east, the sunlit one paler.
					polys.append([PackedVector2Array([iso(corners[3], deck), iso(corners[2], deck), iso(corners[2], foot),
						iso(corners[3], foot)]), _PIER.darkened(0.15)])
					polys.append([PackedVector2Array([iso(corners[2], deck), iso(corners[1], deck), iso(corners[1], foot),
						iso(corners[2], foot)]), _PIER.lightened(0.12)])
			var front_a := a + side * _ROAD_HALF
			var front_b := b + side * _ROAD_HALF
			polys.append([PackedVector2Array([iso(front_a, deck), iso(front_b, deck), iso(front_b, deck - BRIDGE_FASCIA),
				iso(front_a, deck - BRIDGE_FASCIA)]), _GIRDER])
			_piers.append({"tile": str(span["tile"]), "polys": polys, "key": "%s|%s" % [a.round(), b.round()]})


# ------------------------------------------------------------------ building the picture

func _build_ground(rivers: Dictionary, gen: int) -> void:
	var tiles: Dictionary = _model.get("tiles", {})
	_bounds = Rect2()
	if tiles.is_empty():
		return
	var order: Array = tiles.keys()
	order.sort_custom(func(a, b) -> bool:
		var ca: Vector2 = tiles[a]["center"]
		var cb: Vector2 = tiles[b]["center"]
		if absf((ca.x + ca.y) - (cb.x + cb.y)) > 0.5:
			return ca.x + ca.y < cb.x + cb.y
		return ca.x < cb.x)
	var by_center: Dictionary = {}
	var first := true
	for tid in order:
		var t0: Dictionary = tiles[tid]
		by_center[Vector2i((t0["center"] as Vector2).round())] = tid
		t0["top"] = await _tile_top(str(tid))
		if gen != _build_gen:
			return
		for p in Model.hex_points(t0["center"]):
			for hh in [float(t0["top"]), -SLAB_DEPTH]:
				var q := iso(p, hh)
				if first:
					_bounds = Rect2(q, Vector2.ZERO)
					first = false
				else:
					_bounds = _bounds.expand(q)
	_tile_order = order
	var band_cols: Array[Color] = MapStyle.band_colors()
	var sea_cols: Array[Color] = MapStyle.sea_colors()
	var water: Color = sea_cols[4]
	if _ground_meshes.size() > _GROUND_MESHES_KEPT:
		_ground_meshes.clear()
	if _light_meshes.size() > _GROUND_MESHES_KEPT:
		_light_meshes.clear()
	for tid in order:
		await _pace()
		if gen != _build_gen:
			return
		var t: Dictionary = tiles[tid]
		var c: Vector2 = t["center"]
		var hexp := Model.hex_points(c)
		var is_sea := str(t["type"]) == "sea" or str(t["type"]) == "deep_sea"
		var rel: Dictionary = _relief_of(str(tid), c)
		var beside: Array = []                        # per edge: a tile is drawn there
		for i in range(6):
			var mid := (hexp[i] + hexp[(i + 1) % 6]) * 0.5
			beside.append(by_center.has(Vector2i((c + (mid - c) * 2.0).round())))
		t["beside"] = beside
		var label_at := c + Vector2(135.0, 240.0) * 0.72
		_labels.append({"at": iso(label_at, _height_at(label_at)), "text": str(t["label"])})
		_seed_glints(str(tid), t, rel, is_sea)
		var top: Color = sea_cols[0 if str(t["type"]) == "deep_sea" else 2] if is_sea else _warm(sea_cols[5])
		# A tile's ground stays as it is for as long as the tiles drawn beside it do; its light, for as
		# long as the board's extent does too.
		var key := "%s|%s|%d|%d" % [tid, beside, _ground.get_instance_id(), hash([band_cols, sea_cols])]
		var light_key := "%s|%s|%s" % [key, _bounds, plate_sea]
		if not _light_meshes.has(light_key):
			_light_meshes[light_key] = _build_light(c, hexp, beside, rel, is_sea)
		if _ground_meshes.has(key):
			_tile_gfx[tid] = (_ground_meshes[key] as Dictionary).merged({"light": _light_meshes[light_key]}, true)
			continue
		# Each tile has its own meshes, so one tile can be drawn, and baked, without the rest.
		var verts := PackedVector3Array()
		var cols := PackedColorArray()
		var idx := PackedInt32Array()
		var wverts := PackedVector3Array()            # the cut-away walls, textured with the strata
		var wcols := PackedColorArray()
		var wuvs := PackedVector2Array()
		var widx := PackedInt32Array()
		# The ground first, laid over its shape: the plate's colour, the sea under the land, then
		# every band of the land and the lakes, each where the map has it.
		_drape(verts, cols, idx, hexp, top)
		for e in rel["sea"]:
			_drape(verts, cols, idx, e["p"], sea_cols[int(e["b"])])
		if not is_sea:
			for e in rel["land"]:
				_drape(verts, cols, idx, e["p"], _warm(band_cols[clampi(int(e["b"]), 0, band_cols.size() - 1)]))
		for p in rel["lakes"]:
			_drape(verts, cols, idx, p, water)
		# Over each edge it shares with a tile drawn beside it, a skirt of this tile's own ground runs on a
		# little way, so the two pictures overlap where they meet and no gap shows between them.
		for i in range(6):
			if not bool(beside[i]):
				continue
			var a := hexp[i]
			var b := hexp[(i + 1) % 6]
			var n := (b - a).orthogonal().normalized()
			if n.dot((a + b) * 0.5 - c) < 0.0:
				n = -n
			var along := _edge_points(a, b)
			for k in range(along.size() - 1):
				var q0 := along[k]
				var q1 := along[k + 1]
				var c0 := _ground_colour(rel, q0.lerp(q1, 0.02) - n * 0.6, top, is_sea, band_cols, sea_cols, water, rivers.get(tid, []))
				var c1 := _ground_colour(rel, q1.lerp(q0, 0.02) - n * 0.6, top, is_sea, band_cols, sea_cols, water, rivers.get(tid, []))
				var board: Array = []
				for q in [q0, q1, q1 + n * _SKIRT, q0 + n * _SKIRT]:
					board.append(iso(q, _height_at(q)))
				_quad_cols(verts, cols, idx, board, [c0, c1, c1, c0])
		await _pace()
		if gen != _build_gen:
			return
		var coast: Array = [] if is_sea or (rel["sea"] as Array).is_empty() else _shore_of(rel, hexp)
		# The shore, as on the key art's plate: no hard line, but a beach. Dry sand on the land
		# side, a darker wet strip at the water's edge, a thread of foam, and pale shallows
		# running out into the deeper water.
		if not coast.is_empty():
			# Laid widest first, so each band shows as a strip beside the next.
			for band in [[_SHALLOWS_OUT, _SHALLOWS_W, water.lightened(0.14)], [_SHALLOWS_OUT * 0.45, _SHALLOWS_W * 0.6, water.lightened(0.3)],
					[-_STRAND * 0.5, _STRAND, _SAND], [0.6, 3.4, _SAND.darkened(0.16)], [2.6, 1.1, _FOAM]]:
				for seg in coast:
					var out: Vector2 = (seg[2] as Vector2) * float(band[0])
					# A band that would run out over the tile's own edge is left off there.
					if not Geometry2D.is_point_in_polygon(((seg[0] as Vector2) + (seg[1] as Vector2)) * 0.5
							+ (seg[2] as Vector2) * (float(band[0]) + signf(float(band[0])) * float(band[1]) * 0.5), hexp):
						continue
					_stroke_on(verts, cols, idx, PackedVector2Array([(seg[0] as Vector2) + out, (seg[1] as Vector2) + out]),
						float(band[1]), band[2])
		for p in rel["lakes"]:
			var ring: PackedVector2Array = p
			ring.append(ring[0])
			_stroke_on(verts, cols, idx, ring, 4.0, _SAND.darkened(0.08))
			_stroke_on(verts, cols, idx, ring, 1.6, water.lightened(0.3))
		# The open water on this tile, for an estuary to run out over and no further.
		var sea_pieces: Array = []
		for e in rel["sea"]:
			sea_pieces.append(e["p"])
		# A river: pale banks, the water lighter down its middle, and only a thin line to it.
		# Laid after the beach, so at its mouth the water runs over the sand and into the sea;
		# the banks stop at the shoreline. It runs on the floor of its valley, falling where the
		# valley steps down, white where the fall is steep.
		var skirted := _skirted(hexp, beside)
		for rec in rivers.get(tid, []):
			var half_w := (float(rec["start_width"]) + float(rec["end_width"])) * 0.25
			for part in Geometry2D.intersect_polyline_with_polygon(rec["points"], skirted):
				for run in _to_mouth(rel, _aim_mouth(rel, part, coast, half_w * 2.0), coast, half_w * 2.0):
					var ground: Array = _ground_line(run["pts"])
					var pts: PackedVector2Array = ground[0]
					var hs: PackedFloat32Array = ground[1]
					_stroke_to(verts, cols, idx, pts, half_w * 2.0, water, run["cuts"], _MOUTH, hs)
					_stroke_to(verts, cols, idx, pts, half_w * 0.9, water.lightened(0.16), run["cuts"], _MOUTH, hs)
					for side in [-1.0, 1.0]:
						_stroke_to(verts, cols, idx, _beside(pts, (half_w + 1.4) * float(side)), 3.0, _BANK, run["cuts"], 0.0, hs)
						_stroke_to(verts, cols, idx, _beside(pts, half_w * float(side)), 0.9, _INK_SOFT, run["cuts"], 0.0, hs)
					_white_water(verts, cols, idx, pts, hs, half_w * 2.0)
					for cut in run["cuts"]:
						_estuary(verts, cols, idx, pts, cut, half_w * 2.0, water, hexp, sea_pieces)
		# The board's rim: a cliff down to the slab's foot wherever no tile is drawn beyond an edge,
		# its top following the ground along the edge, and inked.
		for i in range(6):
			if bool(beside[i]):
				continue
			var a := hexp[i]
			var b := hexp[(i + 1) % 6]
			var n := ((a + b) * 0.5 - c).normalized()
			var rim := _edge_points(a, b)
			var rim_h := PackedFloat32Array()
			for q in rim:
				rim_h.append(_height_at(q))
			if n.x + n.y > 0.01:
				_cliff(verts, cols, idx, wverts, wcols, wuvs, widx, rel, is_sea, rim, rim_h, a, b, n, top, water, sea_cols)
			_stroke_on(verts, cols, idx, rim, _INK_W * 1.3, _INK)
		await _pace()
		if gen != _build_gen:
			return
		_ground_meshes[key] = {"ground": _mesh_of(verts, cols, idx), "walls": _mesh_of(wverts, wcols, widx, wuvs),
			"shade": _build_shade(hexp, beside)}
		_tile_gfx[tid] = (_ground_meshes[key] as Dictionary).merged({"light": _light_meshes[light_key]}, true)


## A tile's light, laid over everything on its ground: golden toward the sun and cool away from it,
## over its skirts too; and where plate_sea is on, its open water pale toward the sun and deep away.
func _build_light(c: Vector2, hexp: PackedVector2Array, beside: Array, rel: Dictionary, is_sea: bool) -> ArrayMesh:
	var lverts := PackedVector3Array()
	var lcols := PackedColorArray()
	var lidx := PackedInt32Array()
	if plate_sea:
		var open: Array = [hexp] if is_sea else []
		if not is_sea:
			for e in rel["sea"]:
				open.append(e["p"])
			for e in rel["land"]:
				var cut: Array = []
				for w in open:
					for piece in Geometry2D.clip_polygons(w, e["p"]):
						if not Geometry2D.is_polygon_clockwise(piece):
							cut.append(piece)
				open = cut
		for sheet in open:
			_drape(lverts, lcols, lidx, sheet, Color.WHITE, _DRAPE_SEA_LIGHT)
	_drape(lverts, lcols, lidx, hexp, Color.WHITE, _DRAPE_LIGHT)
	for i in range(6):
		if not bool(beside[i]):
			continue
		var a := hexp[i]
		var b := hexp[(i + 1) % 6]
		var n := (b - a).orthogonal().normalized()
		if n.dot((a + b) * 0.5 - c) < 0.0:
			n = -n
		var along := _edge_points(a, b)
		for k in range(along.size() - 1):
			var board: Array = []
			var wash: Array = []
			for q in [along[k], along[k + 1], along[k + 1] + n * _SKIRT, along[k] + n * _SKIRT]:
				var bq := iso(q, _height_at(q))
				board.append(bq)
				wash.append(_light_wash(_light_at(bq)))
			_quad_cols(lverts, lcols, lidx, board, wash)
	return _mesh_of(lverts, lcols, lidx)


## A tile's hex with each edge it shares with a tile drawn beside it moved out by the skirt.
static func _skirted(hexp: PackedVector2Array, beside: Array) -> PackedVector2Array:
	var c := (hexp[0] + hexp[3]) * 0.5
	var lines: Array = []                         # per edge: [a point on it, its direction]
	for i in range(6):
		var a := hexp[i]
		var b := hexp[(i + 1) % 6]
		var n := (b - a).orthogonal().normalized()
		if n.dot((a + b) * 0.5 - c) < 0.0:
			n = -n
		lines.append([a + n * (_SKIRT if bool(beside[i]) else 0.0), b - a])
	var out := PackedVector2Array()
	for i in range(6):
		var l0: Array = lines[(i + 5) % 6]
		var l1: Array = lines[i]
		var hit: Variant = Geometry2D.line_intersects_line(l0[0], l0[1], l1[0], l1[1])
		out.append(hit if hit != null else hexp[i])
	return out


## The colour the ground is drawn in at a point of a tile: its river, its lake, its band of land, its
## sea or its plate, in the order they are laid.
func _ground_colour(rel: Dictionary, p: Vector2, top: Color, is_sea: bool, band_cols: Array[Color],
		sea_cols: Array[Color], water: Color, river_recs: Array) -> Color:
	for rec in river_recs:
		var line: PackedVector2Array = rec["points"]
		var half := (float(rec["start_width"]) + float(rec["end_width"])) * 0.25
		for k in range(line.size() - 1):
			if Geometry2D.get_closest_point_to_segment(p, line[k], line[k + 1]).distance_to(p) < half:
				return water
	for lake in rel["lakes"]:
		if Geometry2D.is_point_in_polygon(p, lake):
			return water
	var col := top
	for e in rel["sea"]:
		if Geometry2D.is_point_in_polygon(p, e["p"]):
			col = sea_cols[int(e["b"])]
	if not is_sea:
		for e in rel["land"]:
			if Geometry2D.is_point_in_polygon(p, e["p"]):
				col = _warm(band_cols[clampi(int(e["b"]), 0, band_cols.size() - 1)])
	return col


## The highest ground over a tile's hex, the ground's lattice over it worked out row by row (a paced
## build hands a frame back between rows when its time is up).
func _tile_top(tile: String) -> float:
	var t: Dictionary = (_model["tiles"] as Dictionary)[tile]
	var c: Vector2 = t["center"]
	var top := float(t["height"])
	var g := Ground.NODE
	for j in range(floori((c.y - Ground.HEX_HALF.y) / g) - 1, ceili((c.y + Ground.HEX_HALF.y) / g) + 2):
		for i in range(floori((c.x - Ground.HEX_HALF.x) / g) - 1, ceili((c.x + Ground.HEX_HALF.x) / g) + 2):
			var d := Vector2(float(i), float(j)) * g - c
			if absf(d.y) <= Ground.HEX_HALF.y + g * 2.0 and absf(d.x) <= Ground.HEX_HALF.x - absf(d.y) * 0.5625 + g * 2.0:
				top = maxf(top, Ground.cell_height(_ground.cell(i, j), 0.0, 0.0))
		await _pace()
	return top


## The points along a tile edge from `a` to `b` where it crosses the ground's lattice, ends included:
## where the ground drawn on the edge has its corners, so a cliff's top meets it exactly.
static func _edge_points(a: Vector2, b: Vector2) -> PackedVector2Array:
	var shares: Array = [0.0, 1.0]
	var g := Ground.NODE
	for axis in [0, 1]:
		var lo := minf(a[axis], b[axis])
		var hi := maxf(a[axis], b[axis])
		if hi - lo < 0.001:
			continue
		var k := ceilf(lo / g) * g
		while k < hi:
			shares.append((k - a[axis]) / (b[axis] - a[axis]))
			k += g
	shares.sort()
	var out := PackedVector2Array()
	for s in shares:
		var p := a.lerp(b, float(s))
		if out.is_empty() or out[out.size() - 1].distance_to(p) > 0.05:
			out.append(p)
	return out


## One cliff of the board's rim, under the edge from `a` to `b` facing the viewer: the strata run
## level through the whole board, so the wall shows the part of them between the ground along its
## top and the slab's foot. Along the edge, stretch by stretch: under land the rock comes up to a lip
## of turf; under open water the cut shows the water's depth over the rock.
func _cliff(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, wverts: PackedVector3Array,
		wcols: PackedColorArray, wuvs: PackedVector2Array, widx: PackedInt32Array, rel: Dictionary, is_sea: bool,
		rim: PackedVector2Array, rim_h: PackedFloat32Array, a: Vector2, b: Vector2, n: Vector2, top: Color,
		water: Color, sea_cols: Array[Color]) -> void:
	var k := 0.74 + 0.26 * maxf(0.0, n.dot(_SUN))
	var shade := Color(k, k, k)
	var runs: Array = []                          # [[first point, last point, wet]]
	for i in range(rim.size() - 1):
		var wet: bool = is_sea or Ground.is_water(rel, (rim[i] + rim[i + 1]) * 0.5 - n * 3.0)
		if not runs.is_empty() and bool(runs[runs.size() - 1][2]) == wet:
			runs[runs.size() - 1][1] = i + 1
		else:
			runs.append([i, i + 1, wet])
	for run in runs:
		var wet := bool(run[2])
		var outline: Array = []
		for i in range(int(run[0]), int(run[1]) + 1):
			outline.append([rim[i], rim_h[i] - (_WATER_DEPTH if wet else 0.0)])
		outline.append([rim[int(run[1])], -SLAB_DEPTH])
		outline.append([rim[int(run[0])], -SLAB_DEPTH])
		_wall(wverts, wcols, wuvs, widx, outline, a, b, shade)
		for i in range(int(run[0]), int(run[1])):
			var p0 := rim[i]
			var p1 := rim[i + 1]
			var h0 := rim_h[i]
			var h1 := rim_h[i + 1]
			if wet:
				var shallow := water.lightened(0.12)
				var deep: Color = sea_cols[1]
				_quad_cols(verts, cols, idx, [iso(p0, h0), iso(p1, h1), iso(p1, h1 - _WATER_DEPTH), iso(p0, h0 - _WATER_DEPTH)],
					[shallow, shallow, deep, deep])
				_poly_board(verts, cols, idx, PackedVector2Array([iso(p0, h0 - _WATER_DEPTH), iso(p1, h1 - _WATER_DEPTH),
					iso(p1, h1 - _WATER_DEPTH - 1.6), iso(p0, h0 - _WATER_DEPTH - 1.6)]), _INK)
			else:
				_poly_board(verts, cols, idx, PackedVector2Array([iso(p0, h0), iso(p1, h1), iso(p1, h1 - _TURF),
					iso(p0, h0 - _TURF)]), top.darkened(0.38))


## How a polygon is laid over the ground: in its own colour; as the sea's light; or as the light's
## wash over the whole tile.
const _DRAPE_SHADED := 0
## Each sloping cell of the lattice is shaded cut this many ways each way.
const _SHADE_SUB := 2
const _DRAPE_SEA_LIGHT := 1
const _DRAPE_LIGHT := 2


## Lay a polygon over the ground, in its own colour: the ground's slopes are shaded over it after
## (_build_shade). It is cut row by row along the ground's lattice; where a run of lattice cells is
## level it is laid in one piece at that height, and elsewhere cell by cell, every corner at the
## ground's height there, so it lies on the ground as everything else reads it.
func _drape(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, poly: PackedVector2Array,
		col: Color, mode: int = _DRAPE_SHADED) -> void:
	if poly.size() < 3:
		return
	var g := Ground.NODE
	var box := _box_of(poly)
	for j in range(floori(box.position.y / g), ceili(box.end.y / g)):
		var y0 := float(j) * g
		var row := PackedVector2Array([Vector2(box.position.x - 1.0, y0), Vector2(box.end.x + 1.0, y0),
			Vector2(box.end.x + 1.0, y0 + g), Vector2(box.position.x - 1.0, y0 + g)])
		for piece in Geometry2D.intersect_polygons(poly, row):
			if Geometry2D.is_polygon_clockwise(piece):
				continue
			var pb := _box_of(piece)
			var i0 := floori(pb.position.x / g)
			var i1 := ceili(pb.end.x / g)
			var i := i0
			while i < i1:
				var level := _ground.cell_level(i, j)
				var k := i + 1
				if not is_nan(level):
					while k < i1 and absf(_ground.cell_level(k, j) - level) < 0.001:
						k += 1
				if i == i0 and k == i1:
					_drape_part(verts, cols, idx, piece, col, mode, level, Vector2i(i, j))
				else:
					var cell := PackedVector2Array([Vector2(float(i) * g, y0 - 0.5), Vector2(float(k) * g, y0 - 0.5),
						Vector2(float(k) * g, y0 + g + 0.5), Vector2(float(i) * g, y0 + g + 0.5)])
					for part in Geometry2D.intersect_polygons(piece, cell):
						if not Geometry2D.is_polygon_clockwise(part):
							_drape_part(verts, cols, idx, part, col, mode, level, Vector2i(i, j))
				i = k


## One piece of a draped polygon: at `level` throughout, or where that is NAN on the ground point
## by point, within lattice cell `at`.
func _drape_part(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array, pts: PackedVector2Array,
		col: Color, mode: int, level: float, at: Vector2i, cut: bool = true) -> void:
	var flat := not is_nan(level)
	if flat and cut and mode != _DRAPE_SHADED:
		# The light turns from shade to sun along one line across the board: a level piece is cut
		# there, so neither side's colour is blended across it.
		var across := (_bounds.get_center().y + level * ISO_RISE) / ISO_Y   # x + y of that line in plan
		var lo := INF
		var hi := -INF
		for p in pts:
			lo = minf(lo, p.x + p.y)
			hi = maxf(hi, p.x + p.y)
		if lo < across - 0.01 and hi > across + 0.01:
			var big := 1.0e6
			for side in [-1.0, 1.0]:
				var half := PackedVector2Array([Vector2(across * 0.5, across * 0.5) + Vector2(big, -big),
					Vector2(across * 0.5, across * 0.5) + Vector2(-big, big),
					Vector2(across * 0.5, across * 0.5) + Vector2(-big, big) + Vector2(big, big) * side,
					Vector2(across * 0.5, across * 0.5) + Vector2(big, -big) + Vector2(big, big) * side])
				for part in Geometry2D.intersect_polygons(pts, half):
					if not Geometry2D.is_polygon_clockwise(part):
						_drape_part(verts, cols, idx, part, col, mode, level, at, false)
			return
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	var base := verts.size()
	var cd: Array = [] if flat else _ground.cell(at.x, at.y)
	var corner := Vector2(at) * Ground.NODE
	for p in pts:
		var h := level
		if not flat:
			# Read off the cell, as the ground's height is.
			h = Ground.cell_height(cd, clampf((p.x - corner.x) / Ground.NODE, 0.0, 1.0),
				clampf((p.y - corner.y) / Ground.NODE, 0.0, 1.0))
		var q := iso(p, h)
		verts.append(Vector3(q.x, q.y, 0.0))
		match mode:
			_DRAPE_SEA_LIGHT:
				var t := _light_at(q)
				cols.append(Color(_SEA_PALE.r, _SEA_PALE.g, _SEA_PALE.b, (t - 0.5) * 2.0 * _SEA_PALE_ALPHA) if t >= 0.5
					else Color(_SEA_DEEP.r, _SEA_DEEP.g, _SEA_DEEP.b, (0.5 - t) * 2.0 * _SEA_DEEP_ALPHA))
			_DRAPE_LIGHT:
				cols.append(_light_wash(_light_at(q)))
			_:
				cols.append(col)
	for k in tris:
		idx.append(base + k)


## How much of its colour ground rising by `grad` (height per map unit) keeps: less the steeper it
## is, and most where it faces the sun, as the slopes between tiles have always been shaded.
static func _shade_of(grad: Vector2) -> float:
	var steep := grad.length()
	if steep < Ground.LEVEL_SLOPE:
		return 1.0
	var downhill := -grad / steep
	return 1.0 - clampf(steep / SLOPE_SHADE_FULL, 0.0, 1.0) * (0.2 - 0.16 * maxf(0.0, downhill.dot(_SUN)))


## A tile's shading, multiplied over its ground layer (_draw_grade): every sloping cell of the
## lattice over the tile and its skirts, cut _SHADE_SUB ways each way, each corner as dark as the
## ground's slope there (_shade_of). The slope is read off the ground's smooth spline, so the shading
## runs on smoothly from cell to cell and shows no squares. Level ground keeps its colour.
func _build_shade(hexp: PackedVector2Array, beside: Array) -> ArrayMesh:
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var area := _skirted(hexp, beside)
	var box := _box_of(area)
	var g := Ground.NODE
	var w := _SHADE_SUB + 1
	for j in range(floori(box.position.y / g), ceili(box.end.y / g)):
		for i in range(floori(box.position.x / g), ceili(box.end.x / g)):
			var cd: Array = _ground.cell(i, j)
			if not is_nan(float(cd[0])):
				continue
			var o := Vector2(float(i), float(j)) * g
			var square := PackedVector2Array([o, o + Vector2(g, 0.0), o + Vector2(g, g), o + Vector2(0.0, g)])
			var inside := true
			for q in square:
				inside = inside and Geometry2D.is_point_in_polygon(q, area)
			if inside:
				var base := verts.size()
				for sy in range(w):
					for sx in range(w):
						_shade_vertex(verts, cols, cd, o, sx, sy)
				for sy in range(_SHADE_SUB):
					for sx in range(_SHADE_SUB):
						var a := base + sy * w + sx
						idx.append_array([a, a + 1, a + w + 1, a, a + w + 1, a + w])
				continue
			# A cell at the edge of the tile: its fine squares cut to the tile, each corner read off the cell.
			var step := g / float(_SHADE_SUB)
			for sy in range(_SHADE_SUB):
				for sx in range(_SHADE_SUB):
					var so := o + Vector2(float(sx), float(sy)) * step
					var sub := PackedVector2Array([so, so + Vector2(step, 0.0), so + Vector2(step, step), so + Vector2(0.0, step)])
					for piece in Geometry2D.intersect_polygons(sub, area):
						var tris := Geometry2D.triangulate_polygon(piece)
						if Geometry2D.is_polygon_clockwise(piece) or tris.is_empty():
							continue
						var base := verts.size()
						for p in piece:
							var u := clampf((p.x - o.x) / g, 0.0, 1.0)
							var v := clampf((p.y - o.y) / g, 0.0, 1.0)
							var m := _shade_of(Ground.cell_gradient(cd, u, v))
							var q := iso(p, Ground.cell_height(cd, u, v))
							verts.append(Vector3(q.x, q.y, 0.0))
							cols.append(Color(m, m, m))
						for k in tris:
							idx.append(base + k)
	return _mesh_of(verts, cols, idx)


## One corner (sx, sy) of the fine squares of a sloping cell whose near corner is `o`, its slope read
## off weights worked out once (_shade_weights).
func _shade_vertex(verts: PackedVector3Array, cols: PackedColorArray, cd: Array, o: Vector2, sx: int, sy: int) -> void:
	var tw: Array = _shade_weights()
	var nodes: PackedFloat32Array = cd[1]
	var grad := Vector2(Ground._spline_at(nodes, tw[1][sx], tw[0][sy]), Ground._spline_at(nodes, tw[0][sx], tw[1][sy])) / Ground.NODE
	var m := _shade_of(grad)
	var u := float(sx) / float(_SHADE_SUB)
	var v := float(sy) / float(_SHADE_SUB)
	var q := iso(o + Vector2(u, v) * Ground.NODE, Ground.cell_height(cd, u, v))
	verts.append(Vector3(q.x, q.y, 0.0))
	cols.append(Color(m, m, m))


static var _shade_w: Array = []
## The spline's weights, and their rates of change, at each of the fine squares' corners across a cell.
static func _shade_weights() -> Array:
	if _shade_w.is_empty():
		var w: Array = []
		var dw: Array = []
		for k in range(_SHADE_SUB + 1):
			w.append(Ground._spline(float(k) / float(_SHADE_SUB)))
			dw.append(Ground._spline_slope(float(k) / float(_SHADE_SUB)))
		_shade_w = [w, dw]
	return _shade_w


## A stroke laid on the ground: every corner at the ground's height there.
func _stroke_on(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, width: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_squared_to(b) < 0.01:
			continue
		var along := (b - a).normalized() * width * 0.5
		var side := along.orthogonal()
		var corners := [a - along + side, b + along + side, b + along - side, a - along - side]
		var board: Array = []
		for q in corners:
			board.append(iso(q, _height_at(q)))
		_quad(verts, cols, idx, board[0], board[1], board[2], board[3], col)


## One cut-away wall. `pts` is [[plan point, height]] round its outline; a and b are the ends
## of the tile edge it stands under. The strata texture is one edge wide, and from top to
## bottom spans the slab from the highest tile's top to its foot.
static func _wall(verts: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array,
		idx: PackedInt32Array, pts: Array, a: Vector2, b: Vector2, shade: Color) -> void:
	var board := PackedVector2Array()
	var uv := PackedVector2Array()
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	for e in pts:
		var q := iso(e[0], float(e[1]))
		if not board.is_empty() and board[board.size() - 1].is_equal_approx(q):
			continue
		board.append(q)
		uv.append(Vector2(((e[0] as Vector2) - a).dot(along) / length, (_STRATA_TOP - float(e[1])) / (_STRATA_TOP + SLAB_DEPTH)))
	if board.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(board)
	if tris.is_empty():
		return
	var base := verts.size()
	for i in range(board.size()):
		verts.append(Vector3(board[i].x, board[i].y, 0.0))
		cols.append(shade)
		uvs.append(uv[i])
	for k in tris:
		idx.append(base + k)


## A polyline moved sideways by `off`.
static func _beside(pts: PackedVector2Array, off: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size()):
		var d := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		out.append(pts[i] + d.orthogonal() * off)
	return out


static func _mesh_of(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		uvs: PackedVector2Array = PackedVector2Array()) -> ArrayMesh:
	if idx.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The map's land colour, warmed: the key art's grass is an olive that leans yellow, where
## the map's own green is cooler. Hue is turned toward yellow and the colour deepened a little.
static func _warm(col: Color) -> Color:
	var hue := col.h
	if hue > _WARM_HUE:
		hue = lerpf(hue, _WARM_HUE, _WARM_PULL)
	return Color.from_hsv(hue, minf(1.0, col.s * 1.12 + 0.03), col.v * 0.98, col.a)


static func _quad_cols(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: Array, colours: Array) -> void:
	var base := verts.size()
	for i in range(4):
		verts.append(Vector3((pts[i] as Vector2).x, (pts[i] as Vector2).y, 0.0))
		cols.append(colours[i])
	for i in [0, 1, 2, 0, 2, 3]:
		idx.append(base + i)


## A polygon already in board space.
static func _poly_board(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, col: Color) -> void:
	var clean := PackedVector2Array()
	for p in pts:
		if clean.is_empty() or not clean[clean.size() - 1].is_equal_approx(p):
			clean.append(p)
	if clean.size() > 2 and clean[0].is_equal_approx(clean[clean.size() - 1]):
		clean.remove_at(clean.size() - 1)
	if clean.size() < 3:
		return
	var tris := Geometry2D.triangulate_polygon(clean)
	if tris.is_empty():
		return
	var base := verts.size()
	for p in clean:
		verts.append(Vector3(p.x, p.y, 0.0))
		cols.append(col)
	for k in tris:
		idx.append(base + k)


static func _ground_tex(name: String) -> Texture2D:
	if not _ground_textures.has(name):
		var path := "res://assets/iso/ground/%s.png" % name
		_ground_textures[name] = load(path) if ResourceLoader.exists(path) else null
	return _ground_textures[name]


## How lit a board point is, 0 to 1: brightest nearest the south-east sun.
func _light_at(board: Vector2) -> float:
	var reach := maxf(1.0, absf(_bounds.size.x * _SUN_SCREEN.x) + absf(_bounds.size.y * _SUN_SCREEN.y))
	return clampf(0.5 + (board - _bounds.get_center()).dot(_SUN_SCREEN) / reach, 0.0, 1.0)


## The wash that light lays on the ground: gold toward the sun, a cool shade away from it.
static func _light_wash(t: float) -> Color:
	if t >= 0.5:
		return Color(_GOLD_LIGHT.r, _GOLD_LIGHT.g, _GOLD_LIGHT.b, (t - 0.5) * 2.0 * _LIGHT_GOLD_ALPHA)
	return Color(_COOL_SHADE.r, _COOL_SHADE.g, _COOL_SHADE.b, (0.5 - t) * 2.0 * _LIGHT_SHADE_ALPHA)


## What the same light does to something standing in it.
static func _light_tint(t: float) -> Color:
	return _TINT_SHADE.lerp(_TINT_SUN, t)


## A tile's shoreline: every edge of its land that has open water just beyond it, as
## [[p0, p1, outward normal]]. Worked out once per tile and kept with its relief. The coast
## is not one band's outline: wherever the lowest ground stops short of the water a higher
## band meets it instead, so every band's edges are looked at.
static func _shore_of(rel: Dictionary, hexp: PackedVector2Array) -> Array:
	if rel.has("shore"):
		return rel["shore"]
	var shore: Array = []
	for e in rel.get("land", []):
		var pts: PackedVector2Array = e["p"]
		var signed := 0.0
		for k in range(pts.size()):
			signed += pts[k].x * pts[(k + 1) % pts.size()].y - pts[(k + 1) % pts.size()].x * pts[k].y
		var flip := 1.0 if signed >= 0.0 else -1.0
		for k in range(pts.size()):
			var p0 := pts[k]
			var p1 := pts[(k + 1) % pts.size()]
			if p0.distance_squared_to(p1) < 0.01:
				continue
			var mid := (p0 + p1) * 0.5
			if Ground._on_border(mid, hexp):
				continue
			var out := (p1 - p0).normalized().orthogonal() * flip
			if Ground.is_water(rel, mid + out * 3.0):
				shore.append([p0, p1, out])
	rel["shore"] = shore
	return shore


## A river's runs over land, each carried on through its mouth: past the last point on land to
## the shoreline and on into the open water, where the map draws it running on in the sea's
## own colour. Returns [{pts, cuts}]; `cuts` holds [shore point, outward normal] for each mouth,
## the line along the shore its end is squared off on (see _stroke_to). `coast` is the tile's
## shoreline (_shore_of); `width` the river's.
static func _to_mouth(rel: Dictionary, pts: PackedVector2Array, coast: Array, width: float) -> Array:
	var runs: Array = []
	var wet: Array = []
	for p in pts:
		wet.append(Ground.is_water(rel, p))
	var i := 0
	while i < pts.size():
		if bool(wet[i]):
			i += 1
			continue
		var j := i
		while j + 1 < pts.size() and not bool(wet[j + 1]):
			j += 1
		var run := pts.slice(i, j + 1)
		var cuts: Array = []
		if i > 0:
			var m: Array = _mouth(rel, pts[i], pts[i - 1], coast, width)
			run.insert(0, m[0])
			cuts.append(m[1])
		if j < pts.size() - 1:
			var m2: Array = _mouth(rel, pts[j], pts[j + 1], coast, width)
			run.append(m2[0])
			cuts.append(m2[1])
		if run.size() >= 2:
			runs.append({"pts": run, "cuts": cuts})
		i = j + 1
	return runs


## A river's line with its way into the sea straightened: where it runs from land into water, its last
## _MOUTH_AIM_STRETCH widths before the shore bend round, smoothly, until it crosses the shoreline square on
## (by at most _MOUTH_AIM_MAX). Everything up river of that stretch is left as it is; the line ends at its
## first point in the water.
static func _aim_mouth(rel: Dictionary, line: PackedVector2Array, coast: Array, width: float) -> PackedVector2Array:
	if line.size() < 2 or coast.is_empty():
		return line
	var flipped := Ground.is_water(rel, line[0]) and not Ground.is_water(rel, line[line.size() - 1])
	var pts := PackedVector2Array(line)
	if flipped:
		pts.reverse()
	var wet := -1
	for i in range(1, pts.size()):
		if Ground.is_water(rel, pts[i]) and not Ground.is_water(rel, pts[i - 1]):
			wet = i
			break
	if wet < 0:
		return line
	var m: Array = _mouth(rel, pts[wet - 1], pts[wet], coast, width)
	var at: Vector2 = (m[1] as Array)[0]
	var n: Vector2 = (m[1] as Array)[1]
	var dir := (pts[wet] - pts[wet - 1]).normalized()
	var turn := clampf(dir.angle_to(n), -_MOUTH_AIM_MAX, _MOUTH_AIM_MAX)
	if absf(turn) < deg_to_rad(1.0):
		return line
	# The pivot: the stretch's length up river from the shore.
	var stretch := width * _MOUTH_AIM_STRETCH
	var back := at.distance_to(pts[wet - 1])
	var k := wet - 1
	while k > 0 and back + pts[k].distance_to(pts[k - 1]) < stretch:
		back += pts[k].distance_to(pts[k - 1])
		k -= 1
	var pivot := pts[k]
	if k > 0 and back < stretch:
		pivot = pts[k].lerp(pts[k - 1], clampf((stretch - back) / maxf(pts[k].distance_to(pts[k - 1]), 0.001), 0.0, 1.0))
	var out := pts.slice(0, k)
	out.append(pivot)
	var run := 0.0
	var prev := pivot
	# Only as far as its first point in the water: the sea draws the rest, and a line swung out over the sea
	# could find land again at the tile's edge and open a second mouth there.
	for i in range(k, wet + 1):
		run += prev.distance_to(pts[i])
		prev = pts[i]
		out.append(pivot + (pts[i] - pivot).rotated(turn * smoothstep(0.0, 1.0, run / stretch)))
	if flipped:
		out.reverse()
	return out


## Where a river leaves the land between a point on land and the next in open water:
## [the point its run is carried on to, [shore point, outward normal]]. The normal is the
## shore's own where it crosses, so the river's end lies along the shore, not square across it.
static func _mouth(rel: Dictionary, dry: Vector2, wet: Vector2, coast: Array, width: float) -> Array:
	var lo := dry
	var hi := wet
	for _k in range(16):
		var mid := (lo + hi) * 0.5
		if Ground.is_water(rel, mid):
			hi = mid
		else:
			lo = mid
	var at := (lo + hi) * 0.5
	var dir := (wet - dry).normalized()
	var n := dir
	var best := _MOUTH_SHORE_REACH
	for seg in coast:
		var d := Geometry2D.get_closest_point_to_segment(at, seg[0], seg[1]).distance_to(at)
		if d < best and (seg[2] as Vector2).dot(dir) > 0.1:
			best = d
			n = seg[2]
	# Far enough on that the whole width of the river reaches the line it is cut on.
	var reach := minf((_MOUTH + width) / maxf(n.dot(dir), 0.3), at.distance_to(wet))
	return [at + dir * reach, [at, n]]


## Where a river meets the sea: over its last few widths it flares out, its banks turning to the beach's sand
## and its water paling into the shallows' colour, and at the shoreline it fans on into the sea and fades
## there. Near the shore the flare turns to lie along the shoreline, so both banks reach the beach evenly
## however the river meets it, and what runs out to sea is kept to the open water (`sea`), never the beach.
## `cut` is the mouth ([shore point, outward normal]); `pts` the river's run; `width` its width.
func _estuary(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, cut: Array, width: float, water: Color, hexp: PackedVector2Array,
		sea: Array) -> void:
	var at: Vector2 = cut[0]
	var n: Vector2 = cut[1]
	# The run from the shore upstream: start at the end nearer the mouth, step in to the shore point.
	var path := PackedVector2Array(pts)
	if path[path.size() - 1].distance_to(at) < path[0].distance_to(at):
		path.reverse()
	var up := PackedVector2Array([at])
	for p in path:
		if (p - at).dot(n) < 0.0:           # on the land side of the shore
			up.append(p)
	if up.size() < 2:
		return
	var reach := width * _ESTUARY_UP
	# Stations from upstream (t = 0) to the shore (t = 1), then out to sea (t = 2): [centre, across, width, t],
	# `across` the unit way the width is laid. Up the river it is square to the river; by the shore it lies
	# along the shoreline.
	var along_shore := n.orthogonal()
	var stations: Array = []
	for k in range(_ESTUARY_STEPS + 1):
		var t := float(k) / float(_ESTUARY_STEPS)
		var d := reach * (1.0 - t)
		var c := _point_along(up, d)
		var dir := (_point_along(up, maxf(d - 1.0, 0.0)) - _point_along(up, d + 1.0)).normalized()
		if dir == Vector2.ZERO:
			dir = n
		var square := dir.orthogonal()
		var shore := along_shore if along_shore.dot(square) >= 0.0 else -along_shore
		var across := square.slerp(shore, smoothstep(0.4, 1.0, t)).normalized()
		var w := width * lerpf(1.0, _ESTUARY_SHORE_W, smoothstep(0.0, 1.0, t))
		stations.append([c, across, w, t])
	var shore_across: Vector2 = stations[stations.size() - 1][1]
	for k in range(1, _ESTUARY_STEPS + 1):
		var t := float(k) / float(_ESTUARY_STEPS)
		stations.append([at + n * _ESTUARY_OUT * t, shore_across, width * lerpf(_ESTUARY_SHORE_W, _ESTUARY_SEA_W, t), 1.0 + t])
	var shallows := water.lightened(0.3)
	for k in range(stations.size() - 1):
		var a: Array = stations[k]
		var b: Array = stations[k + 1]
		if not Geometry2D.is_point_in_polygon(((a[0] as Vector2) + (b[0] as Vector2)) * 0.5, hexp):
			continue
		var ta := float(a[3])
		var tb := float(b[3])
		# The banks turn to the beach's sand as they open out, solid, from halfway down to the shore.
		var to_sea := tb > 1.0
		var clip: Array = sea if to_sea else []
		if ta >= 0.5 and not to_sea:
			_estuary_quad(verts, cols, idx, a, b, 1.0, 3.0,
				_BANK.lerp(_SAND, smoothstep(0.5, 1.0, ta)), _BANK.lerp(_SAND, smoothstep(0.5, 1.0, tb)), clip)
		_estuary_quad(verts, cols, idx, a, b, 1.0, 0.0, _estuary_colour(water, shallows, ta), _estuary_colour(water, shallows, tb), clip)
		# The river's paler middle runs on into the mouth and pales with it.
		var middle := water.lightened(0.16)
		_estuary_quad(verts, cols, idx, a, b, 0.45, 0.0, _estuary_colour(middle, shallows, ta), _estuary_colour(middle, shallows, tb), clip)


## The estuary's water at `t`: the river's own colour upstream, paling to the shallows' at the shore, then
## fading out over the sea.
static func _estuary_colour(water: Color, shallows: Color, t: float) -> Color:
	if t <= 1.0:
		return water.lerp(shallows, smoothstep(0.35, 1.0, t))
	return Color(shallows, 1.0 - smoothstep(1.0, 2.0, t))


## One step of the estuary between two stations ([centre, across, width, t]), `scale` times as wide plus
## `pad`, on the ground. With `clip`, only what lies over those polygons is laid, each corner coloured by how
## far along it is.
func _estuary_quad(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		a: Array, b: Array, scale: float, pad: float, col_a: Color, col_b: Color, clip: Array = []) -> void:
	var sa: Vector2 = (a[1] as Vector2) * (float(a[2]) * 0.5 * scale + pad)
	var sb: Vector2 = (b[1] as Vector2) * (float(b[2]) * 0.5 * scale + pad)
	var ca: Vector2 = a[0]
	var cb: Vector2 = b[0]
	if clip.is_empty():
		var corners := [ca + sa, cb + sb, cb - sb, ca - sa]
		var board: Array = []
		for q in corners:
			board.append(iso(q, _height_at(q)))
		_quad_cols(verts, cols, idx, board, [col_a, col_b, col_b, col_a])
		return
	var quad := PackedVector2Array([ca + sa, cb + sb, cb - sb, ca - sa])
	var run := cb - ca
	var span := maxf(run.length_squared(), 0.0001)
	for piece in clip:
		for part in Geometry2D.intersect_polygons(quad, piece):
			var tri := Geometry2D.triangulate_polygon(part)
			if tri.is_empty():
				continue
			var base := verts.size()
			for p in part:
				var p2 := iso(p, _height_at(p))
				verts.append(Vector3(p2.x, p2.y, 0.0))
				cols.append(col_a.lerp(col_b, clampf((p - ca).dot(run) / span, 0.0, 1.0)))
			for k in tri:
				idx.append(base + k)


## The point `d` along a polyline from its start (its end when it is shorter).
static func _point_along(line: PackedVector2Array, d: float) -> Vector2:
	var left := d
	for i in range(line.size() - 1):
		var seg := line[i].distance_to(line[i + 1])
		if left <= seg and seg > 0.0:
			return line[i].lerp(line[i + 1], left / seg)
		left -= seg
	return line[line.size() - 1]


## A stroke along a line whose every point stands at its own height (`hs`), sheared from one to the
## next as a slope projects, cut off at each of `cuts` ([point, outward normal]) a distance `reach`
## beyond it, near that point.
static func _stroke_to(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, width: float, col: Color, cuts: Array, reach: float,
		hs: PackedFloat32Array) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_squared_to(b) < 0.01:
			continue
		var along := (b - a).normalized() * width * 0.5
		var side := along.orthogonal()
		var quad := PackedVector2Array([a - along + side, b + along + side, b + along - side, a - along - side])
		for cut in cuts:
			var at: Vector2 = cut[0]
			var n: Vector2 = cut[1]
			if Geometry2D.get_closest_point_to_segment(at, a, b).distance_to(at) < width + _MOUTH * 6.0:
				quad = Atlas.clip(quad, at + n * reach, -n)
		if quad.size() >= 3:
			_poly_along(verts, cols, idx, quad, a, b, hs[i], hs[i + 1], col)


## A polygon laid along a stretch from `a` (at height ha) to `b` (at hb): each corner at the height
## of the stretch where it lies square across from it.
static func _poly_along(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, a: Vector2, b: Vector2, ha: float, hb: float, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	if tris.is_empty():
		return
	var run := b - a
	var span := maxf(run.length_squared(), 0.000001)
	var base := verts.size()
	for p in pts:
		var q := iso(p, lerpf(ha, hb, clampf((p - a).dot(run) / span, 0.0, 1.0)))
		verts.append(Vector3(q.x, q.y, 0.0))
		cols.append(col)
	for k in tris:
		idx.append(base + k)


## A line over a tile's ground: its points, with every place the ground changes under it added, and
## the height there. Returns [PackedVector2Array, PackedFloat32Array].
func _ground_line(line: PackedVector2Array) -> Array:
	var pts := PackedVector2Array()
	var hs := PackedFloat32Array()
	for i in range(line.size()):
		if i == 0:
			pts.append(line[0])
			hs.append(_height_at(line[0]))
			continue
		var a := line[i - 1]
		var b := line[i]
		if a.distance_to(b) < 0.01:
			continue
		var prof: Array = _profile(a, b)
		for k in range(1, prof.size()):
			pts.append(a.lerp(b, float(prof[k][0])))
			hs.append(float(prof[k][1]))
	return [pts, hs]


## White water where a river falls down a slope: broken foam down the fall, and at its foot a
## bar of foam over a thin line of shadow. Only where the fall is RAPIDS_DROP or more.
static func _white_water(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, hs: PackedFloat32Array, width: float) -> void:
	var i := 0
	while i < pts.size() - 1:
		if absf(hs[i + 1] - hs[i]) < 0.05:
			i += 1
			continue
		var j := i
		while j < pts.size() - 1 and absf(hs[j + 1] - hs[j]) >= 0.05:
			j += 1
		var fall := absf(hs[j] - hs[i])
		if fall >= RAPIDS_DROP:
			# Down the fall: short streaks of foam, staggered either side of the middle.
			var n := 0
			for k in range(i, j):
				var a := pts[k]
				var b := pts[k + 1]
				var length := a.distance_to(b)
				var dir := (b - a) / maxf(length, 0.001)
				var d := 1.5
				while d < length - 1.0:
					var off := dir.orthogonal() * width * (0.18 if n % 2 == 0 else -0.18)
					var p0 := a + dir * d + off
					var p1 := a + dir * minf(d + 4.0, length) + off
					var t0 := d / length
					var t1 := minf(d + 4.0, length) / length
					_poly_along(verts, cols, idx, _bar(p0, p1, width * 0.22), p0, p1,
						lerpf(hs[k], hs[k + 1], t0), lerpf(hs[k], hs[k + 1], t1), _FOAM)
					d += 6.5
					n += 1
			# The foot: the lower end of the fall, which may be the tile's own edge, so the mark is
			# laid just up the fall from it.
			var foot := j if hs[j] < hs[i] else i
			var up := foot - 1 if foot == j else foot + 1
			var back := pts[up] - pts[foot]
			var run := maxf(back.length(), 0.001)
			var across := back.orthogonal().normalized() * width * 0.62
			for mark in [[1.0, 1.0, _INK_SOFT], [3.5, 3.0, _FOAM]]:
				var d := minf(float(mark[0]), run)
				var at := pts[foot] + back / run * d
				_stroke(verts, cols, idx, PackedVector2Array([at - across, at + across]), float(mark[1]),
					lerpf(hs[foot], hs[up], d / run), mark[2])
		i = j


## A bar of the given width along a stretch, as a polygon.
static func _bar(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var side := (b - a).normalized().orthogonal() * width * 0.5
	return PackedVector2Array([a + side, b + side, b - side, a - side])


## Points on a tile's water for the sun to catch. Fixed for the tile: the water never moves.
func _seed_glints(tile_id: String, t: Dictionary, rel: Dictionary, is_sea: bool) -> void:
	if not _glint_cache.has(tile_id):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("glint|" + tile_id)
		var c: Vector2 = t["center"]
		var found: Array = []
		for _try in range(140):
			if found.size() >= _GLINTS_PER_TILE:
				break
			var p := c + Vector2(rng.randf_range(-270.0, 270.0), rng.randf_range(-240.0, 240.0))
			if not Geometry2D.is_point_in_polygon(p, Model.hex_points(c)):
				continue
			if is_sea or Ground.is_water(rel, p):
				found.append([p, rng.randf() * TAU, rng.randf_range(0.7, 1.3)])
		_glint_cache[tile_id] = found
	for g in _glint_cache[tile_id]:
		_glints.append({"at": iso(g[0], _height_at(g[0])), "phase": float(g[1]), "rate": float(g[2])})


static func _quad(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	var base := verts.size()
	for p in [a, b, c, d]:
		verts.append(Vector3(p.x, p.y, 0.0))
		cols.append(col)
	for i in [0, 1, 2, 0, 2, 3]:
		idx.append(base + i)


static func _stroke(verts: PackedVector3Array, cols: PackedColorArray, idx: PackedInt32Array,
		pts: PackedVector2Array, width: float, h: float, col: Color) -> void:
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		if a.distance_squared_to(b) < 0.01:
			continue
		var along := (b - a).normalized() * width * 0.5
		var side := along.orthogonal()
		_quad(verts, cols, idx, iso(a - along + side, h), iso(b + along + side, h),
			iso(b + along - side, h), iso(a - along - side, h), col)


func _build_standing() -> void:
	for s in _model.get("standing", []):
		if str(s["kind"]) == "pylon" and not bool(show["cables"]):
			continue
		var d: Dictionary = (s as Dictionary).duplicate()
		var pos: Vector2 = d["pos"]
		var side := float(d["side"])
		var h := _height_at(pos)
		if str(d["kind"]) != "pylon" and not (_mine_flush(str(d.get("internal_name", "")), int(d["level"])) != null):
			# A building stands level on the highest ground of its footprint: where that ground
			# is not level, on a plinth down to it.
			var foot: Array = []
			var low := h
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
				var ch := _height_at(pos + corner * side * 0.5)
				foot.append(ch)
				h = maxf(h, ch)
				low = minf(low, ch)
			if h - low > PLINTH_MIN:
				d["plinth"] = foot
		d["h"] = h
		d["at"] = iso(pos, h)
		d["tint"] = _light_tint(_light_at(d["at"]))
		d["depth"] = pos.x + pos.y
		var tex: Texture2D = d.get("sprite")
		if tex != null:
			# The sprite's content is as wide as its footprint's diamond, and its lowest point is
			# the diamond's front corner.
			var used: Rect2 = Model.BuildingSprites.content_rect(tex)
			# The frame, not the content, is what the slot's footprint scales: a level set shares
			# one scale, so the lower levels sit smaller inside the same frame.
			var k := side * 2.0 * ISO_X / (float(tex.get_width()) * SPRITE_FILL)
			if bool(d.get("tall", false)):
				# A tower's frame is filled by its height, not its footprint: scale by what is drawn.
				k = side * 2.0 * ISO_X / used.size.x
			side = used.size.x * k / (2.0 * ISO_X)
			d["side"] = side
			var front: Vector2 = (d["at"] as Vector2) + Vector2(0.0, side * ISO_Y)
			if str(d["kind"]) == "pylon":
				# A pylon stands on its feet, which are far narrower than its arms.
				front = (d["at"] as Vector2) + Vector2(0.0, side * 0.12)
			var origin := Vector2(front.x - (used.position.x + used.size.x * 0.5) * k,
				front.y - used.end.y * k)
			d["tex_rect"] = Rect2(origin, Vector2(tex.get_width(), tex.get_height()) * k)
			d["rect"] = Rect2(origin + used.position * k, used.size * k)
			# A mine is a hole in the board's own ground: its sprite without the block of earth
			# it is cut into, set down by that block's height so the pit's rim is at ground level.
			var flush: Texture2D = _mine_flush(str(d.get("internal_name", "")), int(d["level"]))
			if flush != null:
				var sink := float(_mine_drop.get(str(clampi(int(d["level"]), 1, 3)), 0.0)) \
					* float(tex.get_width()) / float(_mine_frame) * k
				d["sprite"] = flush
				d["sunk"] = true
				d["tex_rect"] = Rect2(origin + Vector2(0.0, sink), Vector2(tex.get_width(), tex.get_height()) * k)
			# Its windows and fires, lit where the air on its tile is dirty.
			var tile_d: Dictionary = (_model["tiles"] as Dictionary).get(d["tile"], {})
			# A mine's lamps are down its shaft, which on the board is under the ground.
			if int(tile_d.get("polluters", 0)) > 0 and str(d["kind"]) != "pylon" and not bool(d.get("sunk", false)):
				var win: Texture2D = _window_mask(tex)
				if win != null:
					_lights.append({"tex": win, "rect": d["tex_rect"], "phase": float(_lights.size()) * 1.7,
						"col": _WINDOW_LIGHT})
				var fire: Texture2D = EmpireFx.light_mask_for(str(d.get("internal_name", "")),
					EmpireFx.anchor_level(str(d.get("internal_name", "")), int(d["level"])))
				if fire != null and str(d["kind"]) == "building":
					_lights.append({"tex": fire, "rect": d["tex_rect"], "col": EmpireFx.FIRE_CORE,
						"phase": float(_lights.size()) * 1.7})
			# Its chimneys, from the same table the node view's plumes use. Grey smoke where the
			# works is dirty, white steam where it is not.
			if str(d["kind"]) == "building":
				var anchors: Dictionary = EmpireFx.anchors_for(str(d.get("internal_name", "")), int(d["level"]))
				var px := float(tex.get_width()) / EmpireFx.SPRITE_PX * k
				for st in anchors.get("stacks", []):
					var kind := str((st as Dictionary).get("kind", "auto"))
					_stacks.append({"at": origin + Vector2(float(st["x"]), float(st["y"])) * px,
						"r": float(st["r"]) * px, "phase": fmod(float(_stacks.size()) * 0.37, 1.0),
						"smoke": kind == "smoke" or (kind == "auto" and bool(d.get("polluting", false)))})
		else:
			var rise := side * (1.6 if str(d["kind"]) == "pylon" else 0.6)
			var top := iso(pos, h + rise)
			d["rect"] = Rect2(top.x - side * ISO_X, top.y - side * ISO_Y,
				side * 2.0 * ISO_X, side * 2.0 * ISO_Y + rise * ISO_RISE)
			if str(d["kind"]) == "pylon":
				d["rect"] = Rect2(top.x - side * 0.3, top.y, side * 0.6, rise * ISO_RISE)
		_standing.append(d)
	_standing.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["depth"]) < float(b["depth"]))


static var _mine_tex: Dictionary = {}
static var _mine_drop: Dictionary = {}
static var _mine_frame := 800


## The ground-level picture of a mine at this level, or null for anything that is not a mine.
static func _mine_flush(internal_name: String, level: int) -> Texture2D:
	if internal_name != "mine":
		return null
	if _mine_drop.is_empty():
		var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(_MINE_DIR + "mine_flush.json"))
		if meta is Dictionary:
			_mine_drop = (meta as Dictionary).get("drop", {})
			_mine_frame = int((meta as Dictionary).get("frame", 800))
	var lv := clampi(level, 1, 3)
	if not _mine_tex.has(lv):
		var path := "%smine_flush_lvl%d.png" % [_MINE_DIR, lv]
		_mine_tex[lv] = load(path) if ResourceLoader.exists(path) else null
	return _mine_tex[lv] if not _mine_drop.is_empty() else null


func _build_lines(gen: int) -> void:
	var tiles: Dictionary = _model.get("tiles", {})
	var by_iid: Dictionary = {}
	for s in _standing:
		by_iid[str(s["iid"])] = s
	await _build_roads(tiles, gen)
	if gen != _build_gen:
		return
	var laid_track: Dictionary = {}
	# Any way that cannot follow the streets (two tiles that do not touch) is a plain line.
	for l in _model.get("lines", []):
		await _pace()
		if gen != _build_gen:
			return
		var mode := str(l["mode"])
		if mode == Model.MODE_CABLE or Model.PIPE_MODES.has(mode):
			continue
		if str(l.get("kind", "")) == "track":
			_lay_track(l["pts"], laid_track)
			continue
		var pts := PackedVector2Array()
		for node in l["pts"]:
			pts.append(iso(node["p"], _ground_h(node)))
		_links.append({"mode": mode, "pts": pts, "tile": str(l["pts"][0]["tile"])})

	# Pipes, laid from baked pieces on a grid of directions; each end goes into the ground.
	# Two goods piped the same way along the same line share ONE pipe for as far as they run
	# together: the second is not laid over the first, it joins it, and the sign on that
	# stretch shows both.
	var kit: bool = Pipes.ready()
	var stretches: Array = []                 # [{a, b, mode, tile, goods}] what is laid, along the flow
	for l in _model.get("lines", []):
		var mode := str(l["mode"])
		if not Model.PIPE_MODES.has(mode) or not bool(show[mode]):
			continue
		var path: Array = (l["pts"] as Array).duplicate()
		if bool(l.get("reverse", false)):
			path.reverse()                        # now in the order its contents flow
		var good := str(l.get("good", ""))
		for part in _unlaid(path, mode, good, stretches):
			var nodes: Array = part["nodes"]
			for n in range(nodes.size() - 1):
				var a: Vector2 = nodes[n]["p"]
				var b: Vector2 = nodes[n + 1]["p"]
				if a.distance_to(b) > 0.5:
					stretches.append({"a": a, "b": b, "mode": mode, "tile": str(nodes[n]["tile"]), "goods": [good]})
			if kit:
				var legs: Array = Pipes.plan(_pipe_waypoints(nodes))
				if legs.is_empty():
					continue
				var laid: Dictionary = Pipes.lay(legs, _road_plan, "s" if mode == "reinf_pipes" else "c", part["enter"])
				for item in laid["items"]:
					if str(item["kind"]) == "fit":
						_pipe_items.append(item)
						continue
					# A run is drawn tile by tile, so each tile takes its own place in depth.
					for poly in Pipes.kit().run_polys(item):
						poly["kind"] = "run"
						_pipe_items.append(poly)
			else:
				var plain := PackedVector2Array()
				for node in nodes:
					plain.append(iso(node["p"], _ground_h(node) + 4.0))
				_pipes.append({"mode": mode, "pts": plain, "tile": str(nodes[0]["tile"])})
	# A sign at the start of every stretch whose contents differ from the stretch before it.
	for st in stretches:
		var a: Vector2 = st["a"]
		var b: Vector2 = st["b"]
		var length := a.distance_to(b)
		if length < _SIGN_MIN_RUN:
			continue
		var goods: Array = st["goods"]
		var carried_on := false
		for other in stretches:
			if (other["b"] as Vector2).distance_to(a) < 1.0 and other != st and _same_goods(other["goods"], goods) \
					and ((other["b"] as Vector2) - (other["a"] as Vector2)).normalized().dot((b - a) / length) > 0.3:
				carried_on = true
		if carried_on:
			continue
		var at: Vector2 = a.lerp(b, clampf(20.0 / length, 0.0, 0.5))
		var side := ((b - a) / length).orthogonal()
		if side.x + side.y < 0.0:
			side = -side
		var foot: Vector2 = at + side * _SIGN_OFFSET
		var gh := _height_at(foot)
		var icons: Array = []
		for g in goods:
			if str(g) != "":
				icons.append(Model.GoodIcons.texture_for(str(g), Model._internal_name(str(g))))
		if icons.is_empty():
			continue
		_signs.append({"foot": iso(foot, gh), "top": iso(foot, gh + _SIGN_POST), "icons": icons,
			"depth": foot.x + foot.y, "tile": str(st["tile"])})

	# Cables hang from a building to its tile's pylon and from pylon to pylon.
	for l in _model.get("lines", []):
		if str(l["mode"]) != Model.MODE_CABLE or not bool(show["cables"]):
			continue
		var pts := _cable_between(by_iid, l["ids"])
		if pts.size() >= 2:
			_cables.append(pts)

	_signs.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["depth"]) < float(y["depth"]))
	_pipe_items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["depth"]) < float(y["depth"]))

	var n := 0
	for f in _model.get("flows", []):
		var mode := str(f["mode"])
		var pts := PackedVector2Array()
		if mode == Model.MODE_CABLE:
			pts = _cable_between(by_iid, f["ids"])
			if bool(f.get("reverse", false)):
				pts.reverse()
		elif Model.PIPE_MODES.has(mode):
			# What is in a pipe is shown on the pipe itself, not as crates along the way.
			continue
		else:
			pts = _street_line(f["pts"])
		if pts.size() < 2:
			continue
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + pts[i].distance_to(pts[i - 1]))
		var total := cum[cum.size() - 1]
		if total < 1.0:
			continue
		_flows.append({"pts": pts, "cum": cum, "total": total, "icon": f["icon"],
			"good": f["good"], "kind": str(f["kind"]), "live": f.get("live", []),
			"style": "power" if mode == Model.MODE_CABLE else "goods",
			"phase": fmod(float(n) * 0.618034, 1.0) * _TOKEN_SPACING})
		n += 1


## The air darkened by dirt, as a thin mist that hangs over things and does not hide them.
## It is patchy: many soft-edged wisps of different sizes and strengths, drifting. Round each
## dirty works a small bank of it; and over a tile with more than one of them a wider, darker
## bank, at full strength across the tile to a tenth of a tile inside its edge, thinning from
## there, and gone a quarter of a tile into a clean neighbour.
func _build_fog() -> void:
	_fog.clear()
	var tiles: Dictionary = _model.get("tiles", {})
	for s in _standing:
		if not bool(s.get("polluting", false)):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("fog|" + str(s["iid"]))
		var h := float(s["h"])
		# A few uneven arms of mist, each its own length and leaning downwind, with the wisps
		# strung along them and thinning toward the arm's end. A ring of wisps round the works
		# would fade to a circle; this has no outline to fade to.
		var arms: Array = []
		for _a in range(_FOG_ARMS):
			arms.append([_FOG_WIND.angle() + rng.randf_range(-1.5, 1.5), rng.randf_range(0.45, 1.35) * _FOG_WORKS_REACH])
		for _n in range(_FOG_PER_WORKS):
			var arm: Array = arms[rng.randi() % arms.size()]
			var along := pow(rng.randf(), 0.75)
			var dir := Vector2.from_angle(float(arm[0]))
			var p: Vector2 = (s["pos"] as Vector2) + dir * along * float(arm[1]) \
				+ dir.orthogonal() * rng.randf_range(-1.0, 1.0) * (14.0 + 26.0 * along)
			_fog.append({"at": iso(p, h + rng.randf_range(8.0, 34.0)), "r": rng.randf_range(30.0, 82.0),
				"a": rng.randf_range(0.35, 1.0) * (1.0 - 0.6 * along) * _FOG_WORKS_ALPHA, "phase": rng.randf() * TAU})
	var by_center: Dictionary = {}
	for tid in tiles:
		by_center[Vector2i((tiles[tid]["center"] as Vector2).round())] = tid
	var inset := _SMOG_INSET * _TILE_SPAN
	var spill := _SMOG_SPILL * _TILE_SPAN
	for tid in tiles:
		var t: Dictionary = tiles[tid]
		if int(t.get("polluters", 0)) < 2:
			continue
		var c: Vector2 = t["center"]
		var hexp := Model.hex_points(c)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("pall|" + str(tid))
		for _n in range(_FOG_PER_TILE):
			var p := c + Vector2(rng.randf_range(-270.0 - spill, 270.0 + spill), rng.randf_range(-240.0 - spill, 240.0 + spill))
			var r := rng.randf_range(48.0, 120.0)
			var strength := rng.randf_range(0.4, 1.0)
			var lift := rng.randf_range(10.0, 44.0)
			var phase := rng.randf() * TAU
			# How far outside the tile the wisp is; inside counts as negative.
			var d := INF
			for i in range(6):
				d = minf(d, Geometry2D.get_closest_point_to_segment(p, hexp[i], hexp[(i + 1) % 6]).distance_to(p))
			var within := Geometry2D.is_point_in_polygon(p, hexp)
			if within:
				d = -d
			var f := clampf(1.0 - (d + inset) / (inset + spill), 0.0, 1.0)
			if f <= 0.02:
				continue
			var h := float(t["height"])
			if not within:
				# Beyond the edge it lies over whatever tile is drawn there, and stops short of
				# one that has a pall of its own.
				var over: Variant = null
				for other in tiles:
					if other != tid and Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[other]["center"])):
						over = other
				if over == null or int(tiles[over].get("polluters", 0)) >= 2:
					continue
				h = float(tiles[over]["height"])
			_fog.append({"at": iso(p, h + lift), "r": r, "a": strength * f * _FOG_TILE_ALPHA, "phase": phase})


## Street lamps along the streets in use, a pool of light before each works, and the glow of
## lit windows. The posts stand on every tile and are part of its picture. The light is drawn
## live, added to what is under it, and only on a tile whose air is dirty: it is daylight, and
## lamps are lit where the smog has made it dark.
func _build_lamps() -> void:
	_glows.clear()
	if not plate_lamps or not bool(show["roads"]):
		return
	var tiles: Dictionary = _model.get("tiles", {})
	for r in _model.get("roads", []):
		if str(r["kind"]) == "spur":
			continue
		var a: Vector2 = r["a"]
		var b: Vector2 = r["b"]
		var length := a.distance_to(b)
		var n := int(length / _LAMP_GAP)
		if n < 1:
			continue
		var tile := str(r["tile"])
		var dir := (b - a) / length
		# On the far side of the street, so the post stands behind the road it lights.
		var side := dir.orthogonal()
		if side.x + side.y > 0.0:
			side = -side
		var off := (_ROAD_HALF + 5.0) if int(r["level"]) > 1 else (_DRIVE_HALF + 4.0)
		var rel: Dictionary = _relief_cache.get(tile, {})
		for i in range(n):
			var p := a + dir * ((float(i) + 0.5) * length / float(n)) + side * off
			if not Geometry2D.is_point_in_polygon(p, Model.hex_points(tiles[tile]["center"])):
				continue
			if Ground.is_water(rel, p):
				continue                          # no lamp stands in the sea
			var h := _height_at(p)
			var foot := iso(p, h)
			var head := iso(p - side * 3.0, h + _LAMP_HEIGHT)
			var lit := int(tiles[tile].get("polluters", 0)) > 0
			_pipe_items.append({"kind": "lamp", "foot": foot, "head": head, "depth": p.x + p.y, "tile": tile, "lit": lit})
			if not lit:
				continue
			var dark := 1.0 - _light_at(foot)
			_glows.append({"at": iso(p - side * (off * 0.7), h), "rx": 30.0, "ry": 17.0, "a": 0.20 + 0.34 * dark})
			_glows.append({"at": head, "rx": 7.0, "ry": 7.0, "a": 0.55 + 0.35 * dark})
	for s in _standing:
		if not (str(s["kind"]) in ["building", "warehouse", "house", "port"]) \
				or int(tiles[str(s["tile"])].get("polluters", 0)) <= 0:
			continue
		var dark := 1.0 - _light_at(s["at"])
		var side_len := float(s["side"])
		# The yard before it, toward the street, and a softer bloom over its lit windows.
		_glows.append({"at": iso((s["pos"] as Vector2) + Vector2(0.0, side_len * 0.62), float(s["h"])),
			"rx": side_len * 0.85, "ry": side_len * 0.46, "a": (0.16 + 0.30 * dark) * (0.6 if str(s["kind"]) == "house" else 1.0)})
		var r2: Rect2 = s["rect"]
		_glows.append({"at": r2.get_center() + Vector2(0.0, r2.size.y * 0.12), "rx": r2.size.x * 0.5, "ry": r2.size.y * 0.42,
			"a": 0.07 + 0.16 * dark})


## Cars on the streets in use: each stretch carries a few, keeping to the left, at their own pace.
func _build_cars() -> void:
	_cars.clear()
	if not plate_town or not bool(show["roads"]) or not _car_kit().ok():
		return
	var n := 0
	for r in _model.get("roads", []):
		var a: Vector2 = r["a"]
		var b: Vector2 = r["b"]
		var length := a.distance_to(b)
		if str(r["kind"]) == "spur" or length < _CAR_GAP * 0.6:
			continue
		var tile := str(r["tile"])
		var dir := (b - a) / length
		var lane := dir.orthogonal() * (2.6 if int(r["level"]) == 1 else 4.2)
		for way in [1.0, -1.0]:
			# One car to a stretch each way, more on a long one, none where the seed says so.
			for i in range(maxi(1, int(length / _CAR_GAP))):
				n += 1
				if hash("car|%d" % n) % 5 < 2:
					continue
				var from: Vector2 = (a if way > 0.0 else b) - lane * float(way)
				var to: Vector2 = (b if way > 0.0 else a) - lane * float(way)
				# Its way over the ground, as board points and how far along each lies.
				var way_pts := PackedVector2Array()
				var shares := PackedFloat32Array()
				for q in _profile(from, to, tile):
					way_pts.append(iso(from.lerp(to, float(q[0])), float(q[1]) + 1.0))
					shares.append(float(q[0]))
				_cars.append({"pts": way_pts, "shares": shares, "length": length,
					"k": Pipes.k_of(dir * float(way)), "colour": hash("paint|%d" % n) % 4,
					"phase": float(hash("start|%d" % n) % 1000) / 1000.0, "pace": _CAR_SPEED * (0.8 + 0.4 * float(n % 5) / 4.0)})


static var _cars_atlas: Atlas = null
static func _car_kit() -> Atlas:
	if _cars_atlas == null:
		_cars_atlas = Atlas.new("cars")
	return _cars_atlas


func _draw_cars(layer: Control, view: Rect2) -> void:
	var kit: Atlas = _car_kit()
	var tex: Texture2D = kit.texture()
	if tex == null:
		return
	var ppu := kit.px_per_unit()
	for c in _cars:
		var t := fmod(float(c["phase"]) + _clock * float(c["pace"]) / float(c["length"]), 1.0)
		var way_pts: PackedVector2Array = c["pts"]
		var shares: PackedFloat32Array = c["shares"]
		var k := 0
		while k < shares.size() - 2 and shares[k + 1] < t:
			k += 1
		var at := way_pts[k].lerp(way_pts[k + 1], clampf((t - shares[k]) / maxf(shares[k + 1] - shares[k], 0.0001), 0.0, 1.0))
		var p := at * _zoom + _offset
		if not view.has_point(p):
			continue
		var src := kit.cell("car_%d_%d" % [int(c["colour"]), int(c["k"])])
		var half := src.size.x * 0.5 / ppu * _zoom
		# A car fades in and out at the ends of its stretch, where it meets a junction.
		var fade := clampf(minf(t, 1.0 - t) * 8.0, 0.0, 1.0)
		layer.draw_texture_rect_region(tex, Rect2(p - Vector2(half, half), Vector2(half, half) * 2.0), src,
			Color(1.0, 1.0, 1.0, fade))


## Trees: some scattered over each tile, some along the roads. Where a tile's trees might stand
## is fixed for the tile, so its baked picture holds from turn to turn; which of those places
## show depends on what is built and which roads are in use.
func _build_trees() -> void:
	if not bool(show["trees"]):
		return
	var tiles: Dictionary = _model.get("tiles", {})
	var used: Dictionary = {}                 # "tile|a|b" -> the road's half-width
	var roads_kit: Atlas = _road_kit()
	for r in _model.get("roads", []):
		var ia: String = Streets.nid((r["a"] as Vector2) - (tiles[str(r["tile"])]["center"] as Vector2))
		var ib: String = Streets.nid((r["b"] as Vector2) - (tiles[str(r["tile"])]["center"] as Vector2))
		used["%s|%s|%s" % [str(r["tile"]), ia if ia < ib else ib, ib if ia < ib else ia]] = true
	var pads: Dictionary = {}                 # tile -> [Rect2] in plan
	for s in _standing:
		# A mine's worked ground is wider than its slot, and no tree stands on it.
		var half := float(s.get("pad", float(s["side"]))) * 0.5 + (34.0 if bool(s.get("sunk", false)) else 8.0)
		(pads.get_or_add(str(s["tile"]), []) as Array).append(
			Rect2((s["pos"] as Vector2) - Vector2(half, half), Vector2(half, half) * 2.0))
	var pipe_segs: Array = []
	for l in _model.get("lines", []):
		if Model.PIPE_MODES.has(str(l["mode"])):
			for i in range((l["pts"] as Array).size() - 1):
				pipe_segs.append([l["pts"][i]["p"], l["pts"][i + 1]["p"]])
	for tid in tiles:
		var t: Dictionary = tiles[tid]
		var kind := str(t["type"])
		if kind == "sea" or kind == "deep_sea" or kind == "mountain":
			continue
		var c: Vector2 = t["center"]
		var spots: Array = _tree_spots(str(tid), kind)
		var rel: Dictionary = _relief_cache.get(tid, {})
		var hexp := Model.hex_points(c)
		for spot in spots:
			var p: Vector2 = c + (spot["p"] as Vector2)
			if str(spot["edge"]) != "" and not used.has("%s|%s" % [str(tid), str(spot["edge"])]):
				continue
			if not Geometry2D.is_point_in_polygon(p, hexp):
				continue
			var blocked := false
			for pad in pads.get(tid, []):
				blocked = blocked or (pad as Rect2).has_point(p)
			for r in _road_plan:
				blocked = blocked or Geometry2D.get_closest_point_to_segment(p, r["a"], r["b"]).distance_to(p) < float(r["half"]) + 4.0
			for seg in pipe_segs:
				blocked = blocked or Geometry2D.get_closest_point_to_segment(p, seg[0], seg[1]).distance_to(p) < 9.0
			blocked = blocked or Ground.is_water(rel, p)
			for line in _rivers.get(tid, []):
				var river: PackedVector2Array = line
				for i in range(river.size() - 1):
					blocked = blocked or Geometry2D.get_closest_point_to_segment(p, river[i], river[i + 1]).distance_to(p) < 16.0
			if blocked:
				continue
			var name := str(spot["kind"])
			var tex: Texture2D = _tree_texture(name)
			if tex == null:
				continue
			var tall := float(_TREE_HEIGHT[name]) * float(spot["scale"])
			var wide := tall * float(tex.get_width()) / float(tex.get_height())
			var foot := iso(p, _height_at(p))
			_pipe_items.append({"kind": "tree", "tex": tex, "depth": p.x + p.y, "tile": str(tid),
				"rect": Rect2(foot.x - wide * 0.5, foot.y - tall * 0.96, wide, tall),
				"tint": _light_tint(_light_at(foot))})
	_pipe_items.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["depth"]) < float(y["depth"]))


## Every place a tree might stand on a tile, relative to the tile's centre:
## [{p, kind, scale, edge}], `edge` naming the stretch of street a roadside tree lines.
static func _tree_spots(tile_id: String, tile_type: String) -> Array:
	var kept: Dictionary = _tree_cache
	if kept.has(tile_id):
		return kept[tile_id]
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("trees|" + tile_id)
	var hilly := tile_type == "hill"
	var kinds: Array = ["fir"] if hilly else ["large", "small", "large", "fir", "small"]
	var spots: Array = []
	var hexp := Model.hex_points(Vector2.ZERO)
	var want := _TREES_PER_TILE / (2 if hilly else 1)
	for _try in range(want * 4):
		if spots.size() >= want:
			break
		var p := Vector2(rng.randf_range(-260.0, 260.0), rng.randf_range(-230.0, 230.0))
		if Geometry2D.is_point_in_polygon(p / 0.94, hexp):
			spots.append({"p": p, "kind": kinds[rng.randi() % kinds.size()], "scale": rng.randf_range(0.82, 1.15), "edge": ""})
	for e in Streets.edges():
		var a: Vector2 = Streets.node_pos(str(e[0]))
		var b: Vector2 = Streets.node_pos(str(e[1]))
		var length := a.distance_to(b)
		if Streets.kind_of(str(e[0]), str(e[1])) == "spur" or length < _ROADSIDE_GAP:
			continue
		var dir := (b - a) / length
		var n := int(length / _ROADSIDE_GAP)
		for i in range(n):
			for side in [-1.0, 1.0]:
				if rng.randf() > _ROADSIDE_KEEP:
					continue
				var at := a + dir * ((float(i) + 0.5) * length / float(n)) + dir.orthogonal() * float(side) * 21.0
				spots.append({"p": at, "kind": "small" if not hilly else "fir", "scale": rng.randf_range(0.8, 1.0),
					"edge": str(e[0]) + "|" + str(e[1])})
	kept[tile_id] = spots
	return spots


static func _tree_texture(kind: String) -> Texture2D:
	if not _tree_tex.has(kind):
		var path := "%stree_%s.png" % [_TREE_DIR, kind]
		_tree_tex[kind] = load(path) if ResourceLoader.exists(path) else null
	return _tree_tex[kind]


## The streets in use, as baked pieces: a junction piece wherever roads meet, turn or change
## width, straights between them, and a truss bridge where a street crosses a river.
func _build_roads(tiles: Dictionary, gen: int) -> void:
	_road_plan.clear()
	var roads: Atlas = _road_kit()
	var segs: Array = _model.get("roads", [])
	var nodes: Dictionary = {}                # rounded plan point -> {p, arms: {k: {level, h, paved}}}
	for s in segs:
		var level := int(s["level"])
		var ends: Array = [s["a"], s["b"]]
		for e in range(2):
			var here: Vector2 = ends[e]
			var there: Vector2 = ends[1 - e]
			var nd: Dictionary = nodes.get_or_add(Vector2i(here.round()), {"p": here, "arms": {}})
			var k: int = Pipes.k_of(there - here)
			var arms: Dictionary = nd["arms"]
			if not arms.has(k) or int(arms[k]["level"]) < level:
				arms[k] = {"level": level, "h": _way_h(str(s["tile"]), here), "paved": bool(s["paved"]),
					"tile": str(s["tile"]), "sloped": not _level_round(str(s["tile"]), here, roads.dim("arm"))}
		_road_plan.append({"a": s["a"], "b": s["b"],
			"half": roads.dim("half_%d" % level) + roads.dim("walk_%d" % level) if roads.ok() else _ROAD_HALF})
	if not roads.ok():
		# The pieces are not baked: plain lines instead.
		for s in segs:
			_links.append({"mode": "roads" if str(s["kind"]) != "spur" else Model.MODE_DRIVE, "tile": str(s["tile"]),
				"pts": _street_line([{"p": s["a"], "tile": s["tile"], "edge": false}, {"p": s["b"], "tile": s["tile"], "edge": false}])})
		return
	var arm := roads.dim("arm")
	var pieced: Dictionary = {}               # node key -> true: a junction piece stands there
	for key in nodes:
		var nd: Dictionary = nodes[key]
		var arms: Dictionary = nd["arms"]
		var ks: Array = arms.keys()
		ks.sort()
		if ks.size() < 2:
			continue
		var h0 := float(arms[ks[0]]["h"])
		var level_ground := true
		var paved := true
		for k in ks:
			level_ground = level_ground and absf(float(arms[k]["h"]) - h0) < 0.05 and not bool(arms[k]["sloped"])
			paved = paved and bool(arms[k]["paved"])
		var straight := ks.size() == 2 and posmod(int(ks[0]) + 6, 12) == int(ks[1])
		if not level_ground:
			# The ground is not level here: the roads run on up or down the slope, and no flat
			# piece would lie on it. Where they turn, the corner between them is filled with road.
			if not straight:
				_road_joint(roads, nd, arms, ks, paved)
			continue
		if straight and int(arms[ks[0]]["level"]) == int(arms[ks[1]]["level"]):
			continue                              # straight on at one width: no piece
		var parts: Array = []
		for k in ks:
			parts.append("%d.%d" % [int(k), int(arms[k]["level"])])
		var name := "r_j_" + "_".join(parts)
		if not roads.has(name):
			_road_joint(roads, nd, arms, ks, paved)
			continue
		pieced[key] = true
		_road_fits.append({"name": name, "at": iso(nd["p"], h0), "tint": Color.WHITE if paved else _UNPAVED,
			"tile": str(arms[ks[0]]["tile"])})
	for s in segs:
		await _pace()
		if gen != _build_gen:
			return
		var tile := str(s["tile"])
		var a: Vector2 = s["a"]
		var b: Vector2 = s["b"]
		var length := a.distance_to(b)
		var dir := (b - a) / maxf(length, 0.001)
		# A straight runs a little way under each junction piece, so the piece's cut ends are hidden.
		var from := (arm - _ROAD_OVERLAP) if pieced.has(Vector2i(a.round())) else 0.0
		var to := length - ((arm - _ROAD_OVERLAP) if pieced.has(Vector2i(b.round())) else 0.0)
		var level := int(s["level"])
		# Where it leaves for a tile drawn beside, it runs on under that tile's own road, past the edge of
		# that tile's skirt of ground however slantwise it crosses the edge.
		var under := _SKIRT + roads.dim("half_%d" % level) + _ROAD_OVERLAP
		var road_half := roads.dim("half_%d" % level) + roads.dim("walk_%d" % level)
		if _at_shared_edge(tile, a):
			from = -under
			_road_lit(tile, a, -dir, road_half, under)
		if _at_shared_edge(tile, b):
			to = length + under
			_road_lit(tile, b, dir, road_half, under)
		if to - from < 0.5:
			continue
		var k6 := posmod(Pipes.k_of(dir), 6)
		var tint: Color = Color.WHITE if bool(s["paved"]) else _UNPAVED
		var piece := "r_straight_%d_%d" % [k6, level]
		var step := iso(Pipes.dir_of(k6) * roads.dim("tile"))
		# The straight follows the ground: level where it is level, and where it runs up or down a
		# slope, the flat road sheared along its length, which is exactly how a slope projects, so
		# the same piece draws it. Over a river's valley it runs level on its bridge's deck.
		var prof: Array = _profile(a + dir * from, a + dir * to, tile)
		var flats: Array = []                 # [[from, to, height]] the level stretches, for bridges
		var k := 0
		while k < prof.size() - 1:
			var h0 := float(prof[k][1])
			var j := k + 1
			if absf(float(prof[j][1]) - h0) < 0.05:
				while j + 1 < prof.size() and absf(float(prof[j + 1][1]) - h0) < 0.05:
					j += 1
			var d0 := from + float(prof[k][0]) * (to - from)
			var d1 := from + float(prof[j][0]) * (to - from)
			var h1 := float(prof[j][1])
			_road_run(roads, piece, a + dir * d0, a + dir * d1, h0, h1, step, tint, tile)
			if absf(h1 - h0) < 0.05:
				flats.append([d0, d1, h0])
			k = j
		# A truss bridge where this stretch crosses a river. A bridge needs a clear straight its
		# own length, so it slides along a level stretch to find one; where the long bridge has no
		# room the short one is tried, and with no room for that the road simply runs across.
		var hits: Array = []
		for line in _rivers.get(tile, []):
			var river: PackedVector2Array = line
			for i in range(river.size() - 1):
				var hit: Variant = Geometry2D.segment_intersects_segment(a, b, river[i], river[i + 1])
				if hit != null:
					hits.append((hit as Vector2).distance_to(a))
		hits.sort()
		var last := -INF
		for along_hit in hits:
			var placed := false
			for flat in flats:
				for kind in ["bridge", "bridge_short"]:
					var span := roads.dim(kind) * 0.5 + 2.0
					if placed or float(flat[1]) - float(flat[0]) < span * 2.0:
						continue
					var at := clampf(float(along_hit), float(flat[0]) + span, float(flat[1]) - span)
					# The river has to stay under the bridge, and one bridge serves a river that
					# doubles back under the road.
					if absf(at - float(along_hit)) > span * 0.6 or at - last < span * 2.0:
						continue
					last = at
					placed = true
					var p := a + dir * at
					_pipe_items.append({"kind": "fit", "atlas": roads, "at": iso(p, float(flat[2])), "depth": p.x + p.y,
						"tile": tile, "name": "r_bridge_%s%d_%d" % ["s_" if kind == "bridge_short" else "", k6, level]})


## The light over a road's run on past its tile's edge, beyond the tile's own skirt, `half` wide: the
## tile's light mesh stops at the skirt, and the run lies over the light of the tile beside it.
func _road_lit(tile: String, at: Vector2, dir: Vector2, half: float, reach: float) -> void:
	var side := dir.orthogonal() * half
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	for q in [at + dir * _SKIRT + side, at + dir * reach + side, at + dir * reach - side, at + dir * _SKIRT - side]:
		var bq := iso(q, _way_h(tile, q))
		pts.append(bq)
		cols.append(_light_wash(_light_at(bq)))
	_road_lights.append({"tile": tile, "points": pts, "colours": cols})


## Where roads meet with no junction piece to lie there, the corner between them filled with road: a
## disc as wide as the widest of them, at the ground's height.
func _road_joint(roads: Atlas, nd: Dictionary, arms: Dictionary, ks: Array, paved: bool) -> void:
	var widest := 0
	for k in ks:
		widest = maxi(widest, int(arms[k]["level"]))
	var half := roads.dim("half_%d" % widest)
	var p: Vector2 = nd["p"]
	var h := _way_h(str(arms[ks[0]]["tile"]), p)
	var disc := PackedVector2Array()
	for n in range(16):
		disc.append(iso(p + Vector2.from_angle(TAU * float(n) / 16.0) * half, h))
	var on: Dictionary = {}
	for k in ks:
		on[str(arms[k]["tile"])] = true
	for tile in on:
		_road_joints.append({"tile": tile, "points": disc, "colour": _ASPHALT if paved else _ASPHALT * _UNPAVED})


## Does a point lie on an edge a tile shares with a tile drawn beside it.
func _at_shared_edge(tile: String, p: Vector2) -> bool:
	var t: Dictionary = (_model["tiles"] as Dictionary)[tile]
	var hexp := Model.hex_points(t["center"])
	var beside: Array = t.get("beside", [])
	for i in range(mini(6, beside.size())):
		if bool(beside[i]) and Geometry2D.get_closest_point_to_segment(p, hexp[i], hexp[(i + 1) % 6]).distance_to(p) < 0.5:
			return true
	return false


## One run of a straight road from `p0` (ground at h0) to `p1` (at h1): laid level at h0, then,
## where the ground climbs or falls, sheared down its length to h1.
func _road_run(roads: Atlas, piece: String, p0: Vector2, p1: Vector2, h0: float, h1: float, step: Vector2,
		tint: Color, tile: String) -> void:
	var start := iso(p0, h0)
	var end := iso(p1, h0)
	var along := (end - start).normalized()
	var run := maxf(start.distance_to(end), 0.001)
	var fall := Vector2(0.0, (h0 - h1) * ISO_RISE)
	for poly in roads.run_polys({"name": piece, "a": start, "b": end, "step": step}):
		var pts: PackedVector2Array = poly["points"]
		if absf(h1 - h0) >= 0.05:
			for i in range(pts.size()):
				pts[i] += fall * clampf((pts[i] - start).dot(along) / run, -0.2, 1.2)
			poly["points"] = pts
		# A sliver of a piece, or a stretch seen edge on up a slope as steep as the view: nothing shows.
		if Geometry2D.triangulate_polygon(pts).is_empty():
			continue
		poly["tint"] = tint
		poly["tile"] = tile
		_road_polys.append(poly)


static var _roads_atlas: Atlas = null
static func _road_kit() -> Atlas:
	if _roads_atlas == null:
		_roads_atlas = Atlas.new("roads")
	return _roads_atlas


## A path along the streets as board points, on the ground: every stretch follows _profile, so it
## runs up and down the slopes as the road does, and over a river's valley on the bridge's deck. A
## tile edge is given once per tile, at one height from both.
func _street_line(path: Array, info: Array = []) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var put := func(p: Vector2, h: float, tile: String) -> void:
		pts.append(iso(p, h))
		info.append({"p": p, "h": h, "tile": tile})
	for i in range(path.size()):
		var node: Dictionary = path[i]
		var tile := str(node["tile"])
		var p: Vector2 = node["p"]
		if i > 0 and str(path[i - 1]["tile"]) == tile:
			var from: Vector2 = path[i - 1]["p"]
			if from.distance_to(p) < 0.01:
				continue
			var prof: Array = _profile(from, p, tile)
			for k in range(1, prof.size()):
				put.call(from.lerp(p, float(prof[k][0])), float(prof[k][1]), tile)
			continue
		put.call(p, _way_h(tile, p), tile)
	return pts


## Track for one railway run: its corners eased into curves, then cut into each tile's share.
## Runs that share track are laid over each other exactly, so where two part they make points.
func _lay_track(path: Array, laid: Dictionary) -> void:
	var nodes: Array = []
	for i in range(path.size()):
		var node: Dictionary = path[i]
		var corner := i > 0 and i < path.size() - 1 and not bool(node["edge"])
		if not corner:
			nodes.append(node)
			continue
		var b: Vector2 = node["p"]
		var to_a: Vector2 = (path[i - 1]["p"] as Vector2) - b
		var to_c: Vector2 = (path[i + 1]["p"] as Vector2) - b
		var ease := minf(_RAIL_CURVE, minf(to_a.length(), to_c.length()) * 0.5)
		if ease < 1.0 or absf(to_a.normalized().dot(to_c.normalized())) > 0.999:
			nodes.append(node)
			continue
		var p0 := b + to_a.normalized() * ease
		var p2 := b + to_c.normalized() * ease
		for k in range(_RAIL_CURVE_STEPS + 1):
			var t := float(k) / float(_RAIL_CURVE_STEPS)
			nodes.append({"p": p0.lerp(b, t).lerp(b.lerp(p2, t), t), "tile": node["tile"], "edge": false})
	var info: Array = []
	_street_line(nodes, info)
	if info.size() < 2:
		return
	var ends := [not bool(path[0]["edge"]), not bool(path[path.size() - 1]["edge"])]
	var run: Array = []
	for i in range(info.size() + 1):
		if i < info.size() and (run.is_empty() or str(run[0]["tile"]) == str(info[i]["tile"])):
			run.append(info[i])
			continue
		if run.size() >= 2:
			var key := ""
			for r in run:
				key += "%d,%d;" % [int(round((r["p"] as Vector2).x)), int(round((r["p"] as Vector2).y))]
			var first := i - run.size() == 0
			var rail := {"tile": str(run[0]["tile"]), "pts": run, "key": key,
				"stops": [first and ends[0], i == info.size() and ends[1]]}
			if not laid.has(key):
				laid[key] = true
				_rails.append(rail)
				for k in range(run.size() - 1):
					_road_plan.append({"a": run[k]["p"], "b": run[k + 1]["p"], "half": Rails.HALF})
		run = [info[i]] if i < info.size() else []


## The ground under a path point, or the deck of the bridge it stands on.
func _ground_h(node: Dictionary) -> float:
	return _way_h(str(node["tile"]), node["p"])


## Is the ground near enough level round a point, as far as `reach` every way, for a junction piece to
## lie flat on it: a little off level is hidden under the piece, and is better than a gap in the road.
func _level_round(tile: String, p: Vector2, reach: float) -> bool:
	var h := _way_h(tile, p)
	for k in range(8):
		if absf(_way_h(tile, p + Vector2.from_angle(TAU * float(k) / 8.0) * reach) - h) > JUNCTION_TILT:
			return false
	return true


static func _same_goods(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for g in a:
		if not b.has(g):
			return false
	return true


## The parts of a pipe's path, given in the order of flow, that still have to be laid: those not
## running along pipe of the same kind already laid the same way. Where the path does run along
## such pipe, its good is added to what that stretch carries (the stretch is split so only the
## shared part carries it). Returns [{nodes, enter: [start, end]}]; an end is entered into the
## ground only where it is an end of the whole path, not where the pipe joins another.
func _unlaid(path: Array, mode: String, good: String, stretches: Array) -> Array:
	var out: Array = []
	var cur: Array = []
	var from_start := true
	for i in range(path.size() - 1):
		var n0: Dictionary = path[i]
		var n1: Dictionary = path[i + 1]
		var p: Vector2 = n0["p"]
		var q: Vector2 = n1["p"]
		var length := p.distance_to(q)
		if cur.is_empty():
			cur.append(n0)
		if length < 0.5:
			cur.append(n1)                        # a tile edge, given once for each tile
			continue
		var dir := (q - p) / length
		# Where along this leg pipe is already laid the same way.
		var shared: Array = []
		for k in range(stretches.size() - 1, -1, -1):
			var st: Dictionary = stretches[k]
			if str(st["mode"]) != mode:
				continue
			var a: Vector2 = st["a"]
			var b: Vector2 = st["b"]
			var run := a.distance_to(b)
			if ((b - a) / run).dot(dir) < 0.999 or absf((a - p).cross(dir)) > 0.6:
				continue
			var t0 := maxf(0.0, (a - p).dot(dir))
			var t1 := minf(length, (b - p).dot(dir))
			if t1 - t0 < 2.0:
				continue
			shared.append([t0, t1])
			# Split the laid stretch so that only the part run together carries both goods.
			var s0 := (p + dir * t0 - a).dot(dir)
			var s1 := (p + dir * t1 - a).dot(dir)
			var goods: Array = (st["goods"] as Array).duplicate()
			stretches.remove_at(k)
			if s0 > 1.0:
				stretches.append({"a": a, "b": a + dir * s0, "mode": mode, "tile": st["tile"], "goods": goods.duplicate()})
			if run - s1 > 1.0:
				stretches.append({"a": a + dir * s1, "b": b, "mode": mode, "tile": st["tile"], "goods": goods.duplicate()})
			if not goods.has(good):
				goods.append(good)
			stretches.append({"a": a + dir * s0, "b": a + dir * s1, "mode": mode, "tile": st["tile"], "goods": goods})
		shared.sort_custom(func(x: Array, y: Array) -> bool: return float(x[0]) < float(y[0]))
		var at := 0.0
		for iv in shared:
			if float(iv[1]) <= at:
				continue
			if float(iv[0]) > at + 1.0:
				cur.append({"p": p + dir * float(iv[0]), "tile": n0["tile"], "edge": false})
			if cur.size() >= 2 and _path_length(cur) > 1.0:
				out.append({"nodes": cur, "enter": [from_start, false]})
			cur = [{"p": p + dir * float(iv[1]), "tile": n0["tile"], "edge": false}]
			from_start = false
			at = float(iv[1])
		if length - at > 1.0:
			cur.append(n1)
		else:
			cur = [n1]
	if cur.size() >= 2 and _path_length(cur) > 1.0:
		out.append({"nodes": cur, "enter": [from_start, true]})
	return out


static func _path_length(nodes: Array) -> float:
	var total := 0.0
	for i in range(nodes.size() - 1):
		total += (nodes[i]["p"] as Vector2).distance_to(nodes[i + 1]["p"])
	return total


## A pipe line's route as the waypoints the pipe planner takes. Across each tile a pipe keeps one
## level on its supports, that of the highest ground it passes over there, so it never sinks into a
## rise, and it steps to the next tile's level on the edge itself.
func _pipe_waypoints(path: Array) -> Array:
	var tiles: Dictionary = _model["tiles"]
	var out: Array = []
	var levels: Dictionary = {}               # index of a run's first node -> its level
	var run_of: Array = []
	var start := 0
	for i in range(path.size()):
		if i > 0 and str(path[i]["tile"]) != str(path[i - 1]["tile"]):
			start = i
		run_of.append(start)
		var top := float(levels.get(start, -INF))
		var p: Vector2 = path[i]["p"]
		top = maxf(top, _height_at(p))
		if i > start:
			var from: Vector2 = path[i - 1]["p"]
			var steps := ceili(from.distance_to(p) / Ground.NODE)
			for k in range(1, steps):
				top = maxf(top, _height_at(from.lerp(p, float(k) / float(steps))))
		levels[start] = top
	for i in range(path.size()):
		var node: Dictionary = path[i]
		var p: Vector2 = node["p"]
		var base := float(levels[run_of[i]])
		var wp := {"p": p, "base": base, "edge": bool(node["edge"])}
		if bool(node["edge"]):
			var twin: Dictionary = path[i + 1] if i + 1 < path.size() and bool(path[i + 1]["edge"]) \
				and (path[i + 1]["p"] as Vector2).is_equal_approx(p) else path[i - 1]
			var here: Vector2 = tiles[str(node["tile"])]["center"]
			var there: Vector2 = tiles[str(twin["tile"])]["center"]
			wp["normal"] = (there - here).normalized()
		out.append(wp)
	return out


## A cable between two standing things: from high on one to high on the other, with a sag.
func _cable_between(by_iid: Dictionary, ids: Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	if not by_iid.has(str(ids[0])) or not by_iid.has(str(ids[1])):
		return pts
	var ends: Array = []
	for id in ids:
		var s: Dictionary = by_iid[str(id)]
		var r: Rect2 = s["rect"]
		var share := 0.2 if str(s["kind"]) == "pylon" else 0.42
		ends.append(Vector2(r.get_center().x, r.position.y + r.size.y * share))
	var a: Vector2 = ends[0]
	var b: Vector2 = ends[1]
	var sag := a.distance_to(b) * _CABLE_SAG
	for k in range(_CABLE_STEPS + 1):
		var t := float(k) / float(_CABLE_STEPS)
		pts.append(a.lerp(b, t) + Vector2(0.0, sag * 4.0 * t * (1.0 - t)))
	return pts


# ------------------------------------------------------------------ drawing

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		# Closed, the board only bakes what a build in the background has asked for, one layer at
		# a time, so the view opens on finished pictures.
		if bake_while_hidden and not _building and not _baking and has_content():
			var unit := _next_bake()
			if unit == "":
				bake_while_hidden = false
			else:
				_bake(unit, _bake_zoom())
		return
	_clock += delta
	_reveal_when_baked(delta)
	if has_content():
		_tokens.queue_redraw()
		_glow_layer.queue_redraw()
		if not _baking:
			var tile := _next_bake()
			if tile != "":
				_bake(tile, _bake_zoom())


func _draw() -> void:
	if not has_content():
		var font := get_theme_default_font()
		var msg := "Nothing built yet"
		var w := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		draw_string(font, size * 0.5 - Vector2(w * 0.5, 0.0), msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, DS.PALETTE.TEXT)
		return
	# A tile whose picture is not baked yet for this zoom is drawn live, so the board is never
	# blank while the bakes catch up.
	draw_set_transform(_offset, 0.0, Vector2(_zoom, _zoom))
	for unit in _units:
		if _best_bake(str(unit)).is_empty():
			_draw_tile(self, str(unit), _zoom)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Everything about one tile that does not move, in two layers (_unit), each baked on its own: the
## ground layer, its slab and ground, its roads and railways and the light over them; and the things
## layer, everything that stands on the ground, buildings, pipes, trees and lamps. Every tile's
## ground layer is drawn before any tile's things (_units), so what stands near a tile's edge is
## never covered by the ground of the tile beside it.
func _draw_tile(ci: CanvasItem, unit: String, zoom: float) -> void:
	if unit.ends_with(_THINGS):
		_draw_things(ci, unit.trim_suffix(_THINGS))
	else:
		_draw_ground(ci, unit.trim_suffix(_GROUND))


func _draw_ground(ci: CanvasItem, tile: String) -> void:
	var gfx: Dictionary = _tile_gfx.get(tile, {})
	var parts: Dictionary = _tile_parts.get(tile, {})
	if gfx.get("walls") != null:
		ci.draw_mesh(gfx["walls"], _ground_tex("strata"))
	if gfx.get("ground") != null:
		ci.draw_mesh(gfx["ground"], null)
	# What holds the bridges up, under their decks.
	for pier in parts.get("piers", []):
		for poly in pier["polys"]:
			ci.draw_colored_polygon(poly[0], poly[1])
			ci.draw_polyline(poly[0] + PackedVector2Array([(poly[0] as PackedVector2Array)[0]]), _INK, 0.8)
	var road_tex: Texture2D = _road_kit().texture()
	if road_tex != null and bool(show["roads"]):
		for joint in parts.get("joints", []):
			ci.draw_colored_polygon(joint["points"], joint["colour"])
		for fit in parts.get("fits", []):
			var rr: Array = _road_kit().fit_rects(str(fit["name"]), fit["at"])
			ci.draw_texture_rect_region(road_tex, rr[0], rr[1], fit["tint"])
		for poly in parts.get("polys", []):
			var tints := PackedColorArray()
			tints.resize((poly["points"] as PackedVector2Array).size())
			tints.fill(poly["tint"])
			ci.draw_polygon(poly["points"], tints, poly["uvs"], road_tex)
	if bool(show["roads"]):
		_draw_roads(ci, parts.get("links", []))
	if bool(show["rails"]):
		_draw_rails(ci, tile, parts.get("rails", []))
	if gfx.get("light") != null:
		ci.draw_mesh(gfx["light"], null)
	if bool(show["roads"]):
		for lit in parts.get("lit", []):
			ci.draw_polygon(lit["points"], lit["colours"])


func _draw_things(ci: CanvasItem, tile: String) -> void:
	var parts: Dictionary = _tile_parts.get(tile, {})
	# Shadows fall north-west, away from the sun: laid on the ground before anything stands.
	for thing in parts.get("things", []):
		var ref: Dictionary = thing["ref"]
		if str(thing["what"]) == "standing" and str(ref["kind"]) != "pylon" and not bool(ref.get("sunk", false)):
			var half := float(ref["side"]) * 0.5
			var throw := _SHADOW_NW * float(ref["side"]) * _SHADOW_REACH
			var pos: Vector2 = ref["pos"]
			var h := float(ref["h"])
			ci.draw_colored_polygon(PackedVector2Array([
				iso(pos + Vector2(half, -half), h), iso(pos + Vector2(half, half), h), iso(pos + Vector2(-half, half), h),
				iso(pos + Vector2(-half, half) + throw, h), iso(pos + Vector2(-half, -half) + throw, h),
				iso(pos + Vector2(half, -half) + throw, h)]), _SHADOW)
		elif str(thing["what"]) == "item" and str(ref["kind"]) == "tree":
			var r: Rect2 = ref["rect"]
			var foot := Vector2(r.get_center().x, r.end.y - r.size.y * 0.04)
			var oval := PackedVector2Array()
			for k in range(14):
				var a := TAU * float(k) / 14.0
				oval.append(foot + Vector2(cos(a) * r.size.x * 0.36, -r.size.y * 0.2 + sin(a) * r.size.y * 0.22))
			ci.draw_colored_polygon(oval, _SHADOW)
	for p in parts.get("pipes", []):
		_thick(ci, p["pts"], _PIPE_EDGE, 9.0)
		_thick(ci, p["pts"], _PIPE_REINF if str(p["mode"]) == "reinf_pipes" else _PIPE, 6.0)
	# Buildings, pipe pieces, trees and signs, in one order of depth, far to near.
	for thing in parts.get("things", []):
		match str(thing["what"]):
			"standing":
				_draw_standing(ci, thing["ref"])
			"item":
				_draw_pipe_item(ci, thing["ref"])


## The grade over one layer of a tile's picture: a warm key and a cool fill, as on the key art's
## plate. One quad over the layer's whole picture, its corners coloured by how lit each is; and over
## the ground layer, the shading of its slopes (_build_shade), which roads and railways on a slope
## take too.
func _draw_grade(ci: CanvasItem, unit: String) -> void:
	var r := _unit_rect(unit)
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	var cols := PackedColorArray()
	for p in pts:
		cols.append(_GRADE_SHADE.lerp(_GRADE_SUN, _light_at(p)))
	ci.draw_polygon(pts, cols)
	if unit.ends_with(_GROUND):
		var shade: Variant = (_tile_gfx.get(unit.trim_suffix(_GROUND), {}) as Dictionary).get("shade")
		if shade != null:
			ci.draw_mesh(shade, null)


## Sort everything that is drawn into the tile it belongs to, and take a hash of each tile's
## share: a tile's bake is good for as long as that hash stands.
func _sort_parts() -> void:
	var tiles: Dictionary = _model.get("tiles", {})
	for tid in _tile_order:
		_tile_parts[tid] = {"fits": [], "polys": [], "joints": [], "lit": [], "links": [], "rails": [], "pipes": [], "piers": [],
			"things": []}
	for fit in _road_fits:
		_part(fit, "fits", fit)
	for poly in _road_polys:
		_part(poly, "polys", poly)
	for joint in _road_joints:
		_part(joint, "joints", joint)
	for lit in _road_lights:
		_part(lit, "lit", lit)
	for l in _links:
		_part(l, "links", l)
	for r in _rails:
		_part(r, "rails", r)
	for pl in _pipes:
		_part(pl, "pipes", pl)
	for pier in _piers:
		_part(pier, "piers", pier)
	for st in _standing:
		_part(st, "things", {"what": "standing", "depth": float(st["depth"]), "ref": st})
	for item in _pipe_items:
		if not item.has("tile"):
			item["tile"] = _tile_of(item.get("plan", Vector2.ZERO))
		_part(item, "things", {"what": "item", "depth": float(item["depth"]), "ref": item})
	_units.clear()
	_unit_z.clear()
	_things_rects.clear()
	for tid in _tile_order:
		var parts: Dictionary = _tile_parts[tid]
		(parts["things"] as Array).sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return float(x["depth"]) < float(y["depth"]))
		_things_rects[tid] = _things_rect(str(tid), parts)
		# What each layer is made of. The ground: its heights, the tiles drawn beside it, the board it
		# is lit on, and the ways laid over it. The things: everything standing on it.
		var looks: Array = [_bounds, plate_lamps, plate_sea, plate_town, str(show)]
		var made: Array = [float(tiles[tid]["height"]), float(tiles[tid].get("top", 0.0)), str(tiles[tid]["type"]),
			str(tiles[tid].get("beside", []))] + looks
		for fit in parts["fits"]:
			made.append([fit["name"], fit["at"], fit["tint"]])
		for poly in parts["polys"]:
			made.append([poly["points"], poly["tint"]])
		for joint in parts["joints"]:
			made.append(joint["points"])
		for l in parts["links"]:
			made.append([l["mode"], l["pts"]])
		for r in parts["rails"]:
			made.append([r["key"], r["stops"]])
		for pier in parts["piers"]:
			made.append(pier["key"])
		var stood: Array = looks.duplicate()
		for pl in parts["pipes"]:
			stood.append([pl["mode"], pl["pts"]])
		for thing in parts["things"]:
			var ref: Dictionary = thing["ref"]
			match str(thing["what"]):
				"standing":
					stood.append([ref["iid"], ref["level"], ref["pos"], ref["side"], ref.get("tint"), ref.get("sprite")])
				"item":
					stood.append([ref["kind"], ref.get("name", ""), ref.get("at", ref.get("rect", ref.get("foot", ""))), ref.get("points", "")])
		# Every tile's two layers, each with its depth: a tile's own by how far back it lies, and every
		# things layer over every ground layer.
		var depth := (tiles[tid]["center"] as Vector2).x + (tiles[tid]["center"] as Vector2).y
		for layer in [[_GROUND, 0.0, made], [_THINGS, _THINGS_Z, stood]]:
			var unit := str(tid) + str(layer[0])
			_tile_sig[unit] = hash(str(layer[2]))
			_unit_z[unit] = float(layer[1]) + depth
			_units.append(unit)
	_units.sort_custom(func(x: String, y: String) -> bool: return float(_unit_z[x]) < float(_unit_z[y]))
	# Bakes of tiles that have gone are let go. A changed tile keeps its old picture until the new one is
	# baked, so it is never drawn live out of its place in the order (_best_bake).
	for key in _bakes.keys():
		if not _tile_sig.has(str(key).get_slice("|", 0)):
			_bakes.erase(key)


func _part(source: Dictionary, list: String, entry: Dictionary) -> void:
	var tile := str(source.get("tile", ""))
	if _tile_parts.has(tile):
		(_tile_parts[tile][list] as Array).append(entry)


## The drawn tile a plan point lies on, or the nearest when it lies on none.
func _tile_of(p: Vector2) -> String:
	var tiles: Dictionary = _model.get("tiles", {})
	var best := ""
	var best_d := INF
	for tid in tiles:
		var c: Vector2 = tiles[tid]["center"]
		if Geometry2D.is_point_in_polygon(p, Model.hex_points(c)):
			return str(tid)
		if c.distance_squared_to(p) < best_d:
			best_d = c.distance_squared_to(p)
			best = str(tid)
	return best


## The part of the board one layer of a tile covers (_unit).
func _unit_rect(unit: String) -> Rect2:
	if unit.ends_with(_THINGS):
		return _things_rects.get(unit.trim_suffix(_THINGS), _tile_rect(unit.trim_suffix(_THINGS)))
	return _tile_rect(unit.trim_suffix(_GROUND))


## The part of the board a tile's things layer covers: the tile's own, grown to take in everything
## standing on it whole, however far a building, a pylon or a tree reaches past the tile's edge or
## up over the tile behind.
func _things_rect(tile: String, parts: Dictionary) -> Rect2:
	var r := _tile_rect(tile)
	for thing in parts.get("things", []):
		var ref: Dictionary = thing["ref"]
		if str(thing["what"]) == "standing":
			r = r.merge(ref.get("tex_rect", ref["rect"])).merge(ref["rect"])
			continue
		match str(ref["kind"]):
			"tree":
				r = r.merge(ref["rect"])
			"lamp":
				r = r.merge(Rect2(ref["foot"], Vector2.ZERO).expand(ref["head"]).grow(3.0))
			"run":
				r = r.merge(_box_of(ref["points"]))
			_:
				var kit: Atlas = ref.get("atlas", Pipes.kit())
				if kit.ok():
					r = r.merge((kit.fit_rects(str(ref["name"]), ref["at"]) as Array)[0])
	for p in parts.get("pipes", []):
		r = r.merge(_box_of(p["pts"]).grow(6.0))
	r = r.grow(4.0)
	var lo := (r.position / _BAKE_GRID).floor() * _BAKE_GRID
	var hi := (r.end / _BAKE_GRID).ceil() * _BAKE_GRID
	return Rect2(lo, hi - lo)


## The part of the board a tile's ground layer covers: its top, its cut-away below, and room above
## for what stands on it.
func _tile_rect(tile: String) -> Rect2:
	var t: Dictionary = (_model["tiles"] as Dictionary)[tile]
	var hexp := Model.hex_points(t["center"])
	var top := float(t.get("top", t["height"]))
	var r := Rect2(iso(hexp[0], top), Vector2.ZERO)
	for p in hexp:
		r = r.expand(iso(p, top)).expand(iso(p, -SLAB_DEPTH))
	r = r.grow_individual(_TILE_MARGIN, _TILE_HEADROOM, _TILE_MARGIN, 6.0)
	var lo := (r.position / _BAKE_GRID).floor() * _BAKE_GRID
	var hi := (r.end / _BAKE_GRID).ceil() * _BAKE_GRID
	return Rect2(lo, hi - lo)


## Screen pixels to one of the view's own units. The game's canvas is stretched to the window,
## so on a dense display one unit is nearly two pixels; a bake is made at the screen's pixels,
## not the canvas's, or it would be stretched after all.
func _px() -> float:
	return maxf(0.25, get_viewport().get_final_transform().get_scale().x) if is_inside_tree() else 1.0


func _bake_key(tile: String, zoom: float) -> String:
	return "%s|%.2f|%.3f" % [tile, zoom, _px()]


## The bake zoom the present zoom is drawn from: the first at or above it, else the largest.
func _bake_zoom() -> float:
	for z in BAKE_ZOOMS:
		if float(z) >= _zoom * 0.999:
			return float(z)
	return float(BAKE_ZOOMS[BAKE_ZOOMS.size() - 1])


func _good(tile: String, zoom: float) -> bool:
	var b: Dictionary = _bakes.get(_bake_key(tile, zoom), {})
	return not b.is_empty() and int(b["sig"]) == int(_tile_sig.get(tile, 0))


## Is there a picture of this tile from the bake the present zoom calls for?
func _baked(tile: String) -> bool:
	return _good(tile, _bake_zoom())


## The picture to draw a tile from now: the one the zoom calls for, or while that is still
## being baked, whichever other is at hand. Returns [bake, its zoom], or [] when there is none.
func _best_bake(tile: String) -> Array:
	var want := _bake_zoom()
	if _good(tile, want):
		return [_bakes[_bake_key(tile, want)], want]
	var found: Array = []
	for z in BAKE_ZOOMS:
		if _good(tile, float(z)) and (found.is_empty() or absf(float(z) - want) < absf(float(found[1]) - want)):
			found = [_bakes[_bake_key(tile, float(z))], float(z)]
	if found.is_empty():
		# Only a picture from before the tile changed: better than drawing it live.
		for z in BAKE_ZOOMS:
			var b: Dictionary = _bakes.get(_bake_key(tile, float(z)), {})
			if not b.is_empty() and (found.is_empty() or absf(float(z) - want) < absf(float(found[1]) - want)):
				found = [b, float(z)]
	return found


## Bake one tile's picture at one zoom: paint it oversized into the bake viewport, read it
## back, reduce it to size, and keep it.
func _bake(tile: String, zoom: float) -> void:
	_baking = true
	var sig := int(_tile_sig.get(tile, 0))
	var rect := _unit_rect(tile)
	var px := _px()
	var key := _bake_key(tile, zoom)
	var scale_up := zoom * px * _BAKE_OVERSAMPLE
	var want := Vector2i((rect.size * zoom * px).round())
	_bake_view.size = Vector2i((rect.size * scale_up).round())
	_painter.set("tile", tile)
	_painter.set("zoom", scale_up)
	_painter.set("origin", rect.position)
	_painter.size = Vector2(_bake_view.size)
	_painter.queue_redraw()
	_grade.queue_redraw()
	_bake_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img: Image = _bake_view.get_texture().get_image()
	if img != null and not img.is_empty():
		img.resize(maxi(1, want.x), maxi(1, want.y), Image.INTERPOLATE_BILINEAR)
		# Mipmaps, because between two bake zooms the picture is drawn reduced.
		img.generate_mipmaps()
		_bakes[key] = {"tex": ImageTexture.create_from_image(img), "sig": sig, "rect": rect,
			"bytes": int(want.x * want.y * 4 * 1.34), "used": Engine.get_frames_drawn()}
		_trim_bakes()
	_painter.set("tile", "")
	_baking = false
	_view_changed()


## The next tile in view wanting a bake for the present zoom, far to near. Tiles out of view
## are left until they are looked at.
func _next_bake() -> String:
	var view := Rect2(Vector2.ZERO, size)
	for unit in _units:
		if _baked(str(unit)):
			continue
		var r := _unit_rect(str(unit))
		if view.intersects(Rect2(r.position * _zoom + _offset, r.size * _zoom)):
			return str(unit)
	return ""


## Keep the bakes within their budget, letting go of the ones drawn longest ago.
func _trim_bakes() -> void:
	var total := 0
	for key in _bakes:
		total += int(_bakes[key].get("bytes", 0))
	while total > _BAKE_BUDGET and _bakes.size() > 1:
		var oldest := ""
		for key in _bakes:
			if oldest == "" or int(_bakes[key].get("used", 0)) < int(_bakes[oldest].get("used", 0)):
				oldest = str(key)
		total -= int(_bakes[oldest].get("bytes", 0))
		_bakes.erase(oldest)


func _draw_bakes(layer: Control) -> void:
	var px := _px()
	var frame := Engine.get_frames_drawn()
	for unit in _units:
		var found: Array = _best_bake(str(unit))
		if found.is_empty():
			continue
		var b: Dictionary = found[0]
		b["used"] = frame
		var tex: Texture2D = b["tex"]
		# A bake holds the tile at its own zoom; here it is drawn at the present one.
		var shrink := _zoom / float(found[1])
		var at := (b["rect"] as Rect2).position * _zoom + _offset
		if is_equal_approx(shrink, 1.0):
			at = (at * px).round() / px
		layer.draw_texture_rect(tex, Rect2(at, Vector2(tex.get_width(), tex.get_height()) / px * shrink), false)


func _draw_standing(ci: CanvasItem, s: Dictionary) -> void:
	var pos: Vector2 = s["pos"]
	var h := float(s["h"])
	var side := float(s["side"])
	if str(s["kind"]) == "pylon":
		if s.get("sprite") != null:
			ci.draw_texture_rect(s["sprite"], s["tex_rect"], false, s.get("tint", Color.WHITE))
		else:
			var foot: Vector2 = s["at"]
			var r: Rect2 = s["rect"]
			ci.draw_line(foot, Vector2(foot.x, r.position.y), _PIPE_EDGE, 3.0)
			for arm in [0.18, 0.36]:
				var y: float = r.position.y + r.size.y * float(arm)
				ci.draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), _PIPE_EDGE, 2.2)
		return
	if s.has("plinth"):
		_draw_plinth(ci, pos, side, h, s["plinth"])
	var tex: Texture2D = s.get("sprite")
	if tex != null:
		if bool(s.get("sunk", false)):
			# Worked ground round the pit: dark trodden earth, ragged at its edge, so the pit
			# reads against it and not against the grass.
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(str(s["iid"]))
			for ring in [[0.62, _MINE_EARTH_EDGE], [0.54, _MINE_EARTH]]:
				var patch := PackedVector2Array()
				for i in range(22):
					var ang := TAU * float(i) / 22.0
					patch.append(iso(pos + Vector2(cos(ang), sin(ang)) * side * float(ring[0]) * rng.randf_range(0.9, 1.08), h))
				ci.draw_colored_polygon(patch, ring[1])
		ci.draw_texture_rect(tex, s["tex_rect"], false, s.get("tint", Color.WHITE))
		return
	# No sprite yet: a plain block of the footprint, with the building's icon on its roof.
	var hs := side * 0.5
	var top := h + side * 0.6
	var a := pos + Vector2(-hs, -hs)
	var b := pos + Vector2(hs, -hs)
	var c := pos + Vector2(hs, hs)
	var d := pos + Vector2(-hs, hs)
	ci.draw_colored_polygon(PackedVector2Array([iso(d, top), iso(c, top), iso(c, h), iso(d, h)]), _BOX_SOUTH)
	ci.draw_colored_polygon(PackedVector2Array([iso(c, top), iso(b, top), iso(b, h), iso(c, h)]), _BOX_EAST)
	ci.draw_colored_polygon(PackedVector2Array([iso(a, top), iso(b, top), iso(c, top), iso(d, top)]), _BOX_ROOF)
	var icon: Texture2D = s.get("icon")
	if icon != null:
		var isz := side * 0.8
		ci.draw_texture_rect(icon, Rect2(iso(pos, top) - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false,
			Color(0.0, 0.12, 0.24))


## The plinth a building stands on where the ground under it is not level: its footprint at `h`,
## and its south and east faces, the sides toward the viewer, down to the ground at each corner
## (`foot`, from the north-west corner round by the north-east).
func _draw_plinth(ci: CanvasItem, pos: Vector2, side: float, h: float, foot: Array) -> void:
	var hs := side * 0.5
	var c: Array = [pos + Vector2(-hs, -hs), pos + Vector2(hs, -hs), pos + Vector2(hs, hs), pos + Vector2(-hs, hs)]
	for face in [[3, 2, _CONCRETE.darkened(0.22)], [2, 1, _CONCRETE.darkened(0.06)]]:
		var a := int(face[0])
		var b := int(face[1])
		if h - float(foot[a]) + h - float(foot[b]) < 0.2:
			continue                              # level with the ground along this side
		ci.draw_colored_polygon(PackedVector2Array([iso(c[a], h), iso(c[b], h), iso(c[b], float(foot[b])),
			iso(c[a], float(foot[a]))]), face[2])
	ci.draw_colored_polygon(PackedVector2Array([iso(c[0], h), iso(c[1], h), iso(c[2], h), iso(c[3], h)]), _PAD)
	ci.draw_polyline(PackedVector2Array([iso(c[3], float(foot[3])), iso(c[3], h), iso(c[2], h), iso(c[1], h),
		iso(c[1], float(foot[1]))]), _PAD_EDGE, 0.8)


## Ways drawn as plain lines: one that cannot follow the streets, a rail line laid over its
## street, and every road when the pieces have not been baked.
func _draw_roads(ci: CanvasItem, links: Array) -> void:
	for l in links:
		match str(l["mode"]):
			"nothing":
				_draw_dashes(ci, l["pts"], 13.0, 9.0, _TRACK, 6.0, [])
			"roads":
				_thick(ci, l["pts"], _KERB, _ROAD_HALF * 2.0 + 5.0)
				_thick(ci, l["pts"], _ASPHALT, _ROAD_HALF * 2.0)
				_draw_dashes(ci, l["pts"], 12.0, 12.0, _DASH, 1.8, [])
			Model.MODE_DRIVE:
				_thick(ci, l["pts"], _KERB, _DRIVE_HALF * 2.0 + 3.5)
				_thick(ci, l["pts"], _ASPHALT, _DRIVE_HALF * 2.0)
			"rail":
				if not bool(show["rails"]):
					continue
				# A railway between two tiles that do not touch: no track plan reaches, so a plain line.
				_thick(ci, l["pts"], _BALLAST, 11.0)
				_draw_ties(ci, l["pts"], 6.0, 8.0, _TIE, 1.6)
				_draw_offset_line(ci, l["pts"], 2.6, _RAIL, 1.1)
				_draw_offset_line(ci, l["pts"], -2.6, _RAIL, 1.1)


## A band along a run of track, `half` wide either side, as quads in board space.
func _rail_band(ci: CanvasItem, pts: Array, half: float, col: Color, from: int = 0, to: int = -1) -> void:
	var last := pts.size() - 1 if to < 0 else to
	for i in range(from, last):
		var a: Vector2 = pts[i]["p"]
		var b: Vector2 = pts[i + 1]["p"]
		if a.distance_to(b) < 0.05:
			continue
		var n := (b - a).normalized().orthogonal() * half
		var ha := float(pts[i]["h"])
		var hb := float(pts[i + 1]["h"])
		ci.draw_colored_polygon(PackedVector2Array([iso(a + n, ha), iso(b + n, hb), iso(b - n, hb), iso(a - n, ha)]), col)
		if i > from:
			# The joint, filled so a curve shows no notches.
			var joint := PackedVector2Array()
			for k in range(10):
				var ang := TAU * float(k) / 10.0
				joint.append(iso(a + Vector2(cos(ang), sin(ang)) * half, ha))
			ci.draw_colored_polygon(joint, col)


## A tile's railway: ballast with an inked edge, sleepers, two rails. Drawn in passes so tracks
## that share ground or part at points lie in one bed. Over a river the bed is a girder deck.
func _draw_rails(ci: CanvasItem, tile: String, rails: Array) -> void:
	if rails.is_empty():
		return
	for band in [[Rails.HALF + _RAIL_INK, _INK], [Rails.HALF, _BALLAST]]:
		for r in rails:
			_rail_band(ci, r["pts"], float(band[0]), band[1])
	# Girders where the track crosses water.
	for r in rails:
		var pts: Array = r["pts"]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]["p"]
			var b: Vector2 = pts[i + 1]["p"]
			for line in _rivers.get(tile, []):
				var river: PackedVector2Array = line
				for k in range(river.size() - 1):
					var hit: Variant = Geometry2D.segment_intersects_segment(a, b, river[k], river[k + 1])
					if hit == null:
						continue
					var dir := (b - a).normalized()
					var h := float(pts[i]["h"])
					var span: Array = [{"p": (hit as Vector2) - dir * _RAIL_SPAN, "h": h}, {"p": (hit as Vector2) + dir * _RAIL_SPAN, "h": h}]
					_rail_band(ci, span, Rails.HALF + 2.6, _INK)
					_rail_band(ci, span, Rails.HALF + 1.6, _GIRDER)
					_rail_band(ci, span, Rails.HALF - 1.0, _GIRDER_DECK)
	# Sleepers, placed by where they are on the ground so shared track carries one set.
	for r in rails:
		var pts: Array = r["pts"]
		for i in range(pts.size() - 1):
			var a: Vector2 = pts[i]["p"]
			var b: Vector2 = pts[i + 1]["p"]
			var length := a.distance_to(b)
			if length < 0.05:
				continue
			var u := (b - a) / length
			if u.x < -0.001 or (absf(u.x) <= 0.001 and u.y < 0.0):
				u = -u
			var sa := a.dot(u)
			var sb := b.dot(u)
			var n := u.orthogonal() * _RAIL_TIE * 0.5
			var s := ceilf(minf(sa, sb) / _RAIL_TIE_GAP) * _RAIL_TIE_GAP
			while s <= maxf(sa, sb):
				var t := (s - sa) / (sb - sa)
				var p := a.lerp(b, t)
				var h := lerpf(float(pts[i]["h"]), float(pts[i + 1]["h"]), t)
				var w := u * _RAIL_TIE_W * 0.5
				ci.draw_colored_polygon(PackedVector2Array([iso(p - n - w, h), iso(p + n - w, h), iso(p + n + w, h), iso(p - n + w, h)]), _TIE)
				s += _RAIL_TIE_GAP
	for r in rails:
		var pts: Array = r["pts"]
		for side in [-1.0, 1.0]:
			for i in range(pts.size() - 1):
				var a: Vector2 = pts[i]["p"]
				var b: Vector2 = pts[i + 1]["p"]
				if a.distance_to(b) < 0.05:
					continue
				var n: Vector2 = (b - a).normalized().orthogonal() * _RAIL_GAUGE * 0.5 * side
				var w: Vector2 = n.normalized() * _RAIL_W * 0.5
				var ha := float(pts[i]["h"])
				var hb := float(pts[i + 1]["h"])
				ci.draw_colored_polygon(PackedVector2Array([iso(a + n - w, ha), iso(b + n - w, hb), iso(b + n + w, hb), iso(a + n + w, ha)]), _RAIL)
		# Buffers where the track ends at what it serves.
		for e in range(2):
			if not bool(r["stops"][e]):
				continue
			var at: Dictionary = pts[0] if e == 0 else pts[pts.size() - 1]
			var next: Dictionary = pts[1] if e == 0 else pts[pts.size() - 2]
			var n: Vector2 = ((next["p"] as Vector2) - (at["p"] as Vector2)).normalized().orthogonal() * (Rails.HALF - 0.6)
			var h := float(at["h"])
			var p: Vector2 = at["p"]
			ci.draw_line(iso(p - n, h + 2.6), iso(p + n, h + 2.6), _INK, 3.6)
			ci.draw_line(iso(p - n, h + 2.6), iso(p + n, h + 2.6), _BUFFER, 2.0)
			for side in [-1.0, 1.0]:
				ci.draw_line(iso(p + n * side * 0.7, h), iso(p + n * side * 0.7, h + 2.6), _INK, 1.4)


func _draw_pipe_item(ci: CanvasItem, item: Dictionary) -> void:
	if str(item["kind"]) == "tree":
		ci.draw_texture_rect(item["tex"], item["rect"], false, item["tint"])
		return
	if str(item["kind"]) == "lamp":
		var foot: Vector2 = item["foot"]
		var head: Vector2 = item["head"]
		ci.draw_line(foot, Vector2(foot.x, head.y), _INK, 1.3)
		ci.draw_line(Vector2(foot.x, head.y), head, _INK, 1.3)
		ci.draw_circle(head, 1.8, _LAMP_HEAD if bool(item.get("lit", false)) else _INK)
		return
	var kit: Atlas = item.get("atlas", Pipes.kit())
	var tex: Texture2D = kit.texture()
	# A bridge is a road's piece, though it stands among the things on the tile.
	if tex == null or (item.has("atlas") and not bool(show["roads"])):
		return
	if str(item["kind"]) == "run":
		ci.draw_colored_polygon(item["points"], Color.WHITE, item["uvs"], tex)
		return
	var rects: Array = kit.fit_rects(str(item["name"]), item["at"])
	ci.draw_texture_rect_region(tex, rects[0], rects[1])


## A small sign on a post in front of a pipe, showing what it carries.
## A pipe's sign, on the live layer in screen space: a post and one plate for everything the
## pipe carries there, the goods side by side on it. `box` is where the plate has room.
func _draw_sign(layer: Control, foot: Vector2, box: Rect2, icons: Array) -> void:
	var plate := box.size.y
	layer.draw_line(foot, Vector2(foot.x, box.end.y), _PIPE_EDGE, maxf(1.6, plate * 0.1))
	layer.draw_rect(box.grow(plate * 0.09), _PIPE_EDGE)
	layer.draw_rect(box, _CREAM)
	for i in range(icons.size()):
		var cell := Rect2(box.position + Vector2(plate * float(i), 0.0), Vector2(plate, plate))
		if icons[i] != null:
			layer.draw_texture_rect(icons[i], cell.grow(-plate * 0.08), false)


## Does this badge's box overlap one already placed?
static func _taken(placed: Array, box: Rect2) -> bool:
	for r in placed:
		if (r as Rect2).intersects(box):
			return true
	return false


## A wide line drawn segment by segment with round joints. draw_polyline miters its joints,
## and a route that steps up a tile's wall turns back on itself there, which throws a spike.
func _thick(ci: CanvasItem, pts: PackedVector2Array, col: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		ci.draw_line(pts[i], pts[i + 1], col, width)
		if i > 0:
			ci.draw_circle(pts[i], width * 0.5, col)


## Walk a polyline calling `emit(point, direction)` every `step` units.
func _walk(pts: PackedVector2Array, step: float, start: float, emit: Callable) -> void:
	var want := start
	var done := 0.0
	for i in range(pts.size() - 1):
		var seg := pts[i].distance_to(pts[i + 1])
		if seg < 0.001:
			continue
		var dir := (pts[i + 1] - pts[i]) / seg
		while want <= done + seg:
			emit.call(pts[i] + dir * (want - done), dir)
			want += step
		done += seg


## Dashes along a line, leaving out any that start inside a guard circle ([centre, radius]).
func _draw_dashes(ci: CanvasItem, pts: PackedVector2Array, dash: float, gap: float, col: Color, width: float, guards: Array) -> void:
	_walk(pts, dash + gap, gap * 0.5, func(p: Vector2, dir: Vector2) -> void:
		for g in guards:
			if p.distance_to(g[0]) < float(g[1]) or (p + dir * dash).distance_to(g[0]) < float(g[1]):
				return
		ci.draw_line(p, p + dir * dash, col, width))


func _draw_ties(ci: CanvasItem, pts: PackedVector2Array, step: float, length: float, col: Color, width: float) -> void:
	_walk(pts, step, step * 0.5, func(p: Vector2, dir: Vector2) -> void:
		var n := dir.orthogonal() * length * 0.5
		ci.draw_line(p - n, p + n, col, width))


func _draw_offset_line(ci: CanvasItem, pts: PackedVector2Array, off: float, col: Color, width: float) -> void:
	for i in range(pts.size() - 1):
		if pts[i].distance_squared_to(pts[i + 1]) < 0.001:
			continue
		var n := (pts[i + 1] - pts[i]).normalized().orthogonal() * off
		ci.draw_line(pts[i] + n, pts[i + 1] + n, col, width)


func _draw_labels(ci: CanvasItem) -> void:
	var font := get_theme_default_font()
	var fs := 13
	for l in _labels:
		var at: Vector2 = (l["at"] as Vector2) * _zoom + _offset
		var text := str(l["text"])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(at - Vector2(w * 0.5 + 8.0, 11.0), Vector2(w + 16.0, 22.0))
		ci.draw_rect(box, Color(_NAVY.r, _NAVY.g, _NAVY.b, 0.86))
		ci.draw_string(font, Vector2(box.position.x + 8.0, box.position.y + 16.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE.TEXT)


func _draw_hover(ci: CanvasItem) -> void:
	if _hover.is_empty():
		return
	var r: Rect2 = _hover["rect"]
	var sr := Rect2(r.position * _zoom + _offset, r.size * _zoom)
	var font := get_theme_default_font()
	var lines: Array = [str(_hover["name"])]
	if str(_hover["kind"]) == "warehouse":
		var tid := str(_hover["tile"])
		lines.append("Level %d   %d of %d stored" % [int(_hover["level"]),
			Stockpile.get_used_capacity(tid), Stockpile.get_capacity(tid)])
		for row in Stockpile.get_top_goods(tid, 3):
			lines.append("%s  %d" % [str(Catalog.get_display_name(str(row["good_id"]))), int(row["qty"])])
	elif str(_hover["kind"]) == "site":
		lines.append("Under construction")
	elif str(_hover["kind"]) == "suppliers":
		lines.append_array(SUPPLIERS_HOVER)
	var fs := 14
	var w := 0.0
	for line in lines:
		w = maxf(w, font.get_string_size(str(line), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var box := Rect2(Vector2(sr.get_center().x - w * 0.5 - 10.0, sr.position.y - 14.0 - 20.0 * lines.size()),
		Vector2(w + 20.0, 20.0 * lines.size() + 10.0))
	box.position.x = clampf(box.position.x, 4.0, maxf(4.0, size.x - box.size.x - 4.0))
	box.position.y = maxf(4.0, box.position.y)
	ci.draw_rect(box, Color(_NAVY.r, _NAVY.g, _NAVY.b, 0.95))
	ci.draw_rect(box, _CREAM, false, 1.0)
	for i in range(lines.size()):
		ci.draw_string(font, box.position + Vector2(10.0, 20.0 + 20.0 * float(i)), str(lines[i]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, DS.PALETTE.TEXT)


## Goods on the move. A shipment really in transit is one token with its quantity, sitting
## where its turns put it along the route and creeping through the turn ahead. A way with
## nothing in transit right now, and every run between a building and its warehouse, shows a
## steady trickle. Fluid in a pipe is a bright slug in the tube; power is a pulse on the cable.
func _draw_tokens(layer: Control) -> void:
	var box := clampf(44.0 * _zoom + 10.0, 16.0, 40.0)
	var view := Rect2(Vector2.ZERO, size).grow(box)
	var font := get_theme_default_font()
	_draw_glints(layer, view)
	_draw_cars(layer, view)
	if bool(show["pollution"]):
		_draw_fog(layer, view)
		_draw_lights(layer, view)
	_draw_smoke(layer, view)
	# Every icon of a good is drawn here, over the light and the mist. What stands still is placed first: the
	# pylons' power, then the pipes' signs, a sign whose place is taken on a taller post. Then the goods on the
	# move, each where its route puts it. Where moving goods meet, the smaller group fades as they cross and
	# comes back on the other side (_moving_alpha); none is pushed aside or dropped.
	var placed: Array = []
	var tiles: Dictionary = _model.get("tiles", {})
	var goods: bool = show["goods"]
	if goods and not animate_goods:
		_draw_made(layer, view, box, placed)
	# Power is shown on the pylons, not as something travelling.
	for s in _standing:
		if str(s["kind"]) != "pylon":
			continue
		var icon: Texture2D = (tiles.get(s["tile"], {}) as Dictionary).get("power_icon")
		var r: Rect2 = s["rect"]
		var at := Vector2(r.get_center().x, r.position.y + r.size.y * 0.52) * _zoom + _offset
		var room := Rect2(at - Vector2(box, box) * 0.45, Vector2(box, box) * 0.9)
		if icon != null and view.has_point(at) and not _taken(placed, room):
			placed.append(room)
			_token(layer, at, box * 0.9, icon)
	var plate := maxf(_SIGN_PLATE * _zoom, _SIGN_MIN_PX)
	for sg in _signs:
		var foot: Vector2 = (sg["foot"] as Vector2) * _zoom + _offset
		if not goods or not view.has_point(foot):
			continue
		var icons: Array = sg["icons"]
		var top: Vector2 = (sg["top"] as Vector2) * _zoom + _offset
		var room := Rect2(top - Vector2(plate * 0.5 * float(icons.size()), plate * 0.9), Vector2(plate * float(icons.size()), plate))
		var lifts := 0
		while _taken(placed, room.grow(plate * 0.12)) and lifts < 5:
			room.position.y -= plate * 1.2
			lifts += 1
		if _taken(placed, room.grow(plate * 0.12)):
			continue
		placed.append(room.grow(plate * 0.12))
		_draw_sign(layer, foot, room, icons)
	# The goods on the move: [{p, dir, size, icon, qty, rank, flow}].
	var moving: Array = []
	for fi in _flows.size():
		var f: Dictionary = _flows[fi]
		var total := float(f["total"])
		var style := str(f["style"])
		if not animate_goods:
			break
		if style == "goods" and not goods:
			continue
		if style == "goods" and not (f["live"] as Array).is_empty():
			# A shipment really in transit, where its turns put it; two at one place stand side by side.
			var beside: Array = []
			for sh in f["live"]:
				var duration := float(sh["duration"])
				var done := duration - float(sh["remaining"])
				var creep := 0.0 if bool(sh["waiting"]) else smoothstep(0.0, 1.0, fmod(_clock / _LIVE_CREEP_SECS, 1.0))
				var d_at := clampf((done + creep) / duration, 0.0, 1.0) * total
				var at := _along(f, d_at) * _zoom + _offset
				var big := box * 1.12
				var room := Rect2(at - Vector2(big, big) * 0.5, Vector2(big, big))
				var tries := 0
				while _taken(beside, room) and tries < 6:
					room.position.x += big + 3.0
					at.x += big + 3.0
					tries += 1
				beside.append(room)
				if view.has_point(at):
					moving.append({"p": at, "dir": _dir_at(f, d_at), "size": big, "icon": f["icon"],
						"qty": int(sh["qty"]), "rank": 1, "flow": fi})
			continue
		var d := fmod(_clock * _TOKEN_SPEED + float(f["phase"]), _TOKEN_SPACING)
		if style != "goods":
			d = fmod(_clock * _TOKEN_SPEED * 1.6 + float(f["phase"]), _PULSE_SPACING)
		while d < total:
			var p := _along(f, d) * _zoom + _offset
			if view.has_point(p):
				if style == "power":
					layer.draw_circle(p, clampf(4.0 * _zoom + 1.5, 2.0, 5.0), _CABLE.lightened(0.4))
				else:
					moving.append({"p": p, "dir": _dir_at(f, d), "size": box, "icon": f["icon"], "qty": -1, "rank": 0, "flow": fi})
			d += _TOKEN_SPACING if style == "goods" else _PULSE_SPACING
	var alphas := _moving_alpha(moving, placed, box)
	for i in moving.size():
		var m: Dictionary = moving[i]
		var a: float = alphas[i]
		if a <= 0.01:
			continue
		var at: Vector2 = m["p"]
		_token(layer, at, float(m["size"]), m["icon"], a)
		if int(m["qty"]) >= 0:
			var text := str(int(m["qty"]))
			var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			var pill := Rect2(at + Vector2(-w * 0.5 - 5.0, box * 0.5), Vector2(w + 10.0, 16.0))
			layer.draw_rect(pill, Color(_NAVY, a))
			layer.draw_string(font, pill.position + Vector2(5.0, 12.0), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(DS.PALETTE.TEXT, a))
	# Cables hang between tiles, so they belong to no one tile's picture.
	layer.draw_set_transform(_offset, 0.0, Vector2(_zoom, _zoom))
	for c in _cables:
		layer.draw_polyline(c, _CABLE_DARK, 2.0, true)
		layer.draw_polyline(c, _CABLE_STRIPE, 0.55, true)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if bool(show["names"]):
		_draw_labels(layer)
	_draw_hover(layer)


func _draw_glows(layer: Control) -> void:
	if _glows.is_empty() or not bool(show["pollution"]):
		return
	if _glow_tex == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
		grad.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
		grad.add_point(0.4, Color(1.0, 1.0, 1.0, 0.42))
		_glow_tex = GradientTexture2D.new()
		_glow_tex.gradient = grad
		_glow_tex.fill = GradientTexture2D.FILL_RADIAL
		_glow_tex.fill_from = Vector2(0.5, 0.5)
		_glow_tex.fill_to = Vector2(1.0, 0.5)
		_glow_tex.width = 128
		_glow_tex.height = 128
	var view := Rect2(Vector2.ZERO, size)
	for g in _glows:
		var p: Vector2 = (g["at"] as Vector2) * _zoom + _offset
		var half := Vector2(float(g["rx"]), float(g["ry"])) * _zoom
		if not view.grow(half.x).has_point(p):
			continue
		layer.draw_texture_rect(_glow_tex, Rect2(p - half, half * 2.0), false,
			Color(_LAMP_LIGHT.r, _LAMP_LIGHT.g, _LAMP_LIGHT.b, float(g["a"])))


## The mist of dirty air: each wisp a soft-edged patch, drifting a little on its own beat.
func _draw_fog(layer: Control, view: Rect2) -> void:
	if _fog.is_empty():
		return
	if _wisp == null:
		var grad := Gradient.new()
		grad.set_color(0, Color(_SOOT.r, _SOOT.g, _SOOT.b, 1.0))
		grad.set_color(1, Color(_SOOT.r, _SOOT.g, _SOOT.b, 0.0))
		grad.add_point(0.45, Color(_SOOT.r, _SOOT.g, _SOOT.b, 0.55))
		_wisp = GradientTexture2D.new()
		_wisp.gradient = grad
		_wisp.fill = GradientTexture2D.FILL_RADIAL
		_wisp.fill_from = Vector2(0.5, 0.5)
		_wisp.fill_to = Vector2(1.0, 0.5)
		_wisp.width = 128
		_wisp.height = 128
	for w in _fog:
		var drift := Vector2(sin(_clock * 0.11 + float(w["phase"])) * 14.0, cos(_clock * 0.07 + float(w["phase"]) * 1.7) * 5.0)
		var p: Vector2 = ((w["at"] as Vector2) + drift) * _zoom + _offset
		var r := float(w["r"]) * _zoom
		if not view.grow(r).has_point(p):
			continue
		var breath := 0.82 + 0.18 * sin(_clock * 0.23 + float(w["phase"]) * 2.3)
		layer.draw_texture_rect(_wisp, Rect2(p - Vector2(r, r * 0.62), Vector2(r, r * 0.62) * 2.0), false,
			Color(1.0, 1.0, 1.0, float(w["a"]) * breath))


## The mask of a sprite's windows (tools/bake_window_masks.py), or null when it has none.
static func _window_mask(sprite: Texture2D) -> Texture2D:
	var path := _WINDOW_DIR + sprite.resource_path.get_file()
	if not _window_tex.has(path):
		_window_tex[path] = load(path) if ResourceLoader.exists(path) else null
	return _window_tex[path]


## Windows and fires, drawn over the mist so they shine through it.
func _draw_lights(layer: Control, view: Rect2) -> void:
	for l in _lights:
		var r: Rect2 = l["rect"]
		var sr := Rect2(r.position * _zoom + _offset, r.size * _zoom)
		if not view.intersects(sr):
			continue
		var col: Color = l["col"]
		var glow := 0.86 + 0.14 * sin(_clock * 0.9 + float(l["phase"]))
		layer.draw_texture_rect(l["tex"], sr, false, Color(col.r, col.g, col.b, col.a * glow))


## The sun catching the water: each glint flares and dies on its own beat.
func _draw_glints(layer: Control, view: Rect2) -> void:
	for g in _glints:
		var p: Vector2 = (g["at"] as Vector2) * _zoom + _offset
		if not view.has_point(p):
			continue
		var beat := pow(maxf(0.0, sin(_clock * 1.6 * float(g["rate"]) + float(g["phase"]))), 6.0)
		if beat < 0.04:
			continue
		# A thin pill of light lying along the water's grid line, growing and fading with its beat.
		var arm := clampf(5.0 * _zoom + 1.5, 2.0, 6.0) * (0.5 + beat)
		var col := Color(_GLINT.r, _GLINT.g, _GLINT.b, beat)
		var along := Vector2(ISO_X, ISO_Y).normalized() * arm
		var w := clampf(1.2 * _zoom + 0.8, 1.2, 2.2)
		layer.draw_line(p - along, p + along, col, w, true)
		layer.draw_circle(p - along, w * 0.5, col, true, -1.0, true)
		layer.draw_circle(p + along, w * 0.5, col, true, -1.0, true)


## Chimneys: grey smoke from a dirty works, white steam from a clean one, as the inked puffs
## the sprites' own effects use, billowing up and leaning with the wind.
func _draw_smoke(layer: Control, view: Rect2) -> void:
	var n := 0
	for st in _stacks:
		n += 1
		var mouth: Vector2 = (st["at"] as Vector2) * _zoom + _offset
		if not view.grow(120.0).has_point(mouth):
			continue
		var r := float(st["r"]) * _zoom
		var texs: Array = EmpireFx.PUFF_SMOKE_TEX if bool(st["smoke"]) else EmpireFx.PUFF_STEAM_TEX
		# Oldest first, so the fresh puff at the mouth sits on top of the plume.
		for i in range(_PUFFS):
			var p := fmod(_clock / _PUFF_SECS + float(i) / float(_PUFFS) + float(st["phase"]), 1.0)
			var rose := 1.0 - pow(1.0 - p, 1.6)
			var centre := mouth + Vector2(0.0, -r) + EmpireFx.DRIFT_DIR.normalized() * (_PUFF_RISE * r) * rose
			var half := r * lerpf(1.2, 4.0, pow(p, 0.75)) * EmpireFx.PUFF_TEX_SPAN
			var alpha := 0.95 * pow(1.0 - p, 1.1)
			if alpha <= 0.01:
				continue
			layer.draw_set_transform(centre, p * EmpireFx.SPIN * (1.0 if (i + n) % 2 == 0 else -1.0), Vector2.ONE)
			layer.draw_texture_rect(texs[(i + n) % texs.size()], Rect2(-half, -half, half * 2.0, half * 2.0), false,
				Color(1.0, 1.0, 1.0, alpha))
		layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _along(f: Dictionary, d: float) -> Vector2:
	var pts: PackedVector2Array = f["pts"]
	var cum: PackedFloat32Array = f["cum"]
	var seg := 0
	while seg < cum.size() - 2 and cum[seg + 1] < d:
		seg += 1
	var span := maxf(0.001, cum[seg + 1] - cum[seg])
	return pts[seg].lerp(pts[seg + 1], clampf((d - cum[seg]) / span, 0.0, 1.0))


## The board at rest: over each building, a token for each good it makes, side by side.
func _draw_made(layer: Control, view: Rect2, box: float, placed: Array) -> void:
	var made: Dictionary = _model.get("made", {})
	if made.is_empty():
		return
	for s in _standing:
		var goods_made: Array = made.get(str(s["iid"]), [])
		if goods_made.is_empty():
			continue
		var r: Rect2 = s["rect"]
		var top := Vector2(r.get_center().x, r.position.y + r.size.y * 0.25) * _zoom + _offset
		if not view.has_point(top):
			continue
		var step := box + 4.0
		var x0 := top.x - step * float(goods_made.size() - 1) * 0.5
		for i in goods_made.size():
			var at := Vector2(x0 + step * float(i), top.y)
			placed.append(Rect2(at - Vector2(box, box) * 0.5, Vector2(box, box)))
			_token(layer, at, box, Model.GoodIcons.texture_for(str(goods_made[i]), Model._internal_name(str(goods_made[i]))))


func _token(layer: Control, p: Vector2, box: float, icon: Texture2D, alpha: float = 1.0) -> void:
	layer.draw_circle(p, box * 0.5 + 1.5, Color(_NAVY, _NAVY.a * alpha), true, -1.0, true)
	layer.draw_circle(p, box * 0.5, Color(_CREAM, _CREAM.a * alpha), true, -1.0, true)
	if icon != null:
		var isz := box * 0.74
		layer.draw_texture_rect(icon, Rect2(p - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, alpha))


## The way a route runs at distance `d` along it, on screen (a unit vector).
func _dir_at(f: Dictionary, d: float) -> Vector2:
	var total := float(f["total"])
	var a := _along(f, clampf(d - 2.0, 0.0, total))
	var b := _along(f, clampf(d + 2.0, 0.0, total))
	return (b - a).normalized() if a.distance_squared_to(b) > 0.0001 else Vector2.RIGHT


## How solid each moving good is drawn. A good's group is the goods near it heading the same way. Where two
## overlap, the one in the smaller group fades, the more the closer they are, and is whole again once clear;
## between equal groups a shipment outranks a route's traffic, then the earlier route. A good over a pylon's
## power or a pipe's sign fades the same way.
func _moving_alpha(moving: Array, still: Array, box: float) -> Array:
	var n := moving.size()
	var crowd: Array = []
	crowd.resize(n)
	for i in n:
		var c := 0
		for j in n:
			if (moving[i]["p"] as Vector2).distance_to(moving[j]["p"]) < box * MOVING_GROUP_REACH \
					and (moving[i]["dir"] as Vector2).dot(moving[j]["dir"]) > MOVING_SAME_WAY:
				c += 1
		crowd[i] = c
	var out: Array = []
	out.resize(n)
	for i in n:
		var a := 1.0
		var pi: Vector2 = moving[i]["p"]
		for j in n:
			if j == i:
				continue
			var dist := pi.distance_to(moving[j]["p"])
			var touch := (float(moving[i]["size"]) + float(moving[j]["size"])) * 0.5
			if dist >= touch:
				continue
			var yields: bool = int(crowd[i]) < int(crowd[j]) or (int(crowd[i]) == int(crowd[j])
				and (int(moving[i]["rank"]) < int(moving[j]["rank"])
				or (int(moving[i]["rank"]) == int(moving[j]["rank"]) and int(moving[i]["flow"]) > int(moving[j]["flow"]))))
			if yields:
				a = minf(a, lerpf(MOVING_FADED, 1.0, smoothstep(0.35, 1.0, dist / touch)))
		for r: Rect2 in still:
			var reach := (r.size.x + float(moving[i]["size"])) * 0.5
			var dist2 := pi.distance_to(r.get_center())
			if dist2 < reach:
				a = minf(a, lerpf(MOVING_FADED, 1.0, smoothstep(0.35, 1.0, dist2 / reach)))
		out[i] = a
	return out


# ------------------------------------------------------------------ input

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / _ZOOM_STEP)
		elif mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_press_pos = mb.position
				_dragging = false
			else:
				if not _dragging and mb.button_index == MOUSE_BUTTON_LEFT:
					_click(mb.position)
				_press_pos = Vector2.INF
				_dragging = false
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _press_pos != Vector2.INF:
			if not _dragging and mm.position.distance_to(_press_pos) > _DRAG_SLOP:
				_dragging = true
			if _dragging:
				_offset += mm.relative
				_view_changed()
		else:
			_set_hover(_pick(mm.position))
	elif event is InputEventMagnifyGesture:
		_zoom_at((event as InputEventMagnifyGesture).position, (event as InputEventMagnifyGesture).factor)
		accept_event()
	elif event is InputEventPanGesture:
		_offset -= (event as InputEventPanGesture).delta * 12.0
		_view_changed()
		accept_event()


func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var z := clampf(_zoom * factor, _ZOOM_MIN, _ZOOM_MAX)
	var board := (screen_pos - _offset) / _zoom
	_zoom = z
	_offset = screen_pos - board * _zoom
	_view_changed()


## What answers the pointer: the company's own buildings, sites and warehouses, and Local Suppliers' depot.
## Housing, the city, ports and pylons are scenery.
const _PICKABLE := ["building", "site", "warehouse", "suppliers"]


## The company's or Local Suppliers' thing under a screen point, nearest the camera first.
func _pick(screen_pos: Vector2) -> Dictionary:
	var board := (screen_pos - _offset) / _zoom
	for i in range(_standing.size() - 1, -1, -1):
		if str(_standing[i]["kind"]) in _PICKABLE and (_standing[i]["rect"] as Rect2).has_point(board):
			return _standing[i]
	return {}


func _set_hover(s: Dictionary) -> void:
	if str(s.get("iid", "")) == str(_hover.get("iid", "")):
		return
	_hover = s
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if str(s.get("kind", "")) in ["building", "site", "suppliers"] \
		else Control.CURSOR_ARROW
	queue_redraw()


func _click(screen_pos: Vector2) -> void:
	var s := _pick(screen_pos)
	if str(s.get("kind", "")) in ["building", "site"]:
		building_picked.emit(str(s["iid"]))
	elif str(s.get("kind", "")) == "suppliers":
		suppliers_picked.emit()
