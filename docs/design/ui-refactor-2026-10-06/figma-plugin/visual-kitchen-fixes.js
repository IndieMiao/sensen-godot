/* Kitchen selection: retain the approved pot stage and drawer proportions.
 * Sources: COOK-2a/2b.html + kit-cook.css, 1080px divided by three.
 * Only COOK-2a, COOK-2b and COOK-P0-2 are intercepted.
 */
const KITCHEN_POLISH_BASE={library,hud,kitchen};
const KITCHEN_POLISH_IDS=new Set(['COOK-2a','COOK-2b','COOK-P0-2']);
function kitchenPolishText(p,value,w,size=12,weight='Bold',color='text',name='Label'){
  const n=figma.createText();n.name=name;n.fontName={family:T.font.family,style:weight};n.fontSize=size;n.lineHeight={unit:'PERCENT',value:125};n.characters=String(value??'');n.resize(w,size*1.25);n.textAutoResize='HEIGHT';fill(n,color);p.appendChild(n);const style=STYLE['compact/'+size+'/'+weight];if(style)STYLE_JOBS.push(n.setTextStyleIdAsync(style.id));return n;
}
function kitchenPolishProperty(c,p,name,value,w,size=12,weight='Bold',color='text'){
  const n=kitchenPolishText(p,value,w,size,weight,color,name);n.componentPropertyReferences={characters:c.addComponentProperty(name,'TEXT',String(value))};return n;
}
function kitchenPolishMaster(name,w,h){const c=component('Gensen Refactor/Compact/Kitchen/'+name,w);c.resize(w,h);c.layoutMode='NONE';c.clipsContent=false;register('Compact/Kitchen/'+name,c);return c;}
const KITCHEN_POLISH_FILTERS={
  'COOK-2a':{count:25,labels:['All','Can cook','Common','Fine','Rare','Legendary']},
  'COOK-2b':{count:20,labels:['All','Fish','Produce','Fruit','Seasoning']},
  'COOK-P0-2':{count:5,labels:['All','Fish','Produce','Fruit','Seasoning']}
};
async function kitchenPolishFilterVariables(){
  const collections=await figma.variables.getLocalVariableCollectionsAsync();let collection=collections.find(c=>c.name==='Gensen · Kitchen filters · Prototype');if(!collection)collection=figma.variables.createVariableCollection('Gensen · Kitchen filters · Prototype');
  const existing=await figma.variables.getLocalVariablesAsync();
  for(const [owner,config]of Object.entries(KITCHEN_POLISH_FILTERS)){
    const fields=[...config.labels.map(label=>['active/'+label,label==='All']),...Array.from({length:config.count},(_,i)=>['cell/'+i,true]),['empty',false]];
    for(const [field,value]of fields){const key='kitchen/'+owner+'/'+field;let variable=existing.find(v=>v.name===key&&v.variableCollectionId===collection.id);if(!variable){variable=figma.variables.createVariable(key,collection,'BOOLEAN');variable.setValueForMode(collection.defaultModeId,value);variable.description='Local kitchen category preview. Changes only visibility; never consumes ingredients or reveals an unknown recipe.';}variable.scopes=['ALL_SCOPES'];VAR[key]=variable;LEDGER.variables[key]=variable.id;}
  }
}
async function kitchenPolishLibrary(){
  await kitchenPolishFilterVariables();
  if(KIT['Compact/Kitchen/Preview'])return;
  for(const state of ['default','selected']){
    const c=kitchenPolishMaster('Mode/'+state,162,36);const pill=frame(c,'Mode pill',162,30,state==='selected'?'primary':'surface');radius(pill,15);border(pill,state==='selected'?'primary':'border',.6);absolute(pill,0,3);
    const title=kitchenPolishProperty(c,pill,'Title','Cookbook',116,13,'ExtraBold',state==='selected'?'surface':'secondary');title.textAlignHorizontal='CENTER';absolute(title,6,6);
    const count=kitchenPolishProperty(c,pill,'Count','4/48',34,10,'Bold',state==='selected'?'surface':'secondary');count.textAlignHorizontal='CENTER';absolute(count,124,9);cvisible(c,count,'Show count',true);
  }
  for(const state of ['filled','empty','locked']){
    const c=kitchenPolishMaster('Slot/'+state,90,50);const ring=frame(c,'Ingredient ring',32,32,state==='locked'?'border':'surface');radius(ring,16);border(ring,state==='filled'?'primary':'border',state==='filled'?1.2:.7);if(state!=='filled')ring.dashPattern=[2,2];absolute(ring,29,0);
    const art=cicon(c,ring,state==='locked'?'i-lock':state==='filled'?'i-fish':'i-question',20);absolute(art,6,6);
    const tag=frame(c,'Ingredient label',90,16,'surface');radius(tag,8);absolute(tag,0,34);const title=kitchenPolishProperty(c,tag,'Title',state==='locked'?'Cooking Lv4':'Pond Crucian',86,10,'Bold',state==='locked'?'secondary':'text');title.textAlignHorizontal='CENTER';absolute(title,2,2);
    const qty=frame(c,'Ingredient quantity',20,13,'primaryTint');radius(qty,6.5);absolute(qty,55,20);const amount=kitchenPolishProperty(c,qty,'Quantity','×1',20,10,'ExtraBold');amount.textAlignHorizontal='CENTER';absolute(amount,0,0);cvisible(c,qty,'Show quantity',state==='filled');
  }
  const preview=kitchenPolishMaster('Preview',292,26);fill(preview,'surface');radius(preview,13);border(preview,'border',.6);
  absolute(kitchenPolishProperty(preview,preview,'Title','Unknown dish',154,12,'ExtraBold'),10,5);
  absolute(kitchenPolishProperty(preview,preview,'State','Fine',58,11,'Bold','info'),170,6);
  absolute(kitchenPolishProperty(preview,preview,'Time','15 s',48,12,'ExtraBold'),234,5);
  const recipe=kitchenPolishMaster('Recipe',336,72);fill(recipe,'surface');border(recipe,'border',.6);radius(recipe,14);
  const medallion=frame(recipe,'Dish medallion',38,38,'primaryTint');radius(medallion,19);absolute(medallion,10,16);absolute(cicon(recipe,medallion,'i-dish-grilled',27),5.5,5.5);
  absolute(kitchenPolishProperty(recipe,recipe,'Title','Grilled Crucian',202,14,'ExtraBold'),58,9);
  absolute(kitchenPolishProperty(recipe,recipe,'State','Common',150,10,'Bold','secondary'),58,29);
  absolute(kitchenPolishProperty(recipe,recipe,'Effect','+20 Energy',142,12,'ExtraBold'),58,49);
  for(const state of ['default','selected','empty']){
    const c=kitchenPolishMaster('Cell/'+state,52,58);const face=frame(c,'Cell surface',52,52,'surface');radius(face,10);border(face,state==='selected'?'primary':'border',state==='selected'?1.5:.6);if(state==='empty'){face.dashPattern=[2,2];face.opacity=.55;}
    const art=cicon(c,face,'i-fish',27);absolute(art,12.5,8);cvisible(c,art,'Show icon',state!=='empty');
    const dot=figma.createEllipse();face.appendChild(dot);dot.name='Rarity dot';dot.resize(6,6);fill(dot,'#9DB89A');absolute(dot,4,4);cvisible(c,dot,'Show rarity',false);
    const qty=frame(face,'Quantity pill',24,13,'primaryTint');radius(qty,6.5);absolute(qty,25,37);const amount=kitchenPolishProperty(c,qty,'Quantity','',24,10,'ExtraBold');amount.textAlignHorizontal='CENTER';absolute(amount,0,0);cvisible(c,qty,'Show quantity',false);
    const caption=frame(c,'Cell state label',52,25,'surface');radius(caption,5);absolute(caption,0,31);const label=kitchenPolishProperty(c,caption,'State','Tasted',50,10,'Bold','secondary');label.textAlignHorizontal='CENTER';absolute(label,1,1);cvisible(c,caption,'Show state',false);
    const mark=frame(c,'Selected or cooked mark',13,13,'primary');radius(mark,6.5);absolute(mark,41,-2);absolute(icon(mark,'i-check',9),2,2);cvisible(c,mark,'Show mark',state==='selected');
  }
  for(const [family,states]of [['Mode',['default','selected']],['Slot',['filled','empty','locked']],['Cell',['default','selected','empty']]])variantSet('Compact/Kitchen/'+family,states.map(state=>{const c=KIT['Compact/Kitchen/'+family+'/'+state];c.name='State='+state;return c;}));
  LIBRARY.resize(1260,Math.max(libraryY+40,LIBRARY.height));
}
library=async function(){await KITCHEN_POLISH_BASE.library();await kitchenPolishLibrary();};
function polishedKitchenHud(p,s){
  const d={...(s.sceneState||{}),...(s.hud||{})},energy=Number(d.energy??142),capacity=Number(d.capacity??200);const n=inst(p,'Compact/HUD',{Energy:energy+'/'+capacity,Coins:String(d.coins??230),Recovery:energy>capacity?'Bonus +'+(energy-capacity):energy===capacity?'Full':d.recoveryText||'+1 in 2:40',Location:(d.city||'Shanghai')+' · Kitchen',Today:'Today · '+(['COOK-P0-2','TUT-3-07B'].includes(s.id)?'Cook your first fish':'Deliver 4 Fine fish')});absolute(n,10,18);
  for(const [label,x,y,w,target]of [['Profile',10,18,38,'PROFILE-1-P0'],['Energy',53,18,100,'ENERGY-P0-1'],['Inbox',314,18,36,'PARCEL-1'],['Today',10,62,170,'TODAY-1'],['Location',188,62,162,'MAP-2-FREE']]){const hit=frame(p,'HUD touch · '+label,w,44);absolute(hit,x,y);PENDING_LINKS.push({node:hit,ownerId:s.id,action:{label,target,kind:'navigate'}});}return n;
}
function kitchenPolishCamera(p){
  const art=p.children.find(n=>n.name.startsWith('Scene art ·'));if(!art)return;art.fills=[];art.clipsContent=true;
  const source=frame(art,'Approved kitchen camera · 1.85 scale',1024*1.85/3,1536*1.85/3);source.fills=[{type:'IMAGE',imageHash:BUNDLE.sceneHashes.kitchen,scaleMode:'FILL'}];absolute(source,-511/3,-499/3);
}
function kitchenPolishStage(p,s,book){
  const k=kitchenSpec(s),selected=book?[{title:'Pond Crucian',icon:'i-fish',quantity:{value:'1'}}]:k.selectedIngredients;
  for(const [index,item]of selected.entries()){const art=icon(p,item.icon||inferIcon(item),book?28:index?23:27);art.rotation=book?-10:index?10:-14;art.opacity=book?.55:1;absolute(art,book?166:index?185:155,book?175:index?171:176);art.name='Pot ingredient · '+item.title;}
  const slots=horizontal(p,'Compact/Kitchen stage ingredient slots',book?90:286,8);absolute(slots,book?135:37,239);
  const count=book?1:3;
  for(let i=0;i<count;i++){
    const item=selected[i],locked=!book&&i===2,kind=locked?'locked':item?'filled':'empty';const n=inst(slots,'Compact/Kitchen/Slot/'+kind,{Title:locked?'Cooking Lv4':item?.title||'Add ingredient',Quantity:item?'×'+item.quantity.value:'',Icon:(ICON[locked?'i-lock':item?.icon||inferIcon(item||{})]||ICON['i-question']).id,'Show quantity':Boolean(item)});n.name='Ingredient '+(i+1)+(locked?' · locked':item?' · selected':' · empty');
    if(!locked)PENDING_LINKS.push({node:n,ownerId:s.id,detail:item?{...item,state:book?'Recipe ingredient':'In pot',actions:book?[{label:'Close',kind:'dismiss'}]:[{label:'Remove',kind:'commit',target:null,context:{operation:'remove-ingredient',item:item.title,resultOnly:true},feedback:item.title+' removed from the pot.'},{label:'Close',kind:'dismiss'}]}:{title:'Choose ingredient',items:s.gridItems||s.items||[],actions:[{label:'Close',kind:'dismiss'}]}});
  }
  const known=book||s.id==='COOK-P0-2';const preview=inst(p,'Compact/Kitchen/Preview',{Title:known?'Ready to cook':'Unknown dish',State:known?'Common':'Fine',Time:known?'5 s':'15 s'});absolute(preview,34,292);
}
function kitchenPolishMatches(raw,label,index,book){
  if(label==='All')return true;const item=legacyItem(raw,index);if(item.empty)return false;
  // The source Cookbook marks its first five pages with the cookable check.
  if(book)return label==='Can cook'?index<5:raw.rarity===label.toLowerCase();
  const key=item.icon||'';const category=/fish|carp|minnow|koi/.test(key)?'Fish':/apple|fruit/.test(key)?'Fruit':/herb|salt/.test(key)?'Seasoning':'Produce';return category===label;
}
function kitchenPolishFilters(p,s,labels,y){
  const clip=frame(p,'Kitchen categories · horizontal scroll',336,36);absolute(clip,12,y);clip.clipsContent=true;clip.overflowDirection='HORIZONTAL';const row=horizontal(clip,'Compact/Kitchen categories',420,4),data=s.gridItems?.length?s.gridItems:s.bagContents?.length?s.bagContents:s.items||[],book=s.id==='COOK-2a';
  for(const label of labels){const width=Math.max(40,label.length*5.7+14),tab=frame(row,'Kitchen category · '+label,width,36);inst(tab,'Compact/Filter/default',{Label:label},width);const active=inst(tab,'Compact/Filter/selected',{Label:label},width);active.setBoundVariable('visible',VAR['kitchen/'+s.id+'/active/'+label]);
    const changes=[];for(const name of labels)changes.push({type:'SET_VARIABLE',variableId:VAR['kitchen/'+s.id+'/active/'+name].id,variableValue:{type:'BOOLEAN',resolvedType:'BOOLEAN',value:name===label}});
    for(let i=0;i<data.length;i++)changes.push({type:'SET_VARIABLE',variableId:VAR['kitchen/'+s.id+'/cell/'+i].id,variableValue:{type:'BOOLEAN',resolvedType:'BOOLEAN',value:kitchenPolishMatches(data[i],label,i,book)}});
    changes.push({type:'SET_VARIABLE',variableId:VAR['kitchen/'+s.id+'/empty'].id,variableValue:{type:'BOOLEAN',resolvedType:'BOOLEAN',value:!data.some((raw,i)=>kitchenPolishMatches(raw,label,i,book))}});
    STYLE_JOBS.push(tab.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:changes}]));
  }
  return clip;
}
function kitchenPolishGrid(p,s,book,y,height){
  const cells=[];const view=scroll(p,'Kitchen grid browser',12,y,336,height);const data=s.gridItems?.length?s.gridItems:s.bagContents?.length?s.bagContents:s.items||[];view.content.itemSpacing=6;view.content.paddingLeft=26;view.content.paddingRight=26;const row=auto(view.content,'Compact/Kitchen wrapping grid',284,'HORIZONTAL',6);row.layoutWrap='WRAP';row.primaryAxisSizingMode='FIXED';row.counterAxisSizingMode='AUTO';row.counterAxisSpacing=6;
  for(let i=0;i<data.length;i++){
    const raw=data[i],item=legacyItem(raw,i),classes=raw.sourceClasses||[],badges=raw.badges||[];const empty=item.empty,unknown=book&&(raw.state==='Unknown'||classes.includes('is-hidden')),off=badges.includes('Not for cooking')||classes.includes('is-off'),inPot=classes.includes('is-pot')||badges.includes('In the pot')||raw.state==='In pot';const selected=Boolean(item.selected||inPot);const caption=off?'Not for\ncooking':raw.state==='Tasted'?'Tasted':inPot?'In pot':badges.includes('Shop')?'Shop':'';
    const cellWrap=frame(row,'Kitchen cell wrapper · '+item.title,52,58);cellWrap.setBoundVariable('visible',VAR['kitchen/'+s.id+'/cell/'+i]);const cell=inst(cellWrap,'Compact/Kitchen/Cell/'+(empty?'empty':selected?'selected':'default'),{Icon:(ICON[item.icon]||ICON['i-question']).id,'Show icon':!empty,Quantity:item.quantity?'×'+item.quantity.value:'','Show quantity':!empty&&Boolean(item.quantity)&&!caption,State:caption,'Show state':Boolean(caption),'Show rarity':Boolean(raw.rarity)&&!empty,'Show mark':selected||classes.includes('is-cook')});cell.name='Kitchen cell · '+(unknown?'Unknown dish':item.title);cells.push({node:cell,wrap:cellWrap,item,raw,index:i});
    const dot=cell.findOne(n=>n.name==='Rarity dot');if(dot&&raw.rarity)fill(dot,{common:'#9DB89A',fine:'#6FA8DC',rare:'#A98BD6',legendary:'#E3B341'}[raw.rarity]||'#9DB89A');const art=cell.findOne(n=>n.type==='INSTANCE');if(art&&(unknown||off))art.opacity=off?.28:.4;
    if(empty)continue;if(off){PENDING_LINKS.push({node:cell,ownerId:s.id,action:{label:'Add ingredient',kind:'blocked',feedback:'This ornamental fish is not for cooking. Choose a food ingredient.'}});continue;}
    PENDING_LINKS.push({node:cell,ownerId:s.id,detail:unknown?{title:'Unknown dish',state:'Not discovered',effect:'Experiment to discover the recipe.',actions:[{label:'Experiment',kind:'navigate',target:'COOK-2b'},{label:'Close',kind:'dismiss'}]}:{...legacyDetails(item,s,i),actions:[{label:'Close',kind:'dismiss'}]}});
  }
  const empty=frame(p,'Compact/Kitchen filter empty state',284,60,'surface');absolute(empty,38,y+12);empty.setBoundVariable('visible',VAR['kitchen/'+s.id+'/empty']);const emptyText=kitchenPolishText(empty,book?'No matching recipes':'No matching ingredients',260,12,'Bold','secondary');emptyText.textAlignHorizontal='CENTER';absolute(emptyText,12,20);
  return {view,count:data.length,cells};
}
function polishedKitchenScreen(p,s){
  const book=s.id==='COOK-2a',p0=s.id==='COOK-P0-2';kitchenPolishCamera(p);kitchenPolishStage(p,s,book);
  const sheet=frame(p,'Compact/Kitchen drawer · source 60%',360,480,'surface');radius(sheet,20);sheet.topLeftRadius=20;sheet.topRightRadius=20;sheet.bottomLeftRadius=0;sheet.bottomRightRadius=0;absolute(sheet,0,320);sheet.fills=[solid('surface',.97)];
  const head=horizontal(p,'Compact/Kitchen heading',280,8);absolute(head,12,335);kitchenPolishText(head,'Stove 1',90,14,'ExtraBold');kitchenPolishText(head,'Empty',50,11,'Bold','secondary');kitchenPolishText(head,p0?'Cooking Lv1':'Cooking Lv2',110,11,'Bold','secondary');
  const close=frame(p,'Kitchen selection close · 44 px',44,44,'surface');radius(close,22);border(close,'border',.6);absolute(icon(close,'i-close',16),14,14);absolute(close,304,322);PENDING_LINKS.push({node:close,ownerId:s.id,action:{label:'Close',kind:'dismiss',target:p0?'COOK-P0-1':'COOK-1'}});
  const modes=horizontal(p,'Compact/Kitchen modes',336,12);absolute(modes,12,364);
  for(const label of ['Cookbook','Experiment']){const active=book?label==='Cookbook':label==='Experiment';const n=inst(modes,'Compact/Kitchen/Mode/'+(active?'selected':'default'),{Title:label,Count:p0?'1/48':'4/48','Show count':!p0&&label==='Cookbook'});if(!active)PENDING_LINKS.push({node:n,ownerId:s.id,action:{label,kind:'navigate',target:label==='Experiment'?'COOK-2b':p0?'TUT-3-07B':'COOK-2a'}});}
  let gridInfo;
  if(book){
    kitchenPolishFilters(p,s,['All','Can cook','Common','Fine','Rare','Legendary'],404);
    const chosen=s.items[0],wrap=frame(p,'Compact/Kitchen selected recipe',336,72);absolute(wrap,12,442);inst(wrap,'Compact/Kitchen/Recipe',{Title:chosen.title,State:chosen.state||'Common',Effect:'+20 Energy',Icon:ICON['i-dish-grilled'].id});
    const details=frame(wrap,'Recipe information · 44 px',232,44);absolute(details,0,0);PENDING_LINKS.push({node:details,ownerId:s.id,detail:{...chosen,actions:[{label:'Close',kind:'dismiss'}]}});
    const cook=inst(wrap,'Compact/Command',{Label:'Cook'},90);absolute(cook,238,28);PENDING_LINKS.push({node:cook,ownerId:s.id,action:chosen.actions.find(a=>a.kind==='commit'),itemContext:chosen});
    gridInfo=kitchenPolishGrid(p,s,true,522,262);
  }else{
    const label=horizontal(p,'Compact/Kitchen bag heading',336,8);absolute(label,12,414);kitchenPolishText(label,'From your bag',154,13,'ExtraBold');const count=kitchenPolishText(label,kitchenSpec(s).selectedIngredients.length+' / 2 slots used',170,11,'Bold','secondary');count.textAlignHorizontal='RIGHT';
    kitchenPolishFilters(p,s,['All','Fish','Produce','Fruit','Seasoning'],438);gridInfo=kitchenPolishGrid(p,s,false,482,250);
    const footer=frame(p,'Compact/Kitchen Cook decision',336,44);absolute(footer,12,742);kitchenPolishText(footer,p0?'Grilled Crucian\n+20 Energy':'Mystery dishes\nrestore 5 Energy',160,12,'Bold','secondary');const cook=inst(footer,'Compact/Command',{Label:'Cook'},164);absolute(cook,172,0);PENDING_LINKS.push({node:cook,ownerId:s.id,action:s.actions.find(a=>a.kind==='commit')});
  }
  LEDGER.sourceReferences[s.id]={...(LEDGER.sourceReferences[s.id]||{}),nativeCellCount:gridInfo.count,potCentre:[180,193.33],slotTop:239,previewTop:292,drawerTop:320,sourceCamera:{x:-511/3,y:-499/3,width:1024*1.85/3,height:1536*1.85/3},layout:'compact-kitchen-stage'};
}
hud=function(p,s){return KITCHEN_POLISH_IDS.has(s.id)?polishedKitchenHud(p,s):KITCHEN_POLISH_BASE.hud(p,s);};
kitchen=function(p,s){return KITCHEN_POLISH_IDS.has(s.id)?polishedKitchenScreen(p,s):KITCHEN_POLISH_BASE.kitchen(p,s);};
