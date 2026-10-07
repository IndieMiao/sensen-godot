/* One authored save-failure fixture. Shares the verified real wardrobe instance;
 * Close/Keep editing hide this failure overlay and retain the Silver Crop draft. */
const AVATAR_RECOVERY_BASE={buildScreen,library};
const AVATAR_RECOVERY_KEY='avatar/recovery/error-visible';
async function avatarRecoveryVariables(){const collections=await figma.variables.getLocalVariableCollectionsAsync();let c=collections.find(x=>x.name==='Gensen · Avatar save recovery · Prototype');if(!c)c=figma.variables.createVariableCollection('Gensen · Avatar save recovery · Prototype');const variables=await figma.variables.getLocalVariablesAsync();let v=variables.find(x=>x.name===AVATAR_RECOVERY_KEY&&x.variableCollectionId===c.id);if(!v)v=figma.variables.createVariable(AVATAR_RECOVERY_KEY,c,'BOOLEAN');v.scopes=['ALL_SCOPES'];v.setValueForMode(c.defaultModeId,true);v.description='Prototype-only error visibility. Hiding the modal preserves the live wardrobe instance and its unsaved preview.';VAR[AVATAR_RECOVERY_KEY]=v;LEDGER.variables[AVATAR_RECOVERY_KEY]=v.id;return v;}
library=async function(){await AVATAR_RECOVERY_BASE.library();await avatarRecoveryVariables();};
function avatarRecoveryInto(screen,s){
 avatarEnsureLibrary();const master=AVATAR_VIEW.views.hairhat0;if(!master)throw Error('Verified Silver Crop wardrobe variant is required');const shown=VAR[AVATAR_RECOVERY_KEY];if(!shown)throw Error('Avatar recovery variable required');
 const draft=master.createInstance();screen.appendChild(draft);absolute(draft,0,0);draft.name='Verified Silver Crop draft · remains unsaved';
 const baseProfile=LEDGER.screens['PROFILE-1-P0'],savedProfile=LEDGER.screens['KEEP-P0-2'];if(!baseProfile||!savedProfile)throw Error('Existing Profile destinations required');
 const navigate=(node,id)=>STYLE_JOBS.push(node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'NODE',destinationId:id,navigation:'NAVIGATE',transition:null,resetInteractiveComponents:true}]}]));
 const hide=node=>STYLE_JOBS.push(node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'SET_VARIABLE',variableId:shown.id,variableValue:{type:'BOOLEAN',resolvedType:'BOOLEAN',value:false}}]}]));
 const block=node=>STYLE_JOBS.push(node.setReactionsAsync([{trigger:{type:'ON_CLICK'},actions:[{type:'SET_VARIABLE',variableId:shown.id,variableValue:{type:'BOOLEAN',resolvedType:'BOOLEAN',value:true}}]}]));
 const back=draft.findOne(n=>n.name==='Back · discard unsaved try-on');if(back)navigate(back,baseProfile);
 const shade=frame(screen,'Save failure · input shield',360,800);shade.fills=[solid('#000000',.14)];absolute(shade,0,0);shade.setBoundVariable('visible',shown);block(shade);
 const panel=auto(screen,'Avatar save failure · recoverable draft',328,'VERTICAL',8,'surface');pad(panel,16);radius(panel,'card');panel.setBoundVariable('visible',shown);block(panel);
 const heading=horizontal(panel,'Failure title and close',296,0);heading.resize(296,44);heading.counterAxisSizingMode='FIXED';text(heading,'Save failed',252,'title','text','ExtraBold');const close=inst(heading,'Close',{},44);close.name='Close error · keep draft';hide(close);
 text(panel,"Your changes are still here.\nRetry when you're connected.",296,'body','secondary');
 const retry=inst(panel,'Command/primary',{Label:'Retry'},296);retry.name='Retry · save displayed Silver Crop draft';navigate(retry,savedProfile);
 const edit=inst(panel,'Dismiss',{Label:'Keep editing'},296);edit.name='Keep editing · preserve draft';hide(edit);
 const discard=inst(panel,'Command/danger-secondary',{Label:'Discard changes'},296);discard.name='Discard draft · original Profile';navigate(discard,baseProfile);
 absolute(panel,16,784-panel.height);
 LEDGER.checks.avatarRecovery={screenId:screen.id,draftInstanceId:draft.id,draftMasterId:master.id,visibilityVariableId:shown.id,retryTarget:savedProfile,discardTarget:baseProfile,closeAndKeepEditing:'hide overlay only; no navigation or draft reset',existingWardrobeMastersUnchanged:true};
 return screen;
}
buildScreen=function(s,index){if(s.id!=='SAVE-RETRY')return AVATAR_RECOVERY_BASE.buildScreen(s,index);const box=figma.createSection();box.name='Review · '+s.id;PAGE.appendChild(box);box.resizeWithoutConstraints(360,1000);fill(box);box.x=100+(index%8)*412;box.y=180+Math.floor(index/8)*1070;const screen=frame(box,s.id+' · Save failed',360,800,'surface');screen.clipsContent=true;avatarRecoveryInto(screen,s);reviewNote(box,s,816);LEDGER.screens[s.id]=screen.id;LEDGER.sourceReferences[s.id]={sourceNodeId:s.sourceRef?.nodeId,newNodeId:screen.id,layout:'existing-wardrobe-save-recovery',actualRenderedAvatar:true};return screen;};
