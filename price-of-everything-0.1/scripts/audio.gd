extends Node
## Audio — presentation-layer sound service (autoload `Audio`).
##
## Plays sound only; read-only against the sim (never mutates game state), so it
## is exempt from the determinism rule. Callers use semantic verbs, never asset
## names. Voices are split into independent CHANNELS so cues in one channel never
## steal a voice from another. Music is a separate looping playlist player.
##
## Button clicks are auto-wired by DS style (see _sound_for_button): the bottom
## menu gets the menu cue, bluish-silver (DS-themed) buttons get the primary cue,
## and custom-styled buttons get the plain click. See memory: sound-effects-design.

# --- Click cues (3, picked per button by style) ------------------------------
const CLICK: AudioStream = preload("res://assets/audio/ui_sounds/click_default.wav")        # other/custom buttons (click-0)
const CLICK_MENU: AudioStream = preload("res://assets/audio/ui_sounds/click_menu.wav")       # bottom-menu buttons (386176, heavier)
const CLICK_PRIMARY: AudioStream = preload("res://assets/audio/ui_sounds/click_primary.wav") # bluish-silver buttons (666hero)
const HOVER: AudioStream = preload("res://assets/audio/ui_sounds/hover.wav")                 # hover over a DS-themed button (menu-interface-selection)

# --- Event / outcome cues ----------------------------------------------------
const HAMMER: AudioStream = preload("res://assets/audio/ui_sounds/hammer.wav")            # building placed (4 strikes)
const RUBBLE: AudioStream = preload("res://assets/audio/ui_sounds/rubble.wav")            # building demolished
const SIGNATURE: AudioStream = preload("res://assets/audio/ui_sounds/signature.wav")      # buy/sell building or land
const CASH_REGISTER: AudioStream = preload("res://assets/audio/ui_sounds/cash_register.wav") # profitable turn
const TECH_UNLOCK: AudioStream = preload("res://assets/audio/ui_sounds/tech_unlock.wav")      # tech unlocked (gears unlock mech)
const SLOT_LEVER: AudioStream = preload("res://assets/audio/ui_sounds/slot_lever.wav")        # turn resolved → back to DECIDE

# Music playlist — five PLACEHOLDER tracks (stereo Ogg Vorbis; licensing pending,
# see memory: music-licensing) that play in sequence with MUSIC_GAP seconds of
# silence between them, looping. The `swap song` cheat jumps to the next.
const MUSIC_TRACKS: Array[AudioStream] = [
	preload("res://assets/audio/music/pizzicato.ogg"),
	preload("res://assets/audio/music/modern_epic_violin.ogg"),
	preload("res://assets/audio/music/urgent_strings.ogg"),
	preload("res://assets/audio/music/big_band_jazz.ogg"),
	preload("res://assets/audio/music/vinyl_77.ogg"),
]
const MUSIC_TRACK_NAMES := ["Pizzicato", "Modern Epic Violin", "Urgent Strings", "Big Band Savage Jazz", "Vinyl 77"]
const MUSIC_GAP := 30.0   # seconds of silence between tracks

# Small delay before the bottom-menu click, so the cue lands with the button's
# slot-out/in motion (bottom_menu.gd RISE_TIME = 0.12s). Only the menu cue waits;
# other clicks play immediately. 0.0 = immediate.
const CLICK_DELAY := 0.05

const MUSIC_FADE_DB := -60.0   # target volume for a faded-out track (effectively silent)

# Independent voice channels: name -> pool size. One pool per kind of cue.
const CHANNELS := {
	&"ui": 3,      # clicks (all three cues share this — you don't click two buttons at once)
	&"build": 2,   # hammer / rubble (longer construction cues)
	&"deal": 2,    # transaction signature
	&"money": 1,   # turn-end cash register
	&"hover": 2,   # button hover
	&"unlock": 1,  # tech-unlock jingle (long; its own non-stealable lane)
	&"turn": 1,    # end-turn → back-to-DECIDE lever
}

var _channels: Dictionary = {}   # StringName -> Array[AudioStreamPlayer]
var _next: Dictionary = {}       # StringName -> round-robin index
var _music: AudioStreamPlayer    # dedicated player for the music playlist
var _track_idx := 0              # current track in MUSIC_TRACKS
var _music_gen := 0              # bumped on every track change; invalidates a pending gap-advance
var _duck_frame := -1            # frame a higher-priority cue ducked clicks on
var _last_hover_ms := -10000     # throttles hover when sweeping across buttons


func _ready() -> void:
	for channel in CHANNELS:
		var pool: Array[AudioStreamPlayer] = []
		for i in int(CHANNELS[channel]):
			var p := AudioStreamPlayer.new()
			add_child(p)
			pool.append(p)
		_channels[channel] = pool
		_next[channel] = 0
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	# Auto-wire a click cue to every Button, now and as they appear.
	get_tree().node_added.connect(_on_node_added)
	await get_tree().process_frame   # let the first scene + the other autoloads come up
	for b in get_tree().root.find_children("*", "Button", true, false):
		_wire_button(b)
	Production.turn_processed.connect(_on_turn_processed)        # profitable turn → cash register
	MatchState.unlock_granted.connect(_on_unlock_granted)        # tech unlocked → gears
	TurnManager.turn_resolution_completed.connect(turn_ready)    # back to DECIDE → slot lever


# --- Click verbs (chosen per button by the auto-wire) ------------------------

## Default click — custom-styled / "other" buttons.
func click() -> void:
	_play_click.call_deferred(CLICK)


## Bottom-menu click. Waits CLICK_DELAY so the cue syncs with the button's slot.
func click_menu() -> void:
	if CLICK_DELAY > 0.0:
		await get_tree().create_timer(CLICK_DELAY).timeout
	_play_click(CLICK_MENU)


## Bluish-silver (DS-themed) buttons — build / buy / confirm / menu actions.
func click_primary() -> void:
	_play_click.call_deferred(CLICK_PRIMARY)


## Hover over a DS-themed button (one with a hover overlay). Throttled so sweeping
## the mouse across a row of buttons doesn't machine-gun the cue.
func hover() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hover_ms < 60:
		return
	_last_hover_ms = now
	_play(HOVER, &"hover")


# --- Event / outcome verbs ---------------------------------------------------

## Player places a building on the map (four hammer strikes). Called from the
## build-commit handlers in world_map.gd, not the broad `building_placed` signal.
func building_placed() -> void:
	_duck_clicks()
	_play(HAMMER, &"build")


## Player demolishes a building (rubble). NOTE: demolish is not a functional
## player action yet (remove_building is test-only; the deposit-dialog Demolish is
## a no-op) — wire this at the demolish success point once that feature exists.
func demolished() -> void:
	_duck_clicks()
	_play(RUBBLE, &"build")


## Player buys/sells a building or land (a pen-signature cue). Wired to the
## success point of each transaction. Sell-building / sell-land aren't in the
## game yet — call this from their commit handlers when they are.
func transaction() -> void:
	_duck_clicks()
	_play(SIGNATURE, &"deal")


## A tech was unlocked — manually, or earned at a turn change. Same cue for both.
func tech_unlocked() -> void:
	_duck_clicks()   # manual unlock from a button → suppress that button's click
	_play(TECH_UNLOCK, &"unlock")


## Turn resolved and control returns to the player (DECIDE) — a slot-machine lever pull.
func turn_ready() -> void:
	_play(SLOT_LEVER, &"turn")


# --- Music (playlist) --------------------------------------------------------

## Start the playlist from the first track (Pizzicato).
func play_music() -> void:
	_track_idx = 0
	_play_track()


## Cheat (`swap song`): jump straight to the next track. Returns its display name.
func swap_song() -> String:
	_track_idx = (_track_idx + 1) % MUSIC_TRACKS.size()
	_play_track()
	return MUSIC_TRACK_NAMES[_track_idx]


func stop_music() -> void:
	_music_gen += 1   # cancel any pending gap-advance
	_music.stop()


## Fade the music out over `duration`s, then stop it — and halt the playlist (no
## auto-advance after the gap). Used when the player begins the game.
func fade_music(duration: float = 2.0) -> void:
	_music_gen += 1
	if _music == null or not _music.playing:
		return
	var tw := create_tween()
	tw.tween_property(_music, "volume_db", MUSIC_FADE_DB, duration)
	tw.tween_callback(func() -> void:
		_music.stop()
		_music.volume_db = 0.0)


func _play_track() -> void:
	_music_gen += 1
	_music.volume_db = 0.0
	_music.stream = MUSIC_TRACKS[_track_idx]
	_music.play()


# A track finished → MUSIC_GAP of silence → next track, unless a swap / fade / stop
# changed the track during the gap (then _music_gen no longer matches and we bail).
func _on_music_finished() -> void:
	var gen := _music_gen
	await get_tree().create_timer(MUSIC_GAP).timeout
	if gen != _music_gen:
		return
	_track_idx = (_track_idx + 1) % MUSIC_TRACKS.size()
	_play_track()


# --- Auto-wiring (clicks, by DS style) ---------------------------------------

func _on_node_added(n: Node) -> void:
	if n is Button:
		_wire_button(n)


func _wire_button(b: Button) -> void:
	if b.has_meta(&"_sfx"):
		return
	b.set_meta(&"_sfx", true)
	var cat := _button_category(b)
	# Every button except the bottom menu uses the 666hero click (click_primary).
	b.pressed.connect(click_menu if cat == &"menu" else click_primary)
	# Menu / bluish-silver buttons show a DS hover overlay → hover cue. Custom-styled
	# "other" buttons that want hover wire it themselves (e.g. the infra plus buttons).
	if cat != &"other":
		b.mouse_entered.connect(hover)


# Classify a button by place + DS style. Bottom-menu buttons are children of
# %BottomMenu; bluish-silver buttons use the default/Primary/Build theme (no
# custom "normal" stylebox); everything else is "other" (plain click, no hover).
func _button_category(b: Button) -> StringName:
	var parent := b.get_parent()
	if parent != null and parent.name == &"BottomMenu":
		return &"menu"
	if not b.has_theme_stylebox_override(&"normal") \
			and b.theme_type_variation in [&"", &"Primary", &"Build"]:
		return &"primary"
	return &"other"


# --- Turn-end ----------------------------------------------------------------

func _on_turn_processed(summary: Dictionary) -> void:
	# Profitable turn = the EXACT figure the turn summary shows green (turn_summary.gd:119:
	# money_in - money_out). Using the raw balance delta instead would also count delayed
	# sale arrivals from past turns, firing the register on operationally-unprofitable turns.
	var net := float(summary.get("money_in", 0.0)) - float(summary.get("money_out", 0.0))
	if net > 0.005:
		_play(CASH_REGISTER, &"money")


func _on_unlock_granted(_title: String, _description: String, _via_condition: bool) -> void:
	tech_unlocked()


# --- Internals ---------------------------------------------------------------

# A higher-priority cue (building / demolish / transaction) is playing this frame
# — mark the frame so any click queued for the same button press is dropped.
func _duck_clicks() -> void:
	_duck_frame = Engine.get_process_frames()


# Clicks are deferred (call_deferred) so they resolve AFTER the press handlers
# that might trigger an outcome cue; if one ducked this frame, the click is dropped.
func _play_click(stream: AudioStream) -> void:
	if Engine.get_process_frames() == _duck_frame:
		return
	_play(stream, &"ui")


func _play(stream: AudioStream, channel: StringName) -> void:
	if stream == null:
		return
	var pool: Array = _channels.get(channel, [])
	if pool.is_empty():
		return
	var player: AudioStreamPlayer = _free_in(pool, channel)
	player.stream = stream
	player.play()


func _free_in(pool: Array, channel: StringName) -> AudioStreamPlayer:
	for player in pool:
		if not player.playing:
			return player
	var idx: int = int(_next[channel])
	_next[channel] = (idx + 1) % pool.size()
	return pool[idx]
