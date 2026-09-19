#!/usr/bin/env python3
"""Fuel-anchored 1/.5/.25/.125 hub input-rate sensitivity."""
import csv,json
from decimal import Decimal
from pathlib import Path
from analyse_hub_rounding_weight import consumption
ROOT=Path(__file__).resolve().parents[1]
def main():
    goods={r['internal_name']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    prior=json.loads((ROOT/'reports/balance/pepper_hub_consumption_sensitivity_2026-09-19.json').read_text())
    unit={g:float(goods[g]['base_price'])*1.055+(.03 if g=='fuels' else .05)*1.75 for g in ['fuels','tyres','hydraulic_components','lithium_battery','sodium_battery']}
    profiles={
        'diesel':{'fuels':6,'tyres':3,'hydraulic_components':1.5},
        'lithium_electric':{'lithium_battery':.75,'tyres':3,'hydraulic_components':1.5},
        'sodium_electric':{'sodium_battery':.75,'tyres':3,'hydraulic_components':1.5}}
    rows={}
    for mode,r in prior['results'].items():
        lc=r['selected']['lc'];rows[mode]={}
        for name,recipe in profiles.items():
            raw={g:q*lc/125 for g,q in recipe.items()}
            rounded={g:consumption(Decimal(str(q))*Decimal(lc)/125) for g,q in recipe.items()}
            avg_cost=sum(q*unit[g] for g,q in raw.items());rounded_cost=sum(q*unit[g] for g,q in rounded.items())
            margin=r['hub_break_even_running_cost']-avg_cost
            rows[mode][name]={'lc':lc,'average_goods_per_turn':raw,'rounded_goods_per_turn':rounded,'average_cost':avg_cost,'rounded_cost':rounded_cost,
                'average_advantage_over_carrier':margin,'rounded_advantage_over_carrier':r['hub_break_even_running_cost']-rounded_cost,
                'average_profit':r['generic_profit']+margin,'vehicle_only_payback_turns':r['selected']['vehicle_capex']/margin if margin>0 else None}
    report={'status':'Candidate sensitivity, not implemented gameplay. Effective differentiated rates require accumulated use across turns; positive per-turn minima still suppress rate differences at these volumes.',
        'interpretation':'Common fuel-relative rate: fuel1, tyres.5, hydraulics.25, battery/specialist input.125; fuel stays6 per125LC. These are not multipliers separately applied to every old recipe quantity.',
        'profiles_per_125_lc':profiles,'delivered_unit_prices':unit,'results':rows,
        'assumptions':'Battery replaces fuel, preserving previous diesel/electric variants; no extra specialist good added without specification. Same compact ten-building/four-tile routes and handoffs, prices, fleet, port, warehouse estimate and upkeep. Averages assume accumulated usage; no initial reserve inventory, hub overhead, construction, amortization or production simulation.'}
    (ROOT/'reports/balance/pepper_hub_differentiated_inputs_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    for mode,variants in rows.items():
        for name,r in variants.items():print(mode,name,'cost',round(r['average_cost'],4),'margin',round(r['average_advantage_over_carrier'],4),'rounded cost',round(r['rounded_cost'],4),'payback',r['vehicle_only_payback_turns'])
if __name__=='__main__':main()
