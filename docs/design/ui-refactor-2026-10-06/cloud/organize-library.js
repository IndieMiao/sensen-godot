// Prepared for use_figma, not executed here. Only the new review page and library are in scope.
// Run after new reference masters have been created. Preserves component IDs, properties and instances.
const PAGE_ID='481:53', LIBRARY_ID='481:54';
const created=new Set(),mutated=new Set(),warnings=[];
const page=await figma.getNodeByIdAsync(PAGE_ID);
if(!page||page.type!=='PAGE')throw Error('Expected the new review page '+PAGE_ID);
await figma.setCurrentPageAsync(page);
const library=await figma.getNodeByIdAsync(LIBRARY_ID);
if(!library||library.type!=='FRAME'||library.parent?.id!==PAGE_ID)throw Error('Library must be a direct frame on the new review page.');
const titleStyle=await figma.getStyleByIdAsync('S:26d55acbd1a71d06a5b37a0e4e9a15fae9a69f14,');
const textStyles=await figma.getLocalTextStylesAsync();
const labelStyle=textStyles.find(s=>s.name==='Gensen Refactor/rowTitle/Bold');
if(!titleStyle||titleStyle.type!=='TEXT'||!labelStyle||labelStyle.type!=='TEXT')throw Error('Existing refactor text styles are required; none will be replaced.');
const ink=await figma.variables.getVariableByIdAsync('VariableID:481:6');
const surface=await figma.variables.getVariableByIdAsync('VariableID:481:4');
const borderVariable=await figma.variables.getVariableByIdAsync('VariableID:481:9');
if(!ink||!surface||!borderVariable)throw Error('Existing refactor semantic variables are required.');
const fonts=new Map();
for(const n of library.findAllWithCriteria({types:['TEXT']}))for(const seg of n.getStyledTextSegments(['fontName']))fonts.set(seg.fontName.family+'|'+seg.fontName.style,seg.fontName);
for(const style of [titleStyle,labelStyle])fonts.set(style.fontName.family+'|'+style.fontName.style,style.fontName);
for(const font of fonts.values())await figma.loadFontAsync(font);
function paint(variable,fallback){return figma.variables.setBoundVariableForPaint({type:'SOLID',color:fallback},'color',variable);}
const inkPaint=()=>paint(ink,{r:.1843,g:.2275,b:.2});
const surfacePaint=()=>paint(surface,{r:.9843,g:.9725,b:.9451});
const borderPaint=()=>paint(borderVariable,{r:.8824,g:.8549,b:.7843});
function touch(n){mutated.add(n.id);return n;}
function append(parent,n){if(n.parent!==parent){const previous=n.parent;parent.appendChild(n);if(previous)touch(previous);touch(parent);touch(n);}return n;}
function allVisible(n,result=[]){if(n.visible===false)return result;result.push(n);if('children'in n)for(const c of n.children)allVisible(c,result);return result;}
function footprint(n){
 const origin=n.absoluteBoundingBox;let minX=0,minY=0,maxX=n.width||1,maxY=n.height||1;
 if(origin)for(const child of allVisible(n)){const b=child.absoluteBoundingBox;if(!b)continue;minX=Math.min(minX,b.x-origin.x);minY=Math.min(minY,b.y-origin.y);maxX=Math.max(maxX,b.x-origin.x+b.width);maxY=Math.max(maxY,b.y-origin.y+b.height);}
 return {x:minX,y:minY,w:Math.max(1,maxX-minX),h:Math.max(1,maxY-minY)};
}
function existing(name,type){return library.findOne(n=>n.name===name&&n.type===type);}
function plainFrame(parent,name,w,h){let n=existing(name,'FRAME');if(!n){n=figma.createFrame();n.name=name;created.add(n.id);}append(parent,n);n.layoutMode='NONE';n.resize(w,Math.max(1,h));n.clipsContent=false;n.fills=[];touch(n);return n;}
function column(name,w){let n=existing(name,'FRAME');if(!n){n=figma.createAutoLayout('VERTICAL');n.name=name;created.add(n.id);}append(library,n);n.resize(w,1);n.layoutMode='VERTICAL';n.primaryAxisSizingMode='AUTO';n.counterAxisSizingMode='FIXED';n.itemSpacing=20;n.paddingLeft=16;n.paddingRight=16;n.paddingTop=16;n.paddingBottom=16;n.clipsContent=false;n.fills=[surfacePaint()];n.strokes=[borderPaint()];n.strokeWeight=1;n.cornerRadius=14;touch(n);return n;}
async function label(parent,name,value,width,style){let n=existing(name,'TEXT');if(!n){n=figma.createText();n.name=name;created.add(n.id);}append(parent,n);n.fontName=style.fontName;await n.setTextStyleIdAsync(style.id);n.characters=value;n.resize(width,Math.max(20,style.fontSize*1.35));n.textAutoResize='HEIGHT';n.fills=[inkPaint()];if(n.parent&&'layoutMode'in n.parent&&n.parent.layoutMode!=='NONE')n.layoutPositioning='AUTO';touch(n);return n;}
function withinIconBoard(n){for(let p=n.parent;p&&p.id!==LIBRARY_ID;p=p.parent)if(p.name.startsWith('Source icon fallbacks'))return true;return false;}
const masters=library.findAllWithCriteria({types:['COMPONENT','COMPONENT_SET']});
const units=masters.filter(n=>n.type==='COMPONENT_SET'||n.type==='COMPONENT'&&n.parent?.type!=='COMPONENT_SET');
const definitionSnapshot=new Map(units.map(n=>[n.id,JSON.stringify(n.componentPropertyDefinitions||{})]));
const instanceSnapshot=new Map(page.findAllWithCriteria({types:['INSTANCE']}).map(n=>[n.id,n.mainComponent?.id||null]));
const rootSnapshot=new Map(page.children.map(n=>[n.id,{x:n.x,y:n.y,width:n.width,height:n.height}]));
const iconUnits=units.filter(n=>withinIconBoard(n)||/^Gensen Refactor\/Icon\//.test(n.name));
const iconIds=new Set(iconUnits.map(n=>n.id));
const wardrobeUnits=units.filter(n=>n.type==='COMPONENT_SET'&&/^Gensen Refactor\/Avatar Wardrobe$/.test(n.name));
const wardrobeIds=new Set(wardrobeUnits.map(n=>n.id));
const avatarAssetUnits=units.filter(n=>n.type==='COMPONENT'&&/^Gensen Refactor\/Avatar thumbnail\//i.test(n.name));
const avatarAssetIds=new Set(avatarAssetUnits.map(n=>n.id));
const groupDefs=[
 {key:'换装组件',english:'Avatar controls',match:/Avatar|PlayerPortrait/},
 {key:'厨房组件',english:'Kitchen',match:/Kitchen|IngredientSlot|HeatRing|FacilityMarker/},
 {key:'信息组件',english:'Information',match:/ObjectHeader|Quantity|Effect|(^|\/)Fact|(^|\/)Cost|ProfileIdentity/},
 {key:'行动与选择',english:'Actions & selection',match:/Command|Navigation|Dismiss|Close|(^|\/)Tab$|Filter|NoteSelection|SceneAction/},
 {key:'容器与物品',english:'Containers & items',match:/Sheet|Inventory|CollectionCell|GearSlot|QuickSlot|NeedTile|IngredientSlot|SelectedSummary|SelectedItem|ItemRow|Container|ShopProduct/},
 {key:'游戏状态',english:'Game states',match:/HUD|StateBadge|Toast|Buff|Heat|Reference|Kitchen|Stove|FacilityMarker/}
];
const groups=Object.fromEntries(groupDefs.map(g=>[g.key,[]]));
for(const unit of units){if(iconIds.has(unit.id)||wardrobeIds.has(unit.id)||avatarAssetIds.has(unit.id))continue;const group=groupDefs.find(g=>g.match.test(unit.name));if(group)groups[group.key].push(unit);else{groups['信息组件'].push(unit);warnings.push('Unclassified master retained under Information: '+unit.name);}}
const setLayouts=[];
// Every set in this library, including icon sets, receives explicit variant geometry from visible bounds.
for(const set of masters.filter(n=>n.type==='COMPONENT_SET')){
 const variants=set.children.filter(n=>n.type==='COMPONENT');if(!variants.length)continue;
 const fullScreens=wardrobeIds.has(set.id);const measures=variants.map(n=>({n,b:fullScreens?{x:0,y:0,w:n.width,h:n.height}:footprint(n)}));const maxW=Math.max(...measures.map(x=>x.b.w));
 const cols=fullScreens?5:Math.max(1,Math.min(4,Math.floor((340+16)/(maxW+16))));
 set.layoutMode='NONE';set.clipsContent=false;touch(set);let y=24,maxRight=24;
 for(let i=0;i<measures.length;i+=cols){const row=measures.slice(i,i+cols);let x=24,rowH=0;
  for(const {n,b}of row){n.x=x-b.x;n.y=y-b.y;touch(n);x+=b.w+16;maxRight=Math.max(maxRight,x-16);rowH=Math.max(rowH,b.h);}
  y+=rowH+20;
 }
 set.resizeWithoutConstraints(maxRight+24,y+4);touch(set);
 setLayouts.push({id:set.id,name:set.name,variants:variants.length,columns:cols,width:set.width,height:set.height,});
}
const GAP=40,START_X=24;let maxHeight=0,nextColumnX=START_X;const groupCounts={};
for(let i=0;i<groupDefs.length;i++){
 const def=groupDefs[i],GROUP_W=Math.max(420,...groups[def.key].map(n=>Math.ceil(footprint(n).w)+32)),col=column('Library layout / '+def.key,GROUP_W);col.x=nextColumnX;col.y=24;nextColumnX+=GROUP_W+GAP;
 const heading=await label(col,'Library heading / '+def.key,def.english,GROUP_W-32,titleStyle);col.insertChild(0,heading);touch(heading);
 const children=groups[def.key].sort((a,b)=>a.name.localeCompare(b.name));
 for(const unit of children){
  const b=footprint(unit);const entry=plainFrame(col,'Library entry / '+unit.id,GROUP_W-32,b.h+44);entry.layoutPositioning='AUTO';
  const name=await label(entry,'Library label / '+unit.id,unit.name.replace(/^Gensen Refactor\//,''),GROUP_W-32,labelStyle);if(name.parent&&'layoutMode'in name.parent&&name.parent.layoutMode!=='NONE')name.layoutPositioning='ABSOLUTE';name.x=0;name.y=0;
  const titleH=name.height;const stage=plainFrame(entry,'Library stage / '+unit.id,Math.max(GROUP_W-32,b.w),b.h);stage.x=0;stage.y=titleH+8;
  append(stage,unit);unit.x=-b.x;unit.y=-b.y;touch(unit);entry.resize(GROUP_W-32,titleH+8+b.h);touch(entry);
  if(b.w>GROUP_W-32)warnings.push('Wide master retained without scaling: '+unit.name+' ('+Math.round(b.w)+'px)');
 }
 maxHeight=Math.max(maxHeight,col.height);groupCounts[def.key]={units:children.length,componentSets:children.filter(x=>x.type==='COMPONENT_SET').length,standaloneComponents:children.filter(x=>x.type==='COMPONENT').length,columnId:col.id,width:GROUP_W};
}
// Real Avatar thumbnails have their own labelled grid; they are never mixed with UI controls.
if(avatarAssetUnits.length){
 const avatarCol=column('Library layout / Avatar part assets',620);avatarCol.x=nextColumnX;avatarCol.y=24;nextColumnX+=660;
 const title=await label(avatarCol,'Library heading / Avatar part assets','Avatar · real part thumbnails',588,titleStyle);avatarCol.insertChild(0,title);touch(avatarCol);touch(title);
 const board=plainFrame(avatarCol,'Avatar part assets · organized',588,1);board.layoutPositioning='AUTO';
 let y=0;const ordered=avatarAssetUnits.sort((a,b)=>a.name.localeCompare(b.name));
 for(let i=0;i<ordered.length;i+=5){let rowHeight=0;for(let j=0;j<Math.min(5,ordered.length-i);j++){const unit=ordered[i+j],b=footprint(unit),entry=plainFrame(board,'Avatar asset entry / '+unit.id,108,b.h+48);entry.x=j*120;entry.y=y;append(entry,unit);unit.x=(108-b.w)/2-b.x;unit.y=-b.y;touch(unit);const name=await label(entry,'Avatar asset label / '+unit.id,unit.name.replace(/^Gensen Refactor\/Avatar thumbnail\//i,''),108,labelStyle);if(name.parent&&'layoutMode'in name.parent&&name.parent.layoutMode!=='NONE')name.layoutPositioning='ABSOLUTE';name.x=0;name.y=b.h+6;entry.resize(108,b.h+6+name.height);touch(entry);rowHeight=Math.max(rowHeight,entry.height);}y+=rowHeight+16;}
 board.resize(588,Math.max(1,y-16));touch(board);maxHeight=Math.max(maxHeight,avatarCol.height);groupCounts['Avatar part assets']={units:ordered.length,columnId:avatarCol.id,boardId:board.id};
}
// Fallback icon masters retain their IDs and their own board, isolated from UI components.
const iconCol=column('Library layout / Fallback icons',620);iconCol.x=nextColumnX;iconCol.y=24;nextColumnX+=660;
const iconHeading=await label(iconCol,'Library heading / Fallback icons','Source icon fallbacks',588,titleStyle);iconCol.insertChild(0,iconHeading);touch(iconHeading);
let iconBoard=library.findOne(n=>n.type==='FRAME'&&n.name.startsWith('Source icon fallbacks'));
if(!iconBoard)iconBoard=plainFrame(iconCol,'Source icon fallbacks · organized',588,1);else append(iconCol,iconBoard);
iconBoard.layoutMode='NONE';iconBoard.fills=[];iconBoard.clipsContent=false;touch(iconBoard);
let ix=0,iy=0,rowH=0;const iconOrder=iconUnits.sort((a,b)=>a.name.localeCompare(b.name));
for(const unit of iconOrder){const b=footprint(unit);if(ix&&ix+b.w>588){ix=0;iy+=rowH+20;rowH=0;}append(iconBoard,unit);unit.x=ix-b.x;unit.y=iy-b.y;touch(unit);ix+=b.w+20;rowH=Math.max(rowH,b.h);}
iconBoard.resize(588,Math.max(1,iy+rowH));touch(iconBoard);maxHeight=Math.max(maxHeight,iconCol.height);
groupCounts['Fallback icons']={units:iconOrder.length,columnId:iconCol.id,boardId:iconBoard.id};
library.layoutMode='NONE';library.clipsContent=false;library.resize(nextColumnX-GAP+24,Math.max(300,maxHeight+48));touch(library);
// Thirty full-screen wardrobe states are a separate gallery, never a narrow library column.
const wardrobeLayouts=[];let wardrobeY=maxHeight+96;
for(const unit of wardrobeUnits){
 const gallery=plainFrame(library,'Library layout / Avatar Wardrobe gallery',Math.max(2000,unit.width+32),unit.height+64);gallery.x=24;gallery.y=wardrobeY;gallery.fills=[surfacePaint()];gallery.strokes=[borderPaint()];gallery.strokeWeight=1;gallery.cornerRadius=14;
 const title=await label(gallery,'Library heading / Avatar Wardrobe gallery','Avatar Wardrobe · full-screen variants',gallery.width-32,titleStyle);if(title.parent&&'layoutMode'in title.parent&&title.parent.layoutMode!=='NONE')title.layoutPositioning='ABSOLUTE';title.x=16;title.y=12;
 append(gallery,unit);unit.x=16;unit.y=title.height+28;touch(unit);gallery.resize(gallery.width,unit.y+unit.height+16);touch(gallery);wardrobeY+=gallery.height+40;
 wardrobeLayouts.push({id:unit.id,name:unit.name,variants:unit.children.filter(n=>n.type==='COMPONENT').length,galleryId:gallery.id,x:gallery.x,y:gallery.y,width:gallery.width,height:gallery.height});
}
if(wardrobeLayouts.length){groupCounts['Avatar Wardrobe gallery']={units:wardrobeUnits.length,variants:wardrobeLayouts.reduce((n,x)=>n+x.variants,0),galleryCount:wardrobeUnits.length};library.resize(Math.max(library.width,...wardrobeLayouts.map(x=>x.x+x.width+24)),Math.max(library.height,wardrobeY));touch(library);}
const sourceScenes=page.children.filter(n=>n.type==='FRAME'&&n.name.startsWith('Source scene · ')&&n.children.length===0&&Array.isArray(n.fills)&&n.fills.some(f=>f.type==='IMAGE')).sort((a,b)=>a.name.localeCompare(b.name));
const sourceIds=new Set(sourceScenes.map(n=>n.id));
const supportNodes=page.children.filter(n=>n.id!==LIBRARY_ID&&!sourceIds.has(n.id));
function intersects(a,b,gap=120){return a.x<b.x+b.width+gap&&a.x+a.width+gap>b.x&&a.y<b.y+b.height+gap&&a.y+a.height+gap>b.y;}
function vacantX(start,y,width,height,obstacles){let x=start;for(let pass=0;pass<=obstacles.length;pass++){const hits=obstacles.filter(n=>intersects({x,y,width,height},n));if(!hits.length)return x;x=Math.max(...hits.map(n=>n.x+n.width))+160;}throw Error('Cannot find an unoccupied library/source lane');}
// If new columns extend into an existing support area, move only the library as
// one intact frame. Existing prototype, Avatar result and support frames stay put.
const libraryOldPosition={x:library.x,y:library.y};library.x=vacantX(library.x,library.y,library.width,library.height,supportNodes);touch(library);
const sourceStackHeight=sourceScenes.reduce((sum,n)=>sum+n.height+40,0),sourceMaxWidth=Math.max(1,...sourceScenes.map(n=>n.width));
const sourceX=vacantX(library.x+library.width+200,180,sourceMaxWidth,sourceStackHeight,[...supportNodes,library]);
let sourceY=180;for(const source of sourceScenes){source.x=sourceX;source.y=sourceY;sourceY+=source.height+40;touch(source);}
const supportChanges=[];for(const node of supportNodes){const old=rootSnapshot.get(node.id);if(old&&(old.x!==node.x||old.y!==node.y||old.width!==node.width||old.height!==node.height))supportChanges.push(node.id);}
const laneOverlaps=[];for(const node of supportNodes)if(intersects(library,node,0))laneOverlaps.push([library.id,node.id]);for(const source of sourceScenes)for(const node of [...supportNodes,library])if(intersects(source,node,0))laneOverlaps.push([source.id,node.id]);
const changedDefinitions=[];for(const unit of units)if(definitionSnapshot.get(unit.id)!==JSON.stringify(unit.componentPropertyDefinitions||{}))changedDefinitions.push(unit.id);
const changedReferences=[];for(const n of page.findAllWithCriteria({types:['INSTANCE']}))if(instanceSnapshot.has(n.id)&&instanceSnapshot.get(n.id)!==(n.mainComponent?.id||null))changedReferences.push(n.id);
if(changedDefinitions.length||changedReferences.length||supportChanges.length)throw Error('Unexpected component API/reference change: '+JSON.stringify({changedDefinitions,changedReferences,supportChanges}));
function packedIds(ids){const groups={};for(const id of new Set(ids)){const cut=id.lastIndexOf(':')+1,prefix=id.slice(0,cut);(groups[prefix]||=[]).push(id.slice(cut));}return Object.fromEntries(Object.entries(groups).map(([prefix,suffixes])=>[prefix,suffixes.join(',')]));}
const result={kind:'organized-refactor-library',pageId:PAGE_ID,libraryId:LIBRARY_ID,createdNodeIdsByPrefix:packedIds(created),mutatedNodeIdsByPrefix:packedIds(mutated),groupCounts,setLayouts:setLayouts.map(s=>[s.id,s.name,s.variants,s.columns,s.width,s.height]),setLayoutColumns:['id','name','variants','columns','width','height'],wardrobeLayouts,sourceScenes:{count:sourceScenes.length,x:sourceX,top:180,bottom:sourceY,nodeIdsByPrefix:packedIds(sourceIds)},preservation:{componentCount:masters.filter(n=>n.type==='COMPONENT').length,componentSetCount:masters.filter(n=>n.type==='COMPONENT_SET').length,checkedInstanceReferences:instanceSnapshot.size,propertyDefinitionsChanged:changedDefinitions,instanceReferencesChanged:changedReferences,supportFramesChanged:supportChanges,laneOverlaps,originalPrototypeTouched:false},libraryBefore:libraryOldPosition,libraryAfter:{x:library.x,y:library.y,width:library.width,height:library.height},warnings};
if(JSON.stringify(result).length>18000){result.warnings={count:warnings.length,examples:warnings.slice(0,10)};result.setLayouts=setLayouts.map(s=>[s.id,s.variants,s.columns,s.width,s.height]);result.setLayoutColumns=['id','variants','columns','width','height'];}
return result;
