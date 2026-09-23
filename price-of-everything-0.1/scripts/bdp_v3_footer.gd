extends "res://scripts/bdp_v3_plate.gd"
## Building Detail v3: Sell building and Demolish as cream keycaps on a worn steel plate the width of
## the control block (layers from tools/button_mockup/cluster.html?export). Demolish is lettered in
## red because it cannot be undone. Both open the supply-chain review, as in v2.

const FRAME := Vector2(863, 150)
const KEYS := {
	"sell": [Rect2(58, 32, 362.5, 86), Rect2(73.6, 47.6, 331.3, 54.8)],
	"demolish": [Rect2(442.5, 32, 362.5, 86), Rect2(458.1, 47.6, 331.3, 54.8)],
}


func _init() -> void:
	super()
	name = "BdpV3Footer"
	set_frame(FRAME)
	var tex := func(layer: String) -> Texture2D: return load("res://assets/ui/bdp_v3/%s.png" % layer)
	set_layers([tex.call("footer_plate")], null, [])
	for key in ["sell", "demolish"]:
		var r: Array = KEYS[key]
		var line := {"text": "Sell building" if key == "sell" else "Demolish", "y": 0.5, "size": 38.0,
			"align": "center", "colour": NAVY if key == "sell" else DANGER_INK}
		set_key(key, r[0], r[1], tex.call("footer_key_" + key), tex.call("footer_key_%s_pressed" % key), [line], false, true)
