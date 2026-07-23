extends Node
## MapStyle — the map-restyle seam (docs/map_ink_wash_restyle_spec.md, P0).
## Two style tables for every base-map color the ink & wash restyle touches:
## `classic` mirrors the pre-restyle constants byte-for-byte; `ink` is the
## vintage board-game grade. Layers read through the getters below and rebuild
## on `style_changed`; the `toggle ink` debug cheat flips at runtime, which
## doubles as the classic-mode regression check. Purely visual — never sim
## state, never saved.

signal style_changed

var ink := false

func set_ink(on: bool) -> void:
	if ink == on:
		return
	ink = on
	style_changed.emit()

## ── Relief bands (hill_visuals) ─────────────────────────────────────────────
## band = level + 1: [0] sub-sea depressions, [1] coastal sand, [2..6] lowland,
## [7..10] uplands, [11] peaks. Ink ramp: olive lowland -> straw -> ochre ->
## sienna, cream peaks (spec §4 Option A: geometry untouched, palette re-graded).

const _BAND_CLASSIC: Array[Color] = [
	Color("28401f"), Color("d9cda2"), Color("5e7d44"), Color("6c874d"),
	Color("7e955c"), Color("9aa771"), Color("bebd8b"), Color("c9b384"),
	Color("bd9c69"), Color("a17e50"), Color("7d5c3a"), Color(1.0, 1.0, 1.0),
]
const _BAND_INK: Array[Color] = [
	Color("55603c"), Color("ddd0a6"), Color("a9ad7b"), Color("b1b381"),
	Color("b9b884"), Color("c1bd85"), Color("c9c287"), Color("cdb47e"),
	Color("bf9a6a"), Color("a98156"), Color("8d6a47"), Color("efe6ce"),
]

## Sea bands: deep -> shelf, then the sandy land base ([5], matches band [1]).
const _SEA_CLASSIC: Array[Color] = [
	Color("000d94"), Color("000dc2"), Color("194ba9"), Color("24549e"),
	Color(0.17647059, 0.40784314, 0.76862745), Color("d9cda2"),
]
const _SEA_INK: Array[Color] = [
	Color("2e4468"), Color("35507a"), Color("46648c"), Color("4f6f99"),
	Color("6b8fb5"), Color("ddd0a6"),
]

const _WATER_CLASSIC := Color(0.17647059, 0.40784314, 0.76862745, 1.0)
const _WATER_INK := Color("5b86b5")

func band_colors() -> Array[Color]:
	return _BAND_INK if ink else _BAND_CLASSIC

func sea_colors() -> Array[Color]:
	return _SEA_INK if ink else _SEA_CLASSIC

## Lakes + the coastal shelf; same hue as rivers so all water reads as one.
func water_color() -> Color:
	return _WATER_INK if ink else _WATER_CLASSIC

func river_color() -> Color:
	return water_color()

## ── Roads (road_network_visuals; widths change in P2, colors here) ──────────

func road_local() -> Color:
	return Color("dfd0a2") if ink else Color("e8c84a")

func road_trunk() -> Color:
	return Color("d4bd8a") if ink else Color("d97b29")

func road_casing() -> Color:
	return Color(0.227, 0.173, 0.094, 0.95) if ink else Color(0.24, 0.16, 0.05, 0.9)

func road_bridge() -> Color:
	return Color("4a3826") if ink else Color(0.32, 0.2, 0.08)

## ── Ports (port_visuals) ────────────────────────────────────────────────────

func port_dockhouse() -> Color:
	return Color("efe9db") if ink else Color(0.96, 0.97, 0.98)

func port_outline() -> Color:
	return Color("3a2c18") if ink else Color(0.55, 0.62, 0.69)

func port_pier() -> Color:
	return Color("cbb489") if ink else Color(0.90, 0.92, 0.94)

## ── Farms (building_visuals farm branch; furrow rework lands in P3) ─────────

func farm_field() -> Color:
	return Color("b8c08a") if ink else Color("a8d98a")

func farm_hatch() -> Color:
	return Color(0.333, 0.314, 0.165, 0.8) if ink else Color(0.18, 0.38, 0.18, 0.85)

## ── Parchment grain (parchment_overlay) ─────────────────────────────────────

func parchment_darkest() -> Color:
	return Color(0.82, 0.77, 0.67) if ink else Color(0.86, 0.81, 0.72)

func parchment_lightest() -> Color:
	return Color(1.0, 0.99, 0.96)

## ── P1 ink structure: contours, coast, water lining, river banks ────────────

const INK := Color("3a2c18")

## Relief band outlines. Classic keeps the darkened-fill stroke; ink draws
## sepia contour hairlines with every 2nd band emphasized (engraved read).
func contour_color(band: int, fill: Color) -> Color:
	if not ink:
		return fill.darkened(0.22)
	return Color(INK.r, INK.g, INK.b, 0.55 if band % 2 == 0 else 0.35)

func contour_width(band: int) -> float:
	if not ink:
		return 1.5
	return 2.0 if band % 2 == 0 else 1.2

## Coastline stroke where the landmass meets the sea (owner: keep it bold).
## Transparent in classic = skip drawing.
func coast_color() -> Color:
	return Color(INK.r, INK.g, INK.b, 0.9) if ink else Color(0.0, 0.0, 0.0, 0.0)

func coast_width() -> float:
	return 4.2

## Engraved water lining: hairlines offset seaward from the coast, fading out.
## Entries are [offset_u, alpha, width]; empty in classic.
func water_lining() -> Array:
	return [[14.0, 0.38, 1.3], [30.0, 0.22, 1.1]] if ink else []

func lake_shore_color(fill: Color) -> Color:
	return Color(INK.r, INK.g, INK.b, 0.7) if ink else fill.darkened(0.25)

func lake_shore_width() -> float:
	return 2.2 if ink else 2.0

## River bank casing (ink only): drawn under the water pass, wider by _extra.
func river_casing() -> Color:
	return Color(INK.r, INK.g, INK.b, 0.8)

func river_casing_extra() -> float:
	return 4.0

## Flow squiggles inside the river (ink only): short darker-blue dashes.
func river_squiggle() -> Color:
	return Color(0.247, 0.435, 0.639, 0.5)
