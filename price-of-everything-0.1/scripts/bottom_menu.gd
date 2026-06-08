extends Control

const BUILDING_LEDGER_PANEL_SCENE := preload("res://scenes/building_ledger_panel.tscn")

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
	"MapmodesButton":  ["#ffffff", "#45597e"],
	"MarketButton":    ["#235b3c", "#e4efcf"],
	"PoliticsButton":  ["#5a2c56", "#ecdce6"],
	"TechButton":      ["#1e5e63", "#ddefec"],
	"PeopleButton":    ["#a8466b", "#f6dfe7"],
}

# Original (shared) button styleboxes captured at _ready, re-applied when the
# alt menu is toggled back off.
var _orig_button_styles := {}

@onready var bottom_menu = %BottomMenu
@onready var construct_panel = %ConstructPanel
@onready var resource_panel: PanelContainer = %ResourcePanel
@onready var market_panel: PanelContainer = %MarketPanel
@onready var mapmodes_button: Button = %MapmodesButton
@onready var mapmodes_panel: PanelContainer = %MapModesPanel
@onready var top_bar: PanelContainer = %TopBar
@onready var money_panel: PanelContainer = %MoneyPanel
@onready var take_loan_dialog: PanelContainer = %TakeLoanDialog

# Building ledger is instantiated lazily on first open (no main.tscn edit needed).
var building_ledger_panel: PanelContainer = null

func _ready() -> void:
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
	%MarketButton.pressed.connect(_on_market_pressed)
	%PoliticsButton.pressed.connect(_on_politics_pressed)
	%TechButton.pressed.connect(_on_tech_pressed)
	%PeopleButton.pressed.connect(_on_people_pressed)
	money_panel.take_loan_dialog = take_loan_dialog
	take_loan_dialog.loan_confirmed.connect(_on_loan_confirmed)
	take_loan_dialog.hide()

	# All panels start hidden
	construct_panel.hide()
	resource_panel.hide()
	market_panel.hide()
	mapmodes_button.pressed.connect(_on_mapmodes_pressed)
	mapmodes_panel.hide()
	top_bar.money_widget_clicked.connect(_on_money_widget_clicked)
	money_panel.hide()

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
	# Slightly negative so the objects render full-size (not shrunk) and their
	# outer reach (e.g. the hammer handle, politics block) meets the ring.
	sb.set_content_margin_all(-2)
	sb.shadow_color = Color(0.02, 0.035, 0.045, 0.55)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
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
	button.add_theme_stylebox_override("hover", _make_alt_button_style(fg, bg.lightened(0.08)))
	button.add_theme_stylebox_override("pressed", _make_alt_button_style(fg, bg.darkened(0.08)))
	button.add_theme_stylebox_override("focus", _make_alt_button_style(fg, bg))

func _restore_button_style(button_name: String) -> void:
	var button := get_node_or_null("%" + button_name) as Button
	if button == null:
		return
	for s in ["normal", "hover", "pressed", "focus"]:
		if _orig_button_styles.has(s) and _orig_button_styles[s] != null:
			button.add_theme_stylebox_override(s, _orig_button_styles[s])

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
	_set_panel_visible(resource_panel, false)
	_set_panel_visible(market_panel, false)
	_set_panel_visible(mapmodes_panel, false)
	_set_panel_visible(money_panel, false)
	if is_instance_valid(building_ledger_panel):
		_set_panel_visible(building_ledger_panel, false)

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

func _on_construct_pressed() -> void:
	_hide_all_panels()
	_set_panel_visible(construct_panel, true)

func _on_resources_pressed() -> void:
	_hide_all_panels()
	_set_panel_visible(resource_panel, true)

func _on_mapmodes_pressed() -> void:
	_set_panel_visible(mapmodes_panel, true)

func _on_market_pressed() -> void:
	_hide_all_panels()
	_set_panel_visible(market_panel, true)

func _on_buildings_pressed() -> void:
	_hide_all_panels()
	if not is_instance_valid(building_ledger_panel):
		building_ledger_panel = BUILDING_LEDGER_PANEL_SCENE.instantiate()
		# Add as sibling to the other panels so it lives in HUDContent.
		construct_panel.get_parent().add_child(building_ledger_panel)
		building_ledger_panel.hide()
		building_ledger_panel.close_requested.connect(
			func(): _set_panel_visible(building_ledger_panel, false)
		)
	_set_panel_visible(building_ledger_panel, true)

func _on_politics_pressed() -> void:
	print("Politics panel not yet implemented")

func _on_tech_pressed() -> void:
	print("Tech panel not yet implemented")

func _on_people_pressed() -> void:
	print("People panel not yet implemented")

func _on_money_widget_clicked() -> void:
	_hide_all_panels()
	_set_panel_visible(money_panel, true)

func _on_loan_confirmed(amount: float) -> void:
	var ok: bool = LoanState.take_loan(amount)
	if not ok:
		print("[HUD] Loan request failed for £%.2f" % amount)
	# Auto-switch Money panel to Loans tab
	var tab_container: TabContainer = money_panel.get_node("MarginContainer/ModalLayout/TabContainer")
	tab_container.current_tab = 3  # 0=Stats, 1=Balance, 2=Budget, 3=Loans
	money_panel.show()
