extends Node
## Global panel stack — panels register here when shown, Escape closes in reverse order.
## A tracked panel also focuses itself when clicked, so overlapping panels can be
## brought forward without needing to drag them out of the way.

var _stack: Array[Control] = []

const _PANEL_WATCH_META := "_panel_stack_panel_watch"
const _FOCUS_WATCH_META := "_panel_stack_focus_watch"
const _CHILD_WATCH_META := "_panel_stack_child_watch"

## Push a panel onto the stack (called when a panel becomes visible).
func push(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_watch_focus(panel)
	focus(panel)

## Move an already-visible panel to the top of the draw/pick order and make it
## the next Escape target. Safe to call repeatedly.
func focus(panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	if _stack.has(panel):
		_stack.erase(panel)
	_stack.append(panel)
	if panel.is_inside_tree():
		panel.move_to_front()

## Remove a panel from the stack without closing it (called when it hides itself).
func remove(panel: Control) -> void:
	_stack.erase(panel)

## Close the topmost panel. Returns true if something was closed.
func close_top() -> bool:
	_prune_invalid()
	while not _stack.is_empty():
		var top: Control = _stack.pop_back()
		if top != null and is_instance_valid(top) and top.visible:
			top.hide()
			return true
	return false

## How many panels are currently tracked.
func size() -> int:
	_prune_invalid()
	return _stack.size()

func top() -> Control:
	_prune_invalid()
	return null if _stack.is_empty() else _stack.back()

func _watch_focus(panel: Control) -> void:
	if panel.has_meta(_PANEL_WATCH_META):
		return
	panel.set_meta(_PANEL_WATCH_META, true)
	_connect_focus_recursive(panel, panel)

func _connect_focus_recursive(node: Node, panel: Control) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		var control := node as Control
		if not control.has_meta(_FOCUS_WATCH_META):
			control.set_meta(_FOCUS_WATCH_META, true)
			control.gui_input.connect(_on_focus_gui_input.bind(panel))
	if not node.has_meta(_CHILD_WATCH_META):
		node.set_meta(_CHILD_WATCH_META, true)
		node.child_entered_tree.connect(_on_focus_child_entered_tree.bind(panel))
	for child in node.get_children():
		_connect_focus_recursive(child, panel)

func _on_focus_child_entered_tree(child: Node, panel: Control) -> void:
	if panel == null or not is_instance_valid(panel):
		return
	_connect_focus_recursive(child, panel)

func _on_focus_gui_input(event: InputEvent, panel: Control) -> void:
	if panel == null or not is_instance_valid(panel) or not panel.visible:
		return
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			focus(panel)

func _prune_invalid() -> void:
	for i in range(_stack.size() - 1, -1, -1):
		var panel: Control = _stack[i]
		if panel == null or not is_instance_valid(panel) or not panel.visible:
			_stack.remove_at(i)
