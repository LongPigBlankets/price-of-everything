extends PopupPanel
## A tile's quick menu, opened by a right click on the map: the tile's name over its quick actions on Building
## Detail's black plastic case (the DS2 kit's parts), each a bevelled cream key (the tile view's keys) with what it
## will do printed beside it. An action that cannot run here keeps its key, greyed, and the reason beside it. Selling a good and building a favourite open a short list in the
## same case; buying all the land asks first, since it raises the neighbours. What each action does and says is
## TileQuickActions'; this only draws it. Closes on a click outside, Esc, or once an action has run.

const Actions := preload("res://scripts/tile_quick_actions.gd")
const Parts := preload("res://scripts/ds2/parts.gd")
const UIFonts := preload("res://scripts/ui_fonts.gd")

const CabinetKey := preload("res://scripts/ds2/latch_key.gd")

const WIDTH := 460.0
const TITLE_PX := 20
const WORDS_PX := 15
const KEY_W := 156.0
const ROW_GAP := 12

var tile_id := ""
var tile_data: Dictionary = {}
var page := "main"
var _case: MarginContainer = null


func _init() -> void:
	name = "TileQuickMenu"
	var clear := StyleBoxEmpty.new()
	add_theme_stylebox_override("panel", clear)
	transparent_bg = true
	wrap_controls = true


## Open the menu for the tile at `at` (screen position).
func open_for(data: Dictionary, at: Vector2) -> void:
	tile_data = data
	tile_id = str(data.get("id", ""))
	show_page("main")
	popup(Rect2i(Vector2i(at) + Vector2i(6, 6), Vector2i(int(WIDTH), 0)))
	_keep_on_screen()


func show_page(which: String) -> void:
	page = which
	if _case != null:
		remove_child(_case)
		_case.queue_free()
	_case = Parts.plastic_case("QuickMenuCase")
	_case.custom_minimum_size.x = WIDTH
	add_child(_case)
	var rows: VBoxContainer = _case.get_child(0)
	rows.add_theme_constant_override("separation", ROW_GAP)
	rows.add_child(_title(Actions.place(tile_id)))
	match which:
		"goods":
			_back_row(rows)
			for r: Dictionary in Actions.goods_options(tile_id):
				var gid := str(r.good_id)
				_row(rows, "Good_" + gid, "Sell", "%s, %s here. %s" % [str(r.name), Actions._count(int(r.qty)), str(r.words)], bool(r.ok),
					func() -> void: _finish(Actions.sell(tile_id, {gid: int(r.qty)})))
		"favourites":
			_back_row(rows)
			for r: Dictionary in Actions.favourite_options(tile_id, tile_data):
				var fav: Dictionary = r.favourite
				_row(rows, "Favourite", "Build", "%s. %s" % [str(r.title), str(r.words)], bool(r.ok), func() -> void:
					hide()
					Actions.build_favourite(tile_id, fav))
		"buy_land":
			rows.add_child(_words(Actions.buy_land_confirm(tile_id), WIDTH - 2.0 * Parts.case_margin()))
			var keys := HBoxContainer.new()
			keys.add_theme_constant_override("separation", ROW_GAP)
			rows.add_child(keys)
			keys.add_child(_key("BuyLandConfirm", "Buy", true, func() -> void:
				if Actions.buy_all_land(tile_id):
					Audio.transaction()
					_finish({"ok": true, "words": "Bought all the land left on %s." % Actions.place(tile_id)})
				else:
					_finish({"ok": false, "words": "Could not buy the land."})))
			keys.add_child(_key("BuyLandCancel", "Cancel", true, func() -> void: show_page("main")))
		_:
			var surplus := Actions.surplus_option(tile_id)
			_row(rows, "SellSurplus", "Sell surplus", str(surplus.words), bool(surplus.ok), func() -> void:
				_finish(Actions.sell(tile_id, surplus.goods)))
			var goods := Actions.goods_entry(tile_id)
			_row(rows, "SellGood", "Sell a good", str(goods.words), bool(goods.ok), func() -> void: show_page("goods"))
			var buy := Actions.buy_land_option(tile_id)
			_row(rows, "BuyLand", "Buy all land", str(buy.words), bool(buy.ok), func() -> void: show_page("buy_land"))
			var sell := Actions.sell_land_option(tile_id)
			_row(rows, "SellLand", "Sell spare land", str(sell.words), bool(sell.ok), func() -> void:
				var done := BuildingState.sell_spare_land(tile_id)
				Audio.transaction()
				_finish({"ok": true, "words": "Sold %s land for %s." % [Actions._count(int(done.units)), Actions.LandPrice.pounds(float(done.paid))]}))
			var fav := Actions.favourite_entry(tile_id, tile_data)
			_row(rows, "BuildFavourite", "Build favourite", str(fav.words), bool(fav.ok), func() -> void: show_page("favourites"))
	reset_size.call_deferred()
	_keep_on_screen.call_deferred()


func _title(text: String) -> Label:
	var l := Label.new()
	l.name = "QuickMenuTitle"
	l.text = text
	l.add_theme_font_override("font", UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", TITLE_PX)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	return l


func _words(text: String, width: float) -> Label:
	var l := Label.new()
	l.name = "Words"
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = width
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_font_override("font", UIFonts.PLEX_MED)
	l.add_theme_font_size_override("font_size", WORDS_PX)
	l.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	return l


## A bevelled cream key (the tile view's keys) that runs `run` when pressed, greyed when it cannot.
func _key(key_name: String, label: String, ok: bool, run: Callable, width := KEY_W) -> Control:
	var k: Control = CabinetKey.new()
	k.name = "QuickKey_" + key_name
	k.text = label
	k.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	k.custom_minimum_size.x = width
	k.disabled = not ok
	if ok:
		k.pressed.connect(run)
	return k


func _back_row(rows: VBoxContainer) -> void:
	var line := HBoxContainer.new()
	line.name = "QuickAction_Back"
	line.add_child(_key("Back", "Back", true, func() -> void: show_page("main")))
	rows.add_child(line)


## One action: its key, and beside it on the plastic what it will do, or why it cannot (the key greyed and the
## same words on its hover).
func _row(rows: VBoxContainer, row_name: String, label: String, words: String, ok: bool, run: Callable) -> void:
	var line := HBoxContainer.new()
	line.name = "QuickAction_" + row_name
	line.add_theme_constant_override("separation", ROW_GAP)
	var key := _key(row_name, label, ok, run)
	key.tooltip_text = words
	key.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(key)
	line.add_child(_words(words, WIDTH - 2.0 * Parts.case_margin() - KEY_W - ROW_GAP))
	if not ok:
		line.set_meta("disabled", true)
	rows.add_child(line)


## Say what happened and close.
func _finish(result: Dictionary) -> void:
	MatchState.request_toast(str(result.get("words", "")), "success" if bool(result.get("ok", false)) else "warning")
	hide()


func _keep_on_screen() -> void:
	if not visible:
		return
	var screen := get_viewport().get_visible_rect().size if get_viewport() != null else Vector2(1920, 1080)
	var p := Vector2(position)
	p.x = clampf(p.x, 0.0, maxf(0.0, screen.x - float(size.x)))
	p.y = clampf(p.y, 0.0, maxf(0.0, screen.y - float(size.y)))
	position = Vector2i(p)
