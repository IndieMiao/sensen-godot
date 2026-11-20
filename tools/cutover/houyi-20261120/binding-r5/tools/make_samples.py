import pathlib,json,gzip,sys,hashlib,time,collections
import shapely
from shapely.geometry import shape,Polygon
from pyproj import Transformer
from generator import core_from_geometry,build,Rejected,DATASET
R=pathlib.Path(__file__).resolve().parents[1];BASE=R.parent;OUT=R/'samples';OUT.mkdir(exist_ok=True)
with gzip.open(BASE/'parcel-r2/data/physical-parcels.json.gz','rt') as f:rows=json.load(f)
lookup={x['parcel_id']:x for x in rows};stats=[]
for n in ['farm-generation-0.json','farm-generation-1.json']:stats+=json.loads((BASE/'parcel-r3/evidence'/n).read_text())['stats']
longest=max(stats,key=lambda x:max(x['width'],x['height']))['id']
ids=['3139019','3139010','4591A011*',longest]
ids+= [next(x['parcel_id'] for x in rows if len(x['geometry']['coordinates'])>1),next(x['parcel_id'] for x in rows if any(len(p)>1 for p in x['geometry']['coordinates']))]
# Explicit recovery candidates; include failures in sample audit, never forge an output.
ids+=['0118025A','0409003']
proj=Transformer.from_crs(4326,32610,always_xy=True);results=[]
for pid in dict.fromkeys(ids):
 t=time.monotonic();e=lookup.get(pid)
 if e is None:
  for file in sorted((BASE/'parcel-r2/data').glob('parcels-*.json')):
   match=next((x for x in json.loads(file.read_text()) if x.get('mapblklot')==pid and x.get('shape')),None)
   if match:e={'parcel_id':pid,'parcel_ids':[pid],'geometry':match['shape'],'addresses':[]};break
 if e is None:results.append({'parcel_id':pid,'rejected':'source_not_found'});continue
 g=shapely.transform(shape(e['geometry']),proj.transform,interleaved=False)
 meta={'parcel_id':pid,'parcel_aliases':e['parcel_ids'],'name':e['addresses'][0] if e['addresses'] else 'SF Parcel '+pid,'address':e['addresses'][0] if e['addresses'] else None}
 try:
  core=core_from_geometry(g);farm=build('p-'+pid,core,meta)
  # Determinism on the actual same geometry/seed, not a claim about arbitrary dependency versions.
  again=build('p-'+pid,core,meta);assert farm==again
  p=OUT/('p-'+pid+'.json');p.write_text(json.dumps(farm,separators=(',',':'))+'\n')
  results.append({'parcel_id':pid,'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'counts':farm['counts'],'grid':farm['grid'],'stats':farm['stats'],'seconds':time.monotonic()-t})
 except Rejected as ex:results.append({'parcel_id':pid,'rejected':ex.reason,'metrics':ex.metrics,'seconds':time.monotonic()-t})
 print(json.dumps(results[-1]),flush=True)
# Geometry stress fixtures are explicitly synthetic; kept separate from real source-derived samples.
fixtures={'synthetic-concave':Polygon([(0,0),(25,0),(25,8),(10,8),(10,25),(0,25)]),'synthetic-hole':Polygon([(0,0),(30,0),(30,30),(0,30)],holes=[[(10,10),(20,10),(20,20),(10,20)]])}
for key,g in fixtures.items():
 core=core_from_geometry(g);f=build('p-'+key,core,{'parcel_id':key,'name':'Synthetic geometry fixture','address':None});f['test_fixture']=True
 p=OUT/(key+'.json');p.write_text(json.dumps(f,separators=(',',':'))+'\n');results.append({'fixture':key,'file':p.name,'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'counts':f['counts']})
(R/'evidence/sample-generation.json').write_text(json.dumps({'scope':'representative real parcels + labelled synthetic geometry tests; not full-city release','dataset_version':DATASET,'results':results},indent=2)+'\n')
