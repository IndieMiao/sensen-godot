/* Pin is a UI preference for the §10.3 consumable allow-list, never a generic item action.
 * Append last. Local Pinned/Unpinned examples keep title, icon and quantity identical.
 */
const PIN_BASE={createDetail,wire};
const PIN_PAIRS=new Map();
function pinMode(item){
 if(!item||item.empty||item.title==='Empty')return null;const title=String(item.title||item.label||item.name||'').trim();
 if(/recipe|blueprint|\b(?:hoe|rod|pickaxe|sword|ring|charm|gloves|permit|ticket|dish|soup|stew)\b/i.test(title))return null;
 if(/\bseeds?\b|\bsapling\b|^Grapevine Cutting$|^Compost$|^Orchard Feed$/i.test(title))return 'Farming';
 if(/^(Worm Bait|Spinner Lure|Fish Trap)$/i.test(title))return 'Fishing';
 if(/^(Torch|Dynamite)$/i.test(title))return 'Mining';
 if(/^Healing Potion$/i.test(title))return 'Combat';return null;
}
function pinIdentity(item){const n=legacyItem(item);return {title:n.title,icon:item.icon&&item.icon!=='i-question'?item.icon:inferIcon({title:n.title}),quantity:n.quantity?{...n.quantity}:undefined,effect:item.effect||'',source:item.source||''};}
function pinOwner(item){if(pinMode(item))return item;if(item.selectedItem&&pinMode(item.selectedItem))return item.selectedItem;const chosen=(item.quickItems||item.quickContents||[]).find(x=>x.selected&&!x.empty);if(chosen&&pinMode(legacyItem(chosen)))return legacyItem(chosen);return null;}
function pinActions(owner){return (owner.actions||[]).flatMap(a=>{if(!/^(Pin|Unpin)$/.test(a.label||''))return [a];const item=pinOwner(owner);if(!item)return [];return [{...a,target:null,context:{...(a.context||{}),operation:'quickbar-pin',mode:pinMode(item),item:pinIdentity(item)}}];});}
function sanitizePins(value){if(!value||typeof value!=='object')return;if(Array.isArray(value)){value.forEach(sanitizePins);return;}if(Array.isArray(value.actions))value.actions=pinActions(value);for(const [key,child]of Object.entries(value))if(key!=='actions'&&key!=='original'&&key!=='originalVisibleText'&&typeof child==='object')sanitizePins(child);}
BUNDLE.screens.forEach(sanitizePins);
createDetail=function(detail,ownerId){return PIN_BASE.createDetail({...detail,actions:pinActions(detail)},ownerId);};
function localPinState(item,mode,pinned,ownerId){
 const o=overlayFrame(item.title+' · '+(pinned?'Pinned':'Unpinned'),290);const body=auto(o,'Same item pin preference',CW,'VERTICAL',12);body.x=16;body.y=16;
 heading(body,{title:item.title,state:pinned?'Pinned':'Unpinned',quantity:item.quantity,effect:mode+' Quick Bar'});
 const sample=horizontal(body,'Preserved item identity',CW,12);polishQuickSlot(sample,{...item,pinned},'default');
 text(sample,pinned?'Stays when this bar refills.':'This slot can refill automatically.',264,'caption','secondary');
 const toggle=button(body,{label:pinned?'Unpin':'Pin',kind:'commit',target:null},'primary',ownerId);PENDING_LINKS.pop();const close=button(body,{label:'Close',kind:'dismiss'},'secondary',ownerId);PENDING_LINKS.pop();
 o.resize(W,body.height+32);LEDGER.overlays[o.id]={title:item.title,ownerId,type:'local-pin-state',state:pinned?'Pinned':'Unpinned',mode,quantity:item.quantity?.value||null,resourceMutation:false};return {frame:o,toggle,close};
}
wire=async function(){
 await PIN_BASE.wire();
 const pins=PENDING_LINKS.filter(p=>/^(Pin|Unpin)$/.test(p.action?.label||''));let reactions=0;const fixed=new Set();
 for(const p of pins){const source=p.action.context?.item||p.itemContext;const item=source?pinIdentity(source):null;const mode=pinMode(item);if(!item||!mode){p.node.visible=false;continue;}
  const key=p.ownerId+'|'+mode+'|'+JSON.stringify(item);let pair=PIN_PAIRS.get(key);
  if(!pair){pair={off:localPinState(item,mode,false,p.ownerId),on:localPinState(item,mode,true,p.ownerId)};PIN_PAIRS.set(key,pair);
   await setReaction(pair.off.toggle,{type:'NODE',destinationId:pair.on.frame.id,navigation:'SWAP',transition:null});
   await setReaction(pair.on.toggle,{type:'NODE',destinationId:pair.off.frame.id,navigation:'SWAP',transition:null});
   await setReaction(pair.off.close,{type:'CLOSE'});await setReaction(pair.on.close,{type:'CLOSE'});reactions+=4;
  }
  const target=p.action.label==='Pin'?pair.on:pair.off;await setReaction(p.node,{type:'NODE',destinationId:target.frame.id,navigation:'OVERLAY',transition:null});reactions++;fixed.add(p.ownerId+'|'+p.action.label);
 }
 LEDGER.warnings=LEDGER.warnings.filter(w=>typeof w!=='object'||!fixed.has(w.screen+'|'+w.action));
 LEDGER.checks.prototypeReactions=(LEDGER.checks.prototypeReactions||0)+reactions;
 LEDGER.checks.pinPreference={eligibleModes:['Farming','Fishing','Mining','Combat'],sameItemPairs:PIN_PAIRS.size,resourceMutations:0,identityPreserved:true};
};
