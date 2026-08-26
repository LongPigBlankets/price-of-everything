extends Node2D
## The goods-rankings flyout: does a good's card show the podium plus the player, and does it
## grow by exactly one row when the player is off that podium?
##
## Driven through CompanyRankings.import_state rather than by playing turns, so the two cases
## that matter can be forced side by side in one screenshot: a good the player LEADS (three
## rows, their own on top) and a good they barely produce (four rows, their real rank last).
##
##   Godot --path . res://tools/rankings_shot.tscn --quit-after 3000
##
## Windowed, not headless — headless cannot capture a viewport.

var _wm


func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_wm = packed.instantiate()
	add_child(_wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	_report_shape()
	await _shoot_goods_tab()
	get_tree().quit()


## A player who dominates coal and dabbles in everything else. The huge number is deliberate:
## rival output climbs with the turn counter, and nothing else guarantees a first place.
func _seed_player() -> void:
	CompanyRankings.import_state({
		"player_revenue_history": [400.0, 520.0, 610.0, 700.0, 815.0],
		"player_goods_produced": {"g_001": 9999, "g_002": 3},
	})


## Counts, not pixels: how many rows each card carries and whether that matches the rule.
func _report_shape() -> void:
	_seed_player()
	var tables: Array = CompanyRankings.goods_standings_for(
		MatchState.match_rng_seed, 40, {"g_001": 9999, "g_002": 3})
	var three := 0
	var four := 0
	var wrong := 0
	var sample: Array = []
	for entry: Variant in tables:
		var table: Dictionary = entry
		var producers: Array = table.get("producers", []) as Array
		var rank := 0
		for row_variant: Variant in producers:
			var row: Dictionary = row_variant
			if bool(row.get("is_player", false)):
				rank = int(row.get("rank", 0))
		var field: int = int(table.get("field_size", 0))
		var want: int = mini(3 if rank <= 3 else 4, field)
		if producers.size() == want:
			if producers.size() >= 4:
				four += 1
			else:
				three += 1
		else:
			wrong += 1
		if sample.size() < 4:
			sample.append("%s: %d shown of %d, player %d%s" %
				[str(table.get("display_name", "")), producers.size(), field, rank,
				" (on podium)" if rank <= 3 else ""])
	print("[RANKCARD] %d cards | podium-only=%d podium+player=%d WRONG=%d" %
		[tables.size(), three, four, wrong])
	for line in sample:
		print("   ", line)
	# The league table itself, which the owner asked to run twenty deep.
	var league: Array = CompanyRankings.standings()
	print("[LEAGUE] %d rows (RIVAL_COUNT=%d + player), names=%d unique" %
		[league.size(), CompanyRankings.RIVAL_COUNT, _unique_names(league)])


func _unique_names(rows: Array) -> int:
	var seen: Dictionary = {}
	for entry: Variant in rows:
		var row: Dictionary = entry
		seen[str(row.get("name", ""))] = true
	return seen.size()


func _shoot_goods_tab() -> void:
	var bar: Node = _find_topbar(_wm)
	if bar == null:
		print("[RANKCARD] top bar not found")
		return
	bar._toggle_fly("rankings")
	await _settle(8)
	bar._set_rankings_tab("goods")
	await _settle(12)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://rankings_goods.png")
	print("SAVED res://rankings_goods.png")
	bar._set_rankings_tab("revenue")
	await _settle(12)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://rankings_revenue.png")
	print("SAVED res://rankings_revenue.png")
	# Twenty rows are taller than the screen, so the panel is clamped and the rest scroll. That
	# is only true if the last rank is actually REACHABLE, which a still of the top cannot show.
	var scroll: ScrollContainer = bar.get("_fly_scroll")
	if scroll != null:
		var bottom: int = int(scroll.get_v_scroll_bar().max_value)
		scroll.scroll_vertical = bottom
		await _settle(10)
		var panel: Control = bar.get("_fly_panel")
		var edge: float = panel.global_position.y + panel.size.y
		print("[SCROLL] panel bottom=%.0f of %.0f screen (%s) | scrollable to %d px (%s)" %
			[edge, get_viewport().get_visible_rect().size.y,
			"on screen" if edge <= get_viewport().get_visible_rect().size.y else "OFF SCREEN",
			bottom, "reachable" if bottom > 0 else "NO SCROLL"])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://rankings_revenue_end.png")
		print("SAVED res://rankings_revenue_end.png")


func _find_topbar(n: Node) -> Node:
	if n.get_script() != null and String(n.get_script().resource_path).ends_with("top_bar.gd"):
		return n
	for c in n.get_children():
		var f: Node = _find_topbar(c)
		if f != null:
			return f
	return null


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame
