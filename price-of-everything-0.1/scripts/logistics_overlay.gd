extends Node2D
const GoodHover := preload("res://scripts/good_icon_hover.gd")
## Logistics map overlay.
##
## When the Logistics mapmode is active: dim the map and draw every
## origin->destination route as a thick coloured line (soft white glow) tile-centre
## to tile-centre, triangle at origin, 60x60 box at destination. Each in-transit
## shipment gets a 120x60 pentagon (rectangle + tip toward the destination) in the
## route colour with turns-to-go in bold white; hover it for the goods breakdown.
## Parallel routes sharing tiles spread 50px apart and cross when they diverge.
##
## During the turn transition (TurnManager's 5 resolution phases x 0.5s = 2.5s) the
## shipment pentagons also appear on the NORMAL map (no dim/lines), gliding from
## their current tile to the next in 5 equal hops; the turn number is HELD during
## the move and counts down once the new turn starts. They vanish when resolution ends.
##
## NOTE: sizes are world-units, tuned by eye — expect in-engine tweaks.

@onready var terrain_layer: HexMap = %TerrainLayer

const GoodIcons := preload("res://scripts/good_icons.gd")
const TileViewData := preload("res://scripts/tile_view_data.gd")
const SEMIBOLD_FONT: Font = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")

# Stockpile hover panel: a square that's STOCK_PANEL_MIN px on screen at max
# zoom-in and STOCK_PANEL_MAX px at max zoom-out (interpolated by zoom).
const STOCK_PANEL_MIN := 200.0
const STOCK_PANEL_MAX := 300.0
const STOCK_PANEL_BARS := 6
const STOCK_BAR_COLORS := [
	Color(0.36, 0.82, 0.5), Color(0.42, 0.65, 0.84), Color(0.9, 0.72, 0.36),
	Color(0.76, 0.82, 0.9), Color(0.55, 0.62, 0.70),
]

const LINE_WIDTH := 20.0
const DEST_BOX := 60.0
const TAG_LEN := 120.0
const TAG_WID := 60.0
const TAG_TIP := 30.0
const PARALLEL_GAP := 50.0
const TRIANGLE_LEN := 30.0
const TRIANGLE_HALF := 18.0
const PANEL := Vector2(120, 120)
# 10% transparent black: route/tile masks read clearly over muted terrain.
const DIM_COLOUR := Color(0, 0, 0, 0.90)
const TILE_MASK_ALPHA := 0.5
const ANIM_TOTAL_STEPS := 5
const PALETTE: Array = [
	Color(0.13, 0.55, 0.13), Color(0.95, 0.83, 0.18), Color(0.47, 0.78, 1.0),
	Color(0.55, 0.35, 0.88), Color(0.22, 0.22, 0.22), Color(0.95, 0.48, 0.14),
	Color(0.48, 0.90, 0.72), Color(0.25, 0.41, 0.88),
]

var _routes: Array = []
var _tag_hits: Array = []
var _hover_tag := -1
# Turn-transition animation
var _resolving := false
var _anim_steps := 0
var _anim_snapshot: Array = []  # [{pos_a, pos_b, dir, turns, goods, color}]
# Move-destination preview (shown while picking a Move destination)
var _move_preview_source := ""
var _move_preview_goods: Dictionary = {}
# Transfer flow (market "Move"): per-tile highlights + origin/dest + dashed line
var _transfer_active := false
var _transfer_highlights: Dictionary = {}  # tile_id -> Color
var _transfer_origin := ""
var _transfer_dest := ""
var _transfer_line_color := Color(0.95, 0.83, 0.18)
# Hover info panel (transfer / buy / sell flows): shows the hovered tile's
# per-turn production and current stockpile of the active good.
var _hover_good := ""

func _ready() -> void:
	add_to_group("logistics_overlay")
	visible = false
	set_process(false)
	MapMode.selections_changed.connect(_on_mode_changed)
	MapMode.mode_cleared.connect(_on_mode_cleared)
	TurnManager.turn_resolution_started.connect(_on_resolution_started)
	TurnManager.phase_completed.connect(_on_phase_completed)
	TurnManager.turn_resolution_completed.connect(_on_resolution_completed)

func _update_visibility() -> void:
	var active := MapMode.current_mode == MapMode.Mode.LOGISTICS or _resolving or _move_preview_source != "" or _transfer_active
	visible = active
	set_process(active)
	queue_redraw()

func set_transfer_state(active: bool, highlights: Dictionary, origin: String, dest: String, line_color: Color = Color(0.95, 0.83, 0.18)) -> void:
	_transfer_active = active
	_transfer_highlights = highlights.duplicate()
	_transfer_origin = origin
	_transfer_dest = dest
	_transfer_line_color = line_color
	_update_visibility()

func clear_transfer() -> void:
	_transfer_active = false
	_transfer_highlights = {}
	_transfer_origin = ""
	_transfer_dest = ""
	_hover_good = ""
	_update_visibility()

func set_hover_good(good_id: String) -> void:
	_hover_good = good_id
	queue_redraw()

func clear_hover_good() -> void:
	_hover_good = ""
	queue_redraw()

func _hover_tile_production_per_turn(tile_id: String, good_id: String) -> int:
	var total := 0
	for iid in MatchState.tile_buildings.get(tile_id, []):
		var b: Dictionary = MatchState.get_building(str(iid))
		var recipe: Dictionary = Catalog.get_recipe(str(b.get("recipe_id", "")))
		total += Catalog.recipe_output_qty(recipe, good_id)
	return total

func _draw_hover_good_info() -> void:
	# Transfer / buy flow: the active good is fixed; the hovered tile comes from the
	# destination-selection tracking.
	if _hover_good == "":
		return
	var hovered := terrain_layer.get_hovered_destination_tile_id()
	if hovered != "":
		_draw_tile_good_card(hovered, _hover_good)

func _draw_logistics_hover_info() -> void:
	# Logistics mapmode: hovering a tile shows its stockpile chart. The shipment
	# hover panel takes precedence when the cursor is over a shipment tag.
	if _hover_tag >= 0:
		return
	var tile_id := terrain_layer.tile_id_under_mouse()
	if tile_id != "":
		_draw_stockpile_panel(tile_id)

# Screen-space side length of the hover panel (interpolated 200→600px by zoom).
func _stock_panel_screen_size() -> float:
	var cam := get_viewport().get_camera_2d()
	if cam == null:
		return 0.5 * (STOCK_PANEL_MIN + STOCK_PANEL_MAX)
	var zmin := 1.0
	var zmax := 4.0
	var zn = cam.get("zoom_min")
	var zx = cam.get("zoom_max")
	if zn != null:
		zmin = float(zn)
	if zx != null:
		zmax = float(zx)
	var t := clampf((cam.zoom.x - zmin) / maxf(0.0001, zmax - zmin), 0.0, 1.0)
	return lerpf(STOCK_PANEL_MAX, STOCK_PANEL_MIN, t)  # zoomed out → big, zoomed in → small

# A rounded, lit panel above the tile: the tile name, then "Stockpile" + fullness
# %, then the same bar-per-good chart as the tile view panel.
func _draw_stockpile_panel(tile_id: String) -> void:
	var pos := _tile_pos(tile_id)
	if pos == Vector2.INF:
		return
	# Highlight the hovered tile in transparent cream.
	_draw_hover_highlight(pos)

	var stock: Dictionary = TileViewData.stockpile_summary(tile_id)
	var z := maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	var s := _stock_panel_screen_size() / z   # base world size for the target screen size
	# Wider by ~40px and taller by ~30px (plus a tile-name row), all scaling with zoom.
	var extra := s / 200.0   # 1 unit ≈ 1px at the min panel size
	var w := s + 40.0 * extra
	var h := s + 30.0 * extra + s * 0.18   # +30px breathing + the new name row
	var tile_w: float = terrain_layer.tile_set.tile_size.x
	var origin := pos - Vector2(w * 0.5, h + tile_w * 0.30)
	var rect := Rect2(origin, Vector2(w, h))
	var radius := s * 0.06
	var border := maxf(2.0, s * 0.025)   # ~5px at min size

	# Rounded navy plate with a thick cream bevel outline.
	var sb := StyleBoxFlat.new()
	sb.bg_color = DS.PALETTE.BG_CARD
	sb.set_corner_radius_all(int(radius))
	sb.set_border_width_all(int(border))
	sb.border_color = DS.PALETTE.BORDER
	draw_style_box(sb, rect)
	# Diagonal light (top-left → bottom-right) over plate + bevel.
	_draw_diag_light(rect, Color(1, 1, 1, 0.10), Color(0, 0, 0, 0.16))
	_draw_bevel(rect, border, radius, Color(1, 1, 1, 0.40), Color(0.10, 0.07, 0.02, 0.40))

	var pad := w * 0.06
	var font := ThemeDB.fallback_font
	# Row 1: tile name (SemiBold 22). Row 2: "Stockpile" (SemiBold) + fullness %.
	var name_h := s * 0.17
	var head_h := s * 0.17
	var name_y := origin.y + border + name_h * 0.74
	var head_y := origin.y + border + name_h + head_h * 0.74
	_stock_text(SEMIBOLD_FONT, Catalog.tile_label(tile_id), Vector2(origin.x + w * 0.5, name_y), int(s * 0.10), DS.PALETTE.ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	var pct: float = float(stock.get("pct", 0.0))
	var pct_text: String = "FULL" if bool(stock.get("is_full", false)) else "%d%%" % roundi(pct * 100.0)
	var pct_col: Color = DS.PALETTE.DANGER if bool(stock.get("is_full", false)) else (DS.PALETTE.WARN if pct >= 0.9 else DS.PALETTE.TEXT_MUTED)
	_stock_text(SEMIBOLD_FONT, "Stockpile", Vector2(origin.x + pad, head_y), int(s * 0.10), DS.PALETTE.ACCENT, HORIZONTAL_ALIGNMENT_LEFT)
	_stock_text(font, pct_text, Vector2(origin.x + w - pad, head_y), int(s * 0.075), pct_col, HORIZONTAL_ALIGNMENT_RIGHT)
	var div_y := origin.y + border + name_h + head_h
	draw_line(Vector2(origin.x + pad, div_y), Vector2(origin.x + w - pad, div_y), DS.PALETTE.BORDER_SOFT, maxf(1.0, 1.5 / z))

	var goods: Array = stock.get("goods", [])
	if goods.is_empty():
		_stock_text(font, "Stockpile is empty", Vector2(origin.x + w * 0.5, div_y + (rect.end.y - div_y) * 0.5), int(s * 0.06), DS.PALETTE.TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER)
		return

	# Lump overflow goods into a single "Other" bar, like the TVP.
	var shown: Array = goods
	var other_sum := 0
	if goods.size() > STOCK_PANEL_BARS:
		shown = goods.slice(0, STOCK_PANEL_BARS - 1)
		for i in range(STOCK_PANEL_BARS - 1, goods.size()):
			other_sum += int(goods[i].qty)
	var bar_count: int = shown.size() + (1 if other_sum > 0 else 0)
	var max_qty := 1
	for g in shown:
		max_qty = maxi(max_qty, int(g.qty))
	max_qty = maxi(max_qty, other_sum)

	var area_left := origin.x + pad
	var area_w := w - 2.0 * pad
	var col_w := area_w / float(bar_count)
	var icon_sz: float = minf(col_w * 0.74, s * 0.16)
	var baseline := rect.end.y - border - icon_sz - s * 0.02
	var bar_top := div_y + s * 0.08
	var bar_max_h := baseline - bar_top
	var bar_w: float = minf(col_w * 0.5, s * 0.12)
	var qty_fs := int(s * 0.055)

	var idx := 0
	for g in shown:
		_draw_stock_bar_im(area_left + col_w * float(idx), col_w, baseline, bar_max_h, bar_w,
			int(g.qty), max_qty, STOCK_BAR_COLORS[idx % STOCK_BAR_COLORS.size()], str(g.good_id), font, qty_fs, icon_sz)
		idx += 1
	if other_sum > 0:
		_draw_stock_bar_im(area_left + col_w * float(idx), col_w, baseline, bar_max_h, bar_w,
			other_sum, max_qty, DS.PALETTE.TEXT_DIM, "", font, qty_fs, icon_sz)

func _draw_stock_bar_im(col_x: float, col_w: float, baseline: float, bar_max_h: float, bar_w: float,
		qty: int, max_qty: int, color: Color, good_id: String, font: Font, qty_fs: int, icon_sz: float) -> void:
	var cx := col_x + col_w * 0.5
	var bh: float = maxf(2.0, bar_max_h * (float(qty) / float(max_qty)))
	var bar_rect := Rect2(cx - bar_w * 0.5, baseline - bh, bar_w, bh)
	# Embossed bar: filled body, dark rim, and a diagonal sheen.
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = color
	bsb.set_corner_radius_all(int(maxf(2.0, bar_w * 0.2)))
	bsb.set_border_width_all(maxi(1, int(bar_w * 0.08)))
	bsb.border_color = color.darkened(0.45)
	draw_style_box(bsb, bar_rect)
	_draw_diag_light(bar_rect, Color(1, 1, 1, 0.28), Color(0, 0, 0, 0.28))
	_stock_text(font, str(qty), Vector2(cx, baseline - bh - qty_fs * 0.3), qty_fs, DS.PALETTE.TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	if good_id != "":
		var tex := GoodIcons.texture_for(good_id, Catalog.get_internal_name(good_id))
		if tex != null:
			GoodHover.drawn(self, Rect2(cx - icon_sz * 0.5, baseline + icon_sz * 0.05, icon_sz, icon_sz), good_id)
			draw_texture_rect(tex, Rect2(cx - icon_sz * 0.5, baseline + icon_sz * 0.05, icon_sz, icon_sz), false)

# Transparent cream mask over the hovered tile's hex.
func _draw_hover_highlight(center: Vector2) -> void:
	var r: float = terrain_layer.tile_set.tile_size.x * 0.5
	var cream: Color = DS.PALETTE.ACCENT
	draw_colored_polygon(_hex_points(center, r), Color(cream.r, cream.g, cream.b, TILE_MASK_ALPHA))

# A subtle top-left → bottom-right light wash over a rect (vertex-colour quad).
func _draw_diag_light(rect: Rect2, light: Color, dark: Color) -> void:
	var mid := light.lerp(dark, 0.5)
	var pts := PackedVector2Array([
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)])
	draw_polygon(pts, PackedColorArray([light, mid, dark, mid]))

# Inner bevel highlight/shadow lines so the cream outline catches the light.
func _draw_bevel(rect: Rect2, bw: float, radius: float, hi: Color, lo: Color) -> void:
	var x := rect.position.x
	var y := rect.position.y
	var w := rect.size.x
	var hgt := rect.size.y
	var lw := maxf(1.0, bw * 0.45)
	var inn := bw
	draw_line(Vector2(x + radius, y + inn), Vector2(x + w - radius, y + inn), hi, lw)          # top
	draw_line(Vector2(x + inn, y + radius), Vector2(x + inn, y + hgt - radius), hi, lw)          # left
	draw_line(Vector2(x + radius, y + hgt - inn), Vector2(x + w - radius, y + hgt - inn), lo, lw) # bottom
	draw_line(Vector2(x + w - inn, y + radius), Vector2(x + w - inn, y + hgt - radius), lo, lw)   # right

# Draws text with the given horizontal alignment; `anchor` is the baseline point.
func _stock_text(font: Font, text: String, anchor: Vector2, fs: int, color: Color, align: int) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := anchor.x
	if align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= w * 0.5
	elif align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= w
	draw_string(font, Vector2(x, anchor.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

func _draw_tile_good_card(tile_id: String, good_id: String) -> void:
	# A 2-cell card over the tile: production/turn (left) + stockpile (right), with the
	# good name as a header straddling both. ~160x80 at max zoom, snapped to 3 zoom
	# steps like the shipment hover panel.
	var pos := _tile_pos(tile_id)
	if pos == Vector2.INF:
		return
	var prod := _hover_tile_production_per_turn(tile_id, good_id)
	var stock := Stockpile.get_at_tile(tile_id, good_id)

	var z := maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	var tile_w: float = terrain_layer.tile_set.tile_size.x
	var quarter_screen := tile_w * 0.25 * z
	var step_px := 100.0
	if quarter_screen > 320.0:
		step_px = 160.0
	elif quarter_screen > 240.0:
		step_px = 130.0
	var world_w := step_px / z
	var world_h := world_w * 0.5
	var origin := pos - Vector2(world_w / 2.0, world_h + tile_w * 0.35)
	var line_w := maxf(1.0, 2.0 / z)
	var header_h := world_h * 0.40
	var mid := origin.x + world_w / 2.0
	var font := ThemeDB.fallback_font

	# Backplate + header strip + divider.
	draw_rect(Rect2(origin, Vector2(world_w, world_h)), Color(0.03, 0.05, 0.09, 0.97))
	draw_rect(Rect2(origin, Vector2(world_w, header_h)), Color(0.10, 0.16, 0.26, 0.98))
	draw_rect(Rect2(origin, Vector2(world_w, world_h)), Color(0.7, 0.85, 1.0, 0.6), false, line_w)
	draw_line(Vector2(mid, origin.y + header_h), Vector2(mid, origin.y + world_h), Color(0.7, 0.85, 1.0, 0.4), line_w)
	draw_line(Vector2(origin.x, origin.y + header_h), Vector2(origin.x + world_w, origin.y + header_h), Color(0.7, 0.85, 1.0, 0.4), line_w)

	# Header (good name).
	_draw_card_text(font, Catalog.get_display_name(good_id),
		Rect2(origin.x, origin.y, world_w, header_h), int(maxf(7.0, header_h * 0.52)),
		Color(0.92, 0.96, 1.0), 0.5)
	# Cells: production/turn (left), stockpile (right).
	var body_y := origin.y + header_h
	var body_h := world_h - header_h
	var cell_w := world_w / 2.0
	var val_fs := int(maxf(8.0, body_h * 0.44))
	var cap_fs := int(maxf(6.0, body_h * 0.24))
	_draw_card_text(font, "%d" % prod, Rect2(origin.x, body_y, cell_w, body_h), val_fs, Color.WHITE, 0.40)
	_draw_card_text(font, "/turn", Rect2(origin.x, body_y, cell_w, body_h), cap_fs, Color(0.75, 0.85, 0.95), 0.80)
	_draw_card_text(font, "%d" % stock, Rect2(mid, body_y, cell_w, body_h), val_fs, Color.WHITE, 0.40)
	_draw_card_text(font, "in stock", Rect2(mid, body_y, cell_w, body_h), cap_fs, Color(0.75, 0.85, 0.95), 0.80)

func _draw_card_text(font: Font, text: String, rect: Rect2, fs: int, color: Color, v_frac: float) -> void:
	# Horizontally centred in rect; baseline at v_frac of the rect height.
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := rect.position + Vector2((rect.size.x - w) / 2.0, rect.size.y * v_frac)
	draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)

func set_move_preview(source: String, goods: Dictionary) -> void:
	_move_preview_source = source
	_move_preview_goods = goods.duplicate(true)
	_update_visibility()

func clear_move_preview() -> void:
	_move_preview_source = ""
	_move_preview_goods = {}
	_update_visibility()

func _draw_move_preview() -> void:
	var hovered := terrain_layer.get_hovered_destination_tile_id()
	if hovered == "" or hovered == _move_preview_source:
		return
	var pos := _tile_pos(hovered)
	if pos == Vector2.INF:
		return
	var preview: Dictionary = MatchState.preview_move(_move_preview_source, hovered, _move_preview_goods)
	var turns := int(preview.get("turns", 0))
	var text := "£%.2f/turn · %d turn%s" % [float(preview.get("per_turn", 0.0)), turns, "" if turns == 1 else "s"]
	var tile_w: float = terrain_layer.tile_set.tile_size.x
	var font := maxf(12.0, tile_w * 0.055)  # world units — scales with zoom, ~shipment-overlay size
	var tw: float = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(font)).x
	var pad := font * 0.5
	var box := Vector2(tw + 2.0 * pad, font + 2.0 * pad)
	var origin := pos - Vector2(box.x / 2.0, box.y + tile_w * 0.35)
	draw_rect(Rect2(origin, box), Color(0.03, 0.05, 0.09, 0.95))
	draw_rect(Rect2(origin, box), Color(0.7, 0.85, 1.0, 0.6), false, 2.0)
	draw_string(ThemeDB.fallback_font, origin + Vector2(pad, pad + font * 0.85), text,
		HORIZONTAL_ALIGNMENT_LEFT, box.x - 2.0 * pad, int(font), Color.WHITE)

func _on_mode_changed(_mode: int, _sel: Array) -> void:
	_update_visibility()

func _on_mode_cleared() -> void:
	_hover_tag = -1
	_update_visibility()

func _process(_delta: float) -> void:
	queue_redraw()

# --- turn-transition animation ---
func _on_resolution_started() -> void:
	_resolving = true
	_anim_steps = 0
	_snapshot_shipments()
	_update_visibility()

func _on_phase_completed(_phase: int) -> void:
	if _resolving:
		_anim_steps = mini(_anim_steps + 1, ANIM_TOTAL_STEPS)
		queue_redraw()

func _on_resolution_completed() -> void:
	_resolving = false
	_anim_snapshot.clear()
	_update_visibility()

func _snapshot_shipments() -> void:
	# Captured BEFORE the PROCESS phase decrements turns_remaining, so pos_a/turns are
	# the pre-turn values and pos_b is where the shipment moves to this turn.
	_anim_snapshot.clear()
	var colors := _route_color_map()
	var by_key: Dictionary = {}
	for s in MatchState.get_pending_transport_shipments():
		var path: Array = s.get("path", [])
		if path.is_empty():
			continue
		var total := int(s.get("transport_turns", path.size() - 1))
		var rem := int(s.get("turns_remaining", 0))
		var idx: int = clampi(total - rem, 0, path.size() - 1)
		var pos_a := _tile_pos(str(path[idx]))
		if pos_a == Vector2.INF:
			continue
		var pos_b := _tile_pos(str(path[clampi(idx + 1, 0, path.size() - 1)]))
		if pos_b == Vector2.INF:
			pos_b = pos_a
		var dir := pos_b - pos_a
		dir = dir.normalized() if dir.length() > 0.5 else Vector2.RIGHT
		var route_key := str(s.get("source_tile", "")) + "->" + str(s.get("destination_tile", ""))
		# Merge shipments sharing a route AND the same position so their tags don't render
		# exactly on top of each other (e.g. a build's two materials bought together).
		var key := route_key + "@" + str(idx)
		if by_key.has(key):
			var existing_goods: Dictionary = by_key[key].goods
			var sg: Dictionary = _shipment_goods(s)
			for g in sg.keys():
				existing_goods[g] = int(existing_goods.get(g, 0)) + int(sg[g])
		else:
			by_key[key] = {
				"pos_a": pos_a, "pos_b": pos_b, "dir": dir, "turns": rem,
				"goods": _shipment_goods(s), "color": colors.get(route_key, Color.WHITE),
			}
	for entry in by_key.values():
		_anim_snapshot.append(entry)

# --- data ---
func get_routes() -> Array:
	_rebuild_routes()
	return _routes

func _route_color_map() -> Dictionary:
	_rebuild_routes()
	var m: Dictionary = {}
	for r in _routes:
		m[str(r.source) + "->" + str(r.dest)] = r.color
	return m

func _rebuild_routes() -> void:
	_routes.clear()
	var by_route: Dictionary = {}
	for s in MatchState.get_pending_transport_shipments():
		var src := str(s.get("source_tile", ""))
		var dst := str(s.get("destination_tile", ""))
		if src == "" or dst == "":
			continue
		var key := src + "->" + dst
		if not by_route.has(key):
			by_route[key] = {"source": src, "dest": dst, "tiles": [], "path": [], "goods": {}}
		var entry: Dictionary = by_route[key]
		if entry.tiles.is_empty() and not s.get("tiles", []).is_empty():
			entry.tiles = s.get("tiles", []).duplicate()
		if entry.path.is_empty() and not s.get("path", []).is_empty():
			entry.path = s.get("path", []).duplicate()
		var sg := _shipment_goods(s)
		for g in sg.keys():
			entry.goods[g] = int(entry.goods.get(g, 0)) + int(sg[g])
	var keys: Array = by_route.keys()
	keys.sort()
	var idx := 0
	for k in keys:
		var r: Dictionary = by_route[k]
		r.color = PALETTE[idx % PALETTE.size()]
		r.index = idx
		_routes.append(r)
		idx += 1

func _shipment_goods(s: Dictionary) -> Dictionary:
	var g: Dictionary = {}
	if bool(s.get("is_sale", false)):
		for item in s.get("sale_record", {}).get("items", []):
			g[str(item.get("good_id", ""))] = int(item.get("qty", 0))
	else:
		var gid := str(s.get("good_id", ""))
		if gid != "":
			g[gid] = int(s.get("qty", 0))
	return g

func _draw_transfer() -> void:
	var tw: float = terrain_layer.tile_set.tile_size.x
	var r := tw * 0.46
	for tid in _transfer_highlights.keys():
		var pos := _tile_pos(str(tid))
		if pos == Vector2.INF:
			continue
		var c: Color = _transfer_highlights[tid]
		draw_colored_polygon(_hex_points(pos, r), Color(c.r, c.g, c.b, TILE_MASK_ALPHA))
	if _transfer_origin != "":
		var op := _tile_pos(_transfer_origin)
		if op != Vector2.INF:
			draw_colored_polygon(_hex_points(op, r), Color(1.0, 1.0, 0.45, TILE_MASK_ALPHA))
	if _transfer_origin != "" and _transfer_dest != "":
		var a := _tile_pos(_transfer_origin)
		var b := _tile_pos(_transfer_dest)
		if a != Vector2.INF and b != Vector2.INF:
			_draw_dashed_line(a, b, _transfer_line_color, 100.0, 50.0, LINE_WIDTH)

func _hex_points(center: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 6:
		var ang := deg_to_rad(60.0 * float(i))
		pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts

func _draw_dashed_line(a: Vector2, b: Vector2, color: Color, on_len: float, off_len: float, width: float) -> void:
	var dir := b - a
	var total := dir.length()
	if total < 0.5:
		return
	dir = dir / total
	var d := 0.0
	while d < total:
		var seg_end: float = minf(d + on_len, total)
		draw_line(a + dir * d, a + dir * seg_end, color, width)
		d = seg_end + off_len

func _tile_pos(tile_id: String) -> Vector2:
	var coord := terrain_layer.id_to_coord(tile_id)
	if coord == Vector2i(-1, -1):
		return Vector2.INF
	return terrain_layer.map_to_local(terrain_layer.map_coord_for_tile_coord(coord))

func _seg_key(a: String, b: String) -> String:
	return (a + "~" + b) if a < b else (b + "~" + a)

func _build_segment_offsets() -> Dictionary:
	var users: Dictionary = {}
	for r in _routes:
		var t: Array = r.tiles
		for i in range(t.size() - 1):
			var k := _seg_key(str(t[i]), str(t[i + 1]))
			if not users.has(k):
				users[k] = []
			if not users[k].has(r.index):
				users[k].append(r.index)
	var offsets: Dictionary = {}
	for k in users.keys():
		var list: Array = users[k]
		list.sort()
		var n := list.size()
		var per: Dictionary = {}
		for rank in range(n):
			per[list[rank]] = (float(rank) - float(n - 1) / 2.0) * PARALLEL_GAP
		offsets[k] = per
	return offsets

# --- drawing ---
func _draw() -> void:
	GoodHover.begin_draw(self)
	var mapmode_on := MapMode.current_mode == MapMode.Mode.LOGISTICS
	if not mapmode_on and not _resolving and _move_preview_source == "" and not _transfer_active:
		return
	if _transfer_active:
		draw_rect(Rect2(-100000, -100000, 200000, 200000), DIM_COLOUR)
		_draw_transfer()
		_draw_hover_good_info()
		return
	if mapmode_on:
		draw_rect(Rect2(-100000, -100000, 200000, 200000), DIM_COLOUR)
		_rebuild_routes()
		var route_colors: Dictionary = {}
		for r in _routes:
			route_colors[str(r.source) + "->" + str(r.dest)] = r.color
		if not _routes.is_empty():
			var seg_offsets := _build_segment_offsets()
			for r in _routes:
				_draw_route_line(r, seg_offsets)
		if _resolving:
			_draw_animated_tags()
		else:
			_build_shipment_tags(route_colors)
			for t in _tag_hits:
				_draw_tag(t, false)
			var mouse := to_local(get_global_mouse_position())
			_hover_tag = -1
			for i in _tag_hits.size():
				if _point_in_tag(mouse, _tag_hits[i]):
					_hover_tag = i
					break
			if _hover_tag >= 0:
				_draw_tag(_tag_hits[_hover_tag], true)
				_draw_hover_panel(_tag_hits[_hover_tag])
			_draw_logistics_hover_info()
	elif _resolving:
		# Mapmode off but mid-transition: just the gliding shipment pentagons.
		_draw_animated_tags()
	if _move_preview_source != "":
		_draw_move_preview()

func _draw_animated_tags() -> void:
	var p := float(_anim_steps) / float(ANIM_TOTAL_STEPS)
	for snap in _anim_snapshot:
		_draw_tag({
			"centre": (snap.pos_a as Vector2).lerp(snap.pos_b, p),
			"dir": snap.dir, "turns": snap.turns, "goods": snap.goods, "color": snap.color,
		}, false)

func _offset_point(p: Vector2, seg_dir: Vector2, amount: float) -> Vector2:
	return p + Vector2(-seg_dir.y, seg_dir.x) * amount

func _draw_glow(pa: Vector2, pb: Vector2) -> void:
	draw_line(pa, pb, Color(1, 1, 1, 0.07), LINE_WIDTH + 18.0)
	draw_line(pa, pb, Color(1, 1, 1, 0.12), LINE_WIDTH + 11.0)
	draw_line(pa, pb, Color(1, 1, 1, 0.22), LINE_WIDTH + 5.0)

func _draw_route_line(r: Dictionary, seg_offsets: Dictionary) -> void:
	var t: Array = r.tiles
	if t.size() < 2:
		return
	var col: Color = r.color
	for i in range(t.size() - 1):
		var a := _tile_pos(str(t[i]))
		var b := _tile_pos(str(t[i + 1]))
		if a == Vector2.INF or b == Vector2.INF:
			continue
		var dir := b - a
		if dir.length() < 0.5:
			continue
		dir = dir.normalized()
		var amount: float = float(seg_offsets.get(_seg_key(str(t[i]), str(t[i + 1])), {}).get(r.index, 0.0))
		var pa := _offset_point(a, dir, amount)
		var pb := _offset_point(b, dir, amount)
		_draw_glow(pa, pb)
		draw_line(pa, pb, col, LINE_WIDTH)
	var p0 := _tile_pos(str(t[0]))
	var p1 := _tile_pos(str(t[1]))
	if p0 != Vector2.INF and p1 != Vector2.INF:
		var d0 := (p1 - p0).normalized()
		var perp := Vector2(-d0.y, d0.x)
		draw_colored_polygon(PackedVector2Array([
			p0 + d0 * TRIANGLE_LEN, p0 + perp * TRIANGLE_HALF, p0 - perp * TRIANGLE_HALF
		]), col)
	var pd := _tile_pos(str(t[t.size() - 1]))
	if pd != Vector2.INF:
		draw_rect(Rect2(pd - Vector2(DEST_BOX, DEST_BOX) / 2.0, Vector2(DEST_BOX, DEST_BOX)), col)

func _build_shipment_tags(route_colors: Dictionary) -> void:
	_tag_hits.clear()
	var tsz: float = terrain_layer.tile_set.tile_size.x
	for s in MatchState.get_pending_transport_shipments():
		var src := str(s.get("source_tile", ""))
		var dst := str(s.get("destination_tile", ""))
		var path: Array = s.get("path", [])
		if src == "" or dst == "" or path.is_empty():
			continue
		var total := int(s.get("transport_turns", path.size() - 1))
		var rem := int(s.get("turns_remaining", 0))
		var idx: int = clampi(total - rem, 0, path.size() - 1)
		var cur := _tile_pos(str(path[idx]))
		if cur == Vector2.INF:
			continue
		var incoming := Vector2.ZERO
		if idx > 0:
			var prev := _tile_pos(str(path[idx - 1]))
			if prev != Vector2.INF and (cur - prev).length() > 0.5:
				incoming = (cur - prev).normalized()
		var outgoing := Vector2.ZERO
		if idx < path.size() - 1:
			var nxt := _tile_pos(str(path[idx + 1]))
			if nxt != Vector2.INF and (nxt - cur).length() > 0.5:
				outgoing = (nxt - cur).normalized()
		var dir := outgoing if outgoing != Vector2.ZERO else incoming
		if dir == Vector2.ZERO:
			dir = Vector2.RIGHT
		var pos := cur
		if incoming != Vector2.ZERO and outgoing != Vector2.ZERO and incoming.dot(outgoing) < 0.95:
			var perp := Vector2(-outgoing.y, outgoing.x)
			pos = cur + outgoing * (tsz * 0.28) + perp * (tsz * 0.10)
			dir = outgoing
		_tag_hits.append({
			"centre": pos, "dir": dir, "turns": rem,
			"goods": _shipment_goods(s),
			"color": route_colors.get(src + "->" + dst, Color.WHITE),
		})

func _draw_tag(tag: Dictionary, hovered: bool) -> void:
	var c: Vector2 = tag.centre
	var along: Vector2 = tag.dir
	var perp := Vector2(-along.y, along.x)
	var half_len := TAG_LEN / 2.0
	var half_wid := TAG_WID / 2.0
	var rect_front := half_len - TAG_TIP
	var poly := PackedVector2Array([
		c - along * half_len + perp * half_wid,
		c - along * half_len - perp * half_wid,
		c + along * rect_front - perp * half_wid,
		c + along * half_len,
		c + along * rect_front + perp * half_wid,
	])
	var col: Color = tag.color
	if hovered:
		col = col.lightened(0.35)
	draw_colored_polygon(poly, col)
	draw_polyline(PackedVector2Array([poly[0], poly[1], poly[2], poly[3], poly[4], poly[0]]),
		Color(1, 1, 1, 0.85), 2.0)
	var label := str(int(tag.turns))
	var text_angle := along.angle()
	if along.x < 0.0:  # keep the number upright — flip so it never reads upside down
		text_angle += PI
	draw_set_transform(c, text_angle, Vector2.ONE)
	for off in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		draw_string(ThemeDB.fallback_font, Vector2(-half_len, 9.0) + off, label,
			HORIZONTAL_ALIGNMENT_CENTER, TAG_LEN, 26, Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _point_in_tag(p: Vector2, tag: Dictionary) -> bool:
	var local: Vector2 = p - tag.centre
	var dir: Vector2 = tag.dir
	return abs(local.dot(dir)) <= TAG_LEN / 2.0 and abs(local.dot(Vector2(-dir.y, dir.x))) <= TAG_WID / 2.0

func _draw_hover_panel(tag: Dictionary) -> void:
	# ~quarter-tile on screen, snapped to 3 zoom steps (>=200px wide). Font fits one
	# line without truncation; only grows taller when there are multiple goods.
	var z := maxf(0.01, get_viewport().get_canvas_transform().get_scale().x)
	var tile_w: float = terrain_layer.tile_set.tile_size.x
	var quarter_screen := tile_w * 0.25 * z
	var step_px := 140.0
	if quarter_screen > 320.0:
		step_px = 280.0
	elif quarter_screen > 240.0:
		step_px = 210.0
	var world_w := step_px / z
	var lines: Array = []
	for g in tag.goods.keys():
		lines.append("%s x%d" % [Catalog.get_display_name(str(g)), int(tag.goods[g])])
	if lines.is_empty():
		lines = ["(empty)"]
	var pad := world_w * 0.08
	var avail := world_w - 2.0 * pad
	# Font scales with the panel (legible at every zoom step), shrinking only if a
	# line would overflow the width.
	var base := maxf(8.0, world_w * 0.15)
	var max_w := 1.0
	for ln in lines:
		max_w = maxf(max_w, ThemeDB.fallback_font.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, int(base)).x)
	var font_world := base
	if max_w > avail:
		font_world = base * (avail / max_w)
	font_world = maxf(6.0, font_world)
	var line_h := font_world * 1.35
	var n: int = lines.size()
	var rows: int = n if n > 1 else 1
	var world_h := 2.0 * pad + line_h * float(rows)
	var origin: Vector2 = tag.centre + Vector2(TAG_LEN / 2.0 + 8.0, -world_h - 8.0)
	draw_rect(Rect2(origin, Vector2(world_w, world_h)), Color(0.03, 0.05, 0.09, 0.97))
	draw_rect(Rect2(origin, Vector2(world_w, world_h)), Color(0.7, 0.85, 1.0, 0.5), false, maxf(1.0, 2.0 / z))
	var y := pad + font_world
	for ln in lines:
		draw_string(ThemeDB.fallback_font, origin + Vector2(pad, y), ln,
			HORIZONTAL_ALIGNMENT_LEFT, avail, int(font_world), Color.WHITE)
		y += line_h
