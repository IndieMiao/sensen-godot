/* Composite overlay families, using native Figma Slots.
 * Outer FRAME IDs remain prototype targets. Slot insertion can re-key descendants;
 * after insertion do not traverse cached child handles in the same MCP call.
 * A separate native read must verify text/action semantics and new descendant IDs.
 * This module loads last, after the existing createDetail/wire adapters.
 */
const COMPONENT_FAMILY_BASE={wire};
const COMPONENT_FAMILY_KEYS={paragraph:'Information/Paragraph',information:'Overlay/InformationSheet',feedback:'Overlay/Feedback'};
const COMPONENT_FAMILY_RESULT={createdMasters:[],migrations:[],paragraphs:[],pendingNativeReadback:[]};
function componentFamilyClone(value){if(value===undefined||typeof value==='symbol')return undefined;const encoded=JSON.stringify(value);return encoded===undefined?undefined:JSON.parse(encoded);}
function componentFamilyPropertyValues(node){
 const values={};for(const [key,p]of Object.entries(node.componentProperties||{}))values[key]=p.boundVariables?.value||p.value;return values;
}
function componentFamilySetProperties(instance,values){
 const available=Object.keys(instance.componentProperties||{}),mapped={};
 for(const [key,value]of Object.entries(values)){const exact=available.includes(key)?key:available.find(k=>k.split('#')[0]===key.split('#')[0]);if(exact)mapped[exact]=value;}
 if(Object.keys(mapped).length)instance.setProperties(mapped);return mapped;
}
function componentFamilySetVisibleProperty(instance,name,value){const key=Object.keys(instance.componentProperties||{}).find(k=>k.split('#')[0]===name);if(!key)throw Error('Missing composite property '+name);instance.setProperties({[key]:value});}
async function componentFamilySpacing(){
 const collections=await figma.variables.getLocalVariableCollectionsAsync();let collection=collections.find(c=>c.id===VAR['space/page']?.variableCollectionId);
 if(!collection)collection=collections.find(c=>c.name==='Gensen · Overlay spacing')||figma.variables.createVariableCollection('Gensen · Overlay spacing');
 const existing=await figma.variables.getLocalVariablesAsync();
 for(const [name,value]of [['space/overlay-block',12],['space/overlay-body',8]]){let v=VAR[name]||existing.find(x=>x.name===name&&x.variableCollectionId===collection.id);if(!v){v=figma.variables.createVariable(name,collection,'FLOAT');v.setValueForMode(collection.defaultModeId,value);v.scopes=['GAP'];}VAR[name]=v;LEDGER.variables[name]=v.id;}
}
function componentFamilyMain(key,width){const n=component('Gensen Refactor/'+key,width);n.clipsContent=false;register(key,n);COMPONENT_FAMILY_RESULT.createdMasters.push(n.id);return n;}
async function componentFamilyEnsureLibrary(){
 await Promise.all(['Regular','Bold','ExtraBold'].map(style=>figma.loadFontAsync({family:T.font.family,style})));
 await componentFamilySpacing();
 if(!KIT[COMPONENT_FAMILY_KEYS.paragraph]){
  const p=componentFamilyMain(COMPONENT_FAMILY_KEYS.paragraph,CW);p.layoutMode='VERTICAL';p.primaryAxisSizingMode='AUTO';p.counterAxisSizingMode='FIXED';p.itemSpacing=0;pad(p,0);fill(p);
  const value=ctext(p,p,'Text','',CW,'body','text','Regular');value.layoutSizingHorizontal='FILL';value.textAutoResize='HEIGHT';
  p.description='Shared 14px regular information paragraph. Edit the Text property; wrapping height follows the content.';
 }
 if(!KIT[COMPONENT_FAMILY_KEYS.information]){
  const p=componentFamilyMain(COMPONENT_FAMILY_KEYS.information,W);p.layoutMode='VERTICAL';p.primaryAxisSizingMode='AUTO';p.counterAxisSizingMode='FIXED';pad(p,16);p.itemSpacing=12;p.setBoundVariable('itemSpacing',VAR['space/overlay-block']);
  // The absolute Sheet background did not follow HUG reliably in the live tool.
  // Use the same semantic surface/border/radius variables directly on the master.
  fill(p,'surface');border(p,'border');radius(p,'sheet');p.strokesIncludedInLayout=false;
  const header=inst(p,'ObjectHeader',{Title:'Information',State:'','Show state':false,Effect:'','Show effect':false,Quantity:'','Quantity label':'','Show quantity':false},CW);header.name='Header';header.isExposedInstance=true;
  const viewport=auto(p,'Body viewport',CW,'VERTICAL',0);pad(viewport,0);viewport.primaryAxisSizingMode='AUTO';viewport.counterAxisSizingMode='FIXED';viewport.maxHeight=440;viewport.clipsContent=true;viewport.overflowDirection='VERTICAL';cvisible(p,viewport,'Show body',true);
  if(typeof p.createSlot!=='function')throw Error('Native component Slots are required for InformationSheet');
  let slot=p.createSlot();slot.name='Content';viewport.appendChild(slot);
  slot=viewport.children.find(n=>n.type==='SLOT');if(!slot)throw Error('Content Slot was not created');slot.layoutMode='VERTICAL';slot.resize(CW,1);slot.primaryAxisSizingMode='AUTO';slot.counterAxisSizingMode='FIXED';pad(slot,0);slot.itemSpacing=8;slot.setBoundVariable('itemSpacing',VAR['space/overlay-body']);
  const slotKey=slot.componentPropertyReferences?.slotContentId||Object.keys(p.componentPropertyDefinitions).find(k=>p.componentPropertyDefinitions[k].type==='SLOT');
  if(slotKey)p.editComponentProperty(slotKey,{name:'Content',slotSettings:{displayEmptyByDefault:true,stretchChildOnInsert:true}});
  const close=inst(p,'Dismiss',{Label:'Close'},CW);close.name='Close';close.isExposedInstance=true;
  p.description='One shared information/context sheet: exposed ObjectHeader and Close properties plus arbitrary existing atomic rows in Content. Body viewport hugs short content and scrolls past440px. Item identity, count and actions are content, never variants.';
 }
 if(!KIT[COMPONENT_FAMILY_KEYS.feedback]){
  const p=componentFamilyMain(COMPONENT_FAMILY_KEYS.feedback,W);p.resize(W,H);p.layoutMode='NONE';fill(p);p.cornerRadius=0;
  const toast=inst(p,'Toast',{Message:''},CW);toast.name='Message';absolute(toast,16,H-176);toast.isExposedInstance=true;
  const close=inst(p,'Dismiss',{Label:'Got it'},CW);close.name='Close';absolute(close,16,H-80);close.isExposedInstance=true;
  p.description='Shared full-screen transparent feedback composition. Reuses Toast and Dismiss. The original outer frame retains its2.5-second timer and prototype target ID; close reactions remain per instance.';
 }
 await Promise.all(STYLE_JOBS);
 return {paragraph:KIT[COMPONENT_FAMILY_KEYS.paragraph],information:KIT[COMPONENT_FAMILY_KEYS.information],feedback:KIT[COMPONENT_FAMILY_KEYS.feedback]};
}
function componentFamilyRawParts(frame){
 if(frame.type!=='FRAME'||!frame.name.startsWith('Overlay · '))return null;
 if(frame.children.some(n=>n.type==='INSTANCE'&&Object.values(COMPONENT_FAMILY_KEYS).includes(n.name)))return null;
 const identity=frame.children.find(n=>n.name==='Detail identity'),viewport=frame.children.find(n=>n.name==='Detail body'),body=viewport?.children.find(n=>n.name==='Scrollable content');
 if(identity&&body){const header=identity.children.find(n=>n.type==='INSTANCE'),close=frame.children.find(n=>n.type==='INSTANCE'&&n.name==='Dismiss');if(header&&close)return {kind:'information',header,close,body,content:[...body.children],containers:[...frame.children]};}
 const pinBody=frame.children.find(n=>n.name==='Same item pin preference');
 if(pinBody){const header=pinBody.children.find(n=>n.type==='INSTANCE'&&n.name==='ObjectHeader'),close=pinBody.children.find(n=>n.type==='INSTANCE'&&/^Dismiss(?: · Close)?$/.test(n.name));if(header&&close)return {kind:'pin',header,close,body:pinBody,content:pinBody.children.filter(n=>n.id!==header.id&&n.id!==close.id),containers:[...frame.children]};}
 const toast=frame.children.find(n=>n.type==='INSTANCE'&&n.name==='Toast'),close=frame.children.find(n=>n.type==='INSTANCE'&&n.name==='Dismiss');
 if(toast&&close)return {kind:'feedback',toast,close,containers:[...frame.children]};return null;
}
function componentFamilySemanticSnapshot(frame){
 const texts=[],reactions=[];function visit(n,shown){const visible=shown&&n.visible!==false;if(n.type==='TEXT'&&visible)texts.push(n.characters);if('reactions'in n)for(const r of n.reactions||[])reactions.push(JSON.stringify(r));for(const child of n.children||[])visit(child,visible);}visit(frame,true);return {texts:texts.sort(),reactions:reactions.sort()};
}
function componentFamilyBindingSnapshot(node){return componentFamilyClone(node.boundVariables||{});}
async function componentFamilyApplyBindings(node,snapshot){
 for(const [field,value]of Object.entries(snapshot||{})){
  if(field==='componentProperties'||['fills','strokes','effects','layoutGrids','textRangeFills'].includes(field))continue;
  const aliases=Array.isArray(value)?value:[value];if(aliases.length!==1||aliases[0]?.type!=='VARIABLE_ALIAS')continue;
  const variable=await figma.variables.getVariableByIdAsync(aliases[0].id);if(variable)node.setBoundVariable(field,variable);
 }
}
function componentFamilyTextSnapshot(node){return {oldId:node.id,name:node.name,characters:node.characters,width:node.width,fontName:componentFamilyClone(node.fontName),fontSize:node.fontSize,textStyleId:typeof node.textStyleId==='string'?node.textStyleId:null,fills:componentFamilyClone(node.fills),textAlignHorizontal:node.textAlignHorizontal,hyperlink:componentFamilyClone(node.hyperlink),bindings:componentFamilyBindingSnapshot(node),reactions:componentFamilyClone(node.reactions||[])};}
async function componentFamilyParagraph(snapshot){
 const characterBinding=snapshot.bindings?.characters,alias=Array.isArray(characterBinding)?characterBinding[0]:characterBinding;
 const p=inst(PAGE,COMPONENT_FAMILY_KEYS.paragraph,{Text:alias?.type==='VARIABLE_ALIAS'?alias:snapshot.characters},CW);p.name='Information/Paragraph';const textNode=p.findOne(n=>n.type==='TEXT'&&n.name==='Text');if(!textNode)throw Error('Paragraph Text field missing');
 if(snapshot.fontName&&typeof snapshot.fontName==='object')await figma.loadFontAsync(snapshot.fontName);
 if(snapshot.textStyleId&&snapshot.textStyleId!==textNode.textStyleId)await textNode.setTextStyleIdAsync(snapshot.textStyleId);
 if(snapshot.fills)textNode.fills=snapshot.fills;if(snapshot.textAlignHorizontal)textNode.textAlignHorizontal=snapshot.textAlignHorizontal;if(snapshot.hyperlink)textNode.hyperlink=snapshot.hyperlink;
 const textBindings={...snapshot.bindings};if(alias?.type==='VARIABLE_ALIAS')delete textBindings.characters;await componentFamilyApplyBindings(textNode,textBindings);if(snapshot.reactions.length)await p.setReactionsAsync(snapshot.reactions);
 return p;
}
async function componentFamilyCopyInstance(target,snapshot){
 componentFamilySetProperties(target,snapshot.properties);await componentFamilyApplyBindings(target,snapshot.bindings);await target.setReactionsAsync(snapshot.reactions);
}
function componentFamilyInstanceSnapshot(n){return {id:n.id,properties:componentFamilyPropertyValues(n),bindings:componentFamilyBindingSnapshot(n),reactions:componentFamilyClone(n.reactions||[])};}
function componentFamilyNested(instance,names){return instance.children.find(n=>n.type==='INSTANCE'&&names.includes(n.name));}
function componentFamilyMakeOuter(frame,instance,fullScreen){
 // The wrapper is a stable prototype target, not a second visual skin.
 fill(frame);frame.strokes=[];frame.effects=[];for(const field of ['cornerRadius','topLeftRadius','topRightRadius','bottomLeftRadius','bottomRightRadius'])frame.setBoundVariable(field,null);frame.cornerRadius=0;
 if(fullScreen){frame.layoutMode='NONE';frame.resize(W,H);absolute(instance,0,0);}
 else{frame.layoutMode='VERTICAL';pad(frame,0);frame.itemSpacing=0;frame.resize(W,Math.max(1,instance.height));frame.primaryAxisSizingMode='AUTO';frame.counterAxisSizingMode='FIXED';instance.layoutSizingHorizontal='FILL';}
 frame.clipsContent=true;
}
async function componentFamilyMigrateFrame(frame,masters){
 const parts=componentFamilyRawParts(frame);if(!parts)return null;masters=masters||await componentFamilyEnsureLibrary();
 const before={semanticSnapshot:componentFamilySemanticSnapshot(frame),frameId:frame.id,name:frame.name,kind:parts.kind,outerReactions:componentFamilyClone(frame.reactions||[]),outerVariableModes:componentFamilyClone(frame.explicitVariableModes||{}),height:frame.height};
 const closeSnapshot=componentFamilyInstanceSnapshot(parts.close),moving=[],replacements=[];
 let instance;
 if(parts.kind==='feedback'){
  const toastSnapshot=componentFamilyInstanceSnapshot(parts.toast);instance=masters.feedback.createInstance();frame.appendChild(instance);instance.name=COMPONENT_FAMILY_KEYS.feedback;
  const toast=componentFamilyNested(instance,['Message','Toast']),close=componentFamilyNested(instance,['Close','Dismiss']);if(!toast||!close)throw Error('Feedback nested instances missing');
  await componentFamilyCopyInstance(toast,toastSnapshot);await componentFamilyCopyInstance(close,closeSnapshot);
 }else{
  const headerSnapshot=componentFamilyInstanceSnapshot(parts.header);
  // Snapshot all text data before any Slot append can invalidate node proxies.
  const descriptors=parts.content.map((node,index)=>({node,index,id:node.id,name:node.name,type:node.type,text:node.type==='TEXT'?componentFamilyTextSnapshot(node):null}));
  const prepared=[];for(const item of descriptors)prepared.push({...item,replacement:item.text?await componentFamilyParagraph(item.text):null});
  instance=masters.information.createInstance();frame.appendChild(instance);instance.name=COMPONENT_FAMILY_KEYS.information;
  // Hidden instance descendants may be absent from children in the live tool.
  componentFamilySetVisibleProperty(instance,'Show body',true);
  const header=componentFamilyNested(instance,['Header','Identity','ObjectHeader']),close=componentFamilyNested(instance,['Close','Dismiss']),viewport=instance.children.find(n=>n.name==='Body viewport');
  const slot=viewport?.children.find(n=>n.type==='SLOT');if(!header||!close||!slot)throw Error('InformationSheet exposed header, close or native Slot missing');
  await componentFamilyCopyInstance(header,headerSnapshot);await componentFamilyCopyInstance(close,closeSnapshot);
  if(!prepared.length)componentFamilySetVisibleProperty(instance,'Show body',false);
  for(const item of prepared){
   const content=item.replacement||item.node;const beforeId=content.id;slot.appendChild(content);
   moving.push({oldId:item.id,oldName:item.name,oldType:item.type,slotOrdinal:item.index,instanceIdBeforeSlot:beforeId});
   if(item.replacement){replacements.push({oldTextId:item.id,paragraphInstanceIdBeforeSlot:beforeId,slotOrdinal:item.index});item.node.remove();}
   // No traversal or post-append edit of content: descendants may have new IDs.
  }
 }
 for(const old of parts.containers)old.remove();componentFamilyMakeOuter(frame,instance,parts.kind==='feedback');
 const record={...before,componentKey:instance.name,instanceId:instance.id,movedContent:moving,paragraphReplacements:replacements,outerFrameIdPreserved:frame.id===before.frameId,descendantIdsRequireFreshRead:true,originalOuterReactionsRetained:JSON.stringify(frame.reactions||[])===JSON.stringify(before.outerReactions),originalVariableModesRetained:JSON.stringify(frame.explicitVariableModes||{})===JSON.stringify(before.outerVariableModes)};
 COMPONENT_FAMILY_RESULT.migrations.push(record);COMPONENT_FAMILY_RESULT.paragraphs.push(...replacements);COMPONENT_FAMILY_RESULT.pendingNativeReadback.push(frame.id);
 if(LEDGER.overlays[frame.id])Object.assign(LEDGER.overlays[frame.id],{componentFamily:record.componentKey,componentInstanceId:instance.id,prototypeTargetIdPreserved:true});
 return record;
}
async function componentFamilyComposeAll(){
 const frames=PAGE.findAllWithCriteria({types:['FRAME']}).filter(n=>componentFamilyRawParts(n));if(!frames.length)return COMPONENT_FAMILY_RESULT;
 const masters=await componentFamilyEnsureLibrary();for(const frame of frames)await componentFamilyMigrateFrame(frame,masters);
 const records=COMPONENT_FAMILY_RESULT.migrations;LEDGER.componentFamilyMigrations=records;LEDGER.checks.componentFamilies={informationAndContext:records.filter(x=>x.kind!=='feedback').length,information:records.filter(x=>x.kind==='information').length,pinContext:records.filter(x=>x.kind==='pin').length,feedback:records.filter(x=>x.kind==='feedback').length,paragraphInstances:COMPONENT_FAMILY_RESULT.paragraphs.length,sharedMasters:Object.fromEntries(Object.entries(masters).map(([key,n])=>[key,n.id])),outerPrototypeTargetsPreserved:records.every(x=>x.outerFrameIdPreserved&&x.originalOuterReactionsRetained&&x.originalVariableModesRetained),nativeSemanticReadbackRequired:true};
 return COMPONENT_FAMILY_RESULT;
}
wire=async function(){await COMPONENT_FAMILY_BASE.wire();await componentFamilyComposeAll();await Promise.all(STYLE_JOBS);};
