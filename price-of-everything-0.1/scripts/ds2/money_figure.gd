extends RefCounted
## A money figure for an LED screen, by the owner's rule (docs/ds2-owner-decisions.md, Digital displays): the
## point takes a cell of its own, a figure is at most five cells with the point counted, never more than two
## decimals, and a printed £ before it and a printed K, M or B after it. Two decimals below £100 (9.99, 99.99),
## one from £100 (999.1), whole pounds from £1,000 (9999), then thousands with one decimal from £10,000 (15.6K,
## to 999.9K), then millions with two (1.01M), billions the same. A minus takes a cell, so a loss drops decimals
## to fit (-10.4). bdp_v3_led.gd fits every number it is handed to the same rule (Led.fit).
const MAX_CELLS := 5

## {"figure": the characters for the screen, "-" for a loss, "suffix": "", "K", "M", "B"}: the screen rule.
static func led(value: float) -> Dictionary:
	return screen(value)


## Cells a figure takes on the screen: every character, the point included.
static func cells(figure: String) -> int:
	return figure.length()


## The figure as the player reads it: "£15.6K", "-£10.4".
static func text(value: float) -> String:
	var parts := led(value)
	var figure: String = parts.figure
	var minus := ""
	if figure.begins_with("-"):
		minus = "-"
		figure = figure.substr(1)
	return "%s£%s%s" % [minus, figure, parts.suffix]


static func _fixed(v: float, decimals: int) -> String:
	return ("%." + str(decimals) + "f") % v


## The steps: the divisor, the printed suffix, the decimals, and the figure it must stay under once rounded (else
## the next step takes it).
const SCREEN_STEPS := [
	[1.0, "", 2, 100.0],
	[1.0, "", 1, 1000.0],
	[1.0, "", 0, 10000.0],
	[1000.0, "K", 1, 1000.0],
	[1000000.0, "M", 2, 1000.0],
	[1000000000.0, "B", 2, INF],
]

## `value` by the rule. `max_decimals` caps the pound steps' decimals (a figure kept whole stays whole); the scaled
## steps (K, M, B) keep theirs.
static func screen(value: float, max_decimals := 2) -> Dictionary:
	var minus := "-" if value < 0.0 else ""
	var a := absf(value)
	for step: Array in SCREEN_STEPS:
		var decimals: int = step[2]
		if float(step[0]) == 1.0:
			decimals = mini(decimals, maxi(0, max_decimals))
		var scaled: float = a / float(step[0])
		var shown := _fixed(scaled, decimals)
		if shown.to_float() >= float(step[3]):
			continue
		while decimals > 0 and (minus + shown).length() > MAX_CELLS:
			decimals -= 1
			shown = _fixed(scaled, decimals)
		return {"figure": minus + shown, "suffix": step[1]}
	return {"figure": minus + _fixed(a, 0), "suffix": ""}


## The rule's figure for a screen, under the name the market's first build called it.
static func display(value: float) -> Dictionary:
	return screen(value)


## The figure as the player reads it under the display rule: "£0.57", "£481.3", "£15.6K".
static func display_text(value: float) -> String:
	var parts := screen(value)
	var figure: String = parts.figure
	var minus := ""
	if figure.begins_with("-"):
		minus = "-"
		figure = figure.substr(1)
	return "%s£%s%s" % [minus, figure, parts.suffix]
