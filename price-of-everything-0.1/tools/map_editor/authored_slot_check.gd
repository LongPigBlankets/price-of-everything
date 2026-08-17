extends Node
## THE P3 GATE: proves an authored slot actually decides where a gameplay building draws.
##
##   <godot> --path . res://tools/map_editor/authored_slot_check.tscn --quit-after 12000
##
## It writes a throwaway document placing slots on a real start-building tile, boots the
## world, and checks that the buildings landed ON the slots rather than wherever the
## procedural search would have put them. Restores whatever was active afterwards.
##
## WINDOWED — the world's placement path runs the same either way, but the capture does not.

const AuthoredMap := preload("res://scripts/authored_map.gd")

const TILE := "tile_22_16"
const SETTLE_FRAMES := 150
## Slots are laid on a ring around the tile centre, tile-centre-relative.
const SLOT_OFFSETS := [Vector2(-160, -100), Vector2(-40, -130), Vector2(80, -110),
	Vector2(170, -60), Vector2(-160, 40), Vector2(-40, 90), Vector2(80, 100),
	Vector2(170, 50)]

var _previous := ""


func _ready() -> void:
	var directory := ProjectSettings.globalize_path(AuthoredMap.DOC_DIR)
	DirAccess.make_dir_recursive_absolute(directory)
	_previous = AuthoredMap.active_name()
	if not _write_document(directory):
		_restore(directory)
		get_tree().quit(1)
		return
	AuthoredMap.write_active("_slot_check", directory)
	AuthoredMap.reset_for_tests()

	var world := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(world)
	for _i in SETTLE_FRAMES:
		await get_tree().process_frame

	var visuals := world.get_node_or_null(NodePath("BuildingVisuals"))
	if visuals == null:
		push_error("[SLOT] BuildingVisuals missing")
		_restore(directory)
		get_tree().quit(1)
		return
	var terrain := get_tree().get_first_node_in_group("hex_map")
	var coord: Vector2i = terrain.call("id_to_coord", TILE)
	var centre: Vector2 = terrain.call("map_to_local", terrain.call("map_coord_for_tile_coord", coord))

	# Where the slots are, in world units.
	var slots: Array = []
	for offset in SLOT_OFFSETS:
		slots.append(centre + offset)

	# Where the tile's buildings actually drew.
	var placed: Array = []
	for placement in (visuals.get("_placements") as Array):
		var entry: Dictionary = placement
		if str(entry.get("tile_id", "")) != TILE:
			continue
		placed.append(centre + (entry.get("center_rel", Vector2.ZERO) as Vector2))
		print("[SLOT] DIAG placement via=%s cat=%s iname=%s" % [
			str(entry.get("via", "?")), str(entry.get("cat", "?")), str(entry.get("iname", "?"))])

	print("[SLOT] DIAG active=%s is_active=%s covers=%s pins=%d" % [
		AuthoredMap.active_name(), AuthoredMap.is_active(), AuthoredMap.covers(TILE),
		(AuthoredMap.slots_for_tile(TILE).get("pins", []) as Array).size()])
	var tmpl: Dictionary = visuals.call("_authored_block_template", TILE)
	print("[SLOT] DIAG authored template lots=%d" % (tmpl.get("lots", []) as Array).size())
	var cached: Dictionary = (visuals.get("_tile_block_templates") as Dictionary).get(TILE, {})
	print("[SLOT] DIAG cached template: authored=%s lots=%d claimed=%s" % [
		cached.get("authored", false), (cached.get("lots", []) as Array).size(),
		str(cached.get("claimed", []))])
	print("[SLOT] DIAG block mode for tile = %s" % visuals.call("_use_block_mode", TILE, coord))
	print("[SLOT] %s — %d slots authored, %d buildings placed" % [TILE, slots.size(), placed.size()])
	var on_slot := 0
	for position in placed:
		var nearest := INF
		for slot in slots:
			nearest = minf(nearest, (position as Vector2).distance_to(slot as Vector2))
		print("[SLOT]   building at %.0f u from the nearest slot" % nearest)
		if nearest < 2.0:
			on_slot += 1
	var pass_all := placed.size() > 0 and on_slot == placed.size()
	print("[SLOT] GATE %d/%d buildings sit on an authored slot => %s"
		% [on_slot, placed.size(), "PASS" if pass_all else "FAIL"])
	_restore(directory)
	get_tree().quit(0 if pass_all else 1)


func _write_document(directory: String) -> bool:
	var pins: Array = []
	for offset in SLOT_OFFSETS:
		pins.append({"pos": [offset.x, offset.y], "angle": 0.0, "size": "medium"})
	var document := AuthoredMap.empty_document()
	document["settlements"] = {"slot_check": {
		"tiles": [TILE],
		"next_id": 2,
		"roads": [{"id": "r:slot_check:1", "class": "mid",
			"points": [[0.0, 0.0], [60.0, 0.0]], "tiles": [TILE]}],
		"slots": {TILE: {"pins": pins}},
	}}
	var problem: String = AuthoredMap.save_to(document, "%s/_slot_check.json" % directory)
	if problem != "":
		push_error("[SLOT] %s" % problem)
		return false
	return true


func _restore(directory: String) -> void:
	if _previous != "":
		AuthoredMap.write_active(_previous, directory)
	else:
		DirAccess.remove_absolute("%s/active.txt" % directory)
	DirAccess.remove_absolute("%s/_slot_check.json" % directory)
	AuthoredMap.reset_for_tests()
