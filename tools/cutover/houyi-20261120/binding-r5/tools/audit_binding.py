"""Strict linkage between fresh semantic audit inputs and bytes accepted for packaging."""
from pathlib import Path
import json,hashlib,platform,importlib.metadata
VERSION='farm-bytes-source-auditor-v1'
def sha(blob):return hashlib.sha256(blob).hexdigest()
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False).encode()
def context(root,manifest_blob,included_blob,source_blob):
 root=Path(root);m=json.loads(manifest_blob)
 assert sha(manifest_blob)==json.loads((root/'binding-input.json').read_text())['author_manifest_sha256'],'input manifest pin mismatch'
 assert sha(included_blob)==m['files']['included-parcels.json'],'input included pin mismatch'
 prior_blob=(root/'generated/reports/source-geometry-audit.json').read_bytes();assert sha(prior_blob)==m['files']['reports/source-geometry-audit.json'],'source provenance report pin mismatch'
 prior=json.loads(prior_blob);assert all(p['source_candidates_sha256']==sha(source_blob) for p in prior['partitions']),'source differs from frozen snapshot'
 assert sha((root/'tools/generator.py').read_bytes())==m['generator']['source_sha256']['generator.py'],'declared generator differs from frozen dataset'
 return {'audit_contract':VERSION,'dataset_version':m['dataset_version'],'farm_schema':4,'generator_version':m['generator_version'],'input_manifest_sha256':sha(manifest_blob),'included_sha256':sha(included_blob),'source_candidates_sha256':sha(source_blob),'audit_code_sha256':{name:sha((root/'tools'/name).read_bytes()) for name in ['audit_source_geometry.py','audit_binding.py']},'declared_generator_code_sha256':sha((root/'tools/generator.py').read_bytes()),'runtime':{'python':platform.python_version(),**{n:importlib.metadata.version(n) for n in ['shapely','pyproj','numpy']}}}
def bound_row(blob,row,farm,expected):
 assert farm['schema']==expected['farm_schema'] and farm['dataset_version']==expected['dataset_version'] and farm['generator_version']==expected['generator_version'],'farm version binding'
 assert farm['block_id']=='p-'+row['parcel_id'] and farm['parcel_id']==row['parcel_id'],'farm source identity binding'
 return {'farm_path':'farms/'+farm['block_id']+'.json','farm_sha256':sha(blob),'source_row_sha256':sha(canonical(row)),'dataset_version':farm['dataset_version'],'farm_schema':farm['schema'],'generator_version':farm['generator_version']}
def verify_reports(reports,expected,rows_by_id,expected_ids,manifest_files,read_farm):
 found={};shards=set();partition_count=None
 for report in reports:
  assert report.get('scope')=='all_included_partition' and report.get('binding')==expected,'audit context/version/source/code mismatch'
  shard=report['shard'];n=report['shards'];assert type(n)==int and n>0 and type(shard)==int and 0<=shard<n and shard not in shards,'audit shard mismatch'
  if partition_count is None:partition_count=n
  assert n==partition_count;shards.add(shard)
  assert report['count']==len(report['results']),'audit count mismatch'
  for result in report['results']:
   bid=result['block_id'];assert bid in expected_ids and bid not in found,'audit duplicate/unknown ID'
   row=rows_by_id[bid];path='farms/'+bid+'.json';blob=read_farm(path);f=json.loads(blob);link=bound_row(blob,row,f,expected)
   assert all(result.get(k)==v for k,v in link.items()),('audited farm/source bytes changed',bid)
   assert result['farm_sha256']==manifest_files[path],('audited farm differs from packaged manifest',bid)
   assert result['source_geometry_hash']==row['source_geometry_hash']==sha(canonical(row['geometry'])),'source geometry binding'
   found[bid]=result
 assert shards==set(range(partition_count)) and set(found)==set(expected_ids),'audit partition/full set mismatch'
 digest=sha(''.join('farms/'+bid+'.json\0'+found[bid]['farm_sha256']+'\n' for bid in sorted(found)).encode())
 return found,digest
