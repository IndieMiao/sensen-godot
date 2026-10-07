#!/usr/bin/env python3
"""Prepare one authored continuation; no cloud execution and no state writes."""
from pathlib import Path
import json,sys,subprocess,os
HERE=Path(__file__).resolve().parent
PLUGIN=HERE.parent/'figma-plugin'
states=json.loads((HERE.parent/'data/flow-repair-states.json').read_text())
screen_id=sys.argv[1]
spec=next((s for s in states if s['id']==screen_id),None)
if spec is None:raise SystemExit('Unknown flow state: '+screen_id)
spec={k:v for k,v in spec.items() if k!='original'}
raw=(PLUGIN/'code.js').read_text()
bundle=json.JSONDecoder().raw_decode(raw.split('const BUNDLE = ',1)[1])[0]
cloud=json.loads((HERE/'state.json').read_text())
bundle['screens']=[{'id':s['id'],'layout':s['layout']} for s in bundle['screens']]
bundle['flowRepairStates']=[spec]
bundle['npcFlowStates']=[]
bundle['sceneHashes'].update(cloud.get('sceneHashes',{}))
bundle.update(sceneBytes={},iconSvgs={},iconNodeIds={},assetNames={})
bundle.pop('avatarAssets',None)
bundle.pop('avatarControlIcons',None);bundle.pop('freeTravelStates',None);bundle.pop('freeTravelPassport',None);bundle.pop('cropDexData',None)
files=['src.js','current-fixes.js','legacy-fixes.js','legacy-scene-fixes.js','legacy-reference-fixes.js','legacy-pin-fixes.js','kitchen-scene-fixes.js','kitchen-selection-fixes.js','action-picker-fixes.js','hud-navigation-fixes.js','legacy-qa-fixes.js','current-qa-fixes.js','camera-highlight-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','flow-repair-fixes.js']
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),'screens:general|'+screen_id,*[str(PLUGIN/f) for f in files if (PLUGIN/f).exists()]],text=True)
source=source.replace("function auto(p,name,w,dir='VERTICAL',gap=6,color) {const n=frame(p,name,w,1,color);n.layoutMode=dir;", "function auto(p,name,w,dir='VERTICAL',gap=6,color) {const n=figma.createAutoLayout(dir);n.name=name;n.resize(w,1);fill(n,color);p.appendChild(n);")
source+='\n'+(PLUGIN/'overlay-cleanup-fixes.js').read_text()
state={k:cloud[k] for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']}
state['kit']={k:v for k,v in state['kit'].items() if k.startswith(('Compact/QuickSlot/','Compact/QuickEnd/')) or not k.startswith(('Compact/','ReferenceBadge/','ReferenceEnergy/','NoteSelection/','FacilityMarker/'))}
state['styles']={k:v for k,v in state['styles'].items() if not k.startswith('compact/')}
state['icons']={k:v for k,v in state['icons'].items() if k.startswith('i-')}
state['variables']={k:v for k,v in state['variables'].items() if not k.startswith(('bag/','kitchen/','container/'))}
restore='''
const CLOUD_STATE=__STATE__;
PAGE=await figma.getNodeByIdAsync(CLOUD_STATE.pageId);await figma.setCurrentPageAsync(PAGE);
LIBRARY=await figma.getNodeByIdAsync(CLOUD_STATE.libraryId);
await Promise.all(['Regular','Bold','ExtraBold'].map(style=>figma.loadFontAsync({family:T.font.family,style})));
for(const [key,id]of Object.entries(CLOUD_STATE.variables))VAR[key]=await figma.variables.getVariableByIdAsync(id);
for(const [key,id]of Object.entries(CLOUD_STATE.styles))STYLE[key]=await figma.getStyleByIdAsync(id);
for(const [key,id]of Object.entries(CLOUD_STATE.kit))KIT[key]=await figma.getNodeByIdAsync(id);
for(const [key,id]of Object.entries(CLOUD_STATE.icons))ICON[key]=await figma.getNodeByIdAsync(id);
for(const row of PAGE.children.filter(n=>n.type==='SECTION'))for(const section of row.children.filter(n=>n.type==='SECTION'))for(const n of section.children.filter(n=>n.type==='FRAME'))LEDGER.screens[n.name.split(' · ')[0]]=n.id;
overlayIndex=CLOUD_STATE.overlayIndex||0;
const beforeIds=new Set(PAGE.findAll(()=>true).map(n=>n.id));
const CLOUD_REACTION_BASE=setReaction;setReaction=async function(node,action){const clean={...action};delete clean.overlayRelativePosition;return await CLOUD_REACTION_BASE(node,clean);};
await wire();await Promise.all(STYLE_JOBS);
const created=PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id));
const inherited={};for(const n of created)if(n.id.startsWith('I')){const at=n.id.indexOf(';'),prefix=n.id.slice(0,at),suffix=n.id.slice(at+1);(inherited[prefix]??=[]).push(suffix);}
return {createdNodeIds:created.filter(n=>!n.id.startsWith('I')).map(n=>n.id),inheritedNodeIdGroups:Object.fromEntries(Object.entries(inherited).map(([prefix,suffixes])=>[prefix,suffixes.join('|')])),mutatedNodeIds:[],flowScreens:LEDGER.flowScreens,flowSceneScreens:LEDGER.flowSceneScreens,mainScreenCount:Object.keys(LEDGER.screens).length,overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,sourceReferences:LEDGER.sourceReferences};
'''.replace('__STATE__',json.dumps(state,separators=(',',':')))
output='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore
target=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/'flow-repairs.js')))
target.parent.mkdir(parents=True,exist_ok=True);target.write_text(output)
subprocess.run(['node',str(HERE/'minify.cjs'),str(target)],check=True)
subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(target)],check=True)
print(json.dumps({'id':screen_id,'file':str(target),'figmaExecuted':False,'stateWritten':False}))
