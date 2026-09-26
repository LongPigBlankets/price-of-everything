extends Node
## Captures of the Building Ledger in its v2 and DS2 looks (UiPrefs.use_ledger_ds2), in the real HUD, cropped
## to the panel: the same seeded buildings (producers and consumers, levels one to three, running, starved
## and idle, a cost and a net each where the solver has one), then in DS2 the Starved filter on and the table
## sorted by net per turn, and the DS2 upgrade panel for a factory. Needs a window:
##   <godot> --path . res://tools/ledger_ds2_shot.tscn --quit-after 3000 -- --no-telemetry
## Writes ledger_<look>_<state>.png into $LEDGER_SHOT_DIR (or the user data folder).

func _ready() -> void:
	var dir := OS.get_environment("LEDGER_SHOT_DIR")
	if dir == "":
		dir = OS.get_user_data_dir()
	var game: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(game)
	await _settle(30)
	var specs := [
		["b_003", "r_004", 1, "tile_10_2"], ["b_024", "r_146", 2, "tile_11_2"], ["b_001", "r_001", 1, "tile_12_2"],
		["b_007", "r_008", 2, "tile_13_2"], ["b_007", "r_009", 1, "tile_13_2"], ["b_008", "r_030", 1, "tile_10_3"],
		["b_020", "r_039", 3, "tile_11_3"], ["b_012", "r_012", 2, "tile_12_3"], ["b_011", "r_024", 1, "tile_12_3"],
	]
	var ids: Array = []
	for s in specs:
		var id: String = BuildingState.add_building(str(s[0]), str(s[1]), str(s[3]), MatchState.LOCAL_PLAYER, "")
		if id == "":
			continue
		BuildingState.buildings[id]["level"] = int(s[2])
		ids.append(id)
	TurnManager.fast_mode = true
	TurnManager.phase_started.emit(TurnManager.Phase.PROCESS)
	await _settle(3)
	var coal: String = str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	for i in ids.size():
		var id: String = ids[i]
		var out := str(Catalog.get_recipe(str(BuildingState.buildings[id].get("recipe_id", ""))).get("output_1", ""))
		var gid := str(Catalog.get_good_by_internal_name(out).get("id", coal))
		if i % 3 == 0:
			Production.last_turn_run[id] = true
			CostSolver.last_result["per_building"][id] = {"output_good_id": gid, "unit_cost": 4.0 + float(i) * 7.5}
		elif i % 3 == 1:
			Production.missing_by_building[id] = [{"good_id": coal, "qty": 5}]
	TurnManager.turn_resolution_completed.emit()
	await _settle(6)
	var hud: Control = game.get_node("UILayer/HUD")
	var ledger: Control = (load("res://scenes/building_ledger_panel.tscn") as PackedScene).instantiate()
	hud.add_child(ledger)
	await _settle(12)
	UiPrefs.set_use_ledger_ds2(false)
	await _settle(8)
	_shot(ledger, dir.path_join("ledger_v2.png"))
	UiPrefs.set_use_ledger_ds2(true)
	await _settle(12)
	_shot(ledger, dir.path_join("ledger_ds2.png"))
	ledger.call("_on_chip", "starved", true)
	ledger.call("_on_sort_pressed", "net")
	await _settle(8)
	_shot(ledger, dir.path_join("ledger_ds2_filtered.png"))
	# The DS2 upgrade panel for the first factory in the table.
	for id in ids:
		if str(BuildingState.buildings[id].get("building_id", "")) == "b_007":
			ledger.call("_open_upgrade", id)
			break
	await _settle(10)
	var dialog: Control = ledger.get("_upgrade_dialog")
	if dialog != null:
		_shot(dialog.find_child("UpgradeSheet", true, false) as Control, dir.path_join("ledger_ds2_upgrade.png"))
		var sheet := dialog.find_child("UpgradeSheet", true, false) as Control
		var parts: Array[String] = []
		for sec_name in ["UpgradeHead", "MaterialsPlate", "ImpactScroll", "ResearchLine", "LandLine", "TimeLine", "UpgradeKeys"]:
			var n := sheet.find_child(sec_name, true, false) as Control
			if n != null:
				parts.append("%s %.0f" % [sec_name, n.size.y])
		print("[LEDGER_SHOT] upgrade sheet %.0f x %.0f in a %.0f x %.0f viewport; %s" % [sheet.size.x, sheet.size.y,
			get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y, ", ".join(parts)])
		# See more open: the Per turn rows under the estimates, the case scrolling.
		var more := sheet.find_child("SeeMore", true, false) as Button
		if more != null:
			more.emit_signal("pressed")
			await _settle(8)
			_shot(sheet, dir.path_join("ledger_ds2_upgrade_open.png"))
			more.emit_signal("pressed")
			await _settle(4)
		# The same with half the materials on the tile: their lamps green, only the rest priced.
		var iid := str(dialog.get("_instance_id"))
		var tile := str(BuildingState.get_building(iid).get("tile_id", ""))
		var mats: Array = BuildingWorks.preview_upgrade(iid).get("materials", [])
		for i in mats.size():
			if i % 2 == 0:
				Stockpile.add(tile, str(mats[i].good_id), int(mats[i].need))
		dialog.call("open", iid)
		await _settle(8)
		_shot(dialog.find_child("UpgradeSheet", true, false) as Control, dir.path_join("ledger_ds2_upgrade_stock.png"))
		# The price's breakdown plate, as its hover shows it.
		var price: Control = dialog.find_child("SourcePrice", true, false)
		# Drawn with the dialog shut: a real tooltip opens above its scrim, a plate on the HUD would sit under it.
		var plate: Control = price.call("_make_custom_tooltip", "") if price != null else null
		dialog.call("close")
		await _settle(2)
		if price != null:
			if plate != null:
				hud.add_child(plate)
				plate.position = Vector2(80, 80)
				await _settle(6)
				_shot(plate, dir.path_join("ledger_ds2_upgrade_breakdown.png"))
				plate.queue_free()
		dialog.call("close")
	print("[LEDGER_SHOT] rows %d, min width %.0f of %.0f" % [(ledger.get("_body") as Control).get_child_count(),
		ledger.get_combined_minimum_size().x, ledger.size.x])
	get_tree().quit(0)


func _shot(panel: Control, path: String) -> void:
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	# The image is in the window's pixels, the panel's rect in the viewport's (two pixels each on a Retina screen).
	var k := Vector2(img.get_size()) / get_viewport().get_visible_rect().size
	var g := panel.get_global_rect().grow(12)
	var r := Rect2i(Vector2i(g.position * k), Vector2i(g.size * k)).intersection(Rect2i(Vector2i.ZERO, img.get_size()))
	img.get_region(r).save_png(path)
	print("[LEDGER_SHOT] saved ", path)


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame
