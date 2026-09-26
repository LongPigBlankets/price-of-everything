extends RefCounted
## DS2: the sizes every DS2 panel shares, so the tile view, Building Detail and the ledger agree.
##
##   GOOD_ICON       a good's icon (in its well, on a tile, on a card) is never drawn smaller than this
##   CARD_PAD_Y      the room above and below a building card's contents
##   CARD_H          a building card's height: a good's well and that room. Every building card (the tile
##                   view's buildings and infrastructure, the ledger's rows) is at least this tall.
##   PLATE_PAD       the room between a plate's edge and the plates it holds (the tile view's door, its navy
##                   sheet and the plastic cases in it)

const GOOD_ICON := 72
const CARD_PAD_Y := 8.0
const CARD_H := GOOD_ICON + 2.0 * CARD_PAD_Y
const PLATE_PAD := 12
