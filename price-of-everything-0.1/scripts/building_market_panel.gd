extends VBoxContainer
## Buildings-for-sale market tab — one long, searchable list of every NPC-owned
## building in the world, rendered with the Building-Ledger row theme (the metallic,
## top-left-lit LedgerRowStyle plate). Columns are deliberately sparse:
##
##   [building icon] [Building name] [Tile] [Output + qty]  [Owner]  →  [£ price button]
##
## This is step 6 of Feature 5 (docs/feature-plans.md — "Building market: buy NPC
## buildings"), built in its first, inert form: every building shows a flat placeholder
## price on an established-style button with hover/pressed visuals but NO purchase
## behaviour yet. Per-building pricing, ownership transfer and the filter chips (two
## rows are reserved for them below the search bar) are later passes.
##
## Added as a tab to the Market panel by market_panel.gd:_build_tabs(). Built lazily the
## first time the tab becomes visible (NPC buildings are seeded at match start, after
## this node's _ready), and rebuilt when buildings are added/removed.

const BuildingNaming := preload("res://scripts/building_naming.gd")
const BuildingStatus := preload("res://scripts/building_status.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")      # navy-keyed, square-cropped building icons
const LedgerRowStyle := preload("res://scripts/ledger_row_style.gd") # metallic, top-left-lit row plate
const UIHelpers := preload("res://scripts/ui_helpers.gd")

const PLACEHOLDER_PRICE := 1000  # flat buy price for every building until Feature 5 pricing lands

const ROW_INSET := 12            # LedgerRowStyle BORDER(4) + PAD_H(8); header inset matches it so columns line up
const ICON_SIZE := 76            # framed output-good icon (drives the row height) — same as the ledger
const BICON_SIZE := 56           # building-type icon in the leading column
const BICON_CELL_W := BICON_SIZE + 30  # icon centred in a wider cell → ~15px padding each side
const PRICE_COL_W := 104.0       # width of the right-anchored price button / its header

# Fixed-width cells, in order. bicon + output are drawn (icon) cells; the rest are text.
# The price button is appended after an expanding spacer so it anchors to the right.
const COLUMNS := [
	{"key": "bicon",  "label": "",         "w": float(BICON_CELL_W), "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "name",   "label": "Building", "w": 200.0,               "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"key": "tile",   "label": "Tile",     "w": 120.0,               "align": HORIZONTAL_ALIGNMENT_LEFT},
	{"key": "output", "label": "Output",   "w": float(ICON_SIZE),    "align": HORIZONTAL_ALIGNMENT_CENTER},
	{"key": "owner",  "label": "Owner",    "w": 220.0,               "align": HORIZONTAL_ALIGNMENT_LEFT},
]

var _count_label: Label = null
var _search: LineEdit = null
var _search_text := ""
var _body: VBoxContainer = null
var _rows: Array = []   # [{control: PanelContainer, blob: String}] — blob is the lowercased search haystack
var _built := false
var _dirty := false

func _ready() -> void:
	name = "Buildings"
	add_theme_constant_override("separation", 6)
	_build_chrome()
	# NPC buildings change rarely; rebuild lazily on next show after a structural change.
	MatchState.building_added.connect(func(_i: Dictionary) -> void: _mark_dirty())
	MatchState.building_removed.connect(func(_i: String) -> void: _mark_dirty())
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
	if is_visible_in_tree() and (not _built or _dirty):
		_rebuild()

func _mark_dirty() -> void:
	_dirty = true
	if is_visible_in_tree():
		_rebuild()

# ── Chrome (search + reserved filter rows + header row + scrolling body) ─────────────────
func _build_chrome() -> void:
	_count_label = Label.new()
	_count_label.theme_type_variation = "Caption"
	add_child(_count_label)

	# Row 1: the search bar (matches building name / output / tile / recipe / owner).
	_search = LineEdit.new()
	_search.placeholder_text = "Search building, output, tile, recipe or owner…"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size = Vector2(220, 0)
	_search.text_changed.connect(func(t: String) -> void:
		_search_text = t.strip_edges().to_lower()
		_apply_search())
	add_child(_search)

	# Rows 2 & 3: reserved (empty) space for the future filter chips — no filters yet.
	add_child(_reserved_filter_row())
	add_child(_reserved_filter_row())

	# Column headers, inset to sit exactly over the row cells. No click-to-sort yet.
	var header_wrap := MarginContainer.new()
	header_wrap.add_theme_constant_override("margin_left", ROW_INSET)
	header_wrap.add_theme_constant_override("margin_right", ROW_INSET)
	header_wrap.add_child(_build_header_row())
	add_child(header_wrap)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 7)  # gap between row plates, as in the ledger
	scroll.add_child(_body)
	add_child(scroll)

# An empty placeholder row reserving the vertical space where a row of filter chips will go.
func _reserved_filter_row() -> Control:
	var row := HBoxContainer.new()
	row.name = "ReservedFilterRow"
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size = Vector2(0, 30)  # ≈ chip height, so two future rows slot in cleanly
	return row

func _build_header_row() -> HBoxContainer:
	# Plain Labels (not Buttons) so their geometry matches the data cells and the columns align.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	for col in COLUMNS:
		row.add_child(_header_label(str(col.label), float(col.w), int(col.align)))
	# Expanding spacer pushes the Price header to the right, over the buy button.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	row.add_child(_header_label("Price", PRICE_COL_W, HORIZONTAL_ALIGNMENT_CENTER))
	return row

func _header_label(text: String, w: float, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = align
	l.theme_type_variation = "Caption"
	l.clip_text = true
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT_MUTED)
	return l

# ── Data ─────────────────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	if _body == null:
		return
	_built = true
	_dirty = false
	for c in _body.get_children():
		c.queue_free()
	_rows.clear()
	for vm in _collect_npc_buildings():
		var row := _build_row(vm)
		_body.add_child(row)
		_rows.append({"control": row, "blob": str(vm.blob)})
	_apply_search()

func _collect_npc_buildings() -> Array:
	var out: Array = []
	for instance_id in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[instance_id]
		if MatchState.is_player_owned(b):
			continue
		out.append(_row_vm(b))
	# Group by owner, then by building name — a stable, readable order for one long list.
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		var c := String(x.owner).naturalnocasecmp_to(String(y.owner))
		if c == 0:
			c = String(x.name).naturalnocasecmp_to(String(y.name))
		return c < 0)
	return out

func _row_vm(b: Dictionary) -> Dictionary:
	var instance_id := str(b.get("instance_id", ""))
	var building_id := str(b.get("building_id", ""))
	var tile_id := str(b.get("tile_id", ""))
	var recipe_id := str(b.get("recipe_id", ""))
	var owner := str(b.get("owner", ""))
	var recipe: Dictionary = Catalog.get_recipe(recipe_id)
	var bdata: Dictionary = Catalog.get_building(building_id)

	var name_str := BuildingNaming.label_for_tile(tile_id, instance_id, building_id, recipe_id)
	var tile_name := Catalog.tile_name(tile_id)
	var tile_text := tile_name if tile_name != "" else _short_tile(tile_id)

	# Output good + its base recipe quantity. NPC buildings are inert, so the raw recipe
	# qty is the honest, owner-agnostic value (no player modifiers/levels applied). Power
	# isn't a tradeable good, so it shows no Output icon.
	var out_gid := BuildingStatus.primary_output_good_id(recipe)
	var out_internal := BuildingStatus.primary_output_internal(recipe)
	var out_qty := BuildingStatus.primary_output_qty(recipe)
	var out_name := BuildingStatus.primary_output_display_name(recipe)
	if out_internal == "power":
		out_gid = ""
		out_qty = 0

	# Search haystack: name, output good, recipe, tile id + name, owner.
	var blob := (name_str + " " + out_name + " " + str(recipe.get("display_name", "")) \
		+ " " + tile_id + " " + tile_name + " " + owner).to_lower()

	return {
		"building_id": building_id, "binternal": str(bdata.get("internal_name", "")),
		"name": name_str, "tile": tile_text, "owner": owner,
		"out_good_id": out_gid, "out_internal": out_internal, "out_qty": out_qty,
		"blob": blob,
	}

func _apply_search() -> void:
	var q := _search_text
	var shown := 0
	for r in _rows:
		var vis: bool = q == "" or str(r.blob).contains(q)
		r.control.visible = vis
		if vis:
			shown += 1
	_update_count(shown)

func _update_count(shown: int = -1) -> void:
	if _count_label == null:
		return
	var total := _rows.size()
	if shown < 0 or shown == total:
		_count_label.text = "%d building%s for sale" % [total, "" if total == 1 else "s"]
	else:
		_count_label.text = "%d of %d buildings" % [shown, total]

# ── Row widgets (mirror the Building-Ledger row theme) ─────────────────────────────────────
func _build_row(vm: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP  # capture hover to brighten the plate
	row.add_theme_stylebox_override("panel", _row_style(false))
	row.mouse_entered.connect(func() -> void: row.add_theme_stylebox_override("panel", _row_style(true)))
	row.mouse_exited.connect(func() -> void: row.add_theme_stylebox_override("panel", _row_style(false)))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hbox)
	for col in COLUMNS:
		hbox.add_child(_build_cell(col, vm))
	# Expanding spacer → right-anchored £ price button.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(spacer)
	hbox.add_child(_price_button())
	return row

func _build_cell(col: Dictionary, vm: Dictionary) -> Control:
	var key := str(col.key)
	if key == "bicon":
		return _bicon_cell(vm)
	if key == "output":
		return _output_cell(vm)
	return _text_cell(str(vm.get(key, "")), float(col.w), int(col.align))

func _text_cell(text: String, w: float, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.theme_type_variation = "Body"
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# Leading column: the building-type icon, embossed (dark drop to the bottom-right + light lift
# to the top-left) so it reads as a raised metallic engraving lit from the top-left, matching
# the row plate. Identical treatment to the Building Ledger's leading icon.
func _bicon_cell(vm: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(BICON_CELL_W, BICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex: Texture2D = BuildingIcon.clean_texture(str(vm.building_id), str(vm.binternal))
	if tex == null:
		return holder
	holder.add_child(_emboss_layer(tex, Vector2(6.0, 6.0), Color(0.02, 0.035, 0.045, 0.38)))  # soft outer shade
	holder.add_child(_emboss_layer(tex, Vector2(3.5, 3.5), Color(0.01, 0.02, 0.03, 0.65)))     # mid shade
	holder.add_child(_emboss_layer(tex, Vector2(2.0, 2.0), Color(0.0, 0.0, 0.0, 0.85)))        # core shade (strong)
	holder.add_child(_emboss_layer(tex, Vector2(-1.0, -1.0), Color(1, 1, 1, 0.45)))            # top-left lift
	holder.add_child(_emboss_layer(tex, Vector2.ZERO, Color(0.93, 0.96, 1.0)))                 # the icon
	return holder

func _emboss_layer(tex: Texture2D, offset: Vector2, tint: Color) -> TextureRect:
	var t := TextureRect.new()
	t.set_anchors_preset(Control.PRESET_FULL_RECT)
	t.offset_left = offset.x
	t.offset_top = offset.y
	t.offset_right = offset.x
	t.offset_bottom = offset.y
	t.texture = tex
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.modulate = tint
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

# Output column: the framed goods icon with a quantity pill, exactly as in the ledger. Empty
# for power/infra (no tradeable goods output).
func _output_cell(vm: Dictionary) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gid: String = str(vm.out_good_id)
	if gid == "":
		return holder
	var icon := UIHelpers.make_framed_good_icon(gid, str(vm.out_internal), ICON_SIZE, false)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	var qty: int = int(vm.out_qty)
	if qty > 0:
		holder.add_child(_qty_pill(qty))
	return holder

func _qty_pill(qty: int) -> Control:
	var lbl := Label.new()
	lbl.text = str(qty)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.02, 0.06, 0.12, 0.92)
	box.border_color = DS.PALETTE.BORDER_SOFT
	box.set_border_width_all(1)
	box.set_corner_radius_all(7)
	box.content_margin_left = 5
	box.content_margin_right = 5
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	lbl.add_theme_stylebox_override("normal", box)
	var w: float = maxf(16.0, 9.0 + float(str(qty).length()) * 8.0)
	lbl.custom_minimum_size = Vector2(w, 17)
	lbl.position = Vector2(float(ICON_SIZE) - w - 1.0, float(ICON_SIZE) - 18.0)
	return lbl

# Right-anchored "£<price>" buy button. Established DS Button style → hover/pressed visuals come
# from the theme for free. No purchase behaviour wired yet (Feature 5, step 7).
func _price_button() -> Button:
	var btn := Button.new()
	btn.text = "£%d" % PLACEHOLDER_PRICE
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(PRICE_COL_W, 0)
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	btn.tooltip_text = "Buy this building (coming soon)"
	return btn

# ── Helpers ────────────────────────────────────────────────────────────────────────────────
func _row_style(hover: bool) -> StyleBox:
	var s := LedgerRowStyle.new()
	s.hover = hover
	return s

func _short_tile(tile_id: String) -> String:
	return tile_id.trim_prefix("tile_") if tile_id.begins_with("tile_") else tile_id
