/* Native screenshot QA: one place for each fact, 2026-10-06.
 * Rewards already obtained belong to content. The fixed decision area shows
 * upcoming costs only. A future collection preview may explicitly opt into
 * presentation.rewardPlacement='decision'; content then omits those rewards.
 * Append after the current/kitchen and legacy QA adapters.
 */
const CURRENT_QA_BASE={bottom,content,kitchen,navAndDetails,semanticRow};
semanticRow=function(p,row,ownerId){
  const n=CURRENT_QA_BASE.semanticRow(p,row,ownerId);
  if(row.selected){fill(n,'primaryTint');border(n,'primary',2);radius(n,'card');n.name='Selected item row · '+row.title;}
  return n;
};
function currentQaDecisionRewards(s){
  return s.presentation?.rewardPlacement==='decision'&&(s.actions||[]).some(a=>!['navigate','dismiss'].includes(a.kind));
}
bottom=function(p,s,id){
  const keyFacts=(s.keyFacts||[]).filter(q=>q.kind!=='reward'||currentQaDecisionRewards(s));
  const result=CURRENT_QA_BASE.bottom(p,{...s,keyFacts,requirements:s.presentation?.showMaterialSummary?s.requirements:[]},id);
  const fixed=new Set(s.presentation?.fixedNavigationLabels||[]);
  if(result.node&&fixed.size){
    let index=0;for(const action of s.actions||[])if(action.kind==='navigate'&&fixed.has(action.label)){const n=button(result.node,action,'secondary',id);result.node.insertChild(index++,n);}
    result.y=H-16-result.node.height;absolute(result.node,16,result.y);
  }
  return result;
};
navAndDetails=function(p,s,id){
  const fixed=new Set(s.presentation?.fixedNavigationLabels||[]);
  return CURRENT_QA_BASE.navAndDetails(p,{...s,actions:(s.actions||[]).filter(a=>a.kind!=='navigate'||!fixed.has(a.label))},id);
};
content=function(p,s,id,options){
  const keyFacts=(s.keyFacts||[]).filter(q=>q.kind!=='reward'||!currentQaDecisionRewards(s));
  return CURRENT_QA_BASE.content(p,{...s,keyFacts},id,options);
};
function currentQaRecipeFacts(p,s){
  // These three have a purpose-built selected-result footer with their own
  // duration/recovery values. Heat and entrance scenes use other renderers.
  if(!s.kitchen||KITCHEN_SELECTION_IDS.has(s.id)||!['recipe','experiment'].includes(s.kitchen.mode))return;
  const viewport=p.children.find(n=>n.name==='Kitchen content');
  const body=viewport?.children.find(n=>n.name==='Scrollable content');
  if(!body)return;
  const list=(s.keyFacts||[]).filter(q=>q.kind!=='cost'&&q.label!=='Ingredient slots'&&!(q.kind==='reward'&&currentQaDecisionRewards(s)));
  if(!list.length)return;
  const summary=auto(body,'Recipe facts · one copy',CW,'VERTICAL',6);
  facts(summary,list);
  const header=body.children.findIndex(n=>n.type==='INSTANCE'&&n.mainComponent?.id===KIT.ObjectHeader.id);
  body.insertChild(header>=0?header+1:0,summary);
}
kitchen=function(p,s){CURRENT_QA_BASE.kitchen(p,s);currentQaRecipeFacts(p,s);};
function currentQaKitchenFit(p,s){
 const view=p.children.find(n=>n.name==='Kitchen content'),body=view?.children.find(n=>n.name==='Scrollable content'),foot=p.children.find(n=>n.name==='Fixed decision area'),sheet=p.children.find(n=>n.type==='INSTANCE'&&n.name==='Sheet');if(!view||!body||!foot||!sheet)return;
 body.itemSpacing=8;const max=foot.y-196-28,visible=Math.max(120,Math.min(body.height,max)),top=Math.max(196,foot.y-visible-28);sheet.y=top;sheet.resize(360,800-top);fill(sheet,'surface');view.y=top+16;view.resize(328,Math.max(120,foot.y-view.y-12));
 const close=p.children.find(n=>n.name==='Close · 44 px');if(close)close.y=Math.max(132,top-50);
}
const CURRENT_KITCHEN_FIT_BASE=kitchen;
kitchen=function(p,s){CURRENT_KITCHEN_FIT_BASE(p,s);currentQaKitchenFit(p,s);};
