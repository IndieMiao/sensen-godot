"""Clip a continuous mineral ribbon onto the original projected relief surface."""
from pathlib import Path
import json
import sys
import numpy as np
from shapely.geometry import Polygon, box
from shapely.ops import triangulate, unary_union

source=Path(sys.argv[1]);target=Path(sys.argv[2])
data=json.loads(source.read_text())
rng=np.random.default_rng(355)
centres=[(u,.20*u-3.45+.08*np.sin(u*.9)) for u in np.arange(-5.,18.,.8)]
upper=[];lower=[]
for u,v in centres:
    upper.append((u,v+rng.uniform(.10,.23)))
    lower.append((u,v-rng.uniform(.10,.23)))
inner=Polygon(upper+list(reversed(lower)))
outer=inner.buffer(.10,join_style=2)
rust_windows=unary_union([box(a,-20,b,20) for a,b in [(-2,-.7),(2.2,4.2),(6.5,7.4),(11,12.5)]])
regions=[('Rust_Host_Margin',outer.difference(inner).intersection(rust_windows),[.24,.063,.040],.007),
    ('Quartz_White_Seam',inner,[.94,.945,.95],.013)]
result=[]
for name,region,color,lift in regions:
    patches=[]
    for triangle in data['triangles']:
        points=np.array(triangle['uvn']);face=Polygon(points[:,:2])
        if face.area<1e-10 or not face.intersects(region):continue
        clipped=face.intersection(region)
        polygons=[clipped] if clipped.geom_type=='Polygon' else [p for p in getattr(clipped,'geoms',[]) if p.geom_type=='Polygon']
        matrix=np.column_stack((points[:,:2],np.ones(3)))
        depth=np.linalg.solve(matrix,points[:,2])
        fade=np.linalg.solve(matrix,np.array(triangle['fade']))
        for polygon in polygons:
            for tri in triangulate(polygon):
                if not polygon.covers(tri.representative_point()) or tri.area<1e-9:continue
                uv=np.array(tri.exterior.coords[:-1]);homogeneous=np.column_stack((uv,np.ones(3)))
                n=np.minimum(homogeneous@depth+lift,-5.605)
                fades=np.clip(homogeneous@fade,0,1)
                shade=(.96 if len(patches)%3==0 else 1.0) if name=='Quartz_White_Seam' else 1.0
                patches.append({'uvn':np.column_stack((uv,n)).tolist(),'fade':fades.tolist(),'shade':shade})
    result.append({'name':name,'color':color,'triangles':patches})
target.write_text(json.dumps(result,indent=2)+'\n')
print('Mineral triangles:',sum(len(row['triangles']) for row in result))
