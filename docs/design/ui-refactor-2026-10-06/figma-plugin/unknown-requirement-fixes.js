/* Unknown inventory is neutral. MCP clone does not preserve parent/property
 * references, so attach the variant and rebind all fields to the existing owner. */
function requirementHasUnknownCount(q){return q.level===undefined&&q.need!==undefined&&q.need!==null&&(q.have===undefined||q.have===null);}
function requirementFields(main){const ring=main.findOne(n=>n.name==='Progress ring');return {ring,title:main.findOne(n=>n.type==='TEXT'&&n.name==='Title'),value:main.findOne(n=>n.type==='TEXT'&&n.name==='Value'),icon:ring?.children.find(n=>n.type==='INSTANCE')};}
function requirementCheckMaster(){
 const met=KIT['NeedTile/met'];if(!met||met.type!=='COMPONENT'||met.parent?.type!=='COMPONENT_SET')throw Error('Existing NeedTile variants required');const set=met.parent,base=requirementFields(met);
 const keys={Title:base.title?.componentPropertyReferences?.characters,Value:base.value?.componentPropertyReferences?.characters,Icon:base.icon?.componentPropertyReferences?.mainComponent};const definitions=set.componentPropertyDefinitions;
 for(const [name,key]of Object.entries(keys))if(!key||!definitions[key]||definitions[key].type!==(name==='Icon'?'INSTANCE_SWAP':'TEXT'))throw Error('Original NeedTile property missing: '+name);
 let check=KIT['NeedTile/check']||set.children.find(n=>n.type==='COMPONENT'&&n.name==='State=check');if(!check)check=met.clone();check.name='State=check';if(check.parent?.id!==set.id)set.appendChild(check);if(check.parent?.id!==set.id)throw Error('Neutral variant has wrong component-property owner');
 const fields=requirementFields(check);if(!fields.ring||!fields.title||!fields.value||!fields.icon)throw Error('Neutral NeedTile layers missing');
 fields.title.componentPropertyReferences={...fields.title.componentPropertyReferences,characters:keys.Title};fields.value.componentPropertyReferences={...fields.value.componentPropertyReferences,characters:keys.Value};fields.icon.componentPropertyReferences={...fields.icon.componentPropertyReferences,mainComponent:keys.Icon};
 border(fields.ring,'border',1);fill(fields.value,'secondary');fields.value.textAutoResize='HEIGHT';
 check.x=met.x;check.y=Math.max(...set.children.filter(n=>n.id!==check.id).map(n=>n.y+n.height))+20;set.resizeWithoutConstraints(Math.max(set.width,check.x+check.width+24),check.y+check.height+24);check.description='Owned quantity has not been checked. Configure Title, Value (Required ×N) and Icon; neutral style never implies that inventory meets the condition.';
 KIT['NeedTile/check']=check;LEDGER.components['NeedTile/check']=check.id;return check;
}
function neutralizeUnknownRequirement(tile,q){
 const master=requirementCheckMaster(),fields=requirementFields(master),keys={Title:fields.title.componentPropertyReferences.characters,Value:fields.value.componentPropertyReferences.characters,Icon:fields.icon.componentPropertyReferences.mainComponent};
 const iconRef=(q.icon&&ICON[q.icon]?.id)||q.iconComponentId;if(!iconRef)throw Error('Explicit requirement source icon is required; do not preserve an already incorrect swap');
 const reactions=JSON.parse(JSON.stringify(tile.reactions));tile.swapComponent(master);tile.name='NeedTile/check';tile.setProperties({[keys.Title]:q.title||q.label||'Requirement',[keys.Value]:'Required ×'+q.need,[keys.Icon]:iconRef});
 const actual=requirementFields(tile);if(actual.title.characters!==(q.title||q.label||'Requirement')||actual.value.characters!=='Required ×'+q.need||actual.icon.mainComponent?.id!==iconRef)throw Error('Neutral requirement property propagation failed');
 fill(actual.value,'secondary');border(actual.ring,'border',1);STYLE_JOBS.push(tile.setReactionsAsync(reactions));return tile;
}
const UNKNOWN_REQUIREMENT_PREVIOUS_NEEDS=needs;
needs=function(p,list,ownerId){const before=new Set(p.children.map(n=>n.id));UNKNOWN_REQUIREMENT_PREVIOUS_NEEDS(p,list,ownerId);if(!list?.some(requirementHasUnknownCount))return;const wrap=p.children.find(n=>!before.has(n.id)&&n.name==='Requirements');if(!wrap)return;const tiles=wrap.children.flatMap(row=>row.children.filter(n=>n.type==='INSTANCE'));list.forEach((q,index)=>{if(requirementHasUnknownCount(q)&&tiles[index])neutralizeUnknownRequirement(tiles[index],q);});};
