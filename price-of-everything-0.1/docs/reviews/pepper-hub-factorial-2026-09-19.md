# Hub factorial trial: optimise L2 profit minus L1 profit

The explicit user objective is **higher total hub profit with L2 handoff than L1**, with each level choosing its best handoff. This is different from equal hub-versus-carrier advantages.

The requested four experiments were tested independently and together: unchanged recipe/capacity, differentiated inputs, 300 LC for rail, and both changes. Two additional level-specific sensitivities diagnose the negative delta. These are operating-economic models, not adopted gameplay changes or production-qualified runs.

## Results with accumulated consumption

These numbers assume consumption accumulates across turns; whole-unit service purchases cover subsequent usage. This explicitly replaces the earlier minimum-one-per-good every active turn. Original diesel input quantities are 2 hydraulics + 4 tyres + 6 fuel. Differentiated quantities are 1.5 hydraulics + 3 tyres + 6 fuel. Road operating capacity remains 125 LC; this comparison actually operates local hub movements by rail.

| Experiment | L1 hub profit | L2 hub profit | **L2 − L1** |
| --- | ---: | ---: | ---: |
| Original inputs; 125 LC at both levels | £176.91 | £175.35 | **£-1.55** |
| Differentiated inputs; 125 LC at both levels | £179.11 | £176.63 | **£-2.49** |
| Original inputs; 300 LC at both levels | £184.69 | £179.85 | **£-4.85** |
| Differentiated inputs; 300 LC at both levels | £185.61 | £180.38 | **£-5.24** |
| Original inputs; L1 125 / L2 300 | £176.91 | £179.85 | **£+2.94** |
| Differentiated inputs; L1 125 / L2 300 | £179.11 | £180.38 | **£+1.27** |

The four requested flat-capacity experiments all favour L1. The combined change maximizes absolute profit in both levels, but worsens the desired delta: L1 benefits more from cheaper operating LC because it needs 26 local LC instead of L2's 15.

The best L1 handoff is tile_5_6, facing the port; the best L2 handoff is central tile_5_5. Both external carrier bills are £11.82, but three owned L2 rail tiles cost £16.20 versus £9 at L1. Therefore the L2 advantage reduces to:

`L2 minus L1 profit = L1 operating inputs − L2 operating inputs − £7.20`

At 300 LC for both levels with the original recipe, L1's entire operating-input bill is only £5.56. Even eliminating all L2 input consumption would not recover the £7.20 additional upkeep. With differentiated inputs, L1's bill falls further to £4.64. Equal rail efficiency cannot deliver the objective at this workload without changing another cost or benefit.

## A level-dependent capacity meets the objective

Keep roads and L1 rail at 125 LC per recipe; give L2 rail 300 LC per recipe. With the original inputs, L2 gains £2.94/turn over L1; differentiated inputs give a smaller £1.27 advantage but slightly higher absolute L2 profit.

Holding L1 at 125, the L2 recipe capacity must exceed approximately **156.6 LC with original inputs**, or **203.8 LC with differentiated inputs**, to cross over. At 300, both clear that operating threshold. This does not establish payback on rail upgrades or hub construction: those capital costs and hub overhead remain excluded.

For the stated goal of increasing the L2-minus-L1 delta, the original recipe with level-specific 125/300 capacity is the stronger tested candidate. If the differentiated-input hierarchy is preferred for its maintenance frequency, combine it with the same level-specific capacity while accepting the narrower margin. Neither candidate was silently promoted to default.

## Existing rounding control

With minimum one of each positive good every active turn, **all six cases still cost £17.96/turn** at the selected workloads. L1 earns £172.29, L2 £165.09, and the delta remains **−£7.20**. The numerical rates cannot deliver the table above unless consumption accounting changes too.

## Actual local rail and congestion accounting

The quote fixture now explicitly operates local covered hub paths on rail, not road movements receiving a discount merely because their outside carrier is a train. Every local covered path fits one rail leg at both levels, and installed rail levels are asserted. Physical-edge LC remains 26 at the best L1 gateway and 15 at the best L2 gateway, using the same provisional payload and equipment pools.

Keep the physical shipment journey continuous across an operator handoff. Treating the two billing records as independent physical journeys counts the same-mode gateway twice and creates artificial congestion. The model stitches those route legs before invoking the engine's per-turn flow accounting, while charging only the external carrier's work. The selected handoffs are congestion-free at both levels; no result relies on a double-counted gateway surcharge.

This is a quote/flow model, not live hub gameplay. Shared dispatch timing, the warehouse-cost estimate and full output remain controlled assumptions. Rail-specific fleet equipment is not yet defined, so the earlier abstract fleet capital is retained rather than claiming a realistic owned-rail investment case. Construction, hub overhead, empty repositioning and inventory effects of timing changes remain unpriced.

## Reproduction

```sh
python3 tools/analyse_hub_factorial.py
```

The L1/L2 engine probes run in parallel with isolated runtime/log/output paths. Every experiment considers all seven covered handoffs and selects by operating profit, then fleet capital and LC. The report includes both accounting rules, all handoffs, carrier comparisons and physical flow records.

[Full report](../../reports/balance/pepper_hub_factorial_2026-09-19.json).
