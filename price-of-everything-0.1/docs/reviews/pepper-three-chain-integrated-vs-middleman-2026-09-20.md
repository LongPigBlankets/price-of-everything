# Pepper Valley steel, copper wiring and motors: integrated rail vs intermediary

This is a live Godot benchmark using the current catalogue and recipe data. It runs 90 turns and averages turns 40–49 after both cases have reached a repeating operating state.

## Setup

- Site: Pepper Valley, `tile_5_4`; port: `tile_5_10`.
- Recipes: steel (`r_003`), copper wiring (`r_008`) and motors (`r_009`). Current outputs are 49 steel, 37 copper wiring and 33 motors per operating turn.
- Integrated case: steel and copper wiring feed the motor factory from the same-tile stockpile. The motor consumes 32 of each, leaving 17 steel and 5 wiring for sale. Coal, iron ingots and copper ingots are bought from the global market. Surplus steel, surplus wiring and all motors are sold through the port.
- Infrastructure cases: level 1 roads or rail on the seven-tile Pepper Valley–port corridor. The player owns the first three transport tiles (`tile_5_4`–`tile_5_6`) in the rail case and the government owns the remaining corridor. Rail maintenance is £9 per turn; roads have no player maintenance charge under the agreed benchmark assumption.
- Intermediary case: all three buildings independently buy their inputs and sell all outputs through the Logistics Intermediary. The intermediary fee is the transport line in this case; it does not also incur a physical rail invoice.
- Prices are reset to catalogue prices each turn, so this isolates steady-state recipe and logistics economics from market drift.

## Results (average per turn)

| Item | Integrated chain + rail L1 | Integrated chain + roads L1 | Three standalone buildings + intermediary |
|---|---:|---:|---:|
| Goods sales revenue | £428.42 | £428.42 | £655.75 |
| Goods purchased (value only) | £143.51 | £143.51 | £382.21 |
| Labour | £104.63 | £104.63 | £104.63 |
| Building maintenance | £24.00 | £24.00 | £24.00 |
| Grid power | £30.00 | £30.00 | £30.00 |
| Factory costs | £158.63 | £158.63 | £158.63 |
| Physical/intermediary logistics | £28.93 rail/port freight | £49.63 road/port freight | £62.64 intermediary fee |
| Warehousing | £4.38 | £4.38 | £0.00 |
| Player infrastructure maintenance | £9.00 rail | £0.00 roads | £0.00 |
| **Pre-tax operating contribution** | **£83.97** | **£72.28** | **£52.27** |
| After tax and dividends (cash retained) | £60.94 | £53.46 | £40.66 |

The rail-integrated route is ahead of the intermediary by **£31.70 per turn before tax** and **£20.29 after tax and dividends**. The road-integrated route is ahead by about **£20.00 before tax** and **£12.80 after tax**; rail is £11.70 per turn better than roads at this volume. Both integrated cases avoid buying 32 steel and 32 copper wiring for the motor factory and instead carry only the raw-material purchases plus the overland/port bill.

### Integrated rail/port charge

The £28.93 transport line averages:

- Rail haulage: £10.35
- Port inbound charges: £4.49
- Port ad-valorem/insurance charge: £11.99
- Port outbound charges: £2.10
- Fixed port-fee component: £0 in this run

For roads L1, the equivalent transport line is £49.63: £31.05 road haulage, £4.48 port inbound, £11.99 ad-valorem/insurance and £2.10 port outbound. Roads have no player maintenance charge under the Pepper Valley assumption; the government-built corridor carries that responsibility.

## Was the road crossover caused by the output uplift?

No. Re-running the same live benchmark with the pre-uplift outputs (44 steel, 33 wiring, 33 motors) gives:

| Pre-uplift quantities | Roads L1 integrated | Three buildings via intermediary |
|---|---:|---:|
| Operating contribution | £44.05 | £22.72 |

The road route was already ahead by £21.33 under the requested tariff schedule at the pre-uplift quantities. The output uplift raises the integrated road case to £72.28 and the intermediary case to £52.27; the extra steel and wiring revenue is partly offset by the additional intermediary charges. At current quantities the fee is £62.64, made up of £57.54 in class/location charges and £5.10 in the 0.5% market-reference component. The no-player-road-maintenance assumption still matters, but the higher requested class rates now make the intermediary materially less profitable at this three-building volume.

Warehousing is £4.38 for the working raw-material and surplus stock held on the tile. The intermediary case has no tile stockpile or physical rail movement, so its £62.64 is a single intermediary logistics charge.

The benchmark runner is [pepper_three_chain_comparison.gd](/Users/crisu/Price%20of%20Everything/price-of-everything/price-of-everything-0.1/tools/pepper_three_chain_comparison.gd), with its scene at [pepper_three_chain_comparison.tscn](/Users/crisu/Price%20of%20Everything/price-of-everything/price-of-everything-0.1/tools/pepper_three_chain_comparison.tscn). The latest JSON outputs are written to `/tmp/pepper-three-chain-comparison/`.
