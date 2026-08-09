extends Node2D
# Dev-only: render the build-forecast trajectory chart on its own plate, for two cases —
# a healthy build (dip then green) and a loss-making one (never crosses zero).
#   Godot --path . res://tools/build_forecast_shot.tscn --quit-after 600
const BuildForecast := preload("res://scripts/build_forecast.gd")
const BuildForecastChart := preload("res://scripts/build_forecast_chart.gd")

var _frame := 0


func _ready() -> void:
	get_window().size = Vector2i(760, 560)
	MatchState.reset()
	# MarketState seeds prices one frame after _ready; projecting before that prices every
	# good at £1 and makes every recipe look broken.
	await get_tree().process_frame
	MarketState._init_prices_from_catalog()

	var layer := CanvasLayer.new()
	add_child(layer)
	var back := ColorRect.new()
	back.color = Color("#0b1726")
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(back)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 14)
	column.offset_left = 22
	column.offset_right = -22
	column.offset_top = 18
	layer.add_child(column)

	# Real projections off the catalog, so the shot shows what the panel will show.
	_add_case(column, "PIG IRON SMELTING (b_002 / r_005) on tile_5_10", "b_002", "r_005", "tile_5_10")
	_add_case(column, "COAL MINING (b_001 / r_001) on tile_6_8", "b_001", "r_001", "tile_6_8")
	# Far from a port: the same smelter, but the first sale is 6 turns out, so the dip the
	# player has to fund is six turns long instead of one.
	_add_case(column, "SAME SMELTER, FAR FROM A PORT (sale lands 6 turns later)", "b_002", "r_005", "tile_1_1")

	await get_tree().process_frame


func _add_case(parent: Control, title: String, building_id: String, recipe_id: String, tile_id: String) -> void:
	var data: Dictionary = BuildForecast.project(building_id, recipe_id, tile_id)

	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 12)
	heading.add_theme_color_override("font_color", Color("#e6b34a"))
	parent.add_child(heading)

	if bool(data.get("no_supply", false)):
		var warn := Label.new()
		warn.text = "No supply route on this tile for %s — it would sit idle." \
			% ", ".join(PackedStringArray(data.get("input_names", [])))
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", DS.PALETTE["DANGER"])
		parent.add_child(warn)

	var chart: Control = BuildForecastChart.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.set_forecast(data)
	parent.add_child(chart)

	print("[Forecast] %s → %s" % [title, JSON.stringify(data)])

	var caption := Label.new()
	var steady := float(data.get("steady_net", 0.0))
	caption.text = "build %d turns · sale lands after %d · steady %s/turn · first profit index %d · payback t%d" % [
		int(data.get("build_turns", 0)), int(data.get("sale_delay", 0)),
		"£%.2f" % steady, int(data.get("first_profit", -1)), int(data.get("payback_turn", -1)),
	]
	caption.add_theme_font_size_override("font_size", 10)
	caption.add_theme_color_override("font_color", Color("#8da0b6"))
	parent.add_child(caption)


func _process(_d: float) -> void:
	_frame += 1
	if _frame == 8:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://build_forecast_shot.png")
		print("SAVED build_forecast_shot.png")
		get_tree().quit()
