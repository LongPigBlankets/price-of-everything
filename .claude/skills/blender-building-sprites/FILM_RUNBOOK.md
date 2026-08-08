# Loading-film render runbook (multi-machine, multi-worker)

For any Claude instance (or human) picking up the loading-screen film render on
a fresh machine. Everything needed is IN THIS FOLDER — the scene rebuilds
entirely from code; `industrial_goods_factory.blend` (441 KB, committed here) is
just the base file the headless runs open.

## What is being rendered — PLAN OF RECORD (2026-08-08)

A 45s dolly down the loading-screen street, **TRUE 30fps, WIDESCREEN**:
**1350 frames at 2400x1080**, camera sensor 45 (was 36), shift_y 0.10 (was
0.125), no interpolation, no edge blur. Output dir `renders/loading/film_wide/`.

Why those numbers travel together: vertical FOV is unchanged
(36*1080/1920 == 45*1080/2400), so the centre 1920x1080 is pixel-identical to
the approved 16:9 composition — 16:9 players see exactly that crop at 1:1,
ultrawides get ~12.5% more street per side. shift_y is in units of the LARGER
sensor dimension, so it must drop to 0.10 with the 45mm sensor
(0.125*36 == 0.10*45) or the vanishing point rises 60px. Ink stays 2.4px
because thickness keys on HEIGHT (native 1080, displayed 1:1) — all of this is
already wired into `loading_scene.py`; the constants are FILM_*.

Three passes per frame (colour+ink / geometric wall mask / ground shadow mask),
stitched by `film_stitch.py` — call `set_size(2400, 1080,
sky='renders/loading/layers/L0_sky_wide.png', shift_y=0.10)` before `frame()`.
The widescreen sky is generated, not rendered:
`python3 -c "from PIL import Image; Image.new('RGBA',(2400,1080)).save('stub.png')"`
then `python3 sky_gradient.py stub.png renders/loading/layers/L0_sky_wide.png`.

**Before ANY batch: render frame 0 and look at the frame edges.** The wide
sensor reveals ~12.5% of scene per side that no one has ever inspected —
verges, tree lines, the sea, back streets. One frame, ~2 min.
(An earlier 447-keyframe/1920 interpolated run lives in `renders/loading/film/`;
superseded, keep for reference.)

## The eighth split (2 machines, 8 workers)

1350 frames in eight contiguous ranges; Mac takes 1-3 (RAM caps it at 3
workers), the 32GB Windows box takes 4-8 (5 workers):

| eighth | frames  | machine | command (`-- I0 I1`) |
|-------|---------|---------|----------------------|
| 1     | 0-169   | Mac     | `-- 0 169`   |
| 2     | 169-338 | Mac     | `-- 169 338` |
| 3     | 338-507 | Mac     | `-- 338 507` |
| 4     | 507-676 | PC      | `-- 507 676` |
| 5     | 676-845 | PC      | `-- 676 845` |
| 6     | 845-1014| PC      | `-- 845 1014`|
| 7     | 1014-1182| PC     | `-- 1014 1182`|
| 8     | 1182-1350| PC     | `-- 1182 1350`|

Each worker: `blender --background industrial_goods_factory.blend --python
tools_render_chunk.py -- I0 I1`. Launch all of a machine's workers at once —
they are independent processes. Expected wall: Mac ~2.5-4h (54-89s/frame),
PC ~3.5-5.5h (est. 70-115s/frame on the 5600X; measure the first frames and
recompute before believing an ETA). RAM: ~5.5GB/worker — on the PC verify the
FIRST worker's usage in Task Manager before starting the other four.

Transfer at the end: the PC ships its `film_wide/f*.png` (3 passes x 843 frames,
~2-3GB) back to wherever the stitch runs; frames are plain PNGs, any transport.

## Stitch + encode (true 30fps — no interpolation)

    python3 - <<'EOF'
    import sys, os
    sys.path.insert(0, ".")
    import film_stitch as F
    from PIL import Image
    F.set_size(2400, 1080, sky="renders/loading/layers/L0_sky_wide.png", shift_y=0.10)
    d = "renders/loading/film_wide"; stage = os.path.join(d, "_stage")
    os.makedirs(stage, exist_ok=True)
    for i in range(1350):
        Image.fromarray(F.frame(d, i, 0.0)).save(os.path.join(stage, "k%04d.png" % i))
    EOF
    ffmpeg -y -r 30 -i renders/loading/film_wide/_stage/k%04d.png -c:v libx264 -crf 17 -pix_fmt yuv420p -movflags +faststart loading_film_wide.mp4
    # 16:9 delivery = centre crop, no scaling:
    ffmpeg -y -i loading_film_wide.mp4 -vf "crop=1920:1080:240:0" -c:v libx264 -crf 17 -pix_fmt yuv420p loading_film_1080.mp4

## What is being rendered — superseded 447-keyframe plan

## One-time setup on a new machine

1. Clone the game repo; this folder comes with it.
2. Create a working root and copy this folder's *.py + *.blend into it, e.g.
   `D:\poe-render\blender-assets\`. Create `renders\loading\film\` under it.
3. **Path shim — required.** Every script hardcodes the Mac root as a single
   consistent literal. Rewrite it once:
   - PowerShell:
     `Get-ChildItem *.py | % { (Get-Content $_ -Raw) -replace '/Users/crisu/Price of Everything/blender-assets/', 'D:/poe-render/blender-assets/' -replace '/Users/crisu/Price of Everything/price-of-everything/', 'D:/poe-render/price-of-everything/' | Set-Content $_ }`
   - bash: same two `sed -i` replacements.
   The second path matters: `vehicles_kit.py`/`docks_builder.py` read goods
   icons from the game repo (`assets/icons/goods/medium/`), and `film_stitch.py`
   reads `renders/loading/layers/L0_sky_graded.png` — copy that ONE file over
   too (it is small; regenerate with `sky_gradient.py` if lost).
4. Python 3 with numpy, pillow, scipy; ffmpeg on PATH. Blender 5.x
   (`blender.exe` full path on Windows).
5. Smoke test (~3 min after the ~16 min build — do it once):
   `blender --background industrial_goods_factory.blend --python tools_render_chunk.py -- 0 1`
   Then CHECK THE MASK (this exact bug shipped once): ground-mask luma on a
   sunlit road pixel must be ~0.76, not ~0.36 —
   `python3 -c "import numpy as np; from PIL import Image; a=np.asarray(Image.open('renders/loading/film/f000_gnd.png').convert('RGB'))/255.; print((a[...,0]*.2126+a[...,1]*.7152+a[...,2]*.0722)[760,960])"`

## Workers: how many, and how to split

- One worker = one Blender process = ~5.5 GB RAM, ONE core (Freestyle is
  single-threaded — a GPU does not help; do not switch to Cycles/OptiX).
- Workers = floor((RAM_GB − 4) / 5.5). 24 GB → 3. 32 GB → 5.
- Split [0, FILM_N) into equal contiguous ranges, one per worker:
  `blender --background industrial_goods_factory.blend --python tools_render_chunk.py -- I0 I1`
  e.g. 1350 over 5 workers: `0 270`, `270 540`, `540 810`, `810 1080`, `1080 1350`.
- Each worker pays a ~16 min scene build before its first frame. Progress:
  `renders/loading/film/chunk_I0_I1.json`. Frame rate varies 43–71s (1920) with
  visible edge count — the entrance and port ends are the slow stretches.
- STOP a worker: create `renders/loading/film/STOP` (checked every 5 frames;
  clears itself; the json records the resume index) — or just kill the process
  and relaunch from the last done index.

## Stitch + encode (after all ranges done)

    python3 - <<'EOF'
    import sys, os
    sys.path.insert(0, ".")
    import film_stitch as F
    from PIL import Image
    d = "renders/loading/film"; stage = os.path.join(d, "_stage")
    os.makedirs(stage, exist_ok=True)
    N = 447   # or 1350
    for i in range(N):
        Image.fromarray(F.frame(d, i, 0.0)).save(os.path.join(stage, "k%03d.png" % i))
    EOF
    # interpolated (447-keyframe plan):
    ffmpeg -y -r 9.923 -i renders/loading/film/_stage/k%03d.png -vf "minterpolate=fps=30:mi_mode=mci:mc_mode=aobmc:vsbmc=1" -c:v libx264 -crf 17 -pix_fmt yuv420p -movflags +faststart loading_film.mp4
    # true 30fps (1350-frame plan): drop -vf entirely and use -r 30
    # NOTE %03d breaks past frame 999 — use k%04d in both places for N=1350.

Edge blur: `film_stitch.py` EDGE_SIGMA/EDGE_FRAC. It exists to hide MOTION-
INTERPOLATION deformation at the frame edges. At true 30fps there is nothing to
hide — set EDGE_SIGMA = 0 (or a token 2–3 purely as a speed cue if the owner
wants it). It never affects Blender render time either way; it costs ~10 min of
post over 1350 frames.

## Known traps (each cost a debugging round — details in SKILL.md)

- A render pass must CREATE what it depends on; never assume session state.
- Ground-mask isolation must use HOLDOUT, not camera-invisible.
- shift_y is in units of the LARGER image dimension.
- 43–71s/frame is content-dependent; do not diagnose a "slowdown" at the port end.
- Do not lower FILM_N to save time without the owner deciding it.
