extends Node
## Tile view v3, Buildings tab: opens other companies' drawer when a tutorial step spotlights a part inside
## it (the port, PortBuildingCard), whenever that step starts: while the tab is being built (the step's
## setup opens the tile) or later, with the tab already on screen. It lives in the drawer, so it goes when
## the tab is rebuilt, and its connection to the tutorial with it.

## The spotlight refs that sit inside the drawer.
const INSIDE := ["PortBuildingCard", "PortBuyButton"]

var _open: Callable


func _init(open_drawer: Callable) -> void:
	name = "DrawerSpotlight"
	_open = open_drawer


## True while the tutorial's current step spotlights something inside the drawer.
static func wants_open() -> bool:
	return INSIDE.has(Tutorial.active_spotlight_ref())


func _enter_tree() -> void:
	if not Tutorial.step_changed.is_connected(_on_step):
		Tutorial.step_changed.connect(_on_step)


func _exit_tree() -> void:
	if Tutorial.step_changed.is_connected(_on_step):
		Tutorial.step_changed.disconnect(_on_step)


func _on_step(_id: String) -> void:
	if wants_open() and _open.is_valid():
		_open.call()
