extends Control
## Mini "start the tutorial" panel — a compact sibling of the New Game screen. Slides
## in over the main-menu goods board when the player clicks Tutorial, showing a TUTORIAL
## banner, a short blurb of what it covers, and a single Begin Tutorial CTA (plus Back).
## Pure UI: emits `begin_requested` / `back_requested`; the main menu owns the launch.
## Built from the shared DS theme. Referenced from main_menu via a preload const (no
## class_name) for headless.

signal begin_requested
signal back_requested

const UIHelpers := preload("res://scripts/ui_helpers.gd")
const MenuChrome := preload("res://scripts/menu_chrome.gd")

const NAVY := Color(0, 0.07, 0.14)
const OFF_WHITE := Color(0.995234, 0.930806, 0.763265)

const COVERS: Array = [
	"Buy your first factory and read its cost per unit",
	"Power it, lay cables and pipelines, source water and coal",
	"Survey, mine, ship, and integrate a supply chain",
]

var _consent_cb: CheckBox


func _ready() -> void:
	_build()


func _input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		back_requested.emit()
		get_viewport().set_input_as_handled()


func _build() -> void:
	# Navy plate matching the menu frame.
	var plate := Panel.new()
	plate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(plate)
	MenuChrome.apply(plate)   # navy fill + brass metallic edge (lit top-left), in sync with the menu

	# Centred content column.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	plate.add_child(center)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", _sp("LG", 18))
	col.custom_minimum_size = Vector2(560, 0)
	center.add_child(col)

	# TUTORIAL banner.
	var banner := Label.new()
	banner.text = "TUTORIAL"
	banner.theme_type_variation = &"Title"
	banner.add_theme_font_size_override("font_size", 64)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(banner)

	var blurb := Label.new()
	blurb.text = "A guided first game on a small stretch of coast. Learn how the economy fits together, one building at a time — then drop into a real game."
	blurb.theme_type_variation = &"Body"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.custom_minimum_size = Vector2(560, 0)
	col.add_child(blurb)

	# What it covers.
	var covers := VBoxContainer.new()
	covers.add_theme_constant_override("separation", _sp("XS", 4))
	for line in COVERS:
		var l := Label.new()
		l.text = "•  " + str(line)
		l.theme_type_variation = &"Caption"
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		covers.add_child(l)
	col.add_child(covers)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, _sp("SM", 8))
	col.add_child(spacer)

	# Begin Tutorial CTA.
	var begin := Button.new()
	begin.text = "Begin Tutorial"
	begin.theme_type_variation = &"Primary"
	begin.custom_minimum_size = Vector2(0, 58)
	begin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	begin.add_theme_font_size_override("font_size", 26)
	begin.pressed.connect(func() -> void: begin_requested.emit())
	col.add_child(begin)

	# Telemetry consent (opt-out, docs/telemetry-spec.md §2) — same row as the
	# New Game screen; main_menu reads send_metrics_enabled() on Begin.
	var consent := UIHelpers.make_telemetry_consent_row(not PlayerProfile.telemetry_opt_out)
	_consent_cb = consent["checkbox"] as CheckBox
	var consent_center := CenterContainer.new()
	consent_center.add_child(consent["row"])
	col.add_child(consent_center)

	# Back button, top-right — added LAST so it renders on top of the full-rect content
	# container and actually receives the click (a CenterContainer defaults to MOUSE_FILTER_STOP
	# and would otherwise swallow it). Mirrors hall_of_records_panel / new_game_panel.
	var back := Button.new()
	back.text = "Back"
	back.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	back.offset_left = -120
	back.offset_top = 24
	back.offset_right = -24
	back.pressed.connect(func() -> void: back_requested.emit())
	plate.add_child(back)


func send_metrics_enabled() -> bool:
	return _consent_cb == null or _consent_cb.button_pressed


func _sp(key: String, fallback: int) -> int:
	if typeof(DS) != TYPE_NIL and "SP" in DS and DS.SP.has(key):
		return int(DS.SP[key])
	return fallback
