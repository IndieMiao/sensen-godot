#!/usr/bin/env python3
"""Compile approved compact current P0 containers with authoritative fixture data."""
from pathlib import Path
import json,os,sys,subprocess
HERE=Path(__file__).resolve().parent;PLUGIN=HERE.parent/'figma-plugin';mode=sys.argv[1];assert mode in ['library','screen']
cloud=json.loads((HERE/'state.json').read_text());raw=(PLUGIN/'code.js').read_text();bundle=json.JSONDecoder().raw_decode(raw.split('const BUNDLE = ',1)[1])[0]
ids=['BAG-1-P0','GEAR-P0-1','GEAR-P0-2','STORE-1','STORE-2'];sid=sys.argv[2] if mode=='screen' else None;spec=None
if sid:
 assert sid in ids;spec=next(s for s in json.loads((HERE.parent/'data/current-all.json').read_text()) if s['id']==sid);spec={k:v for k,v in spec.items() if k!='original'}
bundle.update(screens=[spec] if spec else [],sceneBytes={},iconSvgs={},iconNodeIds={},assetNames={},flowRepairStates=[],npcFlowStates=[]);bundle['sceneHashes'].update(json.loads((HERE.parent/'data/legacy-scene-hashes.json').read_text())['hashes']);bundle['sceneHashes'].update(cloud.get('sceneHashes',{}));bundle.pop('avatarAssets',None);bundle.pop('avatarControlIcons',None);bundle.pop('freeTravelStates',None);bundle.pop('freeTravelPassport',None);bundle.pop('cropDexData',None)
bundle['sceneHashes']={k:v for k,v in bundle['sceneHashes'].items() if k in {'farm',(spec or {}).get('sceneName') or (spec or {}).get('scene') or 'farm'}}
files=['src.js','visual-polish-fixes.js'] if mode=='library' else ['src.js','legacy-icon-fixes.js','legacy-fixes.js','legacy-pin-fixes.js','hud-navigation-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js']
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),'library:polish' if mode=='library' else 'screens:general|BAG-1,'+sid,*[str(PLUGIN/f) for f in files]],text=True)
source+='\n'+subprocess.check_output(['node',str(HERE/'select_legacy_declarations.cjs'),'screen',str(PLUGIN/'visual-container-fixes.js')],text=True)
source+='\n'+(PLUGIN/'visual-current-containers.js').read_text().split('// SOURCE WRAPPERS')[0]
if mode=='screen':source+='\n'+(PLUGIN/'overlay-cleanup-fixes.js').read_text()
state={k:cloud[k] for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']};state['npcFlowScreens']=cloud.get('npcFlowScreens',{})
state['variables']={k:v for k,v in state['variables'].items() if k.startswith(('color/','space/','radius/','p0bag/'))};state['icons']={k:v for k,v in state['icons'].items() if k.startswith('i-')};state['kit']={k:v for k,v in state['kit'].items() if not k.startswith(('Reference','FacilityMarker/','Avatar','NoteSelection/','Compact/Kitchen/','LegacyCollectionCell/','LegacyGearSlot/'))}
restore=(HERE/'legacy-adapter-restore.js.txt').read_text().replace('__STATE__',json.dumps(state,separators=(',',':')))
if mode=='library':restore=restore[:restore.index('const CLOUD_REACTION_BASE=')];tail='''await currentCompactContainerLibrary();return {...legacyNewNodeIds(),mutatedNodeIds:[],variables:LEDGER.variables};'''
else:
 restore+='\nObject.assign(LEDGER.screens,CLOUD_STATE.npcFlowScreens||{});\n'
 tail='''const s=BUNDLE.screens[0];if(s.id==='STORE-1')for(const id of ['STORE-TORCH-TAKEN-10','STORE-TORCH-TAKEN-ALL']){const target=LEDGER.screens[id]?await figma.getNodeByIdAsync(LEDGER.screens[id]):null;if(!target||target.type!=='FRAME'||target.children.length<2)throw Error('Create the exact Torch result first: '+id);}
const screen=await figma.getNodeByIdAsync(LEDGER.screens[s.id]);if(!screen||screen.type!=='FRAME')throw Error('Missing existing current screen '+s.id);for(const n of [...screen.children])n.remove();for(const n of [...screen.parent.children].filter(n=>n.type==='TEXT'))n.remove();currentCompactContainerInto(screen,s);reviewNote(screen.parent,s,816);screen.parent.placeholder=false;await wire();await Promise.all(STYLE_JOBS);return {...legacyNewNodeIds(),mutatedNodeIds:[screen.id,screen.parent.id],screens:[{id:s.id,nodeId:screen.id}],overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,fixturePreserved:true};'''
code='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore+'\n'+tail;dest=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/('current-container-library.js' if mode=='library' else 'current-container-'+sid+'.js'))));dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(code);subprocess.run(['node',str(HERE/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(dest)],check=True);assert dest.stat().st_size<50000
print(json.dumps({'mode':mode,'id':sid,'file':str(dest),'bytes':dest.stat().st_size,'figmaExecuted':False,'stateWritten':False}))
