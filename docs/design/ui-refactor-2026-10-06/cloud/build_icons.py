from pathlib import Path
import json,re
root=Path(__file__).resolve().parent;plugin=root.parent/'figma-plugin'
code=(plugin/'code.js').read_text();bundle=json.JSONDecoder().raw_decode(code.split('const BUNDLE = ',1)[1])[0]
keys=set(bundle['iconNodeIds'])
def visit(x):
 if isinstance(x,dict):
  if x.get('icon'):keys.add(x['icon'])
  if x.get('title') and x['title'].lower() in bundle['assetNames']:keys.add(bundle['assetNames'][x['title'].lower()])
  for v in x.values():visit(v)
 elif isinstance(x,list):
  for v in x:visit(v)
visit(bundle['screens'])
for f in ['src.js','current-fixes.js','legacy-fixes.js']:
 if(plugin/f).exists():keys.update(re.findall(r"['\"](i-[a-z0-9-]+)['\"]",(plugin/f).read_text()))
items=[{'key':k,'id':bundle['iconNodeIds'].get(k),'svg':None if k in bundle['iconNodeIds'] else bundle['iconSvgs'].get(k,bundle['iconSvgs']['i-question'])} for k in sorted(k for k in keys if isinstance(k,str))]
batches=[];batch=[]
for item in items:
 if len(json.dumps(batch+[item]))>22000:batches.append(batch);batch=[]
 batch.append(item)
if batch:batches.append(batch)
for i,items in enumerate(batches):
 script='const items='+json.dumps(items,separators=(',',':'))+''';
const p=await figma.getNodeByIdAsync('481:53');await figma.setCurrentPageAsync(p);
await Promise.all(['Regular','Bold','ExtraBold'].map(style=>figma.loadFontAsync({family:'Nunito',style})));
const library=await figma.getNodeByIdAsync('481:54');const before=new Set(library.findAll(()=>true).map(n=>n.id));
let board=library.children.find(n=>n.name==='Source icon fallbacks');
if(!board){board=figma.createFrame();library.appendChild(board);board.name='Source icon fallbacks';board.resize(700,1600);board.x=500;board.y=72;board.fills=[];board.clipsContent=false;}
const icons={};let reused=0;
for(const item of items){let n=item.id?await figma.getNodeByIdAsync(item.id):null;
if(n&&n.type==='COMPONENT'){icons[item.key]=n.id;reused++;continue;}
const art=figma.createNodeFromSvg(item.svg);const c=figma.createComponent();c.name='Gensen Refactor/Icon/'+item.key;c.resize(64,64);c.fills=[];board.appendChild(c);c.appendChild(art);art.resize(64,64);art.x=0;art.y=0;const index=board.children.length-1;c.x=(index%8)*84;c.y=Math.floor(index/8)*84;icons[item.key]=c.id;
}
return {createdNodeIds:library.findAll(()=>true).filter(n=>!before.has(n.id)).map(n=>n.id),icons,reused,boardId:board.id};'''
 (root/f'icons-{i}.js').write_text(script)
print(json.dumps({'batches':len(batches),'keys':len(keys),'lengths':[len((root/f'icons-{i}.js').read_text()) for i in range(len(batches))]}))
