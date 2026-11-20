from pathlib import Path
import json
import shapely
from shapely.geometry import box
from shapely.affinity import affine_transform,rotate
from generator import core_from_geometry,cell_geometry,build
from validate_farm import validate
from audit_source_geometry import verify_topology
source=shapely.union_all([box(0,0,20,20),box(24,0,44,20),box(19,.05,25,.15)])
assert source.geom_type=='Polygon' and not source.interiors
c=core_from_geometry(source);h=c['source_cell_m'];x,y=c['source_origin_m'];normalized=affine_transform(rotate(source,c['rotation_deg'],origin=source.centroid),[1/h,0,0,1/h,-x/h,-y/h]);core=cell_geometry(c['cells']);assert core.geom_type=='MultiPolygon'
f=build('p-synthetic-single-fragments',c,{'parcel_id':'synthetic-single-fragments','address':None});v=validate(f);topology=verify_topology(normalized,core)
print(json.dumps({'scope':'synthetic single-source no-hole raster fragmentation; not shipped catalog','source_components':1,'core_components':len(core.geoms),'global_iou':c['iou'],'mask_validation':v,'source_topology':topology,'extension_connects_all_core':True},indent=2))
