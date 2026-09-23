# Middleman phase 2 — playable Pepper Valley

Implemented on `codex/transport-middleman-layer`, 19 September 2026. This is the scoped motor-factory prototype, not the full logistics ownership progression.

## Player-facing behavior

- **Pepper Valley Motors** is selectable in New Game (including demo), with one powered motor factory, £1,500 and no initial stock or debt. It opens a skippable five-step introduction. The introduction does not gift inputs, reset cash or replace the business when finished. Progress survives save/load.
- Every middleman buy/sell endpoint uses the existing truck glyph on a gold hex, including expanded Empire supply-chain views. Physical ports retain their existing presentation. Middleman factories trade independently: no internal supplier links or shared input stocks are inferred between them.
- The building report shows material purchase value, expected sale value, one inclusive Middleman fee, upfront operating cash, protected company commitments, required loan funding and retained private goods. Its diagnostics understand funded private procurement instead of reporting missing shared stock. Operating economics includes the fee once, with no separate outsourced warehousing bill.
- Cash commitments show routine middleman procurement separately and exclude it from exceptional purchase warnings. Previews allocate cash, credit and tile power in the same stable building order, without anticipated sales. A factory completing next turn is included in the middleman forecast.
- A review dialog permits a supported building to leave or rejoin the service. Leaving explicitly releases any paid private holdings into owned storage, subject to capacity; joining requires its physical pipeline and credit tab to be resolved. Quotes are estimates at current prices.

## Construction boundary

New motor factories built at Pepper Valley automatically join the service after normal construction completes and before that turn's production. Construction materials still use ordinary transport, quotes, prepayment, lead time and cancellation refunds. The construction forecast explains this distinction and includes material delivery in its first-sale estimate. Company loans remain available; the separate automatic building-credit tab is not opened for a new middleman factory.

No recipes, tariff rates or construction quantities changed in P2. The reusable £10,000 controlled benchmark remains separate from the £1,500 public start. The selected fee is still 0.5% of market value per unit plus cargo rate × location coefficient, calculated independently on each building's purchases and sales.

## Reproducible validation

```sh
python3 tools/run_middleman_phase0.py --phase2 --full
```

This runs the full unit suite, preserved road / three-owned-rail / five-factory baselines, the 50-turn controlled provider benchmark and a new 50-turn public-start exercise (`tools/pepper_middleman_playable.gd`). The latter runs actual TurnManager, production, construction and market-impact logic. It checks the introduction, cancellation refunds, normal material shipments, completion enrollment, separate batches, cash reconciliation, solvency and save/reload at turn 25. Random decisions and research are disabled for repeatability; prices are not reset each turn.

In the public-start exercise the second factory is ordered on turn 2 and completes on turn 9. Both subsequently sell 66 motors per turn in total. Cash remains positive, falling to approximately £1,002 after ordering construction and reaching approximately £2,007 after turn 50. This is an early-game expansion check, not a claim of indefinite steady profit: market impact and wages continue to change margins.

Windowed UI review uses `tools/middleman_p2_preview.tscn` (add `-- --menu` for the selector). Screenshots cover the New Game card, introduction, building details and expanded Empire graph. The playable exercise is also run windowed. Generated acceptance reports are retained in `reports/balance/middleman_phase2_full_gate_2026-09-19.json` and `pepper_middleman_phase2_playable_2026-09-19.json`.

## Remaining scope

Service eligibility is deliberately limited to motor manufacture at Pepper Valley; other recipes/sites and legacy saves retain existing behavior. The new start is the public experimental milestone for phases 0–2. Owned storage/local handling is P3; logistics hubs, equipment/consumption, broader mixed-mode coverage and crossover tuning remain later phases. The previously documented hub model is not activated by this work.
