extends RefCounted
## A money figure for an LED screen: at most five cells, a printed £ before it and a printed K, M
## or B after it. The owner's rule: two decimals below £1,000 (£999.99), whole pounds from £1,000
## (£9999), then thousands with one decimal from £10,000 (£15.6K, up to £999.9K), then millions
## with two decimals (£1.01M), billions the same. A lit point takes no cell of its own (it lights
## on the digit before it, see bdp_v3_led.gd); a minus sign does, so a loss drops decimals to fit.

const MAX_CELLS := 5

## Each step: the divisor, the printed suffix, the decimals, and the figure it must stay under
## once rounded (else the next step takes it).
const STEPS := [
	[1.0, "", 2, 1000.0],
	[1.0, "", 0, 10000.0],
	[1000.0, "K", 1, 1000.0],
	[1000000.0, "M", 2, 1000.0],
	[1000000000.0, "B", 2, 1000.0],
	[1000000000000.0, "T", 2, INF],
]


## {"figure": the characters for the screen, "-" for a loss, "suffix": "", "K", "M", "B" or "T"}.
static func led(value: float) -> Dictionary:
	var minus := "-" if value < 0.0 else ""
	var a := absf(value)
	for step: Array in STEPS:
		var decimals: int = step[2]
		var scaled: float = a / float(step[0])
		var shown := _fixed(scaled, decimals)
		if shown.to_float() >= float(step[3]):
			continue
		while decimals > 0 and cells(minus + shown) > MAX_CELLS:
			decimals -= 1
			shown = _fixed(scaled, decimals)
		return {"figure": minus + shown, "suffix": step[1]}
	return {"figure": minus + _fixed(a, 0), "suffix": ""}


## Cells a figure takes on the screen: every character but the point.
static func cells(figure: String) -> int:
	return figure.replace(".", "").length()


## The figure as the player reads it: "£15.6K", "-£120.0".
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


## The owner's newer screen rule (docs/ds2-owner-decisions.md, Digital displays, 26 September 2026), for screens
## whose point takes a cell of its own (bdp_v3_led.gd point_cell): at most five cells with the point counted; two
## decimals below £100 (20.72), one from £100 (158.8), whole pounds from £1,000 (1153), then £15.6K, £1.01M,
## £1.01B with the letter printed after. A minus takes a cell, so a loss drops decimals to fit (-10.4).
const SCREEN_STEPS := [
	[1.0, "", 2, 100.0],
	[1.0, "", 1, 1000.0],
	[1.0, "", 0, 10000.0],
	[1000.0, "K", 1, 1000.0],
	[1000000.0, "M", 2, 1000.0],
	[1000000000.0, "B", 2, INF],
]

static func screen(value: float) -> Dictionary:
	var minus := "-" if value < 0.0 else ""
	var a := absf(value)
	for step: Array in SCREEN_STEPS:
		var decimals: int = step[2]
		var scaled: float = a / float(step[0])
		var shown := _fixed(scaled, decimals)
		if shown.to_float() >= float(step[3]):
			continue
		while decimals > 0 and (minus + shown).length() > MAX_CELLS:
			decimals -= 1
			shown = _fixed(scaled, decimals)
		return {"figure": minus + shown, "suffix": step[1]}
	return {"figure": minus + _fixed(a, 0), "suffix": ""}
