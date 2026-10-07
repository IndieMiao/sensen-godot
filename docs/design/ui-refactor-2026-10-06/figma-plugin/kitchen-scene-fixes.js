/* Kitchen entrance specialization. Append after the stable renderer patches.
 * Reuses the source kitchen art; only native UI markers/leader lines are added.
 * Selection/ingredient/heat screens keep the previously verified kitchen renderer.
 */
const KITCHEN_SCENE_BASE={library,sceneScreen,kitchen,buildScreen};
const KITCHEN_ENTRANCE_IDS=new Set(['COOK-1','COOK-P0-1','COOK-P1-1','COOK-P1-3','COOK-P1-5']);
const KITCHEN_ART_ANCHORS={
  stoves:[{x:139,y:294},{x:218,y:312},{x:294,y:330}],
  cabinet:{x:348,y:354}
};
library=async function(){
  await KITCHEN_SCENE_BASE.library();
  const variants=[];
  for(const size of ['compact','wide'])for(const kind of ['navigate','commit','blocked']){
    const w=size==='compact'?108:156,inner=w-16;
    const c=component('Size='+size+', Kind='+kind,w);c.itemSpacing=3;pad(c,8);fill(c,'surface',.98);border(c,'border');radius(c,'card');
    ctext(c,c,'Title','Stove 1',inner,'body','text','ExtraBold');
    const status=horizontal(c,'Status and remaining',inner,4);
    ctext(c,status,'State','Cooking',inner-44,'caption','secondary','Bold');
    const value=ctext(c,status,'Value','0:22',40,'body','text','ExtraBold');value.textAlignHorizontal='RIGHT';
    const detail=ctext(c,c,'Detail','1 queued',inner,'caption','secondary');cvisible(c,detail,'Show detail',false);
    const action=frame(c,'Facility action',inner,44);action.layoutMode='HORIZONTAL';action.primaryAxisSizingMode='FIXED';action.counterAxisSizingMode='FIXED';action.counterAxisAlignItems='CENTER';action.primaryAxisAlignItems='CENTER';action.itemSpacing=4;
    if(kind==='commit'){fill(action,'primary');radius(action,'pill');}
    else if(kind==='blocked'){fill(action,'warningTint');radius(action,'pill');}
    const label=ctext(c,action,'Action label',kind==='commit'?'Collect':'Open',kind==='navigate'?inner-20:inner-12,'body',kind==='commit'?'surfaceRaised':kind==='blocked'?'warning':'info','Bold');label.textAlignHorizontal=kind==='navigate'?'LEFT':'CENTER';
    if(kind==='navigate')ctext(c,action,'Chevron','›',16,'body','info','Bold');
    cvisible(c,action,'Show action',true);
    KIT['FacilityMarker/'+size+'/'+kind]=c;LEDGER.components['FacilityMarker/'+size+'/'+kind]=c.id;variants.push(c);
  }
  variantSet('FacilityMarker',variants);
  LIBRARY.resize(1260,Math.max(libraryY+40,2000));
};
function kitchenStoveDescriptors(s){
  if(s.id==='COOK-1')return (s.items||[]).filter(x=>/^Stove \d+$/.test(x.title||''));
  const authored=s.kitchen?.stoves||[],sceneCount=Number(s.sceneState?.stoves||0);
  const countFact=(s.keyFacts||[]).find(f=>f.label==='Empty stoves'||f.label==='Stoves');
  const factCount=countFact?Number(String(countFact.value).split('/').pop()):0;
  const count=Math.max(1,Math.min(3,sceneCount||factCount||authored.length||1));
  const actualStates=s.sceneState?.stoveStates||[];
  const busy=s.id==='COOK-EMPTY';
  return Array.from({length:count},(_,i)=>({title:'Stove '+(i+1),state:busy?'Busy':actualStates[i]||authored[i]?.state||'Empty'}));
}
function kitchenMarkerState(s,item){
  const raw=item.state||'',match=raw.match(/\d+:\d{2}/);
  const timeFact=(item.keyFacts||[]).find(x=>x.kind==='time');
  const cooking=/cooking/i.test(raw),ready=/ready/i.test(raw),empty=/empty/i.test(raw);
  const state=cooking?'Cooking':ready?'Ready':empty?'Empty':raw||'Available';
  const queued=raw.match(/Queued\s*(\d+)/i);
  let detail=queued?queued[1]+' queued':item.effect||'';
  if(!detail&&(s.disclosure||[]).some(x=>x==='Queued 1 on each stove'))detail='1 queued';
  return {state,value:match?.[0]||timeFact?.value||'',detail};
}
function kitchenLeader(p,from,to){
  // Orthogonal native lines tie the floating marker to the approved image landmark.
  // These are presentation anchors for this source image, not runtime world coordinates.
  const v=frame(p,'Facility leader · vertical',1,Math.max(1,Math.abs(to.y-from.y)),'border');v.x=from.x;v.y=Math.min(from.y,to.y);
  const h=frame(p,'Facility leader · horizontal',Math.max(1,Math.abs(to.x-from.x)),1,'border');h.x=Math.min(from.x,to.x);h.y=to.y;
  const dot=frame(p,'Facility anchor',6,6,'primary');radius(dot,3);dot.x=to.x-3;dot.y=to.y-3;
}
function kitchenMarker(p,s,descriptor,position,anchor,size='compact'){
  const kind=descriptor.action?.kind==='commit'?'commit':descriptor.action?.kind==='blocked'?'blocked':'navigate';
  const marker=inst(p,'FacilityMarker/'+size+'/'+kind,{Title:descriptor.title,State:descriptor.state||'',Value:descriptor.value||'',Detail:descriptor.detail||'','Show detail':Boolean(descriptor.detail),'Action label':descriptor.action?.label||'Open','Show action':Boolean(descriptor.action)});
  marker.name='Facility marker · '+descriptor.title;absolute(marker,position.x,position.y);
  if(anchor){const from={x:position.x+marker.width/2,y:anchor.y<position.y?position.y:position.y+marker.height};kitchenLeader(p,from,anchor);}
  if(descriptor.action){const actionNode=marker.findOne(n=>n.name==='Facility action');PENDING_LINKS.push({node:actionNode,ownerId:s.id,action:descriptor.action,detail:descriptor.detailOverlay});}
  return marker;
}
function kitchenEntranceAction(s,item,index,state){
  if(state==='Empty'){
    const supplied=(item.actions||[]).find(a=>a.kind==='navigate')||(s.actions||[]).find(a=>a.kind==='navigate'&&/recipe|stove/i.test(a.label));
    return {label:'Open',kind:'navigate',target:supplied?.target||(s.id==='COOK-P0-1'?'TUT-3-07B':s.sourceHtml?'COOK-2a':'COOK-P0-2')};
  }
  if(state==='Ready'){
    if(s.id==='COOK-P1-3')return {label:'Collect',kind:'blocked',target:null,feedback:'Make room in your bag or Warming Cabinet before collecting.'};
    const supplied=(item.actions||[]).find(a=>a.kind==='commit');
    if(s.id==='COOK-1'&&supplied?.target==='COOK-4'&&item.effect==='Grilled Crucian'){
      LEDGER.warnings.push({screen:s.id,action:'Collect',kind:'commit',target:null,reason:'Ready dish is Grilled Crucian; COOK-4 is Herb Grilled Fish. No matching collection outcome was authored, so the unrelated result is not linked.'});
      return {label:'Collect',kind:'commit',target:null};
    }
    return supplied?{...supplied,label:'Collect'}:{label:'Collect',kind:'commit',target:null};
  }
  return null;
}
function kitchenSceneEntrance(p,s){
  const stoves=kitchenStoveDescriptors(s);
  // Coordinates refer to the same full-bleed source art as the accepted 360×800 kitchen frame.
  const positions=[{x:8,y:154},{x:126,y:154},{x:244,y:154}];
  for(let i=0;i<stoves.length;i++){
    const item=stoves[i],parts=kitchenMarkerState(s,item),action=kitchenEntranceAction(s,item,i,parts.state);
    kitchenMarker(p,s,{title:item.title,...parts,action},positions[i],KITCHEN_ART_ANCHORS.stoves[i]);
  }
  const cabinet=(s.items||[]).find(x=>x.title==='Warming Cabinet');
  const cabinetFact=(cabinet?.keyFacts||[]).find(f=>f.kind==='capacity')||(s.keyFacts||[]).find(f=>f.label==='Cabinet');
  if(cabinet||cabinetFact){
    const full=String(cabinetFact?.value||'')==='6/6';
    const action={label:'Open',kind:'navigate',target:full?null:'COOK-P0-6'};
    const detailOverlay=full?{title:'Warming Cabinet',state:'Full',effect:'Make space before storing another cooked dish.',keyFacts:[{label:'Stored',value:'6/6',kind:'capacity'}],actions:[{label:'Open bag',kind:'navigate',target:'BAG-1-P0'},{label:'Close',kind:'dismiss'}]}:undefined;
    kitchenMarker(p,s,{title:'Warming Cabinet',state:full?'Full':'Stored',value:String(cabinetFact?.value||''),action,detailOverlay},{x:196,y:454},KITCHEN_ART_ANCHORS.cabinet,'wide');
  }
  if(s.id==='COOK-P1-3'){
    const note=frame(p,'Kitchen capacity feedback',328,68,'surface');radius(note,'card');note.x=16;note.y=578;
    const title=text(note,'Make room to collect',304,'body','text','Bold');absolute(title,12,10);
    const detail=text(note,'Bag full · Cabinet 6/6',304,'caption','secondary');absolute(detail,12,38);
  }
  // Only information navigation lives in this compact scene dock. No labour FAB/Quick Bar/Back sheet.
  const dock=auto(p,'Kitchen navigation dock',328,'VERTICAL',0,'surface');radius(dock,'card');
  const cookbook=s.sourceHtml?'COOK-2a':s.id==='COOK-P0-1'?'TUT-3-07B':'COOK-P0-2';
  for(const a of [{label:'Cookbook',kind:'navigate',target:cookbook},{label:'Bag',kind:'navigate',target:s.sourceHtml?'BAG-1':'BAG-1-P0'}])button(dock,a,'secondary',s.id);
  absolute(dock,16,H-24-dock.height);
  LEDGER.sourceReferences[s.id]={...(LEDGER.sourceReferences[s.id]||{}),kitchenStoveCount:stoves.length,kitchenArtAnchors:'Authored 360x800 image landmarks; runtime projection/collision not claimed.'};
}
sceneScreen=function(p,s){if(s.id==='COOK-1'){kitchenSceneEntrance(p,s);return;}KITCHEN_SCENE_BASE.sceneScreen(p,s);};
kitchen=function(p,s){
  if(KITCHEN_ENTRANCE_IDS.has(s.id)){kitchenSceneEntrance(p,s);return;}
  if(s.kitchen?.mode==='stoves'){
    // Confirmation/gate screens retain their existing decision layout, but not an erroneous one-stove default.
    const normalized={...s,kitchen:{...s.kitchen,stoves:kitchenStoveDescriptors(s)}};
    KITCHEN_SCENE_BASE.kitchen(p,normalized);return;
  }
  KITCHEN_SCENE_BASE.kitchen(p,s);
};
buildScreen=function(s,index){
  if(KITCHEN_ENTRANCE_IDS.has(s.id)){const screen=KITCHEN_SCENE_BASE.buildScreen({...s,layout:'scene',presentation:{...(s.presentation||{}),close:false,suppressDecisionArea:true}},index);LEDGER.sourceReferences[s.id]={...(LEDGER.sourceReferences[s.id]||{}),kitchenStoveCount:kitchenStoveDescriptors(s).length,kitchenArtAnchors:'Authored 360x800 image landmarks; runtime projection/collision not claimed.'};return screen;}
  return KITCHEN_SCENE_BASE.buildScreen(s,index);
};
