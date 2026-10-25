extends RefCounted
## Staffing (docs/pacing-labour-mining-licensing-spec.md §5). A player building or construction project carries
## `staff_fill`: the hired share of the headcount it is hiring for. That is the level it runs at, or the level an
## upgrade is taking it to (`staff_level`). Fill starts when construction begins, rises each turn at the pace
## labour satisfaction sets (LabourState.fill_turns), and the building runs once 70% are hired, at a fraction
## equal to its fill. A building without the key is fully staffed: starting buildings, NPC buildings and
## anything saved before staffing existed. The key is dropped again once the hiring is done.
##
## Consumers `preload` this as `const Staffing`.

const BuildingLevels := preload("res://scripts/building_levels.gd")

## A building runs once this share of its staff is hired, at a run fraction equal to its fill.
const OPERATE_AT := 0.70
## The fill a bought building arrives with, and with satisfaction below −5 at closing.
const BOUGHT_FILL := 0.8
const BOUGHT_FILL_SLOW := 0.5
## The fill a new site starts with while Andrew Keeler is Expansion Director.
const EXPANSION_START_FILL := 0.5
const _EPS := 0.0001


## The hired share of the headcount being hired for, 0..1.
static func fill(b: Dictionary) -> float:
	return clampf(float(b.get("staff_fill", 1.0)), 0.0, 1.0)


## Still hiring: a fill below 1.
static func is_hiring(b: Dictionary) -> bool:
	return b.has("staff_fill") and fill(b) < 1.0 - _EPS


## The level the fill is measured against: the operating level, or an upgrade's target while its works run.
static func staff_level(b: Dictionary) -> int:
	return int(b.get("staff_level", b.get("level", 1)))


static func _heads(level: int) -> float:
	return BuildingLevels.mult("labour", level)


## The workforce on the payroll as a share of the operating level's headcount. Above 1 while an upgrade hires
## for the larger works ahead of the new level. Labour is charged on it (§5 Wages).
static func hired_share(b: Dictionary) -> float:
	if not b.has("staff_fill"):
		return 1.0
	return fill(b) * _heads(staff_level(b)) / _heads(int(b.get("level", 1)))


## How hard the staff let the building run this turn: 0 below 70% of its headcount, else the share hired, at
## most 1. After an upgrade, never below the previous level's output while the new hires arrive.
static func run_fraction(b: Dictionary) -> float:
	if not b.has("staff_fill"):
		return 1.0
	var level := int(b.get("level", 1))
	var crew := minf(1.0, hired_share(b))
	var run := crew if crew >= OPERATE_AT - _EPS else 0.0
	var prev := int(b.get("staff_prev_level", level))
	if prev < level:
		var prev_crew := minf(1.0, fill(b) * _heads(staff_level(b)) / _heads(prev))
		if prev_crew >= OPERATE_AT - _EPS:
			run = maxf(run, prev_crew * BuildingLevels.mult("output", prev) / BuildingLevels.mult("output", level))
	return run


## Too few staff to run at all.
static func is_waiting(b: Dictionary) -> bool:
	return run_fraction(b) <= 0.0


## One turn's hiring: 1 / the fill turns the current satisfaction band sets (5, 8 or 12).
static func fill_step() -> float:
	return 1.0 / float(maxi(1, LabourState.fill_turns()))


## The fill a new construction project starts with: 0, or half while the Expansion Director sits.
static func start_fill() -> float:
	return EXPANSION_START_FILL if AdvisorState.expansion_director_active() else 0.0


## The fill a bought building arrives with at closing: 0.8, or 0.5 with satisfaction below −5.
static func bought_fill() -> float:
	return BOUGHT_FILL_SLOW if LabourState.satisfaction < LabourState.BAND_SLOW_BELOW else BOUGHT_FILL


## One turn of hiring on a building or project dict. Once fully staffed at its own level the keys go.
static func tick(b: Dictionary) -> void:
	if not b.has("staff_fill"):
		return
	if fill(b) < 1.0 - _EPS:
		b["staff_fill"] = minf(1.0, fill(b) + fill_step())
	if fill(b) >= 1.0 - _EPS:
		b.erase("staff_prev_level")
		if staff_level(b) == int(b.get("level", 1)):
			b.erase("staff_fill")
			b.erase("staff_level")
		else:
			b["staff_fill"] = 1.0


## An upgrade's works began: the hires so far count against `target`'s larger headcount, and hiring goes on.
static func begin_upgrade(b: Dictionary, target: int) -> void:
	var level := int(b.get("level", 1))
	if target <= level:
		return
	b["staff_fill"] = fill(b) * _heads(staff_level(b)) / _heads(target)
	b["staff_level"] = target
	b["staff_prev_level"] = level


## The upgrade's works were abandoned: the fill counts against the operating level again.
static func cancel_upgrade(b: Dictionary) -> void:
	if not b.has("staff_level"):
		return
	var level := int(b.get("level", 1))
	b["staff_fill"] = minf(1.0, fill(b) * _heads(staff_level(b)) / _heads(level))
	b.erase("staff_level")
	b.erase("staff_prev_level")
	if fill(b) >= 1.0 - _EPS:
		b.erase("staff_fill")


## The upgrade finished: the building now runs at the level its staff were hired for.
static func finish_upgrade(b: Dictionary) -> void:
	if staff_level(b) == int(b.get("level", 1)):
		b.erase("staff_level")
	if not is_hiring(b):
		b.erase("staff_fill")
		b.erase("staff_prev_level")


## Turns from construction start until a new site can run (70% hired) at today's hiring pace: 6 at
## normal satisfaction, 4 when content, 9 when unhappy, 2 with the Expansion Director (§7.7).
static func turns_to_operate(start: float = -1.0) -> int:
	var s := start_fill() if start < 0.0 else start
	return ceili(maxf(0.0, OPERATE_AT - s) / fill_step() - _EPS)


## Whole turns until fill reaches `share` at the current pace (0 when already there).
static func turns_to(b: Dictionary, share: float) -> int:
	var gap := share - fill(b)
	if gap <= _EPS:
		return 0
	return ceili(gap / fill_step() - _EPS)


## The diagnostics line: "Staffed 64%. Starts at 70%." below 70%, "Staffed 85%. Runs at 85%." above it.
static func status_text(b: Dictionary) -> String:
	var hired := roundi(fill(b) * 100.0)
	if is_waiting(b):
		return "Staffed %d%%. Starts at %d%%." % [hired, roundi(OPERATE_AT * 100.0)]
	return "Staffed %d%%. Runs at %d%%." % [hired, roundi(run_fraction(b) * 100.0)]
