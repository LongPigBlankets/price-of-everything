# Patchable exports without making the antivirus problem worse — evaluation

9 August 2026. **Evaluation only — nothing built.** Question: how do we ship so that a future
ruleset / data / asset change doesn't mean redownloading the whole game, without triggering more
antivirus blocks on itch?

## The tension to name first

The obvious answer to "update without a full redownload" is an updater: a program that reaches the
internet, downloads files, and writes them next to itself. **That is the exact behaviour profile
Windows Defender and SmartScreen flag on unsigned indie binaries.** The naive version of this
request makes the AV problem materially worse. Any solution has to route the downloading through
something that already has reputation, or avoid downloading entirely.

## What is actually causing the blocks

Checked, not guessed, in `export_presets.cfg`:

| preset | finding |
|---|---|
| Windows Desktop | `codesign/enable=false` — **the .exe is unsigned** |
| macOS | `codesign/identity=""` — no Developer ID, so ad-hoc at best |
| Linux | `binary_format/embed_pck=true` — one large opaque binary |

**The download blocks are about signing, not structure.** SmartScreen warns on unsigned executables
with no download reputation; Gatekeeper quarantines un-notarised .app bundles. No amount of PCK
re-architecture changes that, and a code signature fixes it regardless of how the game is packaged.
These are two independent problems that have been getting conflated.

Two aggravating factors worth knowing: Godot binaries have a long history of heuristic false
positives, and a **single fat binary with an embedded PCK** (the Linux preset today, and the shape
people often reach for) resembles a self-extracting dropper far more than `exe` + `pck` does.

## The size picture — measured

Current builds are ~605–616 MB per platform, from 341 MB of source assets:

| | size | note |
|---|---|---|
| `assets/icons/goods` | **214 MB** | ~206 PNGs, several over 2 MB each |
| `assets/icons/buildings` | 17 MB | |
| `assets/tile_banners` | 31 MB | |
| `assets/building_banners` | 27 MB | |
| `assets/audio` | 20 MB | |
| `assets/loading` | 18 MB | the 1350-frame film |
| `data` (all CSV) | 11 MB | |

**Goods icons alone are roughly a third of the download**, averaging over 1 MB each for what renders
at icon size. That is the single largest lever here and it has nothing to do with patching: getting
the base build from ~600 MB to ~250 MB does more for the update problem than any delta mechanism,
because at that size a full redownload stops being the thing anyone complains about. It also
shortens every future patch, since a patch of a smaller asset is a smaller patch.

## Options

### A. itch app + butler channels — **recommended, and it is the actual answer**

butler already ships delta patches over itch's wharf protocol; the itch app applies them
automatically. A data-only change becomes a few-MB patch with **zero custom code and zero new
binaries**. The downloading is done by the itch app — signed, known, and already trusted by AV —
so this satisfies "no new AV surface" by construction.

- Cost: users who grab the raw zip from the web page still get a full download. Only itch-app
  installs get deltas. That is a marketing nudge ("install through the app"), not an engineering one.
- Also gives free per-channel builds (`windows-demo`, `macos-demo`, …) and rollback.
- Effort: near zero. It is a push command.

### B. Separate PCK + runtime mount — **already half-configured, worth finishing**

Windows is already `embed_pck=false`, so it ships `.exe` + `.pck`. Godot can mount an extra pack at
runtime with `ProjectSettings.load_resource_pack(path, true)`, whose files override `res://`. Ship
`game.pck` plus a later `patch_01.pck` containing only what changed.

- Makes butler's diffs smaller and better-localised, so it compounds with (A).
- **Ordering trap:** `Catalog` is autoload #4 and reads every CSV in `_ready()`. A patch pack must
  mount before that — so it needs an autoload placed first, or a bootstrap scene. Getting this
  wrong fails silently as "the patch did nothing".
- Set `embed_pck=false` on macOS and Linux too, for the same reason and for consistency.
- Does not reduce the first download.

### C. Loose data next to the executable — **cheapest real win**

Move the runtime CSVs (and any ruleset files) out of the PCK to a `data/` folder beside the
executable, loaded through `AppPaths`. A balance patch then becomes *a text file*, with no binary
update at all.

- The plumbing already exists: `scripts/app_paths.gd` resolves a portable base folder next to the
  exe, handles the macOS bundle parent and app translocation, and falls back to the user-data dir
  when the install location is read-only. This is exactly the resolver such a scheme needs.
- Fits the project's own doctrine — content is CSV, loaded at runtime by `catalog.gd` — and lines
  up with the ruleset seam already planned for the New Game screen.
- Watch the known gotcha: the macOS export needed a CSV **keep-mode** fix or the catalog loaded
  empty. Moving CSVs out of the pack changes that path again and must be verified by booting a
  real export, not by reasoning.
- Side effect: players can edit the numbers. For a demo that is arguably a feature; decide it
  deliberately rather than discovering it.

### D. Custom in-game updater — **reject**

Network access plus self-directed writes next to an unsigned executable. This is the worst case for
exactly the problem being solved, and it duplicates what butler already does properly.

## Recommended shape

1. **Sign the binaries.** This is the AV fix and it is independent of everything else. Windows: an
   OV or EV certificate (EV carries instant SmartScreen reputation; OV accumulates it). macOS:
   Apple Developer ID plus notarisation. Until then, expect warnings no matter how the game is packaged.
2. **Ship updates through butler channels** and point players at the itch app. No custom updater.
3. **Set `embed_pck=false` on all three platforms**, so patches diff a data file rather than a
   400 MB executable — and so the binary stops resembling a self-extractor.
4. **Move rulesets and balance CSVs beside the executable** via `AppPaths`, so numbers patches need
   no binary at all.
5. **Shrink the goods icons before any of this.** A third of the download is 206 PNGs averaging
   over 1 MB. This is the biggest, cheapest, lowest-risk win on the board and it makes every
   subsequent point cheaper.

**Sequencing note:** (5) and (1) are worth doing before the 18 Aug launch — one shrinks the
download, the other removes the warning people actually hit. (2)–(4) are post-launch plumbing that
gets easier once the build is smaller, and none of them should land in the same build as an export
without a boot test on each platform.
