extends Node
## SolvencyState: the distressed-asset offer and the bankruptcy end-state.
##
## Each turn it snapshots four financials (money, post-tax profit, empire sale value,
## output market value) into a saved history that the game-over charts read. It also
## watches the floor:
##   * The FIRST time cash reaches DISTRESS_FLOOR (−£500), if a CFO is seated, the CFO
##     proposes the Distressed Asset Program (a DecisionState one-shot).
##   * If cash stays at/below the floor with non-positive profit for BANKRUPTCY_TURNS
##     turns running (never recovering above the floor OR into profit), the company
##     goes bankrupt: the game ends and the game-over screen takes over.
##
## Interactive-only: gated off in headless so the e2e balance harness is never
## perturbed (it has RunMetrics for observability and must keep driving turns).

const GameOverPanel := preload("res://scripts/game_over_panel.gd")
const BuildingPrice := preload("res://scripts/building_price.gd")

const DISTRESS_FLOOR := -500.0        # cash level that arms the program / bankruptcy clock
const BANKRUPTCY_TURNS := 5           # consecutive floor+unprofitable turns → bankruptcy
const DISTRESSED_BUYOUT_MULT := 1.5   # investors buy your buildings at 1.5x sale value
const DISTRESSED_LOAN := 500.0        # the rescue loan principal
const DISTRESSED_GRACE_TURNS := 10    # interest-free turns before it amortises normally
const HISTORY_CAP := 320              # >= MAX_TURNS, so a whole run fits

# Tutorial kindness: a learner who ends turns while reading must not be able to lose the
# lesson to arithmetic. Three top-ups, escalating in tone, then the training wheels come
# off for real. See docs/early-game-onboarding-spec.md §3.
const TUTORIAL_RESCUE_CASH := 2500.0
const TUTORIAL_RESCUE_LIMIT := 3
const TUTORIAL_RESCUE_TITLES: Array[String] = [
	"The tutorial is feeling kind",
	"You're testing the tutorial's kindness",
	"Last chance. Don't waste it",
]
const TUTORIAL_RESCUE_BODIES: Array[String] = [
	"Your balance went below zero, so the books have been topped back up to £%s. Running a factory costs money every turn before it earns any.",
	"Below zero again — topped back up to £%s. There are only so many of these.",
	"Topped up to £%s for the last time; the next red balance stands. Check what your factory buys each turn, and get its output sold.",
]

signal bankruptcy_declared()
signal tutorial_rescued(count: int)

var enabled: bool = false
var history: Array = []                # [{turn, money, profit, empire_value, output_value}]
var _bad_streak: int = 0
var _distressed_offered: bool = false
var _bankrupt: bool = false
var _tutorial_rescues: int = 0
var _last_summary: Dictionary = {}
var _panel: Control = null
var _panel_layer: CanvasLayer = null


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	await get_tree().process_frame
	if Production.has_signal("turn_processed"):
		Production.turn_processed.connect(_on_turn_processed)
	TurnManager.turn_resolution_completed.connect(_on_turn_resolution_completed)
	MatchState.state_reset.connect(reset)

func reset() -> void:
	history.clear()
	_bad_streak = 0
	_distressed_offered = false
	_bankrupt = false
	_tutorial_rescues = 0
	_last_summary = {}
	_close_panel()

func is_bankrupt() -> bool:
	return _bankrupt


# --- Per-turn snapshot + evaluation --------------------------------------------------

func _on_turn_processed(summary: Dictionary) -> void:
	_last_summary = summary

func _on_turn_resolution_completed() -> void:
	if _bankrupt:
		return
	# Tutorial kindness runs FIRST — before the bridge loan, so a learner is topped up
	# instead of taking on debt — and outside the headless gate below, so the suite can
	# drive it. It is a no-op in every non-tutorial match.
	_tutorial_rescue_if_needed()
	if not enabled:
		return
	# Negative at the end of the turn → auto-borrow (against remaining capacity) to
	# bridge back toward £0, and tell the player. If capacity can't cover the gap the
	# balance stays red and the bankruptcy clock below starts ticking.
	_auto_bridge_negative_cash()
	var turn: int = maxi(1, int(TurnManager.current_turn) - 1)
	var money: float = float(MatchState.money)
	var profit: float = _post_tax_profit(_last_summary)
	var point := {
		"turn": turn,
		"money": money,
		"profit": profit,
		"empire_value": _empire_sale_value(),
		"output_value": _output_market_value(_last_summary),
	}
	history.append(point)
	while history.size() > HISTORY_CAP:
		history.pop_front()
	_last_summary = {}
	_evaluate(money, profit)

func _evaluate(money: float, profit: float) -> void:
	# First touch of the floor with a CFO seated → the CFO proposes the program.
	if money <= DISTRESS_FLOOR and not _distressed_offered and _cfo_seated():
		if DecisionState.force_draw("distressed_asset") == "":
			_distressed_offered = true
	# Bankruptcy clock: a "bad" turn is at/below the floor AND not in profit. Any
	# recovery (above the floor OR positive profit) resets it.
	if money <= DISTRESS_FLOOR and profit <= 0.0:
		_bad_streak += 1
	else:
		_bad_streak = 0
	if _bad_streak >= BANKRUPTCY_TURNS:
		_declare_bankruptcy()

func _cfo_seated() -> bool:
	return MatchState.get_advisor_in_seat("cfo") != ""


# --- Tutorial rescue -----------------------------------------------------------------

## How many times this tutorial run has been bailed out (telemetry reads this).
func tutorial_rescues() -> int:
	return _tutorial_rescues

## Tutorial matches only: a negative balance is topped back up to TUTORIAL_RESCUE_CASH,
## TUTORIAL_RESCUE_LIMIT times, with escalating copy. After the last one the balance is
## allowed to go red and bankruptcy can genuinely fire — the stakes are part of the lesson.
func _tutorial_rescue_if_needed() -> void:
	if not bool(MatchState.ruleset.get("tutorial_enabled", false)):
		return
	if _tutorial_rescues >= TUTORIAL_RESCUE_LIMIT or float(MatchState.money) >= 0.0:
		return
	_tutorial_rescues += 1
	# add_money (not a direct write) so money_changed fires and the HUD follows.
	MatchState.add_money(TUTORIAL_RESCUE_CASH - float(MatchState.money))
	var title: String = TUTORIAL_RESCUE_TITLES[_tutorial_rescues - 1]
	var body: String = TUTORIAL_RESCUE_BODIES[_tutorial_rescues - 1] % ("%.0f" % TUTORIAL_RESCUE_CASH)
	print("[Solvency] tutorial rescue %d/%d → £%.0f" % [_tutorial_rescues, TUTORIAL_RESCUE_LIMIT, TUTORIAL_RESCUE_CASH])
	tutorial_rescued.emit(_tutorial_rescues)
	if enabled:
		# Same one-source-of-truth shape the bridge loan uses: a toast now, and a bell
		# item that survives being missed. Non-blocking, so the coach's step machine
		# is never interrupted mid-lesson.
		MatchState.request_toast("%s — topped up to £%.0f." % [title, TUTORIAL_RESCUE_CASH], "info")
		EventScheduler.emit_event({
			"kind": "tutorial_rescue",
			"severity": "info",
			"title": title,
			"body": body,
			"source": "solvency",
			"persistent": false,
			"auto_dismiss_turns": 3,
		})


# --- Auto-bridge loan (keep the balance non-negative while capacity allows) -----------

## Borrow up to available capacity to lift a negative balance toward £0. Returns the
## amount borrowed (0 if solvent or out of capacity). Shows the bridge popup on success.
func auto_bridge_amount() -> float:
	var money: float = float(MatchState.money)
	if money >= 0.0:
		return 0.0
	var gap: float = -money
	var amount: float = minf(gap, LoanState.available_capacity())
	if amount < 1.0:
		return 0.0   # no borrowing room left — heading for bankruptcy
	return amount

func _auto_bridge_negative_cash() -> void:
	var amount: float = auto_bridge_amount()
	if amount < 1.0:
		return
	if not LoanState.take_loan(amount):
		return
	var capacity_left: float = LoanState.available_capacity()
	print("[Solvency] auto-bridge loan of £%.0f (capacity left £%.0f)" % [amount, capacity_left])
	# Surfaces as a Turn Briefing info item (the standalone popup is retired) and in
	# the bell — same event, one source of truth.
	if enabled:
		# Red toast in the bottom-centre warning stack — lands directly under the
		# "Cash is in the red" toast that fired earlier this turn.
		MatchState.request_toast(
			"Loan taken to cover the deficit: £%.0f, £%.0f loan capacity left." % [amount, capacity_left],
			"warning")
		EventScheduler.emit_event({
			"kind": "bridge_loan",
			"severity": "info",
			"title": "Bridge loan taken — £%.0f" % amount,
			"body": "Your balance went into the red, so £%.0f was borrowed automatically to bridge you until next turn. Loan capacity left: £%.0f." % [amount, capacity_left],
			"source": "solvency",
			"persistent": false,
			"auto_dismiss_turns": 3,
		})


# --- Distressed Asset Program (the DecisionState "accept" effect calls this) ----------

## Investors buy every building at 1.5x sale value, and a £500 grace loan lands
## (interest-free for 10 turns, then normal). Returns a summary for the toast/log.
func accept_distressed_program() -> Dictionary:
	var res: Dictionary = MatchState.liquidate_all_buildings(DISTRESSED_BUYOUT_MULT)
	LoanState.take_grace_loan(DISTRESSED_LOAN, DISTRESSED_GRACE_TURNS)
	_bad_streak = 0   # the cash injection is the escape
	return res


# --- Bankruptcy end-state ------------------------------------------------------------

func _declare_bankruptcy() -> void:
	if _bankrupt:
		return
	_bankrupt = true
	TurnManager.game_ended = true
	bankruptcy_declared.emit()
	# Fire the run-metrics roll-up the same way the turn-cap end does.
	if TurnManager.has_signal("game_ended_signal"):
		TurnManager.game_ended_signal.emit("bankruptcy")
	_show_panel()

func _show_panel() -> void:
	if not enabled or _panel != null:
		return
	print("[Solvency] bankruptcy game-over panel mounting")
	_panel_layer = CanvasLayer.new()
	_panel_layer.layer = 200   # above every other overlay
	add_child(_panel_layer)
	_panel = GameOverPanel.new()
	_panel_layer.add_child(_panel)
	_panel.open(history)

func _close_panel() -> void:
	if _panel_layer != null and is_instance_valid(_panel_layer):
		_panel_layer.queue_free()
	_panel = null
	_panel_layer = null

## Called by the game-over panel's "Return to Main Menu": tear down the (autoload-
## owned) game-over layer, then change scene, so the overlay doesn't survive.
func return_to_main_menu(menu_scene: String) -> void:
	_close_panel()
	get_tree().change_scene_to_file(menu_scene)

## Debug/test entry: force the end-state now (the `bankrupt` cheat).
func force_bankruptcy() -> void:
	_declare_bankruptcy()


# --- Financial helpers ---------------------------------------------------------------

# Post-tax profit for the turn, mirroring RunMetrics' definition off the summary dict.
func _post_tax_profit(summary: Dictionary) -> float:
	if summary.is_empty():
		return 0.0
	var money_in: float = float(summary.get("money_in", 0.0))
	var money_out: float = float(summary.get("money_out", 0.0))
	var taxes: float = float(summary.get("taxes_paid", 0.0))
	var dividends: float = float(summary.get("dividends_paid", 0.0))
	var sharing: float = float(summary.get("profit_sharing_paid", 0.0))
	var pre_tax: float = money_in - (money_out - taxes - dividends - sharing)
	return pre_tax - taxes - dividends - sharing

# Empire value = what every player building would sell for right now.
func _empire_sale_value() -> float:
	var total: float = 0.0
	for b in MatchState.buildings.values():
		if MatchState.is_player_owned(b):
			total += float(BuildingPrice.sale_price(b))
	return total

# Output value = this turn's produced goods valued at market price.
func _output_market_value(summary: Dictionary) -> float:
	var total: float = 0.0
	for gid in (summary.get("produced", {}) as Dictionary):
		total += float(int(summary.produced[gid])) * MarketState.get_price(str(gid))
	return total


# --- Save / load (additive key; tolerant reader, no version bump) --------------------

func export_state() -> Dictionary:
	return {
		"history": history.duplicate(true),
		"bad_streak": _bad_streak,
		"distressed_offered": _distressed_offered,
		"bankrupt": _bankrupt,
		"tutorial_rescues": _tutorial_rescues,
	}

func import_state(d: Dictionary) -> void:
	history = (d.get("history", []) as Array).duplicate(true)
	_bad_streak = int(d.get("bad_streak", 0))
	_distressed_offered = bool(d.get("distressed_offered", false))
	_bankrupt = bool(d.get("bankrupt", false))
	# Tolerant reader: saves from before the rescue existed start the learner at zero.
	_tutorial_rescues = int(d.get("tutorial_rescues", 0))
	if _bankrupt and enabled:
		_show_panel()
