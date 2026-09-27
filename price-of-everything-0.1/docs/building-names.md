# Building names

Every building and recipe with its name under the owner's convention (`docs/ds2-owner-decisions.md`, Construct):
a building is named by what it makes, "<qualifier> <output word> <building word>", with its letter once it stands
on a tile ("Iron Furnace A"). The qualifier appears only where several recipes of the same building make the same
main output, and the plain recipe of such a group has none. The rule and its table of exceptions live in
`scripts/building_naming.gd`. This file is written by `tools/building_names_table.tscn`. Regenerate it rather than editing by hand.

A building type in a catalogue, before a recipe is chosen, keeps its type name (the Type column).
Names shown here are without the letter. **Was** is the name the building had before, with letter A.
Rows marked **check** carry a note for the owner.

## Buildings with recipes

| Type | Recipe | Main output | Name | Was | Note |
|---|---|---|---|---|---|
| Mine | Alloy Metal Mining (r_134) | Alloy Metals Ore | **Alloy Metal Mine** | Mine - Alloy Metals Ore - A |  |
| Mine | Salt Mining (r_010) | Basic Salt | **Salt Mine** | Mine - Basic Salt - A |  |
| Mine | Bauxite Mining (r_015) | Bauxite Ore | **Bauxite Mine** | Mine - Bauxite Ore - A |  |
| Mine | Coal Mining (r_001) | Coal | **Coal Mine** | Mine - Coal - A |  |
| Mine | Copper Mining (r_006) | Copper Ore | **Copper Mine** | Mine - Copper Ore - A |  |
| Mine | Iron Mining (r_002) | Iron Ore | **Iron Mine** | Mine - Iron Ore - A |  |
| Mine | Limestone Mining (r_019) | Limestone | **Limestone Mine** | Mine - Limestone - A | **check** Limestone is quarried, but keeps the Mine word with its kind. |
| Mine | Lithium Mining (r_016) | Lithium Ore | **Lithium Mine** | Mine - Lithium Ore - A |  |
| Mine | Rare Earth Mining (r_017) | Rare Earth Ore | **Rare Earth Mine** | Mine - Rare Earth Ore - A |  |
| Mine | Sand Excavation (r_018) | Sand | **Sand Mine** | Mine - Sand - A | **check** Sand is dug, not mined, but keeps the Mine word with its kind. |
| Mine | Sulphur Mining (r_179) | Sulphur | **Sulphur Mine** | Mine - Sulphur - A |  |
| Furnace | Alloy Metal Smelting (r_132) | Alloy Metals Ingots | **Alloy Metal Furnace** | Furnace - Alloy Metals Ingots - A |  |
| Furnace | Bayer Process (r_040) | Alumina | **Alumina Furnace** | Furnace - Alumina - A |  |
| Furnace | Aluminium (Hall Heroult) Smelting (r_050) | Aluminium | **Aluminium Furnace** | Furnace - Aluminium - A |  |
| Furnace | Bauxite Carbochlorination (r_232) | Aluminium | **Carbochlorination Aluminium Furnace** | Furnace - Aluminium - A |  |
| Furnace | Biomass Carbonisation (r_217) | Carbonised Biomass | **Carbonised Biomass Furnace** | Furnace - Carbonised Biomass - A |  |
| Furnace | Concrete Firing (r_029) | Concrete | **Concrete Furnace** | Furnace - Concrete - A |  |
| Furnace | Copper Blistering (r_007) | Copper Ingots | **Copper Furnace** | Furnace - Copper Ingots - A |  |
| Furnace | Flash Copper Smelting (r_020) | Copper Ingots | **Flash Copper Furnace** | Furnace - Copper Ingots - A |  |
| Furnace | Copper Pipe Hot Rolling (r_026) | Copper Pipe | **Copper Pipe Furnace** | Furnace - Copper Pipe - A |  |
| Furnace | Copper Pipe Moulding (r_219) | Copper Pipe | **Moulded Copper Pipe Furnace** | Furnace - Copper Pipe - A |  |
| Furnace | Industrial Glassmaking (r_053) | Glass | **Glass Furnace** | Furnace - Glass - A |  |
| Furnace | High Strength Glassmaking (r_054) | Glass | **High Strength Glass Furnace** | Furnace - Glass - A |  |
| Furnace | Bio-Graphitisation (r_042) | Graphite | **Graphite Furnace** | Furnace - Graphite - A |  |
| Furnace | Pig Iron Smelting (r_005) | Iron Ingots | **Iron Furnace** | Furnace - Iron Ingots - A |  |
| Furnace | Direct Reduced Iron Smelting (r_031) | Iron Ingots | **Direct Reduced Iron Furnace** | Furnace - Iron Ingots - A |  |
| Furnace | Rudimentary Lithium Refinement (r_227) | Lithium Carbonate | **Lithium Furnace** | Furnace - Lithium Carbonate - A |  |
| Furnace | Steelmaking (r_003) | Steel | **Steel Furnace** | Furnace - Steel - A |  |
| Furnace | Basic Oxygen Steelmaking (r_025) | Steel | **Basic Oxygen Steel Furnace** | Furnace - Steel - A |  |
| Furnace | HIsarna Steel Making (r_077) | Steel | **HIsarna Steel Furnace** | Furnace - Steel - A |  |
| Furnace | Steelmaking (Petro) (r_234) | Steel | **Petro Steel Furnace** | Furnace - Steel - A |  |
| Furnace | Steelmaking (Bio) (r_235) | Steel | **Bio Steel Furnace** | Furnace - Steel - A |  |
| Power plant | Coal Power Production (r_004) | Power | **Coal Power Plant** | Coal Power Plant A |  |
| Power plant | Gas Combined Cycle Turbines (r_038) | Power | **Gas Power Plant** | Gas Power Plant A |  |
| Power plant | Hydrogen Power (r_131) | Power | **Hydrogen Power Plant** | Hydrogen Power Plant A |  |
| Power plant | Petroleum Needle Coke Power (r_151) | Power | **Coke Power Plant** | Coke Power Plant A |  |
| Power plant | Oil Power Production (r_181) | Power | **Oil Power Plant** | Oil Power Plant A |  |
| Industrial Goods Factory | Alkaline Battery Manufacturing (r_101) | Alkaline Battery | **Alkaline Battery Factory** | Alkaline Battery Factory A |  |
| Industrial Goods Factory | Car Body Manufacturing (r_068) | Car Body | **Car Body Factory** | Car Body Factory A |  |
| Industrial Goods Factory | Basic Circuit Soldering (r_120) | Circuit Board | **Circuit Board Factory** | Circuit Board Factory A |  |
| Industrial Goods Factory | Construction Equipment Assembly (EV) (r_034) | Construction Equipment EV | **Construction Equipment EV Factory** | Construction Equipment EV Factory A | **check** Keeps the good's own word order, "Construction Equipment EV". |
| Industrial Goods Factory | Construction Equiment Assembly (ICE) (r_033) | Construction Equipment ICE | **Construction Equipment ICE Factory** | Construction Equipment ICE Factory A | **check** Keeps the good's own word order, "Construction Equipment ICE". |
| Industrial Goods Factory | Copper Pipe Manufacturing (r_220) | Copper Pipe | **Copper Pipe Factory** | Copper Pipe Factory A |  |
| Industrial Goods Factory | Copper Wire Drawing (r_008) | Copper Wiring | **Copper Wiring Factory** | Copper Wiring Factory A |  |
| Industrial Goods Factory | Electrical Components Production (r_126) | Electrical Components | **Electrical Components Factory** | Electrical Components Factory A |  |
| Industrial Goods Factory | ICE Engine Manufacturing (r_071) | Engine | **Engine Factory** | Engine Factory A |  |
| Industrial Goods Factory | V8 Engine Manufacturing (r_072) | Engine | **V8 Engine Factory** | Engine Factory A |  |
| Industrial Goods Factory | Fibreglass Production (r_135) | Fibreglass | **Fibreglass Factory** | Fibreglass Factory A |  |
| Industrial Goods Factory | Heavy Vehicles Assembly (r_204) | Heavy Vehicle | **Heavy Vehicle Factory** | Heavy Vehicle Factory A |  |
| Industrial Goods Factory | Hydraulics Manufacturing (r_236) | Hydraulic Components | **Hydraulic Components Factory** | Hydraulic Components Factory A |  |
| Industrial Goods Factory | ICE Car Production (r_117) | Diesel Car | **Diesel Car Factory** | Diesel Car Factory A |  |
| Industrial Goods Factory | Iron Air Batteries (r_136) | Iron Air Battery | **Iron Air Battery Factory** | Iron Air Battery Factory A |  |
| Industrial Goods Factory | Lithium Ion Battery Manufacturing (r_032) | Lithium Ion Battery | **Lithium Ion Battery Factory** | Lithium Ion Battery Factory A |  |
| Industrial Goods Factory | Motor Manufacture (r_009) | Motor | **Motor Factory** | Motor Factory A |  |
| Industrial Goods Factory | Radial Axial Tire Production (r_165) | Tyres | **Tyres Factory** | Tyres Factory A |  |
| Industrial Goods Factory | uPVC Window Manufacturing (r_055) | Windows | **uPVC Windows Factory** | Windows Factory A |  |
| Industrial Goods Factory | Window Manufacturing (r_056) | Windows | **Windows Factory** | Windows Factory A |  |
| Electric Arc Furnace | ELYSIS Aluminium (r_083) | Aluminium | **ELYSIS Aluminium Arc Furnace** | Electric Arc Furnace - Aluminium - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Electric Arc Furnace | Aluminium Direct Carbothermic Electrolysis (r_084) | Aluminium | **Carbothermic Aluminium Arc Furnace** | Electric Arc Furnace - Aluminium - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Electric Arc Furnace | Electric Concrete Production (r_030) | Concrete | **Concrete Arc Furnace** | Electric Arc Furnace - Concrete - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Electric Arc Furnace | Anthracite Graphitisation (r_231) | Graphite | **Graphite Arc Furnace** | Electric Arc Furnace - Graphite - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Electric Arc Furnace | Silicon Smelting (r_044) | Metallurgical Silicon | **Metallurgical Silicon Arc Furnace** | Electric Arc Furnace - Metallurgical Silicon - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Electric Arc Furnace | Electric Arc Steelmaking (r_076) | Steel | **Steel Arc Furnace** | Electric Arc Furnace - Steel - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Electric Arc Furnace | Scrap Recycling (r_106) | Steel | **Scrap Steel Arc Furnace** | Electric Arc Furnace - Steel - A | **check** "Arc Furnace" shortens Electric Arc Furnace so the name stays at three or four words. |
| Assembly Plant | Building Frame Manufacture (r_057) | Building Frame | **Building Frame Assembly Plant** | Assembly Plant - Building Frame - A |  |
| Assembly Plant | Lightweight Car Bodies (r_069) | Car Body | **Car Body Assembly Plant** | Assembly Plant - Car Body - A |  |
| Assembly Plant | Circuit Printing (r_121) | Circuit Board | **Circuit Board Assembly Plant** | Assembly Plant - Circuit Board - A |  |
| Assembly Plant | Computer Assembly (r_125) | Computer | **Computer Assembly Plant** | Assembly Plant - Computer - A |  |
| Assembly Plant | Semiconductor Fabbing (r_122) | CPU | **CPU Assembly Plant** | Assembly Plant - CPU - A |  |
| Assembly Plant | Monocrystal CPU Fabbing (r_230) | CPU | **Monocrystal CPU Assembly Plant** | Assembly Plant - CPU - A |  |
| Assembly Plant | Hybrid Engine Manufacturing (r_074) | Engine | **Engine Assembly Plant** | Assembly Plant - Engine - A |  |
| Assembly Plant | EV Assembly (r_119) | Electric Car | **Electric Car Assembly Plant** | Assembly Plant - Electric Car - A |  |
| Assembly Plant | Heavy Vehicles Automated Manufacturing (r_205) | Heavy Vehicle | **Automated Heavy Vehicle Assembly Plant** | Assembly Plant - Heavy Vehicle - A | **check** No recipe of this group is the plain one, so each carries its own word. |
| Assembly Plant | Electric Heavy Vehicles Manufacturing (r_206) | Heavy Vehicle | **Electric Heavy Vehicle Assembly Plant** | Assembly Plant - Heavy Vehicle - A | **check** No recipe of this group is the plain one, so each carries its own word. |
| Assembly Plant | Hydraulics Automated Assembly (r_237) | Hydraulic Components | **Hydraulic Components Assembly Plant** | Assembly Plant - Hydraulic Components - A |  |
| Assembly Plant | Automated ICE Car Assembly (r_118) | Diesel Car | **Diesel Car Assembly Plant** | Assembly Plant - Diesel Car - A |  |
| Assembly Plant | Large Vehicle Engine Manufacturing (r_073) | Large Engine | **Large Engine Assembly Plant** | Assembly Plant - Large Engine - A |  |
| Assembly Plant | Heavy Electric Motor (r_207) | Large Engine | **Electric Large Engine Assembly Plant** | Assembly Plant - Large Engine - A |  |
| Assembly Plant | SynRM Magnetless Motors (r_065) | Motor | **SynRM Motor Assembly Plant** | Assembly Plant - Motor - A | **check** The owner's example names a plain "Motor Assembly Plant", but all three motor recipes here are named processes, so each carries its own word. Axial Flux (the earliest research) could be the plain one. |
| Assembly Plant | Axial Flux Motors (r_066) | Motor | **Axial Flux Motor Assembly Plant** | Assembly Plant - Motor - A | **check** See SynRM. |
| Assembly Plant | Hairpin Stator Motors (r_203) | Motor | **Hairpin Stator Motor Assembly Plant** | Assembly Plant - Motor - A | **check** See SynRM. |
| Assembly Plant | Sodium Ion Battery Manufacturing (r_102) | Sodium Ion Battery | **Sodium Ion Battery Assembly Plant** | Assembly Plant - Sodium Ion Battery - A |  |
| Assembly Plant | Solar Panel Manufacturing (r_058) | Solar Panel | **Solar Panel Assembly Plant** | Assembly Plant - Solar Panel - A |  |
| Assembly Plant | Durable Perovskite Solar Panels (r_060) | Solar Panel | **Perovskite Solar Panel Assembly Plant** | Assembly Plant - Solar Panel - A |  |
| Assembly Plant | Wind Turbine Manufacturing (r_059) | Wind Turbine | **Wind Turbine Assembly Plant** | Assembly Plant - Wind Turbine - A |  |
| Assembly Plant | Segmented Assembly Wind Turbines (r_061) | Wind Turbine | **Segmented Wind Turbine Assembly Plant** | Assembly Plant - Wind Turbine - A |  |
| High Tech Manufactory | Fabless Semiconductors (r_123) | CPU | **Fabless CPU Manufactory** | High Tech Manufactory - CPU - A | **check** "Manufactory" drops "High Tech" to keep the names short. |
| High Tech Manufactory | Semiconductor 3D Printing (r_124) | CPU | **3D Printed CPU Manufactory** | High Tech Manufactory - CPU - A | **check** "Manufactory" drops "High Tech" to keep the names short. |
| High Tech Manufactory | Precision Electrical Components (r_127) | Electrical Components | **Electrical Components Manufactory** | High Tech Manufactory - Electrical Components - A | **check** "Manufactory" drops "High Tech" to keep the names short. |
| High Tech Manufactory | Lithium Phosphate Batteries (r_099) | Lithium Ion Battery | **Lithium Ion Battery Manufactory** | High Tech Manufactory - Lithium Ion Battery - A | **check** "Manufactory" drops "High Tech" to keep the names short. |
| High Tech Manufactory | Heterojunction Solar Panels (r_063) | Solar Panel | **Heterojunction Solar Panel Manufactory** | High Tech Manufactory - Solar Panel - A | **check** "Manufactory" drops "High Tech" to keep the names short. |
| High Tech Manufactory | Triple Tandem Solar Panels (r_064) | Solar Panel | **Triple Tandem Solar Panel Manufactory** | High Tech Manufactory - Solar Panel - A | **check** "Manufactory" drops "High Tech" to keep the names short. |
| Petrochemical Refinery | Ethylene Refining (r_023) | Ethylene | **Oil Processing Refinery** | Oil Processing Refinery A |  |
| Petrochemical Refinery | Fuels Refining (r_022) | Diesel Fuel | **Oil Processing Refinery** | Oil Processing Refinery A |  |
| Petrochemical Refinery | Petroleum Needle Coke Calcination (r_150) | Graphite | **Needle Coke Plant** | Needle Coke Plant A |  |
| Petrochemical Refinery | Petroleum Coking (r_218) | Petroleum Needle Coke | **Needle Coke Plant** | Needle Coke Plant A |  |
| Petrochemical Refinery | Oil Refining (r_180) | Processed Oil | **Oil Processing Refinery** | Oil Processing Refinery A |  |
| Petrochemical Refinery | Silica Washing (r_035) | Silica | **Oil Processing Refinery** | Oil Processing Refinery A |  |
| Chemical Plant | Electric Calcination Alumina (r_082) | Alumina | **Alumina Chemical Plant** | Alumina Chemical Plant A |  |
| Chemical Plant | Haber Bosch Process (r_046) | Ammonia | **Ammonia Chemical Plant** | Ammonia Chemical Plant A |  |
| Chemical Plant | Chlor-Alkali Process (r_012) | Chlorine | **Chlor Alkali Complex** | Chlor Alkali Complex A |  |
| Chemical Plant | Copper Electrowinning (r_233) | Copper Wiring | **Copper Wiring Chemical Plant** | Copper Wiring Chemical Plant A |  |
| Chemical Plant | Bio Ethylene (r_228) | Ethylene | **Ethylene Chemical Plant** | Ethylene Chemical Plant A |  |
| Chemical Plant | Fertilisers Production (r_047) | Fertilisers | **Fertilisers Chemical Plant** | Fertilisers Chemical Plant A |  |
| Chemical Plant | Coal Liquefaction (r_154) | Diesel Fuel | **Diesel Fuel Chemical Plant** | Diesel Fuel Chemical Plant A |  |
| Chemical Plant | CZ Monocrystal Growth (r_229) | High Grade Silicon | **High Grade Silicon Chemical Plant** | High Grade Silicon Chemical Plant A |  |
| Chemical Plant | Hydrochloric Acid Production (r_114) | Industrial Acids | **Hydrochloric Acid Chemical Plant** | Industrial Acids Chemical Plant A |  |
| Chemical Plant | Sulphuric Acid Production (r_115) | Industrial Acids | **Sulphuric Acid Chemical Plant** | Industrial Acids Chemical Plant A |  |
| Chemical Plant | Generic Acid Production (r_116) | Industrial Acids | **Acid Chemical Plant** | Industrial Acids Chemical Plant A |  |
| Chemical Plant | Nitrogen Air Separation (r_087) | Nitrogen | **Nitrogen Chemical Plant** | Nitrogen Chemical Plant A |  |
| Chemical Plant | Polysilicon (Siemens) Smelting (r_045) | Polysilicon | **Siemens Polysilicon Chemical Plant** | Polysilicon Chemical Plant A | **check** No recipe of this group is the plain one, so each carries its own word. |
| Chemical Plant | Fluidised Bed Reactor + CZ Silicon (r_081) | Polysilicon | **Fluidised Bed Polysilicon Chemical Plant** | Polysilicon Chemical Plant A | **check** No recipe of this group is the plain one, so each carries its own word. |
| Chemical Plant | Rubber Vulcanisation (r_067) | Tyres | **Tyres Chemical Plant** | Tyres Chemical Plant A |  |
| Polymerisation Refinery | Plastics Manufacturing (r_024) | Plastics | **Plastics Plant** | Plastics Plant A |  |
| Polymerisation Refinery | PVC Polymerisation (r_175) | PVC | **PVC Plant** | PVC Plant A |  |
| Polymerisation Refinery | Synthetic Rubber Production (r_028) | Rubber | **Rubber Plant** | Rubber Plant A |  |
| Farm | Sustainable Biomass Production (r_208) | Biomass | **Biomass Farm** | Farm - Biomass - A |  |
| Farm | Strip Farming - Biomass (r_209) | Biomass | **Strip Biomass Farm** | Farm - Biomass - A |  |
| Farm | Agri Solar Farming - Biomass (r_211) | Biomass | **Agri Solar Biomass Farm** | Farm - Biomass - A |  |
| Farm | Livestock Farming - Biomass (r_212) | Biomass | **Livestock Biomass Farm** | Farm - Biomass - A |  |
| New Growth Forest | Aggressive Logging - Biomass (r_213) | Biomass | **Aggressive Logging Biomass Forest** | New Growth Forest - Biomass - A | **check** Forest names carry "Biomass", the only good a forest makes in the game. |
| New Growth Forest | Sustainable Forestry - Biomass (r_214) | Biomass | **Biomass Forest** | New Growth Forest - Biomass - A | **check** Forest names carry "Biomass", the only good a forest makes in the game. |
| New Growth Forest | Gentle Pruning - Biomass (r_215) | Biomass | **Gentle Pruning Biomass Forest** | New Growth Forest - Biomass - A | **check** Forest names carry "Biomass", the only good a forest makes in the game. |
| Electrolyser | Alloy Metal Electrolysis (r_133) | Alloy Metals Ingots | **Alloy Metal Electrolyser** | Electrolyser - Alloy Metals Ingots - A |  |
| Electrolyser | Methane Pyrolysis (r_078) | Hydrogen | **Methane Pyrolysis Hydrogen Electrolyser** | Electrolyser - Hydrogen - A |  |
| Electrolyser | Water Electrolysis (r_079) | Hydrogen | **Hydrogen Electrolyser** | Electrolyser - Hydrogen - A |  |
| Electrolyser | Membraneless Electrolysis (r_080) | Hydrogen | **Membraneless Hydrogen Electrolyser** | Electrolyser - Hydrogen - A |  |
| Electrolyser | Lithium Electrolysis (r_039) | Lithium Carbonate | **Lithium Electrolyser** | Electrolyser - Lithium Carbonate - A |  |
| Electrolyser | Rare Earth Reduction (r_041) | Refined Rare Earths | **Rare Earth Electrolyser** | Electrolyser - Refined Rare Earths - A |  |
| Electrolyser | Magnetic Separation Electrolysis (r_226) | Refined Rare Earths | **Magnetic Separation Rare Earth Electrolyser** | Electrolyser - Refined Rare Earths - A |  |
| Desalination Plant | Desalination (r_051) | Pure Water | **Desalination Plant** | Desalination Plant - Pure Water - A |  |
| Water Recyling Plant | Water Treatment (r_105) | Pure Water | **Water Recycling Plant** | Water Recyling Plant - Pure Water - A | **check** The type's display name is misspelt ("Recyling"). The building name spells it right. |
| Solar Farm | Solar Power Generation (r_146) | Power | **Solar Farm** | Solar Farm A |  |
| Onshore Wind Farm | Onshore wind generation (r_037) | Power | **Wind Farm** | Wind Farm A |  |
| Offshore Wind Farm | Offshore Wind Power Generation (r_145) | Power | **Offshore Wind Farm** | Offshore Wind Farm A |  |
| Offshore Wind Farm | Floating Offshore Wind Power (r_223) | Power | **Floating Offshore Wind Farm** | Offshore Wind Farm A | **check** Floating is the qualifier. The owner's wind farm names otherwise kept. |
| Hydroelectric Dam | Hydroelectric Power (r_224) | Power | **Hydroelectric Dam** | Hydroelectric Dam - Power - A |  |
| Battery Electric Storage | Battery Storage (r_225) |  | **Battery Electric Storage** | Battery Electric Storage - A | **check** Stores power and makes nothing, so it keeps its type name. |
| Oil Wells | Oil Drilling (r_014) | Crude Oil | **Oil Well** | Oil Wells - Crude Oil - A |  |
| Offshore Oil Platform | Offshore Oil Extraction (r_178) | Crude Oil | **Oil Platform** | Offshore Oil Platform - Crude Oil - A | **check** "Oil Platform": the sea already says offshore. |
| Offshore Oil Platform | Deepwater Oil Extraction (r_221) | Crude Oil | **Deepwater Oil Platform** | Offshore Oil Platform - Crude Oil - A | **check** "Oil Platform": the sea already says offshore. |
| Offshore Oil Platform | Subsea Manifold Extraction (r_222) | Crude Oil | **Subsea Manifold Oil Platform** | Offshore Oil Platform - Crude Oil - A | **check** "Oil Platform": the sea already says offshore. |
| Hydraulic Fracking Oil Wells | Shale Oil Fracking (r_177) | Crude Oil | **Fracking Oil Well** | Hydraulic Fracking Oil Wells - Crude Oil - A | **check** "Fracking Oil Well" rather than the type's "Hydraulic Fracking Oil Wells". |
| Recycling Plant | Biowaste Recycling (r_108) | Biomass | **Biomass Recycling Plant** | Recycling Plant - Biomass - A | **check** Named by its main output, biomass, though it recycles bio waste. |
| Recycling Plant | E-Waste Recycling (r_107) | Copper Wiring | **Copper Wiring Recycling Plant** | Recycling Plant - Copper Wiring - A | **check** Named by its main output, copper wiring, though it recycles electronic waste. |
| Water Pump | Water Pumping (r_011) | Pure Water | **Water Pump** | Water Pump - Pure Water - A |  |

## Buildings without recipes

These keep their type name, with a letter where one stands on a tile ("Port A").

| Type | Name |
|---|---|
| Port | **Port** |
| Roads | **Roads** |
| Cables | **Cables** |
| Old Growth Forest | **Old Growth Forest** |
| Pipeworks | **Pipeworks** |
| Reinforced Pipeworks | **Reinforced Pipeworks** |
| Railways | **Railways** |
| Landfill | **Landfill** |
| Thermal Battery Storage | **Thermal Battery Storage** |
| Consumer Goods Factory | **Consumer Goods Factory** |
| Disused Buildings | **Disused Buildings** |
| Airport | **Airport** |

## Recipes the game does not load

`data/recipes_all.csv` rows the catalogue drops, because their building or one of their goods is not in the game.
They have no name until they load. The rule will name them then.

| Recipe | Building field | Main output |
|---|---|---|
| Heavy Fuels Refining (r_021) | petro_refinery | fuels |
| Biomass Compression (r_043) | bio_chem_plant | compressed_biomass |
| Direct Lithium Extraction (r_048) | brine_processing_plant | lithium_carbonate |
| Brine Evaporation (r_049) | brine_processing_plant | sulphur |
| Carbon Fibre Wind Turbines (r_062) | high_tech_manufactory | wind_turbine |
| Superlightweight Car Bodies (r_070) | assembly_plant | car_body |
| Oxygen Free High Conductivity Copper (r_085) | eaf | copper_ingots |
| Oxygen Air Separation (r_086) | chem_plant | oxygen |
| Steam Methane Reforming (r_088) | petro_refinery | hydrogen |
| Direct Injection Hydrogen Engines (r_089) | assembly_plant | engine |
| Sustainable Food Production (r_090) | farm | food |
| Strip Farming (r_091) | farm | food |
| Mixed Crop Sustainable Farming (r_092) | farm | food |
| Agri Solar Farming (r_093) | farm | food |
| Livestock Farming (r_094) | farm | food |
| Aggressive Logging (r_095) | forest | wood |
| Sustainable Forestry (r_096) | forest | wood |
| Gentle Pruning (r_097) | forest | wood |
| National Park Tourism (r_098) | forest | wood |
| Redox Flow Batteries (r_100) | high_tech_manufactory | flow_battery |
| High Quality Steel Alloying (r_103) | eaf | hq_steel |
| Depolymerisation (r_104) | poly_plant | ethylene |
| Waste to Power (r_109) | power_plant | hydrocarbon_power |
| Rare Earth Recycling (r_110) | recycling_plant | refined_ree |
| Lithium Recycling (r_111) | recycling_plant | lithium_carbonate |
| Open Combined Gas Cycle Turbine (r_112) | power_plant | hydrocarbon_power |
| Aluminium Recycling (r_113) | recycling_plant | aluminium |
| Inert-Atmosphere Precision Components (r_128) | high_tech_manufactory | electrical_components |
| Carbon Fibre Weaving (r_129) | high_tech_manufactory | carbon_fibre |
| Carbon Fibre 3D Printing (r_130) | high_tech_manufactory | carbon_fibre |
| Solid State Batteries (r_137) | high_tech_manufactory | solid_battery |
| Basic Fermentation (r_138) | bio_chem_plant | ethanol |
| Celulosic Enzymatic Hydrolysis (r_139) | bio_chem_plant | ethanol |
| Transestesterification (r_140) | bio_chem_plant | fuels |
| HEFA Biofuels (r_141) | bio_chem_plant | SAF |
| Crude Distillation (r_142) | petro_refinery | heavy_oil |
| Catalytic Cracking (r_143) | petro_refinery | heavy_oil |
| Gas to Methane (r_144) | petro_refinery | methane |
| Propane Dehydrogenation (r_147) | petro_refinery | hydrogen |
| Steam Cracking (r_148) | petro_refinery | ethylene |
| Delayed Coking (r_149) | petro_refinery | pet_coke |
| Alcohol to Jet SAF (r_152) | chem_plant | SAF |
| Biomass Gassification (r_153) | bio_chem_plant | fuels |
| Micro Algae Digestion (r_155) | bio_chem_plant | ethylene |
| Medical Goods Production (r_156) | high_tech_manufactory | medical_components |
| Thermo Mechanical Pulping (r_157) | timber_paper_factory | wood_pulp |
| Chemical Wood Bleaching (r_158) | timber_paper_factory | wood_pulp |
| Wood Pulp Bleaching (r_159) | timber_paper_factory | paper_pulp |
| Paper Goods Production (r_160) | timber_paper_factory | paper_goods |
| Paper Pulp Oxygen Delignification (r_161) | timber_paper_factory | paper_pulp |
| Wood Toy Craftsmanship (r_162) | factory | toys |
| plastics Toy Manufacturing (r_163) | factory | toys |
| plastics Toy Mass Production (r_164) | factory | toys |
| Food Paper Packaging (r_166) | consumer_goods_factory | food_products |
| plastics Food Packaging (r_167) | consumer_goods_factory | food_products |
| Fabric Crops Farming (r_168) | farm | fabric_crops |
| Oil Crops Farming (r_169) | farm | oil_crops |
| Intensive Fabric Crops Farming (r_170) | farm | fabric_crops |
| Intensive Oil Crops Farming (r_171) | farm | oil_crops |
| Pharmaceutical Precuror Production (r_172) | bio_chem_plant | api |
| Specialty Microbe Production (r_173) | bio_chem_plant | spec_microbes |
| Methanol Production (r_174) | petro_refinery | methanol |
| National Park Tourism - Biomass (r_216) | forest | biomass |
