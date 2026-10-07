/* BAR-2 source is an action radial (four 128px controls fanning above the avatar).
 * Dedicated native layout; selection changes the mode/route, never consumes resources.
 */
const ACTION_PICKER_BASE=buildScreen;
function actionPickerScreen(s,index){
 const box=figma.createSection();box.name='Review · '+s.id;PAGE.appendChild(box);box.resizeWithoutConstraints(360,1000);fill(box);box.x=100+(index%8)*412;box.y=180+Math.floor(index/8)*1070;
 const screen=frame(box,s.id+' · Actions',W,H,'surface');screen.clipsContent=true;scene(screen,s);hud(screen,s);
 const head=auto(screen,'Action picker context',220,'VERTICAL',2,'surface');head.x=16;head.y=132;radius(head,'card');head.paddingLeft=10;head.paddingRight=10;head.paddingTop=8;head.paddingBottom=8;text(head,'Choose an action',200,'rowTitle','text','ExtraBold');text(head,'Homestead',200,'caption','secondary');
 // Read-only context control beneath the open selector; it has no work reaction here.
 const current=inst(screen,'SceneAction',{Verb:'Sow ×1',Cost:'2 Energy'});absolute(current,256,580);current.opacity=.6;current.name='Current Farming action · selector open';
 const quick=auto(screen,'Source Quick Bar',336);quick.x=12;quick.y=708;quickbar(quick,s,s.id);
 const cancel=frame(screen,'Close action picker · 44 px',44,44,'primaryTint');radius(cancel,22);border(cancel,'primary');absolute(icon(cancel,'i-switch',24),10,10);absolute(cancel,278,524);PENDING_LINKS.push({node:cancel,ownerId:s.id,action:{label:'Close action picker',kind:'dismiss',target:'FARM-1'}});
 const specimens=[{title:'Farming',icon:'i-field',x:58,y:322},{title:'Fishing',icon:'i-fish',x:140,y:288},{title:'Mining',icon:'i-pickaxe',x:222,y:324},{title:'Combat',icon:'i-sword',x:298,y:404}];
 for(const sample of specimens){
  const source=(s.items||[]).find(i=>i.title===sample.title);const blocked=source?.state==='Unavailable';const selected=source?.state==='Selected';
  const hit=frame(screen,'Action mode · '+sample.title,72,110);absolute(hit,sample.x-36,sample.y-32);
  const disc=frame(hit,'Mode control',64,64,selected?'primaryTint':'surface');absolute(disc,4,0);radius(disc,32);border(disc,selected?'primary':'border',selected?3:1);const art=icon(disc,ICON[sample.icon]?sample.icon:sample.title==='Farming'?'i-hoe':'i-question',30);absolute(art,17,17);if(blocked)art.opacity=.55;
  const name=text(hit,sample.title,72,'body',blocked?'secondary':'text','ExtraBold');name.textAlignHorizontal='CENTER';absolute(name,0,68);
  const state=text(hit,selected?'Selected':blocked?'Unavailable':'',72,'caption',selected?'primary':'secondary','Bold');state.textAlignHorizontal='CENTER';absolute(state,0,89);
  if(selected){const tick=frame(disc,'Selected indicator',20,20,'surface');radius(tick,10);border(tick,'primary');absolute(icon(tick,'i-check',12),4,4);absolute(tick,45,-2);}
  const original=source?.actions?.[0];const action=blocked?{label:sample.title,kind:'blocked',feedback:original?.feedback||'This action is unavailable here.',target:s.id}:{label:sample.title,kind:'navigate',target:original?.target||'FARM-1',context:{operation:'select-action-mode',mode:sample.title,resourceMutation:false}};
  PENDING_LINKS.push({node:hit,ownerId:s.id,action});
 }
 reviewNote(box,{...s,sourceNote:(s.sourceNote||'')+' Dedicated Homestead radial: Farming selected; unavailable modes explain on tap. Selecting a mode does not spend Energy or items.'},816);
 LEDGER.screens[s.id]=screen.id;LEDGER.sourceReferences[s.id]={sourceNodeId:s.figmaNodeId,newNodeId:screen.id,sourceFile:s.sourceHtml,sourceGroup:s.sourceGroup,layout:'action-radial',reviewOnly:false};LEDGER.checks.actionPicker={id:s.id,modeCount:4,minTouchTarget:72,selectionConsumesResources:false};return screen;
}
buildScreen=function(s,index){return s.id==='BAR-2'?actionPickerScreen(s,index):ACTION_PICKER_BASE(s,index);};
