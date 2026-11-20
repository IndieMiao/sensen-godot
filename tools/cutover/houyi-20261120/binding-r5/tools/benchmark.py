import pathlib,gzip,json,time,random,statistics,sys
import shapely
from shapely.geometry import shape
from pyproj import Transformer
from generator import core_from_geometry,build,Rejected
from validate_farm import validate
R=pathlib.Path(__file__).resolve().parents[1];proj=Transformer.from_crs(4326,32610,always_xy=True)
with gzip.open(R/'audit/source-candidates.json.gz','rt') as f:allrows=json.load(f)
rows=random.Random(49904).sample(allrows,min(500,len(allrows)));records=[];rejects=[];t=time.monotonic()
for row in rows:
 started=time.monotonic();pid=row['parcel_id'];g=shapely.transform(shape(row['geometry']),proj.transform,interleaved=False)
 meta={'parcel_id':pid,'parcel_aliases':row['parcel_ids'],'address':row['addresses'][0] if row['addresses'] else None}
 try:
  core=core_from_geometry(g);core['flags']+=row.get('recovery_flags',[]);farm=build('p-'+pid,core,meta);generated=time.monotonic();validate(farm)
  records.append({'id':pid,'gen_ms':(generated-started)*1000,'validate_ms':(time.monotonic()-generated)*1000,'bytes':len(json.dumps(farm,separators=(',',':'))),'counts':farm['counts'],'flags':farm['stats']['recovery_flags']})
 except Rejected as ex:rejects.append({'id':pid,'reason':ex.reason,'metrics':ex.metrics})
summary={'sample_size':len(rows),'passed':len(records),'rejected':rejects,'total_seconds':time.monotonic()-t,'median_gen_ms':statistics.median(x['gen_ms'] for x in records),'mean_gen_ms':statistics.mean(x['gen_ms'] for x in records),'mean_validate_ms':statistics.mean(x['validate_ms'] for x in records),'mean_json_bytes':statistics.mean(x['bytes'] for x in records),'max_total_cells':max(x['counts']['total_cell_count'] for x in records),'scope':'offline sample benchmark; no farm files deployed','records':records}
(R/'evidence/benchmark-500.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps({k:v for k,v in summary.items() if k!='records'}),flush=True)
