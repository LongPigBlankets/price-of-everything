#!/usr/bin/env python3
"""Hub recipe and rounding sensitivities, with new actual L1 rail carrier quotes."""
import csv,json,math,subprocess
from decimal import Decimal
from pathlib import Path
from analyse_hub_rounding_weight import consumption
from run_tests import find_godot
ROOT=Path(__file__).resolve().parents[1];OUT=Path('/tmp/pepper-district')
def main():
    prior=json.loads((ROOT/'reports/balance/pepper_district_handoff_2026-09-19.json').read_text())
    OUT.mkdir(exist_ok=True);(OUT/'spec.json').write_text(json.dumps(prior['spec'],indent=2)+'\n');(OUT/'quotes_l1.json').unlink(missing_ok=True)
    with (OUT/'run_l1.log').open('w') as log:
        run=subprocess.run([find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'godot_l1.log'),'res://tools/pepper_district_quote_probe.tscn','--','--rail-l1'],stdout=log,stderr=subprocess.STDOUT,timeout=120)
    assert run.returncode==0 and 'SCRIPT ERROR' not in (OUT/'run_l1.log').read_text()
    engine=json.loads((OUT/'quotes_l1.json').read_text())
    named={r['internal_name']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    unit={g:float(named[g]['base_price'])*1.055+(.03 if g=='fuels' else .05)*1.75 for g in ['hydraulic_components','tyres','fuels']}
    recipe={'hydraulic_components':2,'tyres':4,'fuels':6}
    def actual(lc,scale=1):return {g:consumption(Decimal(q)*Decimal(lc)*Decimal(str(scale))/125) for g,q in recipe.items()}
    def cost(q):return sum(q[g]*unit[g] for g in q)
    rate=sum(q*unit[g] for g,q in recipe.items())/125
    common=prior['common_costs'];before=common['receipts']-common['purchases']-common['factory']-common['ports']-common['warehouse_estimate']
    modes={}
    l1=engine['modes']['rail_l1'];assert not l1['direct']['overloads']
    baseline=sum(q['charged'] for q in l1['direct']['quotes'])
    candidates={}
    for gate,data in l1.items():
        if gate=='direct':continue
        assert not data['overloads']
        lc=prior['results']['rail']['gateways'][gate]['lc']
        # The local hub road paths, stream quantities, weights and payload are
        # unchanged; reuse their validated consolidated loads, not L2 carrier LC.
        old=prior['results']['rail']['gateways'][gate]
        for q in data['quotes']:
            assert all(l['mode']=='rail' for l in q['stream']['route']['legs'])
        external=sum(q['charged'] for q in data['quotes'])
        candidates[gate]={'lc':lc,'external_freight':external,'running':cost(actual(lc)),'vehicles':math.ceil(lc/10),'vehicle_capex':old['vehicle_capex'],
            'profit':before-engine['rail_maintenance']-external-cost(actual(lc))}
    gate=max(candidates,key=lambda g:(candidates[g]['profit'],-candidates[g]['vehicle_capex'],-candidates[g]['lc']))
    selected=candidates[gate]
    modes['rail_l1']={'generic_profit':before-engine['rail_maintenance']-baseline,'generic_freight':baseline,'rail_upkeep':engine['rail_maintenance'],'selected_gateway':gate,'selected':selected,'gateways':candidates}
    old=prior['results']['rail'];selected2=old['selected']
    modes['rail_l2']={'generic_profit':old['generic_profit'],'generic_freight':old['generic_freight'],'rail_upkeep':old['infrastructure_upkeep'],'selected_gateway':old['selected_gateway'],
        'selected':{'lc':selected2['lc'],'external_freight':selected2['carrier_freight'],'running':selected2['running_cost'],'vehicles':selected2['vehicles'],'vehicle_capex':selected2['vehicle_capex'],'profit':selected2['profit']}}
    for mode,r in modes.items():
        s=r['selected'];allowance=r['generic_freight']-s['external_freight'];r['hub_break_even_running_cost']=allowance
        r['required_effective_cost_reduction']=max(0,1-allowance/s['running'])
        r['current_advantage']=s['profit']-r['generic_profit']
        r['vehicle_only_payback_turns']=s['vehicle_capex']/r['current_advantage'] if r['current_advantage']>0 else None
        rows=[]
        for scale in [1,.8,.5,.25]:
            rounded=cost(actual(s['lc'],scale));average=rate*s['lc']*scale
            rows.append({'recipe_multiplier':scale,'per_turn_rounded_goods':actual(s['lc'],scale),'per_turn_rounded_cost':rounded,'rounded_advantage':allowance-rounded,
                'accumulated_wear_average_goods':{g:q*s['lc']/125*scale for g,q in recipe.items()},'accumulated_wear_average_cost':average,'accumulated_wear_advantage':allowance-average,
                'accumulated_wear_profit':r['generic_profit']+allowance-average})
        r['sensitivity']=rows
    # Assert the existing minimum blocks every positive proportional reduction tested.
    assert all(v['per_turn_rounded_goods']=={'hydraulic_components':1,'tyres':1,'fuels':1} for r in modes.values() for v in r['sensitivity'])
    report={'status':'Sensitivity only; no operating recipe or rounding rule changed in gameplay or default contract.',
        'current_recipe':recipe,'recipe_lc':125,'current_rounding':'Half-up/minimum one per positive good per active hub per turn; idle zero',
        'delivered_unit_cost':unit,'unrounded_cost_per_lc':rate,
        'alternative':'Accumulated wear/usage across turns, purchasing or drawing whole units only when cumulative use requires them. This replaces the previously selected per-turn minimum; it is not equivalent to merely reducing the recipe. Averages exclude initial reserve stocking, consumption spikes and downtime.',
        'assumptions':'Same compact ten-building/four-tile layout, full output, three owned rail tiles, local roads L3, same prices and inventory-cost estimate. Every L1 handoff repriced with actual engine routes. No congestion in these rail cases. Hub construction/overhead, infrastructure capex, empty repositioning and production timing remain unpriced.',
        'results':modes,'l1_engine':engine}
    (ROOT/'reports/balance/pepper_hub_consumption_sensitivity_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    for mode,r in modes.items():print(mode,json.dumps({k:v for k,v in r.items() if k not in ['gateways','sensitivity']},indent=2));print('sensitivity',r['sensitivity'])
if __name__=='__main__':main()
