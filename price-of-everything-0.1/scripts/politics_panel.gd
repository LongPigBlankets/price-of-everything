extends PanelContainer
## The Politics panel: the decarbonisation arc as a plain list of what has already happened.
##
## It reports NOTHING the player has not already been told — every entry here also arrived as
## a news item, a blocking notice or a flyout when it happened. The point is that those are
## easy to miss and impossible to re-read: by turn 150 a player who skimmed the carbon-tax
## notice has no way back to it. So this is a record, not a source, and it stays deliberately
## small (owner 2026-08-29): the election, the levy's three beats, and the subsidy's two.
##
## Everything is DERIVED from PolicyState's beats rather than stored, so it cannot drift from
## the schedule that actually drives the sim, and it works on either timeline (the demo runs
## the same arc ~30 turns earlier — see PolicyState.TIMELINES).
##
## Before the election there is nothing to show, and the panel says so rather than opening
## empty. Read-only against the sim (CLAUDE.md #5).

signal close_requested

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const GoodIcons := preload("res://scripts/good_icons.gd")

# Tall enough for the whole six-beat record without scrolling at 1080p — the panel exists to
# be read in one go, and a record that needs scrolling to reach the subsidy defeats that.
const PANEL_SIZE := Vector2(560, 720)
const HEADER_HEIGHT := 56.0
const ICON_BOX := 46.0
const ROW_GAP := 10

## The gavel the bottom menu already uses for this panel — a political act, not an
## industrial one.
const GAVEL_ICON := "res://assets/icons/ui_icons/alt/politics.png"

var _list: VBoxContainer = null
var _empty_label: Label = null
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	name = "PoliticsPanel"
	if DS and DS.theme:
		theme = DS.theme
	custom_minimum_size = PANEL_SIZE
	size = PANEL_SIZE
	_centre_in_viewport()
	theme_type_variation = &"PanelContainer"
	add_theme_stylebox_override("panel", preload("res://scripts/pipe_frame.gd").dark_brown_stylebox(8.0))
	_build()
	# The arc advances on turn resolution, so a panel left open stays current.
	TurnManager.turn_resolution_completed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		if visible:
			_refresh())


func _centre_in_viewport() -> void:
	var vp := get_viewport_rect().size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	offset_left = maxf(0.0, (vp.x - PANEL_SIZE.x) / 2.0)
	offset_top = maxf(0.0, (vp.y - PANEL_SIZE.y) / 2.0)
	offset_right = offset_left + PANEL_SIZE.x
	offset_bottom = offset_top + PANEL_SIZE.y


func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 10)
	margin.add_child(layout)

	var header := HBoxContainer.new()
	header.mouse_filter = Control.MOUSE_FILTER_STOP
	header.gui_input.connect(_on_header_input)
	layout.add_child(header)

	var title := Label.new()
	title.text = "Politics"
	title.theme_type_variation = &"Title"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.custom_minimum_size = Vector2(32, 32)
	close_button.pressed.connect(func() -> void: close_requested.emit())
	header.add_child(close_button)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", ROW_GAP)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Fill the scroll's viewport even when the content is shorter than it, so the empty-state
	# line can centre itself in the panel instead of clinging to the top of a tall blank box.
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	_refresh()


## The entries whose turn has arrived, oldest first — the arc reads as a story, and a player
## opening this for the first time at turn 150 wants to start at the election.
##
## `icon` is one of: "gavel" (a political act), "coal_banned" (the levy, which is the coal and
## oil story), "power" (the subsidy, which is the green-power story).
func _entries() -> Array:
	var turn := int(TurnManager.current_turn)
	var out: Array = []

	if turn >= PolicyState.beat("election_news"):
		out.append({
			"icon": "gavel",
			"title": "A new government elected!",
			"body": "The Party of Markets is now in government. They are likely to pursue their agenda of reducing pollution through some sort of tax.",
		})
	if turn >= PolicyState.beat("tax_notice"):
		out.append({
			"icon": "coal_banned",
			"title": "Carbon Tax announced",
			"body": "There will be a tax on carbon emissions. Any production or power generation that uses coal or crude oil (or their polluting byproducts) will be subject to a tax.",
		})
	# The ramp entry names the turn the levy reaches full rate, and is replaced by the
	# "in full effect" entry once it gets there — a live "ramping up until turn X" left
	# standing after turn X would be telling the player something untrue.
	var p1: int = PolicyState.beat("p1")
	if turn >= PolicyState.beat("ramp_first") and turn < p1:
		out.append({
			"icon": "coal_banned",
			"title": "Carbon Tax ramping up until turn %d" % p1,
			"body": "The carbon tax will keep increasing until turn %d." % p1,
		})
	if turn >= p1:
		out.append({
			"icon": "coal_banned",
			"title": "Carbon Tax in full effect",
			"body": "Adapt or pay. The government insists it's here to stay. The Ministry of Finance is rather satisfied with the extra revenue too.",
		})
	if turn >= PolicyState.beat("subsidy_notice"):
		out.append({
			"icon": "power",
			"title": "Subsidy for Green energy",
			"body": "A green subsidy has been announced. The objective is to push more companies to invest in green power.",
		})
	if turn >= PolicyState.beat("subsidy"):
		out.append({
			"icon": "power",
			"title": "Green Power subsidy in full effect",
			"body": "The green subsidy has taken effect. It is unknown how much longer the government will keep it around, as it's proving oversubscribed.",
		})
	return out


func _refresh(_a: Variant = null) -> void:
	if _list == null or not is_instance_valid(_list):
		return
	for child in _list.get_children():
		child.queue_free()
	var entries := _entries()
	if entries.is_empty():
		# Nothing has happened yet, and saying so is the whole content of the panel until
		# the election. An empty box would read as a broken panel.
		_empty_label = Label.new()
		_empty_label.text = "No Political Events yet"
		_empty_label.theme_type_variation = &"Body"
		_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_empty_label.add_theme_color_override("font_color", DS.PALETTE["TEXT_MUTED"])
		_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_list.add_child(_empty_label)
		return
	for e: Dictionary in entries:
		_list.add_child(_entry_card(e))


## One event: its icon on the left, title and body stacked beside it, on the DS inset card
## the other panels use for a self-contained item.
func _entry_card(entry: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Inset"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 10)
	card.add_child(pad)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pad.add_child(row)

	var icon := _icon_for(str(entry.get("icon", "")))
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(icon)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)

	var title := Label.new()
	title.text = str(entry.get("title", ""))
	title.theme_type_variation = &"Section"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)

	var body := Label.new()
	body.text = str(entry.get("body", ""))
	body.theme_type_variation = &"Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_color_override("font_color", DS.PALETTE["TEXT"])
	col.add_child(body)
	return card


func _icon_for(kind: String) -> Control:
	match kind:
		"power":
			# Power AS A GOOD (what the subsidy pays for), so the isometric good icon — the
			# flat lightning is the energy-cost mark. See the 2026-08-29 icon ruling.
			# "power" (g_010), not "green_power": the EA catalog carries one power good, and
			# asking for a green_power that does not exist returned a blank icon box.
			var pw := Catalog.get_good_by_internal_name("power")
			var gid := str(pw.get("id", ""))
			var tex: Texture2D = GoodIcons.texture_for_size(gid, "power", ICON_BOX) if gid != "" else null
			return _texture_box(tex)
		"coal_banned":
			return _coal_banned_icon()
		_:
			return _texture_box(load(GAVEL_ICON) as Texture2D)


func _texture_box(tex: Texture2D) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(ICON_BOX, ICON_BOX)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if tex != null:
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.set_anchors_preset(Control.PRESET_FULL_RECT)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(tr)
	return holder


## Coal struck through in red: the levy's subject, and the mark the coal prohibition uses
## conceptually. Drawn rather than baked so there is no new asset to keep in step with the
## goods art, and so the cross scales with ICON_BOX.
func _coal_banned_icon() -> Control:
	var coal := Catalog.get_good_by_internal_name("coal")
	var gid := str(coal.get("id", ""))
	var holder := _texture_box(GoodIcons.texture_for_size(gid, "coal", ICON_BOX) if gid != "" else null)
	var cross := Control.new()
	cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cross.draw.connect(_draw_cross.bind(cross))
	holder.add_child(cross)
	return holder


func _draw_cross(host: Control) -> void:
	var r := host.get_rect().size
	if r.x <= 0.0 or r.y <= 0.0:
		return
	var pad := r.x * 0.12
	var w := maxf(3.0, r.x * 0.10)
	var red: Color = DS.PALETTE["DANGER"]
	# A dark backing stroke first: the goods art is busy, and a bare red line loses itself
	# against the coal's own highlights.
	host.draw_line(Vector2(pad, pad), Vector2(r.x - pad, r.y - pad), Color(0, 0, 0, 0.55), w + 2.0, true)
	host.draw_line(Vector2(r.x - pad, pad), Vector2(pad, r.y - pad), Color(0, 0, 0, 0.55), w + 2.0, true)
	host.draw_line(Vector2(pad, pad), Vector2(r.x - pad, r.y - pad), red, w, true)
	host.draw_line(Vector2(r.x - pad, pad), Vector2(pad, r.y - pad), red, w, true)


## Drag by the header strip, matching the other free-floating panels.
func _on_header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = global_position - get_global_mouse_position()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset
		accept_event()
