extends RefCounted
## Tile view v3, Buildings tab: the hover readout. Building Detail's diagnostics readout (BdpV3Readout: the
## dark glass screen in its gunmetal bezel) shown at the pointer as the tooltip of a module, a key or a
## figure, so what a check found is read where the pointer is, not at the foot of a long case:
## - a check: its lamp, "Motor - J: Starting" and the engine's sentence in full;
## - a figure or a key: its name and what it is, with no lamp (a readout that names, not judges).
## The screen grows a line at a time for a long sentence. The tooltip's own panel is cleared, so the
## readout's bezel is all that shows.
##
## The hosts below are the tab's modules, keys and columns: each keeps its readout in `tip`
## ({stage, name, detail, tone}) and its words in plain text in tooltip_text (which the tooltip needs to
## show at all, and which tests read).

const Readout := preload("res://scripts/bdp_v3_readout.gd")
const Lamp := preload("res://scripts/bdp_v3_lamp.gd")
const FONT_DETAIL: FontFile = preload("res://assets/fonts/IBMPlexSans-Medium.ttf")

## The readout's width at the pointer, and one more line of its detail.
const WIDTH := 400.0
## Clear room above the readout, so it opens under the hovered module (whose middle the pointer is
## usually on) rather than over the words it explains.
const DROP := 28
const LINE := 19.0
const MAX_LINES := 5


## A readout for `tip` ({stage, name, detail, tone}), sized to show its detail in full.
static func make(tip: Dictionary) -> Control:
	var host := Screen.new()
	var r: Control = Readout.new()
	r.name = "HoverReadout"
	var tone := str(tip.get("tone", ""))
	var detail := str(tip.get("detail", ""))
	r.call("show_check", str(tip.get("stage", "")), str(tip.get("name", "")), detail, tone)
	var lines := lines_for(detail, tone != "")
	var label := r.find_child("ReadoutDetail", true, false) as Label
	if label != null:
		label.max_lines_visible = lines
	r.custom_minimum_size = Vector2(WIDTH, Readout.HEIGHT + maxi(0, lines - 2) * LINE)
	host.add_child(r)
	return host


## How many lines `detail` takes on the screen (at least 1, at most MAX_LINES).
static func lines_for(detail: String, with_lamp: bool) -> int:
	if detail == "":
		return 1
	var inset := Readout.RIM / Readout.CAPTURE_SCALE + Readout.PAD.x
	var lamp := roundf(Lamp.BEZEL / Lamp.CAPTURE_SCALE * Readout.LAMP_SCALE) + 8.0 if with_lamp else 0.0
	var w := WIDTH - 2.0 * inset - lamp
	var h := FONT_DETAIL.get_multiline_string_size(detail, HORIZONTAL_ALIGNMENT_LEFT, w, Readout.DETAIL_FONT_SIZE).y
	var one := FONT_DETAIL.get_height(Readout.DETAIL_FONT_SIZE)
	return clampi(ceili(h / one - 0.05), 1, MAX_LINES)


## The same readout in plain words, for tooltip_text.
static func plain(tip: Dictionary) -> String:
	var head := str(tip.get("name", ""))
	if str(tip.get("stage", "")) != "":
		head = "%s: %s" % [str(tip.get("stage", "")), head]
	var detail := str(tip.get("detail", ""))
	return head if detail == "" else "%s\n%s" % [head, detail]


## Gives `host` (one of the classes below) its readout.
static func attach(host: Control, tip: Dictionary) -> void:
	host.set("tip", tip)
	host.tooltip_text = plain(tip)


## Holds the readout in the tooltip's window, DROP below its top, and clears the window's panel, so no
## tooltip box is drawn round the bezel.
class Screen extends MarginContainer:
	func _init() -> void:
		name = "BuildingsTip"
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("margin_top", load("res://scripts/tvp_v3/buildings_tip.gd").DROP)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_PARENTED:
			var win := get_parent() as Window
			if win != null:
				win.add_theme_stylebox_override("panel", StyleBoxEmpty.new())


class TipPanel extends PanelContainer:
	var tip: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/tvp_v3/buildings_tip.gd").make(tip) if not tip.is_empty() else null


class TipButton extends Button:
	var tip: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/tvp_v3/buildings_tip.gd").make(tip) if not tip.is_empty() else null


class TipHBox extends HBoxContainer:
	var tip: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/tvp_v3/buildings_tip.gd").make(tip) if not tip.is_empty() else null


class TipVBox extends VBoxContainer:
	var tip: Dictionary = {}

	func _make_custom_tooltip(_for_text: String) -> Object:
		return load("res://scripts/tvp_v3/buildings_tip.gd").make(tip) if not tip.is_empty() else null
