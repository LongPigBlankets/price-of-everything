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

# --- Tile-view terrain ambience ----------------------------------------------
# Looping field recordings that play while a tile's info panel is open, keyed by
# the tile's `type`. Three non-overlapping slices per terrain (one is picked at
# random each time such a tile is opened, then loops until the panel closes or a
# different terrain is selected). Urban blends three separate city recordings;
# the rest are sliced from a single recording each. Terrains absent here (e.g.
# mountain) simply play nothing.
const AMBIENCE := {
	"sea": [   # gentle shore waves
		preload("res://assets/audio/ambient_sounds/sea_1.ogg"),
		preload("res://assets/audio/ambient_sounds/sea_2.ogg"),
		preload("res://assets/audio/ambient_sounds/sea_3.ogg"),
	],
	"deep_sea": [   # open-ocean swell
		preload("res://assets/audio/ambient_sounds/deep_sea_1.ogg"),
		preload("res://assets/audio/ambient_sounds/deep_sea_2.ogg"),
		preload("res://assets/audio/ambient_sounds/deep_sea_3.ogg"),
	],
	"urban": [   # one slice from each of three city recordings
		preload("res://assets/audio/ambient_sounds/urban_1.ogg"),
		preload("res://assets/audio/ambient_sounds/urban_2.ogg"),
		preload("res://assets/audio/ambient_sounds/urban_3.ogg"),
	],
	"rural": [   # bird chirps
		preload("res://assets/audio/ambient_sounds/rural_1.ogg"),
		preload("res://assets/audio/ambient_sounds/rural_2.ogg"),
		preload("res://assets/audio/ambient_sounds/rural_3.ogg"),
	],
	"hill": [   # forest ambience
		preload("res://assets/audio/ambient_sounds/hill_1.ogg"),
		preload("res://assets/audio/ambient_sounds/hill_2.ogg"),
		preload("res://assets/audio/ambient_sounds/hill_3.ogg"),
	],
	"mountain": [   # one slice from each of three wind recordings (sources short, so 5–14s)
		preload("res://assets/audio/ambient_sounds/mountain_1.ogg"),
		preload("res://assets/audio/ambient_sounds/mountain_2.ogg"),
		preload("res://assets/audio/ambient_sounds/mountain_3.ogg"),
	],
}
const AMBIENCE_DB := -6.0   # terrain ambience sits under the cues and music

# Tutorial hint — a short glass/crystal ping (first 2s) to draw the eye. Not wired
# to any trigger yet; tutorial steps will call Audio.hint().
const HINT: AudioStream = preload("res://assets/audio/ui_sounds/hint.ogg")

# --- Volume buses ------------------------------------------------------------
# Two mixing buses fed into Master, created at startup if absent (there is no
# default_bus_layout.tres). Music routes to MUSIC; every cue + terrain ambience
# routes to SFX. The Settings panel drives all three via set_bus_percent().
const BUS_MASTER := &"Master"
const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"

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
	&"hint": 1,    # tutorial hint ping
}

var _channels: Dictionary = {}   # StringName -> Array[AudioStreamPlayer]
var _next: Dictionary = {}       # StringName -> round-robin index
var _music: AudioStreamPlayer    # dedicated player for the music playlist
var _ambient: AudioStreamPlayer  # dedicated player for tile-view terrain ambience
var _ambient_type := ""          # terrain currently sounding ("" = silent)
var _track_idx := 0              # current track in MUSIC_TRACKS
var _music_gen := 0              # bumped on every track change; invalidates a pending gap-advance
var _duck_frame := -1            # frame a higher-priority cue ducked clicks on
var _last_hover_ms := -10000     # throttles hover when sweeping across buttons


func _ready() -> void:
	_ensure_buses()
	for channel in CHANNELS:
		var pool: Array[AudioStreamPlayer] = []
		for i in int(CHANNELS[channel]):
			var p := AudioStreamPlayer.new()
			p.bus = BUS_SFX
			add_child(p)
			pool.append(p)
		_channels[channel] = pool
		_next[channel] = 0
	_music = AudioStreamPlayer.new()
	_music.bus = BUS_MUSIC
	add_child(_music)
	_music.finished.connect(_on_music_finished)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = BUS_SFX
	add_child(_ambient)
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
	_play(SLOT_LEVER, &"turn", -10.0)   # the end-turn lever sits 10 dB under the other cues


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


## Fade the music out over `duration`s, then stop it. If `resume_after` >= 0, the
## playlist resumes with the NEXT track that many seconds after this call (so the menu
## theme fades as the game begins, then gameplay music returns); pass -1 to leave the
## playlist halted. Used when the player begins the game.
func fade_music(duration: float = 2.0, resume_after: float = -1.0) -> void:
	_music_gen += 1
	var gen := _music_gen
	if _music != null and _music.playing:
		var tw := create_tween()
		tw.tween_property(_music, "volume_db", MUSIC_FADE_DB, duration)
		tw.tween_callback(func() -> void:
			_music.stop()
			_music.volume_db = 0.0)
	if resume_after >= 0.0:
		_resume_music_after(gen, resume_after)


# Resume the playlist (next track) after `delay`s, unless a swap/stop/another fade
# changed the music in the meantime (then `gen` no longer matches and we bail).
func _resume_music_after(gen: int, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if gen != _music_gen:
		return
	_track_idx = (_track_idx + 1) % MUSIC_TRACKS.size()
	_play_track()


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


# --- Tile-view ambience ------------------------------------------------------

## Start (or switch to) the looping ambience for a tile panel showing `terrain`
## (the tile's `type`: "sea", "deep_sea", "urban", "rural", "hill"). Picks one of
## that terrain's slices at random and loops it until stopped. A no-op when the same
## terrain is already sounding, so re-selecting same-type tiles doesn't restart the
## loop; a terrain with no ambience (e.g. "mountain") falls through to silence.
func tile_ambience(terrain: String) -> void:
	var clips: Array = AMBIENCE.get(terrain, [])
	if clips.is_empty():
		stop_tile_ambience()
		return
	if terrain == _ambient_type and _ambient != null and _ambient.playing:
		return
	_ambient_type = terrain
	_ambient.stream = clips[randi() % clips.size()]   # cosmetic pick — Audio is exempt from the determinism rule
	_ambient.volume_db = AMBIENCE_DB
	_ambient.play()


## Silence the tile-view ambience (panel closed / selection cleared).
func stop_tile_ambience() -> void:
	_ambient_type = ""
	if _ambient != null:
		_ambient.stop()


# --- Tutorial hint -----------------------------------------------------------

## A short glass/crystal ping to draw the eye during tutorials. Not wired to any
## trigger yet — tutorial steps will call this.
func hint() -> void:
	_play(HINT, &"hint")


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


# --- Volume control ----------------------------------------------------------

# Create the Music and SFX buses (routed to Master) if they don't already exist.
func _ensure_buses() -> void:
	for bus_name in [BUS_MUSIC, BUS_SFX]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, BUS_MASTER)


## Set a bus's volume from a 0–100 percentage (linear). 0 mutes the bus. Used by
## the Settings panel; `bus` is one of BUS_MASTER / BUS_MUSIC / BUS_SFX.
func set_bus_percent(bus: StringName, percent: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	var frac := clampf(percent, 0.0, 100.0) / 100.0
	AudioServer.set_bus_mute(idx, frac <= 0.0)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(frac, 0.0001)))


## Current volume of a bus as a 0–100 percentage (0 if muted). The Settings panel
## reads this to initialise its sliders to the live values.
func get_bus_percent(bus: StringName) -> float:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return 100.0
	if AudioServer.is_bus_mute(idx):
		return 0.0
	return clampf(db_to_linear(AudioServer.get_bus_volume_db(idx)) * 100.0, 0.0, 100.0)


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


func _play(stream: AudioStream, channel: StringName, vol_db: float = 0.0) -> void:
	if stream == null:
		return
	var pool: Array = _channels.get(channel, [])
	if pool.is_empty():
		return
	var player: AudioStreamPlayer = _free_in(pool, channel)
	player.stream = stream
	player.volume_db = vol_db
	player.play()


func _free_in(pool: Array, channel: StringName) -> AudioStreamPlayer:
	for player in pool:
		if not player.playing:
			return player
	var idx: int = int(_next[channel])
	_next[channel] = (idx + 1) % pool.size()
	return pool[idx]
