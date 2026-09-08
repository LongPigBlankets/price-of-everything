# Demo interaction telemetry — schema 4

## Spreadsheet update

Replace the existing Apps Script with `tools/telemetry/Code.gs`, then deploy a **new version of the existing deployment** (Manage deployments → Edit → New version → Deploy). Keep the existing deployment URL. Do not delete either existing sheet.

On the first schema-4 upload the receiver appends these columns to `turns`:

- `encyclopedia_opened`
- `good_encyclopedia_opened`
- `goods_graph_opened`
- `goods_graph_good_selected`
- `money_panel_opened`
- `balance_panel_opened`
- `supply_chain_opened`
- `supply_chain_building_selected`
- `research_panel_opened`
- `search_used`

Each is an action count during that row's turn. Older client rows leave the columns blank (not measured); new client rows use zero when measured but unused. Existing columns and historical rows stay in place. An unexpected existing header fails explicitly rather than overwriting data. Receiver tests cover the upgrade from the current schema-3 header.

The receiver also creates `events` with columns:

`received_at, player_id, run_id, session_id, event_id, turn, playtime_s, action, interface, target_id, version`

This preserves the order within a turn and includes actions on the final unfinished turn, even if the player quits without pressing End Turn. `playtime_s` retains the existing wall-clock session/playtime definition; it is not idle-adjusted active time. Event IDs are stable across save/load and upload retries. The receiver deduplicates events by event ID and turn rows by run ID + turn, under a write lock.

## Meaning

- Opens count actual hidden-to-visible transitions, including keyboard and button routes. Closing with the same shortcut does not count. Entry points are not distinguished as keyboard versus click in this version.
- Good encyclopedia navigation carries the catalog good ID. Goods-graph selections carry its internal good name, matching that graph's selection API. Supply-chain selections carry the building instance ID. Automatic supply-chain restoration at turn refresh does not count as a click.
- `money_panel_opened` is the top-bar Treasury flyout. `balance_panel_opened` is the full Money/Balance panel.
- Search tracking discovers game LineEdits whose name or placeholder identifies a search field. The interface is the nearest ancestor script (for example `search_overlay`, `market_panel`, `research_panel`, `construct_panel_v2`, `goods_graph_world`, `building_ledger_panel`, `building_market_panel`, `good_select_panel`). It records one event after 750ms without typing, or on submission/focus exit if a burst is pending. Programmatic query prefills without focus and empty searches do not count. Typed text is never stored.
- Existing run consent gates the new capture as well. The start-screen metrics explanation now mentions panel/good/search interactions. Save snapshots preserve the event history; events checkpoint locally after interaction bursts so capture does not depend on reaching turn 10.

No spreadsheet deployment was performed by the coding agent. Update the receiver before distributing the new client. The existing HTTP delivery-acknowledgement protocol is unchanged by this patch.
