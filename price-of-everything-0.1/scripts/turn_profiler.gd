extends Node

## Autoload: TurnProfiler
## Turn-stage duration observability. Times each turn-manager resolution phase
## (excluding DECIDE) and the sub-steps of Production._process_production, and
## logs per-turn timings to the console + a CSV.
##
## Owns: turn_profiler.gd, turn_manager.gd (phase brackets),
## production.gd (sub-step brackets).
##
## API (all calls are cheap no-ops when `enabled == false`, with ZERO behaviour
## change — they never throw and never touch game state):
##   phase_begin(phase) / phase_end(phase)      — TurnManager, around each emit
##   section_begin(name) / section_end(name)    — Production, around each sub-step
##   finalize_turn(turn)                          — flush one CSV row + console line
##
## Timing source: Time.get_ticks_usec() (monotonic microseconds).

# Master switch. When false every public method returns immediately.
var enabled: bool = true

const CSV_PATH := "user://turn_profile.csv"

# Stable column order for the CSV + console. Phases first (excluding DECIDE),
# then the PROCESS sub-steps in execution order, then scale counts.
const PHASE_COLUMNS: Array[String] = [
	"PROCESS", "SEND", "AI", "NARRATIVE", "RECEIVE",
]
const SECTION_COLUMNS: Array[String] = [
	"power_reset",
	"transport_arrivals",
	"production_passes",
	"starvation_report",
	"grid_settlement",
	"flush_outputs",
	"recurring_moves",
	"buy_market_inputs",
	"sell_phase",
	"maintenance_labour",
	"loan_payments",
	"tax_dividends",
	"cost_solve",
	"emit_summary",
]
const SCALE_COLUMNS: Array[String] = [
	"buildings", "pending_shipments", "production_passes",
]

# Accumulated microseconds for the current turn.
var _phase_us: Dictionary = {}      # phase-name -> usec
var _section_us: Dictionary = {}    # section-name -> usec
var _scale: Dictionary = {}         # scale-name -> int

# Open bracket start timestamps (so begin/end can be re-entrant-safe-ish and
# tolerant of a missing partner without ever throwing).
var _phase_open: Dictionary = {}    # phase-name -> start usec
var _section_open: Dictionary = {}  # section-name -> start usec

var _csv_header_written: bool = false


func _ready() -> void:
	# Detect a pre-existing CSV so we don't double-write the header across runs.
	_csv_header_written = FileAccess.file_exists(CSV_PATH)


# --- Phase timing (called by TurnManager) -----------------------------------

func phase_begin(phase: int) -> void:
	if not enabled:
		return
	var name := _phase_name(phase)
	_phase_open[name] = Time.get_ticks_usec()


func phase_end(phase: int) -> void:
	if not enabled:
		return
	var name := _phase_name(phase)
	if not _phase_open.has(name):
		return
	var elapsed: int = Time.get_ticks_usec() - int(_phase_open[name])
	_phase_us[name] = int(_phase_us.get(name, 0)) + elapsed
	_phase_open.erase(name)


# --- Section timing (called by Production, inside the PROCESS phase) ---------

func section_begin(name: String) -> void:
	if not enabled:
		return
	_section_open[name] = Time.get_ticks_usec()


func section_end(name: String) -> void:
	if not enabled:
		return
	if not _section_open.has(name):
		return
	var elapsed: int = Time.get_ticks_usec() - int(_section_open[name])
	_section_us[name] = int(_section_us.get(name, 0)) + elapsed
	_section_open.erase(name)


# Record a cheap scale count (e.g. "production_passes"). No timing.
func note_scale(name: String, value: int) -> void:
	if not enabled:
		return
	_scale[name] = value


# --- Per-turn finalizer (called by TurnManager after resolution) ------------

func finalize_turn(turn: int) -> void:
	if not enabled:
		return
	# Snapshot a couple of cheap scale counts from game state. Guarded so a
	# missing/odd singleton can never make a timing call throw.
	_capture_scale_counts()

	_log_console(turn)
	_write_csv_row(turn)

	# Reset for the next turn.
	_phase_us.clear()
	_section_us.clear()
	_scale.clear()
	_phase_open.clear()
	_section_open.clear()


# --- Internals --------------------------------------------------------------

func _phase_name(phase: int) -> String:
	# Mirror TurnManager.Phase without depending on its enum being loaded.
	match phase:
		0: return "DECIDE"
		1: return "PROCESS"
		2: return "SEND"
		3: return "AI"
		4: return "NARRATIVE"
		5: return "RECEIVE"
		_: return "PHASE_%d" % phase


func _capture_scale_counts() -> void:
	# All reads are defensive: any failure leaves the count at its existing value.
	var ms := get_node_or_null("/root/MatchState")
	if ms != null:
		var b = ms.get("buildings")
		if b is Dictionary:
			_scale["buildings"] = (b as Dictionary).size()
		var ships = ms.get("pending_transport_shipments")
		if ships is Array:
			_scale["pending_shipments"] = (ships as Array).size()
	# production_passes is fed via note_scale() from Production; default to 0.
	if not _scale.has("production_passes"):
		_scale["production_passes"] = 0


func _us_to_ms(us: int) -> float:
	return float(us) / 1000.0


func _log_console(turn: int) -> void:
	var total_us := 0
	for name in PHASE_COLUMNS:
		total_us += int(_phase_us.get(name, 0))

	var parts: Array[String] = []
	parts.append("turn=%d" % turn)
	parts.append("total=%.2fms" % _us_to_ms(total_us))

	var phase_parts: Array[String] = []
	for name in PHASE_COLUMNS:
		phase_parts.append("%s=%.2f" % [name, _us_to_ms(int(_phase_us.get(name, 0)))])
	parts.append("phases[" + " ".join(phase_parts) + "]")

	var section_parts: Array[String] = []
	for name in SECTION_COLUMNS:
		section_parts.append("%s=%.2f" % [name, _us_to_ms(int(_section_us.get(name, 0)))])
	parts.append("PROCESS{" + " ".join(section_parts) + "}")

	var scale_parts: Array[String] = []
	for name in SCALE_COLUMNS:
		scale_parts.append("%s=%d" % [name, int(_scale.get(name, 0))])
	parts.append("scale[" + " ".join(scale_parts) + "]")

	print("[TurnProfiler] " + " ".join(parts))


func _write_csv_row(turn: int) -> void:
	var existed := FileAccess.file_exists(CSV_PATH)
	# Open in append mode (creates the file if it doesn't exist).
	var f := FileAccess.open(CSV_PATH, FileAccess.READ_WRITE) if existed else FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if f == null:
		# Never let an I/O failure disrupt the turn — just warn once.
		push_warning("[TurnProfiler] Could not open %s for writing (err %d)" % [CSV_PATH, FileAccess.get_open_error()])
		return
	# Seek to end for append.
	f.seek_end()

	if not existed or not _csv_header_written:
		# Only write the header if the file is brand new (empty).
		if f.get_length() == 0:
			f.store_line(_csv_header())
		_csv_header_written = true

	var total_us := 0
	for name in PHASE_COLUMNS:
		total_us += int(_phase_us.get(name, 0))

	var cols: Array[String] = []
	cols.append(str(turn))
	cols.append("%.3f" % _us_to_ms(total_us))
	for name in PHASE_COLUMNS:
		cols.append("%.3f" % _us_to_ms(int(_phase_us.get(name, 0))))
	for name in SECTION_COLUMNS:
		cols.append("%.3f" % _us_to_ms(int(_section_us.get(name, 0))))
	for name in SCALE_COLUMNS:
		cols.append(str(int(_scale.get(name, 0))))

	f.store_line(",".join(cols))
	f.close()


func _csv_header() -> String:
	var cols: Array[String] = []
	cols.append("turn")
	cols.append("total_ms")
	for name in PHASE_COLUMNS:
		cols.append("phase_" + name.to_lower() + "_ms")
	for name in SECTION_COLUMNS:
		cols.append("step_" + name + "_ms")
	for name in SCALE_COLUMNS:
		cols.append("scale_" + name)
	return ",".join(cols)
