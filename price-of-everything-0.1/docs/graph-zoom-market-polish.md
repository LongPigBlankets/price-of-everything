# Graph zoom and market routes

Goods graph allows up to 1.5x in both full and focused views. Empire furniture scales up to 1.5x; its existing 2.5x camera limit is preserved. This interprets 1.5 as zoom-in magnification.

Empire edge goods chips render on a dedicated mouse-ignoring overlay above cards, port art and routed lines. Their existing hover rectangles remain registered on the world.

Export-to-market routes use brass gold. A white glow travels along their actual routed arc length, repeating every 2.5 seconds independently of route length. Glow paths are cached during graph redraw and animated on a separate layer, avoiding per-frame layout/routing work. Dashed potential routes retain their dashed base line. Market-input routes retain their existing styling.
