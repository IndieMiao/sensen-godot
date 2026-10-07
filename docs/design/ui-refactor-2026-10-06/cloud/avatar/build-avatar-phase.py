#!/usr/bin/env python3
"""Emit one bounded, reviewable Avatar MCP script; never execute Figma or advance state."""
from pathlib import Path
import argparse,json,subprocess,hashlib,fcntl
HERE=Path(__file__).resolve().parent
DESIGN=HERE.parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('phase',choices=['thumbnails','variants','group','saved','continuations','wire','compose','inspect'])
parser.add_argument('selection',nargs='?',default='all',help='Category for variants; base/part ID for results; PROFILE-1-P0/KEEP-P0-1/KEEP-P0-2 for compose')
parser.add_argument('--offset',type=int,default=0)
parser.add_argument('--count',type=int,default=3)
parser.add_argument('--rebuild',action='store_true',help='Replace only the exact owned destination frame contents during compose')
args=parser.parse_args();state=json.loads((HERE/'state.json').read_text());main=json.loads((HERE.parent/'state.json').read_text());spec=json.loads((DESIGN/'avatar-assets/figma-payload.json').read_text())
assert main['pageId']=='481:53'==state['pageId']
profile=spec['profile'];all_result_ids=['base',*[p['id']for p in spec['parts']],'defaults']
parts_by_category={c['label']:[*(['none-'+c['slot']]if c['optional']else[]),*[p['id']for p in spec['parts']if p['slot']==c['slot']]]for c in spec['categories']}
selected=[];required_images=set();restored=dict(state.get('avatar',{}));restored['links']=[];restored['images']={};pending=[]
if args.phase=='thumbnails':
 selected=[p['id']for p in spec['parts']];required_images={f'thumbs/{x}'for x in selected}
elif args.phase=='variants':
 source=['defaults']if args.selection=='defaults' else parts_by_category.get(args.selection)
 if source is None:raise SystemExit('Select Hair, Outfits, Shoes, Bags, Glasses, or defaults')
 selected=source[args.offset:args.offset+args.count];required_images={'background',*[f'previews/{"base"if x.startswith("none-")else x}'for x in selected]}
elif args.phase in ['saved','continuations']:
 source=all_result_ids if args.selection=='all'else args.selection.split(',');selected=source[args.offset:args.offset+args.count]
 if args.phase=='saved':required_images={f'previews/{x}'for x in selected}
elif args.phase=='wire':
 entries=[('avatar',x)for x in state.get('avatar',{}).get('links',[])if not x.get('wired')]+[('profile',x)for x in state.get('pendingLinks',[])if not x.get('wired')]
 chosen=entries[args.offset:args.offset+args.count];restored['links']=[x for kind,x in chosen if kind=='avatar'];pending=[x for kind,x in chosen if kind=='profile'];selected=[x['nodeId']for _,x in chosen]
elif args.phase=='compose':
 known={'PROFILE-1-P0':'482:310','KEEP-P0-1':'482:312','KEEP-P0-2':'482:314'}
 if args.selection not in known:raise SystemExit('Compose exactly one known canonical Avatar/Profile frame')
 assert main['screens'][args.selection]==known[args.selection]
 selected=[args.selection]
 if args.selection!='KEEP-P0-1':required_images={'previews/base'if args.selection=='PROFILE-1-P0'else'previews/hairhat0'}
avatar_state=state.get('avatar',{})
if args.phase=='variants' and (not all(k in avatar_state.get('thumbs',{}) for k in [*[p['id']for p in spec['parts']],'__none']) or len(avatar_state.get('tiles',{}))!=2):raise SystemExit('Run and merge thumbnails + shared tile first')
if args.phase=='group' and len(avatar_state.get('views',{}))!=30:raise SystemExit('Create all 30 variants before grouping')
if args.phase in ['saved','continuations','wire','compose'] and (len(avatar_state.get('views',{}))!=30 or not avatar_state.get('variantSet')):raise SystemExit('Finish and group all 30 variants first')
if args.phase=='continuations' and any(k not in avatar_state.get('saved',{})for k in selected):raise SystemExit('Build each corresponding Profile result before its continuation')
if args.phase in ['wire','compose'] and (len(avatar_state.get('saved',{}))!=29 or len(avatar_state.get('continuations',{}))!=29):raise SystemExit('Finish all Profile results and edit continuations before wiring/composing')
if args.phase=='compose' and any(not edge.get('wired')for edge in avatar_state.get('links',[])):raise SystemExit('Wire the Avatar variants before composing canonical frames')
upload_meta={i['key']:i for i in json.loads((HERE/'upload-manifest.json').read_text())['images']}
for key in sorted(required_images):
 if key not in state.get('images',{}):raise SystemExit('Upload/merge real image first: '+key)
 if state['images'][key]['uploadSHA']!=upload_meta[key]['uploadSHA']:raise SystemExit('Replace obsolete display copy first: '+key)
 if state['images'][key]['sourceSHA']!=json.loads((DESIGN/'avatar-assets/manifest.json').read_text())['images'][key]['sha256']:raise SystemExit('Source image changed; upload again: '+key)
spec['images']={key:{'hash':state['images'][key]['hash']}for key in required_images}
# Keep all exact destination maps, but don't repeat cached image data or every reaction in each call.
for key in ['views','saved','continuations','thumbs','tiles']:restored.setdefault(key,{})
core_keys=['Command/primary','Command/secondary','Command/destructive','Command/danger-secondary','Command/blocked','NavigationRow','Dismiss','ObjectHeader','Fact','Cost','ItemRow','NeedTile/met','NeedTile/short','Tab','StateBadge','Sheet','Close']
cloud={'pageId':main['pageId'],'libraryId':main['libraryId'],'variables':main['variables'],'styles':main['styles'],'kit':{k:v for k,v in main['kit'].items()if k in core_keys},'icons':{k:v for k,v in main['icons'].items()if k in ['i-home','i-book','i-question','i-coin','i-energy']}}
external_targets={}
def targets(x):
 if isinstance(x,dict):
  if x.get('target')and x['target']in main['screens']:external_targets[x['target']]=main['screens'][x['target']]
  for v in x.values():targets(v)
 elif isinstance(x,list):
  for v in x:targets(v)
targets(profile);targets(pending)
profile_source={'id':profile['id'],'title':profile['title'],**profile}
bundle={'runName':'Avatar original-layout restoration · 2026-10-06','tokens':json.loads((DESIGN/'data/tokens.json').read_text()),'assetNames':{},'screens':[profile_source],'avatarAssets':spec}
source=subprocess.check_output(['node',str(HERE/'filter-avatar-source.cjs'),str(DESIGN/'figma-plugin/src.js'),str(DESIGN/'figma-plugin/avatar-fixes.js')],text=True)
script_key=f'{args.phase}-{args.selection}-{args.offset}-{args.count}'
context={'cloud':cloud,'avatar':restored,'pending':pending,'externalTargets':external_targets,'detailFrameId':state.get('profileDetailsFrameId'),'selected':selected,'phase':args.phase,'scriptKey':script_key,'rebuild':args.rebuild,'canonical':{k:main['screens'][k]for k in ['PROFILE-1-P0','KEEP-P0-1','KEEP-P0-2']}}
pre='const BUNDLE='+json.dumps(bundle,separators=(',',':'),ensure_ascii=False)+';\n'+source+'\nconst INPUT='+json.dumps(context,separators=(',',':'),ensure_ascii=False)+''';
PAGE=await figma.getNodeByIdAsync(INPUT.cloud.pageId);if(!PAGE||PAGE.type!=='PAGE')throw Error('Wrong Avatar page');await figma.setCurrentPageAsync(PAGE);LIBRARY=await figma.getNodeByIdAsync(INPUT.cloud.libraryId);if(!LIBRARY||LIBRARY.type!=='FRAME')throw Error('Shared library missing');
await Promise.all(['Regular','Bold','ExtraBold'].map(style=>figma.loadFontAsync({family:T.font.family,style})));
for(const [k,id]of Object.entries(INPUT.cloud.variables))VAR[k]=await figma.variables.getVariableByIdAsync(id);
for(const [k,id]of Object.entries(INPUT.cloud.styles))STYLE[k]=await figma.getStyleByIdAsync(id);
for(const [k,id]of Object.entries(INPUT.cloud.kit))KIT[k]=await figma.getNodeByIdAsync(id);
for(const [k,id]of Object.entries(INPUT.cloud.icons))ICON[k]=await figma.getNodeByIdAsync(id);
await avatarRestore(INPUT.avatar);const beforeAvatar=avatarLedger(),beforeIds=new Set(PAGE.findAll(()=>true).map(n=>n.id)),removed=[],mutated=[],composed={},pendingUpdates=[];let detailsId=INPUT.detailFrameId;const parentBefore={page:PAGE.children.map(n=>n.id).join(','),library:LIBRARY.children.map(n=>n.id).join(','),width:LIBRARY.width,height:LIBRARY.height},viewBefore=new Map(Object.values(AVATAR_VIEW.views).map(n=>[n.id,JSON.stringify([n.parent?.id,n.x,n.y,n.width,n.height])])),reactionBefore=new Map(AVATAR_VIEW.links.map(e=>[e.node.id,JSON.stringify(e.node.reactions)]));
function nodeIds(node){return [node.id,...('findAll'in node?node.findAll(()=>true).map(n=>n.id):[])]}
'''
actions={
 'thumbnails':'avatarCreateThumbnails(INPUT.selected);avatarMakeTileLibrary();',
 'variants':'avatarCreateVariants(INPUT.selected);',
 'group':'avatarGroupVariants();',
 'saved':'avatarCreateSaved(INPUT.selected);',
 'continuations':'avatarCreateContinuations(INPUT.selected);',
 'wire':'''avatarWire();
async function profileDetails(detail){if(detailsId){const old=await figma.getNodeByIdAsync(detailsId);if(old)return old;}const modal=frame(PAGE,'Avatar · preserved Profile details',360,620,'surface');modal.x=19200;modal.y=0;radius(modal,'sheet');modal.clipsContent=true;const body=scroll(modal,'Profile information',16,16,328,520);heading(body.content,{title:detail.title||'Profile',effect:''});for(const line of detail.disclosure||[])text(body.content,line,328);const close=inst(modal,'Dismiss',{Label:'Close'},328);absolute(close,16,560);await close.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CLOSE'}]}]);detailsId=modal.id;return modal;}
for(const edge of INPUT.pending){const node=await figma.getNodeByIdAsync(edge.nodeId);if(!node)throw Error('Profile link source missing: '+edge.nodeId);let action;if(edge.detail){const modal=await profileDetails(edge.detail);action={type:'NODE',destinationId:modal.id,navigation:'OVERLAY',transition:null};}else if(edge.action?.target&&INPUT.externalTargets[edge.action.target])action={type:'NODE',destinationId:INPUT.externalTargets[edge.action.target],navigation:'NAVIGATE',transition:null,resetInteractiveComponents:false};else if(edge.action?.kind==='dismiss')action={type:'BACK'};else throw Error('No legitimate Avatar/Profile destination for '+node.name);await node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[action]}]);mutated.push(node.id);pendingUpdates.push({...edge,wired:true});}
''',
 'compose':'''const id=INPUT.selected[0],screen=await figma.getNodeByIdAsync(INPUT.canonical[id]);if(!screen||screen.type!=='FRAME'||screen.width!==360||screen.height!==800||!screen.name.startsWith(id+' ·'))throw Error('Canonical Avatar frame identity mismatch');let owner=screen;while(owner.parent&&owner.type!=='PAGE')owner=owner.parent;if(owner.id!==PAGE.id)throw Error('Refusing to replace outside the review page');if(screen.children.length&&!INPUT.rebuild)throw Error('Frame has content; inspect and pass --rebuild for this exact frame');for(const child of [...screen.children]){removed.push(...nodeIds(child));child.remove();}mutated.push(screen.id);if(id==='PROFILE-1-P0'){avatarSavedComposition(screen,'base');avatarWire();}else avatarScreen(screen,{...INPUT, id});composed[id]=screen.id;
''',
 'inspect':'',
}
post='''
await Promise.all(STYLE_JOBS);
if(PAGE.children.map(n=>n.id).join(',')!==parentBefore.page)mutated.push(PAGE.id);if(LIBRARY.children.map(n=>n.id).join(',')!==parentBefore.library||LIBRARY.width!==parentBefore.width||LIBRARY.height!==parentBefore.height)mutated.push(LIBRARY.id);for(const node of Object.values(AVATAR_VIEW.views))if(viewBefore.has(node.id)&&viewBefore.get(node.id)!==JSON.stringify([node.parent?.id,node.x,node.y,node.width,node.height]))mutated.push(node.id);for(const edge of AVATAR_VIEW.links)if(reactionBefore.has(edge.node.id)&&reactionBefore.get(edge.node.id)!==JSON.stringify(edge.node.reactions))mutated.push(edge.node.id);
function serializePending(p){const {node,itemContext,...rest}=p;return {nodeId:node.id,...rest,...(itemContext?{itemContext}:{}),wired:false};}
const generatedPending=PENDING_LINKS.map(serializePending);const afterAvatar=avatarLedger(),delta={};for(const k of ['views','saved','continuations','thumbs','tiles','images']){const before=beforeAvatar[k]||{},after=afterAvatar[k]||{};const changed=Object.fromEntries(Object.entries(after).filter(([key,value])=>before[key]!==value));if(Object.keys(changed).length)delta[k]=changed;}if(afterAvatar.variantSet&&afterAvatar.variantSet!==beforeAvatar.variantSet)delta.variantSet=afterAvatar.variantSet;
const oldLinks=new Map((beforeAvatar.links||[]).map(e=>[e.nodeId,JSON.stringify(e)])),changedLinks=afterAvatar.links.filter(e=>oldLinks.get(e.nodeId)!==JSON.stringify(e));delta.linkRows=changedLinks.map(e=>[e.nodeId,e.partId?'part':e.category?'category':e.savedId?'saved':e.continuationId?'continuation':e.navigation==='BACK'?'back':'node',e.partId||e.category||e.savedId||e.continuationId||e.destinationId||'',e.navigation,Boolean(e.wired)]);
function pack(values){const regular=[],inherited={};for(const id of [...new Set(values)]){if(!id.startsWith('I')||!id.includes(';'))regular.push(id);else{const cut=id.lastIndexOf(';')+1,prefix=id.slice(0,cut),suffix=id.slice(cut);(inherited[prefix]||=[]).push(suffix);}}return {regular,inherited:Object.fromEntries(Object.entries(inherited).map(([p,a])=>[p,a.join(',')]))};}
const fresh=PAGE.findAll(()=>true).filter(n=>!beforeIds.has(n.id)),createdIds=pack(fresh.map(n=>n.id)),mutatedIds=pack(mutated),removedIds=pack(removed);
const result={kind:'avatar-phase',phase:INPUT.phase,scriptKey:INPUT.scriptKey,createdNodeIds:createdIds.regular,createdInheritedNodeIds:createdIds.inherited,mutatedNodeIds:mutatedIds.regular,mutatedInheritedNodeIds:mutatedIds.inherited,removedNodeIds:removedIds.regular,removedInheritedNodeIds:removedIds.inherited,avatarDelta:delta,pendingLinks:[...generatedPending,...pendingUpdates],profileDetailsFrameId:detailsId||null,componentSets:LEDGER.componentSets,overlays:LEDGER.overlays,composed,checks:{phase:INPUT.phase,selected:INPUT.selected,views:Object.keys(AVATAR_VIEW.views).length,saved:Object.keys(AVATAR_VIEW.saved).length,continuations:Object.keys(AVATAR_VIEW.continuations).length,createdCount:fresh.length,removedCount:removed.length,allImagesActual:true}};
return result;
'''
code=pre+actions[args.phase]+post
out=HERE/'phases'/f'{script_key}.js';out.parent.mkdir(exist_ok=True);out.write_text(code)
subprocess.run(['node',str(HERE.parent/'minify.cjs'),str(out)],check=True,capture_output=True)
code=out.read_text();assert len(code)<48000,f'Split the phase further ({len(code)} characters)'
entry={'file':str(out.relative_to(HERE)),'phase':args.phase,'selected':selected,'characters':len(code),'sha256':hashlib.sha256(code.encode()).hexdigest(),'stateFingerprint':hashlib.sha256((HERE/'state.json').read_bytes()).hexdigest(),'mcpExecuted':False}
# Preserve successful receipts that may have arrived while this script was prepared.
with (HERE/'state.lock').open('a') as lock:
 fcntl.flock(lock,fcntl.LOCK_EX)
 latest=json.loads((HERE/'state.json').read_text())
 latest.setdefault('scripts',{})[script_key]=entry
 temp=HERE/'state.json.tmp';temp.write_text(json.dumps(latest,ensure_ascii=False,indent=2)+'\n');temp.replace(HERE/'state.json')
print(json.dumps(entry,ensure_ascii=False))
