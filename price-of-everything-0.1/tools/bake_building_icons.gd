extends Node
## Offline bake of the cleaned building icons. Run headless (no renderer needed — this is a
## per-pixel image pass, not a render):
##     <godot> --headless --path . res://tools/bake_building_icons.tscn --quit-after 20000
##     <godot> --headless --import --path .
##
## Writes assets/icons/buildings/cleaned/<building_id>.png plus data/building_icons_bake.json,
## a manifest of the SOURCE md5 each clean was made from. building_icon.gd loads the baked
## file when the source still hashes the same and cleans at runtime when it does not, so this
## is always safe to delete and re-make, and adding one building costs one runtime clean.
##
## Re-run after changing anything in assets/icons/buildings/, or the keying rules in
## building_icon.gd.

const BuildingIcon := preload("res://scripts/building_icon.gd")
const InfraIcons := preload("res://scripts/infra_icons.gd")


func _ready() -> void:
	var started := Time.get_ticks_msec()
	var out_dir := ProjectSettings.globalize_path(BuildingIcon.BAKE_DIR)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var manifest: Dictionary = {}
	var written := 0
	var skipped := 0
	for building_value in Catalog.all_buildings():
		var building: Dictionary = building_value
		var bid := str(building.get("id", ""))
		var iname := str(building.get("internal_name", ""))
		if InfraIcons.source_path_for(bid, iname) == "":
			skipped += 1
			continue   # no source art (HVDC and friends) — nothing to clean
		# Deliberately the SHIPPED clean, not a copy of it: the bake must be what the runtime
		# would have produced, or the two drift and the bake starts changing the picture.
		var tex := BuildingIcon._bake(bid, iname)
		if tex == null:
			skipped += 1
			continue
		var img := tex.get_image()
		if img == null or img.is_empty():
			skipped += 1
			continue
		if img.save_png(BuildingIcon.baked_path(bid)) != OK:
			push_error("bake_building_icons: could not write %s" % BuildingIcon.baked_path(bid))
			continue
		manifest[bid] = BuildingIcon.source_md5(bid, iname)
		written += 1
	var file := FileAccess.open(BuildingIcon.BAKE_MANIFEST, FileAccess.WRITE)
	if file == null:
		push_error("bake_building_icons: could not write %s" % BuildingIcon.BAKE_MANIFEST)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(manifest, "\t"))
	file.close()
	print("bake_building_icons: %d cleaned, %d without source art (%.1f s) -> %s" % [
		written, skipped, float(Time.get_ticks_msec() - started) / 1000.0, BuildingIcon.BAKE_DIR])
	print("bake_building_icons: now run `--headless --import` so Godot can load them.")
	get_tree().quit(0)
