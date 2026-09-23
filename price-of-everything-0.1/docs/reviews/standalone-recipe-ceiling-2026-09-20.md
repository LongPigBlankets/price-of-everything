# Standalone recipe ceiling review — 20 September 2026

This is a live-engine standalone benchmark from the current `codex/transport-middleman-layer` working tree. It runs one fresh building at Stoneshore Docks, buys inputs and grid power, sells outputs, and measures the mean retained cash change over ten producing turns. Construction and initial pre-operation inventory are excluded. The benchmark directly installs researched recipes to compare their economics, so “Unlockable” means the recipe needs research in a normal game; it is not available at game start.

The run covered **125 non-mining recipes**: **119 completed** and **6 site-incompatible**. Profit includes market purchase cost, transport, warehousing, labour, maintenance, tax and dividends. `Base output value` is the recipe batch multiplied by the current goods base prices; it is a ceiling indicator, not cash sales after market impact.

## What is already applied

The earlier answer that no output/price trial had landed was incorrect. The focused trial is already applied. It changes six output fields (the four motor recipes and both construction-equipment recipes) by roughly 8–10%, and raises ICE/EV car base prices by 9%. It is **not** a blanket output increase across every recipe.

The measured changes are substantial where the lever was applied: Motor Manufacture **£16.40 → £38.79**, SynRM **£17.18 → £39.29**, Axial Flux **£28.75 → £49.84**, Hairpin **£30.56 → £51.65**, ICE equipment **£20.10 → £47.48**, EV equipment **£24.30 → £53.64**, Automated ICE cars **−£6.16 → £66.86**, and EV Assembly **−£52.43 → £50.34** per turn. The exact field manifest and paired real-engine results are in the [targeted trial review](targeted-output-gains-2026-09-19.md).

## Highest standalone profit

| Recipe | Availability | Output (units) | Base output value | Standalone profit/turn |
|---|---|---:|---:|---:|
| `r_154` Coal Liquefaction | Unlockable (`research_petro_019`) | fuels 85 | £288.50 | £146.20 |
| `r_064` Triple Tandem Solar Panels | Unlockable (`research_mfg_038`) | solar_panel 15 | £669.00 | £135.23 |
| `r_123` Fabless Semiconductors | Unlockable (`research_mfg_022`) | cpu 5 | £550.60 | £104.01 |
| `r_124` Semiconductor 3D Printing | Unlockable (`research_mfg_039`) | cpu 5 | £550.60 | £101.79 |
| `r_060` Durable Perovskite Solar Panels | Unlockable (`research_mfg_023`) | solar_panel 12 | £535.20 | £76.46 |
| `r_118` Automated ICE Car Assembly | Unlockable (`research_mfg_032`) | ice_car 9 | £1,215.43 | £66.86 |
| `r_214` Sustainable Forestry - Biomass | Unlockable (`research_biochem_006`) | biomass 40 | £99.99 | £57.92 |
| `r_074` Hybrid Engine Manufacturing | Unlockable (`research_mfg_029`) | engine 9 | £521.05 | £57.17 |
| `r_063` Heterojunction Solar Panels | Unlockable (`research_mfg_037`) | solar_panel 12 | £535.20 | £54.52 |
| `r_233` Copper Electrowinning | Unlockable (`research_metal_020`) | copper_wiring 33 | £156.29 | £54.39 |
| `r_034` Construction Equipment Assembly (EV) | Unlockable (`research_mfg_034`) | construction_equipment_ev 13 | £599.14 | £53.64 |
| `r_203` Hairpin Stator Motors | Unlockable (`research_mfg_027`) | motor 33 | £364.49 | £51.65 |
| `r_207` Heavy Electric Motor | Unlockable (`research_mfg_003`) | large_engine 12 | £652.87 | £50.76 |
| `r_119` EV Assembly | Unlockable (`research_mfg_030`) | ev_car 5 | £1,459.09 | £50.34 |
| `r_066` Axial Flux Motors | Unlockable (`research_mfg_026`) | motor 33 | £364.49 | £49.84 |
| `r_033` Construction Equiment Assembly (ICE) | Base | construction_equipment_ice 13 | £559.00 | £47.48 |
| `r_099` Lithium Phosphate Batteries | Unlockable (`research_renew_030`) | lithium_battery 8 | £404.72 | £43.56 |
| `r_065` SynRM Magnetless Motors | Unlockable (`research_mfg_036`) | motor 32 | £353.44 | £39.29 |
| `r_009` Motor Manufacture | Base | motor 33 | £364.49 | £38.79 |
| `r_206` Electric Heavy Vehicles Manufacturing | Unlockable (`research_mfg_033`) | heavy_vehicle 5 | £1,462.43 | £38.30 |

## Highest output-value batches

| Recipe | Availability | Output (units) | Base output value | Standalone profit/turn |
|---|---|---:|---:|---:|
| `r_206` Electric Heavy Vehicles Manufacturing | Unlockable (`research_mfg_033`) | heavy_vehicle 5 | £1,462.43 | £38.30 |
| `r_205` Heavy Vehicles Automated Manufacturing | Unlockable (`research_mfg_031`) | heavy_vehicle 5 | £1,462.43 | £31.06 |
| `r_204` Heavy Vehicles Assembly | Base | heavy_vehicle 5 | £1,462.43 | £7.48 |
| `r_119` EV Assembly | Unlockable (`research_mfg_030`) | ev_car 5 | £1,459.09 | £50.34 |
| `r_118` Automated ICE Car Assembly | Unlockable (`research_mfg_032`) | ice_car 9 | £1,215.43 | £66.86 |
| `r_125` Computer Assembly | Base | computer 9 | £813.60 | £-31.19 |
| `r_117` ICE Car Production | Base | ice_car 6 | £810.29 | £28.86 |
| `r_064` Triple Tandem Solar Panels | Unlockable (`research_mfg_038`) | solar_panel 15 | £669.00 | £135.23 |
| `r_207` Heavy Electric Motor | Unlockable (`research_mfg_003`) | large_engine 12 | £652.87 | £50.76 |
| `r_034` Construction Equipment Assembly (EV) | Unlockable (`research_mfg_034`) | construction_equipment_ev 13 | £599.14 | £53.64 |
| `r_033` Construction Equiment Assembly (ICE) | Base | construction_equipment_ice 13 | £559.00 | £47.48 |
| `r_123` Fabless Semiconductors | Unlockable (`research_mfg_022`) | cpu 5 | £550.60 | £104.01 |
| `r_124` Semiconductor 3D Printing | Unlockable (`research_mfg_039`) | cpu 5 | £550.60 | £101.79 |
| `r_230` Monocrystal CPU Fabbing | Base | cpu 5 | £550.60 | £10.30 |
| `r_122` Semiconductor Fabbing | Unlockable (`research_mfg_021`) | cpu 5 | £550.60 | £-9.29 |
| `r_073` Large Vehicle Engine Manufacturing | Unlockable (`research_mfg_028`) | large_engine 10 | £544.06 | £-8.09 |
| `r_060` Durable Perovskite Solar Panels | Unlockable (`research_mfg_023`) | solar_panel 12 | £535.20 | £76.46 |
| `r_063` Heterojunction Solar Panels | Unlockable (`research_mfg_037`) | solar_panel 12 | £535.20 | £54.52 |
| `r_074` Hybrid Engine Manufacturing | Unlockable (`research_mfg_029`) | engine 9 | £521.05 | £57.17 |
| `r_057` Building Frame Manufacture | Base | building_frame 25 | £467.17 | £-3.63 |

## Wind turbine and motor path

| Recipe | Availability | Output (units) | Base output value | Standalone profit/turn |
|---|---|---:|---:|---:|
| `r_009` Motor Manufacture | Base | motor 33 | £364.49 | £38.79 |
| `r_059` Wind Turbine Manufacturing | Base | wind_turbine 3 | £357.58 | £5.93 |
| `r_061` Segmented Assembly Wind Turbines | Unlockable (`research_renew_028`) | wind_turbine 3 | £357.58 | £24.17 |
| `r_063` Heterojunction Solar Panels | Unlockable (`research_mfg_037`) | solar_panel 12 | £535.20 | £54.52 |
| `r_064` Triple Tandem Solar Panels | Unlockable (`research_mfg_038`) | solar_panel 15 | £669.00 | £135.23 |
| `r_065` SynRM Magnetless Motors | Unlockable (`research_mfg_036`) | motor 32 | £353.44 | £39.29 |
| `r_066` Axial Flux Motors | Unlockable (`research_mfg_026`) | motor 33 | £364.49 | £49.84 |
| `r_203` Hairpin Stator Motors | Unlockable (`research_mfg_027`) | motor 33 | £364.49 | £51.65 |

The important gap is visible here: the motor supplier gained from the trial, but Wind Turbine Manufacturing (`r_059`) stayed at **£5.93/turn**, and Segmented Assembly Wind Turbines (`r_061`) stayed at **£24.17/turn**. Both still produce three turbines, so they were outside the ≥12-unit output lever, and wind turbines were not included in the terminal-good price trial. The wind recipe buys nine motors; increasing motor output changes the supplier’s ceiling but does not lower the motor’s market price or the turbine assembler’s purchased-input bill. Therefore the current trial makes the upstream motor step more attractive, but it does not yet make “integrate into turbines” more rewarding.

I ran a focused live sensitivity at the same site, changing only `wind_turbine` from £119.192 to **£129.9193 (+9%)**. `r_059` rose from **£5.93 to £31.48/turn** and `r_061` from **£24.17 to £44.66/turn**. This is the intended small-batch price lever: it raises the absolute ceiling without changing the recipe inputs or motor price. It still needs a longer market-impact run before becoming a balance change.

For the stated design objective, a separate turbine-stage test is needed. The least disruptive version is a small price uplift on `wind_turbine` (it has no recipe consumers) or a researched recipe-specific output reward for `r_061`; test it against the unchanged base recipe and the full motor input chain. Do not increase motor price to fund this: motors have many consumers and the current trial deliberately protects their downstream ordering.

## Interpretation of a broader output pass

A held-input +10% output pass raises the batch-value ceiling by about 10% wherever the output actually sells, while labour, maintenance and power remain fixed. The live trial shows why the resulting profit increase is smaller or larger than that simple percentage: market impact, transport/warehousing, tax and dividends move with volume and value. It is a strong lever for recipes that are currently contribution-positive, but it also amplifies the already dominant unlockables (coal liquefaction, triple-tandem solar, fabless semiconductors) and can widen the gap between base and researched recipes.

The safe balance rule is therefore: keep the focused motor/equipment changes, apply output gains by recipe family rather than globally, use the price lever for small terminal batches, and check every downstream consumer and construction kit. A blanket pass would increase the ceiling, but it would also increase market supply and transport bills everywhere; it is not a neutral 10% profit bonus.

For the middleman specifically, the latest £40 Pepper Valley benchmark gives **£15.22/turn at 33 motors** in the later port-rate window. The same factory at 36 motors through the output modifier gives **£48.36/turn** before the logistics rewards. That is the headroom the output lever creates: it lets the fixed intermediary fee remain visible and survivable while leaving a stronger reason to move to owned logistics at higher output. The 10% trial therefore supports the progression, but the £40 fee should be tuned against this later-stage margin rather than against the coastal standalone rows above.

### All completed recipes

| Recipe | Availability | Output (units) | Base output value | Standalone profit/turn |
|---|---|---:|---:|---:|
| `r_033` Construction Equiment Assembly (ICE) | Base | construction_equipment_ice 13 | £559.00 | £47.48 |
| `r_009` Motor Manufacture | Base | motor 33 | £364.49 | £38.79 |
| `r_117` ICE Car Production | Base | ice_car 6 | £810.29 | £28.86 |
| `r_229` CZ Monocrystal Growth | Base | high_grade_silicon 3 | £174.40 | £28.36 |
| `r_213` Aggressive Logging - Biomass | Base | biomass 20 | £50.00 | £26.10 |
| `r_215` Gentle Pruning - Biomass | Base | biomass 20 | £50.00 | £26.10 |
| `r_082` Electric Calcination Alumina | Base | alumina 54 | £153.73 | £25.96 |
| `r_047` Fertilisers Production | Base | fertilisers 24 | £145.69 | £23.31 |
| `r_209` Strip Farming - Biomass | Base | biomass 35, waste_water 15 | £89.14 | £22.67 |
| `r_217` Biomass Carbonisation | Base | carbonised_biomass 21 | £117.32 | £21.75 |
| `r_055` uPVC Window Manufacturing | Base | windows 18 | £273.86 | £21.42 |
| `r_218` Petroleum Coking | Base | pet_coke 20 | £87.56 | £20.80 |
| `r_050` Aluminium (Hall Heroult) Smelting | Base | aluminium 22 | £167.59 | £20.47 |
| `r_030` Electric Concrete Production | Base | concrete 28 | £169.59 | £19.67 |
| `r_115` Sulphuric Acid Production | Base | industrial_acids 16 | £120.60 | £19.29 |
| `r_165` Radial Axial Tire Production | Base | tyres 36 | £230.99 | £18.74 |
| `r_116` Generic Acid Production | Base | industrial_acids 20 | £150.75 | £18.47 |
| `r_056` Window Manufacturing | Base | windows 16 | £243.44 | £17.59 |
| `r_237` Hydraulics Automated Assembly | Base | hydraulic_components 18 | £126.00 | £16.96 |
| `r_079` Water Electrolysis | Base | hydrogen 16, oxygen 8 | £64.11 | £16.72 |
| `r_051` Desalination | Base | pure_water 40, basic_salt 10, chem_salts 5 | £37.57 | £16.40 |
| `r_008` Copper Wire Drawing | Base | copper_wiring 33 | £156.29 | £13.94 |
| `r_135` Fibreglass Production | Base | fibreglass 6 | £116.11 | £13.74 |
| `r_231` Anthracite Graphitisation | Base | graphite 6 | £76.13 | £13.15 |
| `r_023` Ethylene Refining | Base | ethylene 12 | £71.28 | £12.84 |
| `r_022` Fuels Refining | Base | fuels 21 | £71.28 | £12.84 |
| `r_132` Alloy Metal Smelting | Base | alloy_ingots 30 | £67.53 | £12.57 |
| `r_150` Petroleum Needle Coke Calcination | Base | graphite 10 | £126.88 | £12.22 |
| `r_007` Copper Blistering | Base | copper_ingots 25 | £77.83 | £12.18 |
| `r_026` Copper Pipe Hot Rolling | Base | copper_pipe 18 | £72.78 | £11.87 |
| `r_037` Onshore wind generation | Base | power 228 | £25.08 | £11.25 |
| `r_146` Solar Power Generation | Base | power 228 | £25.08 | £11.25 |
| `r_236` Hydraulics Manufacturing | Base | hydraulic_components 16 | £112.00 | £11.16 |
| `r_040` Bayer Process | Base | alumina 30 | £85.41 | £10.89 |
| `r_044` Silicon Smelting | Base | metallurgical_silicon 20 | £96.69 | £10.82 |
| `r_101` Alkaline Battery Manufacturing | Base | alkaline_battery 24 | £167.40 | £10.42 |
| `r_230` Monocrystal CPU Fabbing | Base | cpu 5 | £550.60 | £10.30 |
| `r_041` Rare Earth Reduction | Base | refined_ree 6 | £92.35 | £10.19 |
| `r_003` Steelmaking | Base | steel 44 | £104.19 | £9.97 |
| `r_005` Pig Iron Smelting | Base | iron_ingots 70 | £89.66 | £9.59 |
| `r_024` Plastics Manufacturing | Base | plastics 10 | £92.04 | £9.54 |
| `r_175` PVC Polymerisation | Base | pvc 18 | £152.95 | £9.34 |
| `r_012` Chlor-Alkali Process | Base | chlorine 20, sodium_hydroxide 40, hydrogen 20 | £146.89 | £9.04 |
| `r_045` Polysilicon (Siemens) Smelting | Base | polysilicon 4 | £107.81 | £8.90 |
| `r_046` Haber Bosch Process | Base | ammonia 30 | £120.06 | £8.33 |
| `r_028` Synthetic Rubber Production | Base | rubber 16 | £93.15 | £8.23 |
| `r_029` Concrete Firing | Base | concrete 21 | £127.19 | £8.09 |
| `r_180` Oil Refining | Base | processed_oil 18 | £65.88 | £8.07 |
| `r_053` Industrial Glassmaking | Base | glass 32 | £88.99 | £7.73 |
| `r_204` Heavy Vehicles Assembly | Base | heavy_vehicle 5 | £1,462.43 | £7.48 |
| `r_035` Silica Washing | Base | silica 12 | £51.46 | £6.78 |
| `r_227` Rudimentary Lithium Refinement | Base | lithium_carbonate 9 | £121.27 | £6.32 |
| `r_068` Car Body Manufacturing | Base | car_body 15 | £202.39 | £6.25 |
| `r_067` Rubber Vulcanisation | Base | tyres 25 | £160.41 | £6.04 |
| `r_126` Electrical Components Production | Base | electrical_components 12 | £173.91 | £6.03 |
| `r_059` Wind Turbine Manufacturing | Base | wind_turbine 3 | £357.58 | £5.93 |
| `r_058` Solar Panel Manufacturing | Base | solar_panel 8 | £356.80 | £5.89 |
| `r_181` Oil Power Production | Base | power 525 | £57.75 | £5.83 |
| `r_004` Coal Power Production | Base | power 600 | £66.00 | £5.68 |
| `r_114` Hydrochloric Acid Production | Base | industrial_acids 24 | £180.90 | £2.37 |
| `r_071` ICE Engine Manufacturing | Base | engine 6 | £347.37 | £-1.16 |
| `r_120` Basic Circuit Soldering | Base | circuit_board 12 | £252.12 | £-3.08 |
| `r_057` Building Frame Manufacture | Base | building_frame 25 | £467.17 | £-3.63 |
| `r_225` Battery Storage | Base |  | £0.00 | £-8.49 |
| `r_125` Computer Assembly | Base | computer 9 | £813.60 | £-31.19 |
| `r_154` Coal Liquefaction | Unlockable (`research_petro_019`) | fuels 85 | £288.50 | £146.20 |
| `r_064` Triple Tandem Solar Panels | Unlockable (`research_mfg_038`) | solar_panel 15 | £669.00 | £135.23 |
| `r_123` Fabless Semiconductors | Unlockable (`research_mfg_022`) | cpu 5 | £550.60 | £104.01 |
| `r_124` Semiconductor 3D Printing | Unlockable (`research_mfg_039`) | cpu 5 | £550.60 | £101.79 |
| `r_060` Durable Perovskite Solar Panels | Unlockable (`research_mfg_023`) | solar_panel 12 | £535.20 | £76.46 |
| `r_118` Automated ICE Car Assembly | Unlockable (`research_mfg_032`) | ice_car 9 | £1,215.43 | £66.86 |
| `r_214` Sustainable Forestry - Biomass | Unlockable (`research_biochem_006`) | biomass 40 | £99.99 | £57.92 |
| `r_074` Hybrid Engine Manufacturing | Unlockable (`research_mfg_029`) | engine 9 | £521.05 | £57.17 |
| `r_063` Heterojunction Solar Panels | Unlockable (`research_mfg_037`) | solar_panel 12 | £535.20 | £54.52 |
| `r_233` Copper Electrowinning | Unlockable (`research_metal_020`) | copper_wiring 33 | £156.29 | £54.39 |
| `r_034` Construction Equipment Assembly (EV) | Unlockable (`research_mfg_034`) | construction_equipment_ev 13 | £599.14 | £53.64 |
| `r_203` Hairpin Stator Motors | Unlockable (`research_mfg_027`) | motor 33 | £364.49 | £51.65 |
| `r_207` Heavy Electric Motor | Unlockable (`research_mfg_003`) | large_engine 12 | £652.87 | £50.76 |
| `r_119` EV Assembly | Unlockable (`research_mfg_030`) | ev_car 5 | £1,459.09 | £50.34 |
| `r_066` Axial Flux Motors | Unlockable (`research_mfg_026`) | motor 33 | £364.49 | £49.84 |
| `r_099` Lithium Phosphate Batteries | Unlockable (`research_renew_030`) | lithium_battery 8 | £404.72 | £43.56 |
| `r_065` SynRM Magnetless Motors | Unlockable (`research_mfg_036`) | motor 32 | £353.44 | £39.29 |
| `r_206` Electric Heavy Vehicles Manufacturing | Unlockable (`research_mfg_033`) | heavy_vehicle 5 | £1,462.43 | £38.30 |
| `r_083` ELYSIS Aluminium | Unlockable (`research_metal_021`) | aluminium 18, alloy_ingots 3 | £143.87 | £35.80 |
| `r_219` Copper Pipe Moulding | Unlockable (`research_mfg_040`) | copper_pipe 27 | £109.18 | £35.49 |
| `r_076` Electric Arc Steelmaking | Unlockable (`research_metal_004`) | steel 54 | £127.87 | £34.90 |
| `r_133` Alloy Metal Electrolysis | Unlockable (`research_metal_017`) | alloy_ingots 50 | £112.55 | £34.48 |
| `r_220` Copper Pipe Manufacturing | Unlockable (`research_mfg_007`) | copper_pipe 48 | £194.09 | £34.27 |
| `r_020` Flash Copper Smelting | Unlockable (`research_metal_019`) | copper_ingots 50 | £155.66 | £33.95 |
| `r_084` Aluminium Direct Carbothermic Electrolysis | Unlockable (`research_metal_022`) | aluminium 26 | £198.06 | £32.93 |
| `r_081` Fluidised Bed Reactor + CZ Silicon | Unlockable (`research_metal_018`) | polysilicon 8 | £215.63 | £31.24 |
| `r_205` Heavy Vehicles Automated Manufacturing | Unlockable (`research_mfg_031`) | heavy_vehicle 5 | £1,462.43 | £31.06 |
| `r_136` Iron Air Batteries | Unlockable (`research_renew_031`) | iron_battery 9 | £123.75 | £29.77 |
| `r_025` Basic Oxygen Steelmaking | Unlockable (`research_metal_011`) | steel 44 | £104.19 | £28.95 |
| `r_077` HIsarna Steel Making | Unlockable (`research_metal_003`) | steel 44 | £104.19 | £28.59 |
| `r_232` Bauxite Carbochlorination | Unlockable (`research_metal_012`) | aluminium 22 | £167.59 | £28.36 |
| `r_228` Bio Ethylene | Unlockable (`research_biochem_010`) | ethylene 28 | £166.31 | £28.12 |
| `r_031` Direct Reduced Iron Smelting | Unlockable (`research_metal_005`) | iron_ingots 84 | £107.60 | £25.76 |
| `r_061` Segmented Assembly Wind Turbines | Unlockable (`research_renew_028`) | wind_turbine 3 | £357.58 | £24.17 |
| `r_069` Lightweight Car Bodies | Unlockable (`research_mfg_004`) | car_body 20 | £269.85 | £22.62 |
| `r_087` Nitrogen Air Separation | Unlockable (`research_inorg_014`) | nitrogen 50 | £64.68 | £21.33 |
| `r_054` High Strength Glassmaking | Unlockable (`research_inorg_001`) | glass 48 | £133.48 | £20.61 |
| `r_121` Circuit Printing | Unlockable (`research_mfg_011`) | circuit_board 10 | £210.10 | £19.88 |
| `r_226` Magnetic Separation Electrolysis | Unlockable (`research_metal_017`) | refined_ree 6 | £92.35 | £18.88 |
| `r_080` Membraneless Electrolysis | Unlockable (`research_inorg_024`) | hydrogen 16, oxygen 8 | £64.11 | £17.98 |
| `r_039` Lithium Electrolysis | Unlockable (`research_inorg_012`) | lithium_carbonate 9 | £121.27 | £16.34 |
| `r_102` Sodium Ion Battery Manufacturing | Unlockable (`research_renew_026`) | sodium_battery 6 | £136.45 | £15.87 |
| `r_127` Precision Electrical Components | Unlockable (`research_mfg_035`) | electrical_components 21 | £304.35 | £15.80 |
| `r_038` Gas Combined Cycle Turbines | Unlockable (`research_hcpower_005`) | power 600 | £66.00 | £11.83 |
| `r_235` Steelmaking (Bio) | Unlockable (`research_metal_023`) | steel 44 | £104.19 | £10.99 |
| `r_072` V8 Engine Manufacturing | Unlockable (`research_mfg_002`) | engine 6 | £347.37 | £8.92 |
| `r_234` Steelmaking (Petro) | Unlockable (`research_metal_023`) | steel 44 | £104.19 | £8.86 |
| `r_032` Lithium Ion Battery Manufacturing | Unlockable (`research_renew_025`) | lithium_battery 6 | £303.54 | £2.76 |
| `r_151` Petroleum Needle Coke Power | Unlockable (`research_hcpower_005`) | power 720 | £79.20 | £-3.85 |
| `r_073` Large Vehicle Engine Manufacturing | Unlockable (`research_mfg_028`) | large_engine 10 | £544.06 | £-8.09 |
| `r_208` Sustainable Biomass Production | Unlockable (`research_biochem_009`) | biomass 18, waste_water 5 | £45.55 | £-9.25 |
| `r_122` Semiconductor Fabbing | Unlockable (`research_mfg_021`) | cpu 5 | £550.60 | £-9.29 |
| `r_042` Bio-Graphitisation | Unlockable (`research_biochem_010`) | graphite 12 | £152.25 | £-23.02 |
| `r_131` Hydrogen Power | Unlockable (`research_hcpower_010`) | power 1200 | £132.00 | £-56.12 |

The machine-readable run output was generated with `python3 tools/run_recipe_profitability.py --out <new-directory> --jobs 8`; the ignored local snapshot for this review is under `reports/recipe_profitability/standalone-current-2026-09-20/` while the full table above is the review record. Site-incompatible cases were `r_011`, `r_145`, `r_211`, `r_212`, `r_223`, and `r_224`; they are not economic losses and were excluded from the rankings.
The active runtime catalogue is the source of truth for this ranking. Several draft/retired rows remain in `recipes_all.csv`; notably `r_062` Carbon Fibre Wind Turbines has a blank placeholder in the active `recipes.csv` and was therefore not benchmarked. Resolve that catalogue status before balancing it.
