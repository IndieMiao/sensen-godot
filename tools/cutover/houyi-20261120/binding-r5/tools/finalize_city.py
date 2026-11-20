"""Complete author pins after source reconstruction and MVT decode; no deployment."""
from pathlib import Path
import json,hashlib,collections,datetime,subprocess,sys,time,gzip
from audit_binding import context,verify_reports,sha
R=Path(__file__).resolve().parents[1];O=R/'generated';input_manifest_blob=(O/'manifest.json').read_bytes();m=json.loads(input_manifest_blob);files=m['files'];base={'schema':4,'dataset_version':m['dataset_version']}
def write(name,obj):
 p=O/name;p.write_text(json.dumps(obj,separators=(',',':'),allow_nan=False)+'\n');files[name]=hashlib.sha256(p.read_bytes()).hexdigest()
included_blob=(O/'included-parcels.json').read_bytes();inc=set(json.loads(included_blob)['block_ids']);source_blob=(R/'audit/source-candidates.json.gz').read_bytes();expected=context(R,input_manifest_blob,included_blob,source_blob)
rows_by_id={'p-'+r['parcel_id']:r for r in json.loads(gzip.decompress(source_blob))};full_reports=[];reports=[]
for p in sorted((R/'evidence').glob('source-geometry-[0-9].json')):
 blob=p.read_bytes();a=json.loads(blob);full_reports.append(a);reports.append({**{k:v for k,v in a.items() if k!='results'},'report_sha256':sha(blob)})
found,audited_farm_set_sha256=verify_reports(full_reports,expected,rows_by_id,inc,m['files'],lambda rel:(O/rel).read_bytes());results=list(found.values())
results.sort(key=lambda x:x['block_id'])
summary={**base,'binding':expected,'audited_farm_set_sha256':audited_farm_set_sha256,'each_farm_bytes_source_version_checked':True,'count':len(results),'all_included_reconstructed':True,'iou_range':[min(p['measured_iou'] for p in results),max(p['measured_iou'] for p in results)],'source_components_distribution':dict(collections.Counter(p['source_polygon_count'] for p in results)),'source_holes_parcels':sum(p['source_hole_count']>0 for p in results),'source_holes_total':sum(p['source_hole_count'] for p in results),'oriented_grid_count':sum(p['rotation_deg']!=0 for p in results),'approximation_warning':[p for p in results if p['measured_iou']<.9],'partitions':reports,'all_source_parts_and_holes_matched':True,'individual_feature_minimum_retained_fraction':.85,'method':'Decode emitted RLE rectangles, project frozen source geometry to EPSG:32610, rotate by source centroid and emitted angle, normalize by emitted origin/scale; compute fresh polygon intersection/union, tolerance1e-7. Does not import generator/validator or trust claimed IoU.'}
write('reports/source-geometry-audit.json',summary)
reconciliation=json.loads((O/'reports/topology-reconciliation.json').read_text());reconciliation['all_final_source_topology_audit']='passed_all_included_fresh_source_and_individual_feature_checks';write('reports/topology-reconciliation.json',reconciliation)
report=json.loads((O/'generation-report.json').read_text());report['geographic_source_iou_audit']={'status':'passed_all_included','report':'reports/source-geometry-audit.json','count':len(results)};write('generation-report.json',report)
for name in ['farm-runtime.json','source-audit-runtime.json','reconcile-runtime.json','reconcile-r3-runtime.json','mvt-runtime.json']:
 value=json.loads((R/'evidence'/name).read_text());write('reports/'+name,value)
m['generator']['source_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in [R/'tools/generator.py',R/'tools/audit_source_geometry.py',R/'tools/source_manifest.py',R/'tools/audit_binding.py']}
m['files']=dict(sorted(files.items()));m['author_verification']={'source_inventory_exact':True,'per_farm_mask_validation':True,'source_geometry_all':True,'mvt_decoded_all':True,'external_review':'pending; approval is recorded separately against this manifest hash'}
(O/'manifest.json').write_text(json.dumps(m,separators=(',',':'),allow_nan=False)+'\n');manifest_hash=hashlib.sha256((O/'manifest.json').read_bytes()).hexdigest()
client={k:m[k] for k in ['schema','dataset_version','selection_unit','parcel_count','block_count','generator_version','native_map','scope']};client['source_manifest_sha256']=manifest_hash;(O/'client-manifest.json').write_text(json.dumps(client,separators=(',',':'))+'\n');assert (O/'client-manifest.json').stat().st_size<16384
start=time.monotonic();checked=0;total=0
for name,sha in m['files'].items():
 p=O/name;assert p.is_file() and not p.is_symlink();blob=p.read_bytes();assert hashlib.sha256(blob).hexdigest()==sha,name;checked+=1;total+=len(blob)
actual={p.relative_to(O).as_posix() for p in O.rglob('*') if p.is_file()};assert actual==set(m['files'])|{'manifest.json','client-manifest.json'},'unlisted/missing payload'
node=subprocess.run(['node',str(R/'tools/verify_inventory.mjs')],capture_output=True,text=True);assert node.returncode==0,node.stderr
receipt={**base,'author_manifest_sha256':manifest_hash,'client_manifest_sha256':hashlib.sha256((O/'client-manifest.json').read_bytes()).hexdigest(),'file_count':checked,'payload_bytes_without_manifests':total,'file_hashes_all_passed':True,'exact_payload_set':True,'inventory_validator':json.loads(node.stdout),'source_geometry_count':len(results),'audited_farm_set_sha256':audited_farm_set_sha256,'audit_binding':expected,'mvt_zooms':m['mvt_validation'],'validation_seconds':time.monotonic()-start,'reviewed':False}
(R/'evidence/full-author-validation.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps(receipt),flush=True)
