extends RefCounted
## When is a camera move worth repainting a streaming layer?
##
## Every layer here draws its content `margin` world units beyond the visible rect, so its
## picture stays correct until the view has travelled that far. They were nonetheless testing
## the view rect for EXACT equality, which holds for about one frame in a thousand: any
## sub-pixel drift repainted the whole layer.
##
## That costs nothing while the camera is still, and a great deal while it moves — and the
## camera moves at exactly the worst moment. Pressing Begin starts a one-second intro zoom, so
## for the whole of that second the authored fabric, the roads, the hills and the buildings
## each repainted EVERY frame. Measured with tools/begin_click_probe.tscn: 24,454 draw calls on
## the first frame after the click, decaying over ~7 s as the view settled.
##
## THE TOLERANCE IS DERIVED FROM THE MARGIN, not chosen. A layer that streams more slack
## tolerates more drift automatically, and a margin that changes carries its tolerance with it
## — the alternative is two numbers that mean the same thing and quietly stop agreeing.

## Fraction of a layer's streaming margin the view may drift before a repaint is worth it.
## A quarter, so that position drift and size growth TOGETHER can move an edge by at most half
## the margin, leaving the rest as headroom against pop-in.
const TOLERANCE := 0.25


## True when `now` is close enough to the view a layer last drew for that its picture is still
## right. Callers keep `drawn` as the rect they actually painted, NOT the latest polled view,
## or the drift accumulates a frame at a time and the test never fires.
static func settled(now: Rect2, drawn: Rect2, margin: float) -> bool:
	if drawn.size.x <= 0.0 or drawn.size.y <= 0.0:
		return false          # nothing painted yet — always draw the first time
	var eps := margin * TOLERANCE
	return absf(now.position.x - drawn.position.x) <= eps \
		and absf(now.position.y - drawn.position.y) <= eps \
		and absf(now.size.x - drawn.size.x) <= eps \
		and absf(now.size.y - drawn.size.y) <= eps
