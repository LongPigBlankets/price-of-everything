extends CanvasLayer
## In-game debug / cheat terminal. Toggle with the backtick key ( ` ); Esc closes.
## Type a command and press Enter. Add new cheats in _run_command().
##
## Commands:
##   cash <int>                       add that much cash (negative allowed)
##   sellmode <stockpile|market|building>  set the global production sell mode
##   help                             list commands

const TOGGLE_KEY := KEY_QUOTELEFT  # the ` / ~ key

var _panel: PanelContainer
var _cmd: LineEdit
var _output: RichTextLabel

func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_panel.offset_bottom = 240.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.03, 0.06, 0.93)
	sb.border_color = Color(0.4, 0.9, 0.5, 0.6)
	sb.border_width_bottom = 2
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_output = RichTextLabel.new()
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.scroll_following = true
	_output.bbcode_enabled = true
	_output.add_theme_color_override("default_color", Color(0.7, 1.0, 0.75))
	vbox.add_child(_output)

	_cmd = LineEdit.new()
	_cmd.placeholder_text = "cheat…  e.g.  cash 1000        ( ` to close )"
	_cmd.text_submitted.connect(_on_submit)
	vbox.add_child(_cmd)

	_print_line("[b]Debug terminal[/b] — type 'help'. Toggle with the ` key.")

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == TOGGLE_KEY:
			_set_open(not _panel.visible)
			get_viewport().set_input_as_handled()
		elif _panel.visible and event.keycode == KEY_ESCAPE:
			_set_open(false)
			get_viewport().set_input_as_handled()

func _set_open(open: bool) -> void:
	_panel.visible = open
	if open:
		_cmd.clear()
		_cmd.grab_focus()
	else:
		_cmd.release_focus()

func _on_submit(text: String) -> void:
	var t := text.strip_edges()
	if t != "":
		_print_line("[color=#9fcaff]> %s[/color]" % t)
		_print_line(_run_command(t))
	_cmd.clear()
	_cmd.grab_focus()

func _print_line(s: String) -> void:
	if s != "":
		_output.append_text(s + "\n")

func _run_command(text: String) -> String:
	var parts := text.split(" ", false)
	if parts.is_empty():
		return ""
	match parts[0].to_lower():
		"cash":
			if parts.size() < 2 or not parts[1].is_valid_int():
				return "usage: cash <integer>"
			var amount := int(parts[1])
			MatchState.add_money(float(amount))
			return "Added £%d  (balance now £%.2f)" % [amount, MatchState.money]
		"sellmode":
			if parts.size() < 2:
				return "usage: sellmode <stockpile|market|building>  (current: %s)" % _sell_mode_name()
			match parts[1].to_lower():
				"stockpile":
					MatchState.set_sell_mode(MatchState.SellMode.STOCKPILE_ALL)
				"market":
					MatchState.set_sell_mode(MatchState.SellMode.SELL_ALL)
				"building":
					MatchState.set_sell_mode(MatchState.SellMode.BUILDING_BY_BUILDING)
				_:
					return "usage: sellmode <stockpile|market|building>"
			return "sell mode → %s" % _sell_mode_name()
		"help":
			return "commands:  cash <int>   |   sellmode <stockpile|market|building>   |   help"
		_:
			return "unknown command: '%s'  (try 'help')" % parts[0]

func _sell_mode_name() -> String:
	match MatchState.sell_mode:
		MatchState.SellMode.STOCKPILE_ALL:
			return "stockpile"
		MatchState.SellMode.SELL_ALL:
			return "market"
		MatchState.SellMode.BUILDING_BY_BUILDING:
			return "building"
		_:
			return "unknown"
