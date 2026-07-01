# Special Orders Plan

## Goal

Add early-game special orders as a Market-screen contract system. The system should create
short-lived premium demand for bootstrap goods, let the player route stockpiles or building
outputs into an active order, and pay the premium only when the full requested quantity is
delivered before the order closes.

This is the companion viability mechanic to the higher clean-slate starting cash. It should
help the first 50 turns without becoming a permanent market-price exploit.

## Goods In Cycle

Use good internal names, resolving them through `Catalog.get_good_by_internal_name`.

```gdscript
const SPECIAL_ORDER_GOODS := [
	"iron_ore",
	"iron_ingots",
	"coal",
	"steel",
	"copper_ore",
	"copper_ingots",
	"motor",
	"copper_wiring",
	"crude_oil",
	"ethylene",
	"plastics", # UI label: Plastic / Plastics
	"rubber",
	"sand",
	"concrete",
	"glass",
]
```

## State Owner

Add a new autoload, `SpecialOrderState`, rather than folding contract lifecycle into
`MarketState` or `MatchState`.

Suggested fields per active order:

- `id`
- `good_id` and `good_internal`
- `qty_required`
- `qty_committed`
- `qty_delivered`
- `premium_pct`
- `created_turn`
- `expires_turn`
- `warning_sent`
- `status`: `available`, `fulfilled`, `expired`
- `source_mode_counts`: counts committed from `tile_view` vs `building_output`

Suggested global fields:

- `active_orders`
- `fulfilled_count`
- `fulfilled_count_when_removed_by_good`
- `last_spawn_turn`
- deterministic `RandomNumberGenerator` state for save/load repeatability

Save/load this state alongside the other autoload state so active orders, cooldowns, pending
warnings, and RNG state survive a save.

## Generation Rules

Special orders are an early-game system:

- only roll from turns 1-50
- only roll on 5-turn boundaries
- roll randomly, but deterministically from the saved RNG
- allow multiple active orders at once
- cap active orders to a small number, probably 3
- at each eligible roll, spawn 0-2 orders from currently eligible goods

Eligibility:

- exclude goods that already have an active order
- after a good leaves the cycle, it cannot re-enter until at least 2 other special orders have
  been fulfilled
- track this by comparing `fulfilled_count` to `fulfilled_count_when_removed_by_good[good_internal]`

Quantity and duration:

- pick a target production window of 5-10 turns
- find the baseline one-building recipe for that good, preferring a single mine, furnace, factory,
  or refinery recipe
- `qty_required = one_building_output_per_turn * target_production_turns`
- `expires_turn = created_turn + target_production_turns + 10`
- the extra 10 turns is the logistics/breathing room

Premium:

- start with a data constant, not hardcoded UI text
- suggested first pass: raw goods +40%, intermediates +30%, motors +25%
- show both base value and premium value in the UI

## Fulfilment Rules

An order pays the premium only when delivered quantity reaches the full requirement before
or on `expires_turn`.

Important behavior:

- partial delivery does not pay the premium
- when a delivery brings `qty_delivered >= qty_required`, pay premium value for the required
  quantity and close the order immediately as `fulfilled`
- any over-delivery should be sold at normal market price, not premium
- if the order reaches `expires_turn` without full delivery, close as `expired`
- closing an order removes it from the active list and emits `order_closed(order_id, reason)`

Delivery should use existing transport timing where practical. The simplest first version is to
route special-order shipments to the same nearest-port market path used by market sales, but tag
those shipments with `special_order_id` instead of treating them as ordinary market sales.

## Market UI

Add Special Orders as the third tab in `scripts/market_panel.gd::_build_tabs`.

Current order:

1. Good prices
2. Buildings
3. Sales
4. Transactions
5. Movements

New order:

1. Good prices
2. Buildings
3. Special Orders
4. Sales
5. Transactions
6. Movements

Implement a `special_orders_panel.gd` control or a builder method in `market_panel.gd`. Prefer a
separate script if it grows beyond a simple table.

Each order row should show:

- good icon and display name
- required quantity
- committed/delivered progress
- premium percent
- total premium payout if fulfilled
- turns remaining
- status badge
- a disabled/empty state when no orders are active

The tab should refresh on:

- `SpecialOrderState.order_added`
- `SpecialOrderState.order_updated`
- `SpecialOrderState.order_closed`
- turn processed
- market panel visibility

## Tile View Routing

Extend the stockpile "Move or Sell" panel in `tile_info_panel_v2.gd`.

Destination choices become:

- Market
- Tile
- Special Order, shown only when the selected good has at least one active order

When Special Order is selected:

- show an order selector if more than one active order needs the same good
- show the remaining needed quantity
- clamp default quantity to the remaining needed amount
- confirm calls `SpecialOrderState.queue_from_tile(tile_id, order_id, good_id, qty)`

Tile-view movements are explicitly cancellable:

- tag them with `source_mode = "tile_view"`
- when the order is fulfilled or expires, cancel any still-pending tile-view movement for that
  order immediately
- return cancellable units to the source tile using existing stockpile capacity/overflow behavior
- emit a notification saying the special-order movement was cancelled

## Building Detail Routing

Extend the output route row in `building_detail_panel.gd::_make_output_route_row`.

Destination choices become:

- Market
- Store on tile
- Send to other tile
- Special Order, shown only when this output good has active orders

Choosing Special Order:

- stores a special-order destination for this instance/good, probably with a sentinel such as
  `__special_order__:<order_id>`
- only this output good routes to the order
- does not change global sell mode
- each produced batch is committed until the order closes

When an order closes:

- stop routing that building output to the order
- do not silently fall back to ordinary market sale
- mark the instance/good as requiring route reset
- show a dialog for each affected building/output, or a single stacked dialog listing all affected
  building outputs, asking the player to choose Market, Store on tile, or Send to other tile
- building detail and tile view should show a visible "route needs reset" state until the player
  picks a new destination

## Production Integration

In the production output path, branch output destinations:

- normal tile destination: unchanged
- normal market destination: unchanged
- special-order destination: call `SpecialOrderState.queue_from_building(instance_id, source_tile,
  order_id, good_id, qty)`
- route-reset-required destination: do not market-sell; hold on tile or block routing until reset

The special-order queue should create transport-delayed deliveries and update `qty_committed`
immediately so the UI can show commitment before arrival.

## Notifications

Use `EventScheduler.emit_event` for persistent bell notifications and `MatchState.request_toast`
for short feedback.

Required events:

- fulfilled: success/info notification when a special order is met
- warning: warning notification when an order has 2 turns left and `qty_committed > 0`
- expired: warning/info notification when an order expires with committed goods
- movement cancelled: notification when a tile-view special-order movement is cancelled because
  the order closed
- route reset required: notification/dialog when building outputs were pointed at a closed order

The 2-turn warning should fire once per order.

## Tests

Unit tests:

- generation only occurs on 5-turn boundaries and only through turn 50
- inactive goods can re-enter only after 2 other orders are fulfilled
- active-order cap allows multiple orders but prevents runaway lists
- quantity/deadline calculation is based on one producer for 5-10 turns plus 10 turns
- full delivery pays premium and closes the order
- partial delivery by expiry does not pay premium
- over-delivery only pays premium on required quantity
- 2-turn warning fires once only when committed quantity is positive
- tile-view pending movements are cancelled on close
- building-output destinations enter route-reset-required state on close
- save/load preserves active orders, cooldowns, committed quantities, warnings, and RNG state

UI/headless tests:

- Market panel has Special Orders as tab index 2
- active orders render rows with qty, deadline, and premium
- tile view shows Special Order as a destination only for matching goods
- building detail shows Special Order as an output destination only for matching goods
- closing an order raises the reset dialog/notification for each affected building

E2E:

- add a short bootstrap scenario that receives at least one early raw-good order and fulfils it
- assert the premium changes cash only after full delivery
- assert expired partial fulfilment does not pay the premium

## Implementation Slices

1. Data and state: add `SpecialOrderState`, autoload registration, save/load, deterministic RNG,
   and pure unit tests.
2. Turn lifecycle: generate orders, tick expiry/warnings, close orders, and emit events.
3. Market UI: add the third tab and read-only active-order rows.
4. Tile view: add special-order destination and cancellable movements.
5. Building detail and production: add output routing to special orders plus route-reset-required
   handling.
6. Notifications/dialogs: fulfilment, two-turn warning, cancellation, and route reset prompts.
7. E2E update: add a special-order bootstrap check and then re-run the economy scenario with the
   new starting-cash setup.
