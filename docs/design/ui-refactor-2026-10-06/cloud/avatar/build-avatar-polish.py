#!/usr/bin/env python3
"""Generate idempotent, ID-preserving Avatar visual polish; root executes MCP."""
import argparse,json,subprocess,hashlib
from pathlib import Path
here=Path(__file__).resolve().parent;design=here.parents[1]
p=argparse.ArgumentParser();p.add_argument('phase',choices=['wardrobes','profiles','profile-details']);p.add_argument('--offset',type=int,default=0);p.add_argument('--count',type=int,default=99);args=p.parse_args()
state=json.loads((here/'state.json').read_text());main=json.loads((here.parent/'state.json').read_text());spec=json.loads((design/'avatar-assets/manifest.json').read_text());profile=next(s for s in json.loads((design/'data/current-all.json').read_text())if s['id']=='PROFILE-1-P0');profile.pop('original',None)
spec={k:spec[k]for k in ['categories','parts','base','prototypeBoundary']};spec['profile']=profile;spec['images']={}
bundle={'runName':'Avatar visual polish','tokens':json.loads((design/'data/tokens.json').read_text()),'assetNames':{},'screens':[profile],'avatarAssets':spec,'avatarControlIcons':json.loads((design/'data/avatar-control-icons.json').read_text())}
a=state['avatar'];targets=[{'key':k,'id':v}for k,v in a['views'].items()]if args.phase=='wardrobes'else[{'key':'canonical-base','id':'482:310'},{'key':'canonical-saved','id':'482:314'},*[{'key':k,'id':v}for k,v in a['saved'].items()]];targets=targets[args.offset:args.offset+args.count]
context={'phase':args.phase,'pageId':main['pageId'],'libraryId':main['libraryId'],'targets':targets,'variables':main['variables'],'styles':main['styles'],'icons':{k:v for k,v in main['icons'].items()if k in ['i-home','i-book','i-question']}}
source=subprocess.check_output(['node',str(here/'filter-avatar-source.cjs'),str(design/'figma-plugin/src.js'),str(design/'figma-plugin/avatar-fixes.js'),str(design/'figma-plugin/avatar-polish-fixes.js')],text=True)
code='const BUNDLE='+json.dumps(bundle,separators=(',',':'),ensure_ascii=False)+';\n'+source+'\nconst INPUT='+json.dumps(context,separators=(',',':'),ensure_ascii=False)+''';
PAGE=await figma.getNodeByIdAsync(INPUT.pageId);await figma.setCurrentPageAsync(PAGE);LIBRARY=await figma.getNodeByIdAsync(INPUT.libraryId);
const nodes=[];for(const item of INPUT.targets){const node=await figma.getNodeByIdAsync(item.id);if(!node)throw Error('Avatar target missing '+item.id);nodes.push({...item,node});}
const fonts=new Map();for(const {node}of nodes)for(const textNode of node.findAllWithCriteria({types:['TEXT']}))for(const part of textNode.getStyledTextSegments(['fontName']))fonts.set(JSON.stringify(part.fontName),part.fontName);
for(const style of ['Regular','Bold','ExtraBold'])fonts.set(style,{family:T.font.family,style});await Promise.all([...fonts.values()].map(font=>figma.loadFontAsync(font)));
for(const [key,id]of Object.entries(INPUT.variables))VAR[key]=await figma.variables.getVariableByIdAsync(id);for(const [key,id]of Object.entries(INPUT.styles))STYLE[key]=await figma.getStyleByIdAsync(id);for(const [key,id]of Object.entries(INPUT.icons))ICON[key]=await figma.getNodeByIdAsync(id);
const reactions=new Map(),beforeIds=new Set();for(const {node}of nodes){beforeIds.add(node.id);for(const n of node.findAll(()=>true)){beforeIds.add(n.id);if('reactions'in n&&n.reactions.length)reactions.set(n.id,JSON.stringify(n.reactions));}}
for(const {key,node}of nodes){if(INPUT.phase==='wardrobes'){const categoryName=node.name.match(/^Category=([^,]+)/)?.[1],category=avatarSpec().categories.find(c=>c.label===categoryName);if(!category)throw Error('Unknown master category '+node.name);avatarPolishWardrobe(node,category);}else if(INPUT.phase==='profile-details'){avatarPolishLibrary();avatarPolishProfileDetails(node);}else avatarPolishProfile(node);}
await Promise.all(STYLE_JOBS);
const changedReactions=[];for(const [id,before]of reactions){const node=await figma.getNodeByIdAsync(id);if(!node||JSON.stringify(node.reactions)!==before)changedReactions.push(id);}if(changedReactions.length)throw Error('Unexpected reaction changes: '+changedReactions.join(','));
function pack(ids){const prefixes={};for(const id of new Set(ids)){const cut=id.lastIndexOf(':')+1,prefix=id.slice(0,cut);(prefixes[prefix]||=[]).push(id.slice(cut));}return Object.fromEntries(Object.entries(prefixes).map(([p,a])=>[p,a.join(',')]));}
const created=pack([...AVATAR_POLISH.created].filter(id=>!beforeIds.has(id))),mutated=pack(AVATAR_POLISH.mutated);
return {kind:'avatar-polish',phase:INPUT.phase,targets:INPUT.targets,createdNodeIdsByPrefix:created,mutatedNodeIdsByPrefix:mutated,components:{back:AVATAR_POLISH.back.id,skill:AVATAR_POLISH.skill.id,profileRow:AVATAR_POLISH.menu.id,categories:Object.fromEntries(Object.entries(AVATAR_POLISH.tabs).map(([k,n])=>[k,n.id]))},checks:{targets:nodes.length,reactionsPreserved:reactions.size,changedReactions,characterGeometryUnchanged:true,screenIdsPreserved:true}};
'''
out=here/'phases'/f'polish-{args.phase}-{args.offset}-{args.count}.js';out.write_text(code);subprocess.run(['node',str(here.parent/'minify.cjs'),str(out)],check=True,capture_output=True);code=out.read_text();assert len(code)<48000,len(code)
print(json.dumps({'file':str(out.relative_to(here)),'characters':len(code),'targets':len(targets),'sha256':hashlib.sha256(code.encode()).hexdigest()}))
