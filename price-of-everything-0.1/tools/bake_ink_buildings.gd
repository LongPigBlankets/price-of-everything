extends Node
## Bakes the hand-drawn industrial building art (assets/ink_buildings/src/
## sheet_a.png + sheet_b.png — 3x3 grids of grey buildings on magenta) into
## per-building transparent sprites for the ink map style:
##   res://assets/ink_buildings/<internal_name>_l{1,2,3}.png
## L3 = the full artwork; L2/L1 progressively erase satellite parts (tanks /
## annexes / outbuildings) via the authored TRIMS rects, then re-crop.
## Run headless:  <godot> --headless --path . res://tools/bake_ink_buildings.tscn
## Then import:   <godot> --headless --path . --import
##
## Pass 1 also dumps every keyed cell to /tmp/poe_ink_cell_<sheet><r><c>.png
## for eyeballing assignments and authoring trim rects.

const CELL_DUMP := true

## internal_name -> [sheet, row, col]. Assignment rules (owner 2026-07-23):
## tanks+pipework cells -> refineries / chem plant / electrolyser;
## flues-without-tanks cells -> furnace / EAF; plain sheds & roofed compounds
## -> factories / assembly plant / high tech manufactory.
const ASSIGN := {
	"petro_refinery": ["a", 0, 0],        # L-hall + pipe manifold + domed tanks
	"chem_plant": ["a", 0, 1],            # 8-flue cracker block + tank pods
	"industrial_factory": ["a", 0, 2],    # giant corrugated shed
	"electrolyser": ["a", 1, 0],          # cell-bank tank farm + control hut
	"furnace": ["a", 1, 2],               # twin-stack works + trestle
	"poly_plant": ["a", 2, 0],            # gabled sheds + sphere cluster + capsules
	"eaf": ["a", 2, 1],                   # giant central-flue cube
	"high_tech_manufactory": ["a", 2, 2], # panelled multi-wing compound
	"assembly_plant": ["b", 0, 2],        # cross hall + satellite workshops
	"consumer_factory": ["b", 2, 0],      # cluster of plain workshops
}

## Erase rects (normalized 0-1 in the CROPPED L3 image) applied cumulatively:
## L2 erases its list; L1 erases L2's + its own. Authored by eye from the
## keyed crops ("trim along logical axes" — owner). industrial_factory is one
## monolithic shed: no separable parts, all levels share the art.
const TRIMS := {
	"petro_refinery": {
		"l2": [Rect2(0.45, 0.44, 0.55, 0.56)],                              # tank yard
		"l1": [Rect2(0.80, 0.0, 0.20, 0.42), Rect2(0.10, 0.82, 0.28, 0.18)], # dark wing + rear annex
	},
	"chem_plant": {
		"l2": [Rect2(0.62, 0.66, 0.38, 0.34), Rect2(0.85, 0.14, 0.15, 0.45)], # tank pad + side cylinders
		"l1": [Rect2(0.0, 0.66, 0.40, 0.34)],                                # capsule pod
	},
	"electrolyser": {
		"l2": [Rect2(0.66, 0.74, 0.34, 0.26)],   # control hut
		"l1": [Rect2(0.64, 0.42, 0.36, 0.58)],   # riser pipe fan
	},
	"furnace": {
		"l2": [Rect2(0.0, 0.0, 0.34, 0.62), Rect2(0.24, 0.10, 0.40, 0.24)],  # tower + trestle
		"l1": [Rect2(0.54, 0.0, 0.46, 0.58)],                                # stack platform + drop pipes
	},
	"poly_plant": {
		"l2": [Rect2(0.0, 0.70, 0.42, 0.30)],    # capsule trio
		"l1": [Rect2(0.56, 0.48, 0.44, 0.52)],   # sphere rack
	},
	"eaf": {
		"l2": [Rect2(0.0, 0.05, 0.09, 0.85), Rect2(0.91, 0.05, 0.09, 0.85)],  # side pipe loops
		"l1": [Rect2(0.10, 0.0, 0.80, 0.06), Rect2(0.08, 0.87, 0.84, 0.13)],  # top loop + bottom run
	},
	"high_tech_manufactory": {
		"l2": [Rect2(0.55, 0.52, 0.45, 0.48)],   # diagonal annex wing
		"l1": [Rect2(0.84, 0.03, 0.16, 0.30)],   # round corner tower
	},
	"assembly_plant": {
		"l2": [Rect2(0.71, 0.63, 0.29, 0.37)],   # right workshop
		"l1": [Rect2(0.0, 0.64, 0.28, 0.36)],    # left workshop
	},
	"consumer_factory": {
		"l2": [Rect2(0.53, 0.0, 0.47, 0.36)],                               # top-right shed
		"l1": [Rect2(0.60, 0.44, 0.40, 0.56), Rect2(0.0, 0.0, 0.42, 0.40)], # keep one shed
	},
}

func _ready() -> void:
	var sheets := {
		"a": Image.load_from_file("res://assets/ink_buildings/src/sheet_a.png"),
		"b": Image.load_from_file("res://assets/ink_buildings/src/sheet_b.png"),
	}
	for key in sheets:
		if sheets[key] == null:
			push_error("bake_ink_buildings: failed to load sheet %s" % key)
			get_tree().quit(1)
			return
	# dump every keyed cell for inspection
	if CELL_DUMP:
		for sheet_key in sheets:
			for r in 3:
				for c in 3:
					var cell := _keyed_cell(sheets[sheet_key], r, c)
					cell.save_png("/tmp/poe_ink_cell_%s%d%d.png" % [sheet_key, r, c])
	# bake the assigned buildings
	for internal_name in ASSIGN:
		var a: Array = ASSIGN[internal_name]
		var l3 := _keyed_cell(sheets[str(a[0])], int(a[1]), int(a[2]))
		var trims: Dictionary = TRIMS.get(internal_name, {})
		var l2_rects: Array = trims.get("l2", [])
		var l1_rects: Array = l2_rects + (trims.get("l1", []) as Array)
		l3.save_png("res://assets/ink_buildings/%s_l3.png" % internal_name)
		_trimmed(l3, l2_rects).save_png("res://assets/ink_buildings/%s_l2.png" % internal_name)
		_trimmed(l3, l1_rects).save_png("res://assets/ink_buildings/%s_l1.png" % internal_name)
		print("[BAKE] %s (%s %d,%d) -> l3/l2/l1" % [internal_name, a[0], a[1], a[2]])
	print("[BAKE] done")
	get_tree().quit(0)

## Slice one 3x3 cell, chroma-key the magenta (incl. its darker shadow/grid
## tints), de-fringe edges, crop to content + margin.
func _keyed_cell(sheet: Image, row: int, col: int) -> Image:
	var w := sheet.get_width()
	var h := sheet.get_height()
	var x0 := int(floor(float(col) * w / 3.0))
	var x1 := int(floor(float(col + 1) * w / 3.0))
	var y0 := int(floor(float(row) * h / 3.0))
	var y1 := int(floor(float(row + 1) * h / 3.0))
	var cell := sheet.get_region(Rect2i(x0, y0, x1 - x0, y1 - y0))
	cell.convert(Image.FORMAT_RGBA8)
	for y in cell.get_height():
		for x in cell.get_width():
			var px := cell.get_pixel(x, y)
			var alpha := _key_alpha(px)
			if alpha <= 0.02:
				cell.set_pixel(x, y, Color(0, 0, 0, 0))
			elif alpha < 1.0:
				# edge mix of art + magenta: drop the chroma, keep the value
				var g := px.v
				cell.set_pixel(x, y, Color(g, g, g, alpha))
	return _cropped(cell, 6)

## 1.0 = keep (grey art), 0.0 = background. The background family is magenta
## (hue ~0.83-0.99) at real saturation — the art is near-neutral grey, so a
## saturation guard protects it, including its own drawn shading.
func _key_alpha(c: Color) -> float:
	var s := c.s
	if s < 0.12:
		return 1.0
	var h := c.h
	if h < 0.80 or h > 0.995:
		return 1.0
	if s > 0.30:
		return 0.0
	return clampf((0.30 - s) / 0.18, 0.0, 1.0)

func _cropped(img: Image, margin: int) -> Image:
	var r := img.get_used_rect()
	if r.size.x <= 0:
		return img
	r = r.grow(margin).intersection(Rect2i(Vector2i.ZERO, Vector2i(img.get_width(), img.get_height())))
	return img.get_region(r)

## Erase the given normalized rects (alpha 0), then re-crop so the trimmed
## sprite is tight again.
func _trimmed(l3: Image, rects: Array) -> Image:
	if rects.is_empty():
		return l3
	var img := Image.new()
	img.copy_from(l3)
	var w := img.get_width()
	var h := img.get_height()
	for rn in rects:
		var rr: Rect2 = rn
		var px := Rect2i(int(rr.position.x * w), int(rr.position.y * h), int(rr.size.x * w), int(rr.size.y * h))
		px = px.intersection(Rect2i(0, 0, w, h))
		for y in range(px.position.y, px.position.y + px.size.y):
			for x in range(px.position.x, px.position.x + px.size.x):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	return _cropped(img, 4)
