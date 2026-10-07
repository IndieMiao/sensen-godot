const MODE='info',START=360,END=392;
const page=await figma.getNodeByIdAsync('481:53');await figma.setCurrentPageAsync(page);figma.skipInvisibleInstanceChildren=false;
const section=await figma.getNodeByIdAsync(MODE==='feedback'?'920:71416':MODE==='pin'?'920:71415':'920:71414');
const roots=section.children.filter(n=>n.type==='FRAME'&&(MODE!=='pin'||n.children.some(x=>x.name==='Same item pin preference'))).slice(START,END);
const master=await figma.getNodeByIdAsync(MODE==='feedback'?'932:71702':'932:71686'),paragraph=await figma.getNodeByIdAsync('932:71684');
const created=[],mutated=new Set(),removed=[],mappings={},rows=[],failures=[];
const fonts=new Map();for(const r of roots)for(const t of r.findAll(n=>n.type==='TEXT'))for(const s of t.getStyledTextSegments(['fontName']))fonts.set(JSON.stringify(s.fontName),s.fontName);for(const f of fonts.values())await figma.loadFontAsync(f);
function digest(v){const s=JSON.stringify(v);let h=2166136261,j=5381;for(let i=0;i<s.length;i++){h=Math.imul(h^s.charCodeAt(i),16777619);j=Math.imul(j,33)^s.charCodeAt(i);}return (h>>>0).toString(16)+'-'+(j>>>0).toString(16)+'-'+s.length;}
function props(n){return Object.fromEntries(Object.entries(n.componentProperties||{}).map(([k,v])=>[k.split('#')[0],v.value]));}
function setp(n,data){const keys=Object.keys(n.componentProperties),v={};for(const[k,value]of Object.entries(data)){const key=keys.find(a=>a.split('#')[0]===k);if(key&&value!==undefined)v[key]=value;}n.setProperties(v);}
function visibleTexts(root){const a=[];function walk(n,on){if(!on||n.visible===false)return;if(n.type==='TEXT')a.push(n.characters);if('children'in n)for(const c of n.children)walk(c,true);}walk(root,true);return a.sort();}
function reactions(root){return [root,...root.findAll(()=>true)].filter(n=>'reactions'in n&&n.reactions.length).map(n=>JSON.stringify(n.reactions)).sort();}
function remember(old,newNode){mappings[old.id]=newNode.id;}
async function paragraphize(t){
 const n=paragraph.createInstance();created.push(n.id);setp(n,{Text:t.characters});n.name='Paragraph';n.resize(t.width,n.height);const inner=n.findOne(x=>x.type==='TEXT');inner.resize(t.width,inner.height);inner.textAutoResize='HEIGHT';
 if(t.hyperlink)inner.hyperlink=t.hyperlink;if(t.boundVariables?.characters){const v=await figma.variables.getVariableByIdAsync(t.boundVariables.characters.id);if(v)inner.setBoundVariable('characters',v);}
 await inner.setReactionsAsync(t.reactions);remember(t,inner);return n;
}
for(const root of roots){
 if(root.children.some(n=>n.type==='INSTANCE'&&n.mainComponent?.id===master.id)){rows.push({id:root.id,alreadyMigrated:true});continue;}
 const oldChildren=[...root.children],before={height:root.height,text:visibleTexts(root),actions:reactions(root),rootActions:JSON.stringify(root.reactions)};
 const shared=master.createInstance();created.push(shared.id);root.appendChild(shared);shared.name=MODE==='feedback'?'Feedback · shared instance':MODE==='pin'?'Context menu · shared information sheet':'Information sheet · shared instance';
 if(MODE==='feedback'){
  const oldToast=oldChildren.find(n=>n.type==='INSTANCE'&&n.name==='Toast'),oldClose=oldChildren.find(n=>n.type==='INSTANCE'&&n.name==='Dismiss');if(!oldToast||!oldClose)throw Error('Unexpected feedback '+root.id);
  const target=shared.children.find(n=>n.name==='Message'),close=shared.children.find(n=>n.name==='Dismiss');setp(target,props(oldToast));setp(close,props(oldClose));await target.setReactionsAsync(oldToast.reactions);await close.setReactionsAsync(oldClose.reactions);remember(oldToast,target);remember(oldClose,close);
  shared.x=0;shared.y=0;shared.resize(360,800);
 }else{
  const oldLayout=MODE==='pin'?oldChildren.find(n=>n.name==='Same item pin preference'):null;
  const oldIdentity=MODE==='pin'?oldLayout.children.find(n=>n.type==='INSTANCE'&&n.name==='ObjectHeader'):oldChildren.find(n=>n.name==='Detail identity')?.children.find(n=>n.type==='INSTANCE');
  const oldClose=MODE==='pin'?oldLayout.children.find(n=>n.type==='INSTANCE'&&n.name.startsWith('Dismiss')):oldChildren.find(n=>n.name==='Dismiss');
  const oldViewport=MODE==='pin'?null:oldChildren.find(n=>n.name==='Detail body'),oldBody=oldViewport?.children.find(n=>n.name==='Scrollable content');
  if(!oldIdentity||!oldClose||MODE!=='pin'&&!oldBody)throw Error('Unexpected information structure '+root.id);
  setp(shared,{'Show body':true});
  const hi=shared.children.find(n=>n.name==='Identity'),vp=shared.children.find(n=>n.name==='Body viewport'),slot=vp.children.find(n=>n.type==='SLOT'),close=shared.children.find(n=>n.name==='Close');
  setp(hi,props(oldIdentity));setp(close,props(oldClose));await hi.setReactionsAsync(oldIdentity.reactions);await close.setReactionsAsync(oldClose.reactions);remember(oldIdentity,hi);remember(oldClose,close);
  const contents=MODE==='pin'?oldLayout.children.filter(n=>n!==oldIdentity&&n!==oldClose):[...oldBody.children];
  const hasBody=contents.some(n=>n.visible!==false);setp(shared,{'Show body':hasBody});
  for(const node of contents){if(node.type==='TEXT'){const n=await paragraphize(node);slot.appendChild(n);n.layoutPositioning='AUTO';n.layoutSizingHorizontal='FILL';removed.push(node.id);node.remove();}else{slot.appendChild(node);node.layoutPositioning='AUTO';mutated.add(node.id);}}
  shared.layoutSizingVertical='HUG';shared.x=0;shared.y=0;
 }
 for(const n of oldChildren){removed.push(n.id);n.remove();}
 root.fills=[];root.strokes=[];root.layoutMode='VERTICAL';root.paddingTop=0;root.paddingBottom=0;root.paddingLeft=0;root.paddingRight=0;root.itemSpacing=0;root.primaryAxisSizingMode=MODE==='feedback'?'FIXED':'AUTO';root.counterAxisSizingMode='FIXED';root.resize(360,MODE==='feedback'?800:shared.height);if(MODE!=='feedback')root.primaryAxisSizingMode='AUTO';shared.layoutSizingHorizontal='FILL';root.clipsContent=true;mutated.add(root.id);
 rows.push({id:root.id,name:root.name,instanceId:shared.id,beforeHeight:before.height,afterHeight:root.height,beforeTextHash:digest(before.text),beforeActionHash:digest(before.actions),beforeTextCount:before.text.length,beforeActionCount:before.actions.length});
}
return {mode:MODE,createdNodeIds:created,mutatedNodeIds:[...mutated],removedNodeIds:removed,mappings,rows,failures};
