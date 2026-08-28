extends RefCounted
## Shared safety harness for the windowed screenshot tools.
##
## EDITOR/DEV ONLY. Every shot tool loads the real `main.tscn`, and that is what makes them
## dangerous: `project.godot` sets `window/size/mode=3` (FULLSCREEN), so a tool run takes the
## WHOLE screen the moment it boots and holds it through a ~30 s world build. On the owner's
## 3440x1440 that reads as the machine having frozen, and it did — twice in one session, once
## taking the desktop with it.
##
## Three rules, all enforced here so no tool has to remember them:
##   1. NEVER fullscreen. The window is forced windowed and small before the world loads.
##   2. NEVER run unbounded. `--quit-after` counts FRAMES, so a slow run can sit there for
##      many minutes; the watchdog is wall-clock and fires regardless of what is stuck.
##   3. Free each captured Image and let a frame pass, so a capture loop cannot pile up
##      full framebuffers.
##
## Deliberately no `class_name` (see `mass_form_shapes.gd`): a fresh global class is missing
## from the headless script-class cache until an --import and fails the suite.
##   const ShotHarness := preload("res://tools/shot_harness.gd")

## The window is sized to the project's BASE VIEWPORT, not to something arbitrarily small.
## The stretch mode is `canvas_items`, so the canvas is scaled by window/base — a 960x720
## window renders the world at half scale and every `--zoom` in every tool's docstring would
## frame ~1.8x more map than it used to. Matching the base keeps that scale exactly 1.0, so
## shots are comparable with every one taken before this harness existed.
##
## The safety property here is WINDOWED, not small: 1920x1080 on a 3440x1440 desktop leaves
## the title bar reachable and the rest of the screen usable, which fullscreen did not.
## Wall-clock ceiling for a whole tool run. Generous — a world build alone is ~30 s — but
## finite, which `--quit-after` in frames is not in any useful sense.
const DEFAULT_TIMEOUT_S := 240.0


## Force the window out of the project's fullscreen default. Call FIRST, before instantiating
## main.tscn: the mode is applied at window creation, so the earlier this runs the smaller the
## window in which the screen is held.
static func prepare_window(win: Window, size: Vector2i = Vector2i.ZERO) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var want := size if size != Vector2i.ZERO else base_viewport()
	# Never larger than the monitor can show, or the window is unusable on a small screen.
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen).size
	win.size = Vector2i(mini(want.x, usable.x - 80), mini(want.y, usable.y - 80))
	# Off the top-left corner so the title bar is reachable if a run does wedge.
	win.position = Vector2i(60, 60)


## The project's configured base viewport, which is the size at which the canvas renders 1:1.
static func base_viewport() -> Vector2i:
	return Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 1920)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))


## Hard wall-clock stop. Fires even if the tool is stuck mid-await, which is exactly the case
## `--quit-after` handles badly: a stalled coroutine still burns frames slowly forever.
static func arm_watchdog(host: Node, seconds: float = DEFAULT_TIMEOUT_S) -> void:
	var tree := host.get_tree()
	if tree == null:
		return
	tree.create_timer(seconds).timeout.connect(func() -> void:
		push_error("shot harness: watchdog fired after %.0f s — quitting rather than hanging."
			% seconds)
		tree.quit(124))


## One capture: draw, read back, crop, write, release. The explicit `null` matters — an Image
## is refcounted, and a loop that keeps the last one alive while taking the next holds two
## full framebuffers at once for no reason.
static func capture(host: Node, path: String, crop: Vector2i) -> bool:
	RenderingServer.force_draw()
	var vp := host.get_viewport()
	if vp == null:
		return false
	var image := vp.get_texture().get_image()
	if image == null:
		return false
	var size := Vector2i(mini(crop.x, image.get_width()), mini(crop.y, image.get_height()))
	var origin := Vector2i((image.get_width() - size.x) / 2, (image.get_height() - size.y) / 2)
	var err := image.get_region(Rect2i(origin, size)).save_png(path)
	image = null
	if err != OK:
		push_error("shot harness: could not write %s (error %d)" % [path, err])
		return false
	print("[SHOT] %s" % path)
	return true
