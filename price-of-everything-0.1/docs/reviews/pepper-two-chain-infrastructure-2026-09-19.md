# Two chains: level-2 roads versus level-1 rail

Select **level-1 rail** for the two-chain scenario. This comparison uses actual engine routes, movement accounting and freight quotes at recurring full throughput. It is an economic model, not a newly qualified production run.

Both hub cases retain the same £17.96/turn recipe (one hydraulic component, one tyre, one fuel), three vehicles and £928.34 vehicle investment, as requested. Only covered freight avoided changes with the route. The full engine congestion surcharge remains in either transport model. Rail upkeep covers the previously agreed three player-owned tiles; other rail is public. Roads have no player maintenance.

| Two-chain infrastructure | Middleman profit | Generic carrier profit | Hub profit |
| --- | ---: | ---: | ---: |
| roads_l2 | £93.59 | £52.52 | £61.42 |
| rail_l1 | £93.59 | £147.81 | £141.03 |

## Costs per turn

| Cost | Roads L2 | Rail L1 |
| --- | ---: | ---: |
| Generic carrier base freight | £79.27 | £27.82 |
| Congestion retained in either model | £79.27 | £26.44 |
| Player infrastructure maintenance | £0.00 | £9.00 |
| Player infrastructure labour | £0.00 | £0.00 |
| Port fees/ad valorem | £34.91 | £34.91 |
| Warehousing | £11.61 | £11.61 |
| Base freight remaining with hub | £52.41 | £16.64 |
| Hub running inputs | £17.96 | £17.96 |

The hub remaining-freight row replaces generic base freight; it is not an additional charge. Port, warehouse and factory economics stay fixed for a controlled comparison. Faster deliveries could change real inventory and warehouse costs, which are not recomputed here. Construction/upgrade capital and hub-building overhead are excluded.

L2 roads carry 500 units before congestion, but the furnace tile still handles 580. The selected roads therefore still attract the engine's route surcharge. Upgrades also shorten journeys from four legs to three, reducing base freight.

L1 rail has a 600-unit threshold and halves the per-leg mode rate; typical port journeys take two legs. A routing issue remains: the export path repeats tile_6_4 via tile_7_4, producing 698 units of measured flow at tile_6_4 instead of 540 without the repeat. The £26.44 surcharge from that actual selected route is retained, not silently removed. The origin/departure accounting fix and this repeated-route issue are different concerns. Rail wins even with this charge. No routing or gameplay change was made in this comparison.

The selected rail carrier earns £147.81/turn, versus £141.03 with the hub: cheap rail freight removes the hub's operating advantage at this scale. The hub saves £11.18 of base freight but consumes £17.96 of supplies. Identical hub costs do not imply identical savings on cheaper infrastructure.

## Selected four-setup comparison

| Setup | Middleman | Generic carrier | Hub |
| --- | ---: | ---: | ---: |
| Motors only, original roads | £22.72 | −£3.86 | −£12.46 |
| Motors + steel, original roads | £27.62 | £6.67 | −£0.73 |
| Five factories, original roads | £46.80 | £54.08 | £50.37 |
| Two five-factory chains, selected L1 rail | £93.59 | £147.81 | £141.03 |

The earlier three rows are unchanged. The doubled row is still a full-output model: it has not resolved or revalidated the production input-reservation constraint. Government corridor completion is assumed. Infrastructure capital is not priced, so this selects by recurring operating profitability, not capital payback.

Reproduce after `python3 tools/analyse_pepper_consolidation.py`:

```sh
python3 tools/analyse_pepper_infrastructure.py
```

[Raw engine quotes and comparison](../../reports/balance/pepper_infrastructure_two_chains_2026-09-19.json).
