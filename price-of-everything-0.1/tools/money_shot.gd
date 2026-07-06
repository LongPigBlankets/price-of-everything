extends Node2D
## Verifies the money panel's Sales + new Purchases tabs (per-good breakdown with framed good icons).
## Seeds a couple of turns of sales/purchase history directly, then screenshots each tab.
##   Godot --path . res://tools/money_shot.tscn --quit-after 900
## Writes /tmp/poe_money_sales.png and /tmp/poe_money_purchases.png.

func _ready() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	var wm: Node = packed.instantiate()
	add_child(wm)
	await _settle(140)
	var cam := get_viewport().get_camera_2d()
	if cam != null:
		cam.edge_pan_enabled = false

	var mp: Node = wm.get_node_or_null("UILayer/HUD/HUDContent/MoneyPanel")
	if mp == null:
		print("[MONEY_SHOT] no MoneyPanel node")
		get_tree().quit(1)
		return

	var steel := str(Catalog.get_good_by_internal_name("steel").get("id", ""))
	var motor := str(Catalog.get_good_by_internal_name("motor").get("id", ""))
	var iron := str(Catalog.get_good_by_internal_name("iron_ore").get("id", ""))
	var coal := str(Catalog.get_good_by_internal_name("coal").get("id", ""))
	var copper := str(Catalog.get_good_by_internal_name("copper_ore").get("id", ""))
	for _i in 2:
		mp._record_chart_history({
			"sold": {steel: {"qty": 40, "revenue": 128.0}, motor: {"qty": 28, "revenue": 280.0}},
			"power_sales_revenue": 31.2,
			"purchased": {iron: 60, coal: 30, copper: 24},
			"purchased_cost": {iron: 45.0, coal: 22.0, copper: 61.5},
		})

	mp.visible = true
	mp._refresh_sales()
	mp._refresh_purchases()
	await _settle(12)

	_select_tab(mp, "Sales")
	await _settle(8)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_money_sales.png")
	print("[MONEY_SHOT] saved /tmp/poe_money_sales.png")

	_select_tab(mp, "Purchases")
	await _settle(8)
	get_viewport().get_texture().get_image().save_png("/tmp/poe_money_purchases.png")
	print("[MONEY_SHOT] saved /tmp/poe_money_purchases.png")

	get_tree().quit(0)

func _select_tab(mp: Node, tab_name: String) -> void:
	var tc = mp._tab_container
	if tc == null:
		return
	for i in tc.get_tab_count():
		if tc.get_tab_title(i) == tab_name:
			tc.current_tab = i
			return

func _settle(n: int) -> void:
	for _i in n:
		await get_tree().process_frame
