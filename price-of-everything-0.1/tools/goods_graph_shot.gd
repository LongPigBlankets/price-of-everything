extends Node
## Windowed shot: the full-screen Goods Graph view (G), plus a second frame with a
## good selected so the supply-chain trace is visible, plus a third frame at max
## zoom on a busy edge channel. Run WINDOWED (not --headless):
##   <godot> --path . res://tools/goods_graph_shot.tscn --quit-after 600
## Writes res://goods_graph_shot.png, res://goods_graph_trace.png and
## res://goods_graph_zoom.png.

const START := "res://data/starts/metal_magnate.json"
const TRACE_GOOD := "steel"   # selected for the second shot
const ZOOM_GOOD := "steel"    # max-zoom anchor for the third shot
const ZOOM_LEVEL := 1.0       # _ZOOM_MAX in goods_graph_world.gd

func _ready() -> void:
	get_window().size = Vector2i(1600, 1000)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	for _i in range(20):
		await get_tree().process_frame

	var view: Node = main.find_child("GoodsGraphView", true, false)
	if view == null:
		push_error("no GoodsGraphView found")
		get_tree().quit(1)
		return
	view.call("toggle")
	for _i in range(30):
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://goods_graph_shot.png")
	print("[SHOT] saved goods_graph_shot.png")

	var world: Node = view.find_child("GraphWorld", true, false)
	if world != null:
		# Search dropdown frame ("sil" -> Silica / silicon family).
		var sbox: LineEdit = world.get("_search_box")
		sbox.text = "sil"
		world.call("_refresh_search", "sil")
		for _i in range(8):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://goods_graph_search.png")
		print("[SHOT] saved goods_graph_search.png")
		sbox.text = ""
		world.call("_refresh_search", "")
		world.call("select_good", TRACE_GOOD)
		for _i in range(80):   # let the focus-reorg tween (0.28 s) settle (120 Hz displays)
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://goods_graph_trace.png")
		print("[SHOT] saved goods_graph_trace.png (traced %s, card tray expanded)" % TRACE_GOOD)

		# Alternate-recipes minigraph grid for the traced good.
		world.call("_enter_grid", TRACE_GOOD)
		for _i in range(10):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://goods_graph_grid.png")
		print("[SHOT] saved goods_graph_grid.png (alternates of %s)" % TRACE_GOOD)
		world.call("_exit_grid")
		for _i in range(5):
			await get_tree().process_frame

		# Third frame: clear the trace, then max-zoom into the inter-column channel
		# just right of ZOOM_GOOD so parallel lanes + corner fillets are inspectable.
		world.call("_clear_selection")
		var by_id: Dictionary = world.get("_by_id")
		var anchor: Dictionary = by_id.get(ZOOM_GOOD, {})
		var focus: Vector2 = anchor.get("pos", Vector2.ZERO) + Vector2(180.0, 0.0)
		world.set("_view_zoom", ZOOM_LEVEL)
		# _world_to_screen(p) = p * zoom + offset, so this centres `focus` on screen.
		world.set("_view_offset", Vector2(get_window().size) * 0.5 - focus * ZOOM_LEVEL)
		world.call("queue_redraw")
		for _i in range(10):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://goods_graph_zoom.png")
		print("[SHOT] saved goods_graph_zoom.png (zoom %.1f at %s)" % [ZOOM_LEVEL, ZOOM_GOOD])

		# Fourth frame: the tier-header plates (above the top row) + the power card.
		var by2: Dictionary = world.get("_by_id")
		var top_y := INF
		for nid in by2:
			top_y = minf(top_y, ((by2[nid] as Dictionary).get("pos", Vector2.ZERO) as Vector2).y)
		var power: Dictionary = by2.get("power", {})
		var pfocus := Vector2((power.get("pos", Vector2.ZERO) as Vector2).x, top_y + 560.0)
		world.set("_view_zoom", 0.62)
		world.set("_view_offset", Vector2(get_window().size) * 0.5 - pfocus * 0.62)
		world.call("queue_redraw")
		for _i in range(10):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://goods_graph_header.png")
		print("[SHOT] saved goods_graph_header.png")
	get_tree().quit(0)
