extends Control
const Hover := preload("res://scripts/good_icon_hover.gd")
const Icons := preload("res://scripts/good_icons.gd")
const Emblem := preload("res://scripts/effect_emblem.gd")
var failures := 0
func check(ok: bool, label: String) -> void:
	if not ok: failures += 1; push_error(label)
	else: print("PASS: ", label)
func _ready() -> void:
	get_window().size = Vector2i(1100, 720)
	var bg := ColorRect.new()
	bg.color = Color("#102b44")
	bg.size = Vector2(1100,720)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var tex := TextureRect.new()
	tex.texture = Icons.texture_for("g_004", "iron_ingots")
	tex.position = Vector2(50,40)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.size = Vector2(80,80)
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(tex)
	var plain := TextureRect.new()
	plain.texture = Emblem.texture("engineer")
	plain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	plain.size = Vector2(28,28)
	plain.position = Vector2(350,50)
	add_child(plain)
	for frame in 4: await get_tree().process_frame
	check(tex.has_node("GoodEncyclopediaHover"), "Raw goods textures receive encyclopedia hover automatically")
	check(not plain.has_node("GoodEncyclopediaHover"), "Non-goods retain their existing tooltips")
	var target = tex.get_node("GoodEncyclopediaHover")
	check(target._get_tooltip(Vector2.ZERO) == Catalog.get_display_name("g_004"), "Hover names the actual good")
	var helpers = load("res://scripts/ui_helpers.gd")
	var framed = helpers.make_plain_good_icon("g_004", "iron_ingots")
	helpers.link_good_icon_to_encyclopedia(framed, "g_004")
	framed.position = Vector2(430,40)
	add_child(framed)
	for frame in 3: await get_tree().process_frame
	var sent := []
	MatchState.encyclopedia_good_requested.connect(func(id): sent.append(id))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = tex.get_global_rect().get_center()
	get_viewport().push_input(click, true)
	check(sent == ["g_004"], "Goods clicks dispatch their encyclopedia entry")
	click.pressed = false
	get_viewport().push_input(click, true)
	click.pressed = true
	click.position = framed.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = click.position
	get_viewport().push_input(motion, true)
	await get_tree().process_frame
	get_viewport().push_input(click, true)
	check(sent == ["g_004", "g_004"], "Framed icon link opens encyclopedia once without opening the graph")
	var tip = target._make_custom_tooltip(target._get_tooltip(Vector2.ZERO))
	tip.position = Vector2(145,45)
	add_child(tip)
	check(tip.get_theme_stylebox("panel").bg_color == Color("#051a2e"), "Goods-only hover has dark navy background")
	var image := Emblem.texture("merge").get_image()
	var expected: Image = load("res://assets/icons/research/glyph/merge.png").get_image()
	expected.rotate_90(CLOCKWISE)
	check(image.get_pixel(210,128).a == expected.get_pixel(210,128).a, "Recipe arrow is rotated clockwise toward the right")
	var graph = load("res://scripts/goods_graph_world.gd").new()
	graph.position = Vector2(0,170)
	graph.size = Vector2(1100,520)
	add_child(graph)
	graph.set_graph(load("res://scripts/goods_flow_graph.gd").build())
	graph.select_good("steel")
	for frame in 12: await get_tree().process_frame
	graph.set("_focus_t", 1.0)
	graph.set("_view_zoom", 0.8)
	graph.set("_view_offset", Vector2(450,150) - Vector2(graph.get("_fpos").get("steel",Vector2.ZERO)) * 0.8)
	graph.queue_redraw()
	for frame in 3: await get_tree().process_frame
	check(graph.find_children("DrawnGoodHover*", "", false, false).size() > 0, "Drawn goods have native encyclopedia targets")
	if "--visual" in OS.get_cmdline_user_args():
		RenderingServer.force_draw()
		get_viewport().get_texture().get_image().save_png("/private/tmp/good-hover-preview.png")
	print("GOOD HOVER FAILURES: ", failures)
	get_tree().quit(1 if failures else 0)
