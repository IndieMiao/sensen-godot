"""Bounded real-source check plus corruption negatives for independent geometry audit."""
from pathlib import Path
import json,gzip,copy
from pyproj import Transformer
import audit_source_geometry as a
R=Path(__file__).resolve().parents[1];a.PROJECT=Transformer.from_crs(4326,32610,always_xy=True)
with gzip.open(R/'audit/source-candidates.json.gz','rt') as f:rows={r['parcel_id']:r for r in json.load(f)}
passed=[];pairs=[]
for p in sorted((R/'sample-bundle/farms').glob('*.json')):
 f=json.loads(p.read_text());row=rows[f['parcel_id']];f['source_geometry_hash']=row['source_geometry_hash'];passed.append(a.audit(row,f));pairs.append((row,f))
row,f=next((r,f) for r,f in pairs if f['parcel_id']=='5402049');negatives=[]
for name,mutate in [('fake_iou',lambda x:x['stats'].__setitem__('core_iou',.91)),('wrong_rotation',lambda x:x['source_transform'].__setitem__('rotation_deg',0)),('wrong_origin',lambda x:x['source_transform']['origin_m'].__setitem__(0,x['source_transform']['origin_m'][0]+10)),('wrong_source_hash',lambda x:x.__setitem__('source_geometry_hash','0'*64))]:
 bad=copy.deepcopy(f);mutate(bad)
 try:a.audit(row,bad)
 except AssertionError:negatives.append(name)
 else:raise AssertionError('corruption accepted: '+name)
print(json.dumps({'actual_source_samples':passed,'corruption_rejected':negatives,'note':'samples predate full-city source-hash field; source hash injected in memory for audit only, no frozen sample bytes modified'},indent=2))
