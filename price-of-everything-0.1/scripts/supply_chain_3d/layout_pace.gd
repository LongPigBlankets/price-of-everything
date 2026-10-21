extends RefCounted
## Spreads a long layout solve over frames, so a company rebuild never holds the game still.
## A pass calls `await Pace.step(pace)` between units of work: it returns at once until the
## frame's slice is spent, then waits for the next frame. When the build that owns the pace is
## superseded, `stopped` turns true and the passes return early; their work is thrown away and
## never memoised. Offline bakes and tests pass no pace and run straight through.

## Main-thread time a solve may take in one frame.
const BUDGET_USEC := 6000

## This pace's slice; a test can shrink it to yield at every step.
var budget_usec := BUDGET_USEC
var stopped := false
## Frames the solve was spread over.
var frames := 0
## The longest slice actually run, in microseconds: a single unit of work can overrun the budget.
var longest_usec := 0
var _tree: SceneTree
var _alive: Callable
var _since := 0

func _init(tree: SceneTree, alive: Callable = Callable()) -> void:
	_tree = tree
	_alive = alive
	_since = Time.get_ticks_usec()

## Yields a frame when this frame's slice is spent. A null pace never yields.
static func step(pace: RefCounted) -> void:
	if pace == null or pace.stopped: return
	var spent: int = Time.get_ticks_usec() - pace._since
	if spent < pace.budget_usec: return
	pace.longest_usec = maxi(pace.longest_usec, spent)
	await pace._tree.process_frame
	pace.frames += 1
	pace._since = Time.get_ticks_usec()
	if pace._alive.is_valid() and not pace._alive.call(): pace.stopped = true

## True once the owner has given the solve up.
static func gave_up(pace: RefCounted) -> bool:
	return pace != null and pace.stopped
