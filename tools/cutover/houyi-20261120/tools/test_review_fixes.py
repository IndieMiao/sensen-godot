from pathlib import Path
import json,tempfile,hashlib,copy,importlib.util
from shapely.geometry import box,Polygon,MultiPolygon
from shapely.affinity import affine_transform
from generator import core_from_geometry,cell_geometry,Rejected
from audit_source_geometry import verify_topology
from source_manifest import verify_source_pages
R=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('frozen_old_generator',R/'author-review-r1/source-snapshot/tools/generator.py');old=importlib.util.module_from_spec(spec);spec.loader.exec_module(old)
cases={'narrow_part':MultiPolygon([box(0,0,20,40),box(22,0,22.4,100)]),'narrow_hole':Polygon(box(0,0,20,40).exterior.coords,[box(9.8,5,10.2,35).exterior.coords])};results=[]
for name,g in cases.items():
 before=old.core_from_geometry(g);h=before['source_cell_m'];x,y=before['source_origin_m'];src=affine_transform(g,[1/h,0,0,1/h,-x/h,-y/h]);old_rejected=False
 try:verify_topology(src,cell_geometry(before['cells']))
 except AssertionError:old_rejected=True
 assert old_rejected
 try:
  new=core_from_geometry(g)
  from shapely.affinity import rotate
  h=new['source_cell_m'];x,y=new['source_origin_m'];src=affine_transform(rotate(g,new['rotation_deg'],origin=g.centroid),[1/h,0,0,1/h,-x/h,-y/h]);after={'result':'included','topology':verify_topology(src,cell_geometry(new['cells']))}
 except Rejected as e:after={'result':'excluded','reason':e.reason,'metrics':e.metrics}
 results.append({'case':name,'old_global_iou':before['iou'],'old_fails_new_independent_topology_gate':old_rejected,'new':after})
page_tests=[]
with tempfile.TemporaryDirectory(prefix='houyi-source-manifest-test-') as tmp:
 root=Path(tmp);name='parcels-000000.json';blob=b'[{"synthetic":true}]\n';(root/name).write_bytes(blob);good=[{'file':name,'rows':1,'bytes':len(blob),'sha256':hashlib.sha256(blob).hexdigest()}]
 for label,mutate in [('good',lambda x:None),('missing_page',lambda x:x.append({**x[0],'file':'parcels-050000.json'})),('wrong_hash',lambda x:x[0].__setitem__('sha256','0'*64)),('wrong_bytes',lambda x:x[0].__setitem__('bytes',0)),('wrong_rows',lambda x:x[0].__setitem__('rows',0)),('duplicate_page',lambda x:x.append(x[0])),('empty',lambda x:x.clear())]:
  data=copy.deepcopy(good);mutate(data);(root/'parcel-download-manifest.json').write_text(json.dumps(data));status='passed'
  try:verify_source_pages(root)
  except ValueError:status='rejected'
  assert status==('passed' if label=='good' else 'rejected'),label;page_tests.append({'case':label,'result':status})
 (root/'parcel-download-manifest.json').write_text(json.dumps(good));(root/'parcels-999999.json').write_text('[]')
 try:verify_source_pages(root)
 except ValueError:page_tests.append({'case':'extra_page','result':'rejected'})
 else:raise AssertionError('extra page accepted')
print(json.dumps({'topology':results,'manifest_gate':page_tests},indent=2))
