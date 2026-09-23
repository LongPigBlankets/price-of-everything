#!/usr/bin/env python3
"""Two-chain road L2 versus rail L1, with identical owned-hub costs."""
import json
import subprocess
from pathlib import Path
from run_tests import find_godot
from analyse_logistics_hub import neighbours
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('/tmp/pepper-infrastructure')
def main():
    OUT.mkdir(exist_ok=True)
    (OUT/'quotes.json').unlink(missing_ok=True)
    with (OUT/'run.log').open('w') as log:
        run=subprocess.run([find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'godot.log'),'res://tools/pepper_infrastructure_quote_probe.tscn'],stdout=log,stderr=subprocess.STDOUT,timeout=120)
    assert run.returncode==0 and 'SCRIPT ERROR' not in (OUT/'run.log').read_text()
    quotes=json.loads((OUT/'quotes.json').read_text())
    prior=json.loads((ROOT/'reports/balance/pepper_four_by_three_consolidated_2026-09-19.json').read_text())['results']['ten_factories']
    g=prior['generic_carrier'];h=prior['hub']
    pre_freight=g['profit_before_congestion']+g['inland_freight']
    area=neighbours('tile_5_5')|{'tile_5_5'}
    result={}
    for name,data in quotes.items():
        base=sum(q['base'] for q in data['quotes']);charged=sum(q['charged'] for q in data['quotes']);saved=0
        repeated=[]
        for q in data['quotes']:
            s=q['stream'];route=s['route'];path=route['tiles'];index=0
            modes={leg['mode'] for leg in route['legs']}
            assert modes==({'rail'} if name=='rail_l1' else {'roads'})
            if len(set(path))!=len(path):repeated.append({'good':s['good'],'quantity':s['quantity'],'tiles':path})
            # All legs of these routes have the same mode/cost per leg. Preserve
            # the previous model's covered-edge share of each leg's base charge.
            for leg in route['legs']:
                end=path.index(leg['to'],index+1)
                edges=list(zip(path[index:end],path[index+1:end+1]))
                saved+=q['base']/len(route['legs'])*sum(a in area and b in area for a,b in edges)/len(edges)
                index=end
        upkeep=sum(data['upkeep'].values())
        profit=pre_freight-charged-upkeep
        result[name]={'middleman_profit':prior['middleman_profit'],'carrier_profit':profit,'hub_profit':profit+saved-h['running_cost'],
            'base_freight':base,'congestion':charged-base,'infrastructure_maintenance':data['upkeep']['maintenance'],
            'infrastructure_labour':data['upkeep']['labour'],'port_fees':g['ports'],'warehouse':g['warehousing'],
            'hub_base_freight_replaced':saved,'hub_base_freight_remaining':base-saved,'hub_running_inputs':h['operating_inputs'],
            'hub_running_cost':h['running_cost'],'hub_vehicles':h['vehicles'],'hub_vehicle_capex':h['vehicle_capex'],
            'repeated_tile_routes':repeated,'engine':data}
    assert result['rail_l1']['carrier_profit']>result['roads_l2']['carrier_profit']
    assert result['rail_l1']['hub_profit']>result['roads_l2']['hub_profit']
    report={'status':'Full-output infrastructure quote model, not a new production simulation',
        'selected':'rail_l1','assumptions':{'roads':'All baseline road corridor tiles upgraded to L2; no player road maintenance.',
        'rail':'L1 rail laid on shortest land corridors from each production tile to the same port and between the production tiles. Actual router chooses routes, including existing network. Three owned tiles: tile_5_4, tile_5_5, tile_5_6; remainder public. Road L2 retained as available but all chosen legs verified rail.',
        'hub':'Identical running recipe, three vehicles and capital in both cases, as requested. Covered freight replacement follows actual new routes; retain full network congestion expense.',
        'constant':'Full recipe throughput, prices, port costs and warehouse charge retained from previous model. Faster deliveries may alter real inventory/warehouse costs; not recomputed.',
        'exclusions':'Infrastructure construction/upgrade capital, hub building/overheads, government build timing, production planner fixes and rail routing-loop fixes.'},'results':result}
    (ROOT/'reports/balance/pepper_infrastructure_two_chains_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
    for n,v in result.items():print(n,{k:round(x,4) if isinstance(x,float) else x for k,x in v.items() if k not in ('engine','repeated_tile_routes')})
if __name__=='__main__':main()
