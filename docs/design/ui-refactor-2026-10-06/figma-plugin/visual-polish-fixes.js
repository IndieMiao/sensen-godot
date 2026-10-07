/* Source-proportioned UI. BAG-1 is the visual benchmark before wider adoption.
 * Original: ui-anchors-2026-10-03/ui/bag.html + kit.css. Pure scene artwork only.
 * Information fields remain separate; compact presentation is not a new game rule.
 */
const POLISH_BASE={inventory,hud,library};
function polishText(p,value,w,size=12,weight='Bold',color='text',name='Label'){
 const n=figma.createText();n.name=name;n.fontName={family:T.font.family,style:weight};n.fontSize=size;n.lineHeight={unit:'PERCENT',value:125};n.characters=String(value??'');n.resize(w,size*1.25);n.textAutoResize='HEIGHT';fill(n,color);p.appendChild(n);const st=STYLE['compact/'+size+'/'+weight];if(st)STYLE_JOBS.push(n.setTextStyleIdAsync(st.id));return n;
}
function polishProperty(c,p,name,value,w,size=12,weight='Bold',color='text'){
 const n=polishText(p,value,w,size,weight,color,name);n.componentPropertyReferences={characters:c.addComponentProperty(name,'TEXT',String(value))};return n;
}
function polishBox(p,name,w,h,color='surface',r=12){const n=frame(p,name,w,h,color);radius(n,r);return n;}
function polishMaster(name,w,h){const n=component('Gensen Refactor/Compact/'+name,w);n.resize(w,h);n.layoutMode='NONE';n.clipsContent=false;register('Compact/'+name,n);return n;}
function polishQuickProperty(component,parent,name,value,w,h,role,align='CENTER'){
 const n=figma.createText();parent.appendChild(n);n.name=name;n.fontName={family:T.font.family,style:'Bold'};n.fontSize=role==='end'?11:10;n.lineHeight={unit:'PIXELS',value:role==='title'?11:role==='quantity'?12:14};n.characters=String(value);n.resize(w,h);n.textAutoResize='NONE';n.textTruncation='ENDING';n.maxLines=role==='title'?2:1;n.textAlignHorizontal=align;fill(n,'text');n.componentPropertyReferences={characters:component.addComponentProperty(name,'TEXT',String(value))};if(STYLE['quick/'+role])STYLE_JOBS.push(n.setTextStyleIdAsync(STYLE['quick/'+role].id));return n;
}
function polishQuickItems(s){
 if(s.sceneControls&&Array.isArray(s.sceneControls.quick))return s.sceneControls.quick;
 if(Array.isArray(s.quickItems)&&s.quickItems.length)return s.quickItems;
 if(Array.isArray(s.quickContents))return s.quickContents;
 if(Array.isArray(s.sceneState?.quick))return s.sceneState.quick;
 return [];
}
function polishQuickSlot(parent,raw,variant){
 const item=legacyItem(raw||{empty:true}),empty=item.empty,known=!empty&&item.quantity?.value!==undefined&&item.quantity?.value!==null&&String(item.quantity.value)!=='';
 const slot=inst(parent,'Compact/QuickSlot/'+(variant|| (empty?'empty':item.selected?'selected':'default')),{Title:empty?'':item.title,Quantity:known?'×'+String(item.quantity.value):'',Icon:legacyGlyph(item.icon),'Show icon':!empty,'Show title':!empty,'Show quantity':!empty,'Show pin':!empty&&Boolean(item.pinned)});slot.name='Quick slot · '+item.title;return {slot,item,known};
}
function polishQuickBar(parent,s,id,options={}){
 const end=options.end||(s.sourceHtml&&['inventory','gear'].includes(s.layout)?'Close':'Bag'),mode=options.detailMode||(s.sourceHtml?'legacy':'current'),items=options.items!==undefined?options.items:polishQuickItems(s),row=horizontal(parent,'Quick Bar · five items and '+end.toLowerCase(),336,4);row.resize(336,68);row.counterAxisSizingMode='FIXED';
 for(let i=0;i<5;i++){const {slot,item}=polishQuickSlot(row,items[i]);if(item.empty){if(mode==='legacy')PENDING_LINKS.push({node:slot,ownerId:id,action:{label:'Choose item',kind:'navigate',target:'BAG-1'}});continue;}
  const detail=mode==='item'?item:mode==='legacy'?{title:item.title,icon:item.icon,state:item.pinned?'Pinned':item.selected?'Selected':'Quick Bar',quantity:item.quantity,actions:[{label:item.pinned?'Unpin':'Pin',kind:'commit',target:'BAG-4-2'},{label:'Close',kind:'dismiss'}]}:{title:item.title,icon:item.icon,quantity:item.quantity,effect:'Selected for your next action.',actions:[{label:'Close',kind:'dismiss'}]};PENDING_LINKS.push({node:slot,ownerId:id,detail});
 }
 const capacity=(s.keyFacts||[]).find(f=>/^(Bag|Bag capacity)$/i.test(f.label||'')&&/^\d+\/\d+$/.test(String(f.value))),parts=capacity?String(capacity.value).split('/').map(Number):null,warning=end==='Bag'&&Boolean(s.presentation?.bagFull||s.state==='Bag full'||parts&&parts[1]>0&&parts[0]/parts[1]>=.9);const terminal=inst(row,'Compact/QuickEnd/'+end,{Label:end,'Show capacity warning':warning});terminal.name=end==='Close'?'Close container':'Open Bag';const close=(s.actions||[]).find(a=>a.kind==='dismiss'),action=options.endAction||(end==='Close'?(close||{label:'Close',kind:'dismiss'}):{label:'Bag',kind:'navigate',target:s.sourceHtml?'BAG-1':'BAG-1-P0'});PENDING_LINKS.push({node:terminal,ownerId:id,action});return row;
}
const POLISH_FILTERS=['All','Seeds','Fish','Produce','Dishes','Materials','Tackle'];
function polishItemCategory(item){const k=item.icon||'';if(/seed/.test(k))return 'Seeds';if(/dish-/.test(k))return 'Dishes';if(/fish|carp|minnow/.test(k))return 'Fish';if(/radish$|carrot$|apple$/.test(k))return 'Produce';if(/worm|lure|trap/.test(k))return 'Tackle';return 'Materials';}
async function polishFilterVariables(){
 const collections=await figma.variables.getLocalVariableCollectionsAsync();let collection=collections.find(c=>c.name==='Gensen · Bag filters · Prototype');if(!collection)collection=figma.variables.createVariableCollection('Gensen · Bag filters · Prototype');
 const existing=await figma.variables.getLocalVariablesAsync();for(const label of POLISH_FILTERS)for(const role of ['active','visible']){const key='bag/'+role+'/'+label;let v=existing.find(v=>v.name===key&&v.variableCollectionId===collection.id);if(!v){v=figma.variables.createVariable(key,collection,'BOOLEAN');v.scopes=['ALL_SCOPES'];v.setValueForMode(collection.defaultModeId,role==='visible'||label==='All');v.description='Local prototype category state. Changes visible items only; never changes owned inventory.';}v.scopes=['ALL_SCOPES'];if(!(collection.defaultModeId in v.valuesByMode))v.setValueForMode(collection.defaultModeId,role==='visible'||label==='All');VAR[key]=v;LEDGER.variables[key]=v.id;}
}
async function polishLibrary(){
 await polishFilterVariables();
 if(KIT['Compact/HUD'])return;
 for(const size of [9,10,11,12,13,14])for(const weight of ['Bold','ExtraBold']){const key='compact/'+size+'/'+weight;if(STYLE[key])continue;const st=figma.createTextStyle();st.name='Gensen/Compact/'+size+'/'+weight;st.fontName={family:T.font.family,style:weight};st.fontSize=size;st.lineHeight={unit:'PERCENT',value:125};STYLE[key]=st;LEDGER.styles[key]=st.id;}
 const hud=polishMaster('HUD',340,78);
 const avatar=polishBox(hud,'Profile portrait',38,38,'surface',19);absolute(avatar,0,3);avatar.clipsContent=true;
 const portrait=frame(avatar,'Original character portrait crop',268.33,402.5);portrait.fills=[{type:'IMAGE',imageHash:BUNDLE.sceneHashes.farm,scaleMode:'FILL'}];absolute(portrait,-67.33,-185.67);
 avatar.strokes=[solid('surface')];avatar.strokeWeight=2;
 const ring=figma.createEllipse();hud.appendChild(ring);ring.name='Skill progress ring';ring.resize(38,38);ring.fills=[];ring.strokes=[solid('#7FC66A')];ring.strokeWeight=2;ring.arcData={startingAngle:-Math.PI/2,endingAngle:Math.PI*.45,innerRadius:1};absolute(ring,0,3);
 const energy=polishBox(hud,'Energy capsule',100,42,'surface',12);absolute(energy,43,0);absolute(icon(energy,'i-energy',12),8,6);absolute(polishProperty(hud,energy,'Energy','142/200',72,14,'ExtraBold'),22,3);
 const track=polishBox(energy,'Energy track',84,3,'border',2);absolute(track,8,23);const progress=polishBox(track,'Energy fill',60,3,'primary',2);absolute(progress,0,0);
 absolute(polishProperty(hud,energy,'Recovery','+1 in 2:40',84,10,'Bold','secondary'),8,28);
 const coins=polishBox(hud,'Coins capsule',52,26,'surface',13);absolute(coins,249,8);absolute(polishProperty(hud,coins,'Coins','230',28,11,'ExtraBold'),7,6);absolute(icon(coins,'i-coin',13),34,6);
 const inbox=polishBox(hud,'Inbox capsule',32,32,'surface',16);absolute(inbox,308,5);absolute(icon(inbox,'i-bell',18),7,7);
 const today=polishBox(hud,'Today capsule',170,24,'surface',12);absolute(today,0,50);absolute(polishProperty(hud,today,'Today','Today · Radishes in 1h 12m',153,10),8,6);absolute(polishText(today,'⌄',10,11,'Bold','secondary'),155,4);
 const place=polishBox(hud,'Location capsule',162,24,'surface',12);absolute(place,178,50);absolute(icon(place,'i-home',11),8,7);absolute(polishProperty(hud,place,'Location','Shanghai · Homestead',130,10),24,6);absolute(polishText(place,'›',8,12,'Bold','secondary'),150,4);
 for(const state of ['default','selected','empty']){
  const cell=polishMaster('InventoryCell/'+state,52,52);fill(cell,'surface');border(cell,state==='selected'?'primary':'border',state==='selected'?1.5:.5);radius(cell,10);if(state==='empty'){cell.fills=[solid('surface',.35)];cell.dashPattern=[2,2];}
  const ic=cicon(cell,cell,'i-fish',27);absolute(ic,12.5,10);cvisible(cell,ic,'Show icon',state!=='empty');
  const qty=polishBox(cell,'Quantity pill',24,13,'primaryTint',6.5);absolute(qty,25,36);const qt=polishProperty(cell,qty,'Quantity','×3',24,10,'ExtraBold');qt.textAlignHorizontal='CENTER';absolute(qt,0,0);cvisible(cell,qty,'Show quantity',state!=='empty');
  const dot=figma.createEllipse();cell.appendChild(dot);dot.name='Rarity dot';dot.resize(6,6);fill(dot,'#9DB89A');absolute(dot,5,5);cvisible(cell,dot,'Show rarity',false);
 }
 for(const [role,size,line]of [['title',10,11],['quantity',10,12],['end',11,14]]){const style=figma.createTextStyle();style.name='Gensen/Quick Bar/'+role;style.fontName={family:T.font.family,style:'Bold'};style.fontSize=size;style.lineHeight={unit:'PIXELS',value:line};STYLE['quick/'+role]=style;LEDGER.styles['quick/'+role]=style.id;}
 for(const state of ['default','selected','empty']){
  const slot=polishMaster('QuickSlot/'+state,52,68);fill(slot);const surface=auto(slot,'Surface',52,'VERTICAL',0,'surface');surface.resize(52,64);surface.primaryAxisSizingMode='FIXED';surface.counterAxisSizingMode='FIXED';surface.counterAxisAlignItems='CENTER';pad(surface,4);radius(surface,11);border(surface,state==='selected'?'primary':'border',state==='selected'?1.2:.6);if(state==='empty')surface.dashPattern=[2,2];absolute(surface,0,state==='selected'?0:4);
  const pinned=frame(surface,'Pinned warm background',50,62,'warningTint');radius(pinned,10);absolute(pinned,1,1);cvisible(slot,pinned,'Show pin',false);
  const imageBox=frame(surface,'Icon region',44,22),ic=cicon(slot,imageBox,'i-radish-seeds',22);absolute(ic,11,0);cvisible(slot,ic,'Show icon',state!=='empty');
  const nameBox=frame(surface,'Title region',44,22),name=polishQuickProperty(slot,nameBox,'Title','',44,22,'title');cvisible(slot,name,'Show title',state!=='empty');
  const quantityBox=frame(surface,'Quantity region',44,12),quantity=polishQuickProperty(slot,quantityBox,'Quantity','',44,12,'quantity','RIGHT');cvisible(slot,quantity,'Show quantity',false);
  const overlay=frame(slot,'Pinned overlay',52,64);absolute(overlay,0,state==='selected'?0:4);overlay.componentPropertyReferences={visible:pinned.componentPropertyReferences.visible};overlay.visible=false;
  const pinLine=frame(overlay,'Pinned top rule',52,2,'warning');absolute(pinLine,0,0);const badge=frame(overlay,'Pinned badge',16,16,'warningTint');radius(badge,8);absolute(badge,18,-6);const pin=cicon(slot,badge,'i-pin',12,'Pin icon');absolute(pin,2,2);
 }
 for(const end of ['Bag','Close']){const c=polishMaster('QuickEnd/'+end,56,68);fill(c);const face=frame(c,'Surface',56,64,'surface');radius(face,11);border(face,'border',.6);absolute(face,0,4);absolute(cicon(c,face,end==='Bag'?'i-bag':'i-close',22),17,9);const label=polishQuickProperty(c,face,'Label',end,48,14,'end');absolute(label,4,38);const dot=frame(face,'Capacity warning dot',7,7,'warning');radius(dot,3.5);absolute(dot,43,7);cvisible(c,dot,'Show capacity warning',false);}
 variantSet('Compact/QuickEnd',['Bag','Close'].map(end=>{const c=KIT['Compact/QuickEnd/'+end];c.name='Action='+end;return c;}));
 for(const state of ['default','selected']){
  const tab=polishMaster('Filter/'+state,50,36);const surface=polishBox(tab,'Filter pill',50,26,state==='selected'?'primary':'surface',13);absolute(surface,0,5);const label=polishProperty(tab,surface,'Label','Seeds',50,11,'Bold',state==='selected'?'surface':'secondary');label.textAlignHorizontal='CENTER';absolute(label,0,6);surface.constraints={horizontal:'STRETCH',vertical:'CENTER'};label.constraints={horizontal:'STRETCH',vertical:'CENTER'};
 }
 const decision=polishMaster('SelectedItem',336,82);fill(decision,'surface');border(decision,'border',.6);radius(decision,14);
 const medallion=polishBox(decision,'Item medallion',40,40,'primaryTint',20);absolute(medallion,10,21);const object=cicon(decision,medallion,'i-dish-grilled',27);absolute(object,6.5,6.5);
 absolute(polishProperty(decision,decision,'Title','Grilled Crucian',202,14,'ExtraBold'),58,10);absolute(polishProperty(decision,decision,'State','Common',140,10,'Bold','secondary'),58,29);absolute(polishProperty(decision,decision,'Effect','+20 Energy',126,12,'ExtraBold'),58,52);
 const qty=polishBox(decision,'Owned quantity',26,18,'primaryTint',9);absolute(qty,273,10);const qt=polishProperty(decision,qty,'Quantity','×3',26,11,'ExtraBold');qt.textAlignHorizontal='CENTER';absolute(qt,0,2);
 absolute(polishText(decision,'›',12,14,'Bold','secondary','Details chevron'),315,9);
 const primary=polishMaster('Command',68,44);const pill=polishBox(primary,'Command surface',68,34,'primary',17);absolute(pill,0,5);const label=polishProperty(primary,pill,'Label','Eat',68,12,'ExtraBold','surface');label.textAlignHorizontal='CENTER';absolute(label,0,9);pill.constraints={horizontal:'STRETCH',vertical:'CENTER'};label.constraints={horizontal:'STRETCH',vertical:'CENTER'};
 const navigation=polishMaster('Navigation',54,44);const nav=polishProperty(navigation,navigation,'Label','Gift ›',54,12,'Bold','primary');nav.textAlignHorizontal='CENTER';absolute(nav,0,14);nav.constraints={horizontal:'STRETCH',vertical:'CENTER'};
 for(const family of ['InventoryCell','QuickSlot','Filter']){const names=family==='Filter'?['default','selected']:['default','selected','empty'];variantSet('Compact/'+family,names.map(state=>{const c=KIT['Compact/'+family+'/'+state];c.name='State='+state;return c;}));}
 LIBRARY.resize(1260,Math.max(libraryY+40,LIBRARY.height));
}
library=async function(){await POLISH_BASE.library();await polishLibrary();};
function polishHud(p,s){
 const d={...(s.sceneState||{}),...(s.hud||{})};const n=inst(p,'Compact/HUD',{Energy:String(d.energy??142)+'/'+String(d.capacity??200),Coins:String(d.coins??230),Recovery:d.recoveryText||'+1 in 2:40',Location:(d.city||'Shanghai')+' · Homestead'});absolute(n,10,18);
 const hits=[['Profile',10,18,38,'PROFILE-1-P0'],['Energy',53,18,100,'ENERGY-P0-1'],['Inbox',314,18,36,'PARCEL-1'],['Today',10,62,170,'TODAY-1'],['Location',188,62,162,'MAP-2-FREE']];for(const [label,x,y,w,target]of hits){const hit=frame(p,'HUD touch · '+label,w,44);absolute(hit,x,y);PENDING_LINKS.push({node:hit,ownerId:s.id,action:{label,target,kind:'navigate'}});}return n;
}
hud=function(p,s){return s.id==='BAG-1'?polishHud(p,s):POLISH_BASE.hud(p,s);};
function polishBag(p,s){
 const art=p.children.find(n=>n.name.startsWith('Scene art ·'));if(art){art.fills=[{type:'SOLID',color:rgb('#B0CFC1')}];const image=frame(art,'Original farm camera framing',416.43,624.64);image.fills=[{type:'IMAGE',imageHash:BUNDLE.sceneHashes.farm,scaleMode:'FILL'}];absolute(image,-42.33,118.67);const veil=frame(art,'Scene dim behind drawer',360,800);veil.fills=[{type:'SOLID',color:rgb('#2F3A33'),opacity:.18}];}
 const sheet=polishBox(p,'Bag drawer · source proportions',360,546,'surface',20);absolute(sheet,0,254);sheet.topLeftRadius=20;sheet.topRightRadius=20;sheet.bottomLeftRadius=0;sheet.bottomRightRadius=0;sheet.fills=[solid('surface',.97)];
 const chrome=auto(p,'Bag layout',336,'VERTICAL',0);absolute(chrome,12,266);
 polishQuickBar(chrome,s,s.id,{end:'Close',detailMode:'item',endAction:{label:'Close',target:'FARM-1',kind:'dismiss'}});
 const space=(h)=>{const n=frame(chrome,'Spacing',336,h);return n;};space(8);
 const capacity=horizontal(chrome,'Bag capacity and utilities',336,6);capacity.resize(336,28);capacity.counterAxisSizingMode='FIXED';polishText(capacity,'Bag 19/25',77,12,'ExtraBold');const track=polishBox(capacity,'Capacity track',83,3,'border',2);polishBox(track,'Capacity fill',63,3,'primary',2);const gear=inst(capacity,'Compact/Navigation',{Label:'Gear ›'},58);PENDING_LINKS.push({node:gear,ownerId:s.id,action:{label:'Gear',kind:'navigate',target:'BAG-2'}});const sort=inst(capacity,'Compact/Navigation',{Label:'Sort · Recent'},100);PENDING_LINKS.push({node:sort,ownerId:s.id,detail:{title:'Sort',state:'Recent',items:[{title:'Recent'},{title:'Name'},{title:'Type'}],actions:[{label:'Close',kind:'dismiss'}]}});space(4);
 const tabsView=frame(chrome,'Category filters · horizontal scroll',336,36);tabsView.clipsContent=true;tabsView.overflowDirection='HORIZONTAL';const tabsRow=horizontal(tabsView,'Categories',390,4);
 for(const [i,label]of (s.tabs||[]).entries()){const width=[32,42,32,53,46,63,44][i],tab=frame(tabsRow,'Category · '+label,width,36);inst(tab,'Compact/Filter/default',{Label:label},width);const selectedTab=inst(tab,'Compact/Filter/selected',{Label:label},width);selectedTab.setBoundVariable('visible',VAR['bag/active/'+label]);const actions=[];for(const name of POLISH_FILTERS)for(const role of ['active','visible'])actions.push({type:'SET_VARIABLE',variableId:VAR['bag/'+role+'/'+name].id,variableValue:{type:'BOOLEAN',resolvedType:'BOOLEAN',value:role==='active'?name===label:label==='All'||name===label}});STYLE_JOBS.push(tab.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions}]));}space(4);
 const selected=s.items[0],summary=frame(chrome,'Selected item · identity and decision',336,82);summary.setBoundVariable('visible',VAR['bag/visible/Dishes']);inst(summary,'Compact/SelectedItem',{Title:selected.title,State:selected.state||'',Effect:selected.effect.replace('Restores ','+'),Quantity:'×'+selected.quantity.value,Icon:legacyGlyph('i-dish-grilled')});
 const details=frame(summary,'Details touch target',278,38);absolute(details,54,0);PENDING_LINKS.push({node:details,ownerId:s.id,detail:selected});
 const gift=inst(summary,'Compact/Navigation',{Label:'Gift ›'});absolute(gift,202,38);PENDING_LINKS.push({node:gift,ownerId:s.id,action:selected.actions.find(a=>a.kind==='navigate'),itemContext:selected});
 const eat=inst(summary,'Compact/Command',{Label:'Eat'});absolute(eat,260,38);PENDING_LINKS.push({node:eat,ownerId:s.id,action:selected.actions.find(a=>a.kind==='commit'),itemContext:selected});space(8);
 const grid=auto(chrome,'Inventory · wrapping five-column grid',336,'HORIZONTAL',6);grid.paddingLeft=26;grid.paddingRight=26;grid.layoutWrap='WRAP';grid.primaryAxisSizingMode='FIXED';grid.counterAxisSizingMode='AUTO';grid.counterAxisSpacing=6;grid.minHeight=284;
 const data=s.gridItems.map(legacyItem);for(let i=0;i<25;i++){const item=data[i]||{empty:true};const cell=inst(grid,'Compact/InventoryCell/'+(item.empty?'empty':item.selected?'selected':'default'),{Icon:legacyGlyph(item.icon),'Show icon':!item.empty,Quantity:'×'+(item.quantity?.value||''),'Show quantity':!item.empty,'Show rarity':Boolean(item.rarity)});cell.name='Inventory cell · '+(item.title||'Empty');cell.setBoundVariable('visible',VAR[item.empty?'bag/active/All':'bag/visible/'+polishItemCategory(item)]);const dot=cell.findOne(n=>n.name==='Rarity dot');if(dot&&item.rarity)fill(dot,{common:'#9DB89A',fine:'#6FA8DC',rare:'#A98BD6',legendary:'#E3B341'}[item.rarity]||'#9DB89A');if(!item.empty)PENDING_LINKS.push({node:cell,ownerId:s.id,detail:legacyDetails(item,s,i)});}
 return chrome;
}
inventory=function(p,s){return s.id==='BAG-1'?polishBag(p,s):POLISH_BASE.inventory(p,s);};
