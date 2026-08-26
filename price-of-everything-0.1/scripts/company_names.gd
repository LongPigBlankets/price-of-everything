extends RefCounted
## Cosmetic company names shared by NPC building ownership and the league table.

const NAMES := [
	"Ashworth Industrials", "Meridian Foundries", "Blackwater Holdings", "Calderon & Vance",
	"Ironbridge Group", "Nordvik Materials", "Halcyon Works", "Sterling Combine",
	"Thornfield Mills", "Vantage Refineries", "Crown Metalworks", "Pemberton Chemical",
	"Drexel Manufacturing", "Grayson Foundry Co.", "Aldridge Consolidated", "Whitmore Petrochem",
]

## WHAT EACH NAMED FIRM ACTUALLY MAKES.
##
## A name that says what a company does is a promise, and the goods table was breaking it:
## Pemberton Chemical mining bauxite, Whitmore Petrochem rolling steel. Rivals were drawn per
## good by a plain shuffle over the whole roster, which reads as noise the moment a name means
## something.
##
## A firm listed here competes ONLY in what it matches; anything absent from this table is a
## generic industrial and competes everywhere, which is what keeps every good populated. Match
## on whichever of the three is the honest description of the firm:
##
##   categories  the good's `category` column (chems, metals, petrochem, vehicles, ...)
##   tiers       its `goods_graph_tier` (raw, processed, intermediate, finished, apex)
##   goods       explicit internal names, when neither column carves the right shape
##
## Deliberately GENERIC, though the names hint at industry: Ashworth Industrials, Blackwater
## Holdings, Calderon & Vance, Halcyon Works, Sterling Combine, Aldridge Consolidated — and
## Thornfield Mills, because a mill rolls steel or grinds grain depending on who you ask, and a
## guess there would be a worse promise than none.
const THEMES := {
	# Owner's calls.
	"Pemberton Chemical": {"categories": ["chems"]},
	"Nordvik Materials": {"tiers": ["raw"]},
	"Whitmore Petrochem": {"goods": [
		"crude_oil", "processed_oil", "pet_coke", "fuels", "ethylene", "plastics", "rubber"]},
	# Read off the same names. Refineries take the refining half of the petrochem line —
	# polymers (plastics, rubber, pvc) are a different plant, so they stay with Whitmore.
	"Vantage Refineries": {"goods": ["crude_oil", "processed_oil", "pet_coke", "fuels", "ethylene"]},
	"Meridian Foundries": {"categories": ["metals"]},
	"Grayson Foundry Co.": {"categories": ["metals"]},
	"Crown Metalworks": {"categories": ["metals"]},
	"Ironbridge Group": {"categories": ["metals"]},
	"Drexel Manufacturing": {"categories": ["vehicles", "electronics"]},
}


## Does `company_name` compete in `good`? `good` is a Catalog goods record. Unlisted firms are
## generic and compete in everything.
static func competes_in(company_name: String, good: Dictionary) -> bool:
	var theme: Variant = THEMES.get(company_name, null)
	if typeof(theme) != TYPE_DICTIONARY:
		return true
	var t: Dictionary = theme
	if (t.get("categories", []) as Array).has(str(good.get("category", ""))):
		return true
	if (t.get("tiers", []) as Array).has(str(good.get("goods_graph_tier", ""))):
		return true
	return (t.get("goods", []) as Array).has(str(good.get("internal_name", "")))
