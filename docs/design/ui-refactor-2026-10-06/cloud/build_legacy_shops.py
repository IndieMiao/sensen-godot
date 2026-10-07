#!/usr/bin/env python3
"""Prepare original counter/Bag composition, preserving normalized NPC contracts."""
from pathlib import Path
import json,sys,os,subprocess
HERE=Path(__file__).resolve().parent;PLUGIN=HERE.parent/'figma-plugin';mode=sys.argv[1];assert mode in ['library','screen']
cloud=json.loads((HERE/'state.json').read_text());bundle=json.JSONDecoder().raw_decode((PLUGIN/'code.js').read_text().split('const BUNDLE = ',1)[1])[0];spec=None
if mode=='screen':
 sid=sys.argv[2];assert sid in ['NPC-2','NPC-2-2','NPC-3','NPC-3-2','FARM-6','FARM-6-2'];spec={**next(s for s in bundle['screens']if s['id']==sid),**next(s for s in json.loads((HERE.parent/'data/legacy-screens.json').read_text())if s['id']==sid)}
 for k in ['gridCells','quickSlots','bagContents','quickContents','sourceGridVariants','sourceQuickVariants','sourceScreenshot','layoutSpecialization','rebuildStatus','sourceKind','figmaSectionName','original','originalVisibleText','reviewedEvidence']:spec.pop(k,None)
 def clean(v):
  if isinstance(v,dict):return {k:clean(x)for k,x in v.items()if k not in ['sourceSprite','sourceClasses']}
  if isinstance(v,list):return [clean(x)for x in v]
  return v
 spec=clean(spec)
 spec['gridItems']=[{k:v for k,v in cell.items()if k in (['empty','selected']if cell.get('empty')else['icon','count','rarity','selected','empty','title','label','quantity','state','badges','source','hint','region'])}for cell in spec['gridItems']]
bundle['screens']=[spec]if spec else[];bundle['sceneHashes'].update(cloud.get('sceneHashes',{}));bundle.update(sceneBytes={},iconSvgs={},iconNodeIds={},assetNames={},flowRepairStates=[],npcFlowStates=[]);bundle.pop('avatarAssets',None);bundle.pop('avatarControlIcons',None);bundle.pop('freeTravelStates',None);bundle.pop('freeTravelPassport',None);bundle.pop('cropDexData',None)
files=['src.js','visual-polish-fixes.js']if mode=='library'else['src.js','legacy-icon-fixes.js','legacy-fixes.js','legacy-pin-fixes.js','hud-navigation-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','legacy-npc-flow-fixes.js']
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),'library:polish'if mode=='library'else'screens:general|BAG-1,'+sid,*[str(PLUGIN/f)for f in files]],text=True)
source+='\n'+subprocess.check_output(['node',str(HERE/'select_legacy_shop_declarations.cjs'),mode,str(PLUGIN/'visual-legacy-shops.js')],text=True)
if mode=='screen':source+='\n'+(PLUGIN/'overlay-cleanup-fixes.js').read_text()
state={k:cloud[k]for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']};state['variables']={k:v for k,v in state['variables'].items()if not k.startswith(('bag/','kitchen/','container/','p0bag/'))};state['icons']={k:v for k,v in state['icons'].items()if k.startswith('i-')};state['kit']={k:v for k,v in state['kit'].items()if not k.startswith(('Reference','FacilityMarker/','Compact/Kitchen/','Avatar','NoteSelection/','LegacyCollectionCell/','LegacyGearSlot/'))}
restore=(HERE/'legacy-adapter-restore.js.txt').read_text().replace('__STATE__',json.dumps(state,separators=(',',':')))
if mode=='screen':restore+='\nfor(const n of PAGE.children){if(n.type!=="FRAME")continue;const col=Math.round((n.x-3560)/400),row=Math.round((n.y-180)/900);if(col>=0&&col<3&&row>=0&&Math.abs(n.x-(3560+col*400))<1&&Math.abs(n.y-(180+row*900))<1)overlayIndex=Math.max(overlayIndex,row*3+col+1);}'
if mode=='library':
 restore=restore[:restore.index('const CLOUD_REACTION_BASE=')]
 tail="""libraryY=LIBRARY.height+80;legacyShopLibrary();await Promise.all(STYLE_JOBS);return {...legacyNewNodeIds(),mutatedNodeIds:[LIBRARY.id,...LEGACY_SHOP_MUTATED],kit:Object.fromEntries(Object.entries(KIT).filter(([k])=>k.startsWith('Compact/ShopProduct/')).map(([k,n])=>[k,n.id])),icons:Object.fromEntries(['i-sapling','i-rod-carbon','i-shop-sweet-potato'].map(k=>[k,ICON[k].id])),components:LEDGER.components,componentSets:LEDGER.componentSets,libraryHeight:LIBRARY.height};"""
else:
 tail="""const s=BUNDLE.screens[0],screen=await figma.getNodeByIdAsync(LEDGER.screens[s.id]);if(!screen||screen.type!=='FRAME'||!screen.name.startsWith(s.id+' ·'))throw Error('Expected existing shop target');const contractBefore=JSON.stringify({items:s.items,selected:s.selectedItem,keyFacts:s.keyFacts,actions:s.actions,grid:s.gridItems});for(const child of [...screen.children])child.remove();for(const note of [...screen.parent.children].filter(n=>n.type==='TEXT'))note.remove();legacyShopSurface(screen,s);reviewNote(screen.parent,s,816);screen.parent.placeholder=false;await wire();await Promise.all(STYLE_JOBS);const contractAfter=JSON.stringify({items:s.items,selected:s.selectedItem,keyFacts:s.keyFacts,actions:s.actions,grid:s.gridItems});if(contractBefore!==contractAfter)throw Error('Visual renderer altered NPC data contract');return {...legacyNewNodeIds(),mutatedNodeIds:[screen.id,screen.parent.id],screens:[{id:s.id,nodeId:screen.id}],overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,prototypeReactions:LEDGER.checks.prototypeReactions,checks:{...LEDGER.checks.legacyShops[s.id],dataContractUnchanged:true}};"""
code='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore+'\n'+tail;dest=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/('legacy-shop-library.js'if mode=='library'else'legacy-shop-'+sid+'.js'))));dest.write_text(code);subprocess.run(['node',str(HERE/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(dest)],check=True);assert dest.stat().st_size<50000,dest.stat().st_size;print(json.dumps({'mode':mode,'id':spec['id']if spec else None,'file':str(dest),'bytes':dest.stat().st_size,'figmaExecuted':False,'stateWritten':False}))
