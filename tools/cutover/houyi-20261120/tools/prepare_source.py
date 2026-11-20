"""Freeze source IDs before repair/dedup, with row and parcel-level accounting."""
import pathlib,json,hashlib,re,collections,gzip,time
import shapely
from shapely.geometry import shape,mapping
from pyproj import Transformer
from generator import clean_address
from source_manifest import verify_source_pages
R=pathlib.Path(__file__).resolve().parents[1];SOURCE=R.parent/'parcel-r2/data';AUDIT=R/'audit';AUDIT.mkdir(exist_ok=True);DATASET='sf-dynamic-farm-20261118-r4';base={'schema':4,'dataset_version':DATASET};PROJECT=Transformer.from_crs(4326,32610,always_xy=True)
def digest(x):return hashlib.sha256(json.dumps(x,sort_keys=True,separators=(',',':')).encode()).hexdigest()
def write(name,obj):(AUDIT/name).write_text(json.dumps(obj,separators=(',',':'))+'\n')
def record_hash(file,index,row):return {'record_key':hashlib.sha256((file+':'+str(index)+':'+digest(row)).encode()).hexdigest(),'source_dataset':'acdm-wktn','source_file':file,'record_index':index,'record_sha256':digest(row),'parcel_id':row.get('mapblklot') if isinstance(row.get('mapblklot'),str) else None}
source_manifest_verification=verify_source_pages(SOURCE,'5b364560e3dd720c4257cbfa6d62f5d25c7ae6ae17a9e4182a02d584368f8e4d')
verified_pages={p['file']:p for p in source_manifest_verification['pages']}
start=time.monotonic();ids=set();byid={};rejected=[];records=0;accepted=0;source_files=[]
for page in sorted(SOURCE.glob('parcels-*.json')):
 blob=page.read_bytes();rows=json.loads(blob);verified=verified_pages[page.name]
 assert hashlib.sha256(blob).hexdigest()==verified['sha256'] and len(blob)==verified['bytes'] and len(rows)==verified['count'],'source changed after verification'
 source_files.append({'file':page.name,'sha256':hashlib.sha256(blob).hexdigest(),'count':len(rows)})
 for i,row in enumerate(rows):
  records+=1;pid=row.get('mapblklot');reason=None
  if not pid:reason='missing_parcel_id'
  elif not isinstance(pid,str) or re.fullmatch(r'[A-Za-z0-9_*-]{1,78}',pid) is None:reason='invalid_parcel_id'
  if reason:rejected.append({**record_hash(page.name,i,row),'reason_code':reason});continue
  ids.add(pid);e=byid.setdefault(pid,{'variants':{},'addresses':set(),'zoning':set()})
  if not row.get('shape'):rejected.append({**record_hash(page.name,i,row),'reason_code':'missing_geometry'});continue
  try:
   g=shape(row['shape']);norm=shapely.normalize(g)
   if g.is_empty or g.geom_type not in ['Polygon','MultiPolygon']:raise ValueError('non polygon')
  except Exception:rejected.append({**record_hash(page.name,i,row),'reason_code':'invalid_geometry'});continue
  accepted+=1;key=hashlib.sha256(norm.wkb).hexdigest();e['variants'][key]=row['shape']
  a=str(row.get('from_address_num') or '').strip();b=str(row.get('to_address_num') or '').strip();street=' '.join(x for x in [row.get('street_name'),row.get('street_type')] if isinstance(x,str) and x)
  if a and a.upper() not in ['UNKNOWN','NONE','NULL'] and street and street.upper()!='UNKNOWN':e['addresses'].add(a+('-'+b if b and b!=a and b.upper()!='UNKNOWN' else '')+' '+street)
  if row.get('zoning_code'):e['zoning'].add(row['zoning_code'])
write('input-parcels.json',{**base,'parcel_ids':sorted(ids),'count':len(ids)})
write('raw-record-rejections.json',{**base,'records':rejected,'count':len(rejected)})
physical={};excluded=[];recovered_variants=[]
for pid,e in sorted(byid.items()):
 variants=e['variants'];flags=[]
 if not variants:
  excluded.append({'block_id':'p-'+pid,'parcel_id':pid,'aliases':[],'stage':'source','reason_code':'missing_geometry','source_geometry_hash':None,'attempted_repairs':[],'metrics':{}});continue
 if len(variants)>1:
  projected=[shapely.transform(shape(x),PROJECT.transform,interleaved=False) for x in variants.values()]
  equal=all(x.is_valid for x in projected)
  if equal:
   ref=projected[0]
   for other in projected[1:]:
    if ref.hausdorff_distance(other)>.05 or ref.symmetric_difference(other).area/max(ref.union(other).area,1e-12)>.001:equal=False;break
  if not equal:
   excluded.append({'block_id':'p-'+pid,'parcel_id':pid,'aliases':[],'stage':'geometry','reason_code':'ambiguous_geometry','source_geometry_hash':digest(variants),'attempted_repairs':['near_equal_variants_check'],'metrics':{'variant_count':len(variants)}});continue
  flags=['near_equal_variants'];recovered_variants.append(pid)
 key=sorted(variants)[0];geom=variants[key];item=physical.setdefault(key,{'parcel_ids':[],'geometry':geom,'addresses':set(),'zoning':set(),'recovery_flags':set()})
 item['parcel_ids'].append(pid);item['addresses'].update(e['addresses']);item['zoning'].update(e['zoning']);item['recovery_flags'].update(flags)
candidates=[];aliases=[]
for e in physical.values():
 canonical=min(e['parcel_ids']);e.update(parcel_id=canonical,parcel_ids=sorted(e['parcel_ids']),addresses=sorted(x for x in e['addresses'] if clean_address(x)),zoning=sorted(e['zoning']),recovery_flags=sorted(e['recovery_flags']),source_geometry_hash=digest(e['geometry']))
 candidates.append(e)
 for alias in e['parcel_ids']:
  if alias!=canonical:aliases.append({'alias_parcel_id':alias,'canonical_parcel_id':canonical,'canonical_block_id':'p-'+canonical})
candidates.sort(key=lambda x:x['parcel_id']);aliases.sort(key=lambda x:x['alias_parcel_id'])
with gzip.open(AUDIT/'source-candidates.json.gz','wt') as f:json.dump(candidates,f,separators=(',',':'))
write('alias-map.json',{**base,'aliases':aliases,'count':len(aliases)})
write('source-exclusions.json',{**base,'parcels':excluded,'count':len(excluded)})
assert records==accepted+len(rejected)
assert ids=={x['parcel_id'] for x in candidates}|{x['parcel_id'] for x in excluded}|{x['alias_parcel_id'] for x in aliases}
counts={'source_records':records,'source_accepted_records':accepted,'source_rejected_records':len(rejected),'source_distinct_parcels':len(ids),'source_canonical_candidates':len(candidates),'source_excluded_canonicals':len(excluded),'alias_parcels':len(aliases)}
write('source-audit.json',{**base,'counts':counts,'source_files':source_files,'source_download_manifest_sha256':hashlib.sha256((SOURCE/'parcel-download-manifest.json').read_bytes()).hexdigest(),'download_inventory_verified':source_manifest_verification,'near_equal_recovered_ids':recovered_variants,'seconds':time.monotonic()-start})
print(json.dumps(counts),'near_equal_recovered',len(recovered_variants),flush=True)
