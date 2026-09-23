#!/usr/bin/env python3
"""Three chains across one hub centre and six surrounding tiles, with L2 rail."""
import csv
import json
import math
import subprocess
from collections import Counter
from decimal import Decimal
from pathlib import Path
from run_tests import find_godot
from analyse_logistics_hub import neighbours
from analyse_pepper_consolidation import consolidate
from analyse_hub_rounding_weight import consumption
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('/tmp/pepper-seven-tiles')

def main():
    OUT.mkdir(exist_ok=True)
    hub='tile_5_5';port='tile_5_10';area=neighbours(hub)|{hub}
    layout=[{'tile':hub,'recipe':'r_009'} for _ in range(3)]
    streams=[]
    def move(g,q,a,b,d):streams.append({'good':g,'quantity':q,'source':a,'destination':b,'direction':d})
    pairs=[('tile_5_4','tile_6_4'),('tile_6_5','tile_5_6'),('tile_4_4','tile_4_5')]
    for processing,smelting in pairs:
        layout.extend([{'tile':processing,'recipe':r} for r in ['r_003','r_008']]+[{'tile':smelting,'recipe':r} for r in ['r_005','r_007']])
        for g,q,t in [('g_001',20,processing),('g_001',20,smelting),('g_002',40,smelting),('g_003',36,smelting)]:move(g,q,port,t,'import')
        for g,q in [('g_004',70),('g_005',25)]:move(g,q,smelting,processing,'internal')
        for g,q in [('g_006',44),('g_007',33)]:move(g,q,processing,hub,'internal')
        move('g_004',33,processing,port,'export')
    for g,q in [('g_006',36),('g_007',3),('g_008',99)]:move(g,q,hub,port,'export')
    assert {s['tile'] for s in layout}==area and len(layout)==15
    spec={'hub':hub,'port':port,'layout':layout,'pairs':pairs,'streams':streams,'owned_rail_tiles':['tile_5_4','tile_5_5','tile_5_6']}
    (OUT/'spec.json').write_text(json.dumps(spec,indent=2)+'\n')
    (OUT/'quotes.json').unlink(missing_ok=True)
    with (OUT/'run.log').open('w') as log:
        run=subprocess.run([find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'godot.log'),'res://tools/pepper_seven_tile_quote_probe.tscn'],stdout=log,stderr=subprocess.STDOUT,timeout=120)
    assert run.returncode==0 and 'SCRIPT ERROR' not in (OUT/'run.log').read_text(),(OUT/'run.log').read_text()
    engine=json.loads((OUT/'quotes.json').read_text())
    goods={r['ID']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())};named={r['internal_name']:r for r in goods.values()}
    recipes={r['recipe_id']:r for r in csv.DictReader((ROOT/'data/recipes_all.csv').open())}
    terrain={r['id']:r for r in csv.DictReader((ROOT/'data/tile_properties.csv').open())}
    weight_classes=json.loads((ROOT/'tests/scenarios/logistics_hub_lc_weights.json').read_text())['lc_weights']
    weights={g:weight_classes[r['transport_class']] for g,r in goods.items() if r['transport_class'] in weight_classes}
    def density(tile):
        if terrain[tile]['type']=='mountain':return 2.5
        if terrain[tile]['type']=='urban':return 1.5
        return 1.75 if any(terrain.get(t,{}).get('type')=='urban' for t in neighbours(tile)) else 2.0
    def price(g):return float(goods[g]['base_price'])
    def unit_fee(g,tile):return .005*price(g)+{'solid_heavy':.05,'ultra_heavy':.5,'safe_liquid':.03}[goods[g]['transport_class']]*density(tile)
    factory=sum(sum(c[k] for k in ['labour','maintenance','power']) for c in engine['factory_costs'])
    provider=[]
    # Check complete material conservation at each factory tile, including surplus.
    balances={t:Counter() for t in area}
    for site,c in zip(layout,engine['factory_costs']):
        recipe=recipes[site['recipe']];buy=sell=fee=0
        for side in ['input','output']:
            for i in range(1,7 if side=='input' else 6):
                good=recipe.get(f'{side}_{i}','');q=int(float(recipe.get(f'qty_{i}' if side=='input' else f'output_qty_{i}',0) or 0))
                if not good or not q:continue
                g=named[good]['ID'];fee+=q*unit_fee(g,site['tile'])
                if side=='input':buy+=q*price(g)*1.05;balances[site['tile']][g]-=q
                else:sell+=q*price(g);balances[site['tile']][g]+=q
        cost=sum(c[k] for k in ['labour','maintenance','power'])
        provider.append(dict(site,density=density(site['tile']),fee=fee,profit=sell-buy-fee-cost))
    for s in streams:
        if s['source'] in balances:balances[s['source']][s['good']]-=s['quantity']
        if s['destination'] in balances:balances[s['destination']][s['good']]+=s['quantity']
    assert all(all(v==0 for v in b.values()) for b in balances.values()),balances
    events=[];saved=0;repeats=[]
    for q in engine['quotes']:
        s=q['stream'];route=s['route'];path=route['tiles'];index=0
        assert all(l['mode']=='rail' for l in route['legs'])
        if len(path)!=len(set(path)):repeats.append(s)
        for leg in route['legs']:
            end=path.index(leg['to'],index+1);edges=list(zip(path[index:end],path[index+1:end+1]))
            for a,b in edges:events.append({'good':s['good'],'quantity':int(s['quantity']),'from':a,'to':b,'operator':'hub' if a in area and b in area else 'carrier','available_turn':0})
            saved+=q['base']/len(route['legs'])*sum(a in area and b in area for a,b in edges)/len(edges)
            index=end
    batches=consolidate(events,weights);lc=sum(b['lc'] for b in batches)
    operating={g:consumption(Decimal(q)*Decimal(lc)/Decimal(125)) for g,q in {'hydraulic_components':2,'tyres':4,'fuels':6}.items()}
    running=sum(q*(1.05*price(named[g]['ID'])+unit_fee(named[g]['ID'],hub)) for g,q in operating.items())
    vehicles=math.ceil(lc/10);vehicle_unit=1.05*price(named['heavy_vehicle']['ID'])+unit_fee(named['heavy_vehicle']['ID'],hub)
    prior=json.loads((ROOT/'reports/balance/pepper_three_by_three_2026-09-19.json').read_text())['results']['five_factories']['generic_carrier']
    receipts=sum(s['quantity']*price(s['good']) for s in streams if s['direction']=='export')
    purchases=sum(s['quantity']*price(s['good'])*1.05 for s in streams if s['direction']=='import')
    assert abs(receipts-prior['goods_receipts']*3)<.001 and abs(purchases-prior['goods_purchases']*3)<.001
    freight=sum(q['base'] for q in engine['quotes']);charged=sum(q['charged'] for q in engine['quotes']);upkeep=sum(engine['rail_upkeep'].values())
    warehouse=prior['warehousing']*3;ports=prior['ports']*3
    generic=receipts-purchases-factory-charged-upkeep-warehouse-ports
    result={'spec':spec,'status':'Full-output periodic model with actual engine rail routes, congestion quotes and factory/rail costs; not a validated production simulation.',
        'assumptions':{'storage':'Controlled aggregate stock carrying cost: three times prior five-factory baseline. Not measured seven-tile occupancy; add/subtract any actual storage-cost difference equally to carrier/hub.',
        'transfers':'Whole ingot batches to steel/wiring tile, whole steel/wiring outputs to motor tile, surplus sold at receiving tile. No mines. Same policy as previous comparisons.',
        'middleman':'Independent building trades; location coefficients recomputed for each site. The two local urban tiles use existing Pepper Valley small-city coefficient 1.5.',
        'hub':'Existing 100 weighted units/load and 10 LC/vehicle; diesel recipe per125 LC rounded half-up/min-one. Workload recomputed for three chains. Phase-aligned recurring arrivals, local consolidation, no extra travel. Entire network congestion charge retained.',
        'rail':'L2 shortest land corridors for all required streams, actual router chooses among installed and existing network. Three player-owned rail tiles, rest government. Construction and hub overhead excluded.'},
        'middleman_profit':sum(p['profit'] for p in provider),'middleman_fees':sum(p['fee'] for p in provider),'provider_buildings':provider,
        'generic_profit':generic,'hub_profit':generic+saved-running,
        'costs':{'receipts':receipts,'purchases':purchases,'factory':factory,'rail_base_freight':freight,'rail_congestion':charged-freight,'rail_upkeep':upkeep,'warehouse_assumption':warehouse,'ports':ports,'hub_remaining_base_freight':freight-saved,'hub_running':running},
        'hub':{'lc':lc,'vehicles':vehicles,'vehicle_capex':vehicles*vehicle_unit,'operating_inputs':operating,'freight_replaced':saved,'advantage_over_carrier':saved-running,'batches':batches,
        'payload_sensitivity_lc':{str(c):sum(b['lc'] for b in consolidate(events,weights,c)) for c in (50,100,200)}},
        'repeated_tile_routes':repeats,'engine':engine}
    (ROOT/'reports/balance/pepper_three_chains_seven_tiles_2026-09-19.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ['engine','spec','provider_buildings','repeated_tile_routes','hub']},indent=2))
    print('hub',{k:v for k,v in result['hub'].items() if k!='batches'})
    print('peak flow',max(engine['flow'].values()),'repeated routes',len(repeats))
if __name__=='__main__':main()
