extends RefCounted
const Sheet := preload("res://scripts/ds2/destination_sheet.gd")
## Ticked on the sheet: no supplier change asks again this session.
static var skip_confirmation := false

const OUTPUT_TO_MARKET := "The intermediary will no longer buy your output. A bridging loan will cover you during transit to the port, but long distances may be expensive unless served by advanced infrastructure. Invest in infrastructure to reduce travel times and increase capacity."
const OUTPUT_TO_STOCKPILE := "The intermediary will no longer buy your output. This may decrease your revenue if you don't use the output in other recipes. If unused, the output will accumulate in the stockpile. If you want to sell the unused surplus, do so in the Stockpile tab."
## The words of OUTPUT_TO_STOCKPILE that link to the tile's Stockpile tab.
const STOCKPILE_LINK := "Stockpile tab"

## What leaving the intermediary means, for the side and destination the player chose:
##   context {side: "input"|"output", destination: "market"|"stockpile"|"tile", good: good_id, tile: tile_id}
## "stockpile" is the building's own tile, "tile" another tile's stockpile: both read the same. Anything not
## given reads as the whole building or tile, both sides.
static func message_for(context: Dictionary) -> String:
	var good := str(context.get("good", ""))
	var what := Catalog.get_display_name(good).to_lower() if good != "" else "these goods"
	var side := str(context.get("side", ""))
	match [side, str(context.get("destination", ""))]:
		["output", "market"]:
			return OUTPUT_TO_MARKET
		["output", "stockpile"], ["output", "tile"]:
			return OUTPUT_TO_STOCKPILE
		["input", "market"]:
			return "The intermediary stops supplying %s. You will buy it at the global market through a port, paying freight and the port charge." % what
		["input", "stockpile"]:
			return "The intermediary stops supplying %s. It will come from your stockpile, so keep it stocked." % what
	return "The intermediary stops handling %s. Your own transport and the ports take over, which costs freight and port charges." % what


## The sheet's title and its confirm key: a destination for outputs, a supplier for anything else.
static func title_for(context: Dictionary) -> String:
	return "Change destination" if str(context.get("side", "")) == "output" else "Change supplier"


## Asks before leaving the intermediary (returning to it never asks), on the DS2 sheet. `apply` makes the
## change and answers whether it took; `canceled` runs when the player backs out.
static func request(parent: Node, mode: String, apply: Callable, canceled: Callable = Callable(), context: Dictionary = {}) -> void:
	if mode == "middleman" or skip_confirmation:
		apply.call()
		return
	var sheet := Sheet.new()
	sheet.name = "TransportSupplierConfirmation"
	sheet.title_text = title_for(context)
	sheet.confirm_text = sheet.title_text
	sheet.message = message_for(context)
	if sheet.message == OUTPUT_TO_STOCKPILE:
		sheet.link_phrase = STOCKPILE_LINK
		sheet.link_tile = str(context.get("tile", ""))
	sheet.confirmed.connect(func() -> void:
		if apply.call(): skip_confirmation = sheet.dont_show_again()
		sheet.queue_free(), CONNECT_ONE_SHOT)
	sheet.canceled.connect(func() -> void:
		if canceled.is_valid(): canceled.call()
		sheet.queue_free(), CONNECT_ONE_SHOT)
	parent.add_child(sheet)
