#!/usr/bin/env python3
"""Compare direct service with genuine shared-handoff quotes for ten factories."""
import csv,json,math,subprocess
from collections import Counter,deque
from decimal import Decimal
from pathlib import Path
from run_tests import find_godot
from analyse_logistics_hub import neighbours
from analyse_pepper_consolidation import consolidate
from analyse_hub_rounding_weight import consumption
ROOT=Path(__file__).resolve().parents[1];OUT=Path('/tmp/pepper-district')
def main():
    OUT.mkdir(exist_ok=True)
    hub='tile_5_5';port='tile_5_10';area=neighbours(hub)|{hub}
    layout=[{'tile':t,'recipe':r} for t,r in [(hub,'r_009'),('tile_5_4','r_003'),('tile_6_5','r_008'),('tile_6_4','r_005'),('tile_6_4','r_007')] for _ in range(2)]
    def stream(g,q,a,b,d,op='carrier'):return {'good':g,'quantity':q,'source':a,'destination':b,'direction':d,'operator':op}
    direct=[stream(g,q,port,t,'import') for g,q,t in [('g_001',40,'tile_5_4'),('g_001',40,'tile_6_4'),('g_002',80,'tile_6_4'),('g_003',72,'tile_6_4')]]
    direct += [stream(g,q,a,b,'internal') for g,q,a,b in [('g_004',140,'tile_6_4','tile_5_4'),('g_005',50,'tile_6_4','tile_6_5'),('g_006',88,'tile_5_4',hub),('g_007',66,'tile_6_5',hub)]]
    direct += [stream(g,q,t,port,'export') for g,q,t in [('g_004',66,'tile_5_4'),('g_006',24,hub),('g_007',2,hub),('g_008',66,hub)]]
    def local(s):
        a=s['source'];b=s['destination'];queue=deque([[a]]);seen={a}
        while queue:
            path=queue.popleft()
            if path[-1]==b:break
            for t in sorted(neighbours(path[-1])&area-seen):seen.add(t);queue.append(path+[t])
        assert path[-1]==b and len(path)>1
        return dict(s,operator='hub',route={'tiles':path,'path':path,'legs':[{'from':a,'to':b,'mode':'roads'} for a,b in zip(path,path[1:])],'turns':len(path)-1,'reachable':True})
    cases={'direct':direct}
    for gateway in sorted(area):
        moves=[];external=Counter()
        for s in direct:
            if s['direction']=='internal':moves.append(local(s));continue
            if s['direction']=='import':
                external[(s['good'],'import')]+=s['quantity']
                if gateway!=s['destination']:moves.append(local(dict(s,source=gateway)))
            else:
                external[(s['good'],'export')]+=s['quantity']
                if gateway!=s['source']:moves.append(local(dict(s,destination=gateway)))
        for (g,d),q in external.items():moves.append(stream(g,q,port if d=='import' else gateway,gateway if d=='import' else port,d))
        cases[gateway]=moves
    # Operator splits conserve each good's net delivery at every tile, including handoff.
    def net(moves):
        c=Counter()
        for s in moves:c[(s['source'],s['good'])]-=s['quantity'];c[(s['destination'],s['good'])]+=s['quantity']
        return {k:v for k,v in c.items() if v}
    assert all(net(v)==net(direct) for v in cases.values())
    spec={'hub':hub,'port':port,'area':sorted(area),'layout':layout,'cases':cases}
    (OUT/'spec.json').write_text(json.dumps(spec,indent=2)+'\n');(OUT/'quotes.json').unlink(missing_ok=True)
    with (OUT/'run.log').open('w') as log:r=subprocess.run([find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'godot.log'),'res://tools/pepper_district_quote_probe.tscn'],stdout=log,stderr=subprocess.STDOUT,timeout=180)
    assert r.returncode==0 and 'SCRIPT ERROR' not in (OUT/'run.log').read_text(),(OUT/'run.log').read_text()
    engine=json.loads((OUT/'quotes.json').read_text())
    goods={r['ID']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())};named={r['internal_name']:r for r in goods.values()}
    recipes={r['recipe_id']:r for r in csv.DictReader((ROOT/'data/recipes_all.csv').open())}
    factors=json.loads((ROOT/'tests/scenarios/logistics_hub_lc_weights.json').read_text())['lc_weights'];weights={g:factors[r['transport_class']] for g,r in goods.items() if r['transport_class'] in factors}
    def price(g):return float(goods[g]['base_price'])
    def fee(g,t):return .005*price(g)+(.5 if goods[g]['transport_class']=='ultra_heavy' else .03 if goods[g]['transport_class']=='safe_liquid' else .05)*(1.5 if t in ['tile_5_4','tile_6_5'] else 1.75)
    factory=sum(sum(c[k] for k in ['labour','maintenance','power']) for c in engine['factory_costs'])
    provider=0;balances=Counter()
    for site,c in zip(layout,engine['factory_costs']):
        p=-sum(c[k] for k in ['labour','maintenance','power']);recipe=recipes[site['recipe']]
        for side in ['input','output']:
            for i in range(1,7 if side=='input' else 6):
                name=recipe.get(f'{side}_{i}','');q=int(float(recipe.get(f'qty_{i}' if side=='input' else f'output_qty_{i}',0) or 0))
                if not name or not q:continue
                g=named[name]['ID'];p+=q*(price(g)*(1 if side=='output' else -1.05)-fee(g,site['tile']))
                balances[(site['tile'],g)]+=q*(1 if side=='output' else -1)
        provider+=p
    for k,v in net(direct).items():balances[k]+=v
    assert all(v==0 for (t,g),v in balances.items() if t!=port)
    prior=json.loads((ROOT/'reports/balance/pepper_three_by_three_2026-09-19.json').read_text())['results']['five_factories']['generic_carrier']
    warehouse=prior['warehousing']*2;ports=prior['ports']*2
    receipts=sum(s['quantity']*price(s['good']) for s in direct if s['direction']=='export');purchases=sum(s['quantity']*price(s['good'])*1.05 for s in direct if s['direction']=='import')
    assert abs(receipts-prior['goods_receipts']*2)<.001 and abs(purchases-prior['goods_purchases']*2)<.001
    common=receipts-purchases-factory-warehouse-ports
    results={}
    for mode,data in engine['modes'].items():
        upkeep=engine['rail_maintenance'] if mode=='rail' else 0
        baseline=sum(q['charged'] for q in data['direct']['quotes']);options={}
        for gate,case in data.items():
            if gate=='direct':continue
            events=[]
            for s in case['streams']:
                if s['operator']=='hub':
                    for a,b in zip(s['route']['tiles'],s['route']['tiles'][1:]):events.append({'from':a,'to':b,'good':s['good'],'quantity':int(s['quantity']),'operator':'hub'})
            batches=consolidate(events,weights);lc=sum(b['lc'] for b in batches)
            qty={g:consumption(Decimal(q)*Decimal(lc)/125) for g,q in {'hydraulic_components':2,'tyres':4,'fuels':6}.items()}
            running=sum(q*(price(named[g]['ID'])*1.05+fee(named[g]['ID'],hub)) for g,q in qty.items())
            freight=sum(q['charged'] for q in case['quotes']);vehicles=math.ceil(lc/10)
            options[gate]={'lc':lc,'vehicles':vehicles,'vehicle_capex':vehicles*(price(named['heavy_vehicle']['ID'])*1.05+fee(named['heavy_vehicle']['ID'],hub)),'operating_inputs':qty,'running_cost':running,'carrier_freight':freight,'profit':common-upkeep-freight-running,'advantage_over_direct':baseline-freight-running,'overloads':case['overloads'],'batches':batches}
        valid=[g for g,v in options.items() if not v['overloads']]
        # Congestion is a charge, not a hard cap. If all gateways overload, retain
        # the best optimistic candidate and explicitly flag unpriced hub impacts.
        best=max(valid or list(options),key=lambda g:(options[g]['profit'],-options[g]['vehicle_capex'],-options[g]['lc']))
        results[mode]={'generic_profit':common-upkeep-baseline,'generic_freight':baseline,'generic_overloads':data['direct']['overloads'],'infrastructure_upkeep':upkeep,'selected_gateway':best,'unpriced_owned_hub_congestion':not bool(valid),'selected':options[best],'gateways':options}
    report={'status':'Engine quote model at recurring full throughput, not a production benchmark or implemented hub gameplay. Road handoffs are optimistic bounds because owned-hub congestion operating effects are unpriced.','spec':spec,'middleman_profit':provider,'common_costs':{'receipts':receipts,'purchases':purchases,'factory':factory,'ports':ports,'warehouse_estimate':warehouse},
        'assumptions':{'infrastructure':'Road L3 versus rail L2, with local hub road L3 in either case, to test service substitution; concentrated road handoffs still overload and retain engine carrier surcharges. No hard shipment cap is assumed. Three owned L2 rail tiles; all other infrastructure public; construction excluded.',
        'handoff':'Explicit aggregation at each of seven reachable covered tiles; generic carrier requoted only between gateway and port. Local distribution uses covered road edges only, one edge per turn, charged in hub LC. No generic invoices for owned local movements.',
        'timing':'Recurring phase-aligned dispatch; no extra handoff dwell. Actual local travel duration is retained, so end-to-end delivery can differ from direct rail. Inventory effect not simulated.',
        'storage':'Same two-chain inventory carrying cost in both models; no assumed savings from warehousing, handling fees or bulk discounts. Additional gateway inventory/land/handling overhead, empty repositioning and fleet amortization not priced.',
        'controls':'Recipes, prices, middleman tariffs, payload, rounding and operating recipe unchanged. Earlier small-building controls unchanged but not rerun under a new tariff, since no tariff introduced.'},'results':results,'engine':engine}
    (ROOT/'reports/balance/pepper_district_handoff_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    print('middleman',provider)
    for mode,r in results.items():print(mode,'generic',r['generic_profit'],'best',r['selected_gateway'],{k:v for k,v in r['selected'].items() if k!='batches'})
if __name__=='__main__':main()
