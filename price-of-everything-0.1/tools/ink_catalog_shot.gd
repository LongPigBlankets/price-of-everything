extends Node2D
## Renders every InkBuildingGen recipe at L1/L2/L3 as a contact sheet, without
## booting a match — the only way to eyeball research-gated types (solar, wind)
## and to A/B the whole shape language after a change.
##   <godot> --path . res://tools/ink_catalog_shot.tscn --quit-after 400
## Writes /tmp/poe_ink_catalog.png

const KEYS := [
	"furnace", "eaf", "industrial_factory", "consumer_factory",
	"assembly_plant", "high_tech_manufactory", "petro_refinery", "poly_plant",
	"chem_plant", "electrolyser", "power_plant", "water_pump", "pipes",
	"cables", "mine", "solar_farm", "wind_farm", "port",
]
const CELL := Vector2(150.0, 132.0)
const DRAWN := 96.0        # generous so detail is legible on the sheet
const COLS := 9            # 3 types per row (3 levels each)
## Sample washes from BuildingVisuals' category triad, cycled so the sheet also
## proves the mass recolour works (and that material colours — pit earth,
## timber decks, solar cells, containers — correctly ignore it).
const WASHES: Array[Color] = [
	Color("b0483a"), Color("8d8a80"), Color("c9992e"), Color("5d7285"),
	Color("b57f97"), Color("9fae5a"), Color("efe9db"),
]

func _ready() -> void:
	get_viewport().set_disable_input(true)
	var rows := int(ceil(float(KEYS.size()) / 3.0))
	var vp := Vector2(CELL.x * COLS, CELL.y * rows)
	get_window().size = Vector2i(vp)
	RenderingServer.set_default_clear_color(Color("9aa465"))
	await get_tree().process_frame
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("/tmp/poe_ink_catalog.png")
	print("[CATALOG] %d recipes x3 levels -> /tmp/poe_ink_catalog.png" % KEYS.size())
	get_tree().quit(0)

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in KEYS.size():
		var key: String = KEYS[i]
		for lvl in [1, 2, 3]:
			var col: int = (i % 3) * 3 + (int(lvl) - 1)
			var row: int = i / 3
			var ctr := Vector2(float(col) + 0.5, float(row) + 0.5) * CELL + Vector2(0.0, 8.0)
			InkBuildingGen.draw(self, key, lvl, ctr, 0.0, DRAWN, false, Vector2.INF, WASHES[i % WASHES.size()])
			if lvl == 1:
				draw_string(font, ctr + Vector2(-CELL.x * 0.45, -CELL.y * 0.42),
					"%s" % key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("2f2b26"))
