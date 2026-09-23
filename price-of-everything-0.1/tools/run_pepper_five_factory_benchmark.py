#!/usr/bin/env python3
"""Execute real five-factory turns and verify or record their steady snapshot."""
import argparse
import json
from pathlib import Path
import subprocess
from run_tests import PROJECT_DIR, find_godot
ROOT=Path(PROJECT_DIR)
OUT=Path('/tmp/pepper-five-factories')
BASELINE=ROOT/'tests/snapshots/pepper_valley_five_factories_v1.json'

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--double",action="store_true")
    mode=p.add_mutually_exclusive_group()
    mode.add_argument('--check-baseline',action='store_true')
    mode.add_argument('--write-baseline',action='store_true')
    args=p.parse_args()
    global OUT, BASELINE
    if args.double:
        OUT=Path(str(OUT)+"-double")
        BASELINE=ROOT/"tests/snapshots/pepper_valley_ten_factories_v1.json"
    godot=find_godot()
    if not godot:p.error('Godot not found')
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'result.json').unlink(missing_ok=True)
    with (OUT/'run.log').open('w') as log:
        run=subprocess.run([godot,'--headless','--path',str(ROOT),'--log-file',str(OUT/'godot.log'),'res://tools/pepper_five_factory_benchmark.tscn']+(['--','--double'] if args.double else []),stdout=log,stderr=subprocess.STDOUT,timeout=240)
    if run.returncode or 'SCRIPT ERROR' in (OUT/'run.log').read_text() or not (OUT/'result.json').exists():
        raise RuntimeError(f'Benchmark failed; see {OUT}/run.log')
    r=json.loads((OUT/'result.json').read_text())
    assert not r['failures'] and len(r['sample'])==10,r['failures']
    assert [x['turn'] for x in r['sample']]==list(range(40,50))
    if not args.double:assert all(x['flow']<=x['cap'] for x in r['settled_links'])
    if args.check_baseline:
        old=json.loads(BASELINE.read_text())
        for key in ['layout','expected_production','expected_inputs','expected_sales','routes','settled_links']:
            assert old[key]==r[key],key
        for a,b in zip(old['sample'],r['sample']):
            assert a['stock']==b['stock'] and a['transit']==b['transit']
            for key in ['contribution','factory_costs']:assert abs(a[key]-b[key])<.001,key
            for key in ['goods_sales_revenue','goods_purchased_cost','transport_paid','warehousing_paid']:
                assert abs(a['summary'][key]-b['summary'][key])<.001,key
        print('Five-factory baseline verified: turns 40-49, cash reconciliation, exact quantities, steady inventories; congestion recorded in settled links.')
    if args.write_baseline:
        r.pop('turns');BASELINE.write_text(json.dumps(r,indent=2)+'\n')
        print('Baseline written:',BASELINE)
    return 0

if __name__=='__main__':raise SystemExit(main())
