const fs=require('fs'),acorn=require('/tmp/gensen-ui-cloud-build/node_modules/acorn');
const mode=process.argv[2],path=process.argv[3],source=fs.readFileSync(path,'utf8');const ast=acorn.parse(source,{ecmaVersion:'latest'});let out='';
for(const n of ast.body){const name=n.type==='FunctionDeclaration'?n.id.name:null;const vars=n.type==='VariableDeclaration'?n.declarations.map(d=>d.id.name):[];
 if(mode==='crop-discover'){if(name!=='discoverCropDex')continue;}
 else if(mode==='library'){if(name!=='visualContainerLibrary'&&!vars.includes('CONTAINER_FILTER_IDS'))continue;}
 else{if(n.type!=='FunctionDeclaration')continue;if(['visualContainerLibrary','visualContainerScreen'].includes(name))continue;}
 out+=source.slice(n.start,n.end)+'\n';}
process.stdout.write(out);
