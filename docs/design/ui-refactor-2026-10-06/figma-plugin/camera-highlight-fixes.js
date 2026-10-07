/* Read-only Show actions and compact Today cards. Append after QA adapters.
 * The inspected scene/map is a native overlay; it never moves the player,
 * opens a facility, starts travel, gathers a resource or awards anything.
 */
const CAMERA_HIGHLIGHT_BASE={contextDetail,createDetail,general};
const CAMERA_HIGHLIGHT_CACHE=new Map();
contextDetail=function(action){
  if(action.context?.operation==='highlight-target')return {title:action.context.placeName,cameraHighlight:action.context};
  return CAMERA_HIGHLIGHT_BASE.contextDetail(action);
};
function cameraHighlightFrame(detail,ownerId){
  const c=detail.cameraHighlight,key=ownerId+'|'+JSON.stringify(c);
  if(CAMERA_HIGHLIGHT_CACHE.has(key))return CAMERA_HIGHLIGHT_CACHE.get(key);
  const source=BUNDLE.screens.find(s=>s.id===ownerId)||BUNDLE.screens.find(s=>s.id===c.ownerId);
  if(!source)throw Error('Camera highlight requires the source view: '+ownerId);
  const o=overlayFrame('Camera focus · '+c.placeName,H);o.cornerRadius=0;
  CAMERA_HIGHLIGHT_CACHE.set(key,o);
  const sceneView=c.view==='scene'?source:{...source,scene:'map',sceneName:'map'};
  scene(o,sceneView);
  // Keep the source location/resources, including a source farm player baked
  // into the same scene art. HUD navigation is inert in this read-only preview.
  const start=PENDING_LINKS.length;hud(o,source);PENDING_LINKS.splice(start);
  const [cx,cy]=c.anchor||[180,365];
  const glow=figma.createEllipse();o.appendChild(glow);glow.name='Camera target · halo';glow.resize(64,64);fill(glow,'primary',.16);glow.x=cx-32;glow.y=cy-32;
  const ring=figma.createEllipse();o.appendChild(ring);ring.name='Camera target · focus ring';ring.resize(44,44);fill(ring,null);border(ring,'primary',3);ring.x=cx-22;ring.y=cy-22;
  const tag=auto(o,'Camera target · place name',Math.min(304,Math.max(140,c.placeName.length*7+32)),'VERTICAL',0,'surface');pad(tag,10);radius(tag,'card');border(tag,'primary');
  const label=text(tag,c.placeName,tag.width-20,'rowTitle','text','ExtraBold');label.textAlignHorizontal='CENTER';
  absolute(tag,Math.max(16,Math.min(W-16-tag.width,cx-tag.width/2)),cy+42);
  const close=inst(o,'Close');absolute(close,300,122);close.name='Close camera focus · 44 px';PENDING_LINKS.push({node:close,close:true});
  const note=text(PAGE,'Camera-only review · '+ownerId+' → '+c.placeName+'\nSource player and resources preserved. Highlight anchor is illustrative on approved art; no movement, facility opening or settlement.',W,'caption','secondary');note.name='Camera review note · outside player viewport';note.x=o.x;note.y=o.y+H+12;
  LEDGER.overlays[o.id]={title:c.placeName,ownerId,type:'camera-highlight',view:c.view,preservePlayer:true,preserveResources:true,sourceScene:sceneKey(source),reviewNoteId:note.id};
  return o;
}
createDetail=function(detail,ownerId){
  if(detail.cameraHighlight)return cameraHighlightFrame(detail,ownerId);
  return CAMERA_HIGHLIGHT_BASE.createDetail(detail,ownerId);
};
function currentTodayCompact(p,s){
  const items=(s.rows||[]).slice(0,3).map(row=>({...row,actions:[...(row.actions||[])]}));
  if(s.id==='TODAY-1'){
    const cook=items.find(row=>row.title==='Grilled Crucian'),show=(s.actions||[]).find(a=>a.context?.operation==='highlight-target');
    if(cook&&show)cook.actions=[show];
  }
  qaToday(p,{...s,items});
  const col=p.findOne(n=>n.name==='Today · three visible tasks');if(col)col.name='Today · three current tasks';
}
general=function(p,s){
  if(s.id==='TODAY-1'||s.id==='TODAY-2')return currentTodayCompact(p,s);
  return CAMERA_HIGHLIGHT_BASE.general(p,s);
};
