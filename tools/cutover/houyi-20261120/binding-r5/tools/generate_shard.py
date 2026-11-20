import pathlib,json,gzip,sys,time,hashlib,os
import shapely
from shapely.geometry import shape,mapping
from pyproj import Transformer
from generator import core_from_geometry,build,Rejected,DATASET,VERSION,polygons
from validate_farm import validate
R=pathlib.Path(__file__).resolve().parents[1];SHARD=int(sys.argv[1]);SHARDS=int(sys.argv[2]);OUT=R/'generated';(OUT/'farms').mkdir(parents=True,exist_ok=True);(R/'staging').mkdir(exist_ok=True)
proj=Transformer.from_crs(4326,32610,always_xy=True)
with gzip.open(R/'audit/source-candidates.json.gz','rt') as f:rows=json.load(f)[SHARD::SHARDS]
files={};catalog=[];exclusions=[];quality=[];t=time.monotonic();geo=open(R/'staging'/f'parcels-{SHARD}.ndjson','w')
for i,row in enumerate(rows):
 pid=row['parcel_id'];bid='p-'+pid;flags=row.get('recovery_flags',[])
 try:
  g=shapely.transform(shape(row['geometry']),proj.transform,interleaved=False);core=core_from_geometry(g);core['flags']+=flags
  # Legacy material provenance is only a display/theme hint, never the r4 capability or collision mask.
  old=R.parent/'parcel-r3/generated/farms'/f'{bid}.json';hints={'water_fraction':None,'water_fraction_basis':'not_available','landuse':'unknown','source_building_count':None}
  if old.exists():
   legacy=json.loads(old.read_text());cells=legacy['grid']['cells'];hints={'water_fraction':sum(c[2]==5 for c in cells)/len(cells),'water_fraction_basis':'r3_snapshot_grid_estimate_not_live_survey','landuse':'unknown','source_building_count':legacy.get('building_count')}
  f=build(bid,core,{'parcel_id':pid,'parcel_aliases':row['parcel_ids'],'address':row['addresses'][0] if row['addresses'] else None,'geo_hints':hints});f['source_geometry_hash']=row['source_geometry_hash']
  validate(f) # A validator failure is a code/data contract bug: stop shard, never hide it as parcel rejection.
  blob=(json.dumps(f,separators=(',',':'))+'\n').encode();rel='farms/'+bid+'.json';p=OUT/rel;tmp=p.with_suffix('.json.tmp');tmp.write_bytes(blob);os.replace(tmp,p);files[rel]=hashlib.sha256(blob).hexdigest()
  # MVT remains original geography, never rotated game geometry or procedural extension.
  original=shape(row['geometry']);original=original if original.is_valid else shapely.make_valid(original);original=shapely.union_all(polygons(original)).simplify(.0000003,preserve_topology=True);pt=original.representative_point();bbox=list(original.bounds)
  props={'block_id':bid,'parcel_id':pid,'name':f['name'],'address':f['address'] or '', 'center_lon':pt.x,'center_lat':pt.y,'center':json.dumps([pt.x,pt.y],separators=(',',':')),'bbox':json.dumps(bbox,separators=(',',':')),'farm_path':rel,'source_area_m2':f['source_area_m2'],'area':f['source_area_m2'],'cell_count':f['counts']['core_cell_count'],**f['counts']}
  geo.write(json.dumps({'type':'Feature','id':bid,'geometry':mapping(original),'properties':props},separators=(',',':'))+'\n')
  catalog.append({**props,'center':[pt.x,pt.y],'bbox':bbox,'address':f['address'],'parcel_aliases':row['parcel_ids']})
  quality.append({'block_id':bid,'core_iou':f['stats']['core_iou'],'flags':f['stats']['recovery_flags'],'core_components':f['stats']['core_components'],'core':f['counts']['core_cell_count'],'extension':f['counts']['extension_cell_count'],'total':f['counts']['total_cell_count'],'width':f['grid']['width'],'height':f['grid']['height'],'bytes':len(blob)})
 except Rejected as ex:
  stage='geometry' if ex.reason in ['invalid_geometry','area_below_minimum'] else 'extension' if ex.reason in ['extension_budget_exceeded','walk_disconnected','no_safe_spawn'] else 'core'
  exclusions.append({'block_id':bid,'parcel_id':pid,'aliases':[x for x in row['parcel_ids'] if x!=pid],'stage':stage,'reason_code':ex.reason,'source_geometry_hash':row['source_geometry_hash'],'attempted_repairs':flags+ex.repairs,'metrics':ex.metrics})
 if i%1000==0:print('PROGRESS',i+1,'included',len(catalog),'excluded',len(exclusions),'seconds',round(time.monotonic()-t,1),flush=True)
geo.close()
for name,value in [('hashes',files),('catalog',catalog),('excluded',exclusions),('quality',quality)]:
 (R/'staging'/f'{name}-{SHARD}.json').write_text(json.dumps(value,separators=(',',':'))+'\n')
(R/'evidence'/f'shard-{SHARD}-result.json').write_text(json.dumps({'shard':SHARD,'input':len(rows),'included':len(catalog),'excluded':len(exclusions),'seconds':time.monotonic()-t,'all_written_farms_independently_validated':True},indent=2)+'\n')
print('DONE',SHARD,len(catalog),len(exclusions),round(time.monotonic()-t,1),flush=True)
