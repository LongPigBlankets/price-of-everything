extends Node
## How long the land hex's full view takes to lay out a crowded tile, and the blocks' shapes.
##   Godot --headless --path . res://tools/land_hex_timing.tscn --quit-after 600

func _ready() -> void:
	var Hex := load("res://scripts/tile_land_hex.gd")
	for case_sizes: Array in [[25, 20, 11, 10, 15, 15, 25], [30, 22, 18, 14, 12, 9, 8, 7, 6, 5, 4, 3, 12, 10, 8, 6, 4, 2, 1, 1]]:
		var segs: Array = []
		var i := 0
		for sz: int in case_sizes:
			segs.append({"size": float(sz), "is_other": i < case_sizes.size() / 2, "instance_id": "b%d" % i})
			i += 1
		var used := 0
		for sz: int in case_sizes:
			used += sz
		var hex: Control = Hex.new()
		hex.expanded = true
		add_child(hex)
		var t0 := Time.get_ticks_usec()
		hex.configure({"type_cap": 200, "segments": segs}, {"free": 0, "buyable": maxi(0, 200 - used), "max": 200})
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var worst := 0.0
		var cells: PackedInt32Array = hex.get("cell_group")
		var groups: Array = hex.get("groups")
		var rowv: PackedInt32Array = hex.get("_cell_row")
		var colv: PackedInt32Array = hex.get("_cell_col")
		var shapes: Array = []
		for gi in groups.size():
			if str(groups[gi].kind) == "buy":
				continue
			var c0 := 999
			var c1 := -1
			var r0 := 999
			var r1 := -1
			for k in cells.size():
				if cells[k] == gi:
					c0 = mini(c0, colv[k]); c1 = maxi(c1, colv[k]); r0 = mini(r0, rowv[k]); r1 = maxi(r1, rowv[k])
			if c1 < 0:
				continue
			var w := c1 - c0 + 1
			var h := r1 - r0 + 1
			worst = maxf(worst, maxf(float(w) / h, float(h) / w))
			shapes.append("%dx%d" % [w, h])
		print("[LAND_HEX] %d buildings, %d used: %.1f ms, worst aspect %.2f, %s" % [case_sizes.size(), used, ms, worst, " ".join(PackedStringArray(shapes))])
	get_tree().quit(0)
