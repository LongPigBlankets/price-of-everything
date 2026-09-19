#!/usr/bin/env python3
"""Hub operating-cost and capacity bounds on retained Pepper Valley benchmarks."""
import csv
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def neighbours(tile):
    _, x, y = tile.split('_'); x, y = int(x)-1, int(y)-1
    offsets = [(0,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0)] if x%2 else [(0,-1),(1,-1),(1,0),(0,1),(-1,0),(-1,-1)]
    return {f'tile_{x+dx+1}_{y+dy+1}' for dx,dy in offsets}

def minimum_corridor_hubs(paths, terrain):
    # Alternate interpretation: radius-one catchments must cover every road edge.
    edges = sorted({tuple(sorted(edge)) for path in paths for edge in zip(path,path[1:])})
    nodes = {t for edge in edges for t in edge}
    candidates = sorted({t for n in nodes for t in neighbours(n)|{n} if terrain.get(t) in ('urban','rural','hill','mountain')})
    covers = {}
    for t in candidates:
        area = neighbours(t)|{t}
        mask = sum(1<<i for i,(a,b) in enumerate(edges) if a in area and b in area)
        if mask: covers[t] = mask
    full = (1<<len(edges))-1
    states = {0:()}
    for tile, cover in covers.items():
        for mask, selection in list(states.items()):
            new = mask|cover
            if new not in states or len(selection)+1 < len(states[new]):
                states[new] = selection+(tile,)
    result = states[full]
    assert all(any(a in neighbours(h)|{h} and b in neighbours(h)|{h} for h in result) for a,b in edges)
    return {'hubs':list(result),'count':len(result),'road_edges':edges}

def main():
    goods = {r['internal_name']:r for r in csv.DictReader((ROOT/'data/Goods - goodsMVP.csv').open())}
    terrain = {r['id']:r['type'] for r in csv.DictReader((ROOT/'data/tile_properties.csv').open())}
    def load(name):return json.loads((ROOT/'tests/snapshots'/name).read_text())
    motor=load('pepper_valley_motors_v5.json')
    chain=load('pepper_valley_motors_v7_furnace.json')
    rail=load('pepper_valley_motors_rail_three_owned_v7_furnace.json')
    rates={'solid_heavy':.05,'ultra_heavy':.5,'safe_liquid':.03}
    density=1.5
    def price(g):return float(goods[g]['base_price'])
    def cost(recipe):
        base=sum(price(g)*q for g,q in recipe.items())
        supply_fee=sum(q*(.005*price(g)+rates[goods[g]['transport_class']]*density) for g,q in recipe.items())
        return {'market_value':base,'purchase_cost':base*1.05,'middleman_supply_fee':supply_fee,'delivered_cost':base*1.05+supply_fee}
    # Check the purchase-price assumption against a retained real route quote.
    quote=motor['route_quotes_at_start']['buy:g_006']
    assert abs(quote['goods_cost']-32*price('steel')*1.05)<1e-8
    recipes={'diesel':{'hydraulic_components':2,'tyres':4,'fuels':6},
             'lithium':{'hydraulic_components':2,'tyres':4,'lithium_battery':1},
             'sodium':{'hydraulic_components':2,'tyres':4,'sodium_battery':1}}
    costs={k:cost(v) for k,v in recipes.items()}
    vehicle=cost({'heavy_vehicle':1})
    paths=[motor['route_quotes_at_start']['buy:g_006']['route']['tiles'],motor['route_quotes_at_start']['sell']['route']['tiles']]
    corridor=minimum_corridor_hubs(paths,terrain)
    assert all(b in neighbours(a) for path in paths for a,b in zip(path,path[1:]))
    physical_moves=sum(len(path)-1 for path in paths)
    game_legs=sum(len(motor['route_quotes_at_start'][k]['route']['legs']) for k in ('buy:g_006','sell'))
    def provider(manifest):return sum(q*(.005*price(g)+rates[goods[g]['transport_class']]*density) for g,q in manifest.items())
    motor_manifest={'steel':32,'copper_wiring':32,'motor':33}
    furnace_manifest={'iron_ingots':37,'coal':20,'steel':44}
    mf=provider(motor_manifest);ff=provider(furnace_manifest)
    mm=motor['means'];cm=chain['means']
    motor_profit=mm['goods_receipts']-mm['goods_purchases']-mm['factory_costs']-mf
    chain_profit=cm['middleman_goods_receipts_reference']-cm['middleman_goods_purchases_reference']-cm['factory_costs']-mf-ff
    cases={}
    for label,record,provider_profit,inbound,outbound in [('motor',motor,motor_profit,64,33),('chain',chain,chain_profit,89,45)]:
        m=record['means']; freight=m['freight_weight_distance']+m['freight_ad_valorem']
        before_hub=m['direct_operating_contribution']+freight
        cases[label]={'provider_profit':provider_profit,'carrier_road_profit':m['direct_operating_contribution'],
            'inland_freight_replaced':freight,'port_fees_retained':m['port_import_ad_valorem']+m['port_export_ad_valorem'],
            'storage_retained':m['warehousing'],'single_hub_optimistic_profit':{k:before_hub-v['delivered_cost'] for k,v in costs.items()},
            'five_turn_recipe_sensitivity_profit':{k:before_hub-v['delivered_cost']/5 for k,v in costs.items()},
            'max_hub_running_cost_to_beat_provider':before_hub-provider_profit,
            'scaling_sensitivity':[]}
        for n in range(1,9):
            # No quantity ceiling in the literal pooled-LC model; show a 100-unit
            # per-direction payload alternative explicitly, without changing fees.
            vehicles100=(len(paths[0])-1)*math.ceil(n*inbound/100)+(len(paths[1])-1)*math.ceil(n*outbound/100)
            row={'copies':n,'external_units_per_turn':n*(inbound+outbound),
                 'exceeds_existing_300_unit_shared_road_capacity':n*(inbound+outbound)>300,
                 'literal_pooled_vehicles':physical_moves,'vehicles_at_100_unit_payload':vehicles100,
                 'vehicle_capex_at_100_unit_payload':vehicles100*vehicle['delivered_cost'],
                 'provider_profit':n*provider_profit,'hub_profit_ignoring_added_congestion':{k:n*before_hub-v['delivered_cost'] for k,v in costs.items()},
                 'warning':'Linear cost bound only: market changes, hub overhead, payload-dependent operating consumption, extra stock and congestion are not simulated.'}
            cases[label]['scaling_sensitivity'].append(row)
        cases[label]['copies_to_beat_carrier_roads_ignoring_congestion']={k:math.floor(v['delivered_cost']/freight)+1 for k,v in costs.items()}
        delta=before_hub-provider_profit
        cases[label]['copies_to_beat_provider_ignoring_congestion']={k:math.floor(v['delivered_cost']/delta)+1 if delta>0 else None for k,v in costs.items()}
        assert all(before_hub-v['purchase_cost']<m['direct_operating_contribution'] for v in costs.values())
    report={'status':'optimistic arithmetic bounds; no implemented hub or new gameplay simulation',
        'middleman':{'ad_valorem':.005,'solid_heavy':.05,'ultra_heavy':.5,'density':density,'motor_fee':mf,'furnace_fee':ff},
        'assumptions':{'primary_coverage':'Hub serves factories on its own and adjacent tiles; their connected external routes may extend to the port.',
            'operating_recipe':'one recipe per active hub per turn, not per installed vehicle; batteries consumed every turn exactly as requested',
            'capacity':'one vehicle per directed adjacent-tile movement per turn for a pooled load; 100-unit payload is a separate sensitivity',
            'pricing':'1.05 purchase markup checked against game quote; middleman supplies operating goods so no recursive hub LC demand',
            'fuel_middleman_weight':'.03 provisional safe-liquid rate, not an approved global tariff',
            'savings':'optimistically replace 100% of covered inland freight, including freight ad valorem; retain ports, storage, infrastructure upkeep and congestion',
            'omitted':'hub construction/land, wages, power, own maintenance, loading/returns, finite LC calibration, changed inventory/timing and capital financing',
            'timing':'Recorded roads take four game turns with range two. Physical hop capacity and game-leg capacity are alternatives; no new vehicle movement timing is simulated.'},
        'recipes':recipes,'running_costs':costs,'vehicle':vehicle,
        'route':{'paths':paths,'physical_directed_movements_per_turn':physical_moves,'existing_game_legs_per_turn':game_legs,
            'physical_movement_vehicle_capex':physical_moves*vehicle['delivered_cost'],
            'game_leg_vehicle_capex':game_legs*vehicle['delivered_cost'],
            'corridor_coverage_alternative':corridor},
        'cases':cases,'existing_chain_rail_profit':rail['means']['direct_operating_contribution'],
        'rail_scope':'Road heavy vehicles are not rolling stock. Rail hub capacity requires a separate equipment/recipe specification.'}
    (ROOT/'reports/balance/logistics_hub_trial_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ('running_costs','vehicle','route','cases')},indent=2))

if __name__=='__main__':main()
