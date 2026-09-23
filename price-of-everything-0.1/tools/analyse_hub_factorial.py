#!/usr/bin/env python3
"""Compare separate and combined hub levers against the L2-minus-L1 profit target."""
import csv,json,subprocess
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from pathlib import Path
from analyse_hub_rounding_weight import consumption
from run_tests import find_godot
ROOT=Path(__file__).resolve().parents[1];OUT=Path('/tmp/pepper-district')
def main():
    prior=json.loads((ROOT/'reports/balance/pepper_district_handoff_2026-09-19.json').read_text())
    OUT.mkdir(exist_ok=True);(OUT/'spec.json').write_text(json.dumps(prior['spec'],indent=2)+'\n')
    godot=find_godot()
    def probe(level):
        output=OUT/f'quotes_owned_rail_l{level}.json';output.unlink(missing_ok=True)
        logpath=OUT/f'owned_l{level}.log'
        with logpath.open('w') as log:
            run=subprocess.run([godot,'--headless','--path',str(ROOT),'--log-file',str(OUT/f'godot_owned_l{level}.log'),'res://tools/pepper_district_quote_probe.tscn','--','--owned-rail']+(['--rail-l1'] if level==1 else []),stdout=log,stderr=subprocess.STDOUT,timeout=120)
        assert run.returncode==0 and 'SCRIPT ERROR' not in logpath.read_text(),logpath.read_text()
        return json.loads(output.read_text())
    with ThreadPoolExecutor(max_workers=2) as pool:
        engine=dict(zip((1,2),pool.map(probe,(1,2))))
    goods={r['internal_name']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    unit={g:float(goods[g]['base_price'])*1.055+(.03 if g=='fuels' else .05)*1.75 for g in ['hydraulic_components','tyres','fuels']}
    recipes={'original':{'hydraulic_components':2,'tyres':4,'fuels':6},'differentiated':{'hydraulic_components':1.5,'tyres':3,'fuels':6}}
    common=prior['common_costs'];before=common['receipts']-common['purchases']-common['factory']-common['ports']-common['warehouse_estimate']
    experiments=[('current','original',125,125),('differentiated_only','differentiated',125,125),('rail_300_only','original',300,300),('combined','differentiated',300,300),
                 ('level_specific_original','original',125,300),('level_specific_differentiated','differentiated',125,300)]
    results={}
    for name,recipe_name,cap1,cap2 in experiments:
        by_accounting={}
        for accounting in ['per_turn_minimum','accumulated_usage']:
            levels={}
            for level,capacity in [(1,cap1),(2,cap2)]:
                data=list(engine[level]['modes'].values())[0];upkeep=engine[level]['rail_maintenance']
                generic=before-upkeep-sum(q['charged'] for q in data['direct']['quotes']);candidates={}
                for gate,case in data.items():
                    if gate=='direct':continue
                    # Same prescribed covered paths and quantities in both levels:
                    # local rail travel duration differs from road, physical edge LC does not.
                    old=prior['results']['rail']['gateways'][gate];lc=old['lc']
                    raw={g:q*lc/capacity for g,q in recipes[recipe_name].items()}
                    qty=raw if accounting=='accumulated_usage' else {g:consumption(Decimal(str(q))*Decimal(lc)/Decimal(capacity)) for g,q in recipes[recipe_name].items()}
                    run=sum(q*unit[g] for g,q in qty.items());carrier=sum(q['charged'] for q in case['quotes'])
                    candidates[gate]={'lc':lc,'recipe_capacity':capacity,'operating_goods':qty,'running_cost':run,'carrier_cost':carrier,'carrier_surcharge':sum(q['charged']-q['base'] for q in case['quotes']),
                        'profit':before-upkeep-carrier-run,'vehicles':old['vehicles'],'vehicle_capex':old['vehicle_capex'],'overloads':case['overloads']}
                best=max(candidates,key=lambda g:(candidates[g]['profit'],-candidates[g]['vehicle_capex'],-candidates[g]['lc']))
                chosen=candidates[best];assert not chosen['overloads'],(name,level,best,chosen['overloads'])
                levels[str(level)]={'generic_profit':generic,'upkeep':upkeep,'selected_gateway':best,'selected':chosen,'advantage_over_generic':chosen['profit']-generic,'all_gateways':candidates}
            by_accounting[accounting]={'levels':levels,'delta_l2_minus_l1':levels['2']['selected']['profit']-levels['1']['selected']['profit'],'delta_advantage_l2_minus_l1':levels['2']['advantage_over_generic']-levels['1']['advantage_over_generic']}
        results[name]={'recipe':recipes[recipe_name],'rail_capacity_by_level':{'1':cap1,'2':cap2},'accounting':by_accounting}
    threshold={}
    for recipe_name,recipe in recipes.items():
        cost_per_recipe=sum(q*unit[g] for g,q in recipe.items())
        # Best tested L1/L2 gateways have the same base external carrier bill.
        l1_run=cost_per_recipe*26/125;budget=l1_run-7.2
        threshold[recipe_name]={'rail_l1_capacity':125,'l2_running_cost_must_be_below':budget,'l2_recipe_capacity_must_exceed':cost_per_recipe*15/budget}
    report={'objective':'Optimise L2 hub operating profit minus L1 hub operating profit; each level chooses its best reachable covered handoff.',
        'status':'Four requested factorial sensitivities plus two explicitly labelled level-specific alternatives. No gameplay rates or accounting changed.',
        'assumptions':{'local_mode':'Actual owned local rail over the same shortest covered paths. Each path fits one rail leg at both levels, and every tile is checked for the installed level. LC remains weighted physical-edge load movements.',
        'handoff_congestion':'Physical same-mode journeys remain continuous across operator handoff, so the gateway is not counted twice. Quotes are split by operator. Selected handoffs have no congestion at either level.',
        'inventory':'Common warehouse-cost estimate retained; changed travel timing and gateway inventory are not production-validated.',
        'fleet':'Existing abstract vehicle investment retained for controlled comparison; rail-specific fleet equipment and capital remain undefined, so no realistic rail investment return is claimed.',
        'costs':'Three owned rail tiles cost9 atL1 and16.2 atL2. Same prices, factory outputs, port fees and layout; construction, hub overhead and empty repositioning unpriced.',
        'rounding':'Existing per-turn minimum retained as control. Accumulated-use results require an explicit accounting change; they are long-run averages, not constant cash outflow.'},
        'delivered_prices':unit,'results':results,'level_specific_crossover_thresholds':threshold,'engine':engine}
    (ROOT/'reports/balance/pepper_hub_factorial_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    for n,v in results.items():
        a=v['accounting']['accumulated_usage'];l=a['levels'];print(n,'L1',round(l['1']['selected']['profit'],4),'L2',round(l['2']['selected']['profit'],4),'DELTA',round(a['delta_l2_minus_l1'],4),'gates',l['1']['selected_gateway'],l['2']['selected_gateway'])
    print('thresholds',threshold)
if __name__=='__main__':main()
