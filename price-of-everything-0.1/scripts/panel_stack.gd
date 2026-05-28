extends Node
## Global panel stack — panels register here when shown, Escape closes in reverse order.

var _stack: Array[Control] = []

## Push a panel onto the stack (called when a panel becomes visible).
func push(panel: Control) -> void:
	if _stack.has(panel):
		_stack.erase(panel)
	_stack.append(panel)

## Remove a panel from the stack without closing it (called when it hides itself).
func remove(panel: Control) -> void:
	_stack.erase(panel)

## Close the topmost panel. Returns true if something was closed.
func close_top() -> bool:
	if _stack.is_empty():
		return false
	var top: Control = _stack.back()
	_stack.pop_back()
	top.hide()
	return true

## How many panels are currently tracked.
func size() -> int:
	return _stack.size()
