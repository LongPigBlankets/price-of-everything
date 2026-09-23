# Logistics Hub capacity and cost experiment — 19 September 2026

The requested running recipes are too expensive for a hub serving the single Pepper Valley motor factory or the motor-plus-furnace chain. This remains true even if the hub replaces **all** inland freight, before charging any hub construction, labour, power or maintenance. A shared industrial hub or slower recipe consumption can be modelled, but neither should be presented as already balanced gameplay.

This experiment restores middleman ad valorem to **0.5%**, with solid-heavy £0.05/unit and ultra-heavy £0.50/unit, density 1.5. The middleman stays a building-level buyer/seller; only owned logistics connects buildings. This is a new arithmetic scenario against retained game evidence, not a live balance or gameplay change.

## Coverage and capacity contract

Primary interpretation: a hub serves player buildings on its tile and the six adjacent tiles. Its vehicles can use connected roads to external destinations such as the port. The radius defines eligible buildings; route distance still consumes LC. Both benchmark production buildings are on the hub’s own tile.

Alternate interpretation: every road edge must lie inside at least one hub’s radius. An exact set-cover calculation on the recorded inbound and outbound road paths requires at least **five** hubs. Example centres: `tile_5_10`, `tile_5_5`, `tile_6_6`, `tile_6_7`, `tile_6_8`. This is a geometric lower bound; buildability, ownership, city coefficients and land cost have not been checked. Paying a full recipe at each depot worsens the economics considerably.

The requested “one vehicle per tile-movement” is provisionally modelled as one installed heavy vehicle supplying one directed pooled tile-movement per turn. The operating recipe is paid once per active hub per turn. Mixing fuels with other cargo, payload weights, empty returns and loading are not yet modelled; the pooled rule is intentionally an optimistic capacity bound.

Recorded roads use eight adjacent-tile hops inbound and eight outbound. All purchased goods share the inbound route, while sales share the outbound route. Thus steady pooled work requires **16 LC/turn**, or 16 vehicles under the physical-hop convention. Their existing game routes instead contain four movement legs in each direction, each potentially spanning two tiles. If one LC means one existing game leg, the requirement is **eight vehicles**. This definition must be settled before implementation; changing physical speed would also change transit buffers and timing, which this arithmetic does not simulate.

The actual routed paths are longer than the catalogue’s six-tile straight-line distance. Fleet requirements are based on recorded route edges, not that distance field. Vehicles are installed once, never consumed each turn. LC is an operating service, not a stockpilable or saleable good.

## Running recipe at current prices

Every active hub consumes 2 hydraulic components and 4 tyres, plus one of 6 diesel fuel, 1 lithium battery or 1 sodium battery **each turn**, exactly as requested. This explicit experiment supersedes the earlier proposal’s default treatment of battery packs as installed equipment. It does not silently convert a battery into electricity.

| Per active hub per turn | Diesel | Lithium | Sodium |
| --- | ---: | ---: | ---: |
| Hydraulics + tyres, catalogue value | £39.67 | £39.67 | £39.67 |
| Fuel/battery, catalogue value | £20.36 | £50.59 | £22.74 |
| Total goods at purchase prices | £63.03 | £94.77 | £65.53 |
| Middleman input delivery | £1.02 | £0.98 | £0.84 |
| **Delivered running inputs** | **£64.05** | **£95.74** | **£66.36** |

Purchases use the existing 5% markup, verified against a recorded game buy quote. Hub supplies are bought through the middleman so the model does not grant free delivery or recursively consume its own undefined LC. Fuel uses a provisional £0.03 safe-liquid weight rate, inherited from the earlier experiment; that class is not yet an approved middleman rate. The cost conclusion already holds before any input delivery charge.

Sodium is cheaper than lithium but slightly dearer than diesel under these quantities. Equal service output is an explicit trial assumption: one sodium battery and one lithium battery need not have equal capacity in the final design.

## Upfront equipment

Use the existing Heavy Vehicle (`g_055`) as the requested large vehicle: £292.485 catalogue value, £307.10925 purchase price, £309.321675 including the experimental middleman delivery fee.

- Sixteen physical-hop slots: **£4,949.15** in installed vehicles.
- Eight game-leg slots: **£2,474.57**.

These exclude the hub building, land, finance and any additional infrastructure. Heavy road vehicles are not rail rolling stock; a rail hub needs a separately specified equipment and operating recipe.

## Profit comparison, one factory or one chain

Owned-hub cases optimistically remove 100% of the existing inland weight/distance and ad valorem freight. Port charges, storage and infrastructure obligations remain; network congestion remains a separate constraint. Any smaller discount produces a worse result. There is no double charge of replaced inland carrier freight.

| Operating contribution per turn | Motors only | Motors + furnace |
| --- | ---: | ---: |
| Middleman, restored 0.5% | £22.72 | £27.62 |
| Existing public-road carrier | −£3.86 | £6.67 |
| Existing rail, three owned sections | £15.22 | £29.35 |
| Own road hub: diesel | −£30.46 | −£15.12 |
| Own road hub: lithium | −£62.15 | −£46.82 |
| Own road hub: sodium | −£32.77 | −£17.44 |

Motors alone currently pay £37.45 in inland road freight; the chain pays £42.26. Both are smaller than even the cheapest full hub recipe. For the chain, retain £19.82 port charges and £3.56 storage after taking inland freight in-house. These operating figures exclude tax, financing and capital investment; unknown hub overhead would reduce them further.

## Scale and recipe-frequency sensitivities

With a fixed recipe per hub and unlimited pooled payload, the diesel hub beats the existing road carrier at two motor factories or two chains. To beat the middleman requires six motor factories or four chains. These are **linear break-even estimates, not simulated successful businesses**. Six motors produce 582 external units per turn and four chains 536; the existing shared road tiles have capacity 300. Congestion, price impact, warehouse capacity, land availability and changing factory costs invalidate a straight extrapolation at those sizes. Even three chains (402 units) are already above that capacity.

A 100-unit payload limit per direction is included separately in the raw report. One chain fits its 89 inbound and 45 outbound units into one load each; four chains need four inbound loads and two outbound, or 48 physical-hop vehicle slots. It is not credible to keep increasing volume indefinitely with 16 vehicles and a completely fixed operating recipe. If the recipe is instead per vehicle, the current numbers worsen by an order of magnitude: sixteen diesel vehicles consume roughly £1,024.83 of delivered inputs per turn.

For a small-company hub, the allowed running-cost budget is more informative. Full freight replacement leaves **£10.88/turn** available to beat the middleman for motors alone, or **£21.30/turn** for the chain, before hub overhead and capital recovery. The proposed £64.05 diesel recipe is well above both.

A five-turn recipe batch is a useful separate sensitivity: average the supplied quantities over five turns, giving £12.81 diesel running inputs per turn. It leaves:

- Motors alone: **£20.78**, still behind the middleman’s £22.72.
- Motors + furnace: **£36.12**, ahead of the middleman’s £27.62 and existing rail’s £29.35.

This gives the desired operating progression, but £4,949 of vehicle capex would still need roughly **583 turns** to recover the £8.49 chain advantage over outsourcing, before other costs. Under the eight-game-leg convention it is about 291 turns. LC output, payload, vehicle occupation and installation scale therefore matter at least as much as running-recipe tuning. The five-turn batch is a suggestion only; the requested every-turn recipe remains the primary model.

## Reproduction and limits

```sh
python3 tools/analyse_middleman_dynamic_fee.py --ad-valorem .005 --solid-heavy .05 --ultra-heavy .5
python3 tools/analyse_logistics_hub.py
```

[Scenario assumptions](../../tests/scenarios/pepper_valley_logistics_hub_trial.json). [Full hub/capacity results](../../reports/balance/logistics_hub_trial_2026-09-19.json). The model checks the purchase-price markup, adjacency of every route edge, coverage of the optimized corridor and the recurring-cost inequality against both benchmarks. No recipe CSV, live tariff or shipment simulation changed.

Economic design targets in the dynamic-fee analyser are now reported as pass/fail findings rather than assertions that prevent a report from being written. This matters here: returning to 0.5% makes the furnace’s incremental contribution slightly negative (about −£0.14) at the mountain coefficient, even though Pepper Valley expansion remains positive. Negative findings must remain visible rather than aborting the experiment.
