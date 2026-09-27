extends Control
## The People panel in DS2 (docs/people-ds2-plan.md), built into the panel (scripts/people_panel.gd) while
## UiPrefs.use_people_ds2 is on. With the switch off the panel builds today's look itself.
##
## The shell: a fixed head (the PEOPLE nameplate, the two latching tab keys, Close) over the seam, and under it
## the open tab's body, which scrolls. Both tabs share one width.

signal close_requested
## A press or drag on the head, which moves the panel as the v2 title bar does.
signal drag_input(event: InputEvent)

const LatchKey := preload("res://scripts/ds2/latch_key.gd")
const Key := preload("res://scripts/bdp_v3_key.gd")
const AdvisorsTab := preload("res://scripts/advisor_council_tab.gd")
const LabourTab := preload("res://scripts/labour_policy_tab.gd")

const TABS := ["Advisors", "Labour"]

var _keys: Array = []
var _bodies: Array[Control] = []
var _tab := 0


func _init() -> void:
	name = "PeopleDs2"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
	var col := VBoxContainer.new()
	col.name = "Cabinet"
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(col)
	var head := HBoxContainer.new()
	head.name = "Head"
	head.gui_input.connect(func(e: InputEvent) -> void: drag_input.emit(e))
	col.add_child(head)
	for i in TABS.size():
		var k: Control = LatchKey.new()
		k.name = "TabKey_%s" % TABS[i]
		k.set("text", TABS[i])
		k.custom_minimum_size.x = 150
		k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var at := i
		k.connect("pressed", func() -> void: show_tab(at))
		head.add_child(k)
		_keys.append(k)
	var close: TextureButton = Key.make("close")
	close.name = "CloseKey"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	var host := Control.new()
	host.name = "Bodies"
	host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(host)
	for script: GDScript in [AdvisorsTab, LabourTab]:
		var body: Control = script.new()
		body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		host.add_child(body)
		_bodies.append(body)
	show_tab(_tab)


## Shows tab `i` (0 Advisors, 1 Labour), its key latched and the other's up.
func show_tab(i: int) -> void:
	_tab = clampi(i, 0, TABS.size() - 1)
	for j in _bodies.size():
		_bodies[j].visible = j == _tab
		_keys[j].set("latched", j == _tab)


func current_tab() -> int:
	return _tab
