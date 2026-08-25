extends PanelContainer
## Anomaly popup — a small card that drops under the Treasury or Power module when a
## turn does something abnormal, and says what in one sentence.
##
## This exists because of a playtest finding: the player could not tell why money
## jumped around, and a +£2,500 turn read as arbitrary. It was not — it was a batch of
## sale shipments landing at once, on top of an auto-bridge loan she never saw taken.
## Every number involved was already on screen somewhere; none of it was ever
## ATTRIBUTED. So the popup's whole job is to name the cause, in the player's words,
## at the moment it happens.
##
## Dismissed by clicking anywhere else (owner ruling) — there is no close button and
## no timer. Unlike a toast it cannot expire before it is read, which was the other
## half of the same finding ("the toasts are too short lived").
##
## All copy is off-white (DS.PALETTE.TEXT) — never grey. See docs/top-bar-v3-spec.md §4.

const _UIFonts := preload("res://scripts/ui_fonts.gd")

## The card is as wide as the MODULE it belongs to (owner 2026-08-24) — a fixed 320 made
## a card under the narrow Power module read as a floating banner rather than as that
## module's own footnote. WIDTH is only the fallback for an anchor with no width yet.
const WIDTH := 320.0
const MIN_WIDTH := 180.0    # a very narrow module still needs a readable measure
const PAD := 6              # owner: no more than 6px
const FONT_SIZE := 14
const MAX_LINES := 4        # then the text trims with an ellipsis; short cards stay short
const BORDER := 2           # owner: a heavier rim, so a card reads as a card
## The one word that says what happened, bolded and coloured by whether it is good news
## (owner 2026-08-24). A card is read in a glance on a busy turn boundary; the word is
## what the glance lands on, and its colour answers "do I care?" before the sentence does.
const TONE_COLORS := {"good": "OK", "bad": "DANGER", "warn": "WARN"}
const ANCHOR_GAP := 8.0     # below the bar module it belongs to
## The card announces itself, then stops. A turn is a busy moment — numbers change all
## over the bar at once — so a card that simply appeared could be missed entirely, which
## is the failure this whole feature exists to fix. Two beats of the border and the card
## is found; any more and it becomes the thing you wait to stop rather than read.
const FLASH_BEATS := 2
const FLASH_BEAT_TIME := 0.28

signal dismissed

var _body: RichTextLabel
var _width: float = WIDTH


func _ready() -> void:
	theme = DS.theme
	theme_type_variation = "Card"
	top_level = true          # positioned against a module, not laid out by a container
	custom_minimum_size = Vector2(_width, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP   # clicks on the card itself never dismiss it
	# The Card variation brings its own content margin, which stacked on top of the
	# margin below and put the text ~27px in. Zero the stylebox's and let the one
	# MarginContainer own the padding, so PAD is the whole of it.
	var sb := get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		var box := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
		box.set_content_margin_all(0.0)
		box.set_border_width_all(BORDER)
		add_theme_stylebox_override("panel", box)
	_build()


func _build() -> void:
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, PAD)
	add_child(margin)

	# A RichTextLabel, because one word in the sentence is bold and coloured and a Label
	# cannot do that. The three-line trim is therefore done by MEASUREMENT below rather
	# than by max_lines_visible, which RichTextLabel does not have.
	_body = RichTextLabel.new()
	_body.bbcode_enabled = true
	_body.fit_content = true
	_body.scroll_active = false
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(_width - PAD * 2, 0)
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Explicit, not inherited: this card is the one place the owner named by hand —
	# the text is off-white, never the dim secondary.
	_body.add_theme_color_override("default_color", DS.PALETTE.TEXT)
	_body.add_theme_font_override("normal_font", _UIFonts.PLEX_MED)
	_body.add_theme_font_override("bold_font", _UIFonts.PLEX_SEMI)
	_body.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	_body.add_theme_font_size_override("bold_font_size", FONT_SIZE)
	margin.add_child(_body)


## Match the module this card belongs to. Called BEFORE set_message, because the wrapped
## height the caller stacks by is only right once the width the text wraps at is.
func set_width(w: float) -> void:
	_width = maxf(MIN_WIDTH, w)
	custom_minimum_size = Vector2(_width, 0)
	if _body != null:
		_body.custom_minimum_size = Vector2(_width - PAD * 2, 0)
	reset_size()


## `word` is the one term the card is about and `tone` how to read it — "bad" for a cost
## running away, "good" for money arriving, "warn" for something merely worth knowing.
func set_message(text: String, word: String = "", tone: String = "warn") -> void:
	var shown := _trim_to_lines(text)
	_body.text = _mark(shown, word, tone)
	reset_size()
	_flash()


## Cut `text` down to MAX_LINES at the card's width, ending on an ellipsis when it had to.
## Measured against the font rather than the laid-out label: the caller stacks cards by
## their height immediately after setting the text, before any layout pass has run.
func _trim_to_lines(text: String) -> String:
	var font: Font = _body.get_theme_font("normal_font")
	if font == null:
		return text
	var avail: float = maxf(40.0, _width - PAD * 2)
	var line_h: float = font.get_height(FONT_SIZE)
	var budget: float = line_h * float(MAX_LINES) + 1.0
	if font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, avail, FONT_SIZE).y <= budget:
		return text
	var words := text.split(" ", false)
	var kept := ""
	for w: String in words:
		var candidate := w if kept == "" else kept + " " + w
		if font.get_multiline_string_size(candidate + "…", HORIZONTAL_ALIGNMENT_LEFT, avail, FONT_SIZE).y > budget:
			break
		kept = candidate
	return (kept if kept != "" else text.substr(0, 12)) + "…"


## Bold and colour the first occurrence of `word` — a PHRASE as often as a single word:
## on a big-sale card the part worth seeing is "earned you £912", not the verb.
## BBCode is escaped first, so a message that happens to contain a bracket cannot open a
## tag by accident.
func _mark(text: String, word: String, tone: String) -> String:
	var safe := text.replace("[", "[lb]")
	if word == "":
		return safe
	var lower := safe.to_lower()
	var at := lower.find(word.to_lower())
	if at < 0:
		return safe
	var key: String = str(TONE_COLORS.get(tone, "WARN"))
	var col: Color = DS.PALETTE[key]
	var hit := safe.substr(at, word.length())
	return "%s[b][color=#%s]%s[/color][/b]%s" % [
		safe.substr(0, at), col.to_html(false), hit, safe.substr(at + word.length())]


## Place the card under `anchor`, `stack_offset` px further down for each card already
## showing on the same anchor, and clamped so a module near the right edge of an
## ultrawide does not push it off screen.
func place_under(anchor: Control, stack_offset: float = 0.0) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	if anchor.size.x > 1.0:
		set_width(anchor.size.x)
	reset_size()
	var vw := get_viewport_rect().size.x
	var x: float = clampf(anchor.global_position.x, 8.0, maxf(8.0, vw - size.x - 8.0))
	var y: float = anchor.global_position.y + anchor.size.y + ANCHOR_GAP + stack_offset
	global_position = Vector2(x, y)


## Pulse the border and the ground, from the accent back down to rest. Tweened, not
## animated per frame: a tween that misses a frame resumes where it was, and this runs on
## the turn boundary, which is the busiest the main thread ever gets.
func _flash() -> void:
	var sb := get_theme_stylebox("panel")
	if not (sb is StyleBoxFlat):
		return
	var box := (sb as StyleBoxFlat).duplicate() as StyleBoxFlat
	add_theme_stylebox_override("panel", box)   # our own copy; never tween the shared one
	var rest_border: Color = box.border_color
	var rest_bg: Color = box.bg_color
	var lit_border: Color = DS.PALETTE.ACCENT
	var lit_bg: Color = rest_bg.lerp(DS.PALETTE.ACCENT, 0.14)
	box.set_border_width_all(maxi(1, box.border_width_top))
	var tween := create_tween()
	for _beat in FLASH_BEATS:
		tween.tween_method(func(t: float) -> void:
			box.border_color = rest_border.lerp(lit_border, t)
			box.bg_color = rest_bg.lerp(lit_bg, t),
			0.0, 1.0, FLASH_BEAT_TIME * 0.4)
		tween.tween_method(func(t: float) -> void:
			box.border_color = lit_border.lerp(rest_border, t)
			box.bg_color = lit_bg.lerp(rest_bg, t),
			0.0, 1.0, FLASH_BEAT_TIME * 0.6)


func dismiss() -> void:
	dismissed.emit()
	queue_free()
