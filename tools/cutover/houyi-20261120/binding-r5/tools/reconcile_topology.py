"""Preserve first-pass diagnostics; rebuild source-complex parcels, copy unaffected masks.
All final included cores MUST subsequently pass fresh source/feature topology audit.
"""
from pathlib import Path
import json,gzip,hashlib,shutil,time,os
import shapely
from shapely.geometry import shape,mapping
from pyproj import Transformer
from generator import core_from_geometry,build,Rejected,polygons
from validate_farm import validate
from source_manifest import verify_source_pages
R=Path(__file__).resolve().parents[1];start=time.monotonic();proj=Transformer.from_crs(4326,32610,always_xy=True)
verification=verify_source_pages(R.parent/'parcel-r2/data','5b364560e3dd720c4257cbfa6d62f5d25c7ae6ae17a9e4182a02d584368f8e4d')
old_results=[json.loads((R/'evidence'/f'shard-{i}-result.json').read_text()) for i in range(2)]
assert all(x['all_written_farms_independently_validated'] for x in old_results)
runtime=json.loads((R/'evidence/farm-runtime.json').read_text());assert not runtime['pending_restart'] and all(x.get('exit_code')==0 or x.get('resource_downgrade') for x in runtime['processes'])
D=R/('diagnostic-topology-r2' if (R/'diagnostic-firstpass').exists() else 'diagnostic-firstpass');assert not D.exists(),'never overwrite diagnostics';D.mkdir();(R/'generated').rename(D/'generated');(R/'staging').rename(D/'staging');(D/'evidence').mkdir()
for name in ['farm-runtime.json','shard-0-result.json','shard-1-result.json','farm-shard-0.log','farm-shard-1.log']:shutil.copyfile(R/'evidence'/name,D/'evidence'/name)
previous_reconciliation=json.loads((R/'evidence/topology-reconciliation.json').read_text()) if (R/'evidence/topology-reconciliation.json').exists() else None
if previous_reconciliation:(D/'previous-reconciliation.json').write_text(json.dumps(previous_reconciliation,indent=2)+'\n')
O=R/'generated';(O/'farms').mkdir(parents=True);(R/'staging').mkdir();oldfiles={};oldcat={};oldexcluded={};oldquality={}
for i in range(2):
 oldfiles.update(json.loads((D/'staging'/f'hashes-{i}.json').read_text()))
 for kind,dest in [('catalog',oldcat),('excluded',oldexcluded),('quality',oldquality)]:
  for x in json.loads((D/'staging'/f'{kind}-{i}.json').read_text()):dest[x['block_id']]=x
with gzip.open(R/'audit/source-candidates.json.gz','rt') as stream:rows=json.load(stream)
assert len(rows)==sum(x['input'] for x in old_results)
shards=[{'hashes':{},'catalog':[],'excluded':[],'quality':[],'input':0} for _ in range(2)];geos=[open(R/'staging'/f'parcels-{i}.ndjson','w') for i in range(2)];recomputed=[];copied=0;old_rejections_reused=0
for index,row in enumerate(rows):
 n=index%2;s=shards[n];s['input']+=1;pid=row['parcel_id'];bid='p-'+pid;g0=shape(row['geometry']);valid=g0.is_valid;g=g0 if valid else shapely.make_valid(g0);parts=polygons(g);complex_source=(not valid) or len(parts)!=1 or any(p.interiors for p in parts);f=None
 if not complex_source:
  if bid in oldexcluded:s['excluded'].append(oldexcluded[bid]);old_rejections_reused+=1;continue
  cat=oldcat[bid];rel=cat['farm_path'];oldpath=D/'generated'/rel;blob=oldpath.read_bytes();assert hashlib.sha256(blob).hexdigest()==oldfiles[rel]
  (O/rel).write_bytes(blob);s['hashes'][rel]=oldfiles[rel];s['catalog'].append(cat);s['quality'].append(oldquality[bid]);copied+=1
 else:
  result={'block_id':bid,'source_invalid_repaired':not valid,'source_parts':len(parts),'source_holes':sum(len(p.interiors) for p in parts),'old_result':'included' if bid in oldcat else 'excluded'}
  try:
   projected=shapely.transform(g0,proj.transform,interleaved=False);core=core_from_geometry(projected);core['flags']+=row.get('recovery_flags',[])
   old=R.parent/'parcel-r3/generated/farms'/f'{bid}.json';hints={'water_fraction':None,'water_fraction_basis':'not_available','landuse':'unknown','source_building_count':None}
   if old.exists():
    legacy=json.loads(old.read_text());cells=legacy['grid']['cells'];hints={'water_fraction':sum(c[2]==5 for c in cells)/len(cells),'water_fraction_basis':'r3_snapshot_grid_estimate_not_live_survey','landuse':'unknown','source_building_count':legacy.get('building_count')}
   f=build(bid,core,{'parcel_id':pid,'parcel_aliases':row['parcel_ids'],'address':row['addresses'][0] if row['addresses'] else None,'geo_hints':hints});f['source_geometry_hash']=row['source_geometry_hash'];validate(f)
   rel=f'farms/{bid}.json';blob=(json.dumps(f,separators=(',',':'))+'\n').encode();(O/rel).write_bytes(blob);s['hashes'][rel]=hashlib.sha256(blob).hexdigest()
   original=shapely.union_all(parts).simplify(.0000003,preserve_topology=True);pt=original.representative_point();bbox=list(original.bounds)
   props={'block_id':bid,'parcel_id':pid,'name':f['name'],'address':f['address'],'center_lon':pt.x,'center_lat':pt.y,'center':[pt.x,pt.y],'bbox':bbox,'farm_path':rel,'source_area_m2':f['source_area_m2'],'area':f['source_area_m2'],'cell_count':f['counts']['core_cell_count'],**f['counts'],'parcel_aliases':row['parcel_ids']}
   cat=props;s['catalog'].append(cat);s['quality'].append({'block_id':bid,'core_iou':f['stats']['core_iou'],'flags':f['stats']['recovery_flags'],'core_components':f['stats']['core_components'],'core':f['counts']['core_cell_count'],'extension':f['counts']['extension_cell_count'],'total':f['counts']['total_cell_count'],'width':f['grid']['width'],'height':f['grid']['height'],'bytes':len(blob)})
   result.update(new_result='included',old_sha256=oldfiles.get(rel),new_sha256=s['hashes'][rel],byte_identical_to_first_pass=oldfiles.get(rel)==s['hashes'][rel])
  except Rejected as ex:
   stage='geometry' if ex.reason in ['invalid_geometry','area_below_minimum'] else 'extension' if ex.reason in ['extension_budget_exceeded','walk_disconnected','no_safe_spawn'] else 'core'
   s['excluded'].append({'block_id':bid,'parcel_id':pid,'aliases':[x for x in row['parcel_ids'] if x!=pid],'stage':stage,'reason_code':ex.reason,'source_geometry_hash':row['source_geometry_hash'],'attempted_repairs':row.get('recovery_flags',[])+ex.repairs,'metrics':ex.metrics});result.update(new_result='excluded',reason=ex.reason,metrics=ex.metrics);recomputed.append(result);continue
  recomputed.append(result)
 # Recreate final map stream from source geometry and final catalog; no rejected remnants.
 original=shapely.union_all(parts).simplify(.0000003,preserve_topology=True);props={k:v for k,v in cat.items() if k!='parcel_aliases'};props.update(address=cat['address'] or '',center=json.dumps(cat['center'],separators=(',',':')),bbox=json.dumps(cat['bbox'],separators=(',',':')))
 geos[n].write(json.dumps({'type':'Feature','id':bid,'geometry':mapping(original),'properties':props},separators=(',',':'))+'\n')
 if index%10000==0:print('RECONCILE',index+1,'copied',copied,'recomputed',len(recomputed),flush=True)
for n,s in enumerate(shards):
 geos[n].close()
 for kind in ['hashes','catalog','excluded','quality']:(R/'staging'/f'{kind}-{n}.json').write_text(json.dumps(s[kind],separators=(',',':'))+'\n')
 (R/'evidence'/f'shard-{n}-result.json').write_text(json.dumps({'shard':n,'input':s['input'],'included':len(s['catalog']),'excluded':len(s['excluded']),'all_written_farms_independently_validated':True,'validation_provenance':'unaffected simple no-hole masks copied byte-exact from first-pass independent mask checks; all source-complex geometries regenerated by corrected candidate gate and mask-validated; every included requires NEW independent source topology audit before freezing','seconds_firstpass':old_results[n].get('seconds',old_results[n].get('seconds_firstpass'))},indent=2)+'\n')
audit=json.loads((R/'audit/source-audit.json').read_text());audit['download_inventory_verified']=verification;shutil.copyfile(R/'audit/source-audit.json',D/'source-audit-before-manifest-gate.json');(R/'audit/source-audit.json').write_text(json.dumps(audit,separators=(',',':'))+'\n')
report={'previous_reconciliation':previous_reconciliation,'firstpass_diagnostics':str(D),'source_candidates':len(rows),'unaffected_simple_no_hole_farms_copied_byte_exact':copied,'unaffected_simple_rejections_reused':old_rejections_reused,'complex_sources_regenerated':len(recomputed),'recomputed':recomputed,'newly_excluded_ids':[x['block_id'] for x in recomputed if x['old_result']=='included' and x['new_result']=='excluded'],'all_final_source_topology_audit':'pending; must complete before freeze','seconds':time.monotonic()-start,'generator_sha256':hashlib.sha256((R/'tools/generator.py').read_bytes()).hexdigest(),'independent_source_auditor_sha256':hashlib.sha256((R/'tools/audit_source_geometry.py').read_bytes()).hexdigest()}
(R/'evidence/topology-reconciliation.json').write_text(json.dumps(report,indent=2)+'\n');print('RECONCILE_DONE',json.dumps({k:v for k,v in report.items() if k!='recomputed'}),flush=True)
