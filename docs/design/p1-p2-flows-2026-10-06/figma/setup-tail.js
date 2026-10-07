const page=await figma.getNodeByIdAsync('310:2955');
await figma.loadFontAsync({family:'Nunito',style:'Bold'});
await figma.loadFontAsync({family:'Noto Sans SC',style:'Bold'});
const vars=Object.fromEntries((await figma.variables.getLocalVariablesAsync()).filter(v=>v.name.startsWith('p0/')).map(v=>[v.name.slice(3),v]));
function paint(name){return figma.variables.setBoundVariableForPaint(figma.util.solidPaint('#FBF8F1'),'color',vars[name]);}
const prior=page.findOne(n=>n.type==='COMPONENT_SET'&&n.name==='Gensen / Action Button');
if(prior)throw new Error('Component already exists: '+prior.id);
const collection=figma.variables.createVariableCollection('Gensen · control geometry');
const geo={};
for(const [name,value,scope] of [['control-padding',12,'GAP'],['control-radius',16,'CORNER_RADIUS'],['control-gap',4,'GAP']]){const v=figma.variables.createVariable(name,collection,'FLOAT');v.scopes=[scope];v.setValueForMode(collection.defaultModeId,value);v.setVariableCodeSyntax('WEB','var(--'+name+')');geo[name]=v;}
const type=figma.createTextStyle();type.name='Gensen / Button';type.fontName={family:'Nunito',style:'Bold'};type.fontSize=14;type.lineHeight={unit:'PERCENT',value:130};
const {componentSet,variants}=await createComponentWithVariants({name:'Gensen / Action Button',description:'Text action. Primary commits; Secondary is optional or back; Disabled states the unmet requirement. Product font: Nunito.',variantAxes:{Tone:['Primary','Secondary','Disabled']},baseProps:{width:320,height:44,layoutMode:'HORIZONTAL',radius:16,padding:{top:12,bottom:12,left:12,right:12},itemSpacing:4},page});
const created=[componentSet.id,...variants.map(v=>v.id)];
const labelKey=componentSet.addComponentProperty('Label','TEXT','Continue');
for(let i=0;i<variants.length;i++){const c=variants[i];c.primaryAxisSizingMode='FIXED';c.counterAxisSizingMode='FIXED';c.fills=[paint(['green','soft','disabled'][i])];for(const prop of ['paddingLeft','paddingRight','paddingTop','paddingBottom'])c.setBoundVariable(prop,geo['control-padding']);c.setBoundVariable('cornerRadius',geo['control-radius']);c.setBoundVariable('itemSpacing',geo['control-gap']);const t=figma.createText();created.push(t.id);t.name='Label';t.fontName={family:'Nunito',style:'Bold'};t.textStyleId=type.id;t.characters=['Continue','Not now','Need 2 more Copper Ore'][i];t.textAutoResize='NONE';t.resize(296,19);t.textAlignHorizontal='CENTER';t.fills=[paint(i===2?'muted':'ink')];c.appendChild(t);t.componentPropertyReferences={characters:labelKey};c.x=32+i*352;c.y=48;}
componentSet.x=5500;componentSet.y=-2070;componentSet.resize(1120,150);
const sections=[];
for(const cfg of [{name:'08 · P1日常操作',x:5500,y:-1420,h:4250},{name:'09 · P2免费旅行闭环',x:5500,y:3060,h:2330}]){if(page.children.some(n=>n.name===cfg.name))throw new Error('Section exists');const s=figma.createSection();created.push(s.id);s.name=cfg.name;s.x=cfg.x;s.y=cfg.y;s.resizeWithoutConstraints(2496,cfg.h);s.fills=[paint('soft')];const t=figma.createText();created.push(t.id);t.fontName={family:'Noto Sans SC',style:'Bold'};t.fontSize=34;t.characters=cfg.name;s.appendChild(t);t.x=48;t.y=42;sections.push({id:s.id,name:s.name});}
return {createdNodeIds:created,sections,componentSetId:componentSet.id,variants:variants.map(v=>({id:v.id,name:v.name})),labelKey,textStyleId:type.id,geometryVariables:Object.fromEntries(Object.entries(geo).map(([k,v])=>[k,v.id])),variantCount:variants.length,fonts:['Nunito Bold'],bindings:variants.map(v=>({id:v.id,fills:v.fills,boundVariables:v.boundVariables}))};
