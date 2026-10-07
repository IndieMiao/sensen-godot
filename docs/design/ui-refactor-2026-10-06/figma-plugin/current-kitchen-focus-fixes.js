/* First-session recipe and authored first heat moment. Use the approved pot
 * camera and shared Compact components; keep the owner HUD values unchanged. */
const CURRENT_KITCHEN_FOCUS_BASE={hud,kitchen,createDetail};
function focusedTutorialKitchen(p,s){
  kitchenPolishCamera(p);kitchenPolishStage(p,s,true);
  const sheet=frame(p,'Compact/Tutorial kitchen focus drawer',360,244,'surface');radius(sheet,20);sheet.bottomLeftRadius=sheet.bottomRightRadius=0;absolute(sheet,0,556);
  const head=horizontal(p,'Compact/Tutorial stove identity',280,8);absolute(head,12,572);kitchenPolishText(head,'Stove 1',88,14,'ExtraBold');kitchenPolishText(head,'Empty',50,11,'Bold','secondary');kitchenPolishText(head,'Cooking Lv1',118,11,'Bold','secondary');
  const close=frame(p,'Close tutorial recipe · 44 px',44,44,'surface');radius(close,22);border(close,'border',.6);absolute(icon(close,'i-close',16),14,14);absolute(close,304,558);PENDING_LINKS.push({node:close,ownerId:s.id,action:{label:'Close',kind:'dismiss',target:'COOK-P0-1'}});
  const modes=horizontal(p,'Compact/Tutorial kitchen modes',336,12);absolute(modes,12,609);inst(modes,'Compact/Kitchen/Mode/selected',{Title:'Cookbook','Show count':false});const experiment=inst(modes,'Compact/Kitchen/Mode/default',{Title:'Experiment','Show count':false});PENDING_LINKS.push({node:experiment,ownerId:s.id,action:{label:'Experiment',kind:'navigate',target:'COOK-P0-2'}});
  const wrap=frame(p,'Compact/Tutorial selected recipe',336,72);absolute(wrap,12,655);inst(wrap,'Compact/Kitchen/Recipe',{Title:'Grilled Crucian',State:'Common',Effect:'+20 Energy',Icon:ICON['i-dish-grilled'].id});
  const cook=inst(wrap,'Compact/Command',{Label:'Cook'},90);absolute(cook,238,28);PENDING_LINKS.push({node:cook,ownerId:s.id,detail:{title:'Grilled Crucian',tutorialHeat:true,ownerId:s.id}});
  const details=inst(p,'Compact/Navigation',{Label:'Recipe details ›'},164);absolute(details,12,740);PENDING_LINKS.push({node:details,ownerId:s.id,detail:{title:s.title,state:s.state,requirements:s.requirements,disclosure:s.disclosure,actions:[{label:'Close',kind:'dismiss'}]}});
  kitchenPolishText(p,'Uses 1 Pond Crucian',156,12,'Bold','secondary').name='Tutorial ingredient cost';const cost=p.children[p.children.length-1];absolute(cost,192,755);
  LEDGER.sourceReferences[s.id]={...(LEDGER.sourceReferences[s.id]||{}),layout:'focused-tutorial-recipe',potVisible:true,recipeConsumesOneFish:true,heatSeconds:5};
}
function tutorialHeatMaster(){
  let c=KIT['HeatRing/tutorial']||LIBRARY.children.find(n=>n.type==='COMPONENT'&&n.name==='Gensen Refactor/HeatRing/tutorial');if(c)return c;
  c=KIT.HeatRing.clone();LIBRARY.appendChild(c);c.name='Gensen Refactor/HeatRing/tutorial';c.fills=[];c.x=1500;c.y=200;c.description='First5-second cook: 50% gold window. Transparent centre keeps the selected3D pot visible.';
  const gold=c.findOne(n=>n.name==='Gold timing zone');gold.arcData={startingAngle:-Math.PI/2,endingAngle:Math.PI/2,innerRadius:.84};fill(gold,'warning');KIT['HeatRing/tutorial']=c;LEDGER.components['HeatRing/tutorial']=c.id;return c;
}
function tutorialHeatDetail(detail,ownerId){
  const source=BUNDLE.screens.find(s=>s.id===ownerId);if(!source)throw Error('Tutorial heat needs its source recipe context');
  const n=overlayFrame('Tutorial heat · '+ownerId,H);n.cornerRadius=0;scene(n,source);kitchenPolishCamera(n);polishedKitchenHud(n,source);
  const fish=icon(n,'i-fish',27);absolute(fish,166,175);fish.opacity=.55;
  const master=tutorialHeatMaster(),ring=master.createInstance();n.appendChild(ring);ring.name='First cook · pot heat control';absolute(ring,120,133);PENDING_LINKS.push({node:ring,ownerId,action:{label:'Tap pot in gold',kind:'commit',target:'TUT-3-07C'}});
  const message=auto(n,'Compact/Tutorial heat instruction',304,'VERTICAL',6,'surface');pad(message,12);radius(message,14);absolute(message,28,668);const header=horizontal(message,'Recipe and remaining time',280,8);kitchenPolishText(header,'Grilled Crucian',202,14,'ExtraBold');kitchenPolishText(header,'0:03',70,14,'ExtraBold');kitchenPolishText(message,'Tap the pot when the needle is in gold.',280,12,'Bold');
  LEDGER.overlays[n.id]={title:'First cook · Grilled Crucian',ownerId,type:'tutorial-heat',durationSeconds:5,shownMomentSeconds:2.5,firstGoldWindow:.5,successTarget:'TUT-3-07C'};return n;
}
hud=function(p,s){return s.id==='TUT-3-07B'?polishedKitchenHud(p,s):CURRENT_KITCHEN_FOCUS_BASE.hud(p,s);};
kitchen=function(p,s){return s.id==='TUT-3-07B'?focusedTutorialKitchen(p,s):CURRENT_KITCHEN_FOCUS_BASE.kitchen(p,s);};
createDetail=function(detail,ownerId){return detail.tutorialHeat?tutorialHeatDetail(detail,ownerId):CURRENT_KITCHEN_FOCUS_BASE.createDetail(detail,ownerId);};
