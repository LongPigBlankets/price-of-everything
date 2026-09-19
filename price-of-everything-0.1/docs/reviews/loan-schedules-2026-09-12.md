# Money notice and loan schedules — 12 September 2026

The attention notice now uses the money module's rendered global bounds, including its icon and numbers, and reads “Upcoming extra costs”. The ordinary Upcoming costs links still describe the broader next-turn total.

Treasury, Loans and Upcoming show each loan's stored interest rate in brackets and its full repayment range on a separate line. The range is inferred from remaining instalments and original repayment amounts, including grace conversion; no save schema or payment amounts changed. A transient payment-turn marker keeps dates stable during resolution and is cleared on new matches and loads.

Verification: script sweep 607 scripts, zero failed; unit suite 405 tests / 3,960 assertions passed; 100-turn E2E 723 assertions passed. Windowed trial confirmed exact rendered notice width and a loan repaying on turns 3–12 still showing that range after four payments. Forecast-to-actual checks passed for six turns. Screenshots inspected for Treasury, Loans, Upcoming and the notice. Existing Godot cleanup/RID warnings remain.

Evidence: `outputs/loan-schedules-2026-09-12/`.
