#!/usr/bin/env python3
"""Per-hub rounding contract and user-selected cargo-weight LC model."""
import csv
import json
import math
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]

def consumption(amount):
    value=Decimal(str(amount))
    if value<=0:return 0
    return max(1,int(value.quantize(Decimal('1'),rounding=ROUND_HALF_UP)))

def main():
    contract=json.loads((ROOT/'tests/scenarios/logistics_hub_lc_weights.json').read_text())
    weights=contract['lc_weights']
    source=json.loads((ROOT/'reports/balance/logistics_hub_handoffs_2026-09-19.json').read_text())
    goods={r['internal_name']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    byid={r['ID']:r for r in goods.values()}
    recipes={'diesel':{'hydraulic_components':2,'tyres':4,'fuels':6},'lithium':{'hydraulic_components':2,'tyres':4,'lithium_battery':1},'sodium':{'hydraulic_components':2,'tyres':4,'sodium_battery':1}}
    def bill(recipe,lc):
        quantities={g:consumption(Decimal(q)*Decimal(str(lc))/Decimal(125)) for g,q in recipe.items()}
        total=0.0
        for g,q in quantities.items():
            p=float(goods[g]['base_price']);weight=.03 if g=='fuels' else .05
            total+=q*(p*1.05+.005*p+weight*1.75)
        return {'quantities':quantities,'delivered_cost':total}
    rows={}
    for case in ('motor','chain'):
        row=source['results'][case];hub=row['cases']['adjacent_hub']
        lc=sum(hub['shipment_hops_by_hub'].values())
        weighted=sum(weights[byid[t['good']]['transport_class']] for t in hub['handoff_trace'] if t['operator']!='carrier')
        rows[case]={}
        for label,work in [('unweighted',lc),('user_weighted_lc',weighted)]:
            costs={name:bill(recipe,work) for name,recipe in recipes.items()}
            rows[case][label]={'lc':work,'vehicles':math.ceil(work/10),'running':costs,
                'diesel_profit':row['carrier_road_profit']+hub['covered_freight_saved_prorated']-costs['diesel']['delivered_cost'],
                'diesel_saving_against_carrier':hub['covered_freight_saved_prorated']-costs['diesel']['delivered_cost']}
    assert [consumption(x) for x in (0,.01,.99,1,1.49,1.5,2.49,2.5)]==[0,1,1,1,1,2,2,3]
    assert bill(recipes['diesel'],0)['delivered_cost']==0
    assert bill(recipes['diesel'],10)['quantities']=={'hydraulic_components':1,'tyres':1,'fuels':1}
    assert bill(recipes['diesel'],125)['quantities']==recipes['diesel']
    assert rows['motor']['user_weighted_lc']['lc']==18
    assert rows['chain']['user_weighted_lc']['lc']==26
    assert weights == {'solid_light':1,'solid_heavy':2,'ultra_heavy':5,'safe_liquid':2,'liquid':2,'hazard_liquid':4,'gas':3}
    report={'status':'arithmetic model; user-selected rounding and cargo weights; no live hub implementation', 'contract':contract,
        'rounding':'Sum actual weighted LC across each hub per turn; for each recipe input round amount*LC/125 half-up, minimum one if positive. Idle hub consumes zero. No fractional carry.',
        'weight':'User-selected class multipliers applied to canonical shipment-hop LC once; consumption derives from that same LC, no second multiplier',
        'limits':'Batch-size cap, payload, cargo mixing, standard/unclassified goods and hub overhead not specified. One vehicle supports 10 weighted LC. Raw-game tariffs unchanged.',
        'density':1.75,'lc_per_recipe':125,'results':rows,
        'diesel_load_sweep':{str(lc):bill(recipes['diesel'],lc) for lc in (0,1,5,10,20,40,62.5,125)}}
    (ROOT/'reports/balance/hub_rounding_weight_v2_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(rows,indent=2))

if __name__=='__main__':main()
