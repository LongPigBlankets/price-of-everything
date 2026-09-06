extends Control
## Shared two-row encyclopedia hover and click target for goods only.
const Emblem := preload("res://scripts/effect_emblem.gd")
var good_id := ""
var texture_source: TextureRect

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

func resolved_good_id() -> String:
	if is_instance_valid(texture_source):
		return str(texture_source.texture.get_meta("encyclopedia_good_id", "")) if texture_source.texture != null else ""
	return good_id

func _get_tooltip(_at_position: Vector2) -> String:
	var id := resolved_good_id()
	return Catalog.get_display_name(id) if id != "" else ""

func _make_custom_tooltip(for_text: String) -> Object:
	return make_tooltip(for_text)

static func make_tooltip(good_name: String) -> Control:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#051a2e")
	style.border_color = Color("#f6e8c6")
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	col.add_child(_label(good_name))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	col.add_child(row)
	row.add_child(_label("Click to open"))
	var book := TextureRect.new()
	book.texture = Emblem.texture("encyclopedia")
	book.self_modulate = Color("#f6e8c6")
	book.custom_minimum_size = Vector2(18, 18)
	book.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	book.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(book)
	row.add_child(_label("entry"))
	return panel

static func _label(value: String) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color("#f3f0e7"))
	return label

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var id := resolved_good_id()
		if id != "":
			accept_event()
			MatchState.encyclopedia_good_requested.emit(id)

static func attach(ctrl: Control, id: String = "") -> void:
	if ctrl.get_script() == load("res://scripts/good_icon_hover.gd"):
		ctrl.good_id = id
		return
	if ctrl.has_node("GoodEncyclopediaHover"):
		var existing = ctrl.get_node("GoodEncyclopediaHover")
		existing.good_id = id
		return
	var hover = load("res://scripts/good_icon_hover.gd").new()
	hover.name = "GoodEncyclopediaHover"
	hover.good_id = id
	if ctrl is TextureRect: hover.texture_source = ctrl
	ctrl.add_child(hover)
	hover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## Canvas-drawn icons use the same native tooltip. Reuse hit regions per redraw.
static func begin_draw(canvas: CanvasItem) -> void:
	canvas.set_meta("good_hover_index", 0)
	for child in canvas.get_children():
		if child is Control and child.has_meta("drawn_good_hover"):
			child.hide()

static func drawn(canvas: CanvasItem, rect: Rect2, id: String) -> void:
	if id == "" or rect.size.x <= 0 or rect.size.y <= 0: return
	var index := int(canvas.get_meta("good_hover_index", 0))
	canvas.set_meta("good_hover_index", index + 1)
	var key := "DrawnGoodHover%d" % index
	var hover = canvas.get_node_or_null(key)
	if hover == null:
		hover = load("res://scripts/good_icon_hover.gd").new()
		hover.name = key
		hover.set_meta("drawn_good_hover", true)
		canvas.add_child(hover)
	hover.good_id = id
	hover.position = rect.position
	hover.size = rect.size
	hover.show()
