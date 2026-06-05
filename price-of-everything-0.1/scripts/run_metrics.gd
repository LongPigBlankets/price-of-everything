extends Node
# RunMetrics: per-turn strategy/economy observability.
#
# Each turn this autoload captures the numbers needed to judge whether a coded
# strategy is economically viable — financial (cash, equity, revenue, the full
# cost breakdown, pre/post-tax profit), operational (building/starvation counts,
# units produced & consumed), solvency (cash low-water mark, turns in the red,
# debt/equity, a bankrupt flag) and the easy-to-miss "silent leaks" (goods lost
# to stockpile capacity caps). One row per turn is appended to
#   user://run_metrics.csv
# and a whole-run roll-up is written to
#   user://run_metrics_summary.json
# when the run finishes (finish_run(), or TurnManager.game_ended_signal).
#
# Everything is gated behind `enabled` (default true). When disabled the autoload
# does nothing and has zero effect on game behaviour.
#
# Data sources (all autoloads): MatchState (money, buildings), Stockpile
# (per-tile good totals + the capacity-loss counter), MarketState (prices),
# LoanState (debt), Catalog (building/good valuation), Production
# (turn_processed summary + building_starved), TurnManager (turn signals).

const CSV_PATH := "user://run_metrics.csv"
const SUMMARY_PATH := "user://run_metrics_summary.json"

# Stable CSV column order. Append-only: never reorder/remove a column once shipped.
const COLUMNS: Array[String] = [
	"turn",
	# Financial
	"cash",
	"equity",
	"stockpile_value",
	"building_value",
	"debt",
	"revenue",
	"cost_input_buys",
	"cost_transport",
	"cost_maintenance",
	"cost_labour",
	"cost_interest",
	"cost_taxes",
	"cost_dividends",
	"cost_grid_power",
	"cost_build_land",
	"profit_pre_tax",
	"profit_post_tax",
	# Operational
	"building_count",
	"starved_count",
	"most_missing_input",
	"units_produced",
	"units_consumed",
	# Silent leaks
	"capacity_lost",
	# Solvency
	"cash_low_water",
	"turns_cash_negative",
	"debt_to_equity",
	"bankrupt",
]

@export var enabled: bool = true

# --- Per-run accumulators ---
var _row_count: int = 0
var _header_written: bool = false
var _last_summary: Dictionary = {}            # latest Production.turn_processed payload
var _starved_buffer: Array = []               # building_starved records since the last row
var _seen_first_turn: bool = false

# Solvency / roll-up state
var _cash_low_water: float = INF
var _turns_cash_negative: int = 0
var _peak_equity: float = -INF
var _final_equity: float = 0.0
var _final_cash: float = 0.0
var _max_equity_drawdown: float = 0.0         # largest peak-to-trough drop in equity
var _equity_peak_so_far: float = -INF
var _first_positive_profit_turn: int = -1     # time-to-first-positive-profit (-1 = never)
var _total_produced: int = 0
var _turns_survived: int = 0
var _bankrupt: bool = false
var _summary_written: bool = false


func _ready() -> void:
	if not enabled:
		return
	# Autoloads come up before the scene tree settles; wait a frame so the other
	# singletons (Production, TurnManager, MarketState, ...) have run their _ready.
	await get_tree().process_frame
	_connect_signals()
	_reset_run_state()
	print("[RunMetrics] ready (enabled). Logging to %s" % CSV_PATH)


func _connect_signals() -> void:
	if Production and Production.has_signal("turn_processed"):
		if not Production.turn_processed.is_connected(_on_turn_processed):
			Production.turn_processed.connect(_on_turn_processed)
	if Production and Production.has_signal("building_starved"):
		if not Production.building_starved.is_connected(_on_building_starved):
			Production.building_starved.connect(_on_building_starved)
	if TurnManager and TurnManager.has_signal("turn_resolution_completed"):
		if not TurnManager.turn_resolution_completed.is_connected(_on_turn_resolution_completed):
			TurnManager.turn_resolution_completed.connect(_on_turn_resolution_completed)
	if TurnManager and TurnManager.has_signal("game_ended_signal"):
		if not TurnManager.game_ended_signal.is_connected(_on_game_ended):
			TurnManager.game_ended_signal.connect(_on_game_ended)


func _reset_run_state() -> void:
	_row_count = 0
	_header_written = false
	_last_summary = {}
	_starved_buffer = []
	_seen_first_turn = false
	_cash_low_water = INF
	_turns_cash_negative = 0
	_peak_equity = -INF
	_final_equity = 0.0
	_final_cash = 0.0
	_max_equity_drawdown = 0.0
	_equity_peak_so_far = -INF
	_first_positive_profit_turn = -1
	_total_produced = 0
	_turns_survived = 0
	_bankrupt = false
	_summary_written = false


# === Signal handlers ===

func _on_building_starved(record: Dictionary) -> void:
	# Emitted once per starved building during PROCESS, before turn_processed.
	if not enabled:
		return
	_starved_buffer.append(record)


func _on_turn_processed(summary: Dictionary) -> void:
	# The authoritative per-turn economics dict, emitted at the end of PROCESS.
	if not enabled:
		return
	_last_summary = summary


func _on_turn_resolution_completed() -> void:
	# Fires once per turn after PROCESS (and after current_turn has advanced).
	# This is where we snapshot a CSV row, so equity uses post-turn cash + prices.
	if not enabled:
		return
	if _last_summary.is_empty():
		# No production summary yet this turn (shouldn't happen in normal play) —
		# skip rather than write a misleading all-zero row.
		_starved_buffer.clear()
		return
	_capture_row()
	# Consume per-turn buffers so the next turn starts clean.
	_last_summary = {}
	_starved_buffer.clear()


func _on_game_ended(_reason: String) -> void:
	finish_run()


# === Per-turn capture ===

func _capture_row() -> void:
	var turn: int = _metrics_turn()
	var summary: Dictionary = _last_summary

	# --- Financial ---
	var cash: float = float(MatchState.money)
	var stockpile_value: float = _stockpile_value()
	var building_value: float = _building_value()
	var debt: float = _debt()
	var equity: float = cash + stockpile_value + building_value - debt

	var revenue: float = float(summary.get("goods_sales_revenue", 0.0)) \
		+ float(summary.get("power_sales_revenue", 0.0))

	var cost_input_buys: float = float(summary.get("goods_purchased_cost", 0.0))
	var cost_transport: float = float(summary.get("transport_paid", 0.0))
	var cost_maintenance: float = float(summary.get("maintenance_paid", 0.0))
	var cost_labour: float = float(summary.get("labour_paid", 0.0))
	var cost_interest: float = float(summary.get("interest_paid", 0.0))
	var cost_taxes: float = float(summary.get("taxes_paid", 0.0))
	var cost_dividends: float = float(summary.get("dividends_paid", 0.0))
	var cost_grid_power: float = float(summary.get("power_purchase_cost", 0.0))
	# Build/land spend isn't broken out of the production summary; surface it as 0
	# here (it is captured in cash directly) so the column stays stable for later.
	var cost_build_land: float = float(summary.get("build_land_cost", 0.0))

	# Pre-tax profit mirrors Production's own definition (operating profit - interest).
	var operating_costs: float = cost_maintenance + cost_labour + cost_grid_power + cost_transport
	var profit_pre_tax: float = revenue - operating_costs - cost_interest
	var profit_post_tax: float = profit_pre_tax - cost_taxes - cost_dividends

	# --- Operational ---
	var building_count: int = MatchState.buildings.size()
	var starved_records: Array = _starved_records(summary)
	var starved_count: int = starved_records.size()
	var most_missing_input: String = _most_missing_input(starved_records)
	var units_produced: int = _sum_int_values(summary.get("produced", {}))
	var units_consumed: int = _sum_int_values(summary.get("consumed", {}))

	# --- Silent leaks ---
	var capacity_lost: int = 0
	if Stockpile and Stockpile.has_method("get_capacity_lost_this_turn"):
		capacity_lost = int(Stockpile.get_capacity_lost_this_turn())
		Stockpile.reset_capacity_lost_this_turn()

	# --- Solvency ---
	if cash < _cash_low_water:
		_cash_low_water = cash
	if cash < 0.0:
		_turns_cash_negative += 1
	var bankrupt: bool = cash < 0.0
	if bankrupt:
		_bankrupt = true
	var debt_to_equity: float = (debt / equity) if absf(equity) > 0.0001 else 0.0

	# --- Roll-up tracking ---
	_total_produced += units_produced
	_turns_survived = turn
	_final_cash = cash
	_final_equity = equity
	if equity > _peak_equity:
		_peak_equity = equity
	if equity > _equity_peak_so_far:
		_equity_peak_so_far = equity
	var drawdown: float = _equity_peak_so_far - equity
	if drawdown > _max_equity_drawdown:
		_max_equity_drawdown = drawdown
	if _first_positive_profit_turn < 0 and profit_post_tax > 0.0:
		_first_positive_profit_turn = turn

	# --- Write the row ---
	var row: Dictionary = {
		"turn": turn,
		"cash": cash,
		"equity": equity,
		"stockpile_value": stockpile_value,
		"building_value": building_value,
		"debt": debt,
		"revenue": revenue,
		"cost_input_buys": cost_input_buys,
		"cost_transport": cost_transport,
		"cost_maintenance": cost_maintenance,
		"cost_labour": cost_labour,
		"cost_interest": cost_interest,
		"cost_taxes": cost_taxes,
		"cost_dividends": cost_dividends,
		"cost_grid_power": cost_grid_power,
		"cost_build_land": cost_build_land,
		"profit_pre_tax": profit_pre_tax,
		"profit_post_tax": profit_post_tax,
		"building_count": building_count,
		"starved_count": starved_count,
		"most_missing_input": most_missing_input,
		"units_produced": units_produced,
		"units_consumed": units_consumed,
		"capacity_lost": capacity_lost,
		"cash_low_water": _cash_low_water,
		"turns_cash_negative": _turns_cash_negative,
		"debt_to_equity": debt_to_equity,
		"bankrupt": bankrupt,
	}
	_append_row(row)


# === Valuation helpers ===

func _stockpile_value() -> float:
	# Σ over every tile of (units of a good × its current market price).
	var total: float = 0.0
	if Stockpile == null:
		return 0.0
	var totals: Dictionary = Stockpile.get_all_totals()
	for good_id in totals.keys():
		var qty: int = int(totals[good_id])
		if qty <= 0:
			continue
		total += float(qty) * MarketState.get_price(str(good_id))
	return total

func _building_value() -> float:
	# Σ over placed player buildings of their build cost (base_price proxy).
	var total: float = 0.0
	for inst in MatchState.buildings.values():
		if not MatchState.is_player_owned(inst):
			continue
		var bd: Dictionary = Catalog.get_building(str(inst.get("building_id", "")))
		total += float(bd.get("base_price", 0.0))
	return total

func _debt() -> float:
	if LoanState and LoanState.has_method("total_outstanding"):
		return float(LoanState.total_outstanding())
	return 0.0


# === Operational helpers ===

func _starved_records(summary: Dictionary) -> Array:
	# Prefer the per-turn building_starved signal buffer; fall back to summary.starved.
	if not _starved_buffer.is_empty():
		return _starved_buffer
	return summary.get("starved", [])

func _most_missing_input(starved_records: Array) -> String:
	# The input good most often cited as missing across starved buildings this turn.
	var counts: Dictionary = {}
	for rec in starved_records:
		for m in rec.get("missing", []):
			var name: String = str(m.get("internal_name", m.get("good_id", "")))
			if name == "":
				continue
			counts[name] = int(counts.get(name, 0)) + 1
	var best_name: String = ""
	var best_count: int = 0
	for name in counts.keys():
		if int(counts[name]) > best_count:
			best_count = int(counts[name])
			best_name = str(name)
	return best_name

func _sum_int_values(d: Dictionary) -> int:
	var total: int = 0
	for v in d.values():
		total += int(v)
	return total

func _metrics_turn() -> int:
	# At turn_resolution_completed the counter has already advanced past the turn
	# we just resolved, so the resolved turn is current_turn - 1 (>= 1).
	if TurnManager == null:
		return _row_count + 1
	return maxi(1, int(TurnManager.current_turn) - 1)


# === CSV writing ===

func _append_row(row: Dictionary) -> void:
	var f: FileAccess
	if not _header_written and not FileAccess.file_exists(CSV_PATH):
		# Fresh file: create + write the header.
		f = FileAccess.open(CSV_PATH, FileAccess.WRITE)
		if f == null:
			push_warning("[RunMetrics] cannot open %s for writing" % CSV_PATH)
			return
		f.store_line(",".join(COLUMNS))
		_header_written = true
	else:
		# Append to the existing file.
		f = FileAccess.open(CSV_PATH, FileAccess.READ_WRITE)
		if f == null:
			# File vanished between checks — recreate with a header.
			f = FileAccess.open(CSV_PATH, FileAccess.WRITE)
			if f == null:
				push_warning("[RunMetrics] cannot open %s for writing" % CSV_PATH)
				return
			f.store_line(",".join(COLUMNS))
		_header_written = true
		f.seek_end()
	var cells: Array[String] = []
	for col in COLUMNS:
		cells.append(_format_cell(row.get(col, "")))
	f.store_line(",".join(cells))
	f.close()
	_row_count += 1

func _format_cell(value) -> String:
	if value is bool:
		return "1" if value else "0"
	if value is float:
		# Compact, deterministic, locale-independent.
		return "%.4f" % value
	if value is int:
		return str(value)
	var s := str(value)
	# Escape any comma/quote so the CSV stays well-formed.
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"" + s.replace("\"", "\"\"") + "\""
	return s


# === Public API ===

## Truncate the CSV and reset all run state — call before a fresh run if the
## process is reused. A fresh `--script`/scene launch does not need this.
func reset() -> void:
	if not enabled:
		return
	if FileAccess.file_exists(CSV_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CSV_PATH))
	_reset_run_state()

## Write the per-run roll-up to user://run_metrics_summary.json. Idempotent within
## a run (guarded by _summary_written); the sim calls this explicitly, and
## game_ended_signal calls it automatically.
func finish_run() -> Dictionary:
	if not enabled:
		return {}
	if _summary_written:
		return _last_run_summary()
	var data: Dictionary = _last_run_summary()
	var f := FileAccess.open(SUMMARY_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "\t"))
		f.close()
		print("[RunMetrics] run summary written to %s" % SUMMARY_PATH)
	else:
		push_warning("[RunMetrics] cannot write %s" % SUMMARY_PATH)
	_summary_written = true
	return data

func _last_run_summary() -> Dictionary:
	return {
		"peak_equity": _peak_equity if _peak_equity != -INF else 0.0,
		"final_equity": _final_equity,
		"final_cash": _final_cash,
		"time_to_first_positive_profit": _first_positive_profit_turn,
		"max_drawdown": _max_equity_drawdown,
		"turns_survived": _turns_survived,
		"total_produced": _total_produced,
		"cash_low_water": _cash_low_water if _cash_low_water != INF else 0.0,
		"turns_cash_negative": _turns_cash_negative,
		"bankrupt": _bankrupt,
		"rows_logged": _row_count,
	}

## Read every logged CSV row back as an Array of Dictionaries (header-keyed).
## Handy for the validation sim's assertions and for tests.
func read_rows() -> Array:
	var rows: Array = []
	if not FileAccess.file_exists(CSV_PATH):
		return rows
	var f := FileAccess.open(CSV_PATH, FileAccess.READ)
	if f == null:
		return rows
	var header: PackedStringArray = f.get_csv_line()
	while not f.eof_reached():
		var line: PackedStringArray = f.get_csv_line()
		if line.size() < header.size() or (line.size() == 1 and line[0] == ""):
			continue
		var row: Dictionary = {}
		for i in header.size():
			row[header[i]] = line[i] if i < line.size() else ""
		rows.append(row)
	f.close()
	return rows
