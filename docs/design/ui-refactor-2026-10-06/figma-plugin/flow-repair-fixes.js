/* Authored continuation states live outside the original 288-screen inventory.
 * Frames are top-level NAVIGATE targets. They preserve explicit result values;
 * opening a state never performs a second claim, meal or reward settlement.
 */
const FLOW_REPAIR_BASE={wire};
function flowRepairDiscover(){
  LEDGER.flowScreens=LEDGER.flowScreens||{};LEDGER.flowSceneScreens=LEDGER.flowSceneScreens||{};
  for(const n of PAGE.children){
    if(n.type!=='FRAME')continue;
    if(n.name.startsWith('Flow state · '))LEDGER.flowScreens[n.name.slice('Flow state · '.length).split(' · ')[0]]=n.id;
    if(n.name.startsWith('Flow scene · '))LEDGER.flowSceneScreens[n.name.slice('Flow scene · '.length).split(' · ')[0]]=n.id;
  }
}
function flowRepairNote(frameNode,s,note){
  const t=text(PAGE,s.id+' · '+(s.sourceRef?.designLabel||s.title)+'\n'+(note||s.sourceNote||''),W,'caption','secondary');
  t.name='Flow review notes · outside player viewport';t.x=frameNode.x;t.y=frameNode.y+H+12;return t;
}
async function flowRepairResultScene(s){
  const key=s.id+'/scene';const previous=LEDGER.flowSceneScreens?.[key];
  if(previous){const n=await figma.getNodeByIdAsync(previous);if(n)return n;}
  const n=overlayFrame('Result scene · '+s.id,H);n.name='Flow scene · '+key;n.cornerRadius=0;
  scene(n,s);hud(n,s);LEDGER.flowSceneScreens[key]=n.id;
  flowRepairNote(n,s,'Result-preserving scene: '+(s.hud?.energy??'—')+'/'+(s.hud?.capacity??'—')+' Energy. The result panel closes here; the pre-action cabinet is not restored.');
  return n;
}
async function buildFlowRepairState(s){
  const previous=LEDGER.flowScreens?.[s.id];if(previous){const n=await figma.getNodeByIdAsync(previous);if(n)return n;}
  let view=s,closeTarget=null;
  if(s.presentation?.closeResult==='scene'){
    await flowRepairResultScene(s);closeTarget=s.id+'/scene';
    view={...s,actions:(s.actions||[]).map(a=>a.kind==='dismiss'?{...a,target:closeTarget}:a)};
  }
  const n=overlayFrame('Continuation · '+s.id,H);n.name='Flow state · '+s.id+' · '+s.title;n.cornerRadius=0;
  scene(n,view);hud(n,view);general(n,view);
  if(s.presentation?.close){
    const sheet=n.children.find(c=>c.type==='INSTANCE'&&c.mainComponent?.id===KIT.Sheet.id);
    const close=inst(n,'Close');absolute(close,300,Math.max(132,(sheet?.y||248)-50));close.name='Close continuation · 44 px';
    PENDING_LINKS.push({node:close,ownerId:s.id,action:{label:'Close',kind:'dismiss',...(closeTarget?{target:closeTarget}:{})}});
  }
  flowRepairNote(n,s);LEDGER.flowScreens[s.id]=n.id;
  LEDGER.sourceReferences[s.id]={newNodeId:n.id,sourceGroup:s.sourceGroup,layout:'flow-continuation',notInOriginalMainScreenCount:true,sourceRef:s.sourceRef};
  return n;
}
wire=async function(){
  flowRepairDiscover();
  for(const state of BUNDLE.flowRepairStates||[])await buildFlowRepairState(state);
  const extra={...(LEDGER.flowScreens||{}),...(LEDGER.flowSceneScreens||{})};const prior=new Map();
  for(const [key,id]of Object.entries(extra)){prior.set(key,LEDGER.screens[key]);LEDGER.screens[key]=id;}
  try{await FLOW_REPAIR_BASE.wire();}
  finally{for(const [key,value]of prior){if(value===undefined)delete LEDGER.screens[key];else LEDGER.screens[key]=value;}}
  LEDGER.checks.flowRepairStates={screens:LEDGER.flowScreens,resultScenes:LEDGER.flowSceneScreens,mainScreenCountPreserved:true};
};
