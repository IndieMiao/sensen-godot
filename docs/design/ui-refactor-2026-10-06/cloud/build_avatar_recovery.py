#!/usr/bin/env python3
"""Compose one recovery fixture from the verified wardrobe master; no new masters."""
from pathlib import Path
import json,subprocess
HERE=Path(__file__).resolve().parent; PLUGIN=HERE.parent/'figma-plugin'
cloud=json.loads((HERE/'state.json').read_text()); avatar=json.loads((HERE/'avatar/state.json').read_text())
bundle=json.JSONDecoder().raw_decode((PLUGIN/'code.js').read_text().split('const BUNDLE = ',1)[1])[0]
spec=next(s for s in json.loads((HERE.parent/'data/current-all.json').read_text())if s['id']=='SAVE-RETRY')
bundle={k:bundle[k]for k in ['tokens','runName']};bundle['screens']=[spec]
select="""const fs=require('fs'),acorn=require('/tmp/gensen-ui-cloud-build/node_modules/acorn');const src=fs.readFileSync(process.argv[1],'utf8').split('figma.showUI(__html__')[0],ast=acorn.parse(src,{ecmaVersion:'latest'});const names=new Set('rgb solid fill border radius bounds frame auto horizontal pad absolute text propKeys inst reviewNote'.split(' '));for(const n of ast.body)if((n.type==='VariableDeclaration'&&n.start<1100)||(n.type==='FunctionDeclaration'&&names.has(n.id.name)))process.stdout.write(src.slice(n.start,n.end)+'\\n');"""
source=subprocess.check_output(['node','-e',select,str(PLUGIN/'src.js')],text=True)
recovery=(PLUGIN/'avatar-recovery-fixes.js').read_text();recovery=recovery[recovery.index('const AVATAR_RECOVERY_KEY='):recovery.index('\nbuildScreen=function')];recovery=recovery.replace('library=async function(){await AVATAR_RECOVERY_BASE.library();await avatarRecoveryVariables();};','')
state={k:cloud[k]for k in ['pageId','libraryId','variables','styles','kit','icons','overlayIndex']};state['variables']={k:v for k,v in state['variables'].items()if k.startswith(('color/','radius/','space/','font/','avatar/recovery/'))};state['kit']={k:v for k,v in state['kit'].items()if k in ['Close','Command/primary','Dismiss','Command/danger-secondary']};state['icons']={}
restore=(HERE/'legacy-adapter-restore.js.txt').read_text().replace('__STATE__',json.dumps(state,separators=(',',':'))).split('const CLOUD_REACTION_BASE=')[0]
restore+='\nconst AVATAR_VIEW={views:{hairhat0:await figma.getNodeByIdAsync('+json.dumps(avatar['avatar']['views']['hairhat0'])+')}};function avatarEnsureLibrary(){if(!AVATAR_VIEW.views.hairhat0)throw Error("Verified Silver draft missing");}'
tail='''
const s=BUNDLE.screens[0],screen=await figma.getNodeByIdAsync('482:320');if(screen.type!=='FRAME'||!screen.name.startsWith('SAVE-RETRY ·'))throw Error('Wrong recovery target');
const fontNames=new Map();for(const root of [screen,AVATAR_VIEW.views.hairhat0,...Object.values(KIT)])for(const n of root.findAllWithCriteria({types:['TEXT']}))for(const seg of n.getStyledTextSegments(['fontName']))fontNames.set(JSON.stringify(seg.fontName),seg.fontName);await Promise.all([...fontNames.values()].map(f=>figma.loadFontAsync(f)));
const masterBefore=JSON.stringify({bounds:[AVATAR_VIEW.views.hairhat0.width,AVATAR_VIEW.views.hairhat0.height],children:AVATAR_VIEW.views.hairhat0.findAll(()=>true).map(n=>n.id)});
const removedNodeIds=screen.findAll(()=>true).map(n=>n.id);for(const c of [...screen.children])c.remove();for(const n of [...screen.parent.children].filter(n=>n.type==='TEXT')){removedNodeIds.push(n.id);n.remove();}
await avatarRecoveryVariables();avatarRecoveryInto(screen,s);reviewNote(screen.parent,s,816);screen.parent.placeholder=false;await Promise.all(STYLE_JOBS);
const masterAfter=JSON.stringify({bounds:[AVATAR_VIEW.views.hairhat0.width,AVATAR_VIEW.views.hairhat0.height],children:AVATAR_VIEW.views.hairhat0.findAll(()=>true).map(n=>n.id)});if(masterBefore!==masterAfter)throw Error('Wardrobe master was mutated');
const panel=screen.children.find(n=>n.name==='Avatar save failure · recoverable draft');panel.y=784-panel.height;
return {...legacyNewNodeIds(),mutatedNodeIds:[screen.id,screen.parent.id],removedNodeIds,variables:LEDGER.variables,checks:{...LEDGER.checks.avatarRecovery,panelBounds:{x:panel.x,y:panel.y,width:panel.width,height:panel.height},masterUnchanged:true},reactions:screen.findAll(n=>n.reactions&&n.reactions.length).map(n=>({id:n.id,name:n.name,reactions:n.reactions})),screenId:screen.id};
'''
dest=HERE/'avatar-recovery.js';dest.write_text('const BUNDLE='+json.dumps(bundle,ensure_ascii=False,separators=(',',':'))+';\n'+source+'\n'+recovery+'\n'+restore+'\n'+tail)
subprocess.run(['node',str(HERE/'minify.cjs'),str(dest)],check=True);subprocess.run(['node',str(HERE/'preflight_script.cjs'),str(dest)],check=True);assert dest.stat().st_size<50000
print(json.dumps({'file':str(dest),'bytes':dest.stat().st_size,'figmaExecuted':False,'stateWritten':False}))
