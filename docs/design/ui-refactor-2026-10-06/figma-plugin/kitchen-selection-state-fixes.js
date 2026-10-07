/* Local ingredient selection only. Remove/add never changes owned quantities.
 * This prototype covers the two displayed ingredients, fish and Wild Herb.
 * Seasoning alone cannot cook (gameplay v2 §7.14.4 completeness table).
 */
const KITCHEN_PICK_BASE={library,kitchenPolishStage,kitchenPolishGrid,polishedKitchenScreen};
function kitchenPickValues(fish,herb){return {
  fish,herb,fishEmpty:!fish,herbEmpty:!herb,canCook:fish,blockedCook:!fish,
  title:fish?(herb?'Unknown dish':'Grilled Crucian'):(herb?'Add a main ingredient':'Choose ingredients'),
  state:fish?(herb?'Fine':'Common'):(herb?'No main':'Empty'),
  time:fish?(herb?'15 s':'5 s'):'—',benefit:fish&&!herb?'+20 Energy':'',used:(Number(fish)+Number(herb))+' / 2 slots used'
};}
function kitchenPickKey(id,field){return 'kitchen/'+id+'/pick/'+field;}
async function kitchenSelectionLibrary(){
  const collections=await figma.variables.getLocalVariableCollectionsAsync();let collection=collections.find(c=>c.name==='Gensen · Kitchen selection · Prototype');if(!collection)collection=figma.variables.createVariableCollection('Gensen · Kitchen selection · Prototype');const existing=await figma.variables.getLocalVariablesAsync();
  for(const id of ['COOK-2b','COOK-P0-2'])for(const [field,value]of Object.entries(kitchenPickValues(true,id==='COOK-2b'))){const key=kitchenPickKey(id,field);let v=existing.find(v=>v.name===key&&v.variableCollectionId===collection.id);if(!v){v=figma.variables.createVariable(key,collection,typeof value==='boolean'?'BOOLEAN':'STRING');v.setValueForMode(collection.defaultModeId,value);v.description='Ingredient selection preview only. Removing or restoring an ingredient never consumes owned inventory.';}v.scopes=typeof value==='boolean'?['ALL_SCOPES']:['TEXT_CONTENT'];VAR[key]=v;LEDGER.variables[key]=v.id;}
  const empty=KIT['Compact/Kitchen/Slot/empty'],ring=empty?.findOne(n=>n.name==='Ingredient ring');if(ring&&!ring.children.some(n=>n.name==='Add ingredient plus')){const glyph=ring.children.find(n=>n.type==='INSTANCE');if(glyph)glyph.visible=false;const plus=frame(ring,'Add ingredient plus',14,14);absolute(plus,9,9);const vertical=frame(plus,'Plus vertical',2,14,'secondary'),horizontal=frame(plus,'Plus horizontal',14,2,'secondary');absolute(vertical,6,0);absolute(horizontal,0,6);}
}
library=async function(){await KITCHEN_PICK_BASE.library();await kitchenSelectionLibrary();};
function kitchenPickVariable(id,field){return VAR[kitchenPickKey(id,field)];}
function kitchenPickSet(id,fish,herb){return Object.entries(kitchenPickValues(fish,herb)).map(([field,value])=>({type:'SET_VARIABLE',variableId:kitchenPickVariable(id,field).id,variableValue:{type:typeof value==='boolean'?'BOOLEAN':'STRING',resolvedType:typeof value==='boolean'?'BOOLEAN':'STRING',value}}));}
function kitchenPickCondition(id,field){return {type:'VARIABLE_ALIAS',resolvedType:'BOOLEAN',value:{type:'VARIABLE_ALIAS',id:kitchenPickVariable(id,field).id}};}
function kitchenPickCombination(id,fish,herb,useEmpty=false){
  const term=(field,wanted)=>{const alias=kitchenPickCondition(id,useEmpty?field+'Empty':field),positive=useEmpty?!wanted:wanted;return positive?alias:{type:'EXPRESSION',resolvedType:'BOOLEAN',value:{expressionFunction:'NOT',expressionArguments:[alias]}};};
  return {type:'EXPRESSION',resolvedType:'BOOLEAN',value:{expressionFunction:'AND',expressionArguments:[term('fish',fish),term('herb',herb)]}};
}
function kitchenPickBind(node,field,id,key){node.setBoundVariable(field,kitchenPickVariable(id,key));}
function kitchenPickReaction(node,id,field,remove=false){
  // MCP serializes a native condition as IF / ELSE. The grid adds an
  // ingredient idempotently; the explicit X on its pot slot removes it.
  const other=field==='fish'?'herb':'fish',next=otherValue=>kitchenPickSet(id,field==='fish'?!remove:otherValue,field==='herb'?!remove:otherValue);
  STYLE_JOBS.push(node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'CONDITIONAL',conditionalBlocks:[{condition:kitchenPickCondition(id,other),actions:next(true)},{actions:next(false)}]}]}]));
}
kitchenPolishStage=function(p,s,book){
  if(book)return KITCHEN_PICK_BASE.kitchenPolishStage(p,s,book);
  const ingredients=[{field:'fish',title:'Pond Crucian',icon:'i-fish',x:155,y:176},{field:'herb',title:'Wild Herb',icon:'i-herb',x:185,y:171}];
  for(const item of ingredients){const art=icon(p,item.icon,item.field==='fish'?27:23);art.name='Pot ingredient · '+item.title;art.rotation=item.field==='fish'?-14:10;absolute(art,item.x,item.y);kitchenPickBind(art,'visible',s.id,item.field);}
  const slots=horizontal(p,'Compact/Kitchen stage ingredient slots',286,8);absolute(slots,37,239);
  for(const [index,item]of ingredients.entries()){
    const wrap=frame(slots,'Ingredient choice · '+item.title,90,50);
    const filled=inst(wrap,'Compact/Kitchen/Slot/filled',{Title:item.title,Quantity:'×1',Icon:ICON[item.icon].id,'Show quantity':true});filled.name='Ingredient '+(index+1)+' · selected';kitchenPickBind(filled,'visible',s.id,item.field);kitchenPickReaction(filled,s.id,item.field,true);
    const empty=inst(wrap,'Compact/Kitchen/Slot/empty',{Title:'Add ingredient','Show quantity':false});empty.name='Ingredient '+(index+1)+' · empty';kitchenPickBind(empty,'visible',s.id,item.field+'Empty');
    const remove=frame(wrap,'Remove '+item.title,16,16,'text');radius(remove,8);absolute(remove,60,-4);const cross=kitchenPolishText(remove,'×',16,12,'ExtraBold','surface');cross.textAlignHorizontal='CENTER';absolute(cross,0,-1);kitchenPickBind(remove,'visible',s.id,item.field);kitchenPickReaction(remove,s.id,item.field,true);
  }
  inst(slots,'Compact/Kitchen/Slot/locked',{Title:'Cooking Lv4',Icon:ICON['i-lock'].id,'Show quantity':false});
  const initial=kitchenPickValues(true,s.id==='COOK-2b'),preview=inst(p,'Compact/Kitchen/Preview',{Title:initial.title,State:initial.state,Time:initial.time});absolute(preview,34,292);for(const [name,field]of [['Title','title'],['State','state'],['Time','time']]){const textNode=preview.findOne(n=>n.type==='TEXT'&&n.name===name);kitchenPickBind(textNode,'characters',s.id,field);}
};
kitchenPolishGrid=function(p,s,book,y,height){
  const before=PENDING_LINKS.length,result=KITCHEN_PICK_BASE.kitchenPolishGrid(p,s,book,y,height);if(book)return result;
  // Keep authored node/item pairs. MCP traversal order and proxy object
  // identity are not stable: neither may be used to recover a cell's item.
  for(const {node:cell,wrap,item}of result.cells){
    const field=item.icon==='i-fish'?'fish':item.icon==='i-herb'?'herb':null,zero=item.quantity&&Number(item.quantity.value)===0;
    const propertyValues=values=>{const activeKeys=cell.findAll(n=>Boolean(n.componentPropertyReferences)).flatMap(n=>Object.values(n.componentPropertyReferences)),keys=[...activeKeys,...Object.keys(cell.componentProperties||{})],out={};for(const [name,value]of Object.entries(values)){const key=keys.find(k=>k.split('#')[0]===name);if(key)out[key]=value;}cell.setProperties(out);};
    if(zero){propertyValues({Quantity:'','Show quantity':false,'Show state':true,State:'Not owned','Show mark':false});const art=cell.findOne(n=>n.type==='INSTANCE');if(art)art.opacity=.2;const face=cell.findOne(n=>n.name==='Cell surface');if(face){face.dashPattern=[2,2];border(face,'border',.6);}const link=PENDING_LINKS.slice(before).find(x=>x.node.id===cell.id);if(link){delete link.detail;link.action={label:'Add ingredient',kind:'blocked',feedback:'No '+item.title+' in your bag. Gather or buy it before adding it.'};}continue;}
    if(!field)continue;
    for(let i=PENDING_LINKS.length-1;i>=before;i--)if(PENDING_LINKS[i].node.id===cell.id)PENDING_LINKS.splice(i,1);
    propertyValues({Quantity:'','Show quantity':false,'Show state':!item.quantity,State:'In pot','Show mark':true});
    if(item.quantity){const owned=frame(wrap,'Compact/Kitchen owned quantity · '+item.title,24,13,'primaryTint');radius(owned,6.5);absolute(owned,25,37);const label=kitchenPolishText(owned,'×'+item.quantity.value,24,10,'ExtraBold','text','Quantity');label.textAlignHorizontal='CENTER';absolute(label,0,0);}
    kitchenPickReaction(cell,s.id,field);
    const face=cell.findOne(n=>n.name==='Cell surface');if(face)border(face,'border',.6);
    const selected=frame(wrap,'Selection border · '+item.title,52,52);selected.fills=[];radius(selected,10);border(selected,'primary',1.5);absolute(selected,0,0);kitchenPickBind(selected,'visible',s.id,field);kitchenPickReaction(selected,s.id,field);
    const mark=cell.findOne(n=>n.name==='Selected or cooked mark');if(mark)kitchenPickBind(mark,'visible',s.id,field);
    const caption=cell.findOne(n=>n.name==='Cell state label');if(caption&&!item.quantity)kitchenPickBind(caption,'visible',s.id,field);
  }return result;
};
polishedKitchenScreen=function(p,s){
  KITCHEN_PICK_BASE.polishedKitchenScreen(p,s);if(s.id==='COOK-2a')return;
  const used=p.findOne(n=>n.type==='TEXT'&&/\/ 2 slots used/.test(n.characters));if(used)kitchenPickBind(used,'characters',s.id,'used');
  const footer=p.findOne(n=>n.name==='Compact/Kitchen Cook decision');if(!footer)return;const left=footer.children.find(n=>n.type==='TEXT');if(left){left.visible=true;kitchenPickBind(left,'characters',s.id,'benefit');fill(left,'text');}
  const detail=inst(footer,'Compact/Navigation',{Label:'Info ›'},62);absolute(detail,98,0);PENDING_LINKS.push({node:detail,ownerId:s.id,detail:{title:'Experiment',effect:'Choose a main ingredient, then add a seasoning if you want.',disclosure:['Removing an ingredient before Cook does not use it.','An unmatched combination makes a Mystery Dish. At Cooking Lv1–2 it restores 5 Energy.'],actions:[{label:'Close',kind:'dismiss'}]}});
  const cook=footer.children.find(n=>n.type==='INSTANCE'&&n.mainComponent?.id===KIT['Compact/Command'].id);if(cook)kitchenPickBind(cook,'visible',s.id,'canCook');
  const blocked=frame(footer,'Cook · main ingredient required',164,44);absolute(blocked,172,0);const pill=frame(blocked,'Blocked Cook surface',164,34,'warningTint');radius(pill,17);absolute(pill,0,5);const label=kitchenPolishText(pill,'Cook',164,12,'ExtraBold','warning');label.textAlignHorizontal='CENTER';absolute(label,0,9);kitchenPickBind(blocked,'visible',s.id,'blockedCook');PENDING_LINKS.push({node:blocked,ownerId:s.id,action:{label:'Cook',kind:'blocked',feedback:'Add fish, produce or fruit. Seasoning cannot be cooked on its own.'}});
};
