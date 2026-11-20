from pathlib import Path
import json,hashlib,shutil
from shapely.geometry import shape
D=Path(__file__).resolve().parents[1];R=D.parent;O=D/'sample-bundle';(O/'farms').mkdir(parents=True,exist_ok=True)
version='sf-dynamic-farm-20261118-r4';base={'schema':4,'dataset_version':version};report=json.loads((D/'evidence/sample-generation.json').read_text());real=[x for x in report['results'] if 'parcel_id' in x];input_ids={x['parcel_id'] for x in real};farms={}
for item in real:
 if 'file' in item:
  f=json.loads((D/'samples'/item['file']).read_text());farms[item['parcel_id']]=f;input_ids.update(f['parcel_aliases'])
raw=[]
for p in sorted((R/'parcel-r2/data').glob('parcels-*.json')):
 for i,row in enumerate(json.loads(p.read_text())):
  if row.get('mapblklot') in input_ids:raw.append({'file':p.name,'index':i,'record':row})
byid={}
for row in raw:byid.setdefault(row['record']['mapblklot'],[]).append(row['record'])
files={};included=[];excluded=[];aliases=[];catalog=[]
def write(name,obj):
 p=O/name;p.write_text(json.dumps(obj,separators=(',',':'))+'\n');files[name]=hashlib.sha256(p.read_bytes()).hexdigest()
for item in real:
 pid=item['parcel_id'];block='p-'+pid;source=[x['shape'] for x in byid[pid] if x.get('shape')]
 if 'rejected' in item:
  excluded.append({'block_id':block,'parcel_id':pid,'aliases':[],'stage':'core','reason_code':item['rejected'],'source_geometry_hash':hashlib.sha256(json.dumps(source,sort_keys=True,separators=(',',':')).encode()).hexdigest(),'attempted_repairs':['cell_size_search','phase_search','oriented_grid'],'metrics':item.get('metrics',{})});continue
 f=farms[pid];write('farms/'+block+'.json',f);included.append(block)
 for aid in f['parcel_aliases']:
  if aid!=pid:aliases.append({'alias_parcel_id':aid,'canonical_parcel_id':pid,'canonical_block_id':block})
 g=shape(source[0]);pt=g.representative_point();catalog.append({'block_id':block,'parcel_id':pid,'parcel_aliases':f['parcel_aliases'],'name':f['name'],'address':f['address'],'center':[pt.x,pt.y],'bbox':list(g.bounds),'farm_path':'farms/'+block+'.json',**f['counts']})
write('included-parcels.json',{**base,'block_ids':sorted(included),'count':len(included)})
write('excluded-parcels.json',{**base,'count':len(excluded),'parcels':sorted(excluded,key=lambda x:x['block_id'])})
write('alias-map.json',{**base,'count':len(aliases),'aliases':sorted(aliases,key=lambda x:x['alias_parcel_id'])})
write('input-parcels.json',{**base,'parcel_ids':sorted(input_ids),'count':len(input_ids)})
write('raw-record-rejections.json',{**base,'count':0,'records':[]})
write('parcel-catalog.json',{**base,'selection_unit':'parcel','parcel_count':len(included),'parcels':sorted(catalog,key=lambda x:x['block_id'])})
write('generation-report.json',{**base,'scope':'AUTHOR_SAMPLE_ONLY, NOT CITY RELEASE','included':len(included),'excluded':len(excluded),'synthetic_tests_not_in_catalog':2,'source_subset_records':len(raw)})
assert len(input_ids)==len(included)+len(excluded)+len(aliases)
m={**base,'scope':{'mode':'author_sample_only','not_deployment_ready':True},'selection_unit':'parcel','generator_version':'dynamic-core-ext-1','parcel_count':len(included),'block_count':len(included),'counts':{'source_records':len(raw),'source_accepted_records':len(raw),'source_rejected_records':0,'source_distinct_parcels':len(input_ids),'canonical_parcels':len(included)+len(excluded),'alias_parcels':len(aliases),'included_parcels':len(included),'excluded_parcels':len(excluded)},'files':files,'sources':[{'dataset':'acdm-wktn','subset_parcel_ids':sorted(input_ids),'upstream_manifest_sha256':hashlib.sha256((R/'parcel-r2/data/parcel-download-manifest.json').read_bytes()).hexdigest()}]}
(O/'manifest.json').write_text(json.dumps(m,separators=(',',':'))+'\n');print('SAMPLE_BUNDLE',m['counts'],'manifest',hashlib.sha256((O/'manifest.json').read_bytes()).hexdigest())
