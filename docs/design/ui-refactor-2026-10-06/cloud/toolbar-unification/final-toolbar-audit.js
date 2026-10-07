const page=await figma.getNodeByIdAsync('481:53');await figma.setCurrentPageAsync(page);const issues=[],rows=[];
const normalized=s=>String(s||'').replace(/\s+/g,' ').trim();
for(const r of DATA){
 const n=await figma.getNodeByIdAsync(r.id);if(!n){issues.push([r.screenId,'missing bar']);continue;}
 if(n.width!==336||n.height!==68||n.itemSpacing!==4||n.children.length!==6)issues.push([r.screenId,'bar dimensions/count']);
 const actual=[];for(let i=0;i<5;i++){
  const slot=n.children[i],e=r.slots[i],props=Object.fromEntries(Object.entries(slot.componentProperties||{}).map(([k,v])=>[k.split('#')[0],v.value]));
  const main=slot.mainComponent?.id,expected=e.empty?'633:41241':e.selected?'633:41231':'633:41221';
  if(main!==expected||slot.width!==52||slot.height!==68)issues.push([r.screenId,i,'slot master/geometry']);
  if(!e.empty&&(normalized(props.Title)!==normalized(e.title)||props.Quantity!==e.quantityDisplay||!props['Show title']||!props['Show quantity']||!props['Show icon']||!/^×\d+$/.test(props.Quantity)))issues.push([r.screenId,i,'content',props.Title,props.Quantity,e.title,e.quantityDisplay]);
  if(e.empty&&(props['Show title']||props['Show quantity']||props['Show icon']))issues.push([r.screenId,i,'empty content']);
  if(!!props['Show pin']!==!!e.pinned)issues.push([r.screenId,i,'pin']);
  if(!e.empty){const t=slot.findOne(x=>x.type==='TEXT'&&x.name==='Title'),q=slot.findOne(x=>x.type==='TEXT'&&x.name==='Quantity');if(!t||!q||t.y+t.height>q.y+.1)issues.push([r.screenId,i,'name-quantity-overlap']);}
  actual.push({id:slot.id,title:props.Title,quantity:props.Quantity,state:props.State,pinned:props['Show pin']});
 }
 const end=n.children[5];if(end.type!=='INSTANCE'||end.mainComponent?.id!==(r.end==='Close'?'907:72121':'907:72112')||end.width!==56||end.height!==68)issues.push([r.screenId,'end component']);
 const text=end.findOne(x=>x.type==='TEXT'&&x.name==='Label');if(text?.characters!==r.end)issues.push([r.screenId,'end label']);
 if(r.role==='world'){let top=n;while(top.parent&&top.parent.id!==r.screenNodeId)top=top.parent;if(top.x!==12||top.y!==708)issues.push([r.screenId,'world position',top.x,top.y]);}
 rows.push([r.screenId,n.id,actual.filter(s=>s.quantity).length,end.id]);
}
const legacy=page.findAll(n=>n.type==='INSTANCE'&&['483:496','483:508','483:520'].includes(n.mainComponent?.id));if(legacy.length)issues.push(['legacy slot instances remain',legacy.length]);
return {scope:'40 complete Quick Bars on refactor page',screenCount:rows.length,slots:rows.length*5,sharedSlotMasters:['633:41221','633:41231','633:41241'],sharedEndMasters:['907:72112','907:72121'],rows,remainingLegacySlotInstances:legacy.length,issues};
