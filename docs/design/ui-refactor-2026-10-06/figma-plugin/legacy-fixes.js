/* Legacy-only fidelity adapters, appended after src.js. Source grids and quantities remain authoritative. */
const LEGACY_BASE={library,grid,quickbar,inventory,gearScreen,shop,semanticRow};
const LEGACY_NAMES={'i-radish-seeds':'Radish Seeds','i-carrot-seeds':'Carrot Seeds','i-pumpkin-seeds':'Pumpkin Seeds','i-compost':'Compost','i-feed-bag':'Orchard Feed','i-worm':'Worm Bait','i-lure':'Spinner Lure','i-trap':'Fish Trap','i-torch':'Torch','i-carp':'Carp','i-minnow':'Minnow','i-dish-soup':'Fresh Fish Soup','i-radish':'Radish','i-carrot':'Carrot','i-apple':'Apple','i-dish-grilled':'Grilled Crucian','i-fish':'Pond Crucian','i-wood':'Timber','i-stone':'Stone','i-salt':'Rock Salt','i-copper':'Copper Ore','i-reeds':'Reeds','i-clay':'Clay','i-quartz':'Quartz','i-herb':'Wild Herb'};
function legacySource(id){return BUNDLE.screens.find(s=>s.id===id&&s.sourceHtml);}
function legacyItem(raw={},index=0){const empty=raw.empty===true||raw.title==='Empty'||raw.sourceClasses?.includes('is-ghost');const key=raw.icon||'i-question';const technical=key.replace(/^i-/,'').replace(/-/g,' ');const supplied=raw.label||raw.title||raw.name;const label=(!supplied||String(supplied).toLowerCase()===technical)?(LEGACY_NAMES[key]||technical.replace(/\b\w/g,c=>c.toUpperCase())):supplied;return {...raw,title:empty?'Empty':label,icon:key,empty,quantity:raw.quantity||(raw.count!==null&&raw.count!==undefined?{value:String(raw.count),label:'Owned'}:undefined),selected:Boolean(raw.selected),pinned:Boolean(raw.pinned||raw.sourceClasses?.includes('is-pinned')),state:raw.state||(raw.sourceClasses?.includes('is-pot')?'In pot':''),sourceIndex:index};}
function legacyGlyph(id){return (ICON[id]||ICON['i-question']).id;}
function legacyDetails(item,s,index){const selected=s.selectedItem||(s.variant==='bag'&&s.items?.length===1?s.items[0]:null);const match=selected&&item.selected?selected:(s.items||[]).find(r=>r.title?.toLowerCase()===item.title?.toLowerCase());const data={...item,...(match||{}),icon:item.icon};if(item.source)data.disclosure=[...(data.disclosure||[]),'Stored in '+item.source+'.'];if(item.hint)data.disclosure=[...(data.disclosure||[]),item.hint];if(item.region)data.disclosure=[...(data.disclosure||[]),item.region];return data;}
library=async function(){await LEGACY_BASE.library();
 for(const state of ['default','selected','empty']){
  const c=component('Gensen Refactor/LegacyInventoryCell/'+state,59);c.resize(59,78);c.primaryAxisSizingMode='FIXED';fill(c,state==='empty'?'surface':'surfaceRaised');border(c,state==='selected'?'primary':'border',state==='selected'?2:1);radius(c,'cell');if(state==='empty')c.dashPattern=[3,3];
  const ic=cicon(c,c,'i-fish',28);absolute(ic,15,8);cvisible(c,ic,'Show icon',state!=='empty');
  const st=ctext(c,c,'State','',55,'caption','secondary','Bold');absolute(st,2,38);st.textAlignHorizontal='CENTER';cvisible(c,st,'Show state',false);
  const qty=ctext(c,c,'Quantity','',53,'caption','text','ExtraBold');absolute(qty,3,59);qty.textAlignHorizontal='RIGHT';cvisible(c,qty,'Show quantity',false);
  const dot=figma.createEllipse();c.appendChild(dot);dot.name='Rarity dot';dot.resize(7,7);fill(dot,'primaryTint');dot.x=5;dot.y=5;cvisible(c,dot,'Show rarity',false);
  register('LegacyInventoryCell/'+state,c);
 }
 for(const state of ['default','selected','empty']){
  const c=component('Gensen Refactor/LegacyCollectionCell/'+state,59);c.resize(59,138);c.primaryAxisSizingMode='FIXED';fill(c,'surfaceRaised');border(c,state==='selected'?'primary':'border',state==='selected'?2:1);radius(c,'cell');
  const ic=cicon(c,c,'i-fish',28);absolute(ic,15,8);cvisible(c,ic,'Show icon',state!=='empty');
  const title=ctext(c,c,'Title','Pond Crucian',55,'caption','text','Bold');absolute(title,2,40);title.textAlignHorizontal='CENTER';
  const st=ctext(c,c,'State','',55,'caption','secondary','Bold');absolute(st,2,95);st.textAlignHorizontal='CENTER';cvisible(c,st,'Show state',false);
  const qty=ctext(c,c,'Quantity','',53,'caption','text','ExtraBold');absolute(qty,3,116);qty.textAlignHorizontal='RIGHT';cvisible(c,qty,'Show quantity',false);
  register('LegacyCollectionCell/'+state,c);
 }
 for(const state of ['default','selected','empty']){
  const c=component('Gensen Refactor/LegacyGearSlot/'+state,48);c.resize(48,90);c.primaryAxisSizingMode='FIXED';fill(c,'surfaceRaised');border(c,state==='selected'?'primary':'border',state==='selected'?2:1);radius(c,'cell');if(state==='empty')c.dashPattern=[3,3];
  const role=ctext(c,c,'Role','Fishing',46,'caption','secondary','Bold');absolute(role,1,3);role.textAlignHorizontal='CENTER';
  const ic=cicon(c,c,'i-rod',24);absolute(ic,12,23);
  const title=ctext(c,c,'Title','Starter Rod',46,'caption','text','Bold');absolute(title,1,49);title.textAlignHorizontal='CENTER';register('LegacyGearSlot/'+state,c);
 }
 const summary=component('Gensen Refactor/LegacySelectedSummary',CW);summary.resize(CW,70);summary.primaryAxisSizingMode='FIXED';fill(summary,'surface');
 const sn=ctext(summary,summary,'Title','Grilled Crucian',250,'rowTitle','text','ExtraBold');absolute(sn,0,2);
 const sv=ctext(summary,summary,'Quantity','3',62,'quantity','text','ExtraBold');absolute(sv,266,0);sv.textAlignHorizontal='RIGHT';cvisible(summary,sv,'Show quantity',true);
 const su=ctext(summary,summary,'Quantity label','Owned',62,'caption','secondary');absolute(su,266,31);su.textAlignHorizontal='RIGHT';cvisible(summary,su,'Show quantity label',true);
 const ss=ctext(summary,summary,'State','Common',250,'caption','secondary','Bold');absolute(ss,0,26);cvisible(summary,ss,'Show state',true);
 const se=ctext(summary,summary,'Effect','Restores 20 Energy',CW,'body','text','Bold');absolute(se,0,47);cvisible(summary,se,'Show effect',true);register('LegacySelectedSummary',summary);
 for(const family of ['LegacyInventoryCell','LegacyCollectionCell','LegacyGearSlot']){const members=['default','selected','empty'].map(state=>{const c=KIT[family+'/'+state];c.name='State='+state;return c;});variantSet(family,members);}
 LIBRARY.resize(1260,Math.max(libraryY+40,LIBRARY.height));
};
semanticRow=function(p,r,ownerId){if(!r.requirements?.length)return LEGACY_BASE.semanticRow(p,r,ownerId);const n=LEGACY_BASE.semanticRow(p,{...r,actions:[],disclosure:[]},ownerId);needs(p,r.requirements,ownerId);if(r.supporting)text(p,r.supporting,p.width,'body','secondary');for(const a of r.actions||[]){button(p,a,'secondary',ownerId);PENDING_LINKS[PENDING_LINKS.length-1].itemContext=r;}if(r.disclosure?.length)PENDING_LINKS.push({node:n,ownerId,detail:r});return n;};
grid=function(p,items,id,options={}){
 const s=legacySource(id);if(!s)return LEGACY_BASE.grid(p,items,id,options);
 const isCollection=s.variant==='collection-grid',columns=5,width=(p.width-32)/5;
 const rows=auto(p,'Source grid · five columns',p.width,'VERTICAL',8);
 const groups=isCollection&&s.collectionGroups?.length?s.collectionGroups:[{items:s.gridItems?.length?s.gridItems:items||[]}];
 for(const group of groups){const data=group.items.map(legacyItem);if(group.rarity)sectionTitle(rows,group.rarity[0].toUpperCase()+group.rarity.slice(1));const total=Math.max(s.variant==='bag'?25:data.length,data.length);
  for(let k=0;k<total;k+=columns){const rr=horizontal(rows,'Source inventory row '+(k/columns+1),p.width,8);for(let j=0;j<columns&&k+j<total;j++){
   const raw=data[k+j]||{title:'Empty',empty:true},item=legacyDetails(raw,s,k+j),empty=raw.empty;
   const visualState=raw.state==='Discovered'?'':raw.state;const n=inst(rr,(isCollection?'LegacyCollectionCell/':'LegacyInventoryCell/')+(empty?'empty':raw.selected?'selected':'default'),{Title:item.title,Icon:legacyGlyph(raw.icon),Quantity:raw.quantity?.value||'','Show quantity':!empty&&Boolean(raw.quantity),State:visualState||'','Show state':Boolean(visualState)&&!empty,'Show icon':!empty,'Show rarity':Boolean(raw.rarity)&&!empty},width);
   n.name='Inventory cell · '+item.title;
   const dot=n.findOne(x=>x.name==='Rarity dot');if(dot&&raw.rarity){const colors={common:'#9AB69B',fine:'#6FA8DC',rare:'#AA8BD3',legendary:'#E3B341'};dot.fills=[solid(colors[raw.rarity]||'#9AB69B')];}
   if(!empty&&options.select!==false)PENDING_LINKS.push({node:n,ownerId:id,detail:{...item,actions:item.actions?.length?item.actions:[{label:'Close',kind:'dismiss'}]}});
  }}
 }return rows;
};
quickbar=function(p,s,id){return s.sourceHtml?polishQuickBar(p,s,id,{detailMode:'legacy'}):LEGACY_BASE.quickbar(p,s,id);};
function legacySizedButton(p,a,emphasis,id){const n=button(p,a,emphasis,id);const label=n.findOne(x=>x.type==='TEXT'&&x.name==='Label');if(label){label.resize(Math.max(20,p.width-(a.kind==='navigate'?28:24)),label.height);label.textAutoResize='HEIGHT';}return n;}
function legacyContainerTabs(p,s,active){tabs(p,{tabs:['Bag','Gear'],selectedTab:active},s.id);}
inventory=function(p,s){if(!s.sourceHtml)return LEGACY_BASE.inventory(p,s);panel(p,172);
 const picked=s.gridItems?.find(x=>x.selected);const selected=s.selectedItem||(s.items?.length===1?s.items[0]:null)||(picked?legacyDetails(legacyItem(picked),s,0):null);
 const foot=auto(p,'Selected object · compact decision area',CW,'VERTICAL',8,'surface');foot.paddingTop=10;
 if(selected)inst(foot,'LegacySelectedSummary',{Title:selected.title,State:selected.state||'','Show state':Boolean(selected.state),Effect:selected.effect||'','Show effect':Boolean(selected.effect),Quantity:selected.quantity?.value||'','Quantity label':selected.quantity?.label||'','Show quantity':Boolean(selected.quantity),'Show quantity label':Boolean(selected.quantity)});
 const commands=(selected?.actions||s.actions||[]).filter(a=>['commit','blocked','destructive'].includes(a.kind)).slice(0,2);
 const acts=horizontal(foot,'Selected object actions',CW,8);const specs=commands.length===2?[128,80,104]:commands.length===1?[216,104]:[328];
 commands.forEach((a,i)=>{const cell=auto(acts,'Action slot',specs[i]);legacySizedButton(cell,a,i===0?'primary':'secondary',s.id);PENDING_LINKS[PENDING_LINKS.length-1].itemContext=selected||s;});
 const detailCell=auto(acts,'Information action',specs[specs.length-1]);const detailButton=legacySizedButton(detailCell,{label:'Details',kind:'navigate'},'secondary',s.id);PENDING_LINKS[PENDING_LINKS.length-1].detail=selected||s;
 const footerY=H-16-foot.height;absolute(foot,16,footerY);
 const chrome=auto(p,'Bag chrome · compact',CW,'VERTICAL',6);chrome.x=16;chrome.y=188;quickbar(chrome,s,s.id);
 const identity=horizontal(chrome,'Container selection and capacity',CW,8);const toggle=auto(identity,'Bag / Gear',232);tabs(toggle,{tabs:['Bag','Gear'],selectedTab:'Bag'},s.id);const cap=text(identity,(s.keyFacts||[]).find(f=>f.kind==='capacity')?.value||'',88,'body','secondary','Bold');cap.textAlignHorizontal='RIGHT';
 tabs(chrome,s,s.id);const y=chrome.y+chrome.height+8;const body=scroll(p,'Bag grid · at least three visible rows',16,y,CW,Math.max(250,footerY-y-8));grid(body.content,s.gridItems||s.bagContents||[],s.id,{count:25});
};
gearScreen=function(p,s){if(!s.sourceHtml)return LEGACY_BASE.gearScreen(p,s);panel(p,172);const foot=bottom(p,s,s.id);const body=scroll(p,'Gear selected slot and owned candidates',16,188,CW,Math.max(100,foot.y-200));quickbar(body.content,s,s.id);legacyContainerTabs(body.content,s,'Gear');sectionTitle(body.content,'Equipped');const slots=(s.gearSlots?.length?s.gearSlots:s.slots||[]).map(legacyItem);const strip=horizontal(body.content,'Gear · six slots',CW,8);const roles=['Farming','Fishing','Mining','Combat','Ring','Charm'];
 for(let i=0;i<6;i++){const item=slots[i]||{title:'Empty',empty:true},role=item.slot||roles[i];const picked=item.selected||(!slots.some(x=>x.selected)&&i===1);const n=inst(strip,'LegacyGearSlot/'+(item.empty?'empty':picked?'selected':'default'),{Role:role,Title:item.empty?'Empty':item.title,Icon:legacyGlyph(item.icon||inferIcon(item))},48);n.name='Gear slot · '+role;
  const candidates=role==='Fishing'?(s.items||[]):item.empty?[]:[{title:item.title,state:'Equipped',icon:item.icon,effect:role==='Farming'?'Sows 1 plot per action':role==='Mining'?'1 rock per swing':role==='Combat'?'Attack 3':item.effect||''}];
  PENDING_LINKS.push({node:n,ownerId:s.id,detail:{title:role+' slot',state:item.empty?'Empty':'Owned gear',effect:item.empty?'No item equipped.':'',items:candidates,actions:[{label:'Close',kind:'dismiss'}]}});
 }
 const active=slots.find(x=>x.selected)?.slot||'Fishing';sectionTitle(body.content,active+' slot');for(const item of s.items||[])semanticRow(body.content,item,s.id);navAndDetails(body.content,s,s.id);
};
shop=function(p,s){if(!s.sourceHtml)return LEGACY_BASE.shop(p,s);panel(p,170);const selected=s.selectedItem;const actions=selected?.actions?.length?[...selected.actions,...(s.actions||[]).filter(a=>a.kind==='dismiss')]:s.actions;
 const purchase={...s,actions,keyFacts:[...(s.keyFacts||[]),...(selected?.keyFacts||[])],requirements:selected?.requirements||s.requirements};const foot=bottom(p,purchase,s.id);const body=scroll(p,'Shop · catalogue and own inventory',16,188,CW,Math.max(100,foot.y-200));heading(body.content,s);tabs(body.content,s,s.id);facts(body.content,(s.keyFacts||[]).filter(f=>f.kind!=='cost'));
 if(selected){sectionTitle(body.content,'Selected item');heading(body.content,selected);facts(body.content,selected.keyFacts);needs(body.content,selected.requirements,s.id);if(selected.disclosure?.length){const n=button(body.content,{label:'Item details',kind:'navigate'},'secondary',s.id);PENDING_LINKS[PENDING_LINKS.length-1].detail=selected;}}
 sectionTitle(body.content,'Catalogue');for(const item of s.items||[])semanticRow(body.content,item,s.id);sectionTitle(body.content,'Your Bag');grid(body.content,s.gridItems||s.bagContents||[],s.id,{count:25});navAndDetails(body.content,s,s.id);
};
