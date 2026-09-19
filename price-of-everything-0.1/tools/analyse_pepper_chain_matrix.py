#!/usr/bin/env python3
"""Three chain sizes by independent provider, actual carrier and local hub model."""
import csv
import json
import math
from pathlib import Path
from analyse_logistics_hub import neighbours
from analyse_hub_rounding_weight import consumption
from decimal import Decimal
ROOT=Path(__file__).resolve().parents[1]

def main():
    def load(p):return json.loads((ROOT/p).read_text())
    motor=load('tests/snapshots/pepper_valley_motors_v5.json')
    chain=load('tests/snapshots/pepper_valley_motors_v7_furnace.json')
    five=load('tests/snapshots/pepper_valley_five_factories_v1.json')
    probe=load('reports/balance/pepper_chain_quote_inputs_2026-09-19.json')
    recipes={r['recipe_id']:r for r in csv.DictReader((ROOT/'data/recipes_all.csv').open())}
    goods={r['internal_name']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    byid={r['ID']:r for r in goods.values()}
    weights=load('tests/scenarios/logistics_hub_lc_weights.json')['lc_weights']
    tariff={'solid_heavy':.05,'ultra_heavy':.5,'safe_liquid':.03}
    freight={'solid_heavy':(.03,.008),'ultra_heavy':(.06,.01)}
    hub='tile_5_5';area=neighbours(hub)|{hub}
    assert {'tile_5_4','tile_6_4'}<=area
    assert not five['failures'] and len(five['sample'])==10
    def avg(fn):return sum(fn(row) for row in five['sample'])/10
    fm={'goods_receipts':avg(lambda r:r['summary']['goods_sales_revenue']),
        'goods_purchases':avg(lambda r:r['summary']['goods_purchased_cost']),
        'factory_costs':avg(lambda r:r['factory_costs']),
        'warehousing':avg(lambda r:r['summary']['warehousing_paid']),
        'direct_operating_contribution':avg(lambda r:r['contribution']),
        'transport':avg(lambda r:r['summary']['transport_paid']),
        'inland':avg(lambda r:r['summary']['transport_breakdown'].get('roads',0)),
        'ports':avg(lambda r:sum(v for k,v in r['summary']['transport_breakdown'].items() if k.startswith('port')))}
    def provider_recipe(rid,tile):
        recipe=recipes[rid];din=1.5 if tile=='tile_5_4' else 1.75
        buy=sell=fee=0.0
        for side in ('input','output'):
            for i in range(1,7 if side=='input' else 6):
                g=recipe.get(f'{side}_{i}','');q=float(recipe.get(f'qty_{i}' if side=='input' else f'output_qty_{i}',0) or 0)
                if not g or not q:continue
                p=float(goods[g]['base_price'])
                if side=='input':buy+=p*q*1.05
                else:sell+=p*q
                fee+=q*(.005*p+tariff[goods[g]['transport_class']]*din)
        costs=sum(probe['costs'][rid].values())
        return {'recipe':rid,'tile':tile,'purchases':buy,'receipts':sell,'fee':fee,'factory_costs':costs,'profit':sell-buy-costs-fee}
    def running(lc):
        recipe={'hydraulic_components':2,'tyres':4,'fuels':6};qty={g:consumption(Decimal(q)*Decimal(lc)/Decimal(125)) for g,q in recipe.items()}
        cost=sum(q*(float(goods[g]['base_price'])*1.055+tariff[goods[g]['transport_class']]*1.75) for g,q in qty.items())
        return qty,cost
    definitions=[('motors',[('r_009','tile_5_4')],motor),('motors_steel',[('r_009','tile_5_4'),('r_003','tile_5_4')],chain),
        ('five_factories',[('r_009','tile_5_4'),('r_003','tile_5_4'),('r_008','tile_5_4'),('r_007','tile_6_4'),('r_005','tile_6_4')],five)]
    results={}
    for name,layout,snap in definitions:
        streams=[]
        if name!='five_factories':
            m=snap['means'];inland=m['freight_weight_distance']+m['freight_ad_valorem'];ports=m['port_import_ad_valorem']+m['port_export_ad_valorem']
            for key,q in snap['route_quotes_at_start'].items():
                if key.startswith('buy:'):streams.append((key.split(':')[1],int(q['qty']),q['route'],'import'))
            for gid,q in snap['effective_outputs'].items():streams.append((gid,int(q),snap['route_quotes_at_start']['sell']['route'],'export'))
        else:
            m=fm;inland=fm['inland'];ports=fm['ports']
            for tile,gid,q in [('tile_5_4','g_001',20),('tile_6_4','g_001',20),('tile_6_4','g_002',40),('tile_6_4','g_003',36)]:streams.append((gid,q,snap['routes'][tile][gid]['route'],'import'))
            for gid,q in snap['expected_sales'].items():streams.append((gid,q,snap['routes']['sell']['route'],'export'))
            for gid,q in [('g_004',70),('g_005',25)]:streams.append((gid,q,snap['routes']['internal'],'internal'))
        lc=0;saved=0.;reconstructed=0.;trace=[]
        for gid,q,route,direction in streams:
            flat,av=freight[byid[gid]['transport_class']];legcost=q*(flat+av*float(byid[gid]['base_price']))
            path=route['tiles'];index=0
            for leg in route['legs']:
                end=path.index(leg['to'],index+1);edges=list(zip(path[index:end],path[index+1:end+1]));covered=0
                reconstructed+=legcost
                for a,b in edges:
                    owned=a in area and b in area
                    if owned:lc+=weights[byid[gid]['transport_class']];covered+=1
                    trace.append({'good':gid,'quantity':q,'direction':direction,'from':a,'to':b,'operator':'hub' if owned else 'carrier'})
                saved+=legcost*covered/len(edges);index=end
        assert abs(reconstructed-inland)<.001,(name,reconstructed,inland)
        costs=[provider_recipe(rid,tile) for rid,tile in layout]
        assert abs(sum(c['factory_costs'] for c in costs)-m['factory_costs'])<.001
        qty,run=running(lc);vehicles=math.ceil(lc/10)
        vehicle_price=float(goods['heavy_vehicle']['base_price'])*1.055+.5*1.75
        results[name]={'layout':layout,'middleman':{'buildings':costs,'profit':sum(c['profit'] for c in costs),'fees':sum(c['fee'] for c in costs)},
            'generic_carrier':{'profit':m['direct_operating_contribution'],'goods_receipts':m['goods_receipts'],'goods_purchases':m['goods_purchases'],'factory_costs':m['factory_costs'],'inland_freight':inland,'ports':ports,'warehousing':m['warehousing']},
            'hub':{'profit':m['direct_operating_contribution']+saved-run,'covered_freight_saved':saved,'carrier_freight_remaining':inland-saved,'weighted_lc':lc,'vehicles':vehicles,'vehicle_capex':vehicles*vehicle_price,'operating_inputs':qty,'operating_inputs_cost':run},'trace':trace,'streams':[{'good':g,'quantity':q,'route':route,'direction':d} for g,q,route,d in streams]}
    report={'status':'generic-carrier columns use real recorded steady turns; middleman and owned-hub columns are arithmetic models',
        'assumptions':{'turns':'40-49','production':'one L1 building per listed recipe at full output, no mines, no JIT/research upgrades',
            'surplus':'all intermediate output goes to consuming tile stockpile; tile sells surplus after reserving inputs; motor output goes to port',
            'layout':'motors/steel/wiring tile_5_4; iron/copper ingots tile_6_4; hub tile_5_5 covers both; whole ingot batches go to consuming tile, which exports excess',
            'generic_supplier':'interpreted as existing public-road carrier plus port, not rail',
            'middleman':'independent building buys/sales, .5% price + .05 heavy/.50 ultra * location, storage included; coefficients 1.5 at city and 1.75 at adjacent rural',
            'hub':'local coverage and handoffs, 10 LC per vehicle, user-selected weights, 125 LC per diesel recipe, half-up/min-one per active hub input, zero idle',
            'limits':'hub building/wages/power/maintenance and financing/capital recovery omitted; vehicle capex shown separately; external prices controlled; no market-demand forecast'},'results':results}
    (ROOT/'reports/balance/pepper_three_by_three_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    for name,r in results.items():print(name,'middleman',r['middleman']['profit'],'carrier',r['generic_carrier']['profit'],'hub',r['hub'])

if __name__=='__main__':main()
