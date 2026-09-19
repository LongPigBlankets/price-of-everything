#!/usr/bin/env python3
"""Verify middleman contracts and preserved evidence; --phase1 also runs the live provider benchmark."""
import argparse,hashlib,json,re,subprocess,sys
from pathlib import Path
from run_tests import find_godot
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('/tmp/middleman-phase0')
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full',action='store_true',help='Run the full unit suite and all three real baseline replays')
    parser.add_argument('--phase1',action='store_true',help='Also verify the live provider loop and write a phase-1 report')
    parser.add_argument('--phase2',action='store_true',help='Also verify the public start, introduction and actual second-factory construction')
    args=parser.parse_args()
    if args.phase2: args.phase1=True
    OUT.mkdir(exist_ok=True)
    manifest=json.loads((ROOT/'tests/scenarios/middleman_phase0_baseline_manifest.json').read_text())
    for name,expected in manifest['sha256'].items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==expected,f'Baseline changed: {name}'
    runs=[]
    def run(label,cmd,timeout=300):
        with (OUT/f'{label}.log').open('w') as log:
            proc=subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,timeout=timeout)
        text=(OUT/f'{label}.log').read_text()
        if proc.returncode or 'SCRIPT ERROR' in text or 'Parse Error:' in text:
            raise RuntimeError(f'{label} failed; see {OUT}/{label}.log\n{text[-4000:]}')
        match=re.search(r'==== (\d+) passed, (\d+) failed ====',text)
        if label.startswith('unit'):
            assert match and int(match[2])==0,f'Missing clean unit summary: {label}'
            assert 'test_middleman_contract.gd (8 of 8 tests)' in text,'Phase-0 tests were not all discovered'
            if args.phase1:
                assert 'test_middleman_service.gd (6 of 6 tests)' in text,'Phase-1 integration tests were not all discovered'
        if args.phase2 and label.startswith('unit'):
            assert 'test_middleman_presentation.gd (10 of 10 tests)' in text,'Phase-2 presentation tests were not all discovered'
        result={'label':label,'log':str(OUT/f'{label}.log'),'passed_checks':int(match[1]) if match else None}
        runs.append(result);print(json.dumps(result),flush=True)
    unit_cmd=[find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'godot_tests.log'),'res://tests/test_runner.tscn']
    if not args.full:unit_cmd+=['--','--tags','middleman']
    run('unit_full' if args.full else 'unit_middleman',unit_cmd)
    if args.full:
        run('roads',[sys.executable,'tools/run_pepper_valley_benchmark.py','--route','roads','--check-baseline'])
        run('rail_three_owned',[sys.executable,'tools/run_pepper_valley_benchmark.py','--route','rail-three-owned','--check-baseline'])
        run('five_factories',[sys.executable,'tools/run_pepper_five_factory_benchmark.py','--check-baseline'])
    if args.phase1:
        run('provider',[find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'provider_godot.log'),'res://tools/pepper_middleman_benchmark.tscn'])
        provider=json.loads(Path('/tmp/pepper-middleman-phase1/report.json').read_text())
        assert provider['status']=='passed' and len(provider['rows'])==50
        reference=json.loads((ROOT/'tests/snapshots/middleman_phase0_reference_v1.json').read_text())
        assert abs(provider['mean_operating_contribution']-reference['expected']['contribution'])<1e-6,'Provider/reference contribution changed'
        (ROOT/'reports/balance/pepper_middleman_phase1_2026-09-19.json').write_text(json.dumps(provider,indent=2)+'\n')
    if args.phase2:
        run('playable',[find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/'playable_godot.log'),'res://tools/pepper_middleman_playable.tscn'])
        playable=json.loads(Path('/tmp/pepper-middleman-p2/report.json').read_text())
        assert playable['status']=='passed' and playable['second_factory_completed_turn']>0
        (ROOT/'reports/balance/pepper_middleman_phase2_playable_2026-09-19.json').write_text(json.dumps(playable,indent=2)+'\n')
    report={'phase':0,'status':'contracts/reference fixtures verified; provider execution remains phase 1','full_gate':args.full,
        'preserved_baseline_digests':manifest['sha256'],'runs':runs,
        'limits':'Private holding fixture serialization is a proposed payload check, not an implemented SaveLoad middleman round trip. Phase-order/idempotency integration cases are specified for phase1; only pure quote/budget behaviour executes here.'}
    path=ROOT/'reports/balance'/('middleman_phase0_full_gate_2026-09-19.json' if args.full else 'middleman_phase0_focused_2026-09-19.json')
    if args.phase1:
        report.update(phase=1,status='Live provider, funding, failure recovery and SaveLoad verified',limits='Prototype: motor recipe at Pepper Valley only; internal start, not public onboarding. Controlled catalogue-price benchmark excludes research/events/public road growth.')
        report['provider_mean_operating_contribution']=provider['mean_operating_contribution']
        path=ROOT/'reports/balance'/('middleman_phase1_full_gate_2026-09-19.json' if args.full else 'middleman_phase1_focused_2026-09-19.json')
    if args.phase2:
        report.update(phase=2,status='Public Pepper Valley start, forecasts, independent truck endpoints, introduction and construction expansion verified',limits='Motor recipe at Pepper Valley only. Public-start acceptance retains market impact but excludes random decisions/research; UI inspected separately.')
        report['second_factory_completed_turn']=playable['second_factory_completed_turn']
        path=ROOT/'reports/balance'/('middleman_phase2_full_gate_2026-09-19.json' if args.full else 'middleman_phase2_focused_2026-09-19.json')
    path.write_text(json.dumps(report,indent=2)+'\n');print(path)
if __name__=='__main__':main()
