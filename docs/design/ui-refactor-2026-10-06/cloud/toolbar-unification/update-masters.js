const page=await figma.getNodeByIdAsync('481:53');await figma.setCurrentPageAsync(page);
const changed=new Set(),created=[];
const touch=n=>{changed.add(n.id);return n;};
const made=n=>{created.push(n.id);return n;};
const vars=await figma.variables.getLocalVariablesAsync();
const v=Object.fromEntries(vars.filter(x=>x.name.startsWith('color/')||x.name.startsWith('radius/')).map(x=>[x.name,x]));
function paint(key,opacity=1){const p={type:'SOLID',color:{r:1,g:1,b:1},opacity};return figma.variables.setBoundVariableForPaint(p,'color',v['color/'+key]);}
const fonts=new Map();for(const id of ['633:41221','633:41231','633:41241']){const c=await figma.getNodeByIdAsync(id);for(const n of c.findAll(n=>n.type==='TEXT'))for(const s of n.getStyledTextSegments(['fontName']))fonts.set(JSON.stringify(s.fontName),s.fontName);}
for(const f of fonts.values())await figma.loadFontAsync(f);
await figma.loadFontAsync({family:'Nunito',style:'Bold'});await figma.loadFontAsync({family:'Nunito',style:'ExtraBold'});
const set=await figma.getNodeByIdAsync('633:41279');
let pinKey=Object.keys(set.componentPropertyDefinitions).find(k=>k.startsWith('Show pin#'));
if(!pinKey)pinKey=set.addComponentProperty('Show pin','BOOLEAN',false);
const styles=await figma.getLocalTextStylesAsync();
async function style(n,name,size,line){const s=styles.find(s=>s.name===name);if(s)await n.setTextStyleIdAsync(s.id);n.fontSize=size;n.lineHeight={unit:'PIXELS',value:line};n.textAutoResize='NONE';}
for(const [id,state] of [['633:41221','default'],['633:41231','selected'],['633:41241','empty']]){
 const c=touch(await figma.getNodeByIdAsync(id));c.resize(52,68);c.layoutMode='NONE';c.fills=[];c.strokes=[];c.opacity=1;c.clipsContent=false;
 const icon=c.findOne(n=>n.type==='INSTANCE'&&n.name.startsWith('Icon/'))||c.findOne(n=>n.type==='INSTANCE');
 const title=c.findOne(n=>n.type==='TEXT'&&n.name==='Title');const quantity=c.findOne(n=>n.type==='TEXT'&&n.name==='Quantity');
 let surface=c.children.find(n=>n.name==='Slot surface');if(!surface){surface=made(figma.createAutoLayout('VERTICAL'));c.appendChild(surface);surface.name='Slot surface';}
 touch(surface);surface.layoutMode='VERTICAL';surface.resize(52,64);surface.primaryAxisSizingMode='FIXED';surface.counterAxisSizingMode='FIXED';surface.counterAxisAlignItems='CENTER';surface.itemSpacing=0;surface.paddingTop=4;surface.paddingBottom=4;surface.paddingLeft=4;surface.paddingRight=4;surface.x=0;surface.y=state==='selected'?0:4;surface.cornerRadius=11;surface.setBoundVariable('cornerRadius',v['radius/cell']);surface.fills=[paint('surface',state==='empty'?.44:1)];surface.strokes=[paint(state==='selected'?'primary':'border')];surface.strokeWeight=state==='selected'?2:1;surface.dashPattern=state==='empty'?[3,3]:[];surface.clipsContent=false;
 for(const n of [icon,title,quantity]){touch(n);surface.appendChild(n);n.layoutPositioning='AUTO';}
 icon.resize(22,22);icon.visible=state!=='empty';icon.layoutSizingHorizontal='FIXED';icon.layoutSizingVertical='FIXED';
 title.resize(44,22);await style(title,'Gensen/Compact/10/Bold',10,11);title.textAlignHorizontal='CENTER';title.textAlignVertical='CENTER';title.visible=state!=='empty';
 quantity.resize(44,12);await style(quantity,'Gensen/Compact/10/ExtraBold',10,12);quantity.textAlignHorizontal='RIGHT';quantity.textAlignVertical='CENTER';quantity.visible=state!=='empty';
 for(const old of [...c.children])if(old.name==='Quantity pill'){changed.add(old.id);old.remove();}
 let pin=c.children.find(n=>n.name==='Pinned state');if(!pin){pin=made(figma.createFrame());c.appendChild(pin);pin.name='Pinned state';pin.resize(52,64);pin.fills=[];pin.clipsContent=true;pin.cornerRadius=11;pin.componentPropertyReferences={visible:pinKey};const top=made(figma.createRectangle());pin.appendChild(top);top.name='Pinned amber strip';top.resize(52,2);top.fills=[paint('warning')];const badge=made(figma.createFrame());pin.appendChild(badge);badge.name='Pinned icon surface';badge.resize(16,16);badge.x=34;badge.y=2;badge.cornerRadius=8;badge.fills=[paint('warningTint')];const pi=made((await figma.getNodeByIdAsync('431:348')).createInstance());badge.appendChild(pi);pi.resize(12,12);pi.x=2;pi.y=2;}
 pin.x=0;pin.y=surface.y;pin.visible=false;
 c.description='Unified consumable quick slot. 52 × 68 outer bounds; 64-high surface, selected lifts 4 px. Icon, two-line item name and right-aligned quantity occupy separate fixed rows. Quantity is ×N; unknown stays blank. Empty slots never show inventory. Show pin preserves the amber pinned marker. Tools stay outside the Quick Bar.';
}
set.resize(236,116);touch(set);const stage=touch(set.parent);stage.resize(stage.width,116);
const library=await figma.getNodeByIdAsync('481:54');let group=library.children.find(n=>n.name==='Toolbar components · unified');if(!group){group=made(figma.createAutoLayout('VERTICAL'));library.appendChild(group);group.name='Toolbar components · unified';group.resize(388,200);group.primaryAxisSizingMode='AUTO';group.counterAxisSizingMode='FIXED';group.itemSpacing=16;group.fills=[];group.x=2324;group.y=3200;}
const endIds={};for(const role of ['Bag','Close']){let c=group.children.find(n=>n.type==='COMPONENT'&&n.name==='Gensen Refactor/Compact/QuickEnd/'+role);if(!c){c=made(figma.createComponent());group.appendChild(c);c.name='Gensen Refactor/Compact/QuickEnd/'+role;c.resize(56,68);c.fills=[];c.clipsContent=false;const s=made(figma.createAutoLayout('VERTICAL'));c.appendChild(s);s.name='Navigation surface';s.resize(56,64);s.primaryAxisSizingMode='FIXED';s.counterAxisSizingMode='FIXED';s.primaryAxisAlignItems='CENTER';s.counterAxisAlignItems='CENTER';s.itemSpacing=4;s.fills=[paint('surface')];s.strokes=[paint('border')];s.strokeWeight=1;s.cornerRadius=11;s.setBoundVariable('cornerRadius',v['radius/cell']);s.x=0;s.y=4;const ico=(await figma.getNodeByIdAsync(role==='Bag'?'431:82':'431:55'));if(!ico||ico.type!=='COMPONENT')throw Error('Expected verified icon IDs for '+role);const i=made(ico.createInstance());s.appendChild(i);i.resize(22,22);const t=made(figma.createText());s.appendChild(t);t.name='Label';t.fontName={family:'Nunito',style:'Bold'};t.characters=role;t.resize(48,14);await style(t,'Gensen/Compact/11/Bold',11,14);t.textAlignHorizontal='CENTER';t.fills=[paint('text')];c.description='Shared Quick Bar '+role+' navigation. Label is always visible; never shows item quantity. 56 × 68 touch target.';}endIds['Compact/QuickEnd/'+role]=c.id;}
return {createdNodeIds:created,mutatedNodeIds:[...changed],endIds,slotSet:set.id,pinKey,libraryGroup:group.id};
