/* Standalone-plugin canonical Profile adapter. Cloud compose handles this
 * frame explicitly, so this adapter does not change the frozen upload source. */
const AVATAR_CANONICAL_PREVIOUS_BUILD = buildScreen;
buildScreen = function(s,index){
 if(s.id!=='PROFILE-1-P0')return AVATAR_CANONICAL_PREVIOUS_BUILD(s,index);
 avatarEnsureLibrary();
 const box=figma.createSection();box.name='Review · '+s.id;PAGE.appendChild(box);box.resizeWithoutConstraints(360,1080);fill(box);box.x=100+(index%8)*412;box.y=180+Math.floor(index/8)*1070;
 const screen=frame(box,s.id+' · Profile',360,800,'surface');screen.clipsContent=true;
 avatarSavedComposition(screen,'base');avatarWire();
 reviewNote(box,{...s,sourceNote:s.sourceNote+' Real existing Avatar render. Edit look opens the original upper-preview/lower-grid dressing layout; Back discards the draft, Done saves the demonstrated look.'},816);
 LEDGER.screens[s.id]=screen.id;LEDGER.avatar=avatarLedger();LEDGER.sourceReferences[s.id]={newNodeId:screen.id,sourceNodeId:s.sourceRef?.nodeId||null,sourceFile:'scenes/dressing_room/dressing_room.tscn',actualRenderedAssets:true};
 return screen;
};
