extends RefCounted
## What is bound to what, what the player may change, and what a rebind is allowed to be.
##
## The demo ships the FIXED bindings read-only — Settings → Controls lists them and says so
## on hover — because a half-finished rebinding screen is worse than an honest one. The
## MAP MODE bindings are the deliberate exception: they ship unbound and the player sets
## them, which is why validation lives here rather than inside the settings panel. Anything
## that reads a binding and anything that writes one goes through this file, so the two can
## never disagree about what is taken.
##
## Fixed rows are DESCRIPTIVE. The camera lives in the project's InputMap and the panel keys
## live in bottom_menu's own shortcut table; this file names them so the player can see the
## scheme, and the validator can refuse to hand the same key to a map mode.

## Groups, in the order the Controls tab shows them.
const GROUP_CAMERA := "Camera"
const GROUP_PANELS := "Panels"
const GROUP_VIEWS := "Views"
const GROUP_MAPMODES := "Map modes"

## The bindings the demo does not let the player change. `keys` is display text: the camera
## row stands for a set of InputMap actions rather than one key, which is exactly why these
## are shown as text and not as editable fields.
const FIXED: Array[Dictionary] = [
	{"group": GROUP_CAMERA, "label": "Pan the map", "keys": "W A S D  /  Arrow keys", "codes": [KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]},
	{"group": GROUP_CAMERA, "label": "Zoom", "keys": "Mouse wheel", "codes": []},

	{"group": GROUP_PANELS, "label": "Construct", "keys": "C", "codes": [KEY_C]},
	{"group": GROUP_PANELS, "label": "Resources", "keys": "R", "codes": [KEY_R]},
	{"group": GROUP_PANELS, "label": "Markets", "keys": "M", "codes": [KEY_M]},
	{"group": GROUP_PANELS, "label": "Map overlays", "keys": "O", "codes": [KEY_O]},
	{"group": GROUP_PANELS, "label": "Buildings ledger", "keys": "L", "codes": [KEY_L]},
	{"group": GROUP_PANELS, "label": "Narrative & politics", "keys": "N", "codes": [KEY_N]},
	{"group": GROUP_PANELS, "label": "People", "keys": "P", "codes": [KEY_P]},
	{"group": GROUP_PANELS, "label": "Research", "keys": "T", "codes": [KEY_T]},
	{"group": GROUP_PANELS, "label": "Money", "keys": "Z", "codes": [KEY_Z]},

	{"group": GROUP_VIEWS, "label": "End turn", "keys": "Space", "codes": [KEY_SPACE]},
	{"group": GROUP_VIEWS, "label": "Empire view", "keys": "Tab", "codes": [KEY_TAB]},
	{"group": GROUP_VIEWS, "label": "Goods graph", "keys": "G", "codes": [KEY_G]},
	{"group": GROUP_VIEWS, "label": "Encyclopedia", "keys": "X", "codes": [KEY_X]},
	{"group": GROUP_VIEWS, "label": "Close / back", "keys": "Esc", "codes": [KEY_ESCAPE]},
]

## The rebindable set — one per row of the Mapmodes panel, in its order. `id` matches
## mapmodes_panel.ROWS, so a hotkey and a click go down the same path.
const MAPMODES: Array[Dictionary] = [
	{"id": "producing", "label": "Producing"},
	{"id": "consuming", "label": "Consuming"},
	{"id": "deposits", "label": "Deposits"},
	{"id": "water", "label": "Water"},
	{"id": "power", "label": "Power"},
	{"id": "logistics", "label": "Logistics"},
	{"id": "surveying", "label": "Surveying"},
	{"id": "infrastructure", "label": "Infrastructure"},
	{"id": "stockpile", "label": "Stockpile"},
	{"id": "ownership", "label": "Ownership"},
]

## Keys that are never a valid binding, whatever else is free.
const MODIFIER_KEYS: Array[int] = [KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META]

const MSG_MODIFIER := "Cannot use that key."
const MSG_NUMBER := "Cannot use a number because it would interfere with gameplay."


## Map-mode bindings the player has set: id -> keycode. Unbound ids are simply absent, which
## is the shipped state — nothing is bound until somebody binds it.
static func mapmode_bindings() -> Dictionary:
	# PlayerProfile is an autoload, so it resolves by name even in a static function.
	return PlayerProfile.keybinds.duplicate()


static func keycode_for(mapmode_id: String) -> int:
	return int(mapmode_bindings().get(mapmode_id, 0))


## The map mode bound to `keycode`, or "" if none is. Used by the in-game key handler.
static func mapmode_for_keycode(keycode: int) -> String:
	if keycode == 0:
		return ""
	for id in mapmode_bindings():
		if int(mapmode_bindings()[id]) == keycode:
			return str(id)
	return ""


## Human-readable name for a key, for the Controls tab and for error messages.
static func key_name(keycode: int) -> String:
	if keycode == 0:
		return "Unbound"
	var name := OS.get_keycode_string(keycode)
	return name if name != "" else "Unbound"


## What already owns `keycode` — a fixed binding's label, a map mode's label, or "" if the
## key is free. `ignore_mapmode` lets a row rebind to the key it already holds without
## being told it is taken by itself.
static func holder_of(keycode: int, ignore_mapmode: String = "") -> String:
	for row: Dictionary in FIXED:
		if keycode in (row.get("codes", []) as Array):
			return str(row.get("label", ""))
	var bound := mapmode_bindings()
	for id in bound:
		if str(id) == ignore_mapmode:
			continue
		if int(bound[id]) == keycode:
			for m: Dictionary in MAPMODES:
				if str(m.id) == str(id):
					return str(m.label)
			return str(id)
	return ""


## Is `event` allowed to become `mapmode_id`'s binding? Returns {ok, message}.
##
## Order matters: a modifier or a digit is refused on its own terms before the "already
## taken" check, so the player is told the real reason rather than a coincidence.
static func validate(event: InputEventKey, mapmode_id: String) -> Dictionary:
	var code := int(event.keycode)
	if code == 0:
		return {"ok": false, "message": MSG_MODIFIER}
	# The modifier keys themselves, and any key pressed WITH one held: a binding that needs
	# a chord is not something this screen can express, so both read as the same refusal.
	if code in MODIFIER_KEYS or event.ctrl_pressed or event.alt_pressed \
			or event.meta_pressed or event.shift_pressed:
		return {"ok": false, "message": MSG_MODIFIER}
	if _is_number(code):
		return {"ok": false, "message": MSG_NUMBER}
	var holder := holder_of(code, mapmode_id)
	if holder != "":
		return {"ok": false, "message": "%s is already used by %s." % [key_name(code), holder]}
	return {"ok": true, "message": ""}


## Top-row digits and the numeric keypad alike. Numbers are reserved rather than merely
## busy — the owner's call, so that gameplay can take them later without breaking saves.
static func _is_number(keycode: int) -> bool:
	if keycode >= KEY_0 and keycode <= KEY_9:
		return true
	return keycode >= KEY_KP_0 and keycode <= KEY_KP_9


## Commit a whole set of map-mode bindings (id -> keycode). Called on Apply, so a player who
## backs out of Settings changes nothing.
static func set_mapmode_bindings(bindings: Dictionary) -> void:
	var clean: Dictionary = {}
	for id in bindings:
		var code := int(bindings[id])
		if code != 0:
			clean[str(id)] = code
	PlayerProfile.set_keybinds(clean)
