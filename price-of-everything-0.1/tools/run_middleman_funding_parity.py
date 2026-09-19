#!/usr/bin/env python3
"""Compare 50 funded provider turns headlessly and in a minimized Godot window."""
import sys,subprocess,json
from pathlib import Path
r=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(r/'tools'))
from run_tests import find_godot
runs={}
for mode,flags in [('headless',['--headless']),('windowed',['--minimized'])]:
 log=Path('/tmp/middleman-funded-'+mode+'.log')
 cmd=[find_godot(),*flags,'--path',str(r),'--log-file','/tmp/middleman-funded-'+mode+'-godot.log','res://tools/pepper_middleman_benchmark.tscn','--','--funding']
 with log.open('w') as f:p=subprocess.run(cmd,stdout=f,stderr=subprocess.STDOUT,timeout=240)
 text=log.read_text()
 assert p.returncode==0 and 'SCRIPT ERROR' not in text,(mode,p.returncode,text[-3000:])
 runs[mode]=json.loads(Path('/tmp/pepper-middleman-phase1-funded/report.json').read_text())
 assert not runs[mode]['failures']
 assert runs[mode]['rows'][0]['summary']['middleman_financing']>0
 print(mode,'passed; first loan',runs[mode]['rows'][0]['summary']['middleman_financing'],flush=True)
for a,b in zip(runs['headless']['rows'],runs['windowed']['rows']):
 for key in ['cash_after','cash_before','goods_purchases','goods_sales','middleman_fee','operating_contribution']:
  assert abs(a[key]-b[key])<1e-6,(a['turn'],key,a[key],b[key])
report={'status':'passed','turns_per_mode':50,'opening_cash':300,'initial_loan':runs['headless']['rows'][0]['summary']['middleman_financing'],'headless_windowed_cash_and_operating_results_match':True,'cash_after_50':runs['headless']['rows'][-1]['cash_after'],'includes_reload_after_turn':25}
(r/'reports/balance/middleman_phase1_funding_parity_2026-09-19.json').write_text(json.dumps(report,indent=2)+'\n')
print(report)
