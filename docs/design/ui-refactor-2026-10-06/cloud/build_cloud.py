#!/usr/bin/env python3
"""Build bounded MCP scripts from the native component source and saved node IDs."""
from pathlib import Path
import json,sys,re,subprocess,os,ast
HERE=Path(__file__).resolve().parent
ROOT=HERE.parent
mode=sys.argv[1]
def selected_indices():
 return [int(x) for x in sys.argv[2].split(',')] if ',' in sys.argv[2] else list(range(int(sys.argv[2]),int(sys.argv[2])+int(sys.argv[3])))
state=json.loads((HERE/'state.json').read_text())
plugin=ROOT/'figma-plugin'
code=(plugin/'code.js').read_text()
bundle=json.JSONDecoder().raw_decode(code.split('const BUNDLE = ',1)[1])[0]
bundle.pop('avatarAssets',None)  # Avatar upload/render has its own bounded cloud adapter.
bundle.pop('avatarControlIcons',None);bundle.pop('cropDexData',None)
surface_file=plugin/'visual-legacy-surfaces.js'
surface_match=re.search(r'LEGACY_SURFACE_IDS=(\[.*?\]);',surface_file.read_text(),re.S) if surface_file.exists() else None
surface_ids=set(ast.literal_eval(surface_match.group(1))) if surface_match else set()
if mode=='screens' and len(selected_indices())==1 and bundle['screens'][selected_indices()[0]]['id'] in surface_ids:
 target_id=bundle['screens'][selected_indices()[0]]['id'];target=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/'screens.js')))
 subprocess.run(['python3',str(HERE/'build_legacy_surfaces.py'),target_id],check=True,env={**os.environ,'GENSEN_CLOUD_OUTPUT':str(target)})
 raise SystemExit(0)
if mode=='screens' and len(selected_indices())==1:
 target_id=bundle['screens'][selected_indices()[0]]['id'];adapter='build_current_containers.py' if target_id in {'BAG-1-P0','GEAR-P0-1','GEAR-P0-2','STORE-1','STORE-2'} else 'build_legacy_shops.py' if target_id in {'NPC-2','NPC-2-2','NPC-3','NPC-3-2'} else None
 if adapter:
  target=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/'screens.js')));subprocess.run(['python3',str(HERE/adapter),'screen',target_id],check=True,env={**os.environ,'GENSEN_CLOUD_OUTPUT':str(target)});raise SystemExit(0)
container_ids={'BAG-2','BAG-2-2','BAG-3','BAG-4','BAG-4-2','BAG-5','BAG-5-2'}
if mode=='container-library' or mode=='screens' and len(selected_indices())==1 and bundle['screens'][selected_indices()[0]]['id'] in container_ids:
 target_id=bundle['screens'][selected_indices()[0]]['id'] if mode=='screens' else None
 target=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/('screens.js' if target_id else 'container-library.js'))))
 command=['python3',str(HERE/'build_legacy_containers.py'),'screen',target_id] if target_id else ['python3',str(HERE/'build_legacy_containers.py'),'library']
 subprocess.run(command,check=True,env={**os.environ,'GENSEN_CLOUD_OUTPUT':str(target)})
 raise SystemExit(0)
for item in bundle['screens']:
 if item['id']=='CTRL-1':item['layout']='states';item['reviewOnly']=True
files=[plugin/f for f in ['src.js','legacy-icon-fixes.js','current-fixes.js','legacy-fixes.js','legacy-scene-fixes.js','legacy-reference-fixes.js','legacy-pin-fixes.js','kitchen-scene-fixes.js','kitchen-selection-fixes.js','action-picker-fixes.js','hud-navigation-fixes.js','legacy-qa-fixes.js','current-qa-fixes.js','camera-highlight-fixes.js','responsive-component-fixes.js','visual-polish-fixes.js','hud-lightweight-fixes.js','visual-fishing-fixes.js','visual-kitchen-fixes.js','kitchen-selection-state-fixes.js','current-kitchen-focus-fixes.js','unknown-requirement-fixes.js','p2p3-visual-fixes.js','current-visual-fixes.js','flow-repair-fixes.js','legacy-npc-flow-fixes.js','free-travel-flow-fixes.js','overlay-cleanup-fixes.js'] if (plugin/f).exists()]
filterMode='library:polish' if mode=='polish-library' else 'library:kitchen-polish' if mode=='kitchen-polish-library' else 'library'
if mode not in ['library','delta','delta2','reference','kitchen-library','hud-navigation','polish-library','kitchen-polish-library']:
 def family(s):
  if s['id'] in ['FARM-1','FISH-1']:return 'legacyWorldTemplate'
  if s['id']=='TUT-3-07B':return 'focusedTutorialKitchen'
  if s.get('sceneControls'):return 'currentSceneInto'
  if s['id'] in ['HUD-1','HUD-1-2']:return 'hudReference'
  if s['id'] in ['CTRL-1','CTRL-1-2']:return 'cameraReference'
  if s['id']=='FISH-2':return 'fishingReference'
  if s['id']=='STATE-ICONS':return 'badgesReference'
  if s['id'] in ['BAR-1','BAR-1-2','BAR-3-2','FARM-7']:return 'legacyQaSceneInto'
  if s['id']=='BAG-1':return 'polishBag'
  if s['id']=='BAR-2':return 'actionPickerInto'
  if s['id'] in ['COOK-2a','COOK-2b','COOK-P0-2']:return 'polishedKitchenScreen'
  if s['id'] in ['FISH-3','FISH-4']:return 'fishingSurface'
  if s['id'] in ['COOK-1','COOK-P0-1','COOK-P1-1','COOK-P1-3','COOK-P1-5']:return 'kitchenSceneEntrance'
  if s.get('layout')=='states' or s.get('reviewOnly'):return 'states'
  if s.get('kitchen') or s['id']=='COOK-3':return 'currentKitchenInto'
  if s['id']=='GUESTBOOK':return 'guestbook'
  if s.get('presentation',{}).get('coverage'):return 'coverage'
  x=s.get('layout');v=s.get('variant','')
  return 'gearScreen' if x=='gear' else 'shop' if v=='shop-with-bag' else 'kitchen' if v in ['cookbook-with-scene-pot','experiment-with-scene-pot'] else 'collection' if v=='collection-grid' else 'inventory' if x=='inventory' else 'profile' if x=='profile' else 'sceneScreen' if x=='scene' else 'general'
 group=[bundle['screens'][i] for i in selected_indices()] if mode=='screens' else []
 filterMode='screens:'+','.join(sorted(set(family(s) for s in group)))+'|'+','.join(s['id'] for s in group)
source=subprocess.check_output(['node',str(HERE/'filter_source.cjs'),filterMode,*map(str,files)],text=True)
if mode=='screens' and any(x['id']=='BAR-2' for x in group):
 action=(plugin/'action-picker-fixes.js').read_text();part=action[action.index(' const head='):action.index(' reviewNote(')]
 source+='\nfunction actionPickerInto(screen,s){'+part+'}\n'
if mode=='screens' and any(x['id'] in ['COOK-2a','COOK-2b','COOK-P0-2'] for x in group):
 kitchen_source=(plugin/'kitchen-selection-fixes.js').read_text()
 block=kitchen_source[kitchen_source.index('kitchen=function(p,s){'):kitchen_source.index('\nbuildScreen=function')]
 block=block[block.index('  const book='):].rsplit('};',1)[0]
 source+='\nfunction kitchenSelectionInto(p,s){'+block+'}\n'
if mode=='screens' and any((x.get('kitchen') or x['id']=='COOK-3') and x['id'] not in ['COOK-2a','COOK-2b','COOK-P0-2','TUT-3-07B'] for x in group):
 current_source=(plugin/'current-fixes.js').read_text()
 block=current_source[current_source.index('kitchen=function(p,s){'):current_source.index('function coverage')]
 block=block[len('kitchen=function(p,s){'):].rsplit('};',1)[0]
 source+='\nfunction currentKitchenInto(p,s){'+block+'currentQaRecipeFacts(p,s);currentQaKitchenFit(p,s);'+'}\n'
if mode=='screens' and any(x['id'] in ['BAR-1','BAR-1-2','BAR-3-2','FARM-7'] for x in group):
 qa_source=(plugin/'legacy-qa-fixes.js').read_text()
 block=qa_source[qa_source.index('sceneScreen=function(p,s){'):qa_source.index('inventory=function(p,s){')]
 block=block[len('sceneScreen=function(p,s){'):block.index(' return LEGACY_QA_BASE.sceneScreen')]
 source+='\nfunction legacyQaSceneInto(p,s){'+block+'}\n'
if mode=='screens' and any(x.get('sceneControls') for x in group):
 current_source=(plugin/'current-fixes.js').read_text()
 block=current_source[current_source.index('sceneScreen=function(p,s){'):current_source.index('const currentGearBase=')]
 block=block[len('sceneScreen=function(p,s){'):].rsplit('};',1)[0]
 block=block.replace('if(!s.sceneControls){currentSceneBase(p,s);return;}','')
 source+='\nfunction currentSceneInto(p,s){'+block+'}\n'
# The standalone plugin uses ordinary auto-layout frames; use the MCP helper here.
source=source.replace("function auto(p,name,w,dir='VERTICAL',gap=6,color) {const n=frame(p,name,w,1,color);n.layoutMode=dir;", "function auto(p,name,w,dir='VERTICAL',gap=6,color) {const n=figma.createAutoLayout(dir);n.name=name;n.resize(w,1);fill(n,color);p.appendChild(n);")
source=source.replace("function progress(text, value) { figma.ui.postMessage({type:'progress', text, value}); }", "function progress(text,value){}")
bundle['sceneHashes'].update(state.get('sceneHashes',{}))
for key,alias in {'map-tile':'map','mine-floor1':'mine','stall':'homestead-stall-v2','avatar':'profile-avatar'}.items():
 if alias in bundle['sceneHashes']:bundle['sceneHashes'][key]=bundle['sceneHashes'][alias]
# Scene aliases reuse the same source image content; no complete UI raster is used.
for key,alias in {'map':'map-tile','mine':'mine-floor1','stall':'homestead-stall-v2','avatar':'profile-avatar'}.items():
 if alias in bundle['sceneHashes']:bundle['sceneHashes'][key]=bundle['sceneHashes'][alias]
bundle['sceneBytes']={}
bundle['flowRepairStates']=[]  # Continuations are created by build_flow_repairs.py, then discovered by wire.
bundle['freeTravelStates']=[]
if mode!='screens' or not any(x['id'] in {'LOCAL-SHOP','LOCAL-TRADE','LOCAL-BOUGHT','LOCAL-CATCH'} for x in group):bundle.pop('freeTravelPassport',None)
bundle['npcFlowStates']=[]  # NPC outcomes use their independent cloud builder.
full=bundle['screens']
if mode in ['library','delta','delta2','reference','kitchen-library','hud-navigation','polish-library','kitchen-polish-library']:
 bundle['screens']=[]
 bundle['iconSvgs']={}
 bundle['iconNodeIds']={}
else:
 selected=[full[i] for i in selected_indices()] if mode=='screens' else full
 selectedIds={s['id'] for s in selected}
 dependencies={'FARM-1'} if 'HUD-1' in selectedIds else set()
 targets=set()
 def collectTargets(x):
  if isinstance(x,dict):
   if x.get('target'):targets.add(x['target'])
   for v in x.values():collectTargets(v)
  elif isinstance(x,list):
   for v in x:collectTargets(v)
 collectTargets(selected)
 source_refs=set(re.findall(r"['\"]([A-Z][A-Z0-9-]+)['\"]",source))
 bundle['screens']=[s if s['id'] in selectedIds or s['id'] in dependencies else {k:s[k] for k in (['id','layout','reviewOnly','stateExamples'] if s['id'] in targets else ['id','layout','reviewOnly']) if k in s} for s in full if s['id'] in selectedIds or s['id'] in dependencies or s['id'] in targets or (s['id'] in source_refs and (s.get('reviewOnly') or s.get('layout')=='states'))]
 scene_keys={'farm'}
 for s in selected:
  key=s.get('sceneName') or s.get('scene') or 'farm';scene_keys.add(re.sub(r'\.[^.]+$','',key.split('/')[-1]))
 for key in bundle['sceneHashes']:
  if repr(key) in source or json.dumps(key) in source:scene_keys.add(key)
 bundle['sceneHashes']={k:v for k,v in bundle['sceneHashes'].items() if k in scene_keys}
 bundle['iconSvgs']={}
 bundle['iconNodeIds']={}
for item in bundle['screens']:
 for k in ['gridCells','quickSlots','sourceGridVariants','sourceQuickVariants','sourceScreenshot','layoutSpecialization','rebuildStatus','sourceKind','figmaSectionName','originalVisibleText','reviewedEvidence']:
  item.pop(k,None)
 if item.get('gridItems'):
  item.pop('bagContents',None)
  item['gridItems']=[{'empty':True} if cell.get('empty') else cell for cell in item['gridItems']]
  if item['id'] in {'COOK-2a','COOK-2b','COOK-P0-2'}:item['gridItems']=[{k:v for k,v in cell.items() if k not in ['familyIcons','new']} for cell in item['gridItems']]
 if item.get('quickItems'):item.pop('quickContents',None)
def compact(x):
 if isinstance(x,dict):return {k:compact(v) for k,v in x.items() if k not in ['sourceSprite','sourceGridVariants','sourceQuickVariants'] and v is not None and v != ''}
 if isinstance(x,list):return [compact(v) for v in x]
 return x
bundle=compact(bundle)
bundle.setdefault('screens',[])
if mode=='screens':
 names=set()
 def titles(x):
  if isinstance(x,dict):
   if x.get('title'):names.add(x['title'].lower())
   if x.get('label'):names.add(x['label'].lower())
   for v in x.values():titles(v)
  elif isinstance(x,list):
   for v in x:titles(v)
 titles(selected)
 bundle['assetNames']={k:v for k,v in bundle.get('assetNames',{}).items() if k in names}
state={k:state[k] for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex'] if k in state}
if mode=='screens':
 allowed=set(bundle.get('assetNames',{}).values())
 def iconKeys(x):
  if isinstance(x,dict):
   if isinstance(x.get('icon'),str):allowed.add(x['icon'])
   for v in x.values():iconKeys(v)
  elif isinstance(x,list):
   for v in x:iconKeys(v)
 iconKeys(bundle['screens'])
 allowed.update(re.findall(r"['\"](i-[A-Za-z0-9_-]+)['\"]",source))
 state['icons']={k:v for k,v in state.get('icons',{}).items() if k in allowed}
 # Existing masters are restored only when this batch can instantiate them.
 # No master is mutated or recreated by this selection.
 selected_ids={s['id'] for s in selected}
 keep_quick=bool({family(s) for s in selected}&{'legacyWorldTemplate','currentSceneInto','legacyQaSceneInto','fishingSurface','actionPickerInto','hudReference','sceneScreen','inventory','gearScreen','polishBag'})
 kitchen_polish_ids={'COOK-2a','COOK-2b','COOK-P0-2','TUT-3-07B'}
 if 'BAG-1' not in selected_ids:
  keep_kitchen=bool(selected_ids&kitchen_polish_ids) or any(s.get('kitchen') for s in selected)
  state['kit']={k:v for k,v in state.get('kit',{}).items() if not k.startswith('Compact/') or keep_kitchen or k.startswith(('Compact/QuickSlot/','Compact/QuickEnd/'))}
  if not keep_kitchen:state['styles']={k:v for k,v in state.get('styles',{}).items() if not k.startswith('compact/')}
  state['variables']={k:v for k,v in state.get('variables',{}).items() if not k.startswith('bag/')}
 state['variables']={k:v for k,v in state.get('variables',{}).items() if not k.startswith('kitchen/') or k.split('/')[1] in selected_ids}
 state['variables']={k:v for k,v in state.get('variables',{}).items() if not k.startswith(('container/','p0bag/'))}
 if not selected_ids&kitchen_polish_ids and all(s.get('kitchen') for s in selected):
  state['kit']={k:v for k,v in state['kit'].items() if not k.startswith('Compact/') or k.startswith(('Compact/Kitchen/Slot/','Compact/QuickSlot/','Compact/QuickEnd/'))}
  state['styles']={k:v for k,v in state['styles'].items() if not k.startswith('compact/')}
 if selected_ids and selected_ids<=kitchen_polish_ids:
  state['styles']={k:v for k,v in state['styles'].items() if not k.startswith(('compact/9/','effect/','title/','quantity/')) and k!='compact/14/Bold'}
  detail_masters={'Sheet','ObjectHeader','NavigationRow','Dismiss','Fact','Cost','HeatRing','ItemRow','NeedTile/met','NeedTile/short','Toast','Close','Tab','StateBadge'}
  state['kit']={k:v for k,v in state['kit'].items() if k.startswith(('Compact/Kitchen/','Compact/QuickSlot/','Compact/QuickEnd/')) or k in {'Compact/HUD','Compact/Command','Compact/Navigation','Compact/Filter/default','Compact/Filter/selected'} or k.startswith('Command/') or k in detail_masters}
 def needed_master(key):
  if key.startswith(('Compact/QuickSlot/','Compact/QuickEnd/')):return keep_quick
  if key.startswith('ReferenceBadge/'):return 'STATE-ICONS' in selected_ids
  if key.startswith('ReferenceEnergy/'):return bool(selected_ids&{'HUD-1','HUD-1-2'})
  if key=='ReferenceToday':return bool(selected_ids&{'HUD-1','HUD-4'})
  if key.startswith('NoteSelection/'):return 'GUESTBOOK' in selected_ids
  if key.startswith('FacilityMarker/'):return bool(selected_ids&{'COOK-1','COOK-P0-1','COOK-P1-1','COOK-P1-3','COOK-P1-5','COOK-P1-4','COOK-EMPTY'})
  return True
 state['kit']={k:v for k,v in state.get('kit',{}).items() if needed_master(k)}
restore='''
const CLOUD_STATE=__STATE__;
PAGE=await figma.getNodeByIdAsync(CLOUD_STATE.pageId);await figma.setCurrentPageAsync(PAGE);
LIBRARY=await figma.getNodeByIdAsync(CLOUD_STATE.libraryId);
await Promise.all(['Regular','Bold','ExtraBold'].map(style=>figma.loadFontAsync({family:T.font.family,style})));
for(const [key,id]of Object.entries(CLOUD_STATE.variables))VAR[key]=await figma.variables.getVariableByIdAsync(id);
for(const [key,id]of Object.entries(CLOUD_STATE.styles))STYLE[key]=await figma.getStyleByIdAsync(id);
for(const [key,id]of Object.entries(CLOUD_STATE.kit||{}))KIT[key]=await figma.getNodeByIdAsync(id);
for(const [key,id]of Object.entries(CLOUD_STATE.icons||{}))ICON[key]=await figma.getNodeByIdAsync(id);
for(const row of PAGE.children.filter(n=>n.type==='SECTION'))for(const section of row.children.filter(n=>n.type==='SECTION'))for(const n of section.children.filter(n=>n.type==='FRAME'))LEDGER.screens[n.name.split(' · ')[0]]=n.id;
Object.assign(LEDGER.components,CLOUD_STATE.components||{});
Object.assign(LEDGER.componentSets,CLOUD_STATE.componentSets||{});
overlayIndex=CLOUD_STATE.overlayIndex||0;
const beforeIds=new Set(PAGE.findAll(()=>true).map(n=>n.id));
'''.replace('__STATE__',json.dumps(state,separators=(',',':')))
if mode=='skeleton':
 # This stage only adds placeholders, so there is no need to ship icons or source code.
 cards=[{'id':s['id'],'title':s['title'],'sourceGroup':s['sourceGroup']} for s in full]
 output='const cards='+json.dumps(cards,ensure_ascii=False)+';const state='+json.dumps(state)+''';
const page=await figma.getNodeByIdAsync(state.pageId);await figma.setCurrentPageAsync(page);
const created=[],screens={},sections={},rows=[];
for(let i=0;i<cards.length;i++){
 let row;
 if(i%8===0){row=figma.createSection();page.appendChild(row);row.name='Review row '+String(i/8+1).padStart(2,'0');row.x=100;row.y=180+Math.floor(i/8)*1070;row.resizeWithoutConstraints(8*412-52,1000);row.fills=[];rows.push(row.id);created.push(row.id);}else row=await figma.getNodeByIdAsync(rows[rows.length-1]);
 const s=figma.createSection();row.appendChild(s);s.name='Review · '+cards[i].id;s.x=(i%8)*412;s.y=0;s.resizeWithoutConstraints(360,1000);s.fills=[];s.placeholder=true;sections[cards[i].id]=s.id;created.push(s.id);
 const f=figma.createFrame();s.appendChild(f);f.name=cards[i].id+' · '+cards[i].title;f.resize(360,800);f.clipsContent=true;f.x=0;f.y=0;screens[cards[i].id]=f.id;created.push(f.id);
}
return {createdNodeIds:created,screens,sections,rows,count:cards.length};'''
else:
 if mode=='screens':source+='\nconst CLOUD_REACTION_BASE=setReaction;setReaction=async function(n,a){const clean={...a};delete clean.overlayRelativePosition;try{await CLOUD_REACTION_BASE(n,clean);}catch(e){const dest=clean.destinationId?await figma.getNodeByIdAsync(clean.destinationId):null;throw Error(n.name+\' (\'+n.type+\') → \'+(dest?.name||clean.type)+\' [\'+clean.navigation+\'] \'+e.message);}};\n'
 output='const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+restore
 if mode=='library':
  output+='''\nawait library();await Promise.all(STYLE_JOBS);
const ids=Object.fromEntries(Object.entries(KIT).map(([k,n])=>[k,n.id]));
return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),kit:ids,icons:Object.fromEntries(Object.entries(ICON).map(([k,n])=>[k,n.id])),components:LEDGER.components,componentSets:LEDGER.componentSets,checks:LEDGER.checks,libraryHeight:LIBRARY.height};'''
 elif mode=='delta':
  current=(plugin/'current-fixes.js').read_text()
  meter=current[current.index('const hudMain=KIT.HUD;'):current.index('const buffRow=horizontal')]
  action=current[current.index('const sceneAction=component'):current.index('const choices=')]
  output+='\n'+meter+'\nlibraryY=7100;\n'+action+'''\nKIT.HUD.primaryAxisSizingMode='AUTO';LIBRARY.resize(1260,Math.max(7300,LIBRARY.height));await Promise.all(STYLE_JOBS);
return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),mutatedNodeIds:[KIT.HUD.id,...KIT.HUD.findAll(()=>true).map(n=>n.id)],kit:{SceneAction:KIT.SceneAction.id},components:{SceneAction:KIT.SceneAction.id}};'''
 elif mode=='delta2':
  legacy=(plugin/'legacy-fixes.js').read_text();summary=legacy[legacy.index("const summary=component"):legacy.index("for(const family of")]
  output+='''\nlibraryY=7280;
// Quick Bar uses the unified Compact masters; this legacy delta now only adds its summary.
'''+summary+'''\nLIBRARY.resize(1260,Math.max(7500,LIBRARY.height));await Promise.all(STYLE_JOBS);return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),mutatedNodeIds:[],kit:{LegacySelectedSummary:KIT.LegacySelectedSummary.id},components:{LegacySelectedSummary:KIT.LegacySelectedSummary.id}};'''
 elif mode=='reference':
  ref=(plugin/'legacy-reference-fixes.js').read_text();body=ref[ref.index(' const progress=[];'):ref.index('function referenceBoard')];body=body.rsplit('};',1)[0]
  output+='\nlibraryY=7600;\n'+body+'''\nawait Promise.all(STYLE_JOBS);return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),kit:Object.fromEntries(Object.entries(KIT).filter(([key])=>key.startsWith('Reference')).map(([key,n])=>[key,n.id])),components:LEDGER.components,componentSets:LEDGER.componentSets};'''
 elif mode=='kitchen-library':
  patch=(plugin/'kitchen-scene-fixes.js').read_text();body=patch[patch.index('  const variants=[];'):patch.index('function kitchenStoveDescriptors')];body=body.rsplit('};',1)[0]
  output+='\nlibraryY=LIBRARY.height+120;\n'+body+'''\nawait Promise.all(STYLE_JOBS);return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),kit:Object.fromEntries(Object.entries(KIT).filter(([key])=>key.startsWith('FacilityMarker')).map(([key,n])=>[key,n.id])),components:LEDGER.components,componentSets:LEDGER.componentSets};'''
 elif mode=='kitchen-polish-library':
  output+='''\nlibraryY=LIBRARY.height+80;await kitchenPolishLibrary();await kitchenSelectionLibrary();await Promise.all(STYLE_JOBS);
return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),kit:Object.fromEntries(Object.entries(KIT).filter(([key])=>key.startsWith('Compact/Kitchen/')).map(([key,n])=>[key,n.id])),variables:LEDGER.variables,components:LEDGER.components,componentSets:LEDGER.componentSets,mutatedNodeIds:KIT['Compact/Kitchen/Slot/empty']?[KIT['Compact/Kitchen/Slot/empty'].id,...KIT['Compact/Kitchen/Slot/empty'].findAll(()=>true).map(n=>n.id)]:[],libraryHeight:LIBRARY.height};'''
 elif mode=='polish-library':
  output+='''\nlibraryY=LIBRARY.height+80;await polishLibrary();await Promise.all(STYLE_JOBS);
return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)).map(n=>n.id),kit:Object.fromEntries(Object.entries(KIT).filter(([key])=>key.startsWith('Compact/')).map(([key,n])=>[key,n.id])),styles:Object.fromEntries(Object.entries(STYLE).filter(([key])=>key.startsWith('compact/')).map(([key,n])=>[key,n.id])),components:LEDGER.components,componentSets:LEDGER.componentSets,variables:LEDGER.variables,libraryHeight:LIBRARY.height};'''
 elif mode=='hud-navigation':
  output+='''\nconst delta=await ensureHudNavigation(KIT.HUD);await Promise.all(STYLE_JOBS);
const touched=[];
for(const row of PAGE.children.filter(n=>n.type==='SECTION'))for(const section of row.children.filter(n=>n.type==='SECTION'))for(const screen of section.children.filter(n=>n.type==='FRAME')){
 const location=screen.children.find(n=>n.name==='HUD touch · Location');if(!location)continue;location.x=112;location.resize(232,44);touched.push(location.id);
 if(!screen.children.some(n=>n.name==='HUD touch · Today')){const today=frame(screen,'HUD touch · Today',88,44);today.x=16;today.y=70;if(screen.id!==LEDGER.screens['TODAY-1'])await today.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:LEDGER.screens['TODAY-1'],navigation:'NAVIGATE',transition:null}]}]);}
 const buff=screen.children.find(n=>n.name.startsWith('Buff touch ·'));if(buff){buff.y=118;touched.push(buff.id);}
}
return {createdNodeIds:PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)&&!n.id.startsWith('I')).map(n=>n.id),mutatedNodeIds:[...delta.mutatedNodeIds,...touched],hudHeight:KIT.HUD.height,touchHeight:44};'''
 elif mode=='screens':
  start=selected_indices()[0];count=len(selected_indices());rebuild=len(sys.argv)>4 and sys.argv[4]=='rebuild'
  # The last declaration wins over standalone constructors: populate the pre-created targets.
  match=re.search(r'function buildScreen\(s,index\)\{(.*?)\n',(plugin/'src.js').read_text())
  if not match:raise RuntimeError('Missing screen constructor')
  body=match.group(0)
  sceneidx=body.index('scene(screen,s);')
  body="function buildScreen(s,index){const screen=CLOUD_NODES[s.id];const box=screen.parent;"+body[sceneidx:]
  body=body.replace('scene(screen,s);',"if(!['FISH-3','FISH-4'].includes(s.id))scene(screen,s);",1)
  def renderer(s):
   if s['id'] in ['FARM-1','FISH-1']:return 'hud(screen,s);legacyWorldTemplate(screen,s,legacyWorldAction(s));'
   if s['id']=='TUT-3-07B':return 'polishedKitchenHud(screen,s);focusedTutorialKitchen(screen,s);'
   if s.get('sceneControls'):return 'hud(screen,s);currentSceneInto(screen,s);'
   if s['id'] in ['HUD-1','HUD-1-2']:return 'hudReference(screen,s);'
   if s['id'] in ['CTRL-1','CTRL-1-2']:return 'cameraReference(screen,s);'
   if s['id']=='FISH-2':return 'fishingReference(screen,s);'
   if s['id']=='STATE-ICONS':return 'badgesReference(screen,s);'
   if s['id'] in ['BAR-1','BAR-1-2','BAR-3-2','FARM-7']:return 'hud(screen,s);legacyQaSceneInto(screen,s);'
   if s['id']=='BAG-1':return 'polishHud(screen,s);polishBag(screen,s);'
   if s['id']=='BAR-2':return 'hud(screen,s);actionPickerInto(screen,s);'
   if s['id'] in ['COOK-2a','COOK-2b','COOK-P0-2']:return 'polishedKitchenHud(screen,s);polishedKitchenScreen(screen,s);'
   if s['id'] in ['FISH-3','FISH-4']:return 'fishingSourceCamera(screen,s);hud(screen,s);fishingCreel(screen,s);fishingSmallAction(screen,s);'+('fishingCatchCard(screen,s);' if s['id']=='FISH-3' else 'fishingRecoveryLinks(screen,s);')
   if s['id'] in ['BAR-3','HUD-3']:return 'hud(screen,s);qaEnergy(screen,s);'
   if s['id']=='HUD-4':return 'hud(screen,s);qaToday(screen,s);'
   if s['id'] in ['TODAY-1','TODAY-2']:return 'hud(screen,s);currentTodayCompact(screen,s);'
   if s['id'] in ['COOK-1','COOK-P0-1','COOK-P1-1','COOK-P1-3','COOK-P1-5']:return 'hud(screen,s);kitchenSceneEntrance(screen,s);'
   if s.get('layout')=='states' or s.get('reviewOnly'):return 'states(screen,s);'
   x=s.get('layout');v=s.get('variant','')
   if s.get('kitchen') or s['id']=='COOK-3':return 'hud(screen,s);currentKitchenInto(screen,s);'
   if s['id']=='GUESTBOOK':return 'hud(screen,s);guestbook(screen,s);'
   if s.get('presentation',{}).get('coverage'):return 'hud(screen,s);coverage(screen,s);'
   call='gearScreen' if x=='gear' else 'shop' if v=='shop-with-bag' else 'kitchen' if v in ['cookbook-with-scene-pot','experiment-with-scene-pot'] else 'collection' if v=='collection-grid' else 'inventory' if x=='inventory' else 'profile' if x=='profile' else 'sceneScreen' if x=='scene' else 'general'
   return 'hud(screen,s);'+call+'(screen,s'+(',true' if v=='experiment-with-scene-pot' else '')+');'
  clauses=''.join(('if' if i==0 else 'else if')+'(s.id==='+json.dumps(s['id'])+'){'+renderer(s)+'}' for i,s in enumerate(selected))
  begin=body.index('const reference=');end=body.index('reviewNote(',begin)
  body=body[:begin]+clauses+body[end:]
  body=body.replace('return screen;',"const ownClose=['FISH-3','FISH-4','BAR-2','COOK-2a','COOK-2b','COOK-P0-2','COOK-1','COOK-P0-1','COOK-P1-1','COOK-P1-3','COOK-P1-5'].includes(s.id);const modal=!ownClose&&(s.presentation?.close??(!s.reviewOnly&&s.layout!=='states'&&s.layout!=='scene'&&!(s.sourceHtml&&['inventory','gear'].includes(s.layout))));if(modal){const sheet=screen.children.find(n=>n.type==='INSTANCE'&&n.mainComponent?.id===KIT.Sheet.id);const y=Math.max(132,(sheet?.y||248)-50);const close=inst(screen,'Close');absolute(close,300,y);close.name='Close · 44 px';PENDING_LINKS.push({node:close,ownerId:s.id,action:{label:'Close',kind:'dismiss'}});}box.placeholder=false;return screen;")
  p2p3_match=re.search(r'P2P3_VISUAL_IDS = new Set\((\[.*?\])\)',(plugin/'p2p3-visual-fixes.js').read_text()) if (plugin/'p2p3-visual-fixes.js').exists() else None
  p2p3_ids=set(json.loads(p2p3_match.group(1))) if p2p3_match else set()
  if any(s['id'] in p2p3_ids and s.get('layout')!='scene' and not s.get('kitchen') for s in selected):body=body.replace('box.placeholder=false;',"const refined=p2p3VisualRefine(screen,s);if(refined.applied){LEDGER.checks.p2p3CompactSheets=LEDGER.checks.p2p3CompactSheets||{};LEDGER.checks.p2p3CompactSheets[s.id]=refined;}box.placeholder=false;")
  current_match=re.search(r'CURRENT_VISUAL_IDS=new Set\((\[.*?\])\)',(plugin/'current-visual-fixes.js').read_text())
  current_ids=set(json.loads(current_match.group(1))) if current_match else set()
  if any(s['id'] in current_ids for s in selected):body=body.replace('box.placeholder=false;',"const currentRefined=currentVisualRefine(screen,s);if(currentRefined.applied){LEDGER.checks.currentCompactSheets=LEDGER.checks.currentCompactSheets||{};LEDGER.checks.currentCompactSheets[s.id]=currentRefined;}box.placeholder=false;")
  output+='\nconst CLOUD_NODES={};\n'+body+f'''\nconst selectedIds={json.dumps([s['id'] for s in selected])};const selection=BUNDLE.screens.filter(s=>selectedIds.includes(s.id));
for(const s of selection){{const n=await figma.getNodeByIdAsync(LEDGER.screens[s.id]);if(n.children.length){{if(!{str(rebuild).lower()})throw Error('Screen already composed: '+s.id);for(const child of [...n.children])child.remove();for(const note of [...n.parent.children].filter(c=>c.type==='TEXT'))note.remove();}}CLOUD_NODES[s.id]=n;}}
for(const [index,s]of selection.entries())buildScreen(s,{start}+index);
const mutatedMasterIds=[];
if(selection.some(s=>s.id==='GUESTBOOK')){{const labels=['Nice farm!','Thanks for the fish!','Come visit mine!'];for(let j=0;j<3;j++){{const main=KIT['NoteSelection/'+j];for(let i=0;i<3;i++){{if(i===j)continue;const option=main.children.find(n=>n.name==='Option '+i);PENDING_LINKS.push({{node:option,choiceIndex:i,choiceOwner:j}});mutatedMasterIds.push(option.id);}}const post=main.children.find(n=>n.type==='INSTANCE'&&n.mainComponent?.id===KIT['Command/primary'].id);PENDING_LINKS.push({{node:post,ownerId:'GUESTBOOK',action:{{kind:'commit',label:'Post note',context:{{operation:'post-note',text:labels[j],resultOnly:true}},feedback:'Note posted.'}}}});mutatedMasterIds.push(post.id);}}}}
await wire();await Promise.all(STYLE_JOBS);
const created=PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id));
const inherited={{}};for(const n of created){{if(n.id.startsWith('I')){{const at=n.id.indexOf(';'),prefix=n.id.slice(0,at),suffix=n.id.slice(at+1);(inherited[prefix]??=[]).push(suffix);}}}}
return {{createdNodeIds:created.filter(n=>!n.id.startsWith('I')).map(n=>n.id),inheritedNodeIdGroups:Object.fromEntries(Object.entries(inherited).map(([prefix,suffixes])=>[prefix,suffixes.join('|')])),mutatedNodeIds:[...selection.flatMap(s=>[CLOUD_NODES[s.id].id,CLOUD_NODES[s.id].parent.id]),...mutatedMasterIds],screens:selection.map(s=>({{id:s.id,nodeId:CLOUD_NODES[s.id].id}})),overlayIndex,warnings:LEDGER.warnings,overlays:LEDGER.overlays,prototypeReactions:LEDGER.checks.prototypeReactions,sourceReferences:LEDGER.sourceReferences}};'''
 else:raise RuntimeError('Unknown mode')
print(json.dumps({'source':len(source),'payload':len(json.dumps(bundle)),'state':len(json.dumps(state)),'screens':[(s['id'],len(json.dumps(s))) for s in bundle['screens'] if len(json.dumps(s))>1000]}))
destination=Path(os.environ.get('GENSEN_CLOUD_OUTPUT',str(HERE/(mode+'.js'))))
destination.parent.mkdir(parents=True,exist_ok=True)
destination.write_text(output)
subprocess.run(['node',str(HERE/'minify.cjs'),str(destination)],check=True)
