extends Control

const BUILDING_LEDGER_PANEL_SCENE := preload("res://scenes/building_ledger_panel.tscn")
const PeoplePanel := preload("res://scripts/people_panel.gd")
const VictoryEndScreen := preload("res://scripts/victory_end_screen.gd")
const EndGameData := preload("res://scripts/end_game_data.gd")
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"

var _end_screen: CanvasLayer = null

# Bottom-menu buttons that have multi-resolution circular art in
# assets/icons/ui_icons/{100,200,400}/.
const MENU_ICONS := {
	"ConstructButton": "construct",
	"ResourcesButton": "resources",
	"BuildingsButton": "buildings",
	"MapmodesButton": "map_overlays",
	"MarketButton": "markets",
	"PoliticsButton": "politics",
	"TechButton": "tech",
	"PeopleButton": "",  # empty slot in the current set (no icon)
}

# Alternate icon set — single-resolution PNGs under assets/icons/ui_icons/alt/.
# Toggled at runtime by the `swap bottom menu` cheat (MatchState.use_alt_bottom_menu).
const ALT_MENU_ICONS := {
	"ConstructButton": "construct",
	"ResourcesButton": "goods",
	"BuildingsButton": "building_ledger",
	"MapmodesButton": "mapmodes",
	"MarketButton": "market",
	"PoliticsButton": "politics",
	"TechButton": "research",
	"PeopleButton": "people",
}

# Per-button colours for the alt menu: [background, object+ring]. The object
# (icon art) is baked to the object colour; the button fill uses the background
# and the 10px outer ring uses the object colour. Only applied in alt mode.
const ALT_COLORS := {
	"ConstructButton": ["#b5641f", "#f8e6cb"],
	"ResourcesButton": ["#2c4a66", "#f0e6cb"],
	"BuildingsButton": ["#8e3a33", "#f4dec8"],
	"MapmodesButton":  ["#38474f", "#e6e8e6"],
	"MarketButton":    ["#235b3c", "#e4efcf"],
	"PoliticsButton":  ["#5a2c56", "#ecdce6"],
	"TechButton":      ["#1e5e63", "#ddefec"],
	"PeopleButton":    ["#a8466b", "#f6dfe7"],
}

# Original (shared) button styleboxes captured at _ready, re-applied when the
# alt menu is toggled back off.
var _orig_button_styles := {}

# Selected button rises while its panel is open, then drops when it closes.
const RISE_PX := 25.0
const RISE_TIME := 0.12
var _button_home_y := {}  # button -> resting y (captured on first rise)
var _rise_tween := {}     # button -> active rise/drop tween
var _lifted := {}         # button -> true while raised (longer shadow + specular)
var _rest_styles := {}    # button -> resting styleboxes captured while lifting
var _hovered := {}        # button -> true while the mouse is over it

@onready var bottom_menu = %BottomMenu
@onready var construct_panel = %ConstructPanel
@onready var resource_panel: PanelContainer = %ResourcePanel
@onready var market_panel: PanelContainer = %MarketPanel
@onready var mapmodes_button: Button = %MapmodesButton
@onready var mapmodes_panel: PanelContainer = %MapModesPanel
@onready var research_panel: Control = %ResearchPanel
@onready var victory_panel: Control = %VictoryPanel
@onready var top_bar: PanelContainer = %TopBar
@onready var money_panel: PanelContainer = %MoneyPanel
@onready var take_loan_dialog: PanelContainer = %TakeLoanDialog

# Building ledger is instantiated lazily on first open (no main.tscn edit needed).
var building_ledger_panel: PanelContainer = null
var people_panel: PanelContainer = null
var construct_panel_v2: PanelContainer = null

func _ready() -> void:
	construct_panel_v2 = load("res://scripts/construct_panel_v2.gd").new()
	construct_panel.get_parent().add_child(construct_panel_v2)
	construct_panel_v2.hide()
	MatchState.construct_panel_v2_changed.connect(_on_construct_panel_v2_changed)
	# Capture the shared button styleboxes before any alt override so we can
	# restore them when the alt menu is toggled off.
	for s in ["normal", "hover", "pressed", "focus"]:
		_orig_button_styles[s] = %ConstructButton.get_theme_stylebox(s)
	_apply_menu_icons()
	# `swap bottom menu` cheat flips the icon set live.
	MatchState.alt_bottom_menu_changed.connect(func(_enabled): _apply_menu_icons())
	%ConstructButton.pressed.connect(_on_construct_pressed)
	%ResourcesButton.pressed.connect(_on_resources_pressed)
	%BuildingsButton.pressed.connect(_on_buildings_pressed)
	MatchState.building_ledger_filter_requested.connect(_on_building_ledger_filter_requested)
	%MarketButton.pressed.connect(_on_market_pressed)
	%PoliticsButton.pressed.connect(_on_politics_pressed)
	%TechButton.pressed.connect(_on_research_pressed)
	%PeopleButton.pressed.connect(_on_people_pressed)
	# (Bottom-menu click cues are auto-wired by Audio, which gives %BottomMenu
	# children the menu cue — see Audio._sound_for_button.)
	money_panel.take_loan_dialog = take_loan_dialog
	take_loan_dialog.loan_confirmed.connect(_on_loan_confirmed)
	take_loan_dialog.hide()

	# All panels start hidden
	construct_panel.hide()
	construct_panel_v2.hide()
	resource_panel.hide()
	market_panel.hide()
	research_panel.hide()
	mapmodes_button.pressed.connect(_on_mapmodes_pressed)
	mapmodes_panel.hide()
	top_bar.money_widget_clicked.connect(_on_money_widget_clicked)
	top_bar.money_panel_tab_requested.connect(_on_money_panel_tab_requested)
	money_panel.hide()
	top_bar.victory_widget_clicked.connect(_on_victory_widget_clicked)
	victory_panel.hide()
	# The council loyalty surface opens the People panel (Advisors tab is first).
	top_bar.council_widget_clicked.connect(_on_people_pressed)
	# Victory moment (spec §6): the HUD owns the auto-open so it can clear whatever
	# panel is showing first (the panel can't hide its own siblings).
	VictoryState.victory_achieved.connect(_on_victory_achieved)
	# End of game at the turn cap: the full Victory / Defeat end screen (bankruptcy has
	# its own game-over panel via SolvencyState, so we ignore that reason here).
	if TurnManager.has_signal("game_ended_signal"):
		TurnManager.game_ended_signal.connect(_on_game_ended_signal)
	# Tile-view "Buy Buildings" → open the Market on the Buildings tab, filtered to that tile.
	MatchState.buildings_market_for_tile_requested.connect(_on_buildings_market_for_tile)

	# A button rises while its panel is open and drops when it closes. Buttons
	# with no panel (Politics/People) and disabled buttons never rise.
	_link_rise(construct_panel, %ConstructButton)
	_link_rise(construct_panel_v2, %ConstructButton)
	_link_rise(resource_panel, %ResourcesButton)
	_link_rise(market_panel, %MarketButton)
	_link_rise(mapmodes_panel, %MapmodesButton)
	_link_rise(research_panel, %TechButton)


# Keyboard shortcuts for the bottom-menu tools. Emitting the button's own `pressed` keeps
# behaviour identical to a click (panel toggle + rise tween + audio cue). Runs in
# _unhandled_key_input so it fires only for keys not already consumed by a focused widget /
# _input (Tab=empire) / _unhandled_input (X=encyclopedia), and it skips modified/repeat keys
# and never fires while a text field (market/ledger search) has focus.
const _MENU_SHORTCUTS := {
	KEY_C: "ConstructButton",   # Construct
	KEY_G: "ResourcesButton",   # Goods
	KEY_M: "MarketButton",      # Markets
	KEY_O: "MapmodesButton",    # Map Overlays
	KEY_L: "BuildingsButton",   # Buildings ledger
	KEY_N: "PoliticsButton",    # Narrative and Politics
	KEY_P: "PeopleButton",      # People (labour/advisors)
	KEY_R: "TechButton",        # Research
}

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var k := event as InputEventKey
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed or k.shift_pressed:
		return
	if not _MENU_SHORTCUTS.has(k.keycode):
		return
	if _is_text_entry_focused():
		return
	var button := get_node_or_null("%" + str(_MENU_SHORTCUTS[k.keycode])) as Button
	if button == null or button.disabled or not button.visible:
		return
	button.pressed.emit()
	get_viewport().set_input_as_handled()

func _is_text_entry_focused() -> bool:
	var fo := get_viewport().gui_get_focus_owner()
	return fo is LineEdit or fo is TextEdit

func _icon_tier() -> String:
	# Pick icon resolution from window height: sub-1080p -> 100, 1080p -> 200,
	# above 1080p -> 400. The buttons render small, so a larger source downscales
	# crisply (with the BottomMenu's Linear texture filter).
	var h := DisplayServer.window_get_size().y
	if h >= 1440:
		return "400"
	if h >= 1080:
		return "200"
	return "100"

func _apply_menu_icons() -> void:
	# Swapping menus re-applies resting styleboxes, so drop any lifted tracking.
	_lifted.clear()
	_rest_styles.clear()
	for bn in MENU_ICONS:
		var b := get_node_or_null("%" + bn) as Button
		if b != null:
			var sp := b.get_node_or_null("Specular")
			if sp != null:
				sp.visible = false
	# Alternate set: single-resolution PNGs in assets/icons/ui_icons/alt/, each
	# button recoloured to its own scheme (background fill + object/ring colour).
	if MatchState.use_alt_bottom_menu:
		for button_name in ALT_MENU_ICONS:
			_set_button_icon(button_name, "res://assets/icons/ui_icons/alt/%s.png" % ALT_MENU_ICONS[button_name])
			_apply_alt_button_style(button_name)
		return
	# Current set: multi-resolution circular art picked by window height.
	var tier := _icon_tier()
	for button_name in MENU_ICONS:
		_restore_button_style(button_name)
		var icon_name: String = MENU_ICONS[button_name]
		if icon_name == "":
			_set_button_icon(button_name, "")  # empty slot → clear any icon
		else:
			_set_button_icon(button_name, "res://assets/icons/ui_icons/%s/%s.png" % [tier, icon_name])

func _make_alt_button_style(fg: Color, fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_border_width_all(6)  # 6px outer ring, same colour as the object
	sb.border_color = fg
	sb.set_corner_radius_all(45)  # round on the 90px button
	# 0 keeps the icon filling the whole button (Godot clamps the expanded icon
	# to the button rect, so negative margins have no extra effect). The objects'
	# reach to the ring is handled by the artwork scale instead.
	sb.set_content_margin_all(0)
	sb.shadow_color = Color(0.02, 0.035, 0.045, 0.55)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(4, 4)  # to the bottom-right (offset > blur, light from top-left)
	return sb

func _apply_alt_button_style(button_name: String) -> void:
	if not ALT_COLORS.has(button_name):
		return
	var button := get_node_or_null("%" + button_name) as Button
	if button == null:
		return
	var bg := Color(ALT_COLORS[button_name][0])
	var fg := Color(ALT_COLORS[button_name][1])
	button.add_theme_stylebox_override("normal", _make_alt_button_style(fg, bg))
	button.add_theme_stylebox_override("hover", _make_alt_button_style(fg, bg))
	button.add_theme_stylebox_override("pressed", _make_alt_button_style(fg, bg.darkened(0.08)))
	button.add_theme_stylebox_override("focus", _make_alt_button_style(fg, bg))
	# Per-button glow texture: an inside-out radial (bright centre → fades to the
	# ring) with the object cut out, so only the background glows on hover.
	_ensure_alt_glow(button, Color(bg.lightened(0.3), 0.55), "res://assets/icons/ui_icons/alt/_glow_%s.png" % ALT_MENU_ICONS[button_name])

func _ensure_alt_glow(button: Button, glow_color: Color, tex_path: String) -> void:
	var glow := button.get_node_or_null("AltGlow") as TextureRect
	if glow == null:
		glow = TextureRect.new()
		glow.name = "AltGlow"
		glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glow.stretch_mode = TextureRect.STRETCH_SCALE
		glow.set_anchors_preset(Control.PRESET_FULL_RECT)
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = mat
		button.add_child(glow)
		button.mouse_entered.connect(func(): _hovered[button] = true; _update_glow(button))
		button.mouse_exited.connect(func(): _hovered[button] = false; _update_glow(button))
	if ResourceLoader.exists(tex_path):
		glow.texture = load(tex_path)
	glow.modulate = glow_color
	_update_glow(button)

# Glow shows on hover OR while the button is selected (raised), in alt mode.
func _update_glow(button: Button) -> void:
	var glow := button.get_node_or_null("AltGlow")
	if glow != null:
		glow.visible = MatchState.use_alt_bottom_menu and (_hovered.get(button, false) or _lifted.get(button, false))

func _restore_button_style(button_name: String) -> void:
	var button := get_node_or_null("%" + button_name) as Button
	if button == null:
		return
	for s in ["normal", "hover", "pressed", "focus"]:
		if _orig_button_styles.has(s) and _orig_button_styles[s] != null:
			button.add_theme_stylebox_override(s, _orig_button_styles[s])
	var glow := button.get_node_or_null("AltGlow")
	if glow != null:
		glow.visible = false

func _set_button_icon(button_name: String, path: String) -> void:
	var button := get_node_or_null("%" + button_name) as Button
	if button == null:
		return
	if path == "":
		button.icon = null  # explicit empty slot
		return
	if not ResourceLoader.exists(path):
		return
	button.icon = load(path)

func _hide_all_panels() -> void:
	_set_panel_visible(construct_panel, false)
	_set_panel_visible(construct_panel_v2, false)
	_set_panel_visible(resource_panel, false)
	_set_panel_visible(market_panel, false)
	_set_panel_visible(mapmodes_panel, false)
	_set_panel_visible(money_panel, false)
	_set_panel_visible(research_panel, false)
	_set_panel_visible(victory_panel, false)
	# The mapmode good-select side panel follows the mapmodes panel.
	var good_panel := get_node_or_null("%GoodSelectPanel")
	if good_panel != null:
		good_panel.hide()
	if is_instance_valid(building_ledger_panel):
		_set_panel_visible(building_ledger_panel, false)
	if is_instance_valid(people_panel):
		_set_panel_visible(people_panel, false)

# Toggle a bottom-menu panel: if it's already open, close it; otherwise hide the siblings
# and open it. Visibility is captured before _hide_all_panels() would clear it. Also drives
# the keyboard shortcuts, which emit the button's pressed signal → these same handlers.
func _toggle_panel(panel: Control) -> void:
	if panel != null and panel.visible:
		_set_panel_visible(panel, false)
		return
	_hide_all_panels()
	if panel != null:
		_set_panel_visible(panel, true)

func _set_panel_visible(panel: Control, show_it: bool) -> void:
	if show_it:
		panel.show()
		PanelStack.push(panel)
	else:
		if panel.visible:
			PanelStack.remove(panel)
		panel.hide()

func hide_bottom_menu() -> void:
	_hide_all_panels()
	bottom_menu.hide()

func show_bottom_menu() -> void:
	bottom_menu.show()

# Raise a button while its panel is visible; drop it when hidden. 120ms each way.
func _link_rise(panel: Control, button: Button) -> void:
	panel.visibility_changed.connect(func(): _raise_button(button, panel.visible))

func _raise_button(button: Button, raised: bool) -> void:
	if button == null or button.disabled:
		return  # disabled / not-enabled buttons stay put
	if raised and not _button_home_y.has(button):
		_button_home_y[button] = button.position.y  # capture resting y once, post-layout
	if not _button_home_y.has(button):
		return  # never raised yet → nothing to drop
	var home: float = _button_home_y[button]
	var target: float = (home - RISE_PX) if raised else home
	if _rise_tween.has(button) and _rise_tween[button] != null and _rise_tween[button].is_valid():
		_rise_tween[button].kill()
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(button, "position:y", target, RISE_TIME)
	_rise_tween[button] = tw
	_set_lifted(button, raised)

# Lifted look for the selected button: a longer/softer drop shadow (it's higher
# off the plate) and a faint specular highlight on the top of the disc.
func _set_lifted(button: Button, lifted: bool) -> void:
	if lifted == _lifted.get(button, false):
		return
	_lifted[button] = lifted
	if lifted:
		_rest_styles[button] = {}
		for s in ["normal", "hover", "pressed", "focus"]:
			var sb := button.get_theme_stylebox(s)
			_rest_styles[button][s] = sb
			if sb is StyleBoxFlat:
				var lf: StyleBoxFlat = sb.duplicate()
				lf.shadow_size = 10
				# Offset > blur so the shadow falls only to the bottom-right
				# (diagonal with the top-left light), not straight down on the left.
				lf.shadow_offset = Vector2(13, 13)
				lf.shadow_color = Color(0, 0, 0, 0.55)
				button.add_theme_stylebox_override(s, lf)
		_ensure_specular(button).visible = true
	else:
		if _rest_styles.has(button):
			for s in _rest_styles[button]:
				if _rest_styles[button][s] != null:
					button.add_theme_stylebox_override(s, _rest_styles[button][s])
			_rest_styles.erase(button)
		var sp := button.get_node_or_null("Specular")
		if sp != null:
			sp.visible = false
	_update_glow(button)  # keep glowing while selected; drop when deselected

func _ensure_specular(button: Button) -> TextureRect:
	var sp := button.get_node_or_null("Specular") as TextureRect
	if sp == null:
		sp = TextureRect.new()
		sp.name = "Specular"
		sp.texture = load("res://assets/icons/ui_icons/alt/_specular.png")
		sp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sp.stretch_mode = TextureRect.STRETCH_SCALE
		sp.set_anchors_preset(Control.PRESET_FULL_RECT)
		sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(sp)
		sp.visible = false
	return sp

func _on_construct_pressed() -> void:
	var panel := _active_construct_panel()
	if panel.visible:
		_set_panel_visible(panel, false)
		return
	_hide_all_panels()
	if panel == construct_panel_v2 and panel.has_method("open_browser"):
		panel.open_browser()
	else:
		_set_panel_visible(panel, true)

func _active_construct_panel() -> PanelContainer:
	if MatchState.use_construct_panel_v2 and is_instance_valid(construct_panel_v2):
		return construct_panel_v2
	return construct_panel

func _on_construct_panel_v2_changed(_enabled: bool) -> void:
	var was_open: bool = construct_panel.visible or (is_instance_valid(construct_panel_v2) and construct_panel_v2.visible)
	_set_panel_visible(construct_panel, false)
	if is_instance_valid(construct_panel_v2):
		_set_panel_visible(construct_panel_v2, false)
	if was_open:
		_set_panel_visible(_active_construct_panel(), true)

func _on_resources_pressed() -> void:
	_toggle_panel(resource_panel)

func _on_mapmodes_pressed() -> void:
	# Toggles the map-overlays panel. Closing it also dismisses the good-select side
	# panel that follows it. Leaves building-detail / tile-view panels alone.
	if mapmodes_panel.visible:
		_set_panel_visible(mapmodes_panel, false)
		var gp := get_node_or_null("%GoodSelectPanel")
		if gp != null:
			gp.hide()
		return
	_hide_all_panels()
	_set_panel_visible(mapmodes_panel, true)

func _on_market_pressed() -> void:
	_toggle_panel(market_panel)

func _on_buildings_market_for_tile(tile_id: String) -> void:
	_hide_all_panels()
	if market_panel.has_method("open_buildings_for_tile"):
		market_panel.open_buildings_for_tile(tile_id)
	_set_panel_visible(market_panel, true)

func _on_buildings_pressed() -> void:
	_show_building_ledger()

# Lazy-create (no main.tscn edit needed) + show the building ledger. `allow_toggle` closes it
# when it's already open (button/shortcut); the filter deep-link passes false to always open.
func _show_building_ledger(allow_toggle: bool = true) -> void:
	if allow_toggle and is_instance_valid(building_ledger_panel) and building_ledger_panel.visible:
		_set_panel_visible(building_ledger_panel, false)
		return
	_hide_all_panels()
	if not is_instance_valid(building_ledger_panel):
		building_ledger_panel = BUILDING_LEDGER_PANEL_SCENE.instantiate()
		# Add as sibling to the other panels so it lives in HUDContent.
		construct_panel.get_parent().add_child(building_ledger_panel)
		building_ledger_panel.hide()
		building_ledger_panel.close_requested.connect(
			func(): _set_panel_visible(building_ledger_panel, false)
		)
		_link_rise(building_ledger_panel, %BuildingsButton)
	_set_panel_visible(building_ledger_panel, true)

# Deep-link: open the ledger pre-filtered to a single filter key (e.g. the tile-view
# intermittency "see more" → "green_intermittent"). _ready() ran on instantiate, so the
# chips exist by the time we set the preset.
func _on_building_ledger_filter_requested(filter_key: String) -> void:
	_show_building_ledger(false)   # deep-link always opens (never toggles closed)
	if is_instance_valid(building_ledger_panel) and building_ledger_panel.has_method("set_filter_preset"):
		building_ledger_panel.set_filter_preset(filter_key)

func _on_politics_pressed() -> void:
	print("Politics panel not yet implemented")

func _on_research_pressed() -> void:
	_toggle_panel(research_panel)

func _on_people_pressed() -> void:
	if is_instance_valid(people_panel) and people_panel.visible:
		_set_panel_visible(people_panel, false)
		return
	_hide_all_panels()
	if not is_instance_valid(people_panel):
		people_panel = PeoplePanel.new()
		construct_panel.get_parent().add_child(people_panel)
		people_panel.hide()
		people_panel.close_requested.connect(
			func(): _set_panel_visible(people_panel, false)
		)
		_link_rise(people_panel, %PeopleButton)
	_set_panel_visible(people_panel, true)

func _on_money_widget_clicked() -> void:
	_hide_all_panels()
	_set_panel_visible(money_panel, true)
	money_panel.open_tab("Balance")

func _on_money_panel_tab_requested(tab_name: String) -> void:
	_hide_all_panels()
	_set_panel_visible(money_panel, true)
	money_panel.open_tab(tab_name)

func _on_victory_widget_clicked() -> void:
	# Toggle: clicking the top-bar score widget opens the Victory panel, or closes
	# it if it is already the open panel.
	if victory_panel.visible:
		_set_panel_visible(victory_panel, false)
	else:
		_hide_all_panels()
		_set_panel_visible(victory_panel, true)

func _on_victory_achieved(total: int, turn: int) -> void:
	# Crossing the win threshold at ANY turn ends the game with the Victory screen
	# (owner 2026-07-11 — previously the game kept going and only auto-opened the tracks
	# panel). Headless balance runs are exempt so a mid-run win never cuts them short.
	if DisplayServer.get_name() == "headless":
		return
	MatchState.request_toast("VICTORY — score %d on turn %d!" % [total, turn], "success")
	TurnManager.game_ended = true
	_show_end_screen()

# Reached the turn cap without a win → Defeat. game_ended_signal fires just BEFORE
# turn_resolution_completed (the final VictoryState tick), so wait for that tick; if a
# win latched on the final turn its Victory screen has already been shown.
func _on_game_ended_signal(reason: String) -> void:
	if reason != "turn_cap_reached" or _end_screen != null or DisplayServer.get_name() == "headless":
		return
	await TurnManager.turn_resolution_completed
	await get_tree().process_frame   # let VictoryState._tick finish for the final turn
	if VictoryState.won:
		return
	_show_end_screen()

# Build + present the full end-of-game screen from the live result. Idempotent.
func _show_end_screen() -> void:
	if _end_screen != null:
		return
	_hide_all_panels()
	var data: Dictionary = EndGameData.gather()
	if str(data.get("result", "")) == "victory":
		# Hall of Records: victories only — defeats leave no trace.
		PlayerProfile.record_win({
			"date": Time.get_date_string_from_system(),
			"title": str(data.get("title", "Victory")),
			"turn": int(data.get("turn", 0)),
			"secured": int(data.get("secured_count", 0)),
			"epithet": str(data.get("epithet", "")),
		})
	_end_screen = VictoryEndScreen.new()
	add_child(_end_screen)
	_end_screen.back_to_menu_pressed.connect(_on_end_screen_back)
	_end_screen.show_end(data)

func _on_end_screen_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _on_loan_confirmed(amount: float) -> void:
	var ok: bool = LoanState.take_loan(amount)
	if not ok:
		print("[HUD] Loan request failed for £%.2f" % amount)
	# Auto-switch Money panel to Loans tab.
	money_panel.open_tab("Loans")
	money_panel.show()
