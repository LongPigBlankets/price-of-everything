#!/usr/bin/env python3
"""Fourth-row scale sensitivity, with explicit independent versus pooled batches."""
import json
import csv
import math
from decimal import Decimal
from pathlib import Path
from analyse_hub_rounding_weight import consumption
ROOT=Path(__file__).resolve().parents[1]
def main():
    def load(p):return json.loads((ROOT/p).read_text())
    prior=load('reports/balance/pepper_three_by_three_2026-09-19.json')['results']['five_factories']
    weights=load('tests/scenarios/logistics_hub_lc_weights.json')['lc_weights']
    goods={r['ID']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    named={r['internal_name']:r for r in goods.values()}
    fleet_unit=prior['hub']['vehicle_capex']/prior['hub']['vehicles']
    independent=prior['hub']['weighted_lc']*2
    pooled=sum(math.ceil(t['quantity']*2/100)*weights[goods[t['good']]['transport_class']] for t in prior['trace'] if t['operator']=='hub')
    def costs(lc):
        recipe={'hydraulic_components':2,'tyres':4,'fuels':6}
        quantities={g:consumption(Decimal(q)*Decimal(lc)/Decimal(125)) for g,q in recipe.items()}
        cost=sum(q*(float(named[g]['base_price'])*1.055+(.03 if g=='fuels' else .05)*1.75) for g,q in quantities.items())
        return quantities,cost
    generic=2*prior['generic_carrier']['profit'];saved=2*prior['hub']['covered_freight_saved']
    variants={}
    for label,lc in [('independent_factory_batches',independent),('pooled_same_route_good_100_unit_batches',pooled)]:
        qty,cost=costs(lc);advantage=saved-cost;vehicles=math.ceil(lc/10)
        variants[label]={'lc':lc,'vehicles':vehicles,'vehicle_capex':vehicles*fleet_unit,'operating_inputs':qty,'running_cost':cost,
            'freight_replaced':saved,'profit_ignoring_added_constraints':generic+advantage,'advantage_over_carrier':advantage,
            'vehicle_only_payback_turns':vehicles*fleet_unit/advantage if advantage>0 else None}
    assert independent==72 and pooled==38
    assert variants['independent_factory_batches']['operating_inputs']=={'hydraulic_components':1,'tyres':2,'fuels':3}
    assert variants['pooled_same_route_good_100_unit_batches']['operating_inputs']=={'hydraulic_components':1,'tyres':1,'fuels':2}
    diagnostic=load('reports/balance/pepper_ten_factory_capacity_diagnostic_2026-09-19.json')
    rows=diagnostic['sample_turns_40_49'];assert len(rows)==10
    report={'status':'full-output linear sensitivity, not a validated ten-building steady state',
        'assumptions':'Two copies of five factories on the same two tiles, one covering hub; unchanged per-unit base freight/port/storage costs for the linear comparison. Added congestion and storage limits shown separately. No new hub overhead priced.',
        'middleman_profit_reference':2*prior['middleman']['profit'],'generic_carrier_full_output_linear_profit':generic,'hub_variants':variants,
        'batching':'Independent batches retain each factory set as a separate shipment. Pooling combines matching goods on the same route with an illustrative 100-unit cap; only the doubled 140-unit internal iron movement needs two loads. These are alternatives pending a final canonical shipment/payload rule.',
        'actual_unmodified_two_tile_run':{'steady_state_qualification':diagnostic['failures'],'average_profit_turns_40_49':sum(x['contribution'] for x in rows)/10,
            'average_motors_produced':sum(x['summary']['produced'].get('g_008',0) for x in rows)/10,'target_motors':66,
            'turns_with_storage_capped_orders':sum(bool(x['summary'].get('input_orders_capped')) for x in rows),
            'note':'Storage budget throttles inputs; traffic also exceeds road capacity. Operating averages are diagnostic, not matched throughput. Hubs retain road congestion and storage obligations.'}}
    (ROOT/'reports/balance/pepper_double_chain_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))
if __name__=='__main__':main()
