extends RefCounted
## The map editor's working copy of `data/map_authored.json`, plus its undo stack.
##
## EDITOR-ONLY (see the header of `map_editor.gd`): excluded from exported builds, never
## referenced by shipped code. The shipped half is `scripts/authored_map.gd`, which owns
## the schema, the validator and the writer — this class holds the in-memory document and
## the editing history, and delegates every question of "is this legal" to that validator
## so the editor cannot save something the game would refuse to load.
##
## UNDO MODEL: whole-document snapshots, not deltas. The document is small (a settlement is
## a few hundred records) and snapshots make every future tool undoable for free — no tool
## has to describe its own inverse, which is where hand-rolled undo systems rot. If a
## map-wide document ever makes this heavy, the fix is to snapshot per settlement, not to
## start writing inverses.

const AuthoredMap := preload("res://scripts/authored_map.gd")

## Snapshots kept. Deep enough for a session's worth of mistakes, bounded so a long
## session cannot grow without limit.
const HISTORY_LIMIT := 128

var _doc: Dictionary = {}
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []
var _dirty := false
var _discard_armed := false
var _last_label := "edit"
var _name := ""


func _init() -> void:
	reload()


## Load from disk, discarding any working state. An absent file yields the empty document,
## which is the normal starting point: authoring begins on a blank sheet over the real map.
func reload() -> void:
	_name = AuthoredMap.active_name()
	# Cache only — an override set by a tool (scratch mode) must survive a reload.
	AuthoredMap.reset_cache()
	var loaded := AuthoredMap.data()
	_doc = _copy(loaded) if not loaded.is_empty() else AuthoredMap.empty_document()
	_undo_stack.clear()
	_redo_stack.clear()
	_dirty = false
	_discard_armed = false


## The live document. Callers must not mutate it directly — go through [method begin_edit]
## so the change is undoable.
func data() -> Dictionary:
	return _doc


## Snapshot the current state before a mutation, then mutate the dictionary this returns.
## `label` names the action for the status line ("draw road", "stamp mass").
func begin_edit(label: String) -> Dictionary:
	_undo_stack.append(_copy(_doc))
	if _undo_stack.size() > HISTORY_LIMIT:
		_undo_stack.remove_at(0)
	_redo_stack.clear()
	_dirty = true
	_discard_armed = false
	_last_label = label
	return _doc


func undo() -> String:
	if _undo_stack.is_empty():
		return "Nothing to undo"
	_redo_stack.append(_copy(_doc))
	_doc = _undo_stack.pop_back()
	_dirty = true
	return "Undid %s" % _last_label


func redo() -> String:
	if _redo_stack.is_empty():
		return "Nothing to redo"
	_undo_stack.append(_copy(_doc))
	_doc = _redo_stack.pop_back()
	_dirty = true
	return "Redid %s" % _last_label


func is_dirty() -> bool:
	return _dirty


## Escape on a dirty document arms rather than leaves; a second press confirms. Prevents a
## stray keypress from discarding a session.
func arm_discard() -> void:
	_discard_armed = true


func discard_armed() -> bool:
	return _discard_armed


## Validate and write. Returns an empty string on success, else the reason — the same
## validator the loader runs, so "it saved" means "the game will load it".
func save_to(absolute_path: String) -> String:
	var problem: String = AuthoredMap.save_to(_doc, absolute_path)
	if problem == "":
		_dirty = false
		_discard_armed = false
	return problem


## The document's name, or a placeholder until it has been saved under one.
func display_name() -> String:
	return _name if _name != "" else "(unnamed)"


func name_of() -> String:
	return _name


func set_name(value: String) -> void:
	_name = value


## Headline counts for the status bar.
func counts() -> Dictionary:
	var settlements_value: Variant = _doc.get("settlements", {})
	var settlements: Dictionary = settlements_value if typeof(settlements_value) == TYPE_DICTIONARY else {}
	var roads := 0
	var masses := 0
	for key in settlements.keys():
		var settlement_value: Variant = settlements[key]
		if typeof(settlement_value) != TYPE_DICTIONARY:
			continue
		var settlement: Dictionary = settlement_value
		roads += _count(settlement, "roads")
		masses += _count(settlement, "decor")
	return {"settlements": settlements.size(), "roads": roads, "masses": masses}


func _count(source: Dictionary, key: String) -> int:
	var value: Variant = source.get(key, [])
	return (value as Array).size() if typeof(value) == TYPE_ARRAY else 0


## Deep copy through JSON: the document is plain JSON types by construction, and this
## guarantees a snapshot shares no nested Array/Dictionary with the live document.
## `duplicate(true)` would also work, but round-tripping proves the document stayed
## serialisable — a snapshot that cannot round-trip is one that could not have been saved.
func _copy(source: Dictionary) -> Dictionary:
	var text := JSON.stringify(source)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}
