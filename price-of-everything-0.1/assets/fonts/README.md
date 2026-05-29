# Fonts

All 6 TTFs are already in this folder — downloaded from the official open-source repos:

| File | Source | Role (see `scripts/ds.gd`) |
|---|---|---|
| `BebasNeue-Regular.ttf` | google/fonts | `theme_type_variation = "Title"` — 48px panel / tile titles |
| `BarlowCondensed-Bold.ttf` | google/fonts | `"Section"` — 22px uppercase headers (0.08em tracking via FontVariation) |
| `BarlowCondensed-SemiBold.ttf` | google/fonts | `"BuildingName"` — 22px building / row names |
| `IBMPlexSans-Regular.ttf` | IBM/plex | `"Caption"` — 12px muted metadata |
| `IBMPlexSans-Medium.ttf` | IBM/plex | `"Body"` — 14px default body / stats / labels |
| `IBMPlexSans-SemiBold.ttf` | IBM/plex | `"Numeric"` — 16px numbers / percentages |

If you ever delete a TTF, the theme falls back to the engine default for that role with a console warning — UI still works.

## Refreshing

```sh
cd assets/fonts
# Google Fonts (jsDelivr CDN over google/fonts repo)
curl -fsSL -o BebasNeue-Regular.ttf \
  https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/bebasneue/BebasNeue-Regular.ttf
curl -fsSL -o BarlowCondensed-Bold.ttf \
  https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/barlowcondensed/BarlowCondensed-Bold.ttf
curl -fsSL -o BarlowCondensed-SemiBold.ttf \
  https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/barlowcondensed/BarlowCondensed-SemiBold.ttf
# IBM Plex Sans (IBM/plex repo — was moved to packages/plex-sans/ in 2023)
BASE="https://raw.githubusercontent.com/IBM/plex/master/packages/plex-sans/fonts/complete/ttf"
curl -fsSL -o IBMPlexSans-Regular.ttf  "$BASE/IBMPlexSans-Regular.ttf"
curl -fsSL -o IBMPlexSans-Medium.ttf   "$BASE/IBMPlexSans-Medium.ttf"
curl -fsSL -o IBMPlexSans-SemiBold.ttf "$BASE/IBMPlexSans-SemiBold.ttf"
```
