const fs=require('fs'),acorn=require('/tmp/gensen-ui-cloud-build/node_modules/acorn');
const [modeArg,...files]=process.argv.slice(2);const [mode,options='']=modeArg.split(':');const [familyText='',screenText='']=options.split('|');const screenIds=new Set(screenText.split(','));const any=(ids)=>ids.some(id=>screenIds.has(id));const families=new Set(familyText.split(','));const specialReference=any(['FISH-2','CTRL-1','CTRL-1-2','HUD-1','HUD-1-2','STATE-ICONS']);const renderers=new Set('inventory gearScreen shop kitchen collection profile states sceneScreen general guestbook coverage kitchenSceneEntrance actionPickerInto kitchenSelectionInto currentKitchenInto polishBag polishedKitchenScreen fishingSurface currentSceneInto legacyQaSceneInto focusedTutorialKitchen hudReference cameraReference fishingReference badgesReference legacyWorldTemplate'.split(' '));const needed=new Set(['semanticRow']);if(families.has('legacyWorldTemplate'))needed.add('quickbar');if(families.has('actionPickerInto')||families.has('fishingSurface')||families.has('legacyQaSceneInto')||families.has('hudReference')||families.has('currentSceneInto'))needed.add('quickbar');if(families.has('currentKitchenInto'))needed.add('grid');if(families.has('inventory'))for(const x of ['inventory','grid','quickbar'])needed.add(x);if(families.has('gearScreen'))for(const x of ['gearScreen','quickbar'])needed.add(x);if(families.has('shop'))for(const x of ['shop','grid'])needed.add(x);if(families.has('kitchen')||families.has('collection'))needed.add('grid');if(families.has('sceneScreen')||(families.has('states')&&specialReference))needed.add('quickbar');
const helpers=new Set('rgb solid fill border radius bounds frame auto horizontal pad absolute text ctext cvisible component register variantSet propKeys inst inferIcon icon cicon line library refEllipse refRing refText'.split(' '));
let out='';
for(let index=0;index<files.length;index++){
 const source=fs.readFileSync(files[index],'utf8').split('figma.showUI(__html__')[0];
 const ast=acorn.parse(source,{ecmaVersion:'latest'});
 for(const n of ast.body){
  const name=n.type==='FunctionDeclaration'?n.id.name:null;
  const assigned=n.type==='ExpressionStatement'&&n.expression.type==='AssignmentExpression'?n.expression.left.name:null;
  const vars=n.type==='VariableDeclaration'?n.declarations.map(d=>d.id.name):[];
  let txt=source.slice(n.start,n.end);
  if(mode==='library'){
   if(files[index].endsWith('hud-lightweight-fixes.js')&&!['polish','kitchen-polish'].includes(familyText)){if(vars.includes('LIGHT_HUD_BASE'))txt='const LIGHT_HUD_BASE={library};';else if(assigned!=='library'&&!(name&&(/^lightHud/.test(name)||name==='refineSharedHud')))continue;out+=txt+'\n';continue;}
   if(familyText==='kitchen-polish'){if(index===0){if(name&&(!helpers.has(name)||name==='library'))continue;if(n.type==='ExpressionStatement')continue;if(vars.includes('SCENE_CACHE'))continue;}else if(files[index].endsWith('kitchen-selection-state-fixes.js')){if(!['kitchenSelectionLibrary','kitchenPickValues','kitchenPickKey'].includes(name))continue;}else if(!files[index].endsWith('visual-kitchen-fixes.js')||!(name?.startsWith('kitchenPolish')||vars.includes('KITCHEN_POLISH_FILTERS')))continue;out+=txt+'\n';continue;}
   if(familyText==='polish'){if(index===0){if(name&&(!helpers.has(name)||name==='library'))continue;if(n.type==='ExpressionStatement')continue;if(vars.includes('SCENE_CACHE'))continue;}else if(!files[index].endsWith('visual-polish-fixes.js')||!(name?.startsWith('polish')||vars.includes('POLISH_FILTERS')))continue;out+=txt+'\n';continue;}
   if(index===0){if(name&&!helpers.has(name))continue;if(n.type==='ExpressionStatement')continue;if(vars.includes('SCENE_CACHE'))continue;}
   else {if(!['refEllipse','refRing','refText','ensureHudNavigation','applyResponsiveLabelSizing','polishLibrary','polishText','polishProperty','polishQuickProperty','polishBox','polishMaster'].includes(name)&&assigned!=='library'&&!vars.includes('currentLibraryBase')&&!vars.includes('LEGACY_BASE')&&!vars.includes('LEGACY_REFERENCE_BASE')&&!vars.includes('KITCHEN_SCENE_BASE')&&!vars.includes('KITCHEN_SELECTION_BASE')&&!vars.includes('HUD_NAVIGATION_BASE')&&!vars.includes('RESPONSIVE_LABEL_LIBRARY_BASE')&&!vars.includes('POLISH_BASE'))continue;}
   if(vars.includes('LEGACY_BASE'))txt='const LEGACY_BASE={library};';if(vars.includes('LEGACY_REFERENCE_BASE'))txt='const LEGACY_REFERENCE_BASE={library};';if(vars.includes('KITCHEN_SCENE_BASE'))txt='const KITCHEN_SCENE_BASE={library};';if(vars.includes('KITCHEN_SELECTION_BASE'))txt='const KITCHEN_SELECTION_BASE={library};';if(vars.includes('HUD_NAVIGATION_BASE'))txt='const HUD_NAVIGATION_BASE={library};';if(vars.includes('POLISH_BASE'))txt='const POLISH_BASE={library};';
  } else {
   const file=files[index];
   if((name==='quickbar'||assigned==='quickbar')&&!needed.has('quickbar'))continue;
   const currentVisualSource=files.find(f=>f.endsWith('current-visual-fixes.js')),currentVisualActive=currentVisualSource&&[...screenIds].some(id=>fs.readFileSync(currentVisualSource,'utf8').includes(JSON.stringify(id)));
   if(file.endsWith('free-travel-flow-fixes.js')){if(!any(['LOCAL-SHOP','LOCAL-TRADE','LOCAL-BOUGHT','LOCAL-CATCH']))continue;if(['freeTravelBuild','freeTravelNote'].includes(name))continue;if(assigned==='wire')txt=txt.replace('for(const s of BUNDLE.freeTravelStates||[])await freeTravelBuild(s);','');}
   if(file.endsWith('current-visual-fixes.js')&&!currentVisualActive)continue;
   if(file.endsWith('current-kitchen-focus-fixes.js')){if(!screenIds.has('TUT-3-07B'))continue;if(vars.includes('CURRENT_KITCHEN_FOCUS_BASE')){out+='const CURRENT_KITCHEN_FOCUS_BASE={createDetail};\n';continue;}if(['hud','kitchen'].includes(assigned))continue;}
   if(file.endsWith('kitchen-selection-state-fixes.js')){if(!any(['COOK-2b','COOK-P0-2']))continue;if(assigned==='kitchenPolishStage')txt=txt.replace('if(book)return KITCHEN_PICK_BASE.kitchenPolishStage(p,s,book);','');if(assigned==='library'||name==='kitchenSelectionLibrary')continue;if(vars.includes('KITCHEN_PICK_BASE')){out+='const KITCHEN_PICK_BASE={kitchenPolishGrid,polishedKitchenScreen};\n';continue;}}
   if(file.endsWith('legacy-pin-fixes.js')&&families.size===1&&families.has('shop'))continue;
   if(file.endsWith('legacy-npc-flow-fixes.js')&&!screenIds.has('NPC_FLOW_CREATE')){if(!any(['COOK-4','COOK-6','FARM-6','FARM-6-2','BAG-2','BAG-2-2','NPC-1','NPC-2','NPC-2-2','NPC-3','NPC-3-2','NPC-4','NPC-7']))continue;if(name==='npcFlowFact')continue;if(name==='buildLegacyNpcFlowStates'){out+='async function buildLegacyNpcFlowStates(){npcFlowDiscover();return {createdNodeIds:[],npcFlowScreens:LEDGER.npcFlowScreens};}\n';continue;}}
   if(file.endsWith('unknown-requirement-fixes.js')&&!screenIds.has('BUFF-RATIONS-USE'))continue;
   if(vars.includes('LIGHT_HUD_BASE')){out+='const LIGHT_HUD_BASE={hud};\n';continue;}
   if(file.endsWith('legacy-pin-fixes.js')&&families.size===1&&(families.has('polishedKitchenScreen')||families.has('currentKitchenInto')))continue;
   if(file.endsWith('p2p3-visual-fixes.js')&&!currentVisualActive&&![...screenIds].some(id=>source.includes(JSON.stringify(id))))continue;
   if(file.endsWith('visual-fishing-fixes.js')&&!any(['FISH-3','FISH-4']))continue;
   if(file.endsWith('visual-kitchen-fixes.js')){if(!any(['COOK-2a','COOK-2b','COOK-P0-2','TUT-3-07B'])&&!(families.has('currentKitchenInto')&&name==='kitchenPolishCamera'))continue;if(families.has('focusedTutorialKitchen')&&!['kitchenPolishText','kitchenPolishCamera','kitchenPolishStage','polishedKitchenHud'].includes(name))continue;if(name==='kitchenPolishStage'&&!any(['COOK-2a','TUT-3-07B'])){out+='let kitchenPolishStage;\n';continue;}if(name==='polishedKitchenScreen'&&!screenIds.has('COOK-2a'))txt=txt.replace("const book=s.id==='COOK-2a'",'const book=false');if(assigned==='hud'||assigned==='kitchen')continue;if(vars.includes('KITCHEN_POLISH_BASE'))continue;if(name==='kitchenPolishLibrary'||name==='kitchenPolishFilterVariables')continue;}
   if(file.endsWith('legacy-reference-fixes.js')&&assigned==='states'&&!specialReference)continue;
   if(file.endsWith('flow-repair-fixes.js')&&!any(['MINE-4','RESIDENT-MEAL-DONE','COOK-P0-6','MINE-5-ARRIVAL','RESIDENT-TALK-MEAL-CLAIMED','COOK-CABINET-TAKEN','COOK-CABINET-EATEN']))continue;
   if(file.endsWith('visual-polish-fixes.js')){if(!screenIds.has('BAG-1')&&!['polishQuickItems','polishQuickSlot','polishQuickBar'].includes(name))continue;if(assigned==='hud'||assigned==='inventory')continue;if(vars.includes('POLISH_BASE'))continue;if(name==='polishLibrary')continue;}
   if(file.endsWith('camera-highlight-fixes.js')&&(families.size===1&&families.has('states')||!any(['BAR-3','BOARD-1','DAYPASS','DEX-P1-2','HUD-3','HUD-4','MAP-7-FREE','MAT-1','NEED-TILE','NPC-4','NPC-4-2','PASS-2','SKILL-2','TODAY-1','TODAY-2','TRADER','ENERGY-P0-1'])))continue;
   if(file.endsWith('legacy-qa-fixes.js')){
    const active={inst:families.has('states')||families.has('hudReference')||families.has('fishingReference'),referenceBoard:families.has('states')||['hudReference','cameraReference','fishingReference','badgesReference'].some(x=>families.has(x)),states:families.has('states')&&specialReference,general:false,sceneScreen:any(['BAR-1','BAR-1-2','BAR-3-2','FARM-7']),inventory:screenIds.has('BAG-4'),shop:any(['FARM-6','FARM-6-2']),hud:any(['BAR-3','HUD-3','BAR-3-2'])};
    if(assigned&&active[assigned]===false&&assigned!=='states')continue;
    if(assigned==='states'&&!specialReference)txt=txt.replace('if(LEGACY_REFERENCE_IDS.has(s.id))return LEGACY_QA_BASE.states(p,s);','');
    if(vars.includes('LEGACY_QA_BASE')){txt='const LEGACY_QA_BASE={'+Object.keys(active).filter(k=>k!=='referenceBoard'&&active[k]&&(!renderers.has(k)||families.has(k))).join(',')+'};';out+=txt+'\n';continue;}
   }
   if(file.endsWith('camera-highlight-fixes.js')&&assigned==='general')continue;
   if(vars.includes('HUD_NAVIGATION_BASE')||n.type==='VariableDeclaration'&&n.declarations.some(d=>d.init?.type==='Identifier'&&['buildScreen','library'].includes(d.init.name)))continue;
   if(['foundations','sourceAssets','library','run','validate','buildScreen'].includes(name)||['library','buildScreen'].includes(assigned)||vars.includes('currentLibraryBase')||vars.includes('currentBuildBase'))continue;
   if(vars.includes('LEGACY_BASE'))txt='const LEGACY_BASE={'+[...needed].join(',')+'};';if(vars.includes('LEGACY_REFERENCE_BASE')){if(!families.has('states')||!specialReference)continue;txt='const LEGACY_REFERENCE_BASE={states};';}
   if(vars.includes('KITCHEN_SCENE_BASE'))txt='const KITCHEN_SCENE_BASE={'+['sceneScreen','kitchen'].filter(x=>families.has(x)).join(',')+'};';
   if(vars.includes('KITCHEN_SELECTION_BASE'))txt='const KITCHEN_SELECTION_BASE={'+(families.has('kitchen')?'kitchen':'')+'};';
   if(vars.includes('LEGACY_QA_BASE'))txt='const LEGACY_QA_BASE={'+['inst','referenceBoard','states','general','sceneScreen','inventory','shop','hud'].filter(x=>!renderers.has(x)||families.has(x)).join(',')+'};';
   if(vars.includes('CURRENT_KITCHEN_FIT_BASE')&&!families.has('kitchen'))continue;
   if(vars.includes('CURRENT_QA_BASE'))txt='const CURRENT_QA_BASE={'+['bottom','content','kitchen','navAndDetails','semanticRow'].filter(x=>!renderers.has(x)||families.has(x)).join(',')+'};';
   if(vars.includes('CAMERA_HIGHLIGHT_BASE'))txt='const CAMERA_HIGHLIGHT_BASE={contextDetail,createDetail};';
   if(renderers.has(name)&&!families.has(name))continue;
   if(renderers.has(assigned)&&!families.has(assigned))continue;
   if((vars.includes('currentGearBase')&&!families.has('gearScreen'))||((vars.includes('currentSceneBase')||vars.includes('LEGACY_SCENE_BASE'))&&!families.has('sceneScreen')))continue;
  }
  out+=txt+'\n';
 }
}
process.stdout.write(out);
