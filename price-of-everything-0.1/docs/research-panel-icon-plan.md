# Research panel icons — audit and node-by-node assignment

*Generated 2026-08-19 against `main` @ b733768. Sources: `data/research_unlocks.csv` (239 nodes), `scripts/modifier_state.gd` UNLOCK_MODIFIERS (118 wired effects), `data/recipes_all.csv` `tech_unlock_req` (63 gated recipes), `data/Goods - goodsMVP.csv` (76 active goods).*

## 1. Active goods missing icons

The active set is the 76 goods in `data/Goods - goodsMVP.csv` — the file `Catalog` actually loads (`catalog.gd:5`). Icons live in `assets/icons/goods/{medium,small,very_small}/` as `{good_id}_{internal_name}.png`. A missing file is a blank slot plus a console warning; callers tolerate null by contract.

**7 goods have no icon in any tier:**

| ID | internal_name | Display | Category |
|---|---|---|---|
| `g_063` | `waste_water` | Waste Water | waste |
| `g_067` | `scrap` | Scrap Metal | metals |
| `g_069` | `ammonia` | Ammonia | chems |
| `g_070` | `alkaline_battery` | Alkaline Battery | energy |
| `g_073` | `bio_waste` | Bio Waste | waste |
| `g_074` | `e_waste` | Electronic Waste | waste |
| `g_076` | `carbonised_biomass` | Carbonised Biomass | agribio |

**2 goods have medium + small but no `very_small` tier** (the tier used by the densest lists):

- `g_062` **Biomass** — missing: very_small
- `g_064` **Fertilisers** — missing: very_small

**2 icon files exist with no matching good** — `g_077_green_power`, `g_078_grey_power`. Power is modelled outside the goods CSV, so these are drawn but never resolved by the `{id}_{internal}` lookup. Harmless, but they are not reachable through the normal path.

Coverage: **67 of 76 fully iconed (88%)**, 2 partial, 7 absent.

## 2. Buildings missing icons

Research art leans heavily on building icons (110 of the 239 nodes below use one as their base), so this matters for the panel too. 36 of 37 buildings have an icon.

- `b_029` **Thermal Battery Storage** (`heat_battery`) — no `assets/icons/buildings/b_029_heat_battery.png`

## 3. What the research panel does with its icon slot today

Every non-root node card draws an 80x80 bordered slot and fills it with **the CSV `icon` column rendered as text** — `research_panel.gd:1499-1501`:

```gdscript
var slot_rect := Rect2(rect.position + Vector2(14.0, 44.0), Vector2(UNLOCK_SLOT_SIZE, UNLOCK_SLOT_SIZE))
draw_style_box(_unlock_slot_style, slot_rect)
_draw_text_fit(BODY_FONT, unlock.get("icon", ""), slot_rect.grow(-8.0), 15, DS.PALETTE["ACCENT"], ...)
```

All 239 rows have a token filled in — 122 distinct ones (`coal`, `eaf`, `bifacial`, `hvdc2`, `level2` x21, `level3` x22, `ph` x6 …). So the panel currently shows a word in an accent colour where art should be. The slot, the data column and the per-node intent already exist; only the texture lookup and the art are missing.

Minimal code change to consume real art:

```gdscript
# replace _draw_text_fit with a texture draw, falling back to the token text
var tex := IconLibrary.research_icon(unlock.get("icon", ""))   # new resolver
if tex != null:
    draw_texture_rect(tex, slot_rect.grow(-8.0), false)
else:
    _draw_text_fit(BODY_FONT, unlock.get("icon", ""), slot_rect.grow(-8.0), 15, ...)
```

## 4. Glyph vocabulary — what already exists, what has to be drawn

The overlay glyphs below are the "what happens" half of every card. Most already exist in the project; six do not.

### Already in the project

| Glyph | File | Looks like | Use for |
|---|---|---|---|
| `^` up / `v` down | `ui_icons/recipe_arrow.png` (rotate, tint green) | outlined block arrow | any increase / decrease |
| `+` plus | `ui_icons/plus_off_white.png` (tint green) | thick cross | a new recipe or capability |
| `L2` / `L3` | `ui_icons/upgrade_icon_off_white.png` + numeral | small up arrow | building level unlock |
| bolt | `ui_icons/recipe_power_icon.png` | yellow lightning | power consumption |
| workers | `ui_icons/alt/people.png` | three hard-hatted figures | labour headcount |
| truck | `ui_icons/cost_of_transport_icon.png` | lorry with a coin badge | transport cost |
| notes | `ui_icons/alt/market.png` | banknotes + rising arrow | sale price, premiums |
| clock | `ui_icons/input_transport_duration_icon.png` | clock face | turns / duration |
| crate | `ui_icons/input_status_icon.png` | crate outline | inputs, stock |
| lens | `ui_icons/alt/mapmodes.png` | magnifier | survey / reveal |
| scope | `ui_icons/alt/research.png` | microscope | prerequisite-only, spare nodes |
| leaf | `icons/victory/greenest.png` | green leaf | renewable potential |
| hammer | `ui_icons/hammer_off_white.png` | gold hammer | build actions |

### Must be drawn (6)

| Glyph | Needed by | Why nothing existing works |
|---|---|---|
| **gear / cog** | 22 maintenance nodes | `alt/construct.png` is a hammer-and-spanner on a bottom-menu plate — wrong scale and reads as "build", not "upkeep" |
| **weight / tonnage** | 13 throughput nodes | nothing in the project expresses capacity or mass |
| **coin / pound** | 3 port-fee + cost nodes | the only money art is `alt/market.png` (a plate-style banknote stack) and the $ badge welded onto the truck |
| **CO2 plume** | pollution / carbon nodes (future) | no emissions art anywhere in `assets/` |
| **droplet** | water, desal, brine nodes | would sharpen ~12 chemistry/water cards |
| **flask / beaker** | chemistry nodes | the microscope is the only science glyph and is already doing prereq duty |

## 5. The composition grammar

Every card is **one base + up to two overlay glyphs**, no more:

```
  +-------------------+
  |  BASE  (56x56)    |   base   = WHAT it affects  -> building icon, or good icon
  |            [G][G] |   glyphs = WHAT happens     -> 18x18, bottom-right, in reading order
  +-------------------+
```

Base priority: **modifier target building** > **modifier target good** > **gated recipe output good** > **gated recipe building** > **infrastructure icon implied by the token** > **category fallback**.

| Effect | Glyphs | Count |
|---|---|---|
| new recipe | `+` (plus, green) | 53 |
| output increase | `^` (up, green) | 46 |
| building level | `L2` / `L3` | 42 |
| maintenance down | gear\* + `v` | 21 |
| labour down | workers + `v` | 14 |
| power down | bolt + `v` | 12 |
| throughput up | weight\* + `^` | 9+1 |
| transport cost down | truck + `v` | 5 |
| port fee down | coin\* + `v` | 3 |
| sale price / premium up | notes + `^` | 4 |
| prerequisite / spare | scope | 9 |

\* = glyph must be drawn.

Two nodes carry two rewards (a level **and** a recipe, or a recipe **and** an output boost); those get both glyph pairs and are listed with both effects below.

## 6. All 239 nodes

`Base` names the art file to use (`b_*` = `assets/icons/buildings/`, `g_*` = `assets/icons/goods/small/`, `ui/*` = `assets/icons/ui_icons/`). `Now` is the text token the slot currently prints. Rows marked !! have a described effect that is **not wired in code** — see part 7.

### Mining and Surveying (19)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `mining_001` | I | Improved Coal Mining | `coal` | output +15% Coal | `g_001_coal` | **output** |
| `mining_006` | I | Mining Mastery | `+5%` | output +5% mineral mining / 30t | `b_001_mine` | **output** |
| `mining_008` | I | Spectral Crystallography | `survey` | +1 adjacent tile revealed when surveying | `glyph/binoculars` | arrow_up |
| `mining_013` | I | Bench Blasting Expansion | `blast` | output +20% Mine / 20t | `b_001_mine` | **output** |
| `mining_014` | I | Bulk Haulage Fleets | `truck` | output +5% Mine | `b_001_mine` | **output** |
| `mining_015` | I | Continuous Surface Miners | `miner` | power -20% Mine | `b_001_mine` | power arrow_down |
| `mining_016` | I | Block Caving | `cave` | maintenance -20% Mine | `b_001_mine` | gears arrow_down |
| `mining_017` | I | Shale Oil Fracturing | `frack` | recipe Shale Oil Fracking | `g_026_crude_oil` | **merge** |
| `mining_002` | II | Beneficiated Iron Mining | `iron` | output +15% Iron Ore | `g_002_iron_ore` | **output** |
| `mining_003` | II | Deep Seam Surveying | `survey` | output +15% Limestone | `g_016_limestone` | **output** |
| `mining_004` | II | Copper Froth Flotation | `copper` | output +15% Copper Ore | `g_003_copper_ore` | **output** |
| `mining_007` | II | Rare Vein Prospecting | `rare` | output +15% Rare Earth Ore | `g_032_ree_ore` | **output** |
| `mining_009` | II | Computer Assisted Geoscanning | `svt` | +1 Survey range (2 to 3) | `b_001_mine` | binoculars arrow_up |
| `mining_010` | II | Composite Drill Bits | `drill` | output +15% Rare Earth Ore | `g_032_ree_ore` | **output** |
| `mining_011` | II | In-Pit Crushing | `level2` | Level 2 for Mine | `b_001_mine` | `level_2` |
| `mining_018` | II | Dynamic-Positioning Drilling | `rig` | recipe Deepwater Oil Extraction | `g_026_crude_oil` | **merge** |
| `mining_005` | III | Automated Mine Dispatch | `truck` | output +15% Coal | `g_001_coal` | **output** |
| `mining_012` | III | Autonomous Haul Systems | `level3` | Level 3 for Mine | `b_001_mine` | `level_3` |
| `mining_019` | III | Subsea Production Systems | `manifold` | recipe Subsea Manifold Extraction | `g_026_crude_oil` | **merge** |

### Metallurgy (18)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `metal_001` | I | Basic Blast Furnaces | `furnace` | recipe Direct Reduced Iron Smelting + output +5% Furnace | `b_002_furnace` | **merge** **output** |
| `metal_002` | I | Continuous Casting | `cast` | prerequisite only | `b_002_furnace` | scope (no reward wired) |
| `metal_011` | I | Oxygen-Enriched Blast | `furnace` | recipe Basic Oxygen Steelmaking | `g_006_steel` | **merge** |
| `metal_012` | I | Bauxite Carbochlorination | `furnace` | recipe Bauxite Carbochlorination | `g_029_aluminium` | **merge** |
| `metal_014` | I | Foamy Slag Practice | `slag` | output +5% Electric Arc Furnace | `b_008_eaf` | **output** |
| `metal_016` | I | DC Arc Conversion | `eaf` | power -5% Electric Arc Furnace | `b_008_eaf` | power arrow_down |
| `metal_003` | II | Alloy Heat Treatment | `alloy` | recipe Copper Pipe Moulding; HIsarna Steel Making | `g_006_steel` | **merge** |
| `metal_004` | II | Electric Arc Refining | `eaf` | recipe ELYSIS Aluminium; Electric Arc Steelmaking; Flash Co | `g_005_copper_ingots` | **merge** |
| `metal_006` | II | Hot Blast Stoves | `level2` | Level 2 for Furnace | `b_002_furnace` | `level_2` |
| `metal_008` | II | Ultra-High-Power Arcs | `level2` | recipe Aluminium Direct Carbothermic Electrolysis + output +10% Electric Arc Furnace | `b_008_eaf` | **merge** **output** |
| `metal_015` | II | Twin-Shell Furnaces | `level2` | Level 2 for Electric Arc Furnace | `b_008_eaf` | `level_2` |
| `metal_017` | II | Molten Salt Alloy Electrolysis | `alloy` | recipe Alloy Metal Electrolysis; Magnetic Separation Electr | `g_034_alloy_ingots` | **merge** |
| `metal_005` | III | Hydrogen Direct Reduction | `h2steel` | prerequisite only | `b_002_furnace` | scope (no reward wired) |
| `metal_007` | III | Top-Pressure Recovery Turbines | `level3` | Level 3 for Furnace | `b_002_furnace` | `level_3` |
| `metal_009` | III | Consteel Continuous Charging | `level3` | Level 3 for Electric Arc Furnace | `b_008_eaf` | `level_3` |
| `metal_010` | III | Pulverised Carbon Injection | `pci` | power -20% Furnace | `b_002_furnace` | power arrow_down |
| `metal_013` | III | Scrap Preheating Towers | `preheat` | power -20% Electric Arc Furnace | `b_008_eaf` | power arrow_down |
| `metal_018` | III | Czochralski Crystal Growth | `glass` | recipe Fluidised Bed Reactor + CZ Silicon | `g_048_polysilicon` | **merge** |

### Manufacturing (39)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `mfg_001` | I | Interchangeable Tooling | `tools` | labour -5% Assembly Plant | `b_009_assembly_plant` | engineer arrow_down |
| `mfg_002` | I | Precision Assembly Lines | `assembly` | recipe V8 Engine Manufacturing | `g_046_engine` | **merge** |
| `mfg_013` | I | High-Volume Press Lines | `press` | output +5% Industrial Goods Factory | `b_007_industrial_factory` | **output** |
| `mfg_014` | I | Multi-Shift Production | `shift` | output +5% Industrial Goods Factory | `b_007_industrial_factory` | **output** |
| `mfg_017` | I | Just-in-Time Sequencing | `jit` | maintenance -15% Industrial Goods Factory | `b_007_industrial_factory` | gears arrow_down |
| `mfg_019` | I | Robotic Final Assembly | `robot` | labour -10% Assembly Plant / 20t | `b_009_assembly_plant` | engineer arrow_down |
| `mfg_020` | I | Automated Guided Assembly | `agv` | labour -5% Industrial Goods Factory | `b_007_industrial_factory` | engineer arrow_down |
| `mfg_021` | I | Class-100 Cleanrooms | `ph` | !! unused spare node | `ui/research` | scope (no reward wired) |
| `mfg_024` | I | Fully-Automated Fabs | `fab` | output +10% High Tech Manufactory | `b_010_high_tech_manufactory` | **output** |
| `mfg_026` | I | Axial Flux Motor Lines | `motor` | recipe Axial Flux Motors | `g_008_motor` | **merge** |
| `mfg_027` | I | Hairpin Stator Winding | `motor` | recipe Hairpin Stator Motors | `g_008_motor` | **merge** |
| `mfg_028` | I | Heavy Engine Casting | `assembly` | recipe Large Vehicle Engine Manufacturing | `g_052_large_engine` | **merge** |
| `mfg_029` | I | Hybrid Powertrain Integration | `assembly` | recipe Hybrid Engine Manufacturing | `g_046_engine` | **merge** |
| `mfg_030` | I | Electric Vehicle Assembly | `assembly` | recipe EV Assembly | `g_057_ev_car` | **merge** |
| `mfg_031` | I | Heavy Vehicle Assembly | `assembly` | recipe Heavy Vehicles Automated Manufacturing | `g_055_heavy_vehicle` | **merge** |
| `mfg_003` | II | Motor Winding Automation | `motor` | recipe Heavy Electric Motor | `g_052_large_engine` | **merge** |
| `mfg_004` | II | Composite Panel Pressing | `press` | recipe Lightweight Car Bodies | `g_045_car_body` | **merge** |
| `mfg_006` | II | Conveyor Mass Assembly | `level2` | Level 2 for Industrial Goods Factory | `b_007_industrial_factory` | `level_2` |
| `mfg_007` | II | Precision Tube Drawing | `tube` | recipe Copper Pipe Manufacturing | `g_021_copper_pipe` | **merge** |
| `mfg_009` | II | Moving Assembly Lines | `level2` | Level 2 for Assembly Plant | `b_009_assembly_plant` | `level_2` |
| `mfg_011` | II | 300mm Wafer Lines | `level2` | Level 2 for High Tech Manufactory + recipe Circuit Printing | `b_010_high_tech_manufactory` | `level_2` **merge** |
| `mfg_018` | II | Modular Sub-Assembly | `module` | output +5% Assembly Plant | `b_009_assembly_plant` | **output** |
| `mfg_022` | II | Advanced Photolithography | `litho` | recipe Fabless Semiconductors | `g_041_cpu` | **merge** |
| `mfg_032` | II | Automated Body-in-White Lines | `press` | recipe Automated ICE Car Assembly | `g_056_ice_car` | **merge** |
| `mfg_033` | II | Electric Drivetrain Integration | `motor` | recipe Electric Heavy Vehicles Manufacturing | `g_055_heavy_vehicle` | **merge** |
| `mfg_034` | II | Electric Plant & Machinery | `tools` | recipe Construction Equipment Assembly (EV) | `g_072_construction_equipment_ev` | **merge** |
| `mfg_035` | II | Precision Electronics Assembly | `assembly` | recipe Precision Electrical Components | `g_036_electrical_components` | **merge** |
| `mfg_005` | III | Modular Factory Cells | `cell` | prerequisite only | `b_007_industrial_factory` | scope (no reward wired) |
| `mfg_008` | III | Robotic Assembly Islands | `level3` | Level 3 for Industrial Goods Factory | `b_007_industrial_factory` | `level_3` |
| `mfg_010` | III | Mixed-Model Synchronous Lines | `level3` | Level 3 for Assembly Plant | `b_009_assembly_plant` | `level_3` |
| `mfg_012` | III | EUV Lithography | `level3` | Level 3 for High Tech Manufactory | `b_010_high_tech_manufactory` | `level_3` |
| `mfg_015` | III | Lights-Out Automation | `labour` | labour -20% High Tech Manufactory | `b_010_high_tech_manufactory` | engineer arrow_down |
| `mfg_016` | III | Flexible Manufacturing Cells | `fmc` | labour -10% Industrial Goods Factory | `b_007_industrial_factory` | engineer arrow_down |
| `mfg_023` | III | Atomic Layer Deposition | `ald` | recipe Durable Perovskite Solar Panels + output +5% High Tech Manufactory | `b_010_high_tech_manufactory` | **merge** **output** |
| `mfg_025` | III | Coordinated Robot Handoff | `handoff` | output +5% Assembly Plant | `b_009_assembly_plant` | **output** |
| `mfg_036` | III | Synchronous Reluctance Drives | `motor` | recipe SynRM Magnetless Motors | `g_008_motor` | **merge** |
| `mfg_037` | III | Heterojunction Cell Lines | `solar` | recipe Heterojunction Solar Panels | `g_054_solar_panel` | **merge** |
| `mfg_038` | III | Tandem Cell Stacking | `solar` | recipe Triple Tandem Solar Panels | `g_054_solar_panel` | **merge** |
| `mfg_039` | III | Additive Semiconductor Printing | `assembly` | recipe Semiconductor 3D Printing | `g_041_cpu` | **merge** |

### Inorganic Chemistry (24)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `inorg_001` | I | High Strength Glassmaking | `glass` | recipe High Strength Glassmaking | `g_038_glass` | **merge** |
| `inorg_004` | I | Chlor Alkali Cells | `cell` | output +5% Electrolyser | `b_020_electrolyser` | **output** |
| `inorg_005` | I | Acid Gas Scrubbing | `scrub` | labour -5% Chemical Plant | `b_012_chem_plant` | engineer arrow_down |
| `inorg_014` | I | Process Intensification | `flask` | recipe Nitrogen Air Separation | `g_068_nitrogen` | **merge** |
| `inorg_015` | I | Deep Catalytic Optimisation | `catalyst` | power -10% Chemical Plant | `b_012_chem_plant` | power arrow_down |
| `inorg_016` | I | High-Current Cell Stacks | `stack` | labour -5% Electrolyser | `b_020_electrolyser` | engineer arrow_down |
| `inorg_017` | I | Bipolar Cell Arrays | `cell` | power -20% Electrolyser / 20t | `b_020_electrolyser` | power arrow_down |
| `inorg_021` | I | Multi-Stage Flash Desal | `desal` | output +20% Desalination Plant | `b_021_desal` | **output** |
| `inorg_023` | I | Zero-Liquid Discharge | `ph` | !! unused spare node | `ui/research` | scope (no reward wired) |
| `inorg_002` | II | Pozzolanic Vitrification | `cast` | output +10% Concrete | `g_017_concrete` | **output** |
| `inorg_003` | II | Micro Silica Synthesis | `glass` | output +5% Concrete | `g_017_concrete` | **output** |
| `inorg_006` | II | Industrial Salt Purification | `salt` | output +25% Chemical Plant / 20t | `b_012_chem_plant` | **output** |
| `inorg_007` | II | Ceramic Catalyst Supports | `ceramic` | power -5% Chemical Plant | `b_012_chem_plant` | power arrow_down |
| `inorg_009` | II | Larger Reactor Trains | `level2` | Level 2 for Chemical Plant | `b_012_chem_plant` | `level_2` |
| `inorg_011` | II | Membrane Electrolysers | `level2` | Level 2 for Electrolyser | `b_020_electrolyser` | `level_2` |
| `inorg_018` | II | Reverse Osmosis Trains | `level2` | Level 2 for Desalination Plant | `b_021_desal` | `level_2` |
| `inorg_024` | II | Membraneless Electrolysis | `cell` | recipe Membraneless Electrolysis | `g_014_hydrogen` | **merge** |
| `inorg_008` | III | Precision Reagent Handling | `flask` | maintenance -10% Chemical Plant / 20t | `b_012_chem_plant` | gears arrow_down |
| `inorg_010` | III | Integrated Chemical Complexes | `level3` | Level 3 for Chemical Plant | `b_012_chem_plant` | `level_3` |
| `inorg_012` | III | Solid-Oxide Electrolysis | `level3` | Level 3 for Electrolyser + recipe Lithium Electrolysis | `b_020_electrolyser` | `level_3` **merge** |
| `inorg_013` | III | Continuous-Flow Reactors | `cfr` | output +5% Chemical Plant | `b_012_chem_plant` | **output** |
| `inorg_019` | III | Seawater RO Megaplants | `level3` | Level 3 for Desalination Plant | `b_021_desal` | `level_3` |
| `inorg_020` | III | Extensive Drainage Systems | `level3` | Level 3 for Water Pump | `b_037_water_pump` | `level_3` |
| `inorg_022` | III | Energy-Recovery Devices | `erd` | power -50% Desalination Plant | `b_021_desal` | power arrow_down |

### Petrochemistry (20)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `petro_001` | I | Fractional Distillation | `oil` | output +5% Petrochemical Refinery | `b_011_petro_refinery` | **output** |
| `petro_002` | I | Catalytic Cracking | `catalyst` | power -5% Petrochemical Refinery | `b_011_petro_refinery` | power arrow_down |
| `petro_017` | I | Heat-Integrated Trains | `heat` | power -10% Polymerisation Refinery | `b_013_poly_plant` | power arrow_down |
| `petro_003` | II | Polymer Feedstocks | `poly` | output +5% Polymerisation Refinery | `b_013_poly_plant` | **output** |
| `petro_004` | II | Solvent Recovery | `solvent` | maintenance -10% Petrochemical Refinery / 20t | `b_011_petro_refinery` | gears arrow_down |
| `petro_006` | II | Directional & Horizontal Drilling | `horizontal` | output +10% Oil Wells | `b_032_oil_well` | **output** |
| `petro_007` | II | Offshore Drilling Platforms | `rig` | recipe Offshore Oil Extraction | `g_026_crude_oil` | **merge** |
| `petro_010` | II | Microseismic Monitoring | `survey` | output +5% Oil Wells | `b_032_oil_well` | **output** |
| `petro_015` | II | Fluid Catalytic Cracking | `level2` | Level 2 for Petrochemical Refinery | `b_011_petro_refinery` | `level_2` |
| `petro_019` | II | Fischer-Tropsch Synthesis | `oil` | recipe Coal Liquefaction | `g_031_fuels` | **merge** |
| `petro_020` | II | Methane Pyrolysis | `gas` | recipe Methane Pyrolysis | `g_014_hydrogen` | **merge** |
| `petro_005` | III | Advanced Elastomers | `rubber` | sale price +5% Rubber / 20t | `g_028_rubber` | candles arrow_up |
| `petro_008` | III | Deepwater Drilling | `deepsea` | !! recipe Deepwater Oil Extraction (12 Crude Oil) | `g_026_crude_oil` | **merge** |
| `petro_009` | III | Subsea Tieback Systems | `manifold` | output +10% Offshore Oil Platform | `b_033_offshore_oil_platform` | **output** |
| `petro_011` | III | Reservoir Stimulation | `stim` | output +20% Oil Wells / 30t | `b_032_oil_well` | **output** |
| `petro_012` | III | Multiphase Subsea Boosting | `pump` | output +10% Offshore Oil Platform | `b_033_offshore_oil_platform` | **output** |
| `petro_013` | III | Enhanced Oil Recovery | `eor` | output +20% Crude Oil / 30t | `g_026_crude_oil` | **output** |
| `petro_014` | III | Remote Platform Operations | `remote` | labour -30% Oil Wells | `b_032_oil_well` | engineer arrow_down |
| `petro_016` | III | Deep Conversion Units | `level3` | Level 3 for Petrochemical Refinery | `b_011_petro_refinery` | `level_3` |
| `petro_018` | III | Continuous Catalyst Regeneration | `ccr` | output +5% Petrochemical Refinery | `b_011_petro_refinery` | **output** |

### Biochemistry (10)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `biochem_001` | I | Sterile Fermentation | `ferment` | output +5% Farm | `b_014_farm` | **output** |
| `biochem_002` | I | Enzyme Screening | `enzyme` | sale price +5% Plastics / 20t | `g_027_plastics` | candles arrow_up |
| `biochem_008` | I | Automated Harvest Fleets | `harvest` | labour -5% New Growth Forest | `b_015_new_forest` | engineer arrow_down |
| `biochem_009` | I | Energy Crop Cultivation | `ferment` | recipe Sustainable Biomass Production | `g_062_biomass` | **merge** |
| `biochem_003` | II | Bioplastic Precursors | `bio` | maintenance -10% Farm / 20t | `b_014_farm` | gears arrow_down |
| `biochem_004` | II | Wastewater Bioreactors | `water` | recipe Water Treatment | `g_009_pure_water` | **merge** |
| `biochem_006` | II | Sustainable Forestry | `forest` | recipe Sustainable Forestry - Biomass | `g_062_biomass` | **merge** |
| `biochem_005` | III | Cell Culture Automation | `culture` | labour -5% Farm | `b_014_farm` | engineer arrow_down |
| `biochem_007` | III | Controlled-Environment Farming | `level3` | Level 3 for Farm | `b_014_farm` | `level_3` |
| `biochem_010` | III | Biomass Cracking | `bio` | recipe Bio Ethylene; Bio-Graphitisation | `g_066_graphite` | **merge** |

### Hydrocarbon Power (10)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `hcpower_001` | I | Pulverized Coal Boilers | `boiler` | output +5% Power plant | `b_003_power_plant` | **output** |
| `hcpower_002` | I | Steam Turbine Upgrades | `turbine` | output +25% Power plant / 25t | `b_003_power_plant` | **output** |
| `hcpower_008` | I | Reheat Turbine Cycles | `turbine` | output +10% Power plant | `b_003_power_plant` | **output** |
| `hcpower_010` | I | Hydrogen Combustion Turbines | `turbine` | recipe Hydrogen Power | `g_010_power` | **merge** |
| `hcpower_003` | II | Flue Heat Recovery | `heat` | power -10% Power plant | `b_003_power_plant` | power arrow_down |
| `hcpower_005` | II | Combined Cycle Turbines | `turbine` | recipe Gas Combined Cycle Turbines; Petroleum Needle Coke P | `g_010_power` | **merge** |
| `hcpower_006` | II | Supercritical Boilers | `level2` | Level 2 for Power plant | `b_003_power_plant` | `level_2` |
| `hcpower_004` | III | Grid Synchronous Generation | `grid` | maintenance -8% Power plant / 20t | `b_003_power_plant` | gears arrow_down |
| `hcpower_007` | III | Ultra-Supercritical Units | `level3` | Level 3 for Power plant | `b_003_power_plant` | `level_3` |
| `hcpower_009` | III | Combined Heat & Power | `chp` | maintenance -5% empire-wide | `b_003_power_plant` | gears arrow_down |

### Renewable Power (31)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `renew_001` | I | Utility Solar Arrays | `solar` | output +5% Solar Farm | `b_024_solar_farm` | **output** |
| `renew_002` | I | Onshore Wind Control | `wind` | output +5% Onshore Wind Farm | `b_025_onshore_wind_farm` | **output** |
| `renew_015` | I | Taller Turbine Towers | `onwind` | output +10% Onshore Wind Farm | `b_025_onshore_wind_farm` | **output** |
| `renew_016` | I | Variable-Pitch Control | `pitch` | maintenance -10% Onshore Wind Farm / 20t | `b_025_onshore_wind_farm` | gears arrow_down |
| `renew_018` | I | Utility-Scale Inverters | `inverter` | output +10% Solar Farm | `b_024_solar_farm` | **output** |
| `renew_019` | I | Dual-Axis Tracking Farms | `solar` | output +10% Solar Farm | `b_024_solar_farm` | **output** |
| `renew_020` | I | Perovskite Tandem Arrays | `ph` | !! unused spare node | `ui/research` | scope (no reward wired) |
| `renew_021` | I | Containerised Battery Racks | `battery` | maintenance -10% Battery Electric Storage / 20t | `b_028_battery` | gears arrow_down |
| `renew_025` | I | Lithium Battery Storage | `battery` | recipe Lithium Ion Battery Manufacturing | `g_059_lithium_battery` | **merge** |
| `renew_003` | II | Battery Balancing | `battery` | output +10% Battery Electric Storage | `b_028_battery` | **output** |
| `renew_004` | II | Hydro Intake Design | `hydro` | output +10% Hydroelectric Dam | `b_027_hydro_power_plant` | **output** |
| `renew_007` | II | Larger Rotor Diameters | `level2` | Level 2 for Onshore Wind Farm | `b_025_onshore_wind_farm` | `level_2` |
| `renew_009` | II | Single-Axis Trackers | `level2` | Level 2 for Solar Farm | `b_024_solar_farm` | `level_2` |
| `renew_011` | II | Liquid-Cooled Packs | `level2` | Level 2 for Battery Electric Storage | `b_028_battery` | `level_2` |
| `renew_014` | II | Fast Response Storage | `fastbat` | !! Reduces power consumption for buildings sharing the tile by 5% permane | `g_010_power` | power arrow_down |
| `renew_017` | II | Bifacial Panel Arrays | `bifacial` | !! Increases solar potential on all tiles by 10% permanently. | `b_024_solar_farm` | leaf arrow_up |
| `renew_022` | II | Anti-Reflective Coatings | `arc` | !! Increases solar potential on all tiles by 10% permanently. | `b_024_solar_farm` | leaf arrow_up |
| `renew_023` | II | Tall-Tower Wind Capture | `onwind` | !! Increases onshore wind potential by 10% permanently. | `b_024_solar_farm` | leaf arrow_up |
| `renew_024` | II | Marine Wind Profiling | `offwind` | !! Increases offshore wind potential by 10% permanently. | `b_024_solar_farm` | leaf arrow_up |
| `renew_026` | II | Sodium Battery Storage | `battery` | recipe Sodium Ion Battery Manufacturing | `g_060_sodium_battery` | **merge** |
| `renew_028` | II | Segmented Blade Assembly | `wind` | recipe Segmented Assembly Wind Turbines | `g_053_wind_turbine` | **merge** |
| `renew_029` | II | Agrivoltaic Integration | `solar` | recipe Agri Solar Farming | `b_024_solar_farm` | **merge** |
| `renew_030` | II | Lithium Iron Phosphate Cells | `battery` | recipe Lithium Phosphate Batteries | `g_059_lithium_battery` | **merge** |
| `renew_031` | II | Iron-Air Battery Cells | `battery` | recipe Iron Air Batteries | `g_061_iron_battery` | **merge** |
| `renew_005` | III | Renewable Dispatch Forecasting | `forecast` | output +25% Solar Farm / 15t | `b_024_solar_farm` | **output** |
| `renew_006` | III | Long Duration Storage | `storage` | !! Reduces building maintenance by 15% for 30 turns. | `b_024_solar_farm` | gears arrow_down |
| `renew_008` | III | Direct-Drive Megaturbines | `level3` | Level 3 for Onshore Wind Farm | `b_025_onshore_wind_farm` | `level_3` |
| `renew_010` | III | Self-Adjusting Panel Network | `level3` | Level 3 for Solar Farm | `b_024_solar_farm` | `level_3` |
| `renew_012` | III | Flow Battery Arrays | `level3` | Level 3 for Battery Electric Storage | `b_028_battery` | `level_3` |
| `renew_013` | III | Floating Offshore Wind Farms | `floatwind` | recipe Floating Offshore Wind Power | `g_010_power` | **merge** |
| `renew_027` | III | Iron Air Long Duration Storage | `storage` | Unlocks loading Iron Air Battery cells — the cheapest, long-duration b | `b_028_battery` | plus |

### Infrastructure (35)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `infra_001` | I | Reinforced Roadbeds | `road` | throughput +25% roads | `b_005_roads` | chevrons arrow_up |
| `infra_002` | I | Pipe Trench Standards | `pipe` | maintenance -10% Pipeworks / 20t | `b_017_pipes` | gears arrow_down |
| `infra_019` | I | Heavy Freight Corridors | `rail` | throughput +25% rail | `b_019_rails` | chevrons arrow_up |
| `infra_021` | I | Double-Track Sidings | `rail` | maintenance -10% Railways | `b_019_rails` | gears arrow_down |
| `infra_022` | I | Heavy-Haul Bogies | `ph` | !! unused spare node | `ui/research` | scope (no reward wired) |
| `infra_024` | I | Automated Rail Yards | `rail` | maintenance -10% Railways | `b_019_rails` | gears arrow_down |
| `infra_025` | I | Distributed-Power Trains | `rail` | !! transport cost -5% empire-wide | `b_019_rails` | money arrow_down |
| `infra_026` | I | Large-Diameter Mains | `pipe` | maintenance -10% Reinforced Pipeworks | `b_018_reinf_pipes` | gears arrow_down |
| `infra_027` | I | Booster Pumping Stations | `pipe` | maintenance -10% Pipeworks | `b_017_pipes` | gears arrow_down |
| `infra_028` | I | Trunk Pipeline Networks | `pipe` | !! transport cost -5% empire-wide | `b_017_pipes` | money arrow_down |
| `infra_029` | I | Smart Flow Control | `ph` | !! unused spare node | `ui/research` | scope (no reward wired) |
| `infra_030` | I | Double-Walled Pipelines | `pipe` | maintenance -10% Reinforced Pipeworks | `b_018_reinf_pipes` | gears arrow_down |
| `infra_031` | I | Corrosion-Resistant Linings | `pipe` | maintenance -10% Pipeworks | `b_017_pipes` | gears arrow_down |
| `infra_033` | I | Ultra-High-Pressure Mains | `ph` | !! unused spare node | `ui/research` | scope (no reward wired) |
| `infra_003` | II | High Pressure Mains | `main` | throughput +25% pipes | `b_017_pipes` | chevrons arrow_up |
| `infra_004` | II | Substation Layouts | `substation` | throughput +25% cables | `b_006_cables` | chevrons arrow_up |
| `infra_006` | II | Multi-Lane Widening | `level2` | Level 2 for Roads | `b_005_roads` | `level_2` |
| `infra_008` | II | Longer Freight Consists | `level2` | Level 2 for Railways | `b_019_rails` | `level_2` |
| `infra_010` | II | Automated Pressure Management System | `level2` | Level 2 for Pipeworks | `b_017_pipes` | `level_2` |
| `infra_012` | II | High-Pressure Manifolds | `level2` | Level 2 for Reinforced Pipeworks | `b_018_reinf_pipes` | `level_2` |
| `infra_014` | II | Reconductoring | `level2` | Level 2 for Cables | `b_006_cables` | `level_2` |
| `infra_016` | II | High Voltage Cabling | `hvdc1` | Unlocks HVDC long-distance power transmission. | `g_010_power` | plus |
| `infra_005` | III | Integrated Utility Corridors | `corridor` | maintenance -5% empire-wide / 20t | `b_005_roads` | gears arrow_down |
| `infra_007` | III | Grade-Separated Interchanges | `level3` | Level 3 for Roads | `b_005_roads` | `level_3` |
| `infra_009` | III | Standardised Wagon Gantry Cranes | `level3` | Level 3 for Railways | `b_019_rails` | `level_3` |
| `infra_011` | III | Looped Distribution Grids | `level3` | Level 3 for Pipeworks | `b_017_pipes` | `level_3` |
| `infra_013` | III | Cryogenic Transfer Lines | `level3` | Level 3 for Reinforced Pipeworks | `b_018_reinf_pipes` | `level_3` |
| `infra_015` | III | Smart Grid Control | `level3` | Level 3 for Cables | `b_006_cables` | `level_3` |
| `infra_017` | III | Undersea Current Doublers | `hvdc2` | Unlocks higher-capacity undersea HVDC power links. | `g_010_power` | chevrons plus |
| `infra_018` | III | SF6-free Switchgear | `hvdc3` | Unlocks high-capacity HVDC switchgear for power links. | `g_010_power` | chevrons plus |
| `infra_020` | III | Smart Traffic Control | `traffic` | throughput +25% roads | `b_005_roads` | chevrons arrow_up |
| `infra_023` | III | Electrified Rolling Stock | `erail` | throughput +25% rail | `b_019_rails` | chevrons arrow_up |
| `infra_032` | III | Leak-Detection Networks | `leak` | throughput +25% pipes | `b_017_pipes` | chevrons arrow_up |
| `infra_034` | III | Electrified Road Haul | `eroad` | !! Increases road throughput by 25% permanently. | `b_005_roads` | chevrons arrow_up |
| `infra_035` | III | Dynamic Line Rating | `hvdc1` | throughput +25% cables | `b_006_cables` | chevrons arrow_up |

### Logistics (11)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `logi_001` | I | Depot Scheduling | `depot` | road/rail cost -10% empire-wide | `glyph/lorry` | money arrow_down |
| `logi_008` | I | Just-in-Time Logistics | `depot` | Unlock JIT delivery from building producing a good to building consumi | `b_004_port` | arrow_down |
| `logi_011` | I | Groupage Contracts | `depot` | port fee -10% empire-wide | `b_004_port` | money arrow_down |
| `logi_002` | II | Multimodal Containerized Freight | `container` | port fee -10% empire-wide | `b_004_port` | money arrow_down |
| `logi_003` | II | Route Optimization | `route` | throughput +25% roads | `b_005_roads` | chevrons arrow_up |
| `logi_004` | II | Cold Chain Handling | `cold` | transport cost -5% empire-wide / 20t | `glyph/lorry` | money arrow_down |
| `logi_006` | II | Pallet Racking Systems | `depot` | Raises tile storage to 1600 (warehouse level 2). | `b_004_port` | plus |
| `logi_007` | II | Automated Storage & Retrieval | `depot` | Raises tile storage to 2500 (warehouse level 3). | `b_004_port` | plus |
| `logi_005` | III | Autonomous Dispatch Rooms | `dispatch` | labour -10% Roads | `b_005_roads` | engineer arrow_down |
| `logi_009` | III | Smart Shipping Contracts | `contract` | port throughput +25% empire-wide | `b_004_port` | chevrons arrow_up |
| `logi_010` | III | Port Network Acquisition | `port` | port fee -20% empire-wide | `b_004_port` | money arrow_down |

### Recycling (6)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `recyc_003` | I | Tertiary Filtration | `filter` | output +15% Water Recyling Plant | `b_022_water_recycling` | **output** |
| `recyc_004` | I | Advanced Oxidation Loops | `scrub` | recipe E-Waste Recycling | `g_007_copper_wiring` | **merge** |
| `recyc_005` | I | Zero-Discharge Water | `loop` | power -10% Water Recyling Plant | `b_022_water_recycling` | power arrow_down |
| `recyc_006` | I | Biowaste Digestion | `bio` | recipe Biowaste Recycling | `g_062_biomass` | **merge** |
| `recyc_001` | II | Membrane Bioreactors | `level2` | Level 2 for Water Recyling Plant | `b_022_water_recycling` | `level_2` |
| `recyc_002` | III | Closed-Loop Reclaim | `level3` | Level 3 for Water Recyling Plant | `b_022_water_recycling` | `level_3` |

### People Management (11)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `people_001` | I | Shift Supervisors | `shift` | labour -5% Mine | `b_001_mine` | engineer arrow_down |
| `people_002` | I | Safety Training | `safety` | maintenance -5% empire-wide | `glyph/engineer` | gears arrow_down |
| `people_006` | I | Operational Team Managers | `team` | labour -10% empire-wide | `glyph/engineer` | arrow_down |
| `people_003` | II | Specialist Apprenticeships | `apprentice` | output +5% Assembly Plant | `b_009_assembly_plant` | **output** |
| `people_004` | II | Union Liaison Offices | `union` | maintenance -10% empire-wide / 20t | `glyph/engineer` | gears arrow_down |
| `people_007` | II | Shift Handover Documentation | `shift` | labour -10% empire-wide | `glyph/engineer` | arrow_down |
| `people_008` | II | Third Advisor Seat | `team` | Unlocks a 3rd advisor seat once you own 15 buildings. | `glyph/engineer` | plus |
| `people_011` | II | Executive Search | `search` | Opens the remaining advisor posts for hire. | `glyph/engineer` | plus |
| `people_005` | III | Continuous Improvement Teams | `team` | output +5% empire-wide | `glyph/engineer` | **output** |
| `people_009` | III | Fourth Advisor Seat | `team` | Unlocks a 4th advisor seat once you own 100 buildings. | `glyph/engineer` | plus |
| `people_010` | III | Fifth Advisor Seat | `team` | Unlocks a 5th advisor seat after 3 turns above 1000 profit/turn. | `glyph/engineer` | plus |

### Markets and Operations (5)

| Node | R | Title | Now | Unlocks | Base | Overlay |
|---|---|---|---|---|---|---|
| `markets_001` | I | Spot Price Reporting | `price` | order premium +25% empire-wide | `glyph/candles` | arrow_up |
| `markets_002` | I | Forward Contracts | `contract` | sale price +5% Steel / 20t | `g_006_steel` | candles arrow_up |
| `markets_003` | II | Risk Desk Procedures | `risk` | input haulage -25% empire-wide | `glyph/lorry` | money arrow_down |
| `markets_004` | II | Maintenance Budgeting | `budget` | maintenance -10% empire-wide / 20t | `glyph/money` | gears arrow_down |
| `markets_005` | III | Integrated Operations Planning | `ops` | maintenance -5% empire-wide | `glyph/money` | gears arrow_down |

## 7. Data gaps this exercise surfaced

Assigning an icon per node meant reading what every node actually does. Fourteen do not do what their card says:

**Seven describe a percentage effect with no `UNLOCK_MODIFIERS` entry** — no reference to the node id or its title anywhere in `scripts/` or `tests/`, so the number on the card is not applied:

- `research_renew_006` **Long Duration Storage** — "Reduces building maintenance by 15% for 30 turns."
- `research_renew_014` **Fast Response Storage** — "Reduces power consumption for buildings sharing the tile by 5% permanently."
- `research_renew_017` **Bifacial Panel Arrays** — "Increases solar potential on all tiles by 10% permanently."
- `research_infra_034` **Electrified Road Haul** — "Increases road throughput by 25% permanently."
- `research_renew_022` **Anti-Reflective Coatings** — "Increases solar potential on all tiles by 10% permanently."
- `research_renew_023` **Tall-Tower Wind Capture** — "Increases onshore wind potential by 10% permanently."
- `research_renew_024` **Marine Wind Profiling** — "Increases offshore wind potential by 10% permanently."

**Six are explicit spares** (`Spare tech name (unused leveling option) — no effect yet`), which is honest but means six cards in the tree are decoration: `Class-100 Cleanrooms`, `Perovskite Tandem Arrays`, `Zero-Liquid Discharge`, `Heavy-Haul Bogies`, `Smart Flow Control`, `Ultra-High-Pressure Mains`.

**One promises a recipe that is not gated to it** — `research_petro_008` **Deepwater Drilling** says it unlocks "Deepwater Oil Extraction (12 Crude Oil)", but no row in `recipes_all.csv` carries `tech_unlock_req = research_petro_008`.

None of these block the icon work — each still gets a sensible card — but the art will make them more visible, not less.
