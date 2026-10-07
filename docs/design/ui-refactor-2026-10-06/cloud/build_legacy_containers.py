#!/usr/bin/env python3
"""Prepare compact container library or one existing screen. No MCP/state mutation."""
from pathlib import Path
import json,sys,os,subprocess
HERE=Path(__file__).resolve().parent;PLUGIN=HERE.parent/'figma-plugin';mode=sys.argv[1]
assert mode in ['library','screen']
cloud=json.loads((HERE/'state.json').read_text());raw=(PLUGIN/'code.js').read_text();bundle=json.JSONDecoder().raw_decode(raw.split('const BUNDLE = ',1)[1])[0]
spec=None
if mode=='screen':
 sid=sys.argv[2];spec=next(s for s in bundle['screens'] if s['id']==sid);spec={**spec,**next(s for s in json.loads((HERE.parent/'data/legacy-screens.json').read_text()) if s['id']==sid)};assert sid in ['BAG-2','BAG-2-2','BAG-3','BAG-4','BAG-4-2','BAG-5','BAG-5-2']
 for k in ['gridCells','quickSlots','bagContents','quickContents','sourceGridVariants','sourceQuickVariants','sourceScreenshot','layoutSpecialization','rebuildStatus','sourceKind','figmaSectionName','original','originalVisibleText','reviewedEvidence']:spec.pop(k,None)
 def clean(v):
  if isinstance(v,dict):return {k:clean(x) for k,x in v.items() if k not in ['sourceSprite','sourceClasses']}
  if isinstance(v,list):return [clean(x) for x in v]
  return v
 spec=clean(spec)
bundle['screens']=[spec] if spec else [];bundle['sceneHashes'].update(json.loads((HERE.parent/'data/legacy-scene-hashes.json').read_text())['hashes']);bundle['sceneHashes'].update(cloud.get('sceneHashes',{}));bundle.update(sceneBytes={},iconSvgs={},iconNodeIds={},assetNames={},flowRepairStates=[],npcFlowStates=[]);bundle.pop('avatarAssets',None);bundle.pop('avatarControlIcons',None);bundle.pop('freeTravelStates',None);bundle.pop('freeTravelPassport',None);bundle.pop('cropDexData',None)
files=['src.js','visual-polish-fixes.js'] if mode=='library' else ['src.js','legacy-icon-fixes.js','legacy-fixes.js','legacy-pin-fixes.js','hud-navigation-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','legacy-npc-flow-fixes.js']
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),'library:polish' if mode=='library' else 'screens:general|BAG-1,'+sid,*[str(PLUGIN/f) for f in files]],text=True)
source+='\n'+subprocess.check_output(['node',str(HERE/'select_legacy_declarations.cjs'),mode,str(PLUGIN/'visual-container-fixes.js')],text=True)
if mode=='screen':source+='\n'+(PLUGIN/'overlay-cleanup-fixes.js').read_text()
state={k:cloud[k] for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']}
state['variables']={k:v for k,v in state['variables'].items() if not k.startswith(('bag/','kitchen/')) and (not k.startswith('container/') or mode=='library' or k.startswith('container/'+sid+'/'))}
state['icons']={k:v for k,v in state['icons'].items() if k.startswith('i-')}
state['kit']={k:v for k,v in state['kit'].items() if not k.startswith(('Reference','FacilityMarker/','Compact/Kitchen/','Avatar','NoteSelection/','LegacyCollectionCell/','LegacyGearSlot/'))}
restore=(HERE/'legacy-adapter-restore.js.txt').read_text().replace('__STATE__',json.dumps(state,separators=(',',':')))
if mode=='library':restore=restore[:restore.index('const CLOUD_REACTION_BASE=')]
if mode=='library':tail='''libraryY=LIBRARY.height+80;await visualContainerLibrary();await Promise.all(STYLE_JOBS);return {...legacyNewNodeIds(),mutatedNodeIds:[],kit:Object.fromEntries(Object.entries(KIT).filter(([k])=>k.startsWith('Compact/GearSlot/')).map(([k,n])=>[k,n.id])),components:LEDGER.components,componentSets:LEDGER.componentSets,variables:LEDGER.variables};'''
else:
 draw={'BAG-2':'compactGear','BAG-2-2':'compactStorage','BAG-3':'compactBagDetail','BAG-4':'compactDrag','BAG-4-2':'compactPinReference','BAG-5':'compactFull','BAG-5-2':'compactParcel'}[sid]
 tail='''const s=BUNDLE.screens[0],screen=await figma.getNodeByIdAsync(LEDGER.screens[s.id]);if(!screen||screen.type!=='FRAME')throw Error('Missing original review target '+s.id);for(const child of [...screen.children])child.remove();for(const n of [...screen.parent.children].filter(n=>n.type==='TEXT'))n.remove();if(s.id!=='BAG-4-2'){containerCamera(screen,s,s.id!=='BAG-5-2');hud(screen,s);}__DRAW__(screen,s);reviewNote(screen.parent,s,816);screen.parent.placeholder=false;await wire();await Promise.all(STYLE_JOBS);return {...legacyNewNodeIds(),mutatedNodeIds:[screen.id,screen.parent.id],screens:[{id:s.id,nodeId:screen.id}],overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,prototypeReactions:LEDGER.checks.prototypeReactions};'''.replace('__DRAW__',draw)
code='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore+'\n'+tail
dest=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/('legacy-container-library.js' if mode=='library' else 'legacy-container-'+sid+'.js'))));dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(code);subprocess.run(['node',str(HERE/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(dest)],check=True);assert dest.stat().st_size<50000, 'MCP script exceeds50KB';print(json.dumps({'mode':mode,'id':spec['id'] if spec else None,'file':str(dest),'bytes':dest.stat().st_size,'figmaExecuted':False,'stateWritten':False}))
