extends RefCounted
## Shared pipe-frame helpers for panels.
##
## The DARK BROWN pipe is the same frame the tile view panel uses: a 9-slice of
## tile_modal_pipe_frame.png whose transparent-cornered texture has an opaque dark-navy
## centre — so this single StyleBoxTexture supplies BOTH the panel's navy background AND
## the brown pipe border. Override a Panel/PanelContainer's "panel" stylebox with it to
## get the frame and drop any previous coloured outline in one move. (The BRASS pipe is a
## separate transparent-centre overlay — see brass_pipe_frame.gd.)

const DARK_BROWN_FRAME := "res://assets/ui/tile_modal_pipe_frame.png"
const FRAME_SLICE := 32.0    # the pipe's 9-slice corner (source px == on-screen px)
const FRAME_OUTSET := 11.0   # the frame straddles the panel edge by this much

static func dark_brown_stylebox(content_margin: float = 22.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = load(DARK_BROWN_FRAME)
	sb.draw_center = true
	sb.texture_margin_left = FRAME_SLICE
	sb.texture_margin_top = FRAME_SLICE
	sb.texture_margin_right = FRAME_SLICE
	sb.texture_margin_bottom = FRAME_SLICE
	sb.expand_margin_left = FRAME_OUTSET
	sb.expand_margin_top = FRAME_OUTSET
	sb.expand_margin_right = FRAME_OUTSET
	sb.expand_margin_bottom = FRAME_OUTSET
	sb.content_margin_left = content_margin
	sb.content_margin_top = content_margin
	sb.content_margin_right = content_margin
	sb.content_margin_bottom = content_margin
	return sb
