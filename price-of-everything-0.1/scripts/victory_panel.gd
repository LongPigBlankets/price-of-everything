extends Control

# Fullscreen Victory breakdown panel (docs/victory-system-spec.md §9): the host of the
# DS2 control desk (scripts/victory_ds2/victory_ds2.gd). Read-only: it observes
# VictoryState (score_changed) and hands get_breakdown() to the desk; it never mutates
# sim state (rule #5).
#
# Show/hide goes through PanelStack (Esc closes it) exactly like research_panel:
# the Close key removes itself + hides; bottom_menu opens it via _set_panel_visible;
# a latched win auto-opens it (the victory moment).

const VictoryDs2 := preload("res://scripts/victory_ds2/victory_ds2.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")

var _desk: Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_desk = VictoryDs2.new()
	_desk.connect("close_requested", _close)
	add_child(_desk)
	LampOverlay.attach(self)
	VictoryState.score_changed.connect(_on_score_changed)
	visibility_changed.connect(_on_visibility_changed)
	# The victory-moment auto-open (spec §6) is driven by bottom_menu, which can hide
	# the other HUD panels first; the won state appears here via _populate() on show.
	if visible:
		_populate()

func _populate() -> void:
	var b := VictoryState.get_breakdown()
	if b.is_empty():
		return
	_desk.call("populate", b)

# ── Show / hide / victory moment ────────────────────────────────────────────

func _on_score_changed(_total: int, _breakdown: Dictionary) -> void:
	if visible:
		_populate()

func _on_visibility_changed() -> void:
	if visible:
		_populate()

func _close() -> void:
	PanelStack.remove(self)
	hide()
