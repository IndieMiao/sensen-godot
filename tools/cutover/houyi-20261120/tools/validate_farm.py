"""Independent schema4 decoder/validator. Does not import the generator."""
import json,math,pathlib,collections,re
import numpy as np
import shapely
from shapely.geometry import Polygon,Point
OPERATIONS=['walk','till','plant','arrange','place']
def require(value,message):
 if not value:raise ValueError(message)
def integer(v):return type(v)==int
def decode(runs,W,H,surface):
 require(isinstance(runs,list),'runs list');cells={};last=None
 for row in runs:
  require(isinstance(row,list) and len(row)==(4 if surface else 3) and all(integer(v) for v in row),'run shape/integer')
  y,x,n=row[:3];require(n>0 and 0<=y<H and 0<=x<x+n<=W,'run bounds')
  require(last is None or (y,x)>last,'run order');last=(y,x)
  if surface:require(row[3] in [0,1,2],'surface')
  for xx in range(x,x+n):require((xx,y) not in cells,'run overlap');cells[(xx,y)]=row[3] if surface else 1
 return cells
def flood(cells,start):
 todo=[start];seen={start}
 while todo:
  x,y=todo.pop()
  for n in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
   if n in cells and n not in seen:seen.add(n);todo.append(n)
 return seen
def geometry(cells):
 arr=np.array(sorted(cells));return shapely.coverage_union_all(shapely.box(arr[:,0],arr[:,1],arr[:,0]+1,arr[:,1]+1))
def validate(f):
 require(f['schema']==4 and f['selection_unit']=='parcel','schema/unit');require(f['game_cell_m']==.8,'cell size')
 address=f.get('address');require(address is None or (isinstance(address,str) and address.strip() and not re.search(r'\b(?:UNKNOWN|NONE|NULL)\b',address,re.IGNORECASE)),'address placeholder')
 require(f.get('name')==(address or 'SF Parcel '+f['parcel_id']),'name fallback')
 require(isinstance(f['seed_hex'],str) and len(f['seed_hex'])==64 and all(c in '0123456789abcdef' for c in f['seed_hex']),'seed')
 require(isinstance(f['stats'].get('core_iou'),(int,float)) and .85<=f['stats']['core_iou']<=1.000001,'core IoU')
 require(f['stats']['core_iou']>=.9 or 'approximation_warning' in f['stats']['recovery_flags'],'degraded shape flag')
 grid=f['grid'];W,H=grid['width'],grid['height'];require(integer(W) and integer(H) and 0<W<=544 and 0<H<=544,'grid bounds')
 require(len(grid['origin_cell'])==2 and all(integer(x) for x in grid['origin_cell']),'origin')
 core=decode(f['zones']['core']['runs'],W,H,True);ext=decode(f['zones']['extension']['runs'],W,H,True);C=set(core);E=set(ext);walk=C|E
 require(not C&E,'zones overlap');require(760<=len(C)<=840 and len(walk)<=8192 and E,'counts bounds')
 require(f['counts']=={'core_cell_count':len(C),'extension_cell_count':len(E),'total_cell_count':len(walk)},'counts exact')
 require(f['capabilities']=={'core':{k:True for k in OPERATIONS},'extension':{k:k=='walk' for k in OPERATIONS}},'capabilities exact')
 reserve=set(decode(f['walk_reserve']['no_solid_decor_runs'],W,H,False));spawn=tuple(f['walk_reserve']['spawn_cell']);entry=tuple(f['walk_reserve']['entry_cell'])
 require(spawn in C and entry in E,'spawn/entry membership');require(C<=reserve<=walk and {spawn,entry}<=reserve,'reserve membership')
 require(flood(walk,spawn)==walk,'walk connected');require(flood(reserve,spawn)==reserve,'protected route connected')
 cg=geometry(C);wg=geometry(walk)
 # Authoritative mask geometry vs visualization rings; renderer may simplify by <=0.25 cell.
 for key,expected in [('core',cg),('outer',wg)]:
  pieces=[]
  for p in f['boundaries'][key]:
   g=Polygon(p['outer'],p['holes']);require(g.is_valid and not g.is_empty,'boundary valid');pieces.append(g)
  actual=shapely.union_all(pieces);require(actual.boundary.hausdorff_distance(expected.boundary)<=.251,'boundary tolerance')
 xy=np.array(sorted(E));ds=shapely.distance(shapely.points(xy[:,0]+.5,xy[:,1]+.5),cg)
 require(float(ds.max())<=10.000001,'extension max width')
 require(all(tuple(p) in reserve for p,d in zip(xy,ds) if d<=2),'2-cell protection')
 # All candidate outside-core centers within 4 cells must be present, even at inward corners.
 xx,yy=np.meshgrid(np.arange(W),np.arange(H));xx=xx.ravel();yy=yy.ravel();d=shapely.distance(shapely.points(xx+.5,yy+.5),cg)
 require(all((int(x),int(y)) in walk for x,y,dd in zip(xx,yy,d) if dd<=4),'4-cell minimum extension')
 return {'core':len(C),'extension':len(E),'total':len(walk),'protected':len(reserve),'width':W,'height':H}
if __name__=='__main__':
 import sys,copy
 r=pathlib.Path(sys.argv[1]);results=[]
 for p in sorted(r.glob('*.json')):
  f=json.loads(p.read_text());results.append({'file':p.name,**validate(f)})
 # Real boundary rejection cases, not duplicate implementation assertions.
 base=json.loads(next(r.glob('p-3139019.json')).read_text());negatives=[]
 for name,mutate in [('unknown_address',lambda f:f.update(name='0 UNKNOWN',address='0 UNKNOWN')),('wrong_fallback',lambda f:f.update(name='UNKNOWN',address=None)),('extension_till',lambda f:f['capabilities']['extension'].__setitem__('till',True)),('count_lie',lambda f:f['counts'].__setitem__('core_cell_count',800)),('outside_spawn',lambda f:f['walk_reserve'].__setitem__('spawn_cell',[-1,-1])),('zero_run',lambda f:f['zones']['extension']['runs'][0].__setitem__(2,0)),('overlap',lambda f:f['zones']['extension']['runs'].append(f['zones']['core']['runs'][0]))]:
  f=copy.deepcopy(base);mutate(f)
  try:validate(f);raise AssertionError(name+' accepted')
  except ValueError:negatives.append(name)
 print(json.dumps({'valid_samples':results,'negative_rejections':negatives,'passed':len(results)+len(negatives)},indent=2))
