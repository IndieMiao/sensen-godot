#!/usr/bin/env python3
"""Compile one same-item NPC result with saved node IDs; no MCP or state writes."""
from pathlib import Path
import json,subprocess,sys,os
HERE=Path(__file__).resolve().parent
PLUGIN=HERE.parent/'figma-plugin'
states=json.loads((HERE.parent/'data/legacy-npc-flow-states.json').read_text())
id=sys.argv[1]
spec=next((s for s in states if s['id']==id),None)
if spec is None:raise SystemExit('Unknown NPC outcome '+id)
raw=(PLUGIN/'code.js').read_text();bundle=json.JSONDecoder().raw_decode(raw.split('const BUNDLE = ',1)[1])[0];cloud=json.loads((HERE/'state.json').read_text())
bundle['screens']=[{'id':s['id'],'layout':s['layout']} for s in bundle['screens']]
bundle['npcFlowStates']=[spec];bundle['flowRepairStates']=[];bundle['sceneHashes'].update(json.loads((HERE.parent/'data/legacy-scene-hashes.json').read_text())['hashes']);bundle['sceneHashes'].update(cloud.get('sceneHashes',{}));bundle.update(sceneBytes={},iconSvgs={},iconNodeIds={},assetNames={});bundle.pop('avatarAssets',None);bundle.pop('avatarControlIcons',None);bundle.pop('freeTravelStates',None);bundle.pop('freeTravelPassport',None);bundle.pop('cropDexData',None)
files=['src.js','legacy-icon-fixes.js','hud-navigation-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','legacy-npc-flow-fixes.js']
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),'screens:general|BAG-1,NPC_FLOW_CREATE,'+id,*[str(PLUGIN/f) for f in files if (PLUGIN/f).exists()]],text=True)
assert 'Compact/NPC transaction result' in source, 'Creator was removed by cloud source filtering'
source+='\n'+(PLUGIN/'overlay-cleanup-fixes.js').read_text()
state={k:cloud[k] for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']};state['variables']={k:v for k,v in state['variables'].items() if k.startswith(('color/','space/','radius/'))};state['icons']={k:v for k,v in state['icons'].items() if k.startswith('i-')};state['kit']={k:v for k,v in state['kit'].items() if not k.startswith(('Reference','FacilityMarker/','Compact/Kitchen/','Compact/Inventory','Compact/Quick','Compact/Filter','Avatar','NoteSelection/'))}
restore=(HERE/'legacy-adapter-restore.js.txt').read_text().replace('__STATE__',json.dumps(state,separators=(',',':')))
tail='''await wire();await Promise.all(STYLE_JOBS);
const requested=__REQUESTED__,record=BUNDLE.npcFlowStates[0],resultId=LEDGER.npcFlowScreens?.[requested],sceneId=LEDGER.npcFlowScreens?.[requested+'/scene'];
if(!resultId||!sceneId)throw Error('Requested NPC result was not created: '+requested);
for(const id of [resultId,sceneId]){const node=await figma.getNodeByIdAsync(id);if(!node||node.type!=='FRAME'||node.children.length<2)throw Error('Empty or missing NPC result frame '+id);const header=node.children.find(x=>x.type==='INSTANCE'&&x.name==='HUD');if(!header)throw Error('Result HUD is missing '+id);const props=header.componentProperties;const value=name=>Object.entries(props).find(([key])=>key.split('#')[0]===name)?.[1]?.value;const expected=String(record.hud.energy)+'/'+String(record.hud.capacity);if(value('Energy')!==expected||value('Coins')!==String(record.hud.coins))throw Error('After-state HUD mismatch in '+id);}
return {...legacyNewNodeIds(),mutatedNodeIds:[],requestedFrameId:resultId,requestedSceneId:sceneId,verifiedAfterHUD:true,npcFlowScreens:LEDGER.npcFlowScreens,overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,sourceReferences:LEDGER.sourceReferences,prototypeOnly:true};'''.replace('__REQUESTED__',json.dumps(id))

code='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore+'\n'+tail
dest=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/f'legacy-npc-flow-{id}.js')));dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(code);subprocess.run(['node',str(HERE/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(dest)],check=True)
assert dest.stat().st_size<50000, 'MCP script exceeds 50KB'
print(json.dumps({'id':id,'file':str(dest),'bytes':dest.stat().st_size,'figmaExecuted':False,'stateWritten':False}))
