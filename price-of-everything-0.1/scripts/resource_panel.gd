extends PanelContainer
## Resources panel: the economy table of every good — what you hold, what it costs you to
## make, what you made and burned last turn, and what the carbon levy takes per unit.
##
## Rows expand (owner 2026-08-24). A good's freight is the number players actually plan
## around and it lived nowhere in the UI; opening a row shows what one unit costs to move
## one tile on each mode the good is allowed to use, at each infrastructure level, plus
## what a port takes. Every figure on this panel is per unit.
##
## Every figure comes from scripts/goods_figures.gd, and every freight figure there from
## TransportService, which owns the cost model — a panel with its own copy of the leg maths
## is how a UI starts quoting a price the sim will not charge.
##
## The table is the DS2 view (scripts/resources_ds2/resources_ds2.gd). This host dresses it in the ledger's
## backing and the lamp, drags the panel by its title row, and redraws the view when the figures move.

const ResourcesDs2 := preload("res://scripts/resources_ds2/resources_ds2.gd")
const LedgerV3 := preload("res://scripts/ledger_v3/ledger_v3.gd")
const LampOverlay := preload("res://scripts/ds2/lamp_overlay.gd")

var _dragging := false
var _drag_offset := Vector2.ZERO
var _view: Control = null
var _dirty := false

func _ready() -> void:
	LedgerV3.dress(self)
	var margin := MarginContainer.new()
	margin.name = "Ds2Margin"
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, LedgerV3.CONTENT_MARGIN)
	add_child(margin)
	_view = ResourcesDs2.new()
	_view.set("on_close", Callable(self, "hide"))
	_view.set("on_drag", Callable(self, "_on_drag"))
	margin.add_child(_view)
	custom_minimum_size = Vector2(ResourcesDs2.WIDTH, ResourcesDs2.HEIGHT)
	# The lamp over the whole panel (docs/ds2-theme.md §4).
	LampOverlay.attach(self)
	Stockpile.stockpile_changed.connect(_refresh_values)
	CostSolver.costs_updated.connect(_refresh_values)
	TurnManager.turn_advanced.connect(func(_t: int) -> void: _refresh_values())
	visibility_changed.connect(func() -> void:
		if visible:
			_view.call("refresh"))


## The title row drags the panel.
func _on_drag(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		_drag_offset = global_position - get_global_mouse_position()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() + _drag_offset


## The table is redrawn once a frame at most, and only while it is on screen.
func _refresh_values() -> void:
	if visible and not _dirty:
		_dirty = true
		(func() -> void:
			_dirty = false
			if visible:
				_view.call("refresh")).call_deferred()
