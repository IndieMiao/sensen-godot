#!/usr/bin/env python3
"""Package the validated local plugin; cloud checks are maintained separately."""
from pathlib import Path
import json,re,zipfile,hashlib
p=Path(__file__).resolve().parent
root=p.parents[3]
v=json.loads((p/'local-validation.json').read_text());b=json.loads((p/'bundle-report.json').read_text())
assert hashlib.sha256((p/'code.js').read_bytes()).hexdigest()==b['sha256'],'Rebuild code.js first'
assert v['status']=='local-construction-passed','Local validation must pass'
assert v.get('bundleSha256')==b['sha256'],'Validation must match the exact current bundle'
gaps=json.loads((p/'prototype-gap-ledger.json').read_text())
assert gaps['bundleSha256']==b['sha256'],'Gap ledger must match current verified bundle'
source_manifest=json.loads((p/'source-manifest.json').read_text())
assert source_manifest['bundleSha256']==b['sha256'],'Source manifest must match current bundle'
for entry in source_manifest['files']:
 assert hashlib.sha256((root/entry['path']).read_bytes()).hexdigest()==entry['sha256'],'Build input changed after verification: '+entry['path']
r=p/'README.md';s=r.read_text()
s=re.sub(r'本次本地构建得到 [\d,]+ 个原型反应',f"本次本地构建得到 {v['prototypeReactions']:,} 个原型反应",s)
s=re.sub(r'\*\*\d+ 个位置、\d+ 个不同动作\*\*',f"**{v['missingOutcomeWarnings']} 个位置、{v['uniqueMissingOutcomes']} 个不同动作**",s)
s=re.sub(r'最终本地记录：.*?；所有上述结构检查通过。',f"最终本地记录：{v['screens']} 屏、{v['stateExamples']} 状态例、{v['semanticComponentNodes']} 个语义主组件/变体节点、{v['componentSets']} 个组件集、{v['fallbackVectorMasters']} 个矢量后备主组件、{v['instances']:,} 个实例；所有上述结构检查通过。",s)
s=s.replace('`src.js` → `current-fixes.js` → `legacy-fixes.js`；MCP适配器也须读取这三份文件。','`src.js` → `current-fixes.js` → `legacy-fixes.js` → `legacy-scene-fixes.js`；MCP适配器也须按此顺序读取四份文件。')
r.write_text(s)
with zipfile.ZipFile(p/'gensen-ui-refactor-plugin.zip','w',zipfile.ZIP_DEFLATED) as z:
 for name in ['manifest.json','code.js','ui.html','README.md','bundle-report.json','local-validation.json','local-destination-warnings.json','source-grid-evidence.json','source-manifest.json','prototype-gap-ledger.json']:
  z.write(p/name,'gensen-ui-refactor/'+name)
with zipfile.ZipFile(p/'gensen-ui-refactor-plugin.zip') as z:
 assert z.testzip() is None
 assert hashlib.sha256(z.read('gensen-ui-refactor/code.js')).hexdigest()==b['sha256'],'Packaged code differs from verified bundle'
 members=[{'path':name,'bytes':len(z.read(name)),'sha256':hashlib.sha256(z.read(name)).hexdigest()} for name in z.namelist()]
artifact={'schemaVersion':1,'bundleSha256':b['sha256'],'zip':'gensen-ui-refactor-plugin.zip','zipBytes':(p/'gensen-ui-refactor-plugin.zip').stat().st_size,'zipSha256':hashlib.sha256((p/'gensen-ui-refactor-plugin.zip').read_bytes()).hexdigest(),'members':members,'localValidation':'local-construction-passed','cloudVisualAcceptance':'See cloud receipts and screenshot reports;this ZIP verification does not establish visual acceptance.'}
(p/'artifact-manifest.json').write_text(json.dumps(artifact,ensure_ascii=False,indent=2)+'\n')
print('Packaged',b['sha256'],(p/'gensen-ui-refactor-plugin.zip').stat().st_size)
