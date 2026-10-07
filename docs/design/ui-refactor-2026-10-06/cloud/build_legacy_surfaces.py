#!/usr/bin/env python3
"""Prepare screenshot-led legacy surface repair on an existing review frame. No MCP/state mutation."""
from pathlib import Path
import json,sys,os,subprocess
HERE=Path(__file__).resolve().parent;PLUGIN=HERE.parent/'figma-plugin';mode='screen'
cloud=json.loads((HERE/'state.json').read_text());raw=(PLUGIN/'code.js').read_text();bundle=json.JSONDecoder().raw_decode(raw.split('const BUNDLE = ',1)[1])[0]
spec=None
if mode=='screen':
 sid=sys.argv[1];spec=next(s for s in bundle['screens'] if s['id']==sid);spec={**spec,**next(s for s in json.loads((HERE.parent/'data/legacy-screens.json').read_text()) if s['id']==sid)};assert sid in ['NPC-1a','NPC-1b','NPC-1c','NPC-1d','PROFILE-1','PROFILE-2','FISH-6','COOK-4','COOK-6','COOK-7','HUD-2','MAP-1','SETTINGS-1','SKILL-1','SKILL-2','MINE-1','FISH-5','SKILL-3','TUT-2-2','NPC-4','NPC-5','NPC-5-2','NPC-6','NPC-7','NPC-1e','NPC-G1','NPC-G1-2','NPC-G1-3','NPC-G1-4','FARM-5','HOME-1','HOME-2','SOC-4']
 for k in ['gridCells','quickSlots','bagContents','quickContents','sourceGridVariants','sourceQuickVariants','sourceScreenshot','layoutSpecialization','rebuildStatus','sourceKind','figmaSectionName','original','originalVisibleText','reviewedEvidence']:spec.pop(k,None)
 def clean(v):
  if isinstance(v,dict):return {k:clean(x) for k,x in v.items() if k not in ['sourceSprite','sourceClasses']}
  if isinstance(v,list):return [clean(x) for x in v]
  return v
 spec=clean(spec)
 if sid=='SKILL-2' and spec.get('items'):spec['items'][0]['quantity']['label']='At Lv2'
bundle['screens']=[spec] if spec else [];bundle['sceneHashes'].update(json.loads((HERE.parent/'data/legacy-scene-hashes.json').read_text())['hashes']);bundle['sceneHashes'].update(cloud.get('sceneHashes',{}));bundle.update(sceneBytes={},iconSvgs={},iconNodeIds={},assetNames={},flowRepairStates=[],npcFlowStates=[]);bundle.pop('avatarAssets',None);bundle.pop('avatarControlIcons',None);bundle.pop('freeTravelStates',None);bundle.pop('freeTravelPassport',None);bundle.pop('cropDexData',None)
files=['src.js','visual-polish-fixes.js'] if mode=='library' else ['src.js','legacy-icon-fixes.js','legacy-fixes.js','legacy-pin-fixes.js','hud-navigation-fixes.js','camera-highlight-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','legacy-npc-flow-fixes.js']
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),'library:polish' if mode=='library' else 'screens:general|BAG-1,'+sid,*[str(PLUGIN/f) for f in files]],text=True)
if sid in ['COOK-4','COOK-6']:
 source+='\nfunction discoverCookResults(){LEDGER.npcFlowScreens=LEDGER.npcFlowScreens||{};for(const n of PAGE.children)if(n.type==="FRAME"&&n.name.startsWith("NPC state · ")){const id=n.name.slice("NPC state · ".length).split(" · ")[0];LEDGER.npcFlowScreens[id]=n.id;LEDGER.screens[id]=n.id;}}'
source+='\n'+subprocess.check_output(['node',str(HERE/'select_legacy_declarations.cjs'),mode,str(PLUGIN/'visual-container-fixes.js')],text=True)
source+='\n'+subprocess.check_output(['node',str(HERE/'select_legacy_declarations.cjs'),mode,str(PLUGIN/'visual-legacy-surfaces.js')],text=True)
source+='\n'+subprocess.check_output(['node',str(HERE/'select_legacy_declarations.cjs'),'crop-discover',str(PLUGIN/'crop-dex-fixes.js')],text=True)
source+='\nconst CROP_REPLAY_BASE=wire;wire=async function(){discoverCropDex();await CROP_REPLAY_BASE();};'
if mode=='screen':source+='\n'+(PLUGIN/'overlay-cleanup-fixes.js').read_text()
state={k:cloud[k] for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']}
state['variables']={k:v for k,v in state['variables'].items() if not k.startswith(('bag/','kitchen/')) and (not k.startswith('container/') or mode=='library' or k.startswith('container/'+sid+'/'))}
state['icons']={k:v for k,v in state['icons'].items() if k.startswith('i-')}
state['kit']={k:v for k,v in state['kit'].items() if not k.startswith(('Reference','FacilityMarker/','Compact/Kitchen/','Avatar','NoteSelection/','LegacyCollectionCell/','LegacyGearSlot/'))}
restore=(HERE/'legacy-adapter-restore.js.txt').read_text().replace('__STATE__',json.dumps(state,separators=(',',':')))
if mode=='library':restore=restore[:restore.index('const CLOUD_REACTION_BASE=')]
if mode=='library':tail='''libraryY=LIBRARY.height+80;await visualContainerLibrary();await Promise.all(STYLE_JOBS);return {...legacyNewNodeIds(),mutatedNodeIds:[],kit:Object.fromEntries(Object.entries(KIT).filter(([k])=>k.startsWith('Compact/GearSlot/')).map(([k,n])=>[k,n.id])),components:LEDGER.components,componentSets:LEDGER.componentSets,variables:LEDGER.variables};'''
else:
 draw='legacyRoomSurface' if sid.startswith('NPC-1') else 'legacyGreetingSurface' if sid.startswith('NPC-G1') else 'legacyUpgradeSurface' if sid=='HOME-2' else 'legacyProfileSurface' if sid.startswith('PROFILE-') else 'legacyFishDexSurface' if sid=='FISH-6' else 'legacyMealSurface' if sid=='COOK-7' else 'legacyMapSurface' if sid=='MAP-1' else 'legacyMineSurface' if sid=='MINE-1' else 'legacyCompactSheet'
 tail='''const s=BUNDLE.screens[0];if(['COOK-4','COOK-6'].includes(s.id)){discoverCookResults();for(const [id,node]of Object.entries(LEDGER.npcFlowScreens||{}))LEDGER.screens[id]=node;const target=s.actions.find(a=>a.label==='Eat')?.target;if(!target||!LEDGER.screens[target])throw Error('Create same-dish Eat result before redraw: '+s.id);}const screen=await figma.getNodeByIdAsync(LEDGER.screens[s.id]);if(!screen||screen.type!=='FRAME')throw Error('Missing original review target '+s.id);for(const child of [...screen.children])child.remove();for(const n of [...screen.parent.children].filter(n=>n.type==='TEXT'))n.remove();__DRAW__(screen,s);reviewNote(screen.parent,s,816);screen.parent.placeholder=false;await wire();await Promise.all(STYLE_JOBS);const verifiedCameraLinks=[];if(s.id==='NPC-4'){const links=PENDING_LINKS.filter(p=>p.ownerId===s.id&&p.detail?.cameraHighlight);if(links.length!==3)throw Error('Expected all3 Market Board map controls');for(const link of links){const reactions=link.node.reactions.flatMap(r=>r.actions||[r.action].filter(Boolean)),action=reactions.find(a=>a.type==='NODE'&&a.navigation==='OVERLAY');if(!action||LEDGER.overlays[action.destinationId]?.type!=='camera-highlight')throw Error('Map control does not open actual camera focus: '+link.node.id);verifiedCameraLinks.push({nodeId:link.node.id,destinationId:action.destinationId,kind:'camera-highlight'});}}return {...legacyNewNodeIds(),verifiedCameraLinks,mutatedNodeIds:[screen.id,screen.parent.id],screens:[{id:s.id,nodeId:screen.id}],overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,prototypeReactions:LEDGER.checks.prototypeReactions};'''.replace('__DRAW__',draw)
code='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore+'\n'+tail
dest=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/('legacy-container-library.js' if mode=='library' else 'legacy-surface-'+sid+'.js'))));dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(code);subprocess.run(['node',str(HERE/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(dest)],check=True);assert dest.stat().st_size<50000, 'MCP script exceeds50KB';print(json.dumps({'mode':mode,'id':spec['id'] if spec else None,'file':str(dest),'bytes':dest.stat().st_size,'figmaExecuted':False,'stateWritten':False}))
