# Middleman: catalogue and map rollout

Implemented 19 September 2026. This expands material-service eligibility in `middleman_v1` games, without changing other starts, factory recipes/prices or carrier tariffs. Logistics hub work is paused and is not active in gameplay.

## Eligibility and power

Every player-owned building recipe with a tradeable material input or output can use the intermediary, at every map location. Existing independent input/output switches remain authoritative. New construction joins automatically only where the existing `middleman_new_buildings` rule is enabled. Existing managed buildings are not silently switched.

Electricity is excluded from the intermediary basket. Consumers retain ordinary grid/power allocation; fuelled generators can procure fuel and water through the intermediary while their electricity remains in the existing power/grid system. Pure electricity producers and infrastructure without material recipes need no intermediary contract. Building/recipe research and demo gates remain intact.

Non-tradeable goods such as wastewater cannot be fabricated as purchases or sold for money. They retain ordinary shared-stock handling, reservations and storage charges. Their presence does not exclude a building's other tradeable materials from the service.

## Fee per traded unit

`0.005 × current market reference price + cargo tariff × location coefficient`

| Cargo class | Tariff |
|---|---:|
| Light solid | £0.02 |
| Heavy solid | £0.05 |
| Ultra-heavy | £0.50 |
| Safe liquid | £0.05 |
| Hazardous liquid | £0.10 |
| Gas | £0.125 |

Buy and sell transactions remain independent. Transport and provider storage are included; factory costs, electricity and applicable carbon charges remain separate. The reference price is the ordinary current market price before purchase markup.

The user explicitly retained £0.125 for gases after reviewing oxygen: at base price £0.275, its fee ranges from £0.132625 in an urban port area to £0.313875 in mountains. The latter exceeds sale value. Existing negative-net settlement protection retains the paid output and prevents another batch until it can be sold or released to owned storage; it does not silently reduce the tariff. This is not a claim that every recipe/location is profitable.

At coefficient 1.5, fees as a percentage of base value are approximately 0.53–0.66% for current light solids, 2.55–13.70% for safe liquids, 2.49–14.93% for hazardous liquids, 14.99% for nitrogen and 68.68% for oxygen. These are per-side material-fee checks, not a broader balance study. Full per-good evidence is in `reports/balance/middleman_full_catalogue_tariffs_2026-09-19.json`.

## Geography

Urban areas are connected components of urban hexes, using the game's existing hex neighbours. Sparse city-name metadata is not used to guess their extent.

- Any urban component containing a port on one of its own tiles: **1.05**, irrespective of size. Authored ports and completed runtime port buildings count; an adjacent non-urban port does not.
- Other urban components with four or more tiles: **1.25**.
- Other urban components with one to three tiles: **1.5**.
- Rural/hill tiles adjacent to an urban tile: **1.75**.
- Other rural/hill locations: **2.0**; maritime locations also use this fallback.
- Mountains: **2.5**, including those beside cities or ports.

Port construction/removal invalidates the coefficient cache. Quotes and the next funded batch recompute location coefficients. Already-paid input receipts retain their original fees. Pepper Valley's two original benchmark coefficients remain 1.5 and 1.75.

## Generalized execution

No-material-input recipes can sell their output without a fictitious input-consumption receipt. Multi-product recipes collect every coproduct before exactly-once settlement; the old single-output receipt guard no longer drops later products. Purchased inputs and their applicable operating carbon charge are funded before production, without borrowing against anticipated sales. Power remains on its existing turn path.

Save format 14 prevents older clients with a restricted goods basket from attempting the expanded contracts. Migration does not enroll buildings or alter other-start policies. Private goods, independent modes and existing shipments keep their ownership.

## Verification

Tests exercise all eligible catalogue recipe quotes, every tariff class, geography/port changes, no-input sources, actual multi-product production, a fuelled generator's grid settlement, retained non-tradeable byproducts, cash reconciliation and save/reload. The preserved road, three-owned-rail and five-factory benchmarks, 50-turn middleman/start runs and seven 60-turn P3 cases pass with their established economics.

Construction procurement through the intermediary, other-start rollout, broader balance and additional UI completeness remain outside this change.

Validation: full suite **4,774 passed / 0 failed**; final focused run **897 passed / 0 failed** after the no-input storage attribution and grid-label checks. Windowed review covers chemical coproducts and fuelled power generation. See `reports/balance/middleman_catalogue_rollout_validation_2026-09-19.json`.


### Tile stockpile and building ledger

The Stockpile tab centres independent input/output intermediary checkboxes when all
player material flows use the intermediary. Mixed tiles retain those controls above
the normal stockpile, with **Manage Logistics** opening the building ledger. Grid
power and buildings with no material recipe do not require physical stockpile controls;
non-tradeable physical byproducts still do. Hiding the stockpile never deletes owned
stock or changes outstanding shipments.

Tile switches affect player-owned buildings only. Each changed building is validated,
then all private goods released on that side must fit the shared warehouse together,
before any mode changes. Leaving the intermediary reuses the building supplier warning
and its session-wide “Do not show again” setting. Cancelling restores the checkbox.

The ledger's **Inputs** and **Outputs** columns show distinct endpoints across all
recipe goods: cream truck, port, supplying building, stockpile, or electricity grid.
Tooltips identify the provider or tile coordinates. Clicking any endpoint opens that
row's building directly on its logistics screen. The former goods-output column is
labelled **Produces** to distinguish it from routing.

Validation: `tests/unit/test_tile_logistics.gd` covers atomic bulk release, credit and
ownership guards, independent sides, retained stock, grid exceptions, and ledger
supplier/split-route descriptors. `tools/middleman_p2_preview.tscn -- --tile-ledger`
checks cancellation, confirmation, both stockpile states, ledger opening and logistics
navigation using the actual game UI.

### Global logistics controls

Transport and shipments now has independent **Source of Inputs** and **Source of
Outputs** controls in its footer. A truck denotes intermediary service; a port denotes
player-managed sources. Mixed fleets show both icons and “Mixed”; their button offers
to consolidate that side onto the intermediary. Once all applicable buildings use it,
the button offers to switch to the player's own source.

Both directions always open a Confirm/Cancel modal. Its affected count includes only
existing player material buildings whose selected side will change. The modal includes
the port-arrival/revenue-delay warning; when joining the intermediary, it labels that
warning as applying to use of the player's own source. Managed outputs initially retain
production in their tile stockpiles, as individual and tile switches do; the modal
explains how to choose Global Market for port sales. Electricity stays on the grid.

The confirmation captures the displayed building selection. Confirm revalidates that
selection and checks all private-goods releases per tile before changing any building.
Cancel has no simulation effect. These controls change existing buildings, not the
start's defaults for future construction. Windowed verification is available through
`tools/middleman_p2_preview.tscn -- --global-logistics`.
