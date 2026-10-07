/* Append after src.js + current-fixes.js + legacy-fixes.js.
 * World actions keep the circular work control. Facility transactions and result cards never enter this path.
 */
const LEGACY_SCENE_BASE=sceneScreen;
const LEGACY_WORK_VERBS=/^(Sow(?: ×[13])?|Plant|Till|Water|Harvest|Pick|Cast|Mine|Attack|Light Torch|Blast|Drink)$/i;
function legacyWorldAction(s){
 const root=(s.actions||[]).find(a=>['commit','blocked'].includes(a.kind)&&LEGACY_WORK_VERBS.test(a.label||''));if(root)return {action:root,owner:s};
 for(const item of s.items||[]){const a=(item.actions||[]).find(a=>['commit','blocked'].includes(a.kind)&&LEGACY_WORK_VERBS.test(a.label||''));if(a)return {action:a,owner:item};}
 return null;
}
function legacySceneMetric(p,f,y){
 const n=inst(p,'Fact',{Label:f.label||'',Value:String(f.value??'')},CW);n.name='Scene metric · '+f.label;fill(n,'surface',.9);radius(n,'card');absolute(n,16,y);return n;
}
function legacySceneBag(p,s){
 const b=frame(p,'Bag · scene navigation',53,52,'surfaceRaised');radius(b,'cell');border(b);absolute(icon(b,'i-bag',24),15,5);const t=text(b,'Bag',53,'caption','text','Bold');t.textAlignHorizontal='CENTER';absolute(t,0,32);absolute(b,291,704);
 const action=(s.actions||[]).find(a=>/^Bag$/i.test(a.label||''))||{label:'Bag',kind:'navigate',target:s.sourceHtml?'BAG-1':'BAG-1-P0'};PENDING_LINKS.push({node:b,ownerId:s.id,action});
}
function legacyWorldTemplate(p,s,work){
 const a=work.action;
 const costFact=[...(work.owner.keyFacts||[]),...(work.owner===s?[]:s.keyFacts||[])].find(f=>f.kind==='cost');
 const price=costFact?String(costFact.value):s.sceneControls?.cost||(/^Attack$/i.test(a.label)?'Free':'');
 const verb=/^Sow$/i.test(a.label)?'Sow ×1':a.label;
 const main=inst(p,'SceneAction',{Verb:verb,Cost:price});absolute(main,256,580);main.name='World action · '+verb;PENDING_LINKS.push({node:main,ownerId:s.id,action:a,itemContext:work.owner});
 if(a.kind==='blocked'){border(main,'warning',2);fill(main,'warningTint');}
 const tool=/Cast/i.test(verb)?'i-rod':/Mine|Blast|Torch/i.test(verb)?'i-pickaxe':/Attack|Drink/i.test(verb)?'i-sword':'i-hoe';
 const toolHit=frame(p,'Gear · 44 px touch target',44,44);absolute(toolHit,241,566);const badge=frame(toolHit,'Equipped tool badge',28,28,'surface');radius(badge,14);border(badge);absolute(icon(badge,tool,18),5,5);absolute(badge,8,8);PENDING_LINKS.push({node:toolHit,ownerId:s.id,action:{label:'Gear',kind:'navigate',target:s.sourceHtml?'BAG-2':'GEAR-P0-1'}});
 const change=frame(p,'Change action · 44 px',44,44,'surface');radius(change,22);border(change);absolute(icon(change,'i-switch',24),10,10);absolute(change,278,524);PENDING_LINKS.push({node:change,ownerId:s.id,action:{label:'Choose action',kind:'navigate',target:'BAR-2'}});
 const quick=[s.quickItems,s.quickContents,s.sceneControls?.quick,s.sceneState?.quick].find(x=>x?.length);
 if(quick){const bar=auto(p,'Scene Quick Bar · source items',336);bar.x=12;bar.y=708;quickbar(bar,{...s,quickContents:quick,sceneState:{...(s.sceneState||{}),quick}},s.id);}else legacySceneBag(p,s);
 let y=132;
 const factsToShow=(s.keyFacts||[]).filter(f=>f.kind!=='cost'||(costFact&&f.label!==costFact.label));
 for(const item of s.items||[])for(const f of item.keyFacts||[])if(f.kind==='time'||f.kind==='progress')factsToShow.push({...f,label:item.title+' · '+f.label});
 for(const f of factsToShow){const n=legacySceneMetric(p,f,y);y+=n.height+6;}
 // Legacy farm.html: center(300,1600), outer260, knob120, offset(40,-40), all /3 at 360 wide.
 // Current world cards use the same geometry in a neutral pose unless movement is explicitly restricted.
 const movementRestricted=s.presentation?.suppressMovement||s.sceneControls?.movementDisabled||s.sceneControls?.joystick===false;
 const showJoystick=!movementRestricted&&(s.id==='FARM-1'||!s.sourceHtml);
 if(showJoystick&&KIT['ReferenceJoystick/idle']){const joy=inst(p,'ReferenceJoystick/'+(s.id==='FARM-1'?'moving':'idle'));joy.rescale(2/3);absolute(joy,160/3,1460/3);joy.name='Floating joystick · '+(s.id==='FARM-1'?'source thumb pressed':'neutral pose');}
 const other=(s.actions||[]).filter(x=>x!==a&&!/^Bag$|^Gear$|^Choose action$/i.test(x.label||''));
 for(const item of s.items||[])if(item!==work.owner)for(const nav of item.actions||[])if(!other.some(x=>x.label===nav.label&&x.target===nav.target))other.push(nav);
 const hasDetail=Boolean(s.disclosure?.length||s.supporting||s.stateExamples?.length||(s.items||[]).some(x=>x!==work.owner));
 if(other.length||hasDetail){const links=auto(p,'Scene information links',220,'VERTICAL',0);links.x=16;
  for(const nav of other){legacySizedButton(links,nav,'secondary',s.id);}
  if(hasDetail){const n=legacySizedButton(links,{label:'Details',kind:'navigate'},'secondary',s.id);PENDING_LINKS[PENDING_LINKS.length-1].detail={title:s.title,state:s.state,effect:s.effect,quantity:s.quantity,keyFacts:s.keyFacts,requirements:s.requirements,supporting:s.supporting,disclosure:s.disclosure,items:s.items,rows:s.stateExamples,actions:[{label:'Close',kind:'dismiss'}]};}
  links.y=Math.max(y+8,672-links.height);
 }
 LEDGER.checks.legacyWorldTemplates=LEDGER.checks.legacyWorldTemplates||[];LEDGER.checks.legacyWorldTemplates.push({id:s.id,verb,cost:price,quickItems:quick?.length||0,duplicateBagNavigation:false,sourceActionTarget:a.target||null});
}
sceneScreen=function(p,s){
 // Preserve existing P0/P1/P2/P3 explicit controls and nonmodal Buff expiry handling.
 if(s.sceneControls||s.presentation?.suppressDecisionArea){return LEGACY_SCENE_BASE(p,s);}
 const work=legacyWorldAction(s);
 // Kitchens, shops, travel and result moments keep their own UI. No Craft/Cook/Collect conversion.
 if(work&&!/kitchen/.test(sceneKey(s)))return legacyWorldTemplate(p,s,work);
 return LEGACY_SCENE_BASE(p,s);
};
