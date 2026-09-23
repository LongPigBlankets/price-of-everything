#!/usr/bin/env python3
"""Partial-road hub coverage and ten shipment-hop slots per installed vehicle."""
import csv
import itertools
import json
import math
from pathlib import Path
from analyse_logistics_hub import neighbours
ROOT=Path(__file__).resolve().parents[1]

def main():
    previous=json.loads((ROOT/'reports/balance/logistics_hub_trial_2026-09-19.json').read_text())
    terrain={r['id']:r['type'] for r in csv.DictReader((ROOT/'data/tile_properties.csv').open())}
    roads=json.loads((ROOT/'tests/snapshots/pepper_valley_motors_v5.json').read_text())
    chain=json.loads((ROOT/'tests/snapshots/pepper_valley_motors_v7_furnace.json').read_text())
    prices={r['internal_name']:float(r['base_price']) for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    byid={r['ID']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    hubsets={'factory_tile':['tile_5_4'],'adjacent_hub':['tile_5_5'],
             'full_corridor':previous['route']['corridor_coverage_alternative']['hubs']}
    def density(tile):
        if terrain[tile]=='mountain':return 2.5
        if terrain[tile]=='urban':return 1.5 # selected urban centre is small Stoneshore/Pepper
        return 1.75 if any(terrain.get(n)=='urban' for n in neighbours(tile)) else 2.0
    def run_cost(hub):
        d=density(hub)
        # 2 hydraulics + 4 tyres are solid-heavy; 6 fuel safe-liquid.
        base=previous['running_costs']['diesel']['market_value']
        return 1.05*base+.005*base+d*(6*.05+6*.03)
    def truck_cost(hub):return 1.05*prices['heavy_vehicle']+.005*prices['heavy_vehicle']+.5*density(hub)
    result={}
    for name,snap in [('motor',roads),('chain',chain)]:
        m=snap['means'];quotes=snap['route_quotes_at_start'];streams=[]
        for key,q in quotes.items():
            if not key.startswith('buy:'):continue
            gid=key.split(':',1)[1];streams.append((gid,int(q['qty']),q['route']))
        for gid,qty in snap['effective_outputs'].items():streams.append((gid,int(qty),quotes['sell']['route']))
        rates={'solid_heavy':(.03,.008),'ultra_heavy':(.06,.01)}
        total=0.0
        for gid,qty,route in streams:
            flat,av=rates[byid[gid]['transport_class']]
            total+=qty*(flat+av*float(byid[gid]['base_price']))*len(route['legs'])
        assert abs(total-m['freight_weight_distance']-m['freight_ad_valorem'])<1e-7
        cases={}
        for label,hubs in hubsets.items():
            areas={h:neighbours(h)|{h} for h in hubs}
            # Assign a covered edge once; preserve assignment for all goods/directions.
            edge_work={}
            for _,_,route in streams:
                for a,b in zip(route['tiles'],route['tiles'][1:]):
                    key=tuple(sorted((a,b)))
                    edge_work[key]=edge_work.get(key,0)+1
            eligible={edge:[h for h in hubs if edge[0] in areas[h] and edge[1] in areas[h]] for edge in edge_work}
            eligible={edge:owners for edge,owners in eligible.items() if owners}
            edges=list(eligible)
            best=None; assignments={}
            for owners in itertools.product(*(eligible[e] for e in edges)):
                usage={h:0 for h in hubs}
                for edge,h in zip(edges,owners):usage[h]+=edge_work[edge]
                fleet={h:math.ceil(work/10) for h,work in usage.items()}
                score=(sum(fleet.values()),sum(fleet[h]*truck_cost(h) for h in hubs),sum(run_cost(h)*usage[h] for h in hubs))
                if best is None or score<best:
                    best=score;assignments=dict(zip(edges,owners))
            load={h:0 for h in hubs};saved=0.0;whole_leg_saved=0.0;traces=[]
            for gid,qty,route in streams:
                flat,av=rates[byid[gid]['transport_class']]
                leg_cost=qty*(flat+av*float(byid[gid]['base_price']))
                path=route['tiles'];index=0
                for leg in route['legs']:
                    end=path.index(leg['to'],index+1)
                    edges=list(zip(path[index:end],path[index+1:end+1]));owned=[]
                    for a,b in edges:
                        operator=assignments.get(tuple(sorted((a,b))),'carrier')
                        traces.append({'good':gid,'qty':qty,'from':a,'to':b,'operator':operator})
                        if operator!='carrier':load[operator]+=1
                        owned.append(operator!='carrier')
                    saved+=leg_cost*sum(owned)/len(edges)
                    if all(owned):whole_leg_saved+=leg_cost
                    index=end
            active=[h for h in hubs if load[h]]
            vehicles={h:math.ceil(load[h]/10) for h in active}
            assert all(vehicles[h]*10>=load[h] for h in active)
            running=sum(run_cost(h) for h in active)
            capex=sum(vehicles[h]*truck_cost(h) for h in active)
            # Speculative design sensitivity: recipes consumed proportionally to LC
            # used; 100/125/160 are explicit trial outputs, not approved rules.
            variable={str(output):sum(run_cost(h)*load[h]/output for h in active) for output in (100,125,160)}
            cases[label]={'hubs':active,'shipment_hops_by_hub':load,'vehicles_by_hub':vehicles,
                'vehicles':sum(vehicles.values()),'equipment_capex':capex,
                'covered_freight_saved_prorated':saved,'uncovered_freight_paid':max(0.0,total-saved),
                'covered_freight_saved_whole_legs_only':whole_leg_saved,
                'diesel_running_cost_per_hub_recipe':running,
                'profit_per_turn':m['direct_operating_contribution']+saved-running,
                'profit_if_recipe_every_five_turns':m['direct_operating_contribution']+saved-running/5,
                'profit_without_hub_running_cost':m['direct_operating_contribution']+saved,
                'variable_recipe_cost_by_lc_output':variable,
                'variable_recipe_profit_by_lc_output':{k:m['direct_operating_contribution']+saved-v for k,v in variable.items()},
                'handoff_trace':traces}
            assert abs(saved+(total-saved)-total)<1e-8
            if label=='full_corridor':assert abs(saved-total)<1e-8
        result[name]={'carrier_road_profit':m['direct_operating_contribution'],
            'middleman_profit':previous['cases'][name]['provider_profit'],'inland_freight':total,'cases':cases}
    report={'status':'arithmetic experiment, not implemented handoff or hub gameplay',
        'contract':{'coverage':'own tile plus adjacent tiles; edge is eligible only when both endpoints are covered; crossing edge goes to another covering hub or regular carrier',
            'equipment':'ceil(covered shipment-hop workload / 10) installed heavy vehicles per hub; no sharing vehicles between hubs',
            'shipment':'one canonical good/origin/destination batch per adjacent-tile hop; no per-unit charging; split calls must not inflate or reduce workloads',
            'payload':'All benchmark batches are below 100 units. A proposed 100-unit payload cap would leave these fleet counts unchanged; large-batch handling remains a design requirement.',
            'handoff':'player retains goods ownership; no new market trade, extra port fee or artificial wait; provider assignment cannot reset progress',
            'carrier':'existing direct transport tariff, not building-only middleman service',
            'running':'original full diesel recipe per active hub per turn; five-turn frequency and 100/125/160 LC recipe output are explicit separate sensitivities',
            'partial_leg_billing':'Prorate existing leg charge by physical edges. Whole-leg-only savings also reported because the current game bills per leg, not per edge.',
            'limitations':'No live routing, occupancy/returns, loading, capacity failure, hub building capex or overhead simulated. Hub supply bought from middleman. Full corridor placement is geometric, not buildability-validated.'},
        'results':result}
    out=ROOT/'reports/balance/logistics_hub_handoffs_2026-09-19.json';out.write_text(json.dumps(report,indent=2)+'\n')
    for name,row in result.items():
        print(name)
        for label,c in row['cases'].items():print(label,{k:v for k,v in c.items() if k!='handoff_trace'})

if __name__=='__main__':main()
