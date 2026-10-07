const T={"canvas": {"width": 360, "height": 800}, "colors": {"surface": "#FBF8F1", "surfaceRaised": "#FFFFFF", "text": "#2F3A33", "secondary": "#5D6A62", "border": "#E1DAC8", "primary": "#3E7D43", "primaryTint": "#ECF4E7", "danger": "#9C3F2E", "dangerTint": "#FFF0EB", "warning": "#8C5F12", "warningTint": "#FFF0D4", "info": "#426A88"}, "font": {"family": "Nunito", "title": 20, "quantity": 24, "effect": 15, "rowTitle": 15, "body": 14, "caption": 12, "button": 15}, "space": {"page": 16, "section": 20, "row": 12, "within": 6}, "radius": {"sheet": 24, "card": 14, "pill": 22, "cell": 11}, "touch": 44, "source": "Existing Nunito/cream/green/rounded visual language; revised contrast and semantic hierarchy authorized by 2026-10-06 complete refactor request."};const VAR={},STYLE={},LEDGER={variables:{},styles:{}};
function rgb(hex){return {r:parseInt(hex.slice(1,3),16)/255,g:parseInt(hex.slice(3,5),16)/255,b:parseInt(hex.slice(5,7),16)/255}};
async function foundations(){
 const available=await figma.listAvailableFontsAsync();
 for(const style of ['Regular','Bold','ExtraBold']){if(!available.some(f=>f.fontName.family===T.font.family&&f.fontName.style===style))throw Error('Install Nunito '+style+' before importing. No silent font substitution.');await figma.loadFontAsync({family:T.font.family,style});}
 const collection=figma.variables.createVariableCollection('Gensen Refactor · Primitives');collection.renameMode(collection.defaultModeId,'Default');
 const semantic=figma.variables.createVariableCollection('Gensen Refactor · Semantic');semantic.renameMode(semantic.defaultModeId,'Default');
 const approvedSourceIds={surface:'VariableID:431:3',surfaceRaised:'VariableID:431:17',text:'VariableID:431:9',border:'VariableID:431:4'};
 for(const [name,value]of Object.entries(T.colors)){let raw=approvedSourceIds[name]?await figma.variables.getVariableByIdAsync(approvedSourceIds[name]):null;if(!raw){raw=figma.variables.createVariable('color/'+name,collection,'COLOR');raw.scopes=[];raw.setValueForMode(collection.defaultModeId,{...rgb(value),a:1});raw.setVariableCodeSyntax('WEB','var(--gensen-raw-'+name+')');}const v=figma.variables.createVariable('color/'+name,semantic,'COLOR');v.scopes=['FRAME_FILL','SHAPE_FILL','TEXT_FILL','STROKE_COLOR'];v.setValueForMode(semantic.defaultModeId,{type:'VARIABLE_ALIAS',id:raw.id});v.setVariableCodeSyntax('WEB','var(--gensen-'+name+')');VAR['color/'+name]=v;LEDGER.variables['color/'+name]=v.id;}
 for(const [category,map]of [['space',T.space],['radius',T.radius]])for(const [name,value]of Object.entries(map)){const v=figma.variables.createVariable(category+'/'+name,semantic,'FLOAT');v.scopes=[category==='space'?'GAP':'CORNER_RADIUS'];v.setValueForMode(semantic.defaultModeId,value);v.setVariableCodeSyntax('WEB','var(--gensen-'+category+'-'+name+')');VAR[category+'/'+name]=v;LEDGER.variables[category+'/'+name]=v.id;}
 for(const [role,size]of Object.entries(T.font)){if(typeof size!=='number')continue;for(const weight of ['Regular','Bold','ExtraBold']){const s=figma.createTextStyle();s.name='Gensen Refactor/'+role+'/'+weight;s.fontName={family:T.font.family,style:weight};s.fontSize=size;s.lineHeight={unit:'PERCENT',value:135};STYLE[role+'/'+weight]=s;LEDGER.styles[role+'/'+weight]=s.id;}}
}

const existing=figma.root.children.find(p=>p.name==='14 · UI semantic refactor · 2026-10-06');
if(existing)return {exists:true,pageId:existing.id};
await foundations();
const page=figma.createPage();page.name='14 · UI semantic refactor · 2026-10-06';await figma.setCurrentPageAsync(page);
const library=figma.createFrame();page.appendChild(library);library.name='Shared native components · edit here';library.resize(1260,2000);library.x=5000;library.y=180;library.fills=[];library.clipsContent=false;
const state={pageId:page.id,libraryId:library.id,variables:LEDGER.variables,styles:LEDGER.styles,createdNodeIds:[page.id,library.id]};
figma.io.write('setup-state.json',JSON.stringify(state));
return state;