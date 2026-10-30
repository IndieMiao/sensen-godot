"""Independent actual GLB checks for the SGODOT-244 art contract."""
from collections import Counter
import colorsys
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

import numpy as np
from verify_chef_sign import load_glb, accessor

ROOT = Path(__file__).resolve().parents[2]
KIT = ROOT/'assets/farm/art'
OUT = ROOT/'output/sprinkler-244'
OUT.mkdir(parents=True, exist_ok=True)
BASELINE = 'fadcaa195f5bb34229fba3995b27c5808ff34089'
report = {'checks': [], 'measurements': {}, 'nodes': {}}


def check(ok, label):
    report['checks'].append({'passed': bool(ok), 'check': label})
    if not ok: print('FAIL', label)


def linear(colour):
    return np.where(colour <= .04045, colour/12.92, ((colour+.055)/1.055)**2.4)


def srgb(colour):
    return np.where(colour <= .0031308, colour*12.92, 1.055*colour**(1/2.4)-.055)


def hue(colour): return colorsys.rgb_to_hsv(*colour)[0]*360


doc, data = load_glb(KIT/'sprinkler.glb')
entry = json.loads((KIT/'manifest.json').read_text())['assets']['sprinkler']
palette = {k: np.array([int(v[i:i+2], 16)/255 for i in [0,2,4]]) for k,v in entry['palette_srgb'].items()}
palette_linear = {k: linear(v) for k,v in palette.items()}
check(not doc.get('images') and not doc.get('textures'), 'untextured vertex-painted model')
check(len(doc.get('materials', [])) == 1, 'one opaque shared material')
check(len(doc['meshes']) == 2, 'exactly two meshes')
check({n['name'] for n in doc['nodes']} == {'base', 'head', 'spray_origin'}, 'exact node names; no extra parts')
all_points, total, colours = [], 0, []
arrays = {}
for node in doc['nodes']:
    name = node['name']
    pivot = np.array(node.get('translation', [0,0,0]))
    check(np.allclose(node.get('scale', [1,1,1]), [1,1,1]), name+' unit scale')
    check(np.allclose(node.get('rotation', [0,0,0,1]), [0,0,0,1]), name+' identity rotation')
    check(np.allclose(pivot, [0,.42,0] if name != 'base' else [0,0,0]), name+' correct axis/pivot')
    if 'mesh' not in node:
        check(name == 'spray_origin', 'spray_origin is an empty node')
        continue
    mesh = doc['meshes'][node['mesh']]
    check(mesh['name'] == 'sprinkler_'+name+'_mobile', name+' stable mobile mesh name')
    check(len(mesh['primitives']) == 1, name+' exactly one surface')
    primitive = mesh['primitives'][0]
    check(set(primitive['attributes']) == {'POSITION','NORMAL','COLOR_0'}, name+' positions normals colours only')
    v = np.array(accessor(doc,data,primitive['attributes']['POSITION']))
    n = np.array(accessor(doc,data,primitive['attributes']['NORMAL']))
    c = np.array(accessor(doc,data,primitive['attributes']['COLOR_0']))
    ix = np.array(accessor(doc,data,primitive['indices'])).ravel().reshape(-1,3)
    t = v[ix]; normal = np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0])
    check(np.isfinite(v).all() and np.isfinite(c).all(), name+' finite data')
    check((np.linalg.norm(normal,axis=1)>1e-10).all(), name+' no degenerate faces')
    check((np.sum(normal*n[ix].mean(1),axis=1)>-1e-8).all(), name+' winding and normals agree')
    check(c.shape[1] == 3 or np.allclose(c[:,3],1), name+' opaque vertex colours')
    check(all(any(np.allclose(col[:3], p, atol=2/65535) for p in palette_linear.values()) for col in c), name+' flat authored palette only')
    world = v+pivot; arrays[name] = {'v':world,'c':c,'n':n,'indices':ix}
    all_points.extend(world); colours.extend(c[:,:3]); total += len(ix)
    report['nodes'][name] = {'triangles':len(ix),'surfaces':1,'pivot':pivot.tolist(),
                            'world_bounds':[world.min(0).tolist(),world.max(0).tolist()]}
points = np.array(all_points); lo,hi=points.min(0),points.max(0)
check(total==entry['triangles'] and total<=900 and entry['triangle_limit']==900,
      'actual total triangles <=900 and matches manifest')
check(entry['surfaces']==2, 'manifest two surfaces')
check(np.allclose([lo,hi],entry['bounds']), 'actual metre bounds match manifest')
check(np.allclose(entry['head_pivot'],[0,.42,0]) and np.allclose(entry['spray_origin'],[0,.42,0]), 'v1.2 manifest head and spray positions')
check(abs(lo[1])<1e-7 and .56<=hi[1]<=.58, 'bed-centred root and v1.3 height <=0.58m')
head = arrays['head']; base = arrays['base']
head_diameter = 2*np.linalg.norm(head['v'][:,[0,2]],axis=1).max()
stone = base['v'][base['v'][:,1]<.048]
stone_diameter=2*np.linalg.norm(stone[:,[0,2]],axis=1).max()
water = head['v'][np.array([any(np.allclose(c[:3],palette_linear[k],atol=2/65535) for k in ['water','water_light','water_shade']) for c in head['c']])]
cap_diameter=2*np.linalg.norm(water[:,[0,2]],axis=1).max()
check(head_diameter<=.400001,'v1.3 enlarged head stays within 0.40m swept diameter')
check(.239999<=stone_diameter<=.260001,'v1.1 stone pad diameter 0.24-0.26m')
check(abs(cap_diameter-.13)<1e-6,'v1.3 actual blue cap diameter 0.13m')
check(abs(water[:,1].max()-water[:,1].min()-.123)<1e-6,'v1.3 blue cap actual height 0.123m')
cap_upper=water[np.abs(water[:,1]-.520)<1e-6]
check(len(cap_upper)>=12 and abs(2*np.linalg.norm(cap_upper[:,[0,2]],axis=1).max()-.108)<1e-6,
      'v1.3 cap upper belly is 0.108m across at y=0.520m')
for angle in [0,45,90,135,180,225,270,315]:
    r=math.radians(angle); rotation=np.array([[math.cos(r),0,math.sin(r)],[0,1,0],[-math.sin(r),0,math.cos(r)]])
    rotated=(head['v']-[0,.42,0])@rotation.T+[0,.42,0]
    check(np.max(np.abs(rotated[:,[0,2]]))<=.47,'head '+str(angle)+'deg remains inside real plot')
    check(abs(rotated[:,1].min()-head['v'][:,1].min())<1e-7 and abs(rotated[:,1].max()-head['v'][:,1].max())<1e-7,'head '+str(angle)+'deg no vertical wobble')
# At inner/middle/end cross-sections, verify the actual tube has the prescribed
# minimum thickness and that the centre dips before it rises.
arm_centres=np.array(entry['arm_centreline_right_m'])
for i in [1,2,3]:
    distances=np.linalg.norm(head['v']-arm_centres[i],axis=1)
    ring=head['v'][np.abs(distances-.030)<1e-6]
    check(len(ring)>=8,'v1.3 actual curved arm ring '+str(i)+' radius 0.030m')
check(arm_centres[2,1]<arm_centres[0,1]-.015 and arm_centres[-1,1]>arm_centres[2,1]+.03,'arm centreline descends then rises')
plot_doc,plot_data=load_glb(KIT/'plot.glb'); p=plot_doc['meshes'][0]['primitives'][0]
pv=np.array(accessor(plot_doc,plot_data,p['attributes']['POSITION'])); pc=np.array(accessor(plot_doc,plot_data,p['attributes']['COLOR_0']))
check(np.allclose(pv.max(0)[[0,2]]-pv.min(0)[[0,2]],[.94,.94]),'unscaled plot is actually 0.94m square')
outer=(np.abs(pv[:,0])>.40)|(np.abs(pv[:,2])>.40)
common=Counter(tuple(np.round(c[:3],6)) for c in pc[outer]).most_common(1)[0][0]
rim=srgb(np.array(common))
wood_doc,wood_data=load_glb(KIT/'storage.glb'); wood_prim=wood_doc['meshes'][0]['primitives'][0]
wood_colours=accessor(wood_doc,wood_data,wood_prim['attributes']['COLOR_0'])
wood_linear=Counter(tuple(np.round(c[:3],6)) for c in wood_colours).most_common(1)[0][0]
wood=srgb(np.array(wood_linear)); brass=palette['brass']; sage=palette['sage']; blue=palette['water']
hue_gap=abs(hue(brass)-hue(wood))
check(hue_gap>=12 and 43<=hue(brass)<=60,'yellow brass hue separates from actual storage wood')
check(abs(hue(blue)-hue([.55,.78,.95]))<1,'blue hue matches COVER_TINT within 1 degree')
leaf=np.array([.34,.65,.22])
check(colorsys.rgb_to_hsv(*sage)[1]<colorsys.rgb_to_hsv(*leaf)[1] and np.dot(linear(sage),[.2126,.7152,.0722])>np.dot(linear(leaf),[.2126,.7152,.0722]), 'sage riser is greyer and lighter than actual crop leaf')
old_sage=np.array([166,179,151])/255
old_saturation=colorsys.rgb_to_hsv(*old_sage)[1]
new_saturation=colorsys.rgb_to_hsv(*sage)[1]
check(.08<new_saturation-old_saturation<.15,'sage saturation increases moderately from the prior grey-green')
check(np.dot(linear(brass),[.2126,.7152,.0722])>np.dot(linear(sage),[.2126,.7152,.0722]),'brass brighter than riser')
baseline_manifest=json.loads(subprocess.check_output(['git','show',BASELINE+':assets/farm/art/manifest.json'],cwd=ROOT))
current=json.loads((KIT/'manifest.json').read_text()); current['assets'].pop('sprinkler')
check(current==baseline_manifest,'all pre-existing manifest entries unchanged')
check(subprocess.check_output(['git','show',BASELINE+':assets/farm/art/plot.glb'],cwd=ROOT)==(KIT/'plot.glb').read_bytes(),'original plot bytes unchanged')
check(hashlib.sha256((KIT/'sprinkler.glb').read_bytes()).hexdigest()==entry['sha256'],'manifest SHA-256 correct')
prior_path=OUT/'v1.2-baseline.glb'
prior_path.write_bytes(subprocess.check_output(['git','show','0867b463:assets/farm/art/sprinkler.glb'],cwd=ROOT))
prior_doc,prior_data=load_glb(prior_path)
prior_base=next(n for n in prior_doc['nodes'] if n['name']=='base')
old_prim=prior_doc['meshes'][prior_base['mesh']]['primitives'][0]
old_v=np.array(accessor(prior_doc,prior_data,old_prim['attributes']['POSITION']))
old_c=np.array(accessor(prior_doc,prior_data,old_prim['attributes']['COLOR_0']))
old_n=np.array(accessor(prior_doc,prior_data,old_prim['attributes']['NORMAL']))
old_ix=np.array(accessor(prior_doc,prior_data,old_prim['indices'])).ravel().reshape(-1,3)
check(np.array_equal(old_v,base['v']),'v1.2 base positions unchanged')
check(np.array_equal(old_n,base['n']),'v1.2 base normals unchanged')
check(np.array_equal(old_c,base['c']),'v1.2 base vertex colours unchanged')
check(np.array_equal(old_ix,base['indices']),'v1.2 base topology unchanged')
check(prior_doc['nodes']==doc['nodes'],'v1.2 nodes and pivots unchanged')
# Filter the green riser foot, which also extends into the pad's height range.
def stone_points(vertices, colours):
    return sorted(tuple(np.round(v,6)) for v,c in zip(vertices,colours)
                  if any(np.allclose(c[:3],palette_linear[k],atol=2/65535)
                         for k in ['stone','stone_light','stone_shade']))
check(stone_points(old_v,old_c)==stone_points(base['v'],base['c']),'stone pad geometry retained')
check(prior_doc['materials']==doc['materials'],'shared material retained')
report['measurements']={'triangles':total,'bounds':[lo.tolist(),hi.tolist()], 'size_xyz_m':(hi-lo).tolist(),
    'head_swept_diameter_m':float(head_diameter),'stone_diameter_m':float(stone_diameter),'cap_diameter_m':float(cap_diameter),
    'arm_section_diameter_m':.060,'cap_height_m':float(water[:,1].max()-water[:,1].min()),
    'cap_upper_belly_diameter_m':float(2*np.linalg.norm(cap_upper[:,[0,2]],axis=1).max()),
    'plot_min_edge_clearance_m':float(.47-head_diameter/2)}
report['colour_comparison']={'plot_rim_linear':list(common),'plot_rim_srgb':rim.tolist(),
    'wood_source':'assets/farm/art/storage.glb: most frequent vertex colour',
    'source_correction':'plot.glb is an earthen bed without a wood frame; compare its real soil rim and a separate real farm wood sample.',
    'wood_linear':list(wood_linear),'wood_srgb':wood.tolist(),'brass_srgb':brass.tolist(),
    'wood_hue_degrees':hue(wood),'brass_hue_degrees':hue(brass),'hue_gap_degrees':hue_gap,
    'blue_hue_degrees':hue(blue),'coverage_hue_degrees':hue([.55,.78,.95]),'crop_leaf_srgb':leaf.tolist(),'riser_srgb':sage.tolist(),
    'prior_riser_saturation':old_saturation,'riser_saturation':new_saturation,
    'crop_leaf_saturation':colorsys.rgb_to_hsv(*leaf)[1]}
report['passed']=all(c['passed'] for c in report['checks'])
report['failures']=[c['check'] for c in report['checks'] if not c['passed']]
(OUT/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n')
print('SPRINKLER_GEOMETRY',report['passed'],len(report['checks']))
sys.exit(0 if report['passed'] else 1)
