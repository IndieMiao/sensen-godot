// In-place shared HUD delta. Run only on the refactor page; original Prototype stays intact.
const S={"pageId":"481:53","libraryId":"481:54","hudId":"483:304","benchmarkId":"633:41154","styles":{"compact/10/Bold":"S:10468057d69109a50bd2ffda48217ce9c13c977e,","compact/10/ExtraBold":"S:3b4974f0914e3f5101f2433d4acbec42393c86af,","compact/11/Bold":"S:a03e83607574bc0deaa5454b052a2fbea42c8c0f,","compact/11/ExtraBold":"S:997272bc45475ee4b5ba27f411856fc17be9506e,","compact/12/Bold":"S:1db15c03658638d40e24547fff743264672a2d4b,","compact/12/ExtraBold":"S:2b5a9261020ebd86343a7ac8e0a7c848a1421a5a,","compact/13/Bold":"S:d4804b59dc885cf8c05e4031697b0463ccfa8d9d,","compact/13/ExtraBold":"S:952b401176b1b7ac28d1f99afdaa529ac3c20f84,","compact/14/Bold":"S:9f0d5632eb61e47e16618b0231f0e83024651ecc,","compact/14/ExtraBold":"S:a4d6ab9915c1ad87a5a5d3969bdbe5e3e551fe18,","compact/9/Bold":"S:290515e1d25bbded5ef13af3a2d30bcf17bd2ca3,"},"icons":{"i-energy":"431:59","i-home":"431:75"},"variables":{"color/surface":"VariableID:481:4","color/surfaceRaised":"VariableID:481:5","color/text":"VariableID:481:6","color/secondary":"VariableID:481:8","color/border":"VariableID:481:9","color/primary":"VariableID:481:11","color/primaryTint":"VariableID:481:13","color/danger":"VariableID:481:15","color/dangerTint":"VariableID:481:17","color/warning":"VariableID:481:19","color/warningTint":"VariableID:481:21","color/info":"VariableID:481:23"},"colors":{"surface":"#FBF8F1","surfaceRaised":"#FFFFFF","text":"#2F3A33","secondary":"#5D6A62","border":"#E1DAC8","primary":"#3E7D43","primaryTint":"#ECF4E7","danger":"#9C3F2E","dangerTint":"#FFF0EB","warning":"#8C5F12","warningTint":"#FFF0D4","info":"#426A88"}};
const page=await figma.getNodeByIdAsync(S.pageId);await figma.setCurrentPageAsync(page);
const main=await figma.getNodeByIdAsync(S.hudId),library=await figma.getNodeByIdAsync(S.libraryId),benchmark=await figma.getNodeByIdAsync(S.benchmarkId);
const styles={},icons={},variables={};for(const [key,id]of Object.entries(S.styles))styles[key]=await figma.getStyleByIdAsync(id);for(const [key,id]of Object.entries(S.icons))icons[key]=await figma.getNodeByIdAsync(id);for(const [key,id]of Object.entries(S.variables))variables[key]=await figma.variables.getVariableByIdAsync(id);
function paint(key){const hex=S.colors[key],p={type:'SOLID',color:{r:parseInt(hex.slice(1,3),16)/255,g:parseInt(hex.slice(3,5),16)/255,b:parseInt(hex.slice(5,7),16)/255}};return variables['color/'+key]?figma.variables.setBoundVariableForPaint(p,'color',variables['color/'+key]):p;}
function inPage(n){let p=n;while(p&&p.type!=='PAGE')p=p.parent;return p?.id===page.id;}
const candidates=await main.getInstancesAsync(),instances=candidates.filter(inPage),defs=main.componentPropertyDefinitions,avatarKey=Object.keys(defs).find(k=>k.split('#')[0]==='Avatar'),oldDefault=defs[avatarKey].defaultValue;
// Capture property values and reactions before any master mutation; never remove overrides.
const snapshots=instances.map(n=>({n,props:JSON.parse(JSON.stringify(n.componentProperties)),reactions:JSON.stringify(n.reactions),avatarExplicit:Boolean(n.componentProperties[avatarKey]?.boundVariables?.value)||n.componentProperties[avatarKey]?.value!==oldDefault}));

/* Shared HUD refinement. Keep the existing master, text IDs and property keys.
 * Geometry follows the source-proportioned BAG-1 benchmark; values stay live.
 * This core is also embedded verbatim in the targeted cloud delta.
 */
function lightHudProperty(node,name){return Object.entries(node.componentProperties||{}).find(([key])=>key.split('#')[0]===name)?.[1];}
function lightHudText(node,name){return node.findOne(n=>n.type==='TEXT'&&n.name===name);}
function lightHudPart(node,name){return node.findOne(n=>n.name===name);}
function lightHudPlace(node,x,y,w,h){
 if(node.parent&&'layoutMode'in node.parent&&node.parent.layoutMode!=='NONE')node.layoutPositioning='ABSOLUTE';
 if(w!==undefined)node.resize(w,h===undefined?node.height:h);node.x=x;node.y=y;return node;
}
function lightHudSurface(node,paint,radius){node.fills=[paint('surface')];node.strokes=[];node.cornerRadius=radius;node.clipsContent=false;}
async function refineSharedHud(main,ctx){
 if(!main||main.type!=='COMPONENT'||!ctx.benchmark)throw Error('Existing shared HUD and compact benchmark are required');
 const before=new Set([main.id,...main.findAll(()=>true).map(n=>n.id)]),created=new Set(),mutated=new Set(before);
 const fontMap=new Map();for(const n of main.findAllWithCriteria({types:['TEXT']}))for(const seg of n.getStyledTextSegments(['fontName']))fontMap.set(seg.fontName.family+'|'+seg.fontName.style,seg.fontName);
 for(const style of Object.values(ctx.styles))if(style?.fontName)fontMap.set(style.fontName.family+'|'+style.fontName.style,style.fontName);
 for(const font of fontMap.values())await figma.loadFontAsync(font);
 function box(parent,name,w,h,r){let n=parent.children.find(x=>x.name===name);if(!n){n=figma.createAutoLayout('HORIZONTAL');n.name=name;parent.appendChild(n);created.add(n.id);}n.layoutMode='HORIZONTAL';n.primaryAxisSizingMode='FIXED';n.counterAxisSizingMode='FIXED';n.paddingLeft=n.paddingRight=n.paddingTop=n.paddingBottom=0;n.resize(w,h);lightHudSurface(n,ctx.paint,r);return n;}
 async function type(n,size,weight,w,h){const style=ctx.styles['compact/'+size+'/'+weight];if(!style)throw Error('Missing compact text style '+size+'/'+weight);await n.setTextStyleIdAsync(style.id);n.textAutoResize='NONE';n.resize(w,h);n.textTruncation='ENDING';n.maxLines=1;mutated.add(n.id);return n;}
 function scale(n,size){if(Math.abs(n.width-size)>.01)n.rescale(size/n.width);mutated.add(n.id);}
 const status=lightHudPart(main,'Status'),energy=main.findOne(n=>n.type==='FRAME'&&n.name==='Energy'),avatar=main.findOne(n=>n.type==='INSTANCE'&&n.componentPropertyReferences?.mainComponent?.split('#')[0]==='Avatar'),coins=lightHudText(main,'Coins'),coinIcon=main.findOne(n=>n.type==='INSTANCE'&&n.componentPropertyReferences?.mainComponent?.split('#')[0]==='Coin icon'),bell=main.findOne(n=>n.type==='INSTANCE'&&n.componentPropertyReferences?.mainComponent?.split('#')[0]==='Inbox icon'),row=lightHudPart(main,'HUD second row'),today=lightHudPart(main,'Today navigation'),place=lightHudPart(main,'Location navigation'),buff=lightHudPart(main,'Buff status');
 if([status,energy,avatar,coins,coinIcon,bell,row,today,place,buff].some(n=>!n))throw Error('Shared HUD structure is incomplete');
 const avatarKey=avatar.componentPropertyReferences.mainComponent,oldAvatarDefault=main.componentPropertyDefinitions[avatarKey].defaultValue;
 let portrait=ctx.library.children.find(n=>n.type==='COMPONENT'&&n.name==='Gensen Refactor/Compact/PlayerPortrait');
 if(!portrait){const original=ctx.benchmark.findOne(n=>n.name==='Profile portrait');if(!original)throw Error('Benchmark portrait crop is missing');const clone=original.clone();ctx.library.appendChild(clone);clone.x=1500;clone.y=24;portrait=figma.createComponentFromNode(clone);portrait.name='Gensen Refactor/Compact/PlayerPortrait';portrait.description='Original approved 38px character portrait crop. Shared HUD Avatar remains an instance-swap property.';created.add(portrait.id);for(const n of portrait.findAll(()=>true))created.add(n.id);}
 const avatarReferences={...avatar.componentPropertyReferences};main.editComponentProperty(avatarKey,{defaultValue:portrait.id});avatar.swapComponent(portrait);avatar.componentPropertyReferences=avatarReferences;scale(avatar,38);
 main.layoutMode='NONE';main.fills=[];main.strokes=[];main.effects=[];main.clipsContent=false;main.resize(344,82);
 status.layoutMode='NONE';status.fills=[];lightHudPlace(status,0,0,344,46);lightHudPlace(avatar,2,5,38,38);
 energy.layoutMode='NONE';lightHudSurface(energy,ctx.paint,12);lightHudPlace(energy,45,2,100,42);
 const energyValue=lightHudText(energy,'Energy'),recovery=lightHudText(energy,'Recovery'),track=lightHudPart(energy,'Energy track'),amount=lightHudPart(energy,'Energy fill');
 await type(energyValue,14,'ExtraBold',72,18);lightHudPlace(energyValue,22,3);await type(recovery,10,'Bold',84,13);lightHudPlace(recovery,8,28);
 track.fills=[ctx.paint('border')];track.cornerRadius=2;lightHudPlace(track,8,23,84,3);amount.cornerRadius=2;lightHudPlace(amount,0,0,59.64,3);
 let energyIcon=energy.children.find(n=>n.name==='Energy pictogram');if(!energyIcon){energyIcon=ctx.icons['i-energy'].createInstance();energy.appendChild(energyIcon);energyIcon.name='Energy pictogram';created.add(energyIcon.id);for(const n of energyIcon.findAll(()=>true))created.add(n.id);}scale(energyIcon,12);lightHudPlace(energyIcon,8,6);
 const trailing=box(status,'Balances and Inbox',197,46,0);trailing.fills=[];trailing.primaryAxisAlignItems='MAX';trailing.counterAxisAlignItems='CENTER';trailing.itemSpacing=7;lightHudPlace(trailing,145,0);
 const coinCapsule=box(status,'Coins capsule',52,26,13);trailing.appendChild(coinCapsule);coinCapsule.layoutPositioning='AUTO';coinCapsule.paddingLeft=coinCapsule.paddingRight=7;coinCapsule.itemSpacing=4;coinCapsule.counterAxisAlignItems='CENTER';coinCapsule.primaryAxisSizingMode='AUTO';coinCapsule.counterAxisSizingMode='FIXED';coinCapsule.appendChild(coins);coinCapsule.appendChild(coinIcon);await type(coins,11,'ExtraBold',28,14);coins.layoutPositioning='AUTO';coins.textAutoResize='WIDTH_AND_HEIGHT';scale(coinIcon,13);coinIcon.layoutPositioning='AUTO';
 const inbox=box(status,'Inbox capsule',32,32,16);trailing.appendChild(inbox);inbox.layoutPositioning='AUTO';inbox.appendChild(bell);scale(bell,18);lightHudPlace(bell,7,7);
 const unread=lightHudPart(status,'Inbox unread badge'),unreadCount=lightHudText(status,'Inbox unread count');lightHudPlace(unread,326,-1,18,15);unread.cornerRadius=7.5;await type(unreadCount,10,'ExtraBold',18,13);unreadCount.textAlignHorizontal='CENTER';lightHudPlace(unreadCount,0,1);
 row.layoutMode='HORIZONTAL';row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='FIXED';row.itemSpacing=8;row.paddingLeft=row.paddingRight=row.paddingTop=row.paddingBottom=0;row.fills=[];lightHudPlace(row,2,52,340,24);
 today.layoutMode='NONE';lightHudSurface(today,ctx.paint,12);lightHudPlace(today,0,0,170,24);place.layoutMode='NONE';lightHudSurface(place,ctx.paint,12);lightHudPlace(place,178,0,162,24);
 const todayLabel=lightHudText(today,'Today label'),todayCount=lightHudText(today,'Today count'),todayBadge=lightHudPart(today,'Today count badge'),todayChevron=lightHudText(today,'Today chevron');
 await type(todayLabel,10,'Bold',112,13);lightHudPlace(todayLabel,8,6);lightHudPlace(todayBadge,126,4,24,16);todayBadge.cornerRadius=8;await type(todayCount,10,'ExtraBold',24,13);todayCount.textAlignHorizontal='CENTER';lightHudPlace(todayCount,0,1);await type(todayChevron,11,'Bold',10,14);lightHudPlace(todayChevron,154,4);
 const location=lightHudText(place,'Location'),placeChevron=lightHudText(place,'Location chevron');await type(location,10,'Bold',121,13);lightHudPlace(location,24,6);await type(placeChevron,12,'Bold',8,15);lightHudPlace(placeChevron,150,4);
 let home=place.children.find(n=>n.name==='Location pictogram');if(!home){home=ctx.icons['i-home'].createInstance();place.appendChild(home);home.name='Location pictogram';created.add(home.id);for(const n of home.findAll(()=>true))created.add(n.id);}scale(home,11);lightHudPlace(home,8,7);
 buff.layoutMode='NONE';lightHudSurface(buff,ctx.paint,13);lightHudPlace(buff,8,94,328,26);const buffIcon=buff.findOne(n=>n.type==='INSTANCE'),buffTitle=lightHudText(buff,'Buff title'),buffRemaining=lightHudText(buff,'Buff remaining');scale(buffIcon,14);lightHudPlace(buffIcon,8,6);await type(buffTitle,11,'Bold',183,14);lightHudPlace(buffTitle,28,6);await type(buffRemaining,11,'ExtraBold',101,14);buffRemaining.textAlignHorizontal='RIGHT';lightHudPlace(buffRemaining,219,6);
 // Record full affected trees because icon rescaling affects nested descendants.
 for(const n of main.findAll(()=>true))(before.has(n.id)?mutated:created).add(n.id);
 return {createdNodeIds:[...created],mutatedNodeIds:[...mutated],hudId:main.id,portraitId:portrait.id,avatarKey,oldAvatarDefault,newAvatarDefault:portrait.id};
}
function updateLightHudInstance(n){
 const energy=String(lightHudProperty(n,'Energy')?.value??lightHudText(n,'Energy')?.characters??''),parts=energy.match(/([\d.]+)\s*\/\s*([\d.]+)/),meter=lightHudPart(n,'Energy fill');
 if(meter&&parts&&Number(parts[2])>0)meter.resize(Math.max(1,84*Math.min(1,Number(parts[1])/Number(parts[2]))),3);
 // Auto-layout in the master expands Coins leftward. Instance descendant x/y writes are forbidden.
 const amount=lightHudText(n,'Coins');
 const buff=Boolean(lightHudProperty(n,'Show Buff')?.value);n.resize(344,buff?126:82);
 return {energy,coins:amount?.characters||'',buff};
}
function updateLightHudHitRegions(parent,n){
 const changed=[];let ancestor=parent;while(ancestor&&ancestor.type!=='PAGE'){if(ancestor.type==='INSTANCE')return changed;ancestor=ancestor.parent;}const hits={Profile:[-1,2,44],Energy:[45,0,100],Inbox:[304,1,44],Today:[2,46,170],Location:[180,46,162]};
 for(const [name,[x,y,w]]of Object.entries(hits)){const hit=parent.children.find(c=>c.name==='HUD touch · '+name);if(hit){lightHudPlace(hit,n.x+x,n.y+y,w,44);changed.push(hit.id);}}
 for(const hit of parent.children.filter(c=>c.name.startsWith('Buff touch ·'))){lightHudPlace(hit,n.x+8,n.y+92,328,44);changed.push(hit.id);}return changed;
}


const result=await refineSharedHud(main,{library,benchmark,styles,icons,paint});
const touched=new Set(result.mutatedNodeIds),created=new Set(result.createdNodeIds),valueChecks=[],errors=[];
for(const snap of snapshots){
 const n=snap.n;
 if(snap.avatarExplicit){const avatar=snap.props[avatarKey];n.setProperties({[avatarKey]:avatar.boundVariables?.value||avatar.value});}
 else n.setProperties({[avatarKey]:result.newAvatarDefault});
 const data=updateLightHudInstance(n);for(const id of updateLightHudHitRegions(n.parent,n))touched.add(id);touched.add(n.id);for(const child of n.findAll(()=>true))touched.add(child.id);
 for(const [key,before]of Object.entries(snap.props)){if(key===avatarKey)continue;const after=n.componentProperties[key];if(JSON.stringify(before)!==JSON.stringify(after))errors.push({nodeId:n.id,key,before,after});}
 if(snap.reactions!==JSON.stringify(n.reactions))errors.push({nodeId:n.id,issue:'instance reactions changed'});
 if(snap.avatarExplicit&&JSON.stringify(snap.props[avatarKey])!==JSON.stringify(n.componentProperties[avatarKey]))errors.push({nodeId:n.id,issue:'explicit avatar changed'});
 valueChecks.push({nodeId:n.id,...data,explicitAvatar:snap.avatarExplicit});
}
function ranges(values){const nums=[...new Set(values)].sort((a,b)=>a-b),out=[];let a,b;for(const v of nums){if(a===undefined){a=b=v;}else if(v===b+1)b=v;else{out.push(a===b?String(a):a+'-'+b);a=b=v;}}if(a!==undefined)out.push(a===b?String(a):a+'-'+b);return out.join(',');}
function compactSimple(ids){const by={};for(const id of ids){const match=id.match(/^(I?\d+):(\d+)$/);if(!match)throw Error('Unexpected simple ID '+id);(by[match[1]]??=[]).push(Number(match[2]));}return Object.fromEntries(Object.entries(by).sort().map(([p,v])=>[p,ranges(v)]));}
function compactIds(input){const ids=[...input],direct=[],bySuffix={};for(const id of ids){const semi=id.indexOf(';');if(semi<0)direct.push(id);else{const root=id.slice(0,semi),suffix=id.slice(semi);(bySuffix[suffix]??=[]).push(root);}}const groups=new Map();for(const [suffix,roots]of Object.entries(bySuffix)){const compact=compactSimple(roots),key=JSON.stringify(compact);if(!groups.has(key))groups.set(key,{roots:compact,suffixes:[]});groups.get(key).suffixes.push(suffix);}return {count:ids.length,direct:compactSimple(direct),instanceGroups:[...groups.values()]};}
return {hudId:main.id,portraitId:result.portraitId,oldAvatarDefault:result.oldAvatarDefault,newAvatarDefault:result.newAvatarDefault,instances:instances.length,explicitAvatarsPreserved:snapshots.filter(s=>s.avatarExplicit).length,nonAvatarValuesAndReactionsUnchanged:errors.length===0,errors,energyValues:[...new Set(valueChecks.map(v=>v.energy))],buffVisible:valueChecks.filter(v=>v.buff).length,geometry:{normalHeight:82,buffHeight:126,energyTrack:84,touchHeight:44},createdNodeIds:compactIds(created),mutatedNodeIds:compactIds(touched),idEncoding:'direct prefix:number ranges; instanceGroups expand roots prefix:number ranges, then append every suffix. I prefixes are literal.'};
