extends RefCounted
## Screen-space LODs, with hysteresis: zooming/rotating never rebuilds the company.
const NAMES := ["far", "medium", "near"]
const CELLS := [12.0, 8.0, 4.0]
const TEXTURES := [512, 1024, 2048]
# Pixels per world unit in the logical canvas; independent of display pixel density.
static func choose(ppu: float, current: int = -1) -> int:
	if current == 0 and ppu < 0.84: return 0
	if current == 1 and ppu >= 0.68 and ppu < 1.75: return 1
	if current == 2 and ppu >= 1.45: return 2
	return 0 if ppu < 0.76 else (1 if ppu < 1.60 else 2)
