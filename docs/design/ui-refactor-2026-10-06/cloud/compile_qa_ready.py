#!/usr/bin/env python3
"""Prepare separately bounded QA scripts. Does not execute Figma or edit state."""
from pathlib import Path
import json,subprocess,shutil,hashlib,datetime,os
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
cards=json.loads((ROOT/'data/legacy-screens.json').read_text())+json.loads((ROOT/'data/current-all.json').read_text())
indices={s['id']:i for i,s in enumerate(cards)}
ids=[s['id'] for s in json.loads((HERE/'legacy-qa-rebuild-targets.json').read_text())['targets']]+['COOK-2a','COOK-2b','COOK-P0-2','TODAY-1','TODAY-2','TUT-1']
out=HERE/'qa-ready';out.mkdir(exist_ok=True)
results=[]
for screen_id in ids:
 command=['python3',str(HERE/'build_cloud.py'),'screens',str(indices[screen_id]),'1','rebuild']
 target=out/f'{screen_id}.js'
 run=subprocess.run(command,text=True,capture_output=True,env={**os.environ,'GENSEN_CLOUD_OUTPUT':str(target)})
 result={'id':screen_id,'index':indices[screen_id],'compileExitCode':run.returncode,'regenerateCommand':command}
 if run.returncode==0:
  target=out/f'{screen_id}.js'
  check=subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(target)],text=True,capture_output=True)
  result.update(file=str(target),characters=len(target.read_text()),bytes=target.stat().st_size,sha256=hashlib.sha256(target.read_bytes()).hexdigest(),preflightExitCode=check.returncode)
  if check.returncode:result['error']=check.stderr
 else:result['error']=run.stdout+'\n'+run.stderr
 results.append(result)
report={'preparedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'figmaExecuted':False,'stateMutated':False,'bundleSha256':json.loads((ROOT/'figma-plugin/bundle-report.json').read_text())['sha256'],'scripts':results,'allPassed':all(r['compileExitCode']==0 and r.get('preflightExitCode')==0 for r in results)}
(out/'compile-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'allPassed':report['allPassed'],'scripts':[{k:r[k] for k in ['id','characters','compileExitCode','preflightExitCode'] if k in r}for r in results]},ensure_ascii=False,indent=2))
raise SystemExit(0 if report['allPassed'] else 1)
