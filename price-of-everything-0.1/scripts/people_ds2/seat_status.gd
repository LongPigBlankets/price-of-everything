extends RefCounted
## One council seat's state, read from the engine (docs/people-ds2-plan.md §6): the boardroom's lamp, chair,
## folder and padlock, and the words its hover gives, all read this one helper, so they cannot disagree.
##
##   filled  an advisor sits there: the lamp green when the seat returns more than it costs (net above zero),
##           amber when not; the bonus, salary and net the council shows (AdvisorState's own quotes)
##   open    the company has the seat and room on the council: the chair pulled out, "Assign advisor"
##   full    the company has the seat but the council is at its cap: the folder closed, no padlock
##   locked  the seat is not open yet (the Executive Search research opens the rest): the padlock

const SEATS_RESEARCH := "Executive Search"
## Short names for the seat effects' domains, as a place prints them ("Labour 10% lower").
const DOMAIN_NAMES := {
	"labour_headcount": "Labour", "maintenance": "Upkeep", "building_power": "Power use",
	"grid_buy_price": "Grid price", "grid_sell_price": "Export price",
	"transport_cost": "Freight", "transport_throughput": "Throughput",
	"loan_interest": "Loan interest", "dividend_rate": "Dividends",
	"construction_rebate": "Build rebate", "purchase_cost": "Purchases",
	"tax_rate": "Tax", "market_spread": "Spread", "market_price": "Sale prices",
}


static func seat(seat_id: String) -> Dictionary:
	var aid := AdvisorState.get_advisor_in_seat(seat_id)
	if aid != "":
		var bonus := AdvisorState.advisor_bonus_preview_per_turn(aid, seat_id)
		var salary := AdvisorState.advisor_cost_for(aid, AdvisorState.advisor_revenue_basis())
		var net := bonus - salary
		var pays := net > 0.0
		return {"state": "filled", "advisor": aid, "tone": "ok" if pays else "warn", "bonus": bonus, "salary": salary,
			"net": net, "words": "Returns more than the seat costs." if pays else "Costs more than the seat returns."}
	if not AdvisorState.is_seat_available(seat_id):
		return {"state": "locked", "advisor": "", "tone": "", "words": "Opens with %s research." % SEATS_RESEARCH}
	if AdvisorState.advisor_seats.size() >= AdvisorState.max_advisor_slots:
		return {"state": "full", "advisor": "", "tone": "",
			"words": "The council is full at %d. Unseat someone to fill this seat." % AdvisorState.max_advisor_slots}
	return {"state": "open", "advisor": "", "tone": "", "words": "Assign an advisor to this seat."}


## An effect in words: "Labour 10% lower", "Export price 10% higher".
static func effect_words(eff: Dictionary) -> String:
	var domain := str(eff.get("domain", ""))
	var pct := float(eff.get("pct", 0.0))
	var amount := ("%.0f" % absf(pct)) if is_equal_approx(absf(pct), roundf(absf(pct))) else ("%.1f" % absf(pct))
	return "%s %s%% %s" % [str(DOMAIN_NAMES.get(domain, domain.capitalize())), amount, "higher" if pct > 0.0 else "lower"]


## Every effect an advisor brings in a seat, in words.
static func effects(advisor_id: String, seat_id: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for eff in AdvisorState.advisor_seat_effect_list(advisor_id, seat_id):
		out.append(effect_words(eff))
	return out


## The seat's levers in words, for a seat nobody holds ("Transport cost, throughput, distance per turn").
static func levers(seat_id: String) -> String:
	var kit: Array = (AdvisorState.SEAT_DEFINITIONS.get(seat_id, {}) as Dictionary).get("lever_kit", [])
	var words := ", ".join(PackedStringArray(kit)).replace("-", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)
