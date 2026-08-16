extends Node
## MapStyle — the map-restyle seam (docs/map_ink_wash_restyle_spec.md, P0).
## Style tables for every base-map color the restyles touch: `classic` mirrors
## the pre-restyle constants byte-for-byte; `ink` is the vintage board-game
## grade; `plate` is the city-plate sub-variant of ink (docs/map_city_plate_spec.md).
## Layers read through the getters below and rebuild on `style_changed`; the
## `toggle ink` / `toggle plate` debug cheats flip at runtime, which doubles as
## the classic-mode regression check. Purely visual — never sim state, never saved.
##
## CITY PLATE (2026-08-10): a denser downtown plate by the same cartographer —
## near-uniform cream ground, light sky-blue water, and every solid mass drawn as
## an opaque prism (NW light, SE side-face silhouette under the top fill). It is a
## sub-variant: `plate` only takes effect while `ink` is true, so leaving ink also
## leaves plate. Three-way getters branch through `_sid()` / `_c3()`; a getter the
## plate doesn't change is not edited at all and simply inherits the ink value.

signal style_changed

## Ink & wash is the DEFAULT look (owner 2026-08-01). `classic` is kept as the A/B reference —
## `toggle ink` in the debug terminal flips back to it, which is still the regression check that
## every layer reads its colours through this seam rather than hardcoding them.
var ink := true
## "City plate" sub-variant; only active while `ink` is true. Never saved.
var plate := false
## Optional inhabited mid-century renderer. It is orthogonal to the three
## legacy modes: enabling it masks (but never mutates) the current legacy
## choice, and disabling it reveals that exact choice again.
var midcentury := false

func set_ink(on: bool) -> void:
	if ink == on:
		return
	ink = on
	if not on:
		plate = false   # classic can never latch plate
	style_changed.emit()

func set_plate(on: bool) -> void:
	if plate == on:
		return
	plate = on
	if on and not ink:
		ink = true   # plate implies ink; one emit covers both
	style_changed.emit()

func set_midcentury(on: bool) -> void:
	if midcentury == on:
		return
	midcentury = on
	style_changed.emit()

func is_midcentury() -> bool:
	return midcentury

func uses_ink_linework() -> bool:
	return ink or is_midcentury()

## Shared shape-language predicate for solid cartographic masses. Legacy plate
## and midcentury choose their own offsets/palettes through the getters below.
func has_cartographic_depth() -> bool:
	return is_plate() or is_midcentury()

## THE public plate predicate — the only spelling. Layers branch on this.
func is_plate() -> bool:
	return ink and plate

## Named enum: an unnamed one would inject its members as class constants and
## collide with `const INK` below (duplicate-member parse error).
enum Style { CLASSIC, INK, PLATE }

func _sid() -> Style:
	if ink:
		return Style.PLATE if plate else Style.INK
	return Style.CLASSIC

## Three-way colour pick. Classic/ink literals are copied verbatim from the
## pre-plate code, so both modes stay byte-identical by construction.
func _c3(classic: Color, ink_c: Color, plate_c: Color) -> Color:
	match _sid():
		Style.PLATE:
			return plate_c
		Style.INK:
			return ink_c
		_:
			return classic

## ── Relief bands (hill_visuals) ─────────────────────────────────────────────
## band = level + 1: [0] sub-sea depressions, [1] coastal sand, [2..6] lowland,
## [7..10] uplands, [11] peaks. Ink ramp: olive lowland -> straw -> ochre ->
## sienna, cream peaks (spec §4 Option A: geometry untouched, palette re-graded).

const _BAND_CLASSIC: Array[Color] = [
	Color("28401f"), Color("d9cda2"), Color("5e7d44"), Color("6c874d"),
	Color("7e955c"), Color("9aa771"), Color("bebd8b"), Color("c9b384"),
	Color("bd9c69"), Color("a17e50"), Color("7d5c3a"), Color(1.0, 1.0, 1.0),
]
## Lowland bands [2..4] deepened 2026-07-23 (owner: "too pastel") toward the
## richer olive of the reference plate; uplands keep the straw→sienna climb.
const _BAND_INK: Array[Color] = [
	Color("55603c"), Color("ddd0a6"), Color("9aa465"), Color("a3ad6e"),
	Color("adb377"), Color("c1bd85"), Color("c9c287"), Color("cdb47e"),
	Color("bf9a6a"), Color("a98156"), Color("8d6a47"), Color("efe6ce"),
]
## Plate SHARES ink's land ramp (owner ruling 2026-08-11: "I preferred the old
## green colour for the landmass"). Two earlier cuts regraded it — first to the
## reference's cream, then to a pale sage — and both were rejected. The plate is
## not a re-grade of the ground; it is a re-treatment of what STANDS on it.
## Consequence, and it is the reason several values below are ink's too: on a
## mid-value green ground the figure/ground relationship inverts back to ink's,
## so buildings and canopy have to read LIGHT-on-dark, not dark-on-light.

## Sea bands: deep -> shelf, then the sandy land base ([5], matches band [1]).
const _SEA_CLASSIC: Array[Color] = [
	Color("000d94"), Color("000dc2"), Color("194ba9"), Color("24549e"),
	Color(0.17647059, 0.40784314, 0.76862745), Color("d9cda2"),
]
const _SEA_INK: Array[Color] = [
	Color("2e4468"), Color("35507a"), Color("46648c"), Color("4f6f99"),
	Color("6b8fb5"), Color("ddd0a6"),
]
## Plate water returns TOWARD the pre-ink blue (owner 2026-08-11): the ink
## restyle washed the sea out to slate and the first plate cut took it further,
## to a pale sky. This sits between the two — the saturation and depth of the
## classic ramp, held a step lighter and warmer so it still belongs on paper.
## [5] is the sandy LAND BASE and must track band[1], which is ink's now.
const _SEA_PLATE: Array[Color] = [
	Color("13387f"), Color("18428e"), Color("2354a1"), Color("2c62ae"),
	Color("3f7cc4"), Color("ddd0a6"),
]

const _WATER_CLASSIC := Color(0.17647059, 0.40784314, 0.76862745, 1.0)
const _WATER_INK := Color("5b86b5")
const _WATER_PLATE := Color("3f7cc4")

func band_colors() -> Array[Color]:
	if is_midcentury():
		return MapMidcenturyStyle.BAND_COLORS
	return _BAND_INK if ink else _BAND_CLASSIC

func sea_colors() -> Array[Color]:
	if is_midcentury():
		return MapMidcenturyStyle.SEA_COLORS
	match _sid():
		Style.PLATE:
			return _SEA_PLATE
		Style.INK:
			return _SEA_INK
		_:
			return _SEA_CLASSIC

## Lakes + the coastal shelf; same hue as rivers so all water reads as one.
func water_color() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.WATER
	return _c3(_WATER_CLASSIC, _WATER_INK, _WATER_PLATE)

func river_color() -> Color:
	return water_color()

## ── Roads (road_network_visuals) ────────────────────────────────────────────
## Plate roads are cream CHANNELS, not ribbons: the bed sits in the ground-cream
## family (so on lowland the street nearly is the paper) and the channel read
## comes from solid ink hairline edges. Dashes are survey symbology — dropped.

## Plate streets are the PAPER: one near-white warm cream, the lightest thing on
## the map bar the peaks. Over green country they read as cleared, paved lanes;
## against the dark NPC block fabric they carry ~4:1, and against every player
## block colour at least ~1.85:1 (worst case the khaki urban family) before their
## ink edge is counted. Trunk and local share the bed — width and edge weight
## carry the hierarchy, exactly as they do on a printed plate.
func road_local() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.ROAD_LOCAL
	return _c3(Color("e8c84a"), Color("dfd0a2"), Color("f4efdd"))

func road_trunk() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.ROAD_TRUNK
	return _c3(Color("d97b29"), Color("d4bd8a"), Color("f4efdd"))

func road_casing() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.ROAD_CASING
	if is_plate():
		return _ink_alpha(0.68)
	return Color(0.227, 0.173, 0.094, 0.95) if ink else Color(0.24, 0.16, 0.05, 0.9)

## Trunk roads carry a heavier edge — in the plate idiom that line IS the block
## frontage. Ink/classic have no separate trunk casing.
func road_casing_trunk() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.ROAD_CASING_TRUNK
	return _ink_alpha(0.85) if is_plate() else road_casing()

func road_bridge() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.BRIDGE
	return Color("4a3826") if ink else Color(0.32, 0.2, 0.08)

## ── Ports (port_visuals) ────────────────────────────────────────────────────

func port_dockhouse() -> Color:
	if is_midcentury():
		return Color("d6c9a8")
	return Color("efe9db") if ink else Color(0.96, 0.97, 0.98)

func port_outline() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.INK
	return Color("3a2c18") if ink else Color(0.55, 0.62, 0.69)

func port_pier() -> Color:
	if is_midcentury():
		return Color("baa77f")
	return Color("cbb489") if ink else Color(0.90, 0.92, 0.94)

## Plate: the generated port compound is washed logistics tan. Transparent
## elsewhere = "no override", the generator keeps its own wash.
func port_art_wash() -> Color:
	if is_midcentury():
		return Color("b9a778")
	return Color("c9b88a") if is_plate() else Color(0.0, 0.0, 0.0, 0.0)

## ── Farms (building_visuals farm branch) ────────────────────────────────────

## Classic: one flat green. Ink: a seeded patchwork variant per parcel —
## owner's mix (2026-07-23): pastel yellowish-green, pastel green, pastel
## greenish-brown, plus a light yellow-green.
const _FARM_VARIANTS: Array[Color] = [
	Color("b9c47f"), Color("a2b87c"), Color("a89e6a"), Color("c3c98b"),
]
## Field tints follow the land too — they were regraded for the cream ground and
## sat far too pale on the green one.
func _farm_variants() -> Array[Color]:
	return _FARM_VARIANTS

## The seed key is unchanged across styles on purpose — a parcel keeps its index
## through a style flip, so the patchwork pattern never reshuffles.
func farm_field_variant(seed_key: String) -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.FARM_VARIANTS[RoadHash.pick("ffield|%s" % seed_key, MapMidcenturyStyle.FARM_VARIANTS.size())]
	if not ink:
		return Color("a8d98a")
	var table := _farm_variants()
	return table[RoadHash.pick("ffield|%s" % seed_key, table.size())]

func farm_hatch() -> Color:
	if is_midcentury():
		return Color(0.25, 0.23, 0.16, 0.5)
	if is_plate():
		return Color(0.30, 0.27, 0.16, 0.5)
	return Color(0.30, 0.27, 0.16, 0.7) if ink else Color(0.18, 0.38, 0.18, 0.85)

func farm_hatch_width() -> float:
	if is_midcentury():
		return 1.0
	return 1.1 if ink else 3.0

func farm_outline_color(is_npc: bool) -> Color:
	if is_midcentury():
		return Color(MapMidcenturyStyle.INK, 0.52)
	if not ink:
		return Color.WHITE if is_npc else Color(0.5, 0.5, 0.5)
	return _ink_alpha(0.6)

func farm_outline_width(is_npc: bool) -> float:
	if is_midcentury():
		return 1.0
	if not ink:
		return 2.0 if is_npc else 1.0
	return 1.1

## P3b parcel fabric (ink only): the field base is a parchment path tan that
## shows through the parcel insets as the little farm roads; parcels tint
## from the variant set by their baked index and carry a faint ink hairline.
## The tracks between parcels are paper like the roads, held well back — they are
## dirt lanes, and must not out-read a real road.
func farm_path_color() -> Color:
	if is_midcentury():
		return Color("d8caa3")
	return Color("ddd3ae") if is_plate() else Color("d6c99e")

func farm_parcel_tint(i: int) -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.FARM_VARIANTS[absi(i) % MapMidcenturyStyle.FARM_VARIANTS.size()]
	var table := _farm_variants()
	return table[absi(i) % table.size()]

func farm_parcel_outline() -> Color:
	if is_midcentury():
		return Color(MapMidcenturyStyle.INK, 0.38)
	return _ink_alpha(0.45 if is_plate() else 0.35)

## Farm outbuildings: classic brown; ink = brick barn / mustard silo + ink.
## The barn red is the ONE brick red on the map — see the plate red budget.
func farm_barn_color() -> Color:
	if is_midcentury():
		return Color("a85645")
	return Color("b0483a") if ink else Color(0.50, 0.33, 0.16)

func farm_silo_color() -> Color:
	if is_midcentury():
		return Color("b88e36")
	return Color("c9992e") if ink else Color(0.50, 0.33, 0.16)

## ── P3 building micro-shadow (ink only; transparent = skip) ─────────────────
## Plate replaces the micro-shadow with the extrusion prism — never both.

func building_shadow_color() -> Color:
	if has_cartographic_depth():
		return Color(0.0, 0.0, 0.0, 0.0)
	return Color(INK.r, INK.g, INK.b, 0.13) if ink else Color(0.0, 0.0, 0.0, 0.0)

func building_shadow_offset() -> Vector2:
	if is_midcentury():
		return Vector2(1.25, 1.75)
	return Vector2(1.5, 2.5)

## ── City plate: buildings as extruded blocks ────────────────────────────────
## Top faces keyed by the `_wash_family` output strings (the getter's key domain
## matches its caller exactly). Charcoal/warm-grey masses on cream paper are the
## reference's dominant read; tan and khaki carry the lower-density families.
## Brick red is a RARE accent — courtyard red-majority masses and farm barns only.

## Ownership is INVERTED against ink & wash here, on purpose. The reference's
## signature is a dark block fabric on cream streets, and on this map the fabric
## is the NPC world — so NPC blocks take the reference's warm dark grey, and the
## player's holdings are the COLOURED lots picked out of it. That is the Sanborn
## reading too: colour means a classified, known lot. Ink keeps paper-white NPC.
const _PLATE_BLOCK_TOPS := {
	"navy": Color("58697a"),      # metallurgy — washed steel navy
	"yellow": Color("be9c3c"),    # power
	"pink": Color("9e6b79"),      # refinery — dusty plum
	"lime": Color("8c9757"),      # electrochemistry — olive lime
	"orange": Color("b3743f"),    # manufacturing — muted terracotta
	"grey": Color("9e9382"),      # extraction — warm light grey, clear of NPC
	"mustard": Color("c1922c"),   # logistics
	"blue": Color("77a0b4"),      # water
	"red": Color("c2b08a"),       # urban family default — khaki, NOT red
	"red_mass": Color("b0483a"),  # the brick accent, courtyard masses only
	## Three-way ownership read (owner 2026-08-11), which is also the reference's
	## own block fabric: DECOR is cream, NPC is grey, the player is coloured.
	## Cream took over the paper-white the NPC used to hold.
	"npc": Color("8f8d85"),
	"decor": Color("efe9db"),
	"ruins": Color("7a5f43"),     # decay, not ownership — player AND NPC ruins
}

func plate_block_top(fam: String) -> Color:
	return _PLATE_BLOCK_TOPS.get(fam, _PLATE_BLOCK_TOPS["orange"])

## Gameplay-building palette for the active solid-mass renderer. The legacy
## plate accessor remains unchanged for compatibility tests and old callers.
func block_top(fam: String) -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.gameplay_block_top(fam)
	return plate_block_top(fam)

## Roof linework has to survive on a dark top face, so it flips to a light
## paper tone there; light tops keep the ink.
func roof_motif_color(top: Color) -> Color:
	if has_cartographic_depth() and top.v < 0.55:
		if is_midcentury():
			return Color(MapMidcenturyStyle.PAPER_LIGHT, 0.58)
		return Color(0.894, 0.863, 0.776, 0.55)
	return ink_color()

func courtyard_fill() -> Color:
	if is_midcentury():
		return Color("d7caa5")
	return Color("e3d7b6") if is_plate() else Color("cfc3a2")

## Decorative buildings: the village fabric that belongs to nobody. Cream in
## every style — in ink it reads as the same uncoloured paper as an NPC lot,
## which is correct there; the plate separates them by moving NPC to grey.
func decor_fill() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.gameplay_block_top("decor")
	return Color("efe9db") if ink else Color(0.93, 0.92, 0.89)

## Per-instance value jitter, tightened in plate so a block run stays a family.
func plate_wash_jitter() -> float:
	if is_midcentury():
		return 0.035
	return 0.04 if is_plate() else 0.05

## ── Parchment grain (parchment_overlay) ─────────────────────────────────────
## One seamless noise texture multiplied over the whole map. Ink wants heavy,
## even tooth. The plate is a PRINTED sheet, not a hand-washed one, so its paper
## is quieter and — more importantly — UNEVEN: see parchment_offsets().

func parchment_darkest() -> Color:
	if is_midcentury():
		return Color("ded3b9")
	return Color(0.82, 0.77, 0.67) if ink else Color(0.86, 0.81, 0.72)

func parchment_lightest() -> Color:
	if is_midcentury():
		return Color("fffaf0")
	return Color(1.0, 0.99, 0.96)

## Plate keeps a much gentler floor — ~10% darkening at its deepest against ink's
## ~33% in the blue channel.
const _PARCHMENT_PLATE_DEEP := Color(0.90, 0.88, 0.83)
const _PARCHMENT_PLATE_FAINT := Color(0.945, 0.925, 0.885)

## The ramp SHAPE is what makes the plate's paper patchy instead of uniformly
## grainy. Ink maps noise linearly from dark to light, so every pixel carries
## some grain. The plate parks the middle of the noise range on clean paper, so
## the sheet is untouched across most of its area and the tone only surfaces
## where the noise runs to its extremes — foxing and press-unevenness in
## patches, which is how a printed plate actually ages. Costs nothing: same one
## texture, same single multiply, just more gradient stops.
func parchment_offsets() -> PackedFloat32Array:
	if is_midcentury():
		return PackedFloat32Array([0.0, 0.32, 0.73, 1.0])
	if is_plate():
		return PackedFloat32Array([0.0, 0.38, 0.70, 1.0])
	return PackedFloat32Array([0.0, 1.0])

func parchment_colors() -> PackedColorArray:
	if is_midcentury():
		return PackedColorArray([
			Color("e7ddc7"), parchment_lightest(), parchment_lightest(), Color("f1e9d8"),
		])
	if is_plate():
		return PackedColorArray([
			_PARCHMENT_PLATE_DEEP, parchment_lightest(),
			parchment_lightest(), _PARCHMENT_PLATE_FAINT,
		])
	return PackedColorArray([parchment_darkest(), parchment_lightest()])

## Grain scale. Bigger tile + lower frequency + fewer octaves = broader, softer
## blotches instead of fine speckle; the repeat period doubles too, so the
## tiling is harder to spot.
func parchment_noise_frequency() -> float:
	if is_midcentury():
		return 0.011
	return 0.014 if is_plate() else 0.035

func parchment_noise_octaves() -> int:
	if is_midcentury():
		return 3
	return 3 if is_plate() else 4

func parchment_tile_px() -> int:
	if is_midcentury():
		return 512
	return 512 if is_plate() else 256

## ── P1 ink structure: contours, coast, water lining, river banks ────────────

const INK := Color("3a2c18")
## Plate linework is one cooler grey-sepia — every stroke on the plate map is
## this colour, including the procedural building art (which routes its own
## darker `#2f2b26` through a plate-gated helper).
const _INK_PLATE := Color("4a4136")

## THE plate ink accessor. All plate linework routes through it; the `INK` const
## stays sepia for ink mode.
func ink_color() -> Color:
	if is_midcentury():
		return MapMidcenturyStyle.INK
	return _INK_PLATE if is_plate() else INK

## Current linework ink at `a` alpha — the one constructor for tinted hairlines.
func _ink_alpha(a: float) -> Color:
	var k := ink_color()
	return Color(k.r, k.g, k.b, a)

## Relief band outlines. Classic keeps the darkened-fill stroke; ink draws
## sepia contour hairlines with every 2nd band emphasized (engraved read).
## Plate lightens them so street edges out-weigh contours in the hierarchy.
func contour_color(band: int, fill: Color) -> Color:
	if is_midcentury():
		return _ink_alpha(0.34 if band % 2 == 0 else 0.19)
	if not ink:
		return fill.darkened(0.22)
	if is_plate():
		return _ink_alpha(0.45 if band % 2 == 0 else 0.28)
	return _ink_alpha(0.55 if band % 2 == 0 else 0.35)

func contour_width(band: int) -> float:
	if is_midcentury():
		return 1.35 if band % 2 == 0 else 0.8
	if not ink:
		return 1.5
	if is_plate():
		return 1.6 if band % 2 == 0 else 1.0
	return 2.0 if band % 2 == 0 else 1.2

## Coastline stroke where the landmass meets the sea (owner: keep it bold).
## Transparent in classic = skip drawing.
func coast_color() -> Color:
	if is_midcentury():
		return _ink_alpha(0.78)
	return _ink_alpha(0.9) if ink else Color(0.0, 0.0, 0.0, 0.0)

func coast_width() -> float:
	if is_midcentury():
		return 3.2
	return 4.2

## Engraved water lining: hairlines offset seaward from the coast, fading out.
## Entries are [offset_u, alpha, width]; empty in classic.
func water_lining() -> Array:
	if is_midcentury():
		return [[13.0, 0.23, 1.1], [28.0, 0.12, 0.9]]
	if not ink:
		return []
	if is_plate():
		return [[14.0, 0.28, 1.3], [30.0, 0.16, 1.1]]
	return [[14.0, 0.38, 1.3], [30.0, 0.22, 1.1]]

func lake_shore_color(fill: Color) -> Color:
	if is_midcentury():
		return _ink_alpha(0.67)
	if not ink:
		return fill.darkened(0.25)
	return _ink_alpha(0.75 if is_plate() else 0.7)

func lake_shore_width() -> float:
	if is_midcentury():
		return 1.8
	return 2.2 if ink else 2.0

## River bank casing (ink only): drawn under the water pass, wider by _extra.
func river_casing() -> Color:
	if is_midcentury():
		return _ink_alpha(0.7)
	return _ink_alpha(0.85 if is_plate() else 0.8)

func river_casing_extra() -> float:
	if is_midcentury():
		return 2.7
	return 3.0 if is_plate() else 4.0

## Flow squiggles inside the river (ink only): short darker-blue dashes.
func river_squiggle() -> Color:
	if is_midcentury():
		return Color("4f7287", 0.42)
	if is_plate():
		return Color("2c62ae", 0.5)   # a depth band of the sea ramp, like classic's
	return Color(0.247, 0.435, 0.639, 0.5)

## ── Forests (forest_visuals) ────────────────────────────────────────────────
## Plate: the canopy leaves the dark bottle-green mass and becomes the
## reference's flat olive vegetation, extruded MILD like a low park block.

## The canopy follows the land: with the green ramp back, an olive canopy sat
## within a hair of the ground it stands on and the woods disappeared. Plate
## keeps ink's bottle green and expresses itself through the MILD prism instead.
func forest_base() -> Color:
	if is_midcentury():
		return Color("486747")
	return Color("0d512b")

func forest_lobe_dark() -> Color:
	if is_midcentury():
		return Color("38573d")
	return Color("083b22")

func forest_arc() -> Color:
	if is_midcentury():
		return Color(MapMidcenturyStyle.INK, 0.42)
	## Transparent = skip: the plate canopy is a flat mass, no highlight arcs.
	return Color(0.0, 0.0, 0.0, 0.0) if is_plate() else Color("2d7d3a")

## ── Individual trees (TreeShapes) ───────────────────────────────────────────
## Firs read darker than broadleaves; the shadow is the same warm sepia the rest
## of the map's light model uses, kept translucent so overlapping crowns in a
## bunch do not stack into a black mass.

func tree_fill(is_fir: bool) -> Color:
	if is_midcentury():
		return Color("3f5c42") if is_fir else Color("5c7651")
	if is_fir:
		return Color("2f6a3c") if ink else Color("1f5b2c")
	return Color("3f7f45") if ink else Color("2f7a38")

func tree_outline() -> Color:
	if is_midcentury():
		return _ink_alpha(0.48)
	return _ink_alpha(0.55 if is_plate() else 0.45)

func tree_shadow() -> Color:
	if is_midcentury():
		return Color("40382f", 0.19)
	if is_plate():
		return _ink_alpha(0.24)
	return Color(0.05, 0.16, 0.08, 0.22)

## ── City plate: the one fake-3D model ───────────────────────────────────────
## One light from the NW. Every solid mass is an opaque prism: the wobbled
## polygon is offset toward the SE and drawn UNDER the top fill, so only the
## SE-facing edges show a side face — the reference's raised-cardboard read.
## FULL masses additionally carry a crisp outline; MILD masses draw offset +
## fill and stop. No gradients, no soft shadows anywhere.

enum Extrude { NONE = 0, MILD = 1, FULL = 2 }

## World units, fixed — the prism scales with zoom like the rest of the map.
## ZERO outside plate, which is what makes every extrusion site self-skip.
func extrude_offset(tier: int) -> Vector2:
	if not has_cartographic_depth():
		return Vector2.ZERO
	if is_midcentury():
		match tier:
			Extrude.FULL:
				return Vector2(2.4, 3.0)
			Extrude.MILD:
				return Vector2(1.2, 1.5)
			_:
				return Vector2.ZERO
	match tier:
		Extrude.FULL:
			return Vector2(3.0, 4.0)
		Extrude.MILD:
			return Vector2(1.5, 2.0)
		_:
			return Vector2.ZERO

## Side faces are always derived from the top face — never hand-picked.
## `deep` is the NPC treatment: a heavier side face so a grey NPC block sits
## visibly lower than the cream decor around it (owner 2026-08-11).
func extrude_side(fill: Color, tier: int, deep: bool = false) -> Color:
	var f := (0.27 if tier == Extrude.FULL else 0.17) if is_midcentury() else (0.32 if tier == Extrude.FULL else 0.20)
	if deep:
		f = 0.52
	var c := fill.darkened(f)
	c.a = 1.0
	return c

## FULL masses only — the single full-alpha linework on the plate map.
func extrude_outline() -> Color:
	return _ink_alpha(1.0)

func extrude_outline_width() -> float:
	if is_midcentury():
		return 1.2
	return 1.5

## ── P2 road stroke: geometry post-pass + dashed symbology ───────────────────

func road_width(trunk: bool) -> float:
	if is_midcentury():
		return 8.2 if trunk else 5.0
	if is_plate():
		return 9.5 if trunk else 5.5
	if not ink:
		return 7.0 if trunk else 4.5
	return 6.75 if trunk else 4.5

func road_casing_width(trunk: bool) -> float:
	if is_midcentury():
		# The arterial hierarchy belongs to the printed street boundary, not a
		# modern centre stripe. Local edges retain their quiet hairline.
		return road_width(trunk) + (4.0 if trunk else 2.2)
	if is_plate():
		return road_width(trunk) + 3.0   # ~1.5u of street edge each side
	return road_width(trunk) + (3.2 if ink else 2.5)

## Drawn-polyline restyle (ink only, spec §3c Class 2): RDP simplify kills the
## A*-grid meander, then a seeded hand wobble goes back on top. The LOGIC
## geometry, tiles, bridges and gameplay flags are never touched.
func road_simplify_eps() -> float:
	if is_midcentury():
		return 8.0
	return 10.0 if ink else 0.0

## [subdivide step u, perpendicular amplitude u]; empty = no wobble (classic).
func road_wobble() -> Array:
	if is_midcentury():
		return [22.0, 1.1]
	return [20.0, 1.5] if ink else []

## Casing dash pattern [dash u, gap u] (ink only; classic casing is solid).
func road_dash() -> Array:
	if is_midcentury():
		return [16.0, 10.0]
	return [14.0, 8.0]

## False = the casing is drawn solid instead of dashed. Plate bounds its streets
## with the same solid block-edge line the rest of the idiom uses.
func road_casing_dashed() -> bool:
	if is_midcentury():
		return false
	return not is_plate()

## Pier plank tick hairlines (ink only).
func pier_plank_color() -> Color:
	if is_midcentury():
		return _ink_alpha(0.4)
	return _ink_alpha(0.45)

## Trunk roads are the CROSS-CONTINENT ARTERIES (the bake's long-haul spine
## tier) — in ink mode they carry a dashed centre line on top of the bed.
## Empty in plate: the heavier trunk casing already carries the hierarchy.
func trunk_center_dash() -> Array:
	if is_midcentury():
		return []
	return [] if is_plate() else [11.0, 9.0]

func trunk_center_color() -> Color:
	if is_midcentury():
		return _ink_alpha(0.38)
	return _ink_alpha(0.55)

func trunk_center_width() -> float:
	if is_midcentury():
		return 1.0
	return 1.2
