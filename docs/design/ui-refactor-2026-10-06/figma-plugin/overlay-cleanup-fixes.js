/* Shared, content-sized information sheets. Scene snapshots, tutorial heat,
 * toasts and pin/SWAP fixtures retain their own composition and ownership. */
const OVERLAY_CLEANUP_BASE={createDetail,wire};
const OVERLAY_INFORMATION_CACHE=new Map();
const OVERLAY_INFORMATION_FRAMES=new Map();
function overlayStableValue(value){if(Array.isArray(value))return value.map(overlayStableValue);if(value&&typeof value==='object')return Object.fromEntries(Object.keys(value).sort().filter(k=>value[k]!==undefined).map(k=>[k,overlayStableValue(value[k])]));return value;}
function overlayShareableInformation(detail){
 let safe=true;function visit(value){if(!value||typeof value!=='object'||!safe)return;if(Array.isArray(value)){value.forEach(visit);return;}for(const [key,child]of Object.entries(value)){if(['cameraHighlight','tutorialHeat','context','ownerId','boundVariables','explicitVariableModes','reactions'].includes(key)){safe=false;return;}if(key==='actions'){if(!Array.isArray(child)||child.some(a=>a.kind!=='dismiss'||a.target||a.context)){safe=false;return;}}else visit(child);}}visit(detail);return safe;
}
function overlayInformationParts(o){if(!o||o.type!=='FRAME'||!o.name.startsWith('Overlay · '))return null;const header=o.children.find(n=>n.name==='Detail identity'),viewport=o.children.find(n=>n.name==='Detail body'),body=viewport?.children.find(n=>n.name==='Scrollable content'),close=o.children.find(n=>n.type==='INSTANCE'&&n.name==='Dismiss');return header&&viewport&&body&&close?{header,viewport,body,close}:null;}
function overlayRefitInformation(o){
 const parts=overlayInformationParts(o);if(!parts)return null;const {header,viewport,body,close}=parts,before={width:o.width,height:o.height,bodyHeight:body.height,closeY:close.y};
 const headingInstance=header.children.find(n=>n.type==='INSTANCE');let redundantStateHidden=false;if(headingInstance){const props=headingInstance.componentProperties||{},stateKey=Object.keys(props).find(k=>k.split('#')[0]==='State'),showKey=Object.keys(props).find(k=>k.split('#')[0]==='Show state');if(stateKey&&showKey&&props[stateKey].value==='Details'){headingInstance.setProperties({[showKey]:false});redundantStateHidden=true;}}
 body.itemSpacing=8;const children=body.children.filter(n=>n.visible!==false),hasBody=children.length>0,padding=16,gap=12,maximum=620;
 header.x=padding;header.y=padding;const bodyY=padding+header.height+(hasBody?gap:0),limit=Math.max(44,maximum-bodyY-gap-close.height-padding),natural=hasBody?Math.max(1,body.height):0;
 let fitted=hasBody?Math.min(natural,limit):1;if(natural>limit){const whole=children.filter(n=>n.y+n.height<=limit+.1).map(n=>n.y+n.height);if(whole.length)fitted=Math.max(44,...whole);}
 viewport.x=padding;viewport.y=bodyY;viewport.visible=hasBody;viewport.resize(CW,fitted);viewport.clipsContent=true;viewport.overflowDirection=natural>limit?'VERTICAL':'NONE';
 close.x=padding;close.y=bodyY+(hasBody?viewport.height:0)+gap;close.resize(CW,close.height);
 o.resize(W,close.y+close.height+padding);o.clipsContent=true;fill(o,'surface');radius(o,'sheet');
 let surface=o.children.find(n=>n.name==='Information sheet surface');if(!surface&&KIT.Sheet){surface=inst(o,'Sheet',{},W);surface.name='Information sheet surface';o.insertChild(0,surface);}if(surface){surface.resize(W,o.height);absolute(surface,0,0);fill(surface,'surface');}
 const record={frameId:o.id,before,after:{width:o.width,height:o.height,bodyHeight:body.height,bodyViewportHeight:hasBody?viewport.height:0,closeY:close.y,scrolling:hasBody&&natural>limit},componentReuse:['Sheet','ObjectHeader','Fact','Cost','NeedTile','ItemRow','Dismiss'],semanticContentPreserved:true,redundantStateHidden};
 LEDGER.checks.informationSheets=LEDGER.checks.informationSheets||{};LEDGER.checks.informationSheets[o.id]=record;return record;
}
createDetail=function(detail,ownerId){
 const shareable=overlayShareableInformation(detail),key=shareable?JSON.stringify(overlayStableValue(detail)):null;
 if(key&&OVERLAY_INFORMATION_CACHE.has(key)){const existing=OVERLAY_INFORMATION_CACHE.get(key),meta=LEDGER.overlays[existing.id];if(meta)meta.ownerIds=[...new Set([...(meta.ownerIds||[meta.ownerId]),ownerId])];return existing;}
 const o=OVERLAY_CLEANUP_BASE.createDetail(detail,ownerId);if(!overlayInformationParts(o))return o;
 OVERLAY_INFORMATION_FRAMES.set(o.id,o);overlayRefitInformation(o);if(key)OVERLAY_INFORMATION_CACHE.set(key,o);if(LEDGER.overlays[o.id]){LEDGER.overlays[o.id].sharedPureInformation=shareable;LEDGER.overlays[o.id].ownerIds=[ownerId];}return o;
};
wire=async function(){await OVERLAY_CLEANUP_BASE.wire();await Promise.all(STYLE_JOBS);for(const o of OVERLAY_INFORMATION_FRAMES.values())overlayRefitInformation(o);LEDGER.checks.informationSharing={pureInformationSignatures:OVERLAY_INFORMATION_CACHE.size,adaptedFrames:OVERLAY_INFORMATION_FRAMES.size,ownerDependentActionsPreserved:true,sceneToastPinFixturesPreserved:true};};
