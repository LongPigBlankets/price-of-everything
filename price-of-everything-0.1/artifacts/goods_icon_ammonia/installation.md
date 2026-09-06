# Installed approved ammonia v4

Approved by owner: "great, add this to the game".

Copied the approved v4 master and derived 450px/256px images into both default goods tiers and `alternate_icons`. An older ammonia icon existed in medium/small; those PNGs are retained in `previous_main/`. The existing goods loader searches main tiers only, so installation into those tiers makes the approved artwork appear without changing loader behavior.

Godot editor import completed for all six images. The complete `[params]` blocks match the established iron-ore icon in each tier, including mipmaps and alpha-border settings. Headless `GoodIcons.texture_for` and `resolve_path` select the new main images with sizes800×800,450×450,256×256. Alternate textures load at the same dimensions. Runtime output is in `installation_runtime_check.log`.

The headless environment emitted macOS certificate and editor-settings-write warnings, unrelated to image import. Runtime texture assertions all passed.
