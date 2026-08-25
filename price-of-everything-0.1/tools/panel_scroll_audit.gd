extends Node
## Sweep every panel for scroll overflow.
##
## Three failures, all of which have shipped in this repo at least once: content taller
## than its scroll with NO scrollbar (it is simply cut off), a scroll with no height at
## all (the tab renders blank), and a panel whose own bottom falls off the screen. The
## unit suite cannot see any of them — they are layout, not logic — so this measures.
##
## Two things stop it crying wolf. A scroll is only measured when it is VISIBLE IN TREE:
## a TabContainer's hidden tabs have zero size by design, and reporting them as broken
## buries the real findings. And every tab is walked in turn, because a panel's worst tab
## is rarely the one it opens on.

const START := "res://data/starts/metal_magnate.json"

var _problems := 0

func _ready() -> void:
	get_window().size = Vector2i(1920, 1080)
	SaveLoad.prepare_new_game(START)
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	add_child(main)
	var f := 0
	while f < 5000 and main.get("build_complete") != true:
		await get_tree().process_frame
		f += 1
	await _settle(20)
	# Ten turns first: a panel that fits when every list is empty proves nothing, and the
	# overflow complaint came from a 118-turn run. Then poke the two panels the bottom menu
	# builds LAZILY on first press, or they are simply not in the tree to sweep.
	for _t in 10:
		TurnManager.commit_turn()
		await _settle(4)
	var menu: Node = main.find_child("BottomMenuPanel", true, false)
	if menu != null:
		if menu.has_method("_show_building_ledger"):
			menu.call("_show_building_ledger", false)
			await _settle(6)
		if menu.has_method("_on_people_pressed"):
			menu.call("_on_people_pressed")
			await _settle(6)
	# The two panels a player lives in — the tile view and a building's sheet — hold NO
	# scroll content until something is selected, so an audit that never selects anything
	# silently skips exactly the panels most likely to overflow.
	var iid := ""
	var tid := ""
	for k: Variant in MatchState.buildings:
		var b: Dictionary = MatchState.buildings[k]
		if MatchState.is_player_owned(b):
			iid = str(k)
			tid = str(b.get("tile_id", ""))
			break
	if tid != "":
		MatchState.focus_tile_requested.emit(tid)
		await _settle(10)
	if iid != "":
		MatchState.focus_building_requested.emit(iid)
		await _settle(12)
	await _settle(10)

	var panels: Array = []
	_collect(main, panels)
	print("[SCROLL] sweeping %d panels" % panels.size())
	for p_variant: Variant in panels:
		var panel := p_variant as Control
		var was: bool = panel.visible
		panel.visible = true
		await _settle(8)
		var tabs: Array = []
		_collect_tabs(panel, tabs)
		if tabs.is_empty():
			await _measure(panel, "")
		else:
			var tc := tabs[0] as TabContainer
			var back: int = tc.current_tab
			for i in tc.get_tab_count():
				tc.current_tab = i
				await _settle(8)
				await _measure(panel, tc.get_tab_title(i))
			tc.current_tab = back
		panel.visible = was
		await _settle(2)
	print("[SCROLL] %d finding(s)" % _problems)
	get_tree().quit(0)


func _measure(panel: Control, tab: String) -> void:
	var label: String = str(panel.name) if tab == "" else "%s / %s" % [panel.name, tab]
	var scrolls: Array = []
	_collect_scrolls(panel, scrolls)
	var vh: float = get_viewport().get_visible_rect().size.y
	var tags: Array = []
	var bottom: float = panel.global_position.y + panel.size.y
	if bottom > vh + 1.0:
		tags.append("panel bottom %dpx below the screen" % int(bottom - vh))
	var seen := 0
	for s_variant: Variant in scrolls:
		var sc := s_variant as ScrollContainer
		if not sc.is_visible_in_tree():
			continue
		var inner: Control = null
		for c in sc.get_children():
			if c is Control and not (c is ScrollBar):
				inner = c as Control
				break
		if inner == null:
			continue
		var want: float = inner.get_combined_minimum_size().y
		if want <= 0.0:
			continue          # nothing to show yet; not a layout fault
		seen += 1
		var bar := sc.get_v_scroll_bar()
		var has_bar: bool = bar != null and bar.visible
		if sc.size.y < 8.0:
			tags.append("%s: scroll has NO HEIGHT (content %dpx)" % [sc.name, int(want)])
		elif want > sc.size.y + 2.0 and not has_bar:
			tags.append("%s: %dpx of content in %dpx, NO SCROLLBAR" % [sc.name, int(want), int(sc.size.y)])
	if tags.is_empty():
		print("[SCROLL] ok   %-34s %d visible scroll(s)" % [label, seen])
	else:
		_problems += 1
		print("[SCROLL] FAIL %-34s %s" % [label, " | ".join(tags)])


func _collect(n: Node, out: Array) -> void:
	if n is Control:
		var scr: Variant = n.get_script()
		var path: String = str((scr as Script).resource_path) if scr != null else ""
		if path.ends_with("_panel.gd") or path.ends_with("_panel_v2.gd"):
			out.append(n)
	for c in n.get_children():
		_collect(c, out)


func _collect_scrolls(n: Node, out: Array) -> void:
	if n is ScrollContainer:
		out.append(n)
	for c in n.get_children():
		_collect_scrolls(c, out)


func _collect_tabs(n: Node, out: Array) -> void:
	if n is TabContainer:
		out.append(n)
	for c in n.get_children():
		_collect_tabs(c, out)


func _settle(n: int) -> void:
	for _i in range(n):
		await get_tree().process_frame
