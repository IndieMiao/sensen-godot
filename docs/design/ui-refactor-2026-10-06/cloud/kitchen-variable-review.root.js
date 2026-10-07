// Root-only Figma QA. Set operation to remove-herb/remove-fish/restore-fish/restore-herb.
// Executes the authored native reaction using only the private kitchen prototype variables.
const operation='remove-herb';
const owner='COOK-2b',nodeId='482:78',prefix='kitchen/'+owner+'/pick/';
const page=await figma.getNodeByIdAsync('481:53');await figma.setCurrentPageAsync(page);
await Promise.all(['Regular','Bold','ExtraBold'].map(style=>figma.loadFontAsync({family:'Nunito',style})));
const screen=await figma.getNodeByIdAsync(nodeId);if(!screen||screen.type!=='FRAME')throw Error('Missing kitchen frame');
const variables=await figma.variables.getLocalVariablesAsync(),byId=new Map(variables.map(v=>[v.id,v]));
const scoped=variables.filter(v=>v.name.startsWith(prefix)),modeOf=v=>Object.keys(v.valuesByMode)[0];
const valueOf=id=>{const v=byId.get(id);if(!v)throw Error('Unknown variable '+id);return v.valuesByMode[modeOf(v)];};
const before=Object.fromEntries(scoped.map(v=>[v.name,valueOf(v.id)]));
const virtual=new Map(scoped.map(v=>[v.id,valueOf(v.id)]));
const read=data=>{if(data.type==='VARIABLE_ALIAS')return virtual.has(data.value.id)?virtual.get(data.value.id):valueOf(data.value.id);if(data.type==='EXPRESSION'){const values=data.value.expressionArguments.map(read);if(data.value.expressionFunction==='AND')return values.every(Boolean);if(data.value.expressionFunction==='NOT')return !values[0];throw Error('Unsupported condition');}return data.value;};
const selectors={'remove-herb':'Ingredient 2 · selected','remove-fish':'Ingredient 1 · selected','restore-fish':'Kitchen cell · Pond Crucian','restore-herb':'Kitchen cell · Wild Herb'};
const control=screen.findOne(n=>n.name===selectors[operation]);if(!control?.reactions?.length)throw Error('No authored reaction for '+operation);
const pending=[];const collect=actions=>{for(const a of actions){if(a.type==='CONDITIONAL'){const match=a.conditionalBlocks.find(b=>b.condition===undefined||read(b.condition));if(match)collect(match.actions);}else if(a.type==='SET_VARIABLE'){const v=byId.get(a.variableId);if(!v?.name.startsWith(prefix))throw Error('Not a private selection variable');const nextValue=read(a.variableValue);pending.push({v,value:nextValue});virtual.set(v.id,nextValue);}else throw Error('Selection QA cannot execute '+a.type);}};
collect(control.reactions[0].actions);
const grid=screen.findOne(n=>n.name==='Kitchen grid browser'),owned=()=>grid.findAllWithCriteria({types:['TEXT']}).filter(n=>n.name==='Quantity').map(n=>n.characters);
const ownedBefore=owned();for(const {v,value}of pending)v.setValueForMode(modeOf(v),value);const ownedAfter=owned();if(JSON.stringify(ownedBefore)!==JSON.stringify(ownedAfter))throw Error('Selection changed inventory');
const after=Object.fromEntries(scoped.map(v=>[v.name,valueOf(v.id)]));
const priorFish=before[prefix+'fish'],priorHerb=before[prefix+'herb'];const expectedFish=operation==='remove-fish'?false:operation==='restore-fish'?true:priorFish,expectedHerb=operation==='remove-herb'?false:operation==='restore-herb'?true:priorHerb;
if(after[prefix+'fish']!==expectedFish||after[prefix+'herb']!==expectedHerb)throw Error('Actual selection differs from intended '+operation);
if(after[prefix+'fishEmpty']===expectedFish||after[prefix+'herbEmpty']===expectedHerb)throw Error('Inverse selection visibility is stale');
return {operation,owner,nodeId,createdNodeIds:[],mutatedNodeIds:[screen.id,...screen.findAll(()=>true).map(n=>n.id)],mutatedVariableIds:pending.map(x=>x.v.id),before,after,ownedBefore,ownedAfter,inventoryUnchanged:true,scope:'Private prototype selection only; no gameplay resources'};
