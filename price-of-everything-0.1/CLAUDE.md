# Working notes for this repo

## Text contrast — the standing rule

**Never place grey text on a navy, dark-navy or near-black panel. Default to the design
system's off-white, `DS.PALETTE.TEXT` (#E8EEF7).**

This has come back three times now, so it is written down rather than re-litigated:

- `DS.PALETTE.TEXT_DIM` is a *secondary* tone for a light-ish surface, not a way to make
  text quieter on a dark one. On the panel navies it reads as grey-on-grey at the sizes
  the UI actually uses (11–14 px).
- `DS.PALETTE.TEXT_DISABLED` is for **disabled controls only**, where low contrast IS the
  signal. Never use it for text a player is meant to read.
- Colour that carries meaning is unaffected: `OK` green, `WARN` amber, `DANGER` red, the
  cream `ACCENT`. Those are semantic, not decoration.

When placing any label, check what is behind it first. If the answer is `BG_PANEL`,
`BG_CARD`, `BG_INSET` or the top bar's navy, the colour is `DS.PALETTE.TEXT` unless the
label is saying something semantic.

To make text feel secondary on a dark surface, use **size or weight**, not a greyer
colour.

## Design system

Style through the `DS` autoload (`scripts/ds.gd`) — `theme_type_variation` of "Title",
"Section", "Body", "Numeric", "Card", "Outlined", "Inset". Avoid `add_theme_*_override`
in panel code except for the per-instance colour/size tweaks the variations do not cover.

## Verification

`docs/` holds the specs; `tools/run_tests.py` runs the suite. Two perf tests
("road works: zero frames over 8 ms", "B4: ≤2% frames over 8 ms") sit close to their
budgets and fail intermittently on a loaded machine — a failure in only those two is
pass-equivalent.
