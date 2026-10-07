// Root-only execution snippet. Requires the existing shared cloud bootstrap and kitchen patches.
// Edit kitchenRenderIds to choose a small targeted batch. The default is the three selectors.
const kitchenRenderIds = ['COOK-2a','COOK-2b','COOK-P0-2'];
const kitchenRenderNodes = {"COOK-1": "482:8", "COOK-2a": "482:74", "COOK-2b": "482:78", "COOK-P0-1": "482:259", "COOK-P0-2": "482:261", "COOK-P1-1": "482:363", "COOK-P1-3": "482:367", "COOK-P1-5": "482:371"};
const kitchenRenderPageId = "481:53";
const kitchenRenderEntrances = new Set(["COOK-1", "COOK-P0-1", "COOK-P1-1", "COOK-P1-3", "COOK-P1-5"]);
if (PAGE.id !== kitchenRenderPageId || figma.currentPage.id !== kitchenRenderPageId) throw new Error('Wrong review page.');
const kitchenRenderTargets = [];
for (const id of kitchenRenderIds) {
  const frame = await figma.getNodeByIdAsync(kitchenRenderNodes[id]);
  const descriptor = BUNDLE.screens.find(s=>s.id===id);
  if (!frame || frame.type !== 'FRAME' || !descriptor || !frame.name.startsWith(id)) throw new Error('Unverified kitchen target '+id);
  let parent=frame;while(parent&&parent.type!=='PAGE')parent=parent.parent;
  if(parent?.id!==kitchenRenderPageId)throw new Error('Refusing to modify a different page: '+id);
  kitchenRenderTargets.push({id,frame,descriptor});
}
for(const style of ['Regular','Bold','ExtraBold'])await figma.loadFontAsync({family:T.font.family,style});
const kitchenRenderBeforeIds=new Set(PAGE.findAll(()=>true).map(n=>n.id));
const kitchenRenderRemoved=[];
for(const {id,frame,descriptor} of kitchenRenderTargets){
  for(const child of [...frame.children]){kitchenRenderRemoved.push(child.id,...('findAll'in child?child.findAll(()=>true).map(n=>n.id):[]));child.remove();}
  scene(frame,descriptor);hud(frame,descriptor);
  if(kitchenRenderEntrances.has(id))kitchenSceneEntrance(frame,descriptor);else kitchen(frame,descriptor);
  LEDGER.screens[id]=frame.id;
}
await wire();await Promise.all(STYLE_JOBS);
return {
  createdNodeIds:PAGE.findAll(()=>true).filter(n=>!kitchenRenderBeforeIds.has(n.id)).map(n=>n.id),
  mutatedNodeIds:kitchenRenderTargets.map(t=>t.frame.id),
  removedNodeIds:kitchenRenderRemoved,
  screens:kitchenRenderTargets.map(({id,frame})=>({id,nodeId:frame.id,stoveMarkers:frame.findAll(n=>/^Facility marker · Stove \d+$/.test(n.name)).length,selectionGrid:frame.findOne(n=>n.name==='Kitchen grid browser')?.id||null})),
  warnings:LEDGER.warnings
};
