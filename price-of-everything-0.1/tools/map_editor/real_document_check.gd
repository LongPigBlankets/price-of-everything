extends Node
## Boot the editor on the REAL active document and prove it can open it.
##
## Every other editor check runs in scratch mode, on a document the editor just made. That is
## the wrong half of the problem: the editor's job is to open work that already exists, and
## the branch that reads a document it did not just edit had no coverage at all. It crashed
## the first time it was asked to.
##
## READ-ONLY. Nothing here clicks the panel and nothing saves — a harness that touched a real
## document has already cost this project one restore-by-id-range. The file's size and modify
## time are checked at the end, so "read-only" is asserted rather than intended.
##
##   <godot> --path . res://tools/map_editor/real_document_check.tscn --quit-after 3000
##
## WINDOWED: the overlay draw is part of what is under test, and --headless draws nothing.

const AuthoredMap := preload("res://scripts/authored_map.gd")
const MapEditorSlotBoxes := preload("res://scripts/map_editor/map_editor_slot_boxes.gd")

const MAX_WAIT_FRAMES := 1200
const PAINT_FRAMES := 30

var _failures: PackedStringArray = []


func _ready() -> void:
	var name := AuthoredMap.active_name()
	if name == "":
		print("[REAL] no active document — nothing to open")
		get_tree().quit(1)
		return
	var path := AuthoredMap.path_for(name)
	var before := _fingerprint(path)
	print("[REAL] opening '%s'" % name)

	var packed := load("res://tools/map_editor/map_editor.tscn") as PackedScene
	var editor := packed.instantiate()
	add_child(editor)
	var waited := 0
	while waited < MAX_WAIT_FRAMES and not bool(editor.call("is_ready_to_edit")):
		await get_tree().process_frame
		waited += 1
	_check("the editor opens the real document (%d frames)" % waited,
		bool(editor.call("is_ready_to_edit")))
	if not bool(editor.call("is_ready_to_edit")):
		_report()
		return

	# It has to have LOADED it, not merely started. An editor that silently opened a blank
	# sheet over the real map would look identical until the first save overwrote the work.
	var document: RefCounted = editor.call("document")
	var counts: Dictionary = document.call("counts")
	_check("it loaded the content (%d roads, %d masses, %d settlements)"
		% [int(counts["roads"]), int(counts["masses"]), int(counts["settlements"])],
		int(counts["roads"]) > 0 and int(counts["settlements"]) > 0)
	_check("the name it shows is the active one ('%s')" % str(document.call("display_name")),
		str(document.call("display_name")) == name)
	_check("opening a document does not mark it dirty", not bool(document.call("is_dirty")))

	# Slot boxes against the LIVE map, so this also proves the tile ids in the document
	# resolve to tiles this map actually has — the unit test can only use stand-in centres.
	var boxes: Array = editor.call("document_slot_boxes")
	var reserved: int = MapEditorSlotBoxes.tile_ids(
		document.call("data").get("settlements", {})).size()
	_check("slots resolve against the real map (%d box(es) over %d reserved tile(s))"
		% [boxes.size(), reserved], reserved == 0 or boxes.size() > 0)
	var missing := PackedStringArray()
	for box_value in boxes:
		for required in MapEditorSlotBoxes.KEYS:
			if not (box_value as Dictionary).has(required) and not missing.has(str(required)):
				missing.append(str(required))
	_check("every box carries the keys the overlay reads (%s)"
		% ("complete" if missing.is_empty() else "missing " + ", ".join(missing)),
		missing.is_empty())

	# Clicking where a box is must find it. This is the path that crashed: a box without
	# `tile_id` took the click and then failed reading the key back out.
	if not boxes.is_empty():
		var first: Dictionary = boxes[0]
		var hit: Dictionary = editor.call("_slot_at", first["centre"])
		_check("a click on a slot resolves to its record (%s)" % str(hit.get("tile_id", "none")),
			str(hit.get("tile_id", "")) == str(first["tile_id"]))

	# Let the overlay paint the whole document once. The crash was in a draw call.
	for _i in PAINT_FRAMES:
		await get_tree().process_frame
	_check("the overlay survives painting the real document", is_instance_valid(editor))

	_check("the document on disk was not touched", _fingerprint(path) == before)
	_report()


func _fingerprint(path: String) -> String:
	return "%d:%d" % [FileAccess.get_modified_time(path),
		FileAccess.open(path, FileAccess.READ).get_length()]


func _check(what: String, ok: bool) -> void:
	print("[REAL] %s  %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_failures.append(what)


func _report() -> void:
	if _failures.is_empty():
		print("[REAL] ALL CHECKS PASSED")
		get_tree().quit(0)
	else:
		for failure in _failures:
			print("[REAL] FAILED: %s" % failure)
		get_tree().quit(1)
