extends PanelContainer
## Two-page, widescreen tutorial diagram for the game's core production loop.
## Phase 1 diagrams the live Synthetic Rubber Production recipe. Phase 2 keeps
## that recipe on the left and reveals its three destinations two seconds apart.

signal advanced
signal skipped

const GoodIcons := preload("res://scripts/good_icons.gd")
const BuildingIcon := preload("res://scripts/building_icon.gd")

const PANEL_SIZE := Vector2(1280, 720)
const CREAM := Color(0.995234, 0.930806, 0.763265)
const NAVY := Color(0.0, 0.119856, 0.243095)
const GOLD := Color(0.90, 0.70, 0.29)
const DEST_REVEAL_TIMES: Array[float] = [0.35, 2.35, 4.35]

class FlowCanvas extends Control:
	var phase := 1
	var recipe_shift := 0.0
	var destination_alpha: Array[float] = [0.0, 0.0, 0.0]
	var anchors: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _get_minimum_size() -> Vector2:
		# Diagram children are positioned manually inside a fixed-height frame. They
		# must not influence the surrounding VBox's minimum size.
		return Vector2.ZERO

	func _draw() -> void:
		if anchors.is_empty():
			return
		var ethylene: Vector2 = anchors.get("ethylene", Vector2.ZERO)
		var oxygen: Vector2 = anchors.get("oxygen", Vector2.ZERO)
		var refinery: Vector2 = anchors.get("refinery", Vector2.ZERO)
		var rubber: Vector2 = anchors.get("rubber", Vector2.ZERO)
		_draw_curve(ethylene + Vector2(36, 0), refinery + Vector2(-54, -22), 1.0)
		_draw_curve(oxygen + Vector2(36, 0), refinery + Vector2(-54, 22), 1.0)
		# Power sits immediately above the refinery; proximity conveys the input without
		# adding another crossing arrow to the compact recipe diagram.
		_draw_curve(refinery + Vector2(54, 0), rubber - Vector2(36, 0), 1.0)
		if phase < 2:
			return
		for index in 3:
			var alpha := destination_alpha[index]
			if alpha <= 0.0:
				continue
			_draw_curve(rubber + Vector2(34, 0), anchors.get("dest_%d" % index, rubber), alpha, true)

	func _draw_curve(start: Vector2, finish: Vector2, alpha: float, broad := false) -> void:
		var span := maxf(70.0, absf(finish.x - start.x) * 0.48)
		var control_a := start + Vector2(span, 0)
		var control_b := finish - Vector2(span, 0)
		var points := PackedVector2Array()
		for sample in 25:
			var t := float(sample) / 24.0
			var omt := 1.0 - t
			points.append(omt * omt * omt * start
				+ 3.0 * omt * omt * t * control_a
				+ 3.0 * omt * t * t * control_b
				+ t * t * t * finish)
		var col := Color(GOLD.r, GOLD.g, GOLD.b, alpha)
		var direction := (points[points.size() - 1] - points[points.size() - 2]).normalized()
		var normal := Vector2(-direction.y, direction.x)
		var tip := finish
		var head_length := 18.0 if broad else 14.0
		var shaft := _trim_end(points, head_length)
		draw_polyline(shaft, Color(NAVY.r, NAVY.g, NAVY.b, alpha * 0.75), 12.0 if broad else 10.0, true)
		draw_polyline(shaft, col, 7.0 if broad else 5.0, true)
		var back: Vector2 = shaft[shaft.size() - 1]
		draw_colored_polygon(PackedVector2Array([
			tip, back + normal * 8.0, back - normal * 8.0,
		]), col)

	# Stop the stroke at the base of its arrowhead. Drawing the full Bézier to the
	# tip made the thick body visibly continue through the point.
	func _trim_end(points: PackedVector2Array, trim_distance: float) -> PackedVector2Array:
		var remaining := trim_distance
		for index in range(points.size() - 1, 0, -1):
			var segment := points[index] - points[index - 1]
			var length := segment.length()
			if length >= remaining and length > 0.0:
				var cut := points[index] - segment / length * remaining
				var trimmed := PackedVector2Array()
				for keep in index:
					trimmed.append(points[keep])
				trimmed.append(cut)
				return trimmed
			remaining -= length
		return PackedVector2Array([points[0], points[0]])

var _phase := 1
var _elapsed := 0.0
var _eyebrow: Label
var _title: Label
var _body: Label
var _canvas_frame: Control
var _canvas: FlowCanvas
var _items_root: Node2D
var _next: Button
var _recipe_items: Dictionary = {}
var _destinations: Array[Control] = []
var _destination_base_positions: Array[Vector2] = []

func _ready() -> void:
	name = "TutorialRecipeFlowPanel"
	theme_type_variation = &"CoachCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build()
	set_process(false)

func present(step: Dictionary, index: int, total: int) -> void:
	_phase = int(step.get("diagram_phase", 1))
	_elapsed = 0.0
	_eyebrow.text = "%s  ·  Step %d/%d" % [str(step.get("chapter", "")), index + 1, total]
	_title.text = str(step.get("title", ""))
	_body.text = str(step.get("body", ""))
	_canvas.phase = _phase
	_canvas.recipe_shift = 0.0
	_canvas.destination_alpha = [0.0, 0.0, 0.0]
	for destination in _destinations:
		destination.visible = _phase == 2
		destination.modulate.a = 0.0
	_next.disabled = _phase == 2
	visible = true
	_fit_to_parent()
	_deferred_layout()
	set_process(_phase == 2)
	_canvas.queue_redraw()

func _process(delta: float) -> void:
	if _phase != 2:
		set_process(false)
		return
	_elapsed += delta
	_canvas.recipe_shift = clampf(_elapsed / 0.65, 0.0, 1.0)
	for index in 3:
		var progress := clampf((_elapsed - DEST_REVEAL_TIMES[index]) / 0.4, 0.0, 1.0)
		progress = 1.0 - pow(1.0 - progress, 3.0)
		_canvas.destination_alpha[index] = progress
		var destination := _destinations[index]
		destination.modulate.a = progress
		if index < _destination_base_positions.size():
			destination.position = _destination_base_positions[index] + Vector2((1.0 - progress) * 36.0, 0)
	_layout_diagram()
	_next.disabled = _elapsed < DEST_REVEAL_TIMES[2] + 0.4
	if not _next.disabled and _canvas.recipe_shift >= 1.0:
		set_process(false)

func _build() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	_eyebrow = Label.new()
	_eyebrow.theme_type_variation = &"Caption"
	column.add_child(_eyebrow)
	_title = Label.new()
	_title.theme_type_variation = &"Title"
	column.add_child(_title)
	_body = Label.new()
	_body.theme_type_variation = &"Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(0, 48)
	column.add_child(_body)

	# Keep the absolute-positioned diagram one level below the VBox. This prevents
	# its children from expanding the layout while their first positions are set.
	_canvas_frame = Control.new()
	_canvas_frame.custom_minimum_size = Vector2(0, 500)
	_canvas_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_canvas_frame.clip_contents = true
	column.add_child(_canvas_frame)
	_canvas = FlowCanvas.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas_frame.add_child(_canvas)
	# A non-Control parent isolates the manually positioned icon controls from the
	# container minimum-size calculation.
	_items_root = Node2D.new()
	_canvas.add_child(_items_root)
	_build_recipe_items()
	_build_destinations()

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	column.add_child(buttons)
	var skip := LinkButton.new()
	skip.text = "Skip tutorial"
	skip.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(func() -> void: skipped.emit())
	buttons.add_child(skip)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(spacer)
	_next = Button.new()
	_next.text = "Next"
	_next.theme_type_variation = &"Silver"
	_next.custom_minimum_size = Vector2(86, 42)
	_next.pressed.connect(func() -> void: advanced.emit())
	buttons.add_child(_next)

func _build_recipe_items() -> void:
	_recipe_items["refinery"] = _make_icon_item("Petrochemical Refinery",
		BuildingIcon.clean_texture("b_013", "poly_plant"), 100, 100, 210, false, true)
	_recipe_items["ethylene"] = _make_icon_item("Ethylene",
		GoodIcons.texture_for("g_024", "ethylene"), 60, 70)
	_recipe_items["oxygen"] = _make_icon_item("Oxygen",
		GoodIcons.texture_for("g_011", "oxygen"), 60, 70)
	_recipe_items["rubber"] = _make_icon_item("Rubber",
		GoodIcons.texture_for("g_028", "rubber"), 60, 70)
	_recipe_items["power"] = _make_icon_item("", load("res://assets/icons/ui_icons/recipe_power_icon.png") as Texture2D)
	for item in _recipe_items.values():
		_items_root.add_child(item)

func _build_destinations() -> void:
	var construct_tex: Texture2D = load("res://assets/icons/ui_icons/alt/construct.png") as Texture2D
	var market_tex: Texture2D = load("res://assets/icons/ui_icons/alt/market.png") as Texture2D

	_destinations = [
		_make_destination("Construction", [
			{"kind": "menu", "button": "ConstructButton", "texture": construct_tex},
		]),
		_make_destination("Sell to market", [
			{"kind": "building", "texture": BuildingIcon.clean_texture("b_004", "port")},
			{"kind": "menu", "button": "MarketButton", "texture": market_tex},
		]),
		_make_destination("Feed another recipe", [
			{"kind": "building", "texture": BuildingIcon.clean_texture("b_012", "chem_plant")},
			{"kind": "good", "texture": GoodIcons.texture_for("g_044", "tyres")},
		]),
	]
	for destination in _destinations:
		_items_root.add_child(destination)

func _make_icon_item(label_text: String, texture: Texture2D, icon_size := 50,
		frame_size := 60, item_width := 150, framed := true, white_art := false) -> Control:
	var item := VBoxContainer.new()
	item.custom_minimum_size = Vector2(item_width, frame_size + (28 if label_text != "" else 0))
	item.size = item.custom_minimum_size
	item.alignment = BoxContainer.ALIGNMENT_CENTER
	item.add_theme_constant_override("separation", 5)
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.set_meta("icon_visual_top_inset", _visible_top_inset(texture, icon_size) if not framed else 0.0)
	var centre := CenterContainer.new()
	centre.custom_minimum_size = Vector2(item_width, frame_size)
	item.add_child(centre)
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if white_art:
		var shader := Shader.new()
		shader.code = "shader_type canvas_item;\nvoid fragment() { vec4 px = texture(TEXTURE, UV); COLOR = vec4(vec3(1.0), px.a * COLOR.a); }"
		var material := ShaderMaterial.new()
		material.shader = shader
		icon.material = material
	if framed:
		var frame := PanelContainer.new()
		frame.custom_minimum_size = Vector2(frame_size, frame_size)
		var style := StyleBoxFlat.new()
		style.bg_color = CREAM
		style.set_corner_radius_all(10)
		style.set_content_margin_all(5)
		frame.add_theme_stylebox_override("panel", style)
		centre.add_child(frame)
		frame.add_child(icon)
	else:
		centre.add_child(icon)
	if label_text != "":
		var label := Label.new()
		label.theme_type_variation = &"Caption"
		label.text = label_text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color", CREAM)
		item.add_child(label)
	return item


func _visible_top_inset(texture: Texture2D, rendered_size: int) -> float:
	if texture == null:
		return 0.0
	var image := texture.get_image()
	if image == null or image.get_height() <= 0:
		return 0.0
	if image.is_compressed():
		image.decompress()
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.05:
				return float(y) / float(image.get_height()) * float(rendered_size)
	return 0.0

func _make_destination(label_text: String, icon_specs: Array) -> Control:
	var destination := VBoxContainer.new()
	destination.custom_minimum_size = Vector2(300, 122)
	destination.size = destination.custom_minimum_size
	destination.alignment = BoxContainer.ALIGNMENT_CENTER
	destination.add_theme_constant_override("separation", 4)
	var icons := HBoxContainer.new()
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	icons.add_theme_constant_override("separation", 12)
	destination.add_child(icons)
	for index in icon_specs.size():
		if index > 0:
			var arrow := Label.new()
			arrow.text = "→"
			arrow.theme_type_variation = &"Section"
			arrow.add_theme_color_override("font_color", GOLD)
			icons.add_child(arrow)
		icons.add_child(_make_destination_icon(icon_specs[index] as Dictionary))
	var label := Label.new()
	label.theme_type_variation = &"Body"
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", CREAM)
	destination.add_child(label)
	return destination


func _make_destination_icon(spec: Dictionary) -> Control:
	var texture := spec.get("texture") as Texture2D
	match str(spec.get("kind", "good")):
		"menu":
			return _copy_menu_button(str(spec.get("button", "")), texture)
		"building":
			return _make_icon_item("", texture, 72, 72, 80, false)
		_:
			return _make_icon_item("", texture, 60, 70, 78)


# The live bottom-menu button is the source of truth for its icon, ring, fill and shadow.
# duplicate(0) copies those visual properties and children without copying signal wiring.
func _copy_menu_button(button_name: String, fallback_texture: Texture2D) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(100, 100)
	holder.size = Vector2(100, 100)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var socket := TextureRect.new()
	socket.texture = load("res://assets/icons/ui_icons/alt/_socket.png") as Texture2D
	socket.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	socket.stretch_mode = TextureRect.STRETCH_SCALE
	socket.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	socket.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(socket)

	var scene := get_tree().current_scene
	var original := scene.find_child(button_name, true, false) as Button if scene != null else null
	if original != null:
		var copy := original.duplicate(0) as Button
		copy.name = "%sDiagram" % button_name
		copy.unique_name_in_owner = false
		copy.tooltip_text = ""
		copy.focus_mode = Control.FOCUS_NONE
		copy.mouse_filter = Control.MOUSE_FILTER_IGNORE
		copy.disabled = false
		copy.button_pressed = false
		copy.custom_minimum_size = Vector2(90, 90)
		copy.size = Vector2(90, 90)
		copy.position = Vector2(5, 5)
		var glow := copy.get_node_or_null("AltGlow") as CanvasItem
		if glow != null:
			glow.visible = false
		var specular := copy.get_node_or_null("Specular") as CanvasItem
		if specular != null:
			specular.visible = false
		holder.add_child(copy)
		return holder

	# Standalone tutorial-panel previews have no HUD to clone. Reproduce the same
	# normal-state button so visual probes still match the in-game result.
	var colors: Array = {
		"ConstructButton": [Color("#b5641f"), Color("#f8e6cb")],
		"MarketButton": [Color("#235b3c"), Color("#e4efcf")],
	}.get(button_name, [Color("#38474f"), CREAM])
	var fallback := Button.new()
	fallback.icon = fallback_texture
	fallback.expand_icon = true
	fallback.custom_minimum_size = Vector2(90, 90)
	fallback.size = Vector2(90, 90)
	fallback.position = Vector2(5, 5)
	fallback.focus_mode = Control.FOCUS_NONE
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = colors[0]
	style.set_border_width_all(6)
	style.border_color = colors[1]
	style.set_corner_radius_all(45)
	style.shadow_color = Color(0.02, 0.035, 0.045, 0.55)
	style.shadow_size = 3
	style.shadow_offset = Vector2(4, 4)
	for state in ["normal", "hover", "pressed", "focus"]:
		fallback.add_theme_stylebox_override(state, style)
	holder.add_child(fallback)
	return holder

func _fit_to_parent() -> void:
	var parent_control := get_parent() as Control
	var available := parent_control.size if parent_control != null else get_viewport_rect().size
	var target := Vector2(minf(PANEL_SIZE.x, available.x - 100.0), minf(PANEL_SIZE.y, available.y - 100.0))
	# Godot leaves a Container at its previous size when assigned a value below its
	# combined minimum. Clamp first so repeat presentations always shrink correctly.
	target = target.max(get_combined_minimum_size())
	size = target
	position = (available - size) * 0.5


func _deferred_layout() -> void:
	# The first visible layout pass can report the canvas at the VBox's temporary
	# expansion height. Wait for the container's fixed 500px diagram slot to settle.
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_fit_to_parent()
	await get_tree().process_frame
	if not is_instance_valid(self) or not visible:
		return
	_layout_diagram()

func _layout_diagram() -> void:
	if _canvas == null or _canvas.size.x <= 0.0:
		return
	_layout_recipe_items()
	var w := _canvas.size.x
	var h := _canvas.size.y
	var destination_centres := [
		Vector2(w * 0.77, h * 0.18),
		Vector2(w * 0.77, h * 0.50),
		Vector2(w * 0.77, h * 0.82),
	]
	_destination_base_positions.clear()
	for index in _destinations.size():
		var destination := _destinations[index]
		var centre: Vector2 = destination_centres[index]
		var base: Vector2 = centre - destination.size * 0.5
		_destination_base_positions.append(base)
		if _phase != 2 or destination.modulate.a >= 1.0:
			destination.position = base
		_canvas.anchors["dest_%d" % index] = Vector2(base.x - 8.0, centre.y)
	_canvas.queue_redraw()

func _layout_recipe_items() -> void:
	if _canvas == null or _canvas.size.x <= 0.0:
		return
	var w := _canvas.size.x
	var h := _canvas.size.y
	var phase_one := {
		"ethylene": Vector2(w * 0.28, h * 0.31),
		"oxygen": Vector2(w * 0.28, h * 0.70),
		"refinery": Vector2(w * 0.50, h * 0.52),
		"rubber": Vector2(w * 0.72, h * 0.52),
	}
	var phase_two := {
		"ethylene": Vector2(w * 0.07, h * 0.31),
		"oxygen": Vector2(w * 0.07, h * 0.70),
		"refinery": Vector2(w * 0.24, h * 0.52),
		"rubber": Vector2(w * 0.42, h * 0.52),
	}
	var blend := _canvas.recipe_shift if _phase == 2 else 0.0
	_canvas.anchors.clear()
	for key in ["ethylene", "oxygen", "refinery", "rubber"]:
		var centre: Vector2 = (phase_one[key] as Vector2).lerp(phase_two[key] as Vector2, blend)
		var item := _recipe_items[key] as Control
		item.position = centre - item.size * 0.5
		_canvas.anchors[key] = _item_icon_center(item)
	# The power tile's lower edge sits 10px above the first visible refinery pixel.
	# Building art is square-bounded and may contain transparent vertical negative space.
	var refinery_item := _recipe_items["refinery"] as Control
	var power_item := _recipe_items["power"] as Control
	var refinery_visual_top := refinery_item.position.y + float(
		refinery_item.get_meta("icon_visual_top_inset", 0.0))
	var power_centre := Vector2(
		refinery_item.position.x + refinery_item.size.x * 0.5,
		refinery_visual_top - 10.0 - power_item.size.y * 0.5)
	power_item.position = power_centre - power_item.size * 0.5
	_canvas.anchors["power"] = _item_icon_center(power_item)
	if _phase == 2:
		for index in _destination_base_positions.size():
			var base := _destination_base_positions[index]
			_canvas.anchors["dest_%d" % index] = Vector2(base.x - 8.0, base.y + _destinations[index].size.y * 0.5)


func _item_icon_center(item: Control) -> Vector2:
	var icon_row := item.get_child(0) as Control
	if icon_row == null:
		return item.position + item.size * 0.5
	return item.position + Vector2(item.size.x * 0.5, icon_row.size.y * 0.5)
