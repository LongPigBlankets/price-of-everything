extends VBoxContainer
## The missions panel in DS2, opened from the top bar's mission slot: one tab key per board the match plays
## (MiniQuest.mission_boards(): Metal Magnate's Tutorial and its own board), the board itself as a mimic
## board running top to bottom (mission_board.gd) in a scroller that opens on the selected station, and under
## it a readout of the selected station: its lamp, name, what it asks
## and what it pays, its count on the piston, a key to show the board on the top bar, and at a choice the
## guarded key that takes this branch for good.
## Commands go to MiniQuest (choose, follow_board); everything shown comes from MiniQuest.mission_boards().

const Board := preload("res://scripts/missions_ds2/mission_board.gd")
const TabKey := preload("res://scripts/ds2/latch_key.gd")
const GuardKey := preload("res://scripts/ds2/guard_key.gd")
const Readout := preload("res://scripts/bdp_v3_readout.gd")
const Slot := preload("res://scripts/ds2/mission_slot.gd")
const Scroll := preload("res://scripts/bdp_v3_scroll.gd")

const WIDTH := 880.0
## How much of the board shows before it scrolls.
const BOARD_VIEW_H := 420.0
const READOUT_W := 480.0
const GUARD_PX := 46.0
const KEYS_W := 220.0
## The board and station shown when the panel opens, kept for the session: the top bar rebuilds the panel
## whenever the missions change, and reopening returns to the same place.
static var open_board := ""
static var open_station := ""

var _boards: Array = []
var _tabs: HBoxContainer
var _board: Control
var _scroll: ScrollContainer
var _readout: Control
var _piston: Control
var _follow: Control
var _reward: Label
var _take: Control
var _take_label: Label
var _current := ""


func _init() -> void:
	name = "MissionsPanel"
	add_theme_constant_override("separation", 10)
	custom_minimum_size = Vector2(WIDTH, 0.0)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 6)
	add_child(_tabs)
	_scroll = ScrollContainer.new()
	_scroll.name = "BoardScroll"
	_scroll.custom_minimum_size = Vector2(WIDTH, BOARD_VIEW_H)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	Scroll.apply(_scroll, true)
	_board = Board.new()
	_board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_board.station_selected.connect(_show_station)
	_scroll.add_child(_board)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	add_child(row)
	_readout = Readout.new()
	_readout.custom_minimum_size = Vector2(READOUT_W, Readout.HEIGHT)
	row.add_child(_readout)
	_piston = Slot.new()
	_piston.call("set_collapsed", true, 0.0)
	_piston.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_piston)
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override("separation", 6)
	keys.custom_minimum_size = Vector2(KEYS_W, 0.0)
	keys.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(keys)
	_reward = Label.new()
	_reward.name = "StationReward"
	_reward.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reward.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	keys.add_child(_reward)
	_follow = TabKey.new()
	_follow.name = "FollowBoardKey"
	_follow.set("text", "On the top bar")
	_follow.tooltip_text = "Show this board's current mission in the top bar."
	_follow.connect("pressed", _on_follow)
	keys.add_child(_follow)
	var take_row := HBoxContainer.new()
	take_row.add_theme_constant_override("separation", 8)
	keys.add_child(take_row)
	_take = GuardKey.new(GUARD_PX)
	_take.name = "TakeBranchKey"
	_take.set("layer", "guard_build")
	_take.set("tip", {"stage": "Choice", "name": "Take this branch", "detail": "The other branch closes for good.", "tone": "warn"})
	_take.connect("pressed", _on_take)
	take_row.add_child(_take)
	_take_label = Label.new()
	_take_label.text = "Take this branch. The other closes for good."
	_take_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_take_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_take_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_take_label.add_theme_color_override("font_color", DS.PALETTE.TEXT)
	take_row.add_child(_take_label)


func _ready() -> void:
	refresh()


## Rebuilds from MiniQuest: the tabs, the open board and its selected station.
func refresh() -> void:
	if not is_inside_tree():
		return
	_boards = MiniQuest.mission_boards()
	if _boards.is_empty():
		return
	var ids: Array = _boards.map(func(b: Dictionary) -> String: return str(b.get("id", "")))
	if not ids.has(open_board):
		var followed := MiniQuest.followed_board
		open_board = followed if ids.has(followed) else str(ids[0])
	for child in _tabs.get_children():
		child.queue_free()
	for b: Variant in _boards:
		var id := str((b as Dictionary).get("id", ""))
		var key: Control = TabKey.new()
		key.name = "BoardTab_%s" % id
		key.set("text", str((b as Dictionary).get("title", id)))
		key.set("latched", id == open_board)
		key.connect("pressed", _open.bind(id))
		_tabs.add_child(key)
	var board := _board_dict(open_board)
	var keep := open_station
	_board.call("set_board", board, WIDTH - 24.0)
	if keep == "" or _station(board, keep).is_empty():
		keep = _default_station(board)
	_board.set("selected", keep)
	_show_station(keep)
	_scroll_to.call_deferred(keep)


## Brings a station into the middle of the scroller.
func _scroll_to(id: String) -> void:
	var n := _station(_board_dict(open_board), id)
	if n.is_empty() or not is_instance_valid(_scroll):
		return
	var y: float = (_board.call("station_point", n) as Vector2).y
	_scroll.scroll_vertical = int(maxf(0.0, y - BOARD_VIEW_H * 0.5))


func _open(board_id: String) -> void:
	open_board = board_id
	open_station = ""
	refresh()


func _board_dict(board_id: String) -> Dictionary:
	for b: Variant in _boards:
		if str((b as Dictionary).get("id", "")) == board_id:
			return b as Dictionary
	return {}


static func _station(board: Dictionary, id: String) -> Dictionary:
	for n: Variant in board.get("nodes", []) as Array:
		if str((n as Dictionary).get("id", "")) == id:
			return n as Dictionary
	return {}


## The station a board opens on: its first open one, else its first.
static func _default_station(board: Dictionary) -> String:
	var nodes: Array = board.get("nodes", []) as Array
	for n: Variant in nodes:
		var state := str((n as Dictionary).get("state", ""))
		if state == "active" or state == "choice":
			return str((n as Dictionary).get("id", ""))
	return str((nodes[0] as Dictionary).get("id", "")) if not nodes.is_empty() else ""


func _show_station(id: String) -> void:
	_current = id
	open_station = id
	var board := _board_dict(open_board)
	var n := _station(board, id)
	var state := str(n.get("state", "locked"))
	var detail := str(n.get("subtitle", ""))
	var reward := str(n.get("reward", ""))
	_reward.text = "Reward: %s" % reward if reward != "" else "No reward"

	var stage: String = {"complete": "Done", "active": "Mission", "choice": "Choice", "locked": "Locked", "closed": "Not taken"}.get(state, "Mission")
	_readout.call("show_check", stage, str(n.get("title", "")), detail, Board._tone(state))
	var progress: Vector2i = n.get("progress", Vector2i.ZERO)
	_piston.call("set_mission", "", progress)
	_piston.visible = progress.y > 1
	var themed := bool(board.get("themed", false))
	var followed := MiniQuest.effective_followed_board() == open_board if themed else MiniQuest.followed_board == ""
	_follow.set("latched", followed)
	var choosing := state == "choice"
	_take.get_parent().visible = choosing


func _on_follow() -> void:
	var board := _board_dict(open_board)
	MiniQuest.follow_board(open_board if bool(board.get("themed", false)) else "")


func _on_take() -> void:
	if MiniQuest.choose(_current):
		refresh()
