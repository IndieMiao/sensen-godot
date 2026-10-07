/* Grid-first kitchen selectors, scoped to the three visually audited screens.
 * Append after kitchen-scene-fixes.js. Does not alter entrance or heat layouts.
 */
const KITCHEN_SELECTION_BASE={library,kitchen,buildScreen};
const KITCHEN_SELECTION_IDS=new Set(['COOK-2a','COOK-2b','COOK-P0-2']);
library=async function(){
  await KITCHEN_SELECTION_BASE.library();
  if(!ICON['i-lock']&&BUNDLE.iconSvgs['i-lock']){
    const c=component('Gensen Refactor/Icon/i-lock',64);c.resize(64,64);c.primaryAxisSizingMode='FIXED';
    const source=figma.createNodeFromSvg(BUNDLE.iconSvgs['i-lock']);c.appendChild(source);source.resize(64,64);source.x=0;source.y=0;
    register('Icon/i-lock',c);ICON['i-lock']=c;
  }
};
function kitchenSelectionMetric(p,label,value,width){
  const n=inst(p,'Fact',{Label:label,Value:value},width);
  const labelNode=n.findOne(x=>x.type==='TEXT'&&x.name==='Label');
  const valueNode=n.findOne(x=>x.type==='TEXT'&&x.name==='Value');
  const valueWidth=Math.max(62,Math.floor(width*.56));
  if(labelNode){labelNode.resize(width-valueWidth-8,labelNode.height);labelNode.textAutoResize='HEIGHT';}
  if(valueNode){valueNode.resize(valueWidth,valueNode.height);valueNode.textAutoResize='HEIGHT';}
  return n;
}
function kitchenSelectionItem(raw,index){
  const item=typeof legacyItem==='function'?legacyItem(raw,index):raw;
  return {...item,icon:item.icon||inferIcon(item),empty:item.empty||item.title==='Empty'};
}
function kitchenSelectionGrid(p,s,data){
  const rows=auto(p,'Source grid · five columns',CW,'VERTICAL',8);
  const width=(CW-32)/5;
  for(let start=0;start<data.length;start+=5){
    const rr=horizontal(rows,'Source inventory row '+(start/5+1),CW,8);
    for(let i=start;i<Math.min(start+5,data.length);i++){
      const raw=data[i],item=kitchenSelectionItem(raw,i),badges=raw.badges||[];
      const notCookable=badges.includes('Not for cooking')||raw.sourceClasses?.includes('is-off')&&raw.icon==='i-koi';
      const unknownRecipe=s.id==='COOK-2a'&&raw.state==='Unknown';
      const inPot=raw.sourceClasses?.includes('is-pot')||badges.includes('In the pot')||raw.state==='In pot';
      const state=notCookable?'Not for\ncooking':unknownRecipe?'Unknown':raw.state==='Discovered'?'':raw.state==='Silhouette'?'Unavailable':inPot?'In pot':raw.state||'';
      const iconKey=unknownRecipe?'i-question':item.icon;
      const selected=Boolean(item.selected||inPot);
      const cell=inst(rr,'LegacyInventoryCell/'+(item.empty?'empty':selected?'selected':'default'),{Title:unknownRecipe?'Unknown dish':item.title,Icon:(ICON[iconKey]||ICON['i-question']).id,Quantity:item.quantity?.value||'','Show quantity':!item.empty&&Boolean(item.quantity),'Show icon':!item.empty,State:state,'Show state':Boolean(state)&&!item.empty,'Show rarity':Boolean(raw.rarity)&&!item.empty},width);
      cell.name='Inventory cell · '+(unknownRecipe?'Unknown dish':item.title);
      const dot=cell.findOne(x=>x.name==='Rarity dot');if(dot&&raw.rarity){const colors={common:'#9AB69B',fine:'#6FA8DC',rare:'#AA8BD3',legendary:'#E3B341'};dot.fills=[solid(colors[raw.rarity]||'#9AB69B')];}
      if(notCookable){const glyph=cell.findOne(x=>x.type==='INSTANCE');if(glyph)glyph.opacity=.35;PENDING_LINKS.push({node:cell,ownerId:s.id,action:{label:'Add ingredient',kind:'blocked',target:null,feedback:'This ornamental fish is not for cooking. Choose a food ingredient.'}});continue;}
      if(item.empty)continue;
      const detail=unknownRecipe?{title:'Unknown dish',state:'Not discovered',effect:'Experiment to discover this recipe.',actions:[{label:'Experiment',kind:'navigate',target:'COOK-2b'},{label:'Close',kind:'dismiss'}]}:typeof legacyDetails==='function'&&s.sourceHtml?legacyDetails(item,s,i):item;
      PENDING_LINKS.push({node:cell,ownerId:s.id,detail:{...detail,actions:detail.actions?.length?detail.actions:[{label:'Close',kind:'dismiss'}]}});
    }
  }
  return rows;
}
function kitchenSelectionSlots(p,s,k){
  const count=horizontal(p,'Ingredient capacity',CW,8);text(count,'In the pot',230,'body','text','Bold');const amount=text(count,k.selectedIngredients.length+'/'+k.ingredientSlots,90,'body','text','ExtraBold');amount.textAlignHorizontal='RIGHT';
  const row=horizontal(p,'Ingredient slots',CW,10);
  for(let i=0;i<k.ingredientSlots;i++){
    const item=k.selectedIngredients[i];const key=item?.icon||inferIcon(item||{});
    const n=inst(row,item?'IngredientSlot/filled':'IngredientSlot/empty',{Title:item?.title||'Add ingredient',Quantity:item?'×'+item.quantity.value:'+',Icon:(ICON[key]||ICON['i-question']).id},(CW-20)/3);
    n.name='Ingredient '+(i+1)+(item?' · selected':' · empty');
    PENDING_LINKS.push({node:n,ownerId:s.id,detail:item?{...item,state:'In pot',actions:[{label:'Remove',kind:'commit',target:null,context:{operation:'remove-ingredient',item:item.title,resultOnly:true},feedback:item.title+' removed from the pot.'},{label:'Close',kind:'dismiss'}]}:{title:'Choose ingredient',state:'Available ingredients',items:s.gridItems||s.items||[],actions:[{label:'Close',kind:'dismiss'}]}});
  }
  const lock=inst(row,'IngredientSlot/locked',{Title:'Third slot',Quantity:'Cooking Lv4',Icon:(ICON['i-lock']||ICON['i-question']).id},(CW-20)/3);lock.name='Third ingredient slot · locked';
  if(!ICON['i-lock']){const glyph=lock.findOne(n=>n.type==='INSTANCE');if(glyph)glyph.visible=false;}
}
function kitchenSelectionFooter(p,s,book){
  const f=auto(p,'Kitchen selection decision',CW,'VERTICAL',8,'surface');
  const chosen=book?s.items[0]:s.id==='COOK-P0-2'?{title:'Grilled Crucian',state:'Common'}:{title:'Unknown dish',state:'Fine'};
  const summary=inst(f,'LegacySelectedSummary',{Title:chosen.title,State:chosen.state||'Common',Effect:book?'Base recovery +20 Energy':'','Show effect':book,'Show state':true,Quantity:'1','Quantity label':'portion','Show quantity':true,'Show quantity label':true});
  if(!book){summary.resize(CW,48);summary.primaryAxisSizingMode='FIXED';}
  const time=s.id==='COOK-2b'?'15 s':'5 s';
  if(book){
    const spend=horizontal(f,'Recipe spend and duration',CW,16);spend.counterAxisAlignItems='CENTER';
    for(const req of chosen.requirements||[]){const label=req.title||req.label,short=req.have<req.need;inst(spend,short?'NeedTile/short':'NeedTile/met',{Title:label,Value:req.have+'/'+req.need,Icon:(ICON[req.icon]||ICON[inferIcon({title:label})]).id},104);}
    const remaining=CW-Math.min(1,(chosen.requirements||[]).length)*120;
    const metrics=auto(spend,'Recipe metrics',remaining,'VERTICAL',4);kitchenSelectionMetric(metrics,'Cook time',time,remaining);
  }else{
    const metrics=horizontal(f,'Cooking result preview',CW,12);
    kitchenSelectionMetric(metrics,'Cook time',time,s.id==='COOK-P0-2'?158:CW);
    if(s.id==='COOK-P0-2')kitchenSelectionMetric(metrics,'Recovery','+20 Energy',158);
  }
  const cook=book?(chosen.actions||[]).find(a=>a.kind==='commit'):(s.actions||[]).find(a=>a.kind==='commit');
  if(cook)button(f,cook,'primary',s.id);
  absolute(f,16,H-16-f.height);
  return f;
}
kitchen=function(p,s){
  if(!KITCHEN_SELECTION_IDS.has(s.id)){KITCHEN_SELECTION_BASE.kitchen(p,s);return;}
  const book=s.id==='COOK-2a',k=kitchenSpec(s);
  panel(p,196);
  const footer=kitchenSelectionFooter(p,s,book);
  const chrome=auto(p,'Kitchen selection chrome',CW,'VERTICAL',8);absolute(chrome,16,212);
  const identity=horizontal(chrome,'Selected stove identity',CW,8);text(identity,'Stove 1',230,'title','text','ExtraBold');const status=text(identity,'Empty',90,'caption','secondary','Bold');status.textAlignHorizontal='RIGHT';
  const modeRow=horizontal(chrome,'Kitchen mode tabs',CW,8);
  for(const label of ['Cookbook','Experiment']){const selected=label===(book?'Cookbook':'Experiment');const tab=inst(modeRow,'Tab',{Label:label},160);tab.counterAxisAlignItems='CENTER';if(!selected)fill(tab);tab.name='Kitchen mode · '+label;if(!selected)PENDING_LINKS.push({node:tab,ownerId:s.id,action:{label,kind:'navigate',target:label==='Experiment'?'COOK-2b':s.sourceHtml?'COOK-2a':'TUT-3-07B'}});}
  if(!book){kitchenSelectionSlots(chrome,s,k);sectionTitle(chrome,'Available ingredients');}
  const top=chrome.y+chrome.height+12;
  const browser=scroll(p,'Kitchen grid browser',16,top,CW,Math.max(164,footer.y-top-12));
  const data=s.gridItems?.length?s.gridItems:s.bagContents?.length?s.bagContents:s.items||[];
  kitchenSelectionGrid(browser.content,s,data);
  // One consistent close control; remove the legacy bottom Close row to preserve browsing height.
  const close=inst(p,'Close');absolute(close,300,146);close.name='Kitchen selection close · 44 px';PENDING_LINKS.push({node:close,ownerId:s.id,action:{label:'Close',kind:'dismiss',target:s.sourceHtml?'COOK-1':'COOK-P0-1'}});
  // Secondary recipe/XP/clue information is available from the selected summary, not repeated next to Cook.
  const summary=footer.findOne(n=>n.type==='INSTANCE'&&n.mainComponent?.id===KIT.LegacySelectedSummary.id);
  if(summary){const chosen=book?s.items[0]:s.id==='COOK-P0-2'?{title:s.title,keyFacts:s.keyFacts,disclosure:s.disclosure}:{title:'Unknown dish',state:'Fine',disclosure:['The recipe is revealed after cooking.','Mystery dishes still restore 5 Energy.']};PENDING_LINKS.push({node:summary,ownerId:s.id,detail:{...chosen,actions:[{label:'Close',kind:'dismiss'}]}});}
  LEDGER.sourceReferences[s.id]={...(LEDGER.sourceReferences[s.id]||{}),selectionGridCount:data.length,selectionLayout:'Grid first; selected result and spend remain above Cook.'};
};

buildScreen=function(s,index){
  if(KITCHEN_SELECTION_IDS.has(s.id))return KITCHEN_SELECTION_BASE.buildScreen({...s,presentation:{...(s.presentation||{}),close:false}},index);
  return KITCHEN_SELECTION_BASE.buildScreen(s,index);
};
