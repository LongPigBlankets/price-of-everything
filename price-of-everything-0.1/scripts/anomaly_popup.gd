extends PanelContainer
## Anomaly popup — a small card that drops under the Treasury or Power module when a
## turn does something abnormal, and says what in one sentence.
##
## This exists because of a playtest finding: the player could not tell why money
## jumped around, and a +£2,500 turn read as arbitrary. It was not — it was a batch of
## sale shipments landing at once, on top of an auto-bridge loan she never saw taken.
## Every number involved was already on screen somewhere; none of it was ever
## ATTRIBUTED. So the popup's whole job is to name the cause, in the player's words,
## at the moment it happens.
##
## Dismissed by clicking anywhere else (owner ruling) — there is no close button and
## no timer. Unlike a toast it cannot expire before it is read, which was the other
## half of the same finding ("the toasts are too short lived").
##
## All copy is off-white (DS.PALETTE.TEXT) — never grey. See docs/top-bar-v3-spec.md §4.

const WIDTH := 320.0
const ANCHOR_GAP := 8.0     # below the bar module it belongs to
## The card announces itself, then stops. A turn is a busy moment — numbers change all
## over the bar at once — so a card that simply appeared could be missed entirely, which
## is the failure this whole feature exists to fix. Two beats of the border and the card
## is found; any more and it becomes the thing you wait to stop rather than read.
const FLASH_BEATS := 2
const FLASH_BEAT_TIME := 0.28

signal dismissed

var _body: Label


func _ready() -> void:
	theme = DS.theme
	theme_type_variation = "Card"
	top_level = true          # positioned against a module, not laid out by a container
	custom_minimum_size = Vector2(WIDTH, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP   # clicks on the card itself never dismiss it
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", DS.SP.MD)
	margin.add_theme_constant_override("margin_right", DS.SP.MD)
	margin.add_theme_constant_override("margin_top", DS.SP.SM + 2)
	margin.add_theme_constant_override("margin_bottom", DS.SP.SM + 2)
	add_child(margin)

	_body = Label.new()
	_body.theme_type_variation = "Body"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - DS.SP.MD * 2, 0)
	# Explicit, not inherited: this card is the one place the owner named by hand —
	# the text is off-white, never the dim secondary.
	_body.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	_body.add_theme_font_size_override("font_size", DS.FS.BODY)
	margin.add_child(_body)


func set_message(text: String) -> void:
	_body.text = text
	reset_size()
	_flash()


## Place the card under `anchor`, `stack_offset` px further down for each card already
## showing on the same anchor, and clamped so a module near the right edge of an
## ultrawide does not push it off screen.
func place_under(anchor: Control, stack_offset: float = 0.0) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	reset_size()
	var vw := get_viewport_rect().size.x
	var x: float = clampf(anchor.global_position.x, 8.0, maxf(8.0, vw - size.x - 8.0))
	var y: float = anchor.global_position.y + anchor.size.y + ANCHOR_GAP + stack_offset
	global_position = Vector2(x, y)


## Pulse the border and the ground, from the accent back down to rest. Tweened, not
## animated per frame: a tween that misses a frame resumes where it was, and this runs on
## the turn boundary, which is the busiest the main thread ever gets.
func _flash() -> void:
	var sb := get_theme_stylebox("panel")
	if not (sb is StyleBoxFlat):
		return
	var box := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
	add_theme_stylebox_override("panel", box)   # our own copy; never tween the shared one
	var rest_border: Color = box.border_color
	var rest_bg: Color = box.bg_color
	var lit_border: Color = DS.PALETTE.ACCENT
	var lit_bg: Color = rest_bg.lerp(DS.PALETTE.ACCENT, 0.14)
	box.set_border_width_all(maxi(1, box.border_width_top))
	var tween := create_tween()
	for _beat in FLASH_BEATS:
		tween.tween_method(func(t: float) -> void:
			box.border_color = rest_border.lerp(lit_border, t)
			box.bg_color = rest_bg.lerp(lit_bg, t),
			0.0, 1.0, FLASH_BEAT_TIME * 0.4)
		tween.tween_method(func(t: float) -> void:
			box.border_color = lit_border.lerp(rest_border, t)
			box.bg_color = lit_bg.lerp(rest_bg, t),
			0.0, 1.0, FLASH_BEAT_TIME * 0.6)


func dismiss() -> void:
	dismissed.emit()
	queue_free()
