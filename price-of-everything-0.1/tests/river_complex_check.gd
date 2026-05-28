extends SceneTree

const SubtileGrid := preload("res://scripts/subtile_grid.gd")

func _init() -> void:
	var file := FileAccess.open("res://data/river_properties.csv", FileAccess.READ)
	var header := file.get_csv_line()
	var checked := 0
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() != header.size():
			continue
		var river_data := {}
		for i in range(header.size()):
			river_data[header[i]] = row[i]
		var kind := str(river_data.get("kind", "single"))
		if not ["source", "joint", "merge"].has(kind):
			continue
		SubtileGrid.unbuildable_report(river_data)
		checked += 1
	print("Checked %d complex river subtile reports." % checked)
	quit()
