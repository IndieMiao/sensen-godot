const fs=require('fs'),acorn=require('/tmp/gensen-ui-cloud-build/node_modules/acorn');
const mode=process.argv[2],source=fs.readFileSync(process.argv[3],'utf8'),ast=acorn.parse(source,{ecmaVersion:'latest'});let out='';
for(const n of ast.body){if(n.type==='FunctionDeclaration'){if(mode==='screen'&&['legacyShopAssets','legacyShopLibrary'].includes(n.id.name))continue;out+=source.slice(n.start,n.end)+'\n';}else if(mode==='library'&&n.type==='VariableDeclaration'&&n.declarations.some(d=>['LEGACY_SHOP_SVGS','LEGACY_SHOP_MUTATED'].includes(d.id.name)))out+=source.slice(n.start,n.end)+'\n';}
if(mode==='screen')out+="function legacyShopLibrary(){if(!KIT['Compact/ShopProduct/essential']||!KIT['Compact/ShopProduct/detailed']||!ICON['i-sapling']||!ICON['i-rod-carbon'])throw Error('Create and merge the shared shop library first');}\n";
process.stdout.write(out);
