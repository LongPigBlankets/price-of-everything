extends RefCounted
## The one question asked before a building's goods leave Local Suppliers, on the DS2 sheet
## (scripts/ds2/destination_sheet.gd): titled Change supplier (inputs) or Change destination (outputs), what the
## change may cost for the side and destination chosen, Do not show again, and Cancel and Confirm at the two ends
## of the row. Nothing else asks: the old surplus prompt is gone.
const Sheet := preload("res://scripts/ds2/destination_sheet.gd")
## Ticked on the sheet: no supplier change asks again this session.
static var skip_confirmation := false

const OUTPUT_TO_STOCKPILE := "Stockpiles may accumulate your goods if you don't sell the surplus. View the Tile stockpile to change that, because by default it does not sell surplus."
const OUTPUT_TO_MARKET := "Selling to market is a great way to integrate but be aware that transport and port fees may eat into your profit. Improve the infrastructure and use the right transport method to keep costs low."
## The words of OUTPUT_TO_STOCKPILE that link to the tile's Stockpile tab.
const STOCKPILE_LINK := "Tile stockpile"


static func title_for(context: Dictionary) -> String:
	return "Change supplier" if str(context.get("side", "")) == "input" else "Change destination"


## The sheet's words for the side and destination the player chose:
##   context {side: "input"|"output", destination: "market"|"stockpile"|"tile"|"other", good: good_id, tile: tile_id}
## Anything not given reads as the building's goods, both sides.
static func message_for(context: Dictionary) -> String:
	var side := str(context.get("side", ""))
	var destination := str(context.get("destination", ""))
	var what := str({"input": "the source of your inputs", "output": "the destination of your outputs"}.get(side,
		"the source or destination of your goods"))
	var parts: Array = ["You're about to change %s. This could impact your profit." % what]
	if side == "output" and destination in ["stockpile", "tile", "other"]:
		parts.append(OUTPUT_TO_STOCKPILE)
	elif side == "output" and destination == "market":
		parts.append(OUTPUT_TO_MARKET)
	parts.append("Do you want to continue?")
	return "\n\n".join(parts)


## Asks before leaving Local Suppliers (returning to them never asks). `apply` makes the change and answers
## whether it took; `canceled` runs when the player backs out.
static func request(parent: Node, mode: String, apply: Callable, canceled: Callable = Callable(), context: Dictionary = {}) -> void:
	if mode == "middleman" or skip_confirmation:
		apply.call()
		return
	var sheet := Sheet.new()
	sheet.name = "TransportSupplierConfirmation"
	sheet.title_text = title_for(context)
	sheet.message = message_for(context)
	if sheet.message.contains(STOCKPILE_LINK):
		sheet.link_phrase = STOCKPILE_LINK
		sheet.link_tile = str(context.get("tile", ""))
	sheet.confirmed.connect(func() -> void:
		if apply.call(): skip_confirmation = sheet.dont_show_again()
		sheet.queue_free(), CONNECT_ONE_SHOT)
	sheet.canceled.connect(func() -> void:
		if canceled.is_valid(): canceled.call()
		sheet.queue_free(), CONNECT_ONE_SHOT)
	parent.add_child(sheet)
