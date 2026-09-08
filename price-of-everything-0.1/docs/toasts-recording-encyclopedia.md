# Toasts, encyclopedia and recording mode

Repeated identical amber warnings share one active toast. NPC-owned building additions, including starting ports, produce no building toast. Sale notifications are collected across turn resolution: multiple sale records become “Last turn you sold X units of Y goods, totalling £Z.” Y counts distinct goods, even when the same good sold from several tiles. A single notification retains its existing detail copy. Immediate manual sale notifications flush together on the deferred UI cycle.

Toast backgrounds are darker. A faint white gradient behind the label shrinks from right to left over five seconds; when it reaches the left edge, the toast is removed. The text is neither faded nor covered by the overlay.

Good encyclopedia entries show a 180×180 good image and a 40px Goods Graph icon button in the name row, opening the focused graph. The Resources header uses a separate Goods Graph label and icon button.

After `debug CandC`, `hide updates` enables session-only recording mode. Decisions select their first displayed option through the normal resolver; update panels, decision popups and toasts stay hidden. Deposit notifications also take their first action without a popup (which can demolish an exhausted building). This is a gameplay-affecting cheat and marks telemetry accordingly. `show updates` restores the UI but does not undo choices already made. Manual gameplay panels remain available.
