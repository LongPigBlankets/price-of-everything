# Systemic recipe formula

Prices come from a canonical, non-recycling base recipe per good. Workforce is fixed from building skill mix and input throughput; it is not back-solved from margin. Targets are pre-tax cash after one-turn market freight and a one-turn working-inventory warehouse reserve.

- Canonical prices solved in 33 iterations
- Single-output recipes in their target profit band after formula output quantities: 117 / 124
- Canonical supply links requiring more than one supplier building: 0 / 117
- Workload factor: `clamp(0.7, 1.3, sqrt(max(input_qty, 10) / 30.0))`
- Recommended outputs above 36 use a nearby multiple of 5 or 12, while retaining canonical one-building supply floors.
