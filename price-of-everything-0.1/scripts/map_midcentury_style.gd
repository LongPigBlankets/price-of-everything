class_name MapMidcenturyStyle
extends RefCounted
## Independent art-direction table for the optional inhabited mid-century map.
##
## This file deliberately owns every new-style visual decision. MapStyle only
## delegates to it while `midcentury` is active; none of these values are used
## by classic, ink, or city-plate rendering.

const INK := Color("40382f")
const PAPER := Color("eadfbe")
const PAPER_LIGHT := Color("f2e8cc")
const SHADOW := Color("4a4036", 0.74)

## Exact copies of the pre-city-plate ink terrain/water ramps. They live here
## so mid-century rendering is independent of the currently selected legacy
## style while retaining the requested historical palette source.
const BAND_COLORS: Array[Color] = [
	Color("55603c"), Color("ddd0a6"), Color("9aa465"), Color("a3ad6e"),
	Color("adb377"), Color("c1bd85"), Color("c9c287"), Color("cdb47e"),
	Color("bf9a6a"), Color("a98156"), Color("8d6a47"), Color("efe6ce"),
]

const SEA_COLORS: Array[Color] = [
	Color("2e4468"), Color("35507a"), Color("46648c"), Color("4f6f99"),
	Color("6b8fb5"), Color("ddd0a6"),
]

const WATER := Color("5b86b5")
const ROAD_LOCAL := Color("eadfbe")
const ROAD_TRUNK := Color("e2d0a5")
const ROAD_CASING := Color("40382f", 0.76)
const ROAD_CASING_TRUNK := Color("40382f", 0.92)
const BRIDGE := Color("5a4737")

const FARM_VARIANTS: Array[Color] = [
	Color("b5b779"), Color("98a16f"), Color("a99a69"), Color("c2bd82"),
]

## Real gameplay industries: stronger than the city fabric, but still printed
## and restrained. Colour identifies a landmark; it does not flood a district.
const GAMEPLAY_BLOCK_TOPS := {
	"navy": Color("737d81"),
	"yellow": Color("a58c5b"),
	"pink": Color("997978"),
	"lime": Color("828769"),
	"orange": Color("977257"),
	"grey": Color("8c867b"),
	"mustard": Color("9c8463"),
	"blue": Color("7b8c8f"),
	"red": Color("908278"),
	"red_mass": Color("94695c"),
	# NPC-owned buildings are WHITE, in every style (owner, 2026-08-28). This was a warm grey
	# while midcentury was an opt-in look; now that it ships, white is the rival cue and the
	# player's livery is the only colour on the map that means ownership. Matches
	# building_visuals.NPC_WHITE so the two styles agree on what a rival looks like.
	"npc": Color("efe9db"),
	"decor": Color("a49f91"),
	"ruins": Color("785c43"),
}

## Ordinary urban fabric is deliberately quieter and darker than gameplay
## industries. Core sets lean charcoal; outskirts introduce khaki and tan.
const URBAN_CORE: Array[Color] = [
	Color("625f59"), Color("6d6961"), Color("777269"), Color("817a6e"),
]
const URBAN_MIXED: Array[Color] = [
	Color("77736a"), Color("858075"), Color("918878"), Color("8b866c"),
]
const URBAN_EDGE: Array[Color] = [
	Color("8f897c"), Color("9c927c"), Color("9b936d"), Color("a69776"),
]
const URBAN_CLUSTER_DARK: Array[Color] = [
	Color("4f4d49"), Color("5b5752"), Color("67615a"),
]
const URBAN_CLUSTER_WARM: Array[Color] = [
	Color("706b65"), Color("7d766d"), Color("898075"),
]
const URBAN_CLUSTER_KHAKI: Array[Color] = [
	Color("706e5e"), Color("807a63"), Color("90866b"),
]
const PARKS: Array[Color] = [
	Color("7f8e61"), Color("89976d"), Color("72835b"), Color("939d72"),
]
const INDUSTRIAL_YARDS: Array[Color] = [
	Color("b8aa83"), Color("c1b38d"), Color("afa783"), Color("c5b895"),
]
const VACANT_LOTS: Array[Color] = [
	Color("d1c59f"), Color("c8bd98"), Color("d7caa6"),
]

## Full-map settlement plate. It is deliberately close to the ordinary urban
## family and slightly translucent so terrain/geography retain first read.
const FAR_URBAN_PLATE := Color("65625c", 0.86)

## ── Rare industrial landmark tier ───────────────────────────────────────────
## The ORDINARY gameplay-industry tier above keeps its halved chroma (V4.08b);
## that discipline is unchanged. A single-digit deterministic subset of the
## largest real works is promoted to this landmark tier instead, so a handful of
## oxide/rust industrial anchors survive world scale the way the reference plans'
## rare strong landmarks do.
##
## The bound is explicit. Saturation sits ABOVE the ordinary mid-century industry
## tier and strictly BELOW the full category colour that failed as saturated
## close-zoom colour fields (V4.08a): the tones below are ~0.55 saturation, the
## ordinary tier is ~0.42 and the full plate category colours reach 0.65–0.77.
## Only these few compounds ever use them, and their near-zoom form is a paper
## wash — never a filled roof.
const INDUSTRY_LANDMARK_TONES: Array[Color] = [
	Color("a8674c"),  # oxide red
	Color("9c6a4a"),  # rust
	Color("b17a58"),  # salmon brick
]

## Deterministic per-compound tone. Seeded through RoadHash like every other
## mid-century colour decision; never wall-clock, never global RNG.
static func industry_landmark_tone(key: String) -> Color:
	return INDUSTRY_LANDMARK_TONES[RoadHash.pick(
		"mc-industry-landmark|%s" % key, INDUSTRY_LANDMARK_TONES.size())]

## World-scale plate accent. Drawn only inside the existing far-zoom plate LOD,
## replacing the quiet grey for this compound's works footprint alone.
static func industry_landmark_plate(key: String) -> Color:
	return Color(industry_landmark_tone(key), 0.93)

## Near-zoom works yard/apron wash for a landmark compound. Warmer and slightly
## stronger than INDUSTRIAL_YARDS, still a printed wash well under the category
## colour, so the landmark keeps one identity across zoom levels.
static func industry_landmark_yard(key: String) -> Color:
	return industry_landmark_tone(key).lerp(PAPER, 0.38)

static func gameplay_block_top(family: String) -> Color:
	return GAMEPLAY_BLOCK_TOPS.get(family, GAMEPLAY_BLOCK_TOPS["orange"])

static func industrial_apron(family: String) -> Color:
	return gameplay_block_top(family).lerp(PAPER, 0.54)

static func urban_block(key: String, density: float) -> Color:
	var table: Array[Color]
	if density >= 0.78:
		table = URBAN_CORE
	elif density >= 0.5:
		table = URBAN_MIXED
	else:
		table = URBAN_EDGE
	var base: Color = table[RoadHash.pick("mc-block|%s" % key, table.size())]
	var jitter := (float(RoadHash.pick("mc-value|%s" % key, 101)) / 100.0 - 0.5) * 0.055
	return Color.from_hsv(base.h, base.s, clampf(base.v + jitter, 0.0, 1.0))

static func urban_block_cluster(cluster_key: String, piece_key: String, density: float) -> Color:
	var family_roll := RoadHash.pick("mc-cluster-family|%s" % cluster_key, 100)
	var table := URBAN_CLUSTER_DARK
	if family_roll >= 78:
		table = URBAN_CLUSTER_KHAKI
	elif family_roll >= 46:
		table = URBAN_CLUSTER_WARM
	var base: Color = table[RoadHash.pick("mc-cluster-piece|%s" % piece_key, table.size())]
	if density < 0.78:
		base = base.lightened((0.78 - density) * 0.13)
	var jitter := (float(RoadHash.pick("mc-cluster-value|%s" % piece_key, 101)) / 100.0 - 0.5) * 0.028
	return Color.from_hsv(base.h, base.s, clampf(base.v + jitter, 0.0, 1.0))

static func park(key: String) -> Color:
	return PARKS[RoadHash.pick("mc-park|%s" % key, PARKS.size())]

static func industrial_yard(key: String) -> Color:
	return INDUSTRIAL_YARDS[RoadHash.pick("mc-yard|%s" % key, INDUSTRIAL_YARDS.size())]

static func vacant_lot(key: String) -> Color:
	return VACANT_LOTS[RoadHash.pick("mc-vacant|%s" % key, VACANT_LOTS.size())]

static func far_urban_plate() -> Color:
	return FAR_URBAN_PLATE

static func raised_roof_top(base: Color, key: String, context: String) -> Color:
	var paper_mix := 0.13 + float(RoadHash.pick("mc-roof-cap|%s|%s" % [context, key], 6)) * 0.012
	return base.lerp(PAPER_LIGHT, paper_mix)
