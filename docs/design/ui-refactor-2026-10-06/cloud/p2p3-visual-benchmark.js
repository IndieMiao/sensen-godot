const INPUT={"pageId":"481:53","surfaceVariable":"VariableID:481:4","surface":"#FBF8F1","targets":[{"nodeId":"482:494","data":{"id":"GIFT-SENT","layout":"sheet"}},{"nodeId":"482:473","data":{"id":"SOC-2","layout":"sheet"}},{"nodeId":"482:524","data":{"id":"BUFF-HANDS","layout":"sheet"}},{"nodeId":"482:567","data":{"id":"COMBAT-HEAL","layout":"sheet"}},{"nodeId":"482:446","data":{"id":"TRAVEL-GUIDE","layout":"map"}},{"nodeId":"482:501","data":{"id":"SOC-6","layout":"sheet"}},{"nodeId":"482:599","data":{"id":"RES-HANA","layout":"profile"}}]};
/* P2/P3 visual QA: let short sheets fit their content and keep controls nearby.
 * Native scene art, typography masters, commands and reactions are preserved.
 * Excludes Avatar, cooking composition, inventory, Gear and nonmodal scene HUDs. */
const P2P3_VISUAL_IDS = new Set(["TRAVEL-GUIDE","TRAVEL-CANCEL","TRAVEL-REFUNDED","DAYPASS","DAYPASS-EXPIRED","PERMIT-1","PERMIT-DONE","TICKET-1","SECOND-HOME","SECOND-HOME-DONE","SOC-1","SOC-1-GATE","SOC-1-CONFIRM","SOC-2","SOC-2-INBOX","SOC-2-ARRIVE","SOC-2-ERROR","SOC-3","HELPER-INBOX","HELPER-SUMMARY","HELPER-ONSITE","HELPER-BUDGET","SOC-5","GIFT-SENT","GIFT-CLAIM","GIFT-DETAIL","SOC-6","GUESTBOOK","TOGETHER","TOGETHER-PROGRESS","TOGETHER-DONE","TRADER","BUFF-FARM","BUFF-FISH","BUFF-HANDS","BUFF-TRAVEL","BUFF-CREEL","BUFF-REPLACE","BUFF-ACTIVE","BUFF-CASTS","BUFF-LAST","BUFF-TIMEOUT","BUFF-RATIONS-USE","BUFF-CREEL-END","HOME-LV4","HOME-LV5","HOME-LV6","HOME-LV7","HOME-LV8","HOME-LV9","HOME-LV10","MINE-3","COMBAT-1","COMBAT-LOOT","COMBAT-HEAL","MINE-4","MINE-5","MINE-KO","RESIDENT-TALK","RESIDENT-CHAT","RESIDENT-MEAL","RESIDENT-MEAL-DONE","RESIDENT-TEACH","RES-PIP","RES-GRANNY","RES-MIRA","RES-KAI","RES-RAFA","RES-IVO","RES-HANA","RES-SAM","RES-LENA","RES-TOMO","RES-THEO","RES-NADIA","DEX-MILESTONE"]);
function p2p3Property(node,name){if(node.type!=='INSTANCE')return null;const key=Object.keys(node.componentProperties||{}).find(k=>k.split('#')[0]===name);return key?node.componentProperties[key].value:null;}
function p2p3VisualRefine(screen,s){
 if(!P2P3_VISUAL_IDS.has(s.id)||s.kitchen||s.layout==='scene')return {id:s.id,applied:false,reason:'outside generic sheet scope'};
 const viewport=screen.children.find(n=>['Main content','Profile content'].includes(n.name)),footer=screen.children.find(n=>n.name==='Fixed decision area'),panel=screen.children.find(n=>n.type==='INSTANCE'&&n.name==='Sheet');
 const body=viewport?.children.find(n=>n.name==='Scrollable content');
 if(!viewport||!footer||!panel||!body)return {id:s.id,applied:false,reason:'no generic sheet structure'};
 const before={panelTop:panel.y,viewportHeight:viewport.height,bodyHeight:body.height},changed=new Set();
 if(s.id==='SOC-6')for(const row of body.children){if(row.type==='INSTANCE'&&p2p3Property(row,'Title')==='Guestbook'&&!row.reactions.length){row.visible=false;changed.add(row.id);}}
 body.itemSpacing=8;changed.add(body.id);
 // Use whole content rows when a long list still needs to scroll; a short sheet
 // uses the exact Auto Layout content height and brings its action block near it.
 const maximum=footer.y-168-28,visible=body.children.filter(n=>n.visible!==false&&n.layoutPositioning!=='ABSOLUTE');let running=body.paddingTop||0,lastWhole=0;
 for(let i=0;i<visible.length;i++){const next=running+visible[i].height+(i?body.itemSpacing:0);if(next>maximum)break;running=next;lastWhole=running;}
 const bodyHeight=body.height,visibleHeight=Math.max(120,bodyHeight<=maximum?bodyHeight:(lastWhole||maximum)),top=Math.max(168,footer.y-visibleHeight-28);
 panel.resize(360,800-top);panel.y=top;fill(panel,'surface');changed.add(panel.id);
 viewport.y=top+16;viewport.resize(328,Math.max(120,footer.y-viewport.y-12));changed.add(viewport.id);
 const close=screen.children.find(n=>n.name==='Close · 44 px');if(close){close.y=Math.max(132,top-50);changed.add(close.id);}
 return {id:s.id,applied:true,changedNodeIds:[...changed],before,after:{panelTop:panel.y,viewportHeight:viewport.height,bodyHeight:body.height,scrolls:body.height>viewport.height},footerGap:footer.y-(viewport.y+viewport.height)};
}

const page=await figma.getNodeByIdAsync(INPUT.pageId);await figma.setCurrentPageAsync(page);const surfaceVariable=INPUT.surfaceVariable?await figma.variables.getVariableByIdAsync(INPUT.surfaceVariable):null;
function fill(n){const hex=INPUT.surface;let paint={type:'SOLID',color:{r:parseInt(hex.slice(1,3),16)/255,g:parseInt(hex.slice(3,5),16)/255,b:parseInt(hex.slice(5,7),16)/255}};if(surfaceVariable)paint=figma.variables.setBoundVariableForPaint(paint,'color',surfaceVariable);n.fills=[paint];}
const work=[],fonts=new Map();for(const item of INPUT.targets){const node=await figma.getNodeByIdAsync(item.nodeId);if(!node||!node.name.startsWith(item.data.id+' ·'))throw Error('Wrong target '+item.nodeId);work.push({...item,node});for(const text of node.findAllWithCriteria({types:['TEXT']}))for(const part of text.getStyledTextSegments(['fontName']))fonts.set(JSON.stringify(part.fontName),part.fontName);}await Promise.all([...fonts.values()].map(f=>figma.loadFontAsync(f)));
const reactions=new Map();for(const {node}of work)for(const n of node.findAll(()=>true))if('reactions'in n&&n.reactions.length)reactions.set(n.id,JSON.stringify(n.reactions));
const results=work.map(({node,data})=>p2p3VisualRefine(node,data)),reactionErrors=[];for(const [id,prior]of reactions){const n=await figma.getNodeByIdAsync(id);if(!n||JSON.stringify(n.reactions)!==prior)reactionErrors.push(id);}const mutated=results.flatMap(r=>r.changedNodeIds||[]);const dimensions=results.filter(r=>r.applied).map(({changedNodeIds,...rest})=>rest);const wrongGaps=dimensions.filter(r=>Math.abs(r.footerGap-12)>0.1);return {kind:'p2p3-compact-sheet',createdNodeIds:[],mutatedNodeIds:[...new Set(mutated)],targets:dimensions,skipped:results.filter(r=>!r.applied).map(r=>({id:r.id,reason:r.reason})),checks:{applied:dimensions.length,reactionsPreserved:reactions.size,reactionErrors,wrongGaps,screenIdsPreserved:true}};
