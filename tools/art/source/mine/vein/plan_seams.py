"""Clip a continuous mineral ribbon onto the original projected relief surface."""
from pathlib import Path
import json
import sys
import numpy as np
from shapely.geometry import Polygon
from shapely.ops import triangulate, unary_union
from shapely import set_precision

source=Path(sys.argv[1]);target=Path(sys.argv[2])
data=json.loads(source.read_text())
rng=np.random.default_rng(355)
centres=np.array([(1.9,11.4),(2.3,10.3),(2.15,9.55),(2.85,8.55),(2.95,7.7),(3.4,6.6),
    (4.0,4.5),(4.7,2.0),(5.5,-.8),(6.1,-2.6),(6.4,-3.5),(7.1,-4.35),(7.05,-5.15),(7.8,-6.8)])
def ribbon(widths):
    left=[];right=[]
    for i,point in enumerate(centres):
        tangent=centres[min(i+1,len(centres)-1)]-centres[max(i-1,0)]
        tangent/=np.linalg.norm(tangent);normal=np.array([-tangent[1],tangent[0]])
        left.append(point+normal*widths[i][0]);right.append(point-normal*widths[i][1])
    return Polygon(left+list(reversed(right)))
inner=ribbon(rng.uniform(.13,.28,(len(centres),2)))
outer=ribbon(rng.uniform(.34,.56,(len(centres),2)))
domain=unary_union([set_precision(Polygon(np.array(t['uvn'])[:,:2]),.00001) for t in data['triangles']]).buffer(-.08,join_style=2)
inner=inner.intersection(domain);outer=outer.intersection(domain)
regions=[('Rust_Host_Margin',outer.difference(inner),[.30,.105,.060],.009),
    ('Quartz_White_Seam',inner,[.78,.785,.79],.019)]
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
                if not polygon.covers(tri) or tri.area<1e-9:continue
                uv=np.array(tri.exterior.coords[:-1]);homogeneous=np.column_stack((uv,np.ones(3)))
                n=np.minimum(homogeneous@depth+lift,-5.605)
                fades=np.clip(homogeneous@fade,0,1)
                shade=([.84,.93,1.0,.90][len(patches)%4] if name=='Quartz_White_Seam' else [.76,1.,.88,1.08][len(patches)%4])
                patches.append({'uvn':np.column_stack((uv,n)).tolist(),'fade':fades.tolist(),'shade':shade})
    result.append({'name':name,'color':color,'triangles':patches})
target.write_text(json.dumps(result,indent=2)+'\n')
print('Mineral triangles:',sum(len(row['triangles']) for row in result))
