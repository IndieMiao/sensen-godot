const page=await figma.getNodeByIdAsync('481:53');await figma.setCurrentPageAsync(page);figma.skipInvisibleInstanceChildren=true;
function digest(v){const s=JSON.stringify(v);let h=2166136261,j=5381;for(let i=0;i<s.length;i++){h=Math.imul(h^s.charCodeAt(i),16777619);j=Math.imul(j,33)^s.charCodeAt(i);}return (h>>>0).toString(16)+'-'+(j>>>0).toString(16)+'-'+s.length;}
function visible(n){for(let a=n;a&&a!==page;a=a.parent)if('visible'in a&&a.visible===false)return false;return true;}
const issues=[],rows=[],masters={},bodyInstances={},nativeParagraphs=[];
for(const before of BASELINE){const n=await figma.getNodeByIdAsync(before.id);if(!n){issues.push([before.id,'missing']);continue;}
 const text=n.findAllWithCriteria({types:['TEXT']}).filter(visible).map(n=>n.characters).sort();const acts=[n,...n.findAll(x=>'reactions'in x&&x.reactions.length)].filter(x=>'reactions'in x&&x.reactions.length).map(x=>JSON.stringify(x.reactions)).sort();
 const expectedText=before.beforeTextHash||digest(before.beforeText),expectedActions=before.beforeActionHash||digest(before.beforeActions);
 if(digest(text)!==expectedText)issues.push([before.id,'text-mismatch',expectedText,digest(text),text]);if(digest(acts)!==expectedActions)issues.push([before.id,'actions-mismatch',expectedActions,digest(acts),acts]);
 const direct=n.children.filter(x=>x.type==='INSTANCE');if(direct.length!==1||!['932:71686','932:71702'].includes(direct[0].mainComponent?.id))issues.push([before.id,'not shared composition']);else masters[direct[0].mainComponent.id]=(masters[direct[0].mainComponent.id]||0)+1;
 const slot=n.findOne(x=>x.type==='SLOT');if(slot)for(const x of slot.children){if(x.type==='TEXT')nativeParagraphs.push(x.id);if(x.type==='INSTANCE')bodyInstances[x.mainComponent?.id]=(bodyInstances[x.mainComponent?.id]||0)+1;}
 rows.push([n.id,n.height,text.length,acts.length]);
}
return {checked:rows.length,masters,bodyInstances,nativeParagraphs,rows,issues};
