#!/usr/bin/env python3
"""Four chain sizes: tile-local consolidation model plus engine congestion quotes."""
import csv
import json
import math
import subprocess
from collections import defaultdict
from decimal import Decimal
from pathlib import Path
from analyse_hub_rounding_weight import consumption
from run_tests import find_godot
ROOT = Path(__file__).resolve().parents[1]
OUT = Path('/tmp/pepper-consolidation')

def consolidate(events, weights, capacity=100):
    """Periodic dispatch events: origin/departure history deliberately not a key.

    Whole goods units use weighted payload; split stacks, not individual units.
    Bulk solids and general dry cargo are different equipment pools. All goods
    in these fixtures have unit weights 2 or 5, making descending packing exact.
    Arrival turn is the local availability turn, not the original departure turn.
    """
    groups = defaultdict(lambda: defaultdict(int))
    for e in events:
        if e['operator'] != 'hub':
            continue
        equipment = 'dry_bulk' if e['good'] in {'g_001', 'g_002', 'g_003'} else 'general_dry'
        key = (e.get('available_turn', 0), e['from'], e['to'], equipment)
        groups[key][e['good']] += e['quantity']
    result = []
    for key, cargo in sorted(groups.items()):
        loads = []
        for good in sorted(cargo, key=lambda g: (-weights[g], g)):
            for _ in range(cargo[good]):
                weight = weights[good]
                if weight > capacity:
                    raise ValueError('An indivisible unit exceeds vehicle payload')
                slot = next((i for i, used in enumerate(loads) if used + weight <= capacity), None)
                if slot is None:
                    loads.append(weight)
                else:
                    loads[slot] += weight
        assert sum(loads) == sum(weights[g] * q for g, q in cargo.items())
        assert all(0 < q <= capacity for q in loads)
        result.append(dict(zip(('available_turn', 'from', 'to', 'equipment'), key), cargo=dict(cargo), payloads=loads, lc=len(loads)))
    return result

def main():
    prior = json.loads((ROOT/'reports/balance/pepper_three_by_three_2026-09-19.json').read_text())['results']
    contract = json.loads((ROOT/'tests/scenarios/logistics_hub_lc_weights.json').read_text())
    goods = {r['ID']: r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    named = {r['internal_name']: r for r in goods.values()}
    weights = {g: contract['lc_weights'][r['transport_class']] for g, r in goods.items() if r['transport_class'] in contract['lc_weights']}
    cases = [(k, v, 1) for k, v in prior.items()] + [('ten_factories', prior['five_factories'], 2)]
    OUT.mkdir(exist_ok=True)
    workloads = {n: [dict(s, quantity=s['quantity']*copies) for s in r['streams']] for n, r, copies in cases}
    (OUT/'workloads.json').write_text(json.dumps(workloads))
    with (OUT/'run.log').open('w') as log:
        run = subprocess.run([find_godot(), '--headless', '--path', str(ROOT), '--log-file', str(OUT/'godot.log'), 'res://tools/pepper_consolidation_quote_probe.tscn'], stdout=log, stderr=subprocess.STDOUT, timeout=120)
    assert run.returncode == 0 and 'SCRIPT ERROR' not in (OUT/'run.log').read_text(), (OUT/'run.log').read_text()
    quotes = json.loads((OUT/'quotes.json').read_text())
    rows = {}
    for name, old, copies in cases:
        events = [dict(t, quantity=t['quantity']*copies, available_turn=0) for t in old['trace']]
        batches = consolidate(events, weights)
        # Splitting orders or changing their historic origin must not alter loads.
        split = [dict(e, quantity=1, original_origin=str(i)) for e in events for i in range(e['quantity'])]
        assert consolidate(split, weights) == batches
        # A different availability turn or opposite direction must not consolidate.
        e = next(e for e in events if e['operator']=='hub')
        assert len(consolidate([e, dict(e, available_turn=1)], weights)) == 2
        assert len(consolidate([e, dict(e, **{'from':e['to'], 'to':e['from']})], weights)) == 2
        lc = sum(b['lc'] for b in batches)
        qty = {g: consumption(Decimal(q)*Decimal(lc)/Decimal(125)) for g,q in {'hydraulic_components':2,'tyres':4,'fuels':6}.items()}
        running = sum(q*(float(named[g]['base_price'])*1.055 + (.03 if g=='fuels' else .05)*1.75) for g,q in qty.items())
        generic = {k: v*copies for k,v in old['generic_carrier'].items()}
        base = sum(q['base'] for q in quotes[name]['quotes'])
        assert abs(base-generic['inland_freight']) < .001
        surcharge = sum(q['congestion'] for q in quotes[name]['quotes'])
        saved = copies*old['hub']['covered_freight_saved']
        no_congestion_profit = generic['profit']
        generic['profit'] -= surcharge
        generic['congestion'] = surcharge
        generic['profit_before_congestion'] = no_congestion_profit
        vehicles = math.ceil(lc/10)
        vehicle_unit = old['hub']['vehicle_capex']/old['hub']['vehicles']
        advantage = saved-running
        hub = {'profit':generic['profit']+advantage,'profit_before_congestion':no_congestion_profit+advantage,
               'lc':lc,'vehicles':vehicles,'vehicle_capex':vehicles*vehicle_unit,'operating_inputs':qty,'running_cost':running,
               'base_carrier_freight_remaining':generic['inland_freight']-saved,'congestion_retained':surcharge,'freight_replaced':saved,
               'advantage_over_carrier':advantage,'vehicle_only_payback_turns':vehicles*vehicle_unit/advantage if advantage>0 else None,
               'batches':batches,'payload_sensitivity_lc':{str(c):sum(b['lc'] for b in consolidate(events,weights,c)) for c in (50,100,200)}}
        rows[name] = {'middleman_profit':copies*old['middleman']['profit'],'generic_carrier':generic,'hub':hub,'engine_transport_quotes':quotes[name]}
    report = {'status':'Full-output periodic model. First three carrier rows reconcile with recorded steady runs. Fourth uses engine freight quotes at full throughput, not a passing production simulation. Middleman and hub remain design models.',
              'assumptions':{'consolidation':'Default: same available turn, tile, directed next edge and compatible equipment; origins and original departure turns do not matter. Repack at each covered meeting tile; no extra travel or holding turn.',
              'timing':'One batch per recurring stream per turn; phase-aligned periodic arrivals available at local dispatch. This is a steady scheduling assumption, not replay of engine intra-turn arrival events.',
              'payload':'Working value 100 weighted units per load, 1 LC per load-edge; apply user cargo weights once. Payload is not yet a calibrated gameplay constant. Separate bulk coal/ores from general dry cargo.',
              'congestion':'Engine prices a complete recurring full-throughput pipeline. Keep its entire surcharge in both direct models as a conservative interim network expense; hub-specific congestion costing is not implemented. Consolidation does not reduce goods-unit congestion.',
              'unchanged':'Existing prices, recipes, 0.5% middleman ad valorem, port fees, warehouse costs and layout; fourth scales stock costs from five-factory baseline. Hub recipe 125 LC, 10 LC per vehicle; diesel variant.',
              'exclusions':'Hub construction, wages, power, maintenance, financing and capital recovery not priced. Fourth production remains blocked by conservative input-order reservation; no physical warehouse-cap claim.'},'results':rows}
    target = ROOT/'reports/balance/pepper_four_by_three_consolidated_2026-09-19.json'
    target.write_text(json.dumps(report,indent=2)+'\n')
    for n,r in rows.items():
        print(n, 'middleman', round(r['middleman_profit'],2), 'carrier',round(r['generic_carrier']['profit'],2),'hub',round(r['hub']['profit'],2),'LC',r['hub']['lc'],'congestion',round(r['generic_carrier']['congestion'],2),'payload sensitivity',r['hub']['payload_sensitivity_lc'])

if __name__=='__main__':
    main()
