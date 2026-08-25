extends RefCounted
## What a bake actually DEPENDS ON inside a CSV, rather than the file it happens to live in.
##
## Every bake hash used to be the md5 of whole files. So renaming six tiles — a nickname, no
## more — invalidated the hills; through them the hill texture; and through the CSV again the
## start layout. Three bakes, and the two that were not noticed cost ~47 s of load between them
## redrawing contours and re-placing 417 buildings that came out identical (owner, 25 Aug).
##
## The digest below drops the columns that are provably LABELS and hashes everything else.
##
## It is deliberately an EXCLUDE list, not an include list. A column nobody has thought about
## still invalidates the bake, which is the safe way round: a stale bake wrongly accepted is a
## map that does not match its own data, while a bake re-run needlessly is a minute of someone's
## afternoon. Only add a column here once you can say what reads it, and that nothing else does.

## tile_properties.csv columns that exist to be read by a human.
##   nickname   — Catalog's tile label index and a toast string
##   city_name  — the same label, when a tile has no nickname of its own
##   tile_role  — parsed into the tile dict and read by no runtime script at all
## None of them can move a contour, a river, or a building's footprint.
const LABEL_COLUMNS: Array = ["nickname", "city_name", "tile_role"]


## An md5 over every column of `path` except `ignore_columns`, taken in file order.
##
## Falls back to the whole-file md5 if the CSV cannot be read or has no header — a digest that
## silently returned "" would make every bake look permanently fresh, which is the one failure
## mode worse than re-baking too often.
static func csv_digest(path: String, ignore_columns: Array = LABEL_COLUMNS) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_md5(path)
	var header := file.get_csv_line()
	if header.size() == 0:
		return FileAccess.get_md5(path)
	var ignored: Dictionary = {}
	for name_value: Variant in ignore_columns:
		ignored[str(name_value).strip_edges().to_lower()] = true
	var kept: Array[int] = []
	for i in header.size():
		if not ignored.has(header[i].strip_edges().to_lower()):
			kept.append(i)
	var blob := "|".join(PackedStringArray(header))   # the header itself is part of the shape
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() < header.size():
			continue
		for i in kept:
			blob += "|" + row[i]
	return blob.md5_text()
