#!/usr/bin/env python3
"""P3 gate: preserved P0–P2 controls plus seven actual chain/remote-source runs."""
import argparse,json,subprocess,sys
from pathlib import Path
from run_tests import find_godot
ROOT=Path(__file__).resolve().parents[1]
OUT=Path('/tmp/pepper-p3'); OUT.mkdir(exist_ok=True)
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full',action='store_true')
    args=parser.parse_args()
    subprocess.run([sys.executable,str(ROOT/'tools/run_middleman_phase0.py'),'--phase2']+(['--full'] if args.full else []),check=True)
    reports=[]
    for chain,mode,remote in [(c,m,False) for c in ['steel','five'] for m in ['middleman','managed','mixed']]+[('five','mixed',True)]:
        name=f'{chain}-{mode}'+('-remote' if remote else '')
        cmd=[find_godot(),'--headless','--path',str(ROOT),'--log-file',str(OUT/(name+'-godot.log')),'res://tools/pepper_middleman_p3.tscn','--']
        if chain=='steel': cmd+=['--steel']
        if mode!='managed':cmd+=['--'+mode]
        if remote:cmd+=['--remote']
        with (OUT/(name+'.log')).open('w') as f: p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=210)
        text=(OUT/(name+'.log')).read_text()
        if p.returncode or 'SCRIPT ERROR' in text: raise RuntimeError(f'{name} failed: {text[-3500:]}')
        result=json.loads((OUT/(name+'.json')).read_text())
        assert result['status']=='passed',result['failures']
        reports.append(result)
        print(name, result['averages'],flush=True)
    report={'phase':3,'status':'passed','full_gate':args.full,'cases':reports}
    path=ROOT/'reports/balance/middleman_phase3_chains_2026-09-19.json'
    path.write_text(json.dumps(report,indent=2)+'\n')
    print(path)
if __name__=='__main__':main()
