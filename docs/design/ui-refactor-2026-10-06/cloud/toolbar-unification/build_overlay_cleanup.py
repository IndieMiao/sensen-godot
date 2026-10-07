#!/usr/bin/env python3
"""Compile bounded existing-overlay operations from a complete read-only receipt."""
from pathlib import Path
import json,sys,subprocess
HERE=Path(__file__).resolve().parent;CLOUD=HERE.parent;PLUGIN=CLOUD.parent/'figma-plugin'
mode=sys.argv[1];assert mode in ['dedup','refit'];receipt=Path(sys.argv[2])if len(sys.argv)>2 else HERE/'overlay-audit-result.json';data=json.loads(receipt.read_text());data=json.loads(next(c['text']for c in data['content']if c['type']=='text'))if 'content'in data else data
start=int(sys.argv[3])if len(sys.argv)>3 else 0;size=int(sys.argv[4])if len(sys.argv)>4 else (20 if mode=='dedup' else 80)
if mode=='dedup':
 plan=data['exactGroups'][start:start+size];assert plan,'Empty dedup slice'
 audit=(HERE/'overlay-audit.js').read_text();audit=audit[:audit.index("return {kind:'readonly-overlay-exact-dedup-audit'")]
 tail=(HERE/'overlay-dedup-tail.js.txt').read_text();code='const DEDUP_PLAN='+json.dumps(plan,separators=(',',':'))+';\n'+audit+'\n'+tail
else:
 targets=data['refitIds'][start:start+size];assert targets,'Empty refit slice';state=json.loads((CLOUD/'state.json').read_text());tokens=json.loads((CLOUD.parent/'data/tokens.json').read_text())
 select="""const fs=require('fs'),acorn=require('/tmp/gensen-ui-cloud-build/node_modules/acorn');const names=new Set(process.argv[1].split(','));for(const file of process.argv.slice(2)){const s=fs.readFileSync(file,'utf8').split('figma.showUI(__html__')[0],ast=acorn.parse(s,{ecmaVersion:'latest'});for(const n of ast.body)if(n.type==='FunctionDeclaration'&&names.has(n.id.name))process.stdout.write(s.slice(n.start,n.end)+'\\n');}"""
 source=subprocess.check_output(['node','-e',select,'rgb,solid,fill,radius,bounds,frame,absolute,propKeys,inst,overlayInformationParts,overlayRefitInformation',str(PLUGIN/'src.js'),str(PLUGIN/'overlay-cleanup-fixes.js')],text=True)
 config={'pageId':state['pageId'],'sheetId':state['kit']['Sheet'],'variables':{k:v for k,v in state['variables'].items()if k.startswith(('color/','radius/'))},'targets':targets}
 head='const REFIT='+json.dumps(config,separators=(',',':'))+';const T='+json.dumps(tokens,separators=(',',':'))+';const W=360,CW=328,KIT={},VAR={},LEDGER={checks:{}};\n'
 code=head+source+'\n'+(HERE/'overlay-refit-tail.js.txt').read_text()
tag=sys.argv[5]if len(sys.argv)>5 else '';dest=HERE/('overlay-'+mode+('-'+tag if tag else '')+'-'+str(start)+'.js');dest.write_text(code);subprocess.run(['node',str(CLOUD/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(CLOUD/'preflight_script.cjs'),str(dest)],check=True);assert dest.stat().st_size<50000;print(json.dumps({'mode':mode,'start':start,'count':len(plan if mode=='dedup'else targets),'bytes':dest.stat().st_size,'path':str(dest),'figmaExecuted':False}))
