extends Node2D
## The gantry cranes of an AUTHORED harbour, drawn ABOVE the ships (owner, 2026-08-28).
##
## A crane's jib reaches out over the basin, so a ship berthed under it has to pass BENEATH
## the jib — that is the whole read of a working quay. The authored dock is painted by
## AuthoredFabricVisuals, which sits below the ship layer, so its cranes were being covered by
## the very ships they are supposed to be loading. (The planner's harbours never had the
## problem: PortVisuals is z 60, above the ships at 59.)
##
## Only the cranes move up. Lifting the whole authored dock would put the quay itself over the
## hulls, which is the opposite mistake — a ship alongside would vanish under the deck.
const AuthoredFabricPainter := preload("res://scripts/authored_fabric_painter.gd")

## Above PortShipVisuals (59) and PortVisuals (60), so an authored crane and a planned one
## both end up over the water traffic.
const CRANE_Z := 61

var _cranes: Array = []


func _ready() -> void:
	z_index = CRANE_Z
	z_as_relative = false


## Hand this layer every `crane` record on the map. Called by AuthoredFabricVisuals when it
## rebuilds, so the two never disagree about which harbours exist.
func set_cranes(records: Array) -> void:
	_cranes = records
	queue_redraw()


func _draw() -> void:
	for record_value in _cranes:
		AuthoredFabricPainter.draw_crane(self, record_value as Dictionary)
