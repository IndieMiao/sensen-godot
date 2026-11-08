"""Compare actual upward GLB faces against farm-dev, excluding exact stair cuts.

Uses positive-area triangle intersection, never triangle-centroid filtering.
Run with NumPy/Shapely; no Blender or renderer needed for this geometry audit.
"""
from pathlib import Path
import json, struct, subprocess, hashlib
import numpy as np
from shapely.geometry import Polygon, box, Point
from shapely.ops import unary_union

ROOT=Path(__file__).resolve().parents[4]
ASSETS=ROOT/'assets/landmarks/alcatraz_island'
HERE=Path(__file__).resolve().parent
BASE='188d82c0'
BEFORE='27417c0a'

def triangles(raw):
    n=struct.unpack_from('<I',raw,12)[0]
    doc=json.loads(raw[20:20+n]); blob=raw[28+n:]
    # The two ground GLBs deliberately export in world coordinates.
    assert all(not any(k in node for k in ('matrix','translation','rotation','scale')) for node in doc['nodes'])
    def acc(i):
        a=doc['accessors'][i]; v=doc['bufferViews'][a['bufferView']]
        dt={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
        c={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        off=v.get('byteOffset',0)+a.get('byteOffset',0); size=np.dtype(dt).itemsize
        return np.ndarray((a['count'],c),dtype=dt,buffer=blob,offset=off,strides=(v.get('byteStride',size*c),size))
    result=[]
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            result.append(acc(p['attributes']['POSITION'])[acc(p['indices']).reshape(-1,3)])
    return np.concatenate(result).astype(float)

def layers(t):
    normal=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])
    mask=(normal[:,1]>1e-7)&(np.ptp(t[:,:,1],axis=1)<1e-5)
    result={}
    for tri in t[mask]:
        y=round(float(tri[:,1].mean()),4)
        result.setdefault(y,[]).append(Polygon(tri[:,[0,2]]))
    return result

def original(ref,name):
    return subprocess.check_output(['git','show',f'{ref}:assets/landmarks/alcatraz_island/{name}.glb'],cwd=ROOT)

def main():
    cuts=json.loads((HERE/'geometry_report.json').read_text())['cutters']
    report={'baseline':BASE,'before':BEFORE,'grid_m':.5,'grid_origin_xz':[.25,.25],
            'normal_rule':'geometric winding +Y, horizontal faces; each source height separately',
            'mesh':{}}
    for name in ['alc_ground_terraces','alc_ground_summit']:
        old=original(BASE,name); bad=original(BEFORE,name); new=(ASSETS/(name+'.glb')).read_bytes()
        source=layers(triangles(old)); prior=layers(triangles(bad)); after=layers(triangles(new))
        rows=[]
        for y,polys in source.items():
            base=unary_union(polys); was=unary_union(prior.get(y,[])); now=unary_union(after.get(y,[]))
            excluded=unary_union([box(c['min'][0],c['min'][2],c['max'][0],c['max'][2])
                                  for c in cuts if c['min'][1]-1e-5<=y<=c['max'][1]+1e-5]).buffer(.0001)
            expected=base.difference(excluded)
            lost_before=expected.difference(was.buffer(.00001)); lost_after=expected.difference(now.buffer(.00001))
            count=0; missing_before=[]; missing_after=[]
            for ix in range(-100,101):
                for iz in range(-80,81):
                    x,z=ix*.5+.25,iz*.5+.25;pt=Point(x,z)
                    if not expected.covers(pt):continue
                    count+=1
                    if lost_before.covers(pt):missing_before.append([x,y,z])
                    if lost_after.covers(pt):missing_after.append([x,y,z])
            rows.append({'height':y,'outside_opening_samples':count,'missing_before':len(missing_before),
                         'missing_after':len(missing_after),'lost_area_before_m2':lost_before.area,
                         'lost_area_after_m2':lost_after.area,'missing_before_points':missing_before,
                         'missing_after_points':missing_after})
            assert not missing_after,(name,y,missing_after[:3])
            assert lost_after.area<.0001,(name,y,lost_after.area)
        report['mesh'][name]={'sha256':hashlib.sha256(new).hexdigest(),
                             'baseline_matches_art_source':old==original('edd184d65',name),'layers':rows,
                             'missing_before_total':sum(r['missing_before'] for r in rows),
                             'missing_after_total':sum(r['missing_after'] for r in rows)}
    strips=[]
    name='alc_ground_terraces'
    for label,y,rect in [('t1',3.27,[1.25,7.75,9.25,8.75]),('t3',7.77,[-3.25,-1.25,9.25,-.25])]:
        area=box(*rect);row={'name':label,'road_height':y,'rect_xz':rect,'area_m2':area.area}
        for version,raw in [('base',original(BASE,name)),('before',original(BEFORE,name)),('after',(ASSETS/(name+'.glb')).read_bytes())]:
            polys=layers(triangles(raw)).get(y,[])
            row[version]={'up_triangles_with_positive_area_intersection':sum(p.intersection(area).area>1e-8 for p in polys),
                          'covered_m2':unary_union(polys).intersection(area).area}
        strips.append(row)
    report['strips']=strips
    out=ROOT/'docs/design/alcatraz-mid-stairs-424-2026-11-08/surface-followup'
    out.mkdir(parents=True,exist_ok=True);(out/'surface-preservation.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({name:{k:v for k,v in r.items() if k!='layers'} for name,r in report['mesh'].items()},indent=2))
    print(json.dumps(strips,indent=2))

if __name__=='__main__':main()
