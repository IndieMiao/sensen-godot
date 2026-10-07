// Root executes only after its existing cloud bootstrap has hydrated PAGE/LIBRARY/KIT/ICON/LEDGER/helpers.
// Do not call the full chained library(): that would rebuild already approved masters.
// Bootstrap must set current page once and load the usual function definitions.
const kitchenDeltaKeys = ["FacilityMarker/compact/navigate", "FacilityMarker/compact/commit", "FacilityMarker/compact/blocked", "FacilityMarker/wide/navigate", "FacilityMarker/wide/commit", "FacilityMarker/wide/blocked"];
const kitchenDeltaPresent = kitchenDeltaKeys.filter(key => KIT[key]);
if (kitchenDeltaPresent.length && kitchenDeltaPresent.length !== kitchenDeltaKeys.length) {
  return {status:'partial-marker-ledger',present:kitchenDeltaPresent,required:kitchenDeltaKeys,createdNodeIds:[],mutatedNodeIds:[]};
}
for (const style of ['Regular','Bold','ExtraBold']) await figma.loadFontAsync({family:T.font.family,style});
const kitchenDeltaBeforeIds = new Set(PAGE.findAll(()=>true).map(n=>n.id));
if (!kitchenDeltaPresent.length) {


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
}
if (!ICON['i-lock'] && KIT['Icon/i-lock']) ICON['i-lock'] = KIT['Icon/i-lock'];


  if(!ICON['i-lock']&&BUNDLE.iconSvgs['i-lock']){
    const c=component('Gensen Refactor/Icon/i-lock',64);c.resize(64,64);c.primaryAxisSizingMode='FIXED';
    const source=figma.createNodeFromSvg(BUNDLE.iconSvgs['i-lock']);c.appendChild(source);source.resize(64,64);source.x=0;source.y=0;
    register('Icon/i-lock',c);ICON['i-lock']=c;
  }
await Promise.all(STYLE_JOBS);
return {
  status:'kitchen-components-ready',
  createdNodeIds:PAGE.findAll(()=>true).filter(n=>!kitchenDeltaBeforeIds.has(n.id)).map(n=>n.id),
  mutatedNodeIds:[LIBRARY.id],
  components:Object.fromEntries(kitchenDeltaKeys.map(key=>[key,KIT[key].id])),
  componentSet:LEDGER.componentSets.FacilityMarker,
  lockIconId:ICON['i-lock']?.id||null
};
