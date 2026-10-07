/* Same-item NPC outcomes and proven corrections to stale source illustrations.
 * Gameplay rules §5/6/9 override illustrative prices and gates in old §16 cards.
 * This adds prototype states only; no server transactions or original-page edits.
 */
const LEGACY_NPC_FLOW_BASE={wire};
function normalizeLegacyNpcFlowData(screens=BUNDLE.screens){
 const targets=new Set(['NPC-2','NPC-2-2','NPC-3','NPC-3-2','NPC-4','BAG-2','BAG-2-2','FARM-6','FARM-6-2','COOK-4','COOK-6']);
 for(const s of screens){if(!targets.has(s.id))continue;
  if(['NPC-2','NPC-3','NPC-3-2'].includes(s.id))for(const item of s.items||[]){
   if(item.title==='Sweet Potato Seeds'){item.state='Farming Lv5';item.requirements=[{label:'Farming',level:5}];item.actions=[{label:'Buy',kind:'blocked',feedback:'Farming Lv5 needed. Harvest crops to level up.'}];}
   if(item.title==="Fisher's Stew recipe"||item.title==='Sweet Potato Cakes'){item.title='Sweet Potato Cakes';item.state='Recipe Card · Legendary';item.effect='Reveals this regional recipe';item.icon='i-recipe-card';item.keyFacts=[{label:'Price',value:'500 coins',kind:'cost'},{label:'Stock',value:'1/1',kind:'capacity'}];item.requirements=[];const coins=Number(s.hud?.coins??230);item.actions=coins<500?[{label:'Buy',kind:'blocked',feedback:'Need '+(500-coins)+' more coins.'}]:[{label:'Buy',kind:'commit',target:null}];}
   if(item.title==='Orchard Feed'){item.state='Farming Lv7';item.effect='Next regrow time −50%';item.requirements=[{label:'Farming',level:7}];item.actions=[{label:'Buy',kind:'blocked',feedback:'Farming Lv7 needed. Harvest crops to level up.'}];}
  }
  if(s.id==='NPC-2-2'){
   for(const item of s.items||[]){if(item.title==='Reed Rod')item.actions=[{label:'Buy',kind:'commit',target:'NPC-REED-BOUGHT'}];if(item.title==='Spinner Lure'){item.state='Fishing Lv5';item.effect='Rare bites +15%';item.requirements=[{label:'Fishing',level:5}];item.actions=[{label:'Buy',kind:'blocked',feedback:'Fishing Lv5 needed. Catch fish to level up.'}];}}
   if(s.selectedItem?.title==='Pond Crucian')s.selectedItem.actions=[{label:'Sell one',kind:'commit',target:'NPC-CRUCIAN-SOLD-ONE'},{label:'Sell all',kind:'commit',target:'NPC-CRUCIAN-SOLD-ALL'}];
  }
  if(s.id==='NPC-3'){
   for(const f of s.keyFacts||[])if(/Buyback/.test(f.label))f.value='24/60';
   if(s.selectedItem?.title==='Sweet Potato'){s.selectedItem.keyFacts=[{label:'Each',value:'8 coins',kind:'reward'},{label:'Sell all',value:'96 coins',kind:'reward'}];s.selectedItem.actions=[{label:'Sell one',kind:'commit',target:'NPC-SWEET-POTATO-SOLD-ONE'},{label:'Sell all',kind:'blocked',feedback:'36 coins of regional buyback remain today. This stack sells for 96 coins. Sell fewer or sell at home.'}];}
  }
  if(s.id==='NPC-3-2'){for(const f of s.keyFacts||[])if(/Buyback|quota|limit/i.test(f.label))f.value='60/60';for(const item of [s.selectedItem,...(s.items||[])].filter(Boolean)){if(item.title==='Sweet Potato')item.keyFacts=(item.keyFacts||[]).map(f=>({...f,value:/^Each$/i.test(f.label)?'8 coins':/Sell all/i.test(f.label)?'96 coins':f.value}));}}
  if(s.id==='NPC-4')for(const item of s.items||[])if(item.title==='Dusk Haul')item.actions=(item.actions||[]).map(a=>a.label==='Track'?{...a,target:'NPC-DUSK-TRACKED'}:a);
  if(['FARM-6','FARM-6-2'].includes(s.id)){for(const item of s.items||[]){if(item.title==='Radish Seeds')item.actions=[{label:'Buy',kind:'commit',target:'STALL-RADISH-SEEDS-BOUGHT'}];if(item.title==='Compost'){item.state='Farming Lv3';item.requirements=[{label:'Farming',level:3}];item.actions=[{label:'Buy',kind:'blocked',feedback:'Farming Lv3 needed. Harvest crops to level up.'}];}}if(s.id==='FARM-6-2'){s.keyFacts=(s.keyFacts||[]).filter(f=>!/Buyback/i.test(f.label));if(s.selectedItem?.title==='Radish')s.selectedItem.actions=[{label:'Sell one',kind:'commit',target:'STALL-RADISH-SOLD-ONE'},{label:'Sell all',kind:'commit',target:'STALL-RADISH-SOLD-ALL'}];}}
  if(['COOK-4','COOK-6'].includes(s.id))s.actions=(s.actions||[]).map(a=>a.label==='Eat'?{...a,target:s.id==='COOK-4'?'COOK-FINE-EATEN':'COOK-MYSTERY-EATEN'}:a);
  if(s.id==='BAG-2')for(const item of s.items||[])if(item.title==='Reed Rod')item.actions=[{label:'Equip',kind:'commit',target:'GEAR-REED-EQUIPPED'}];
  if(s.id==='BAG-2-2')for(const item of s.items||[])if(item.title==='Timber'&&item.state==='Farm Storage')item.actions=[{label:'Take 10',kind:'commit',target:'STORAGE-TIMBER-TAKEN-10'},{label:'Take all',kind:'commit',target:'STORAGE-TIMBER-TAKEN-ALL'}];
 }
}
normalizeLegacyNpcFlowData();
function npcFlowDiscover(){LEDGER.npcFlowScreens=LEDGER.npcFlowScreens||{};for(const n of PAGE.children)if(n.type==='FRAME'&&n.name.startsWith('NPC state · '))LEDGER.npcFlowScreens[n.name.slice('NPC state · '.length).split(' · ')[0]]=n.id;}
function npcFlowFact(parent,f){const row=horizontal(parent,'Result fact · '+f.label,272,8);row.resize(272,24);row.counterAxisSizingMode='FIXED';polishText(row,f.label,164,11,'Bold','secondary');const value=polishText(row,String(f.value),100,12,'ExtraBold');value.textAlignHorizontal='RIGHT';return row;}
async function buildLegacyNpcFlowStates(){
 npcFlowDiscover();const created=[];for(const s of BUNDLE.npcFlowStates||[]){
  let sceneNode=LEDGER.npcFlowScreens[s.id+'/scene']?await figma.getNodeByIdAsync(LEDGER.npcFlowScreens[s.id+'/scene']):null;
  if(!sceneNode){sceneNode=overlayFrame('NPC result scene · '+s.id,H);sceneNode.name='NPC state · '+s.id+'/scene';sceneNode.cornerRadius=0;scene(sceneNode,s);hud(sceneNode,s);LEDGER.npcFlowScreens[s.id+'/scene']=sceneNode.id;created.push(sceneNode.id);}
  if(LEDGER.npcFlowScreens[s.id])continue;
  const n=overlayFrame('NPC outcome · '+s.id,H);n.name='NPC state · '+s.id+' · '+s.title;n.cornerRadius=0;scene(n,s);hud(n,s);const card=auto(n,'Compact/NPC transaction result',304,'VERTICAL',6,'surface');pad(card,16);radius(card,14);border(card);polishText(card,s.title,272,14,'ExtraBold');polishText(card,s.state,272,11,'Bold','secondary');if(s.quantity){const q=horizontal(card,'Result quantity',272,8);polishText(q,s.quantity.label,180,11,'Bold','secondary');const v=polishText(q,'×'+s.quantity.value,84,14,'ExtraBold');v.textAlignHorizontal='RIGHT';}polishText(card,s.effect,272,12,'Bold');for(const fact of s.keyFacts||[])npcFlowFact(card,fact);
  const done=inst(card,'Compact/Navigation',{Label:'Done'},272);PENDING_LINKS.push({node:done,ownerId:s.id,action:{label:'Done',kind:'dismiss',target:s.id+'/scene'}});absolute(card,28,Math.min(420,736-card.height));
  const note=text(PAGE,s.id+'\n'+s.sourceNote+'\nBefore → after: '+JSON.stringify(s.resultContext),360,'caption','secondary');note.name='NPC result proof · outside player viewport';note.x=n.x;note.y=n.y+H+12;created.push(n.id,note.id);LEDGER.npcFlowScreens[s.id]=n.id;LEDGER.sourceReferences[s.id]={newNodeId:n.id,layout:'native-npc-outcome',notInOriginalMainScreenCount:true,sourceRef:s.sourceRef};
 }
 return {createdNodeIds:created,npcFlowScreens:LEDGER.npcFlowScreens};
}
wire=async function(){
 await buildLegacyNpcFlowStates();const prior=new Map();for(const [key,id]of Object.entries(LEDGER.npcFlowScreens||{})){prior.set(key,LEDGER.screens[key]);LEDGER.screens[key]=id;}
 try{await LEGACY_NPC_FLOW_BASE.wire();}finally{for(const [key,value]of prior)if(value===undefined)delete LEDGER.screens[key];else LEDGER.screens[key]=value;}
 LEDGER.checks.npcFlowStates={states:Object.keys(LEDGER.npcFlowScreens||{}).filter(k=>!k.endsWith('/scene')).length,resultScenes:Object.keys(LEDGER.npcFlowScreens||{}).filter(k=>k.endsWith('/scene')).length,mainScreenCountPreserved:true};
};
