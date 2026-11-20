"""Join completed shards and freeze exact source/output inventories before MVT."""
from pathlib import Path
import json,hashlib,datetime,collections,shutil,importlib.metadata
from generator import DATASET,VERSION,PARAMS
R=Path(__file__).resolve().parents[1];O=R/'generated';base={'schema':4,'dataset_version':DATASET}
files={};catalog=[];quality=[];excluded=json.loads((R/'audit/source-exclusions.json').read_text())['parcels'];shards=[]
for n in range(2):
 result=json.loads((R/'evidence'/f'shard-{n}-result.json').read_text());assert result['all_written_farms_independently_validated'];shards.append(result)
 h=json.loads((R/'staging'/f'hashes-{n}.json').read_text());assert not files.keys()&h.keys();files.update(h)
 catalog+=json.loads((R/'staging'/f'catalog-{n}.json').read_text());quality+=json.loads((R/'staging'/f'quality-{n}.json').read_text());excluded+=json.loads((R/'staging'/f'excluded-{n}.json').read_text())
catalog.sort(key=lambda x:x['block_id']);quality.sort(key=lambda x:x['block_id']);excluded.sort(key=lambda x:x['block_id'])
inc={p['parcel_id'] for p in catalog};exc={p['parcel_id'] for p in excluded};alias_doc=json.loads((R/'audit/alias-map.json').read_text());aliases={p['alias_parcel_id'] for p in alias_doc['aliases']};input_doc=json.loads((R/'audit/input-parcels.json').read_text());source=json.loads((R/'audit/source-audit.json').read_text());raw=json.loads((R/'audit/raw-record-rejections.json').read_text())
assert not inc&exc and not inc&aliases and not exc&aliases
assert set(input_doc['parcel_ids'])==inc|exc|aliases
assert len(catalog)==len(inc)==len(files)==len(quality)
assert len(excluded)==len(exc)
assert {p.name for p in (O/'farms').iterdir()}=={p['block_id']+'.json' for p in catalog},'unexpected/missing farm file'
assert len(catalog)+len(excluded)==sum(x['input'] for x in shards)+source['counts']['source_excluded_canonicals']
for a in alias_doc['aliases']:assert a['canonical_parcel_id'] in inc|exc
bounds=[min(p['bbox'][0] for p in catalog),min(p['bbox'][1] for p in catalog),max(p['bbox'][2] for p in catalog),max(p['bbox'][3] for p in catalog)]
center=[-122.4519027184,37.729419227]
def write(name,obj):
 p=O/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,separators=(',',':'),allow_nan=False)+'\n');files[name]=hashlib.sha256(p.read_bytes()).hexdigest()
def copy(name,src):
 p=O/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,p);files[name]=hashlib.sha256(p.read_bytes()).hexdigest()
write('included-parcels.json',{**base,'block_ids':sorted('p-'+x for x in inc),'count':len(inc)})
write('excluded-parcels.json',{**base,'count':len(exc),'parcels':excluded})
for name in ['alias-map.json','input-parcels.json','raw-record-rejections.json']:copy(name,R/'audit'/name)
copy('reports/source-audit.json',R/'audit/source-audit.json')
write('parcel-catalog.json',{**base,'selection_unit':'parcel','parcel_count':len(inc),'parcels':catalog})
copy('reports/source-download-manifest.json',R.parent/'parcel-r2/data/parcel-download-manifest.json')
copy('reports/topology-reconciliation.json',R/'evidence/topology-reconciliation.json')
copy('reports/source-manifest-verification.json',R/'evidence/source-manifest-verification.json')
old=json.loads((R.parent/'parcel-r3/generated/parcel-catalog.json').read_text());oldids={p['parcel_id'] for p in old['parcels']};baseline=json.loads((R/'audit/r3-exclusions-baseline.json').read_text());excluded_by_id={p['parcel_id']:p for p in excluded};quality_by_id={p['block_id']:p for p in quality}
reassessment=[]
for row in baseline['rows']:
 pid=row['parcel_id'];reassessment.append({'parcel_id':pid,'r3_reason':row['r3_reason'],'r4_result':'included' if pid in inc else 'excluded' if pid in exc else 'alias','r4_evidence':quality_by_id.get('p-'+pid,excluded_by_id.get(pid))})
write('reports/r3-exclusion-reassessment.json',{**base,'baseline_excluded':len(reassessment),'recovered':sum(x['r4_result']=='included' for x in reassessment),'rows':reassessment,'new_excluded_from_r3':sorted(oldids-inc),'new_included_vs_r3':sorted(inc-oldids)})
write('reports/quality-details.json',{**base,'count':len(quality),'parcels':quality})
counts={k:source['counts'][k] for k in ['source_records','source_accepted_records','source_rejected_records','source_distinct_parcels','alias_parcels']};counts.update(canonical_parcels=len(inc)+len(exc),included_parcels=len(inc),excluded_parcels=len(exc))
assert counts['source_records']==counts['source_accepted_records']+raw['count']
assert counts['source_distinct_parcels']==counts['canonical_parcels']+counts['alias_parcels']
city_counts={name:sum(x[key] for x in quality) for name,key in [('core_cell_count','core'),('extension_cell_count','extension'),('total_cell_count','total')]}
report={**base,'counts':counts,'city_counts':city_counts,'source_input_exact_partition':True,'all_farms_independently_validated_during_generation':True,'geographic_source_iou_audit':'pending separate independent reconstruction','shards':shards,'cell_ranges':{key:[min(p[key] for p in quality),max(p[key] for p in quality)] for key in ['core','extension','total','width','height','core_iou']},'farm_bytes':sum(x['bytes'] for x in quality),'exclusion_reasons':dict(collections.Counter(p['reason_code'] for p in excluded)),'recovery_flags':dict(collections.Counter(flag for p in quality for flag in p['flags'])),'approximation_warning_ids':[p['block_id'] for p in quality if p['core_iou']<.9],'multicomponent_core_ids':[p['block_id'] for p in quality if p['core_components']>1],'new_included_vs_r3':len(inc-oldids),'new_excluded_from_r3':len(oldids-inc),'bounds':bounds,'source_snapshot_note':'Reuses frozen public DataSF pagination from 2026-11-17; no fresh upstream query and no runtime location collection. Row hashes/URLs/counts preserved.','geographic_limits':'extension is scene-local and not extra real parcel ownership; source hints are historical or unknown; no gameplay API enabled'}
write('generation-report.json',report)
fields={x:'String' for x in ['block_id','parcel_id','name','address','center','bbox','farm_path']};fields.update({x:'Number' for x in ['center_lon','center_lat','cell_count','source_area_m2','area','core_cell_count','extension_cell_count','total_cell_count']})
write('tilejson.template.json',{'tilejson':'2.2.0','name':'Dynamic Farm SF parcels r4','scheme':'xyz','tiles':['{PUBLIC_BASE}/tiles/{z}/{x}/{y}.pbf'],'minzoom':15,'maxzoom':18,'bounds':bounds,'center':center+[17.5],'attribution':'DataSF / SF Planning (PDDL / CC0)','vector_layers':[{'id':'parcels','minzoom':15,'maxzoom':18,'fields':fields}]})
m={**base,'selection_unit':'parcel','map_format':'mvt','generator_version':VERSION,'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'parcel_count':len(inc),'block_count':len(inc),'counts':counts,'city_counts':city_counts,'files':files,'native_map':{'type':'vector','parcel_url_path':'tilejson.json','parcel_source_layer':'parcels','promote_id':'block_id','source_minzoom':15,'source_maxzoom':18,'minzoom':16,'address_minzoom':18,'bounds':bounds,'center':center,'initial_zoom':17.5,'building_source':'mapbox'},'scope':{'mode':'full_city','bounds':bounds},'generator':{'version':VERSION,'parameters':PARAMS,'libraries':{p:importlib.metadata.version(p) for p in ['shapely','pyproj','numpy']}},'sources':{'parcels':{'dataset':'acdm-wktn','license':'PDDL','snapshot_manifest_sha256':source['source_download_manifest_sha256'],'source_files':source['source_files']},'geo_hints':{'basis':'r3 frozen estimates or null; not capability or water survey','r3_author_manifest_sha256':hashlib.sha256((R.parent/'parcel-r3/generated/manifest.json').read_bytes()).hexdigest()},'map_buildings':'Mapbox transient native selection only; not in farm/claim data'}}
(R/'staging/manifest-before-tiles.json').write_text(json.dumps(m,separators=(',',':'),allow_nan=False)+'\n')
print(json.dumps({**counts,'farm_bytes':report['farm_bytes'],'warnings':len(report['approximation_warning_ids']),'exclusion_reasons':report['exclusion_reasons']}),flush=True)
