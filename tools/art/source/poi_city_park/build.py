"""SGODOT-320 N5, metres / Y-up / +Z entrance. Run with Blender -b --python.

The named source keeps editable construction pieces. Farm trees retain the
actual exported vertex colours, including their existing contact shading.
"""
from pathlib import Path
import hashlib
import json
import math
import random
import sys
import xml.etree.ElementTree as ET

import bpy
import numpy as np
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / 'tools/art'))
import scene_room_pipeline as p
from scene_room_pipeline import begin, cube, cylinder, ellipsoid, tube, mesh, lathe

SRC = Path(__file__).resolve().parent
REF = SRC/'reference' if (SRC/'reference').is_dir() else Path.home()/'incoming/poi-r3/314'
OUT = ROOT / 'assets/rooms/poi_city_park'
SHELL = ROOT / 'assets/rooms/_shared/shell_park'
PROVENANCE = {}
PLANTS = set()
NO_SHADOW = set()
CENTER_Z = .16


def cube(name, at, size, color, bevel=.025, kind='matte', axis='X'):
    obj = p.cube(name, at, size, color, bevel, kind, axis)
    if bevel == 0:
        for face in obj.data.polygons:
            face.use_smooth = False
    return obj


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')


def provenance(name, sources=(), changes=()):
    PROVENANCE[name] = {'asset': name, 'author': 'Huangzhong',
        'virtual_user_id': '5281cd25-6a49-4df8-9802-f3e534956e80',
        'sources': [{'file': str(s.relative_to(ROOT)) if s.is_relative_to(ROOT) else s.name,
                     'sha256': hashlib.sha256(s.read_bytes()).hexdigest()} for s in sources],
        'changes': list(changes), 'atlas': 'A: emission bake into N5 shared 2048x2048 atlas',
        'coordinates': 'metres, Y up, +Z front; geometry baked at unit scale'}


def box_collision(size, at=None, yaw=0):
    return {'at': at or [0, size[1] / 2, 0], 'size': size, 'yaw_degrees': yaw}


def current(name):
    p.b.CURRENT = p.KITS[name]


def farm_parts(name, original, at=(0, 0, 0), yaw=0, scale=(1, 1, 1), recolor=None, omit=()):
    source = ROOT / 'tools/art/source/decor_290/decor_290.blend'
    begin(name, at, yaw)
    k = p.KITS[name]
    with bpy.data.libraries.load(str(source), link=False) as (_, dst):
        dst.collections = [original]
    collection = dst.collections[0]
    display_offset = Vector(collection.get('source_display_offset_blender', (0, 0, 0)))
    for obj in list(collection.objects):
        if obj.type != 'MESH' or any(token in obj.name for token in omit):
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        collection.objects.unlink(obj)
        k['collection'].objects.link(obj)
        obj.parent = k['root']
        obj.location -= display_offset
        obj.location = Vector((obj.location.x * scale[0], obj.location.y * scale[2], obj.location.z * scale[1]))
        obj.scale = Vector((obj.scale.x * scale[0], obj.scale.y * scale[2], obj.scale.z * scale[1]))
        if recolor:
            for slot in obj.material_slots:
                key = slot.material.name.split('.')[0]
                if key in recolor:
                    slot.material = p.b.material(recolor[key])
        k['objects'].append(obj)
    bpy.data.collections.remove(collection)
    provenance(name, [ROOT / f'assets/farm/art/{original}.glb', source],
               [f'Editable {original} source parts; scale XYZ {scale}',
                f'Palette replacement: {recolor or "none"}', f'Removed: {omit or "none"}'])
    return k


def farm_glb(name, original, at, yaw=0):
    begin(name, at, yaw)
    k = p.KITS[name]
    source = ROOT / f'assets/farm/art/{original}.glb'
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(source))
    for obj in set(bpy.data.objects) - before:
        if obj.type != 'MESH':
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        matrix = obj.matrix_world.copy()
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        k['collection'].objects.link(obj)
        obj.parent = k['root']
        obj.matrix_basis = matrix
        obj.name = name + '_original_vertex_colour'
        # Use the raw colour attribute, not the glTF material's factor chain.
        mat = bpy.data.materials.new(name + '_source_colour')
        mat.use_nodes = True
        color = mat.node_tree.nodes.new('ShaderNodeVertexColor')
        color.layer_name = obj.data.color_attributes.active_color.name
        mat.node_tree.links.new(color.outputs['Color'], mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
        obj.data.materials.clear()
        obj.data.materials.append(mat)
        for face in obj.data.polygons:
            face.material_index = 0
        k['objects'].append(obj)
    provenance(name, [source], ['Actual GLB geometry and linear vertex colour retained, then atlas baked'])
    return k


def clone_into(asset, shift, scale=1, yaw=0):
    dest = p.b.CURRENT
    transform = Matrix.Translation(p.v(shift)) @ Matrix.Rotation(math.radians(yaw), 4, 'Z') @ Matrix.Scale(scale, 4)
    for source in p.KITS[asset]['objects']:
        obj = source.copy()
        obj.data = source.data.copy()
        dest['collection'].objects.link(obj)
        obj.parent = dest['root']
        obj.matrix_basis = transform @ source.matrix_basis
        dest['objects'].append(obj)


def slab(name, points, bottom, top, color, bevel=0):
    n = len(points)
    vertices = [(x, y, z) for y in [bottom, top] for x, z in points]
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    obj = mesh(name, vertices, faces, color)
    if bevel:
        m = obj.modifiers.new('Rounded garden edging', 'BEVEL')
        m.width = bevel
        m.segments = 2
        m = obj.modifiers.new('Garden edge normals', 'WEIGHTED_NORMAL')
        m.keep_sharp = True
    return obj


def polar(r, a):
    a = math.radians(a)
    return r * math.cos(a), r * math.sin(a)


def ribbon(name, points, width, y, height, color):
    for j, (a, b) in enumerate(zip(points, points[1:])):
        dx, dz = b[0] - a[0], b[1] - a[1]
        length = math.hypot(dx, dz)
        obj = cube(name + f' {j:02}', ((a[0]+b[0])/2, y+height/2, (a[1]+b[1])/2),
                   (length + width*.35, height, width), color, min(.035, width*.25))
        obj.rotation_euler.z = -math.atan2(dz, dx)


def shell():
    begin('park_ground', (0,0,0), collision=[box_collision([8, .18, 8], [0, -.09, 0])])
    cube('Eight metre lawn foundation', (0, -.09, 0), (8, .18, 8), '779C50', .05)
    ground = cube('Fine grass surface', (0, -.008, 0), (7.99, .016, 7.99), 'AFCB6C', 0)
    mat = ground.data.materials[0].copy()
    ground.data.materials[0] = mat
    nt = mat.node_tree
    tex = nt.nodes.new('ShaderNodeTexNoise')
    tex.inputs['Scale'].default_value = 25
    tex.inputs['Detail'].default_value = 2
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].color = (*p.rgb('92B65B'), 1)
    ramp.color_ramp.elements[1].color = (*p.rgb('B6CE76'), 1)
    nt.links.new(tex.outputs['Fac'], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], nt.nodes['Principled BSDF'].inputs['Base Color'])
    provenance('park_ground', [ROOT/'assets/farm/art/grass_clump.glb'], ['8x8m lawn; farm grass palette, fine colour-only grain'])

    begin('brick_paths', (0, 0, CENTER_Z))
    # Ring is a single connected annulus with distinct brick courses.
    for j in range(120):
        slab('Outside brick border', [polar(3.125,j*3),polar(3.2,j*3),polar(3.2,(j+1)*3),polar(3.125,(j+1)*3)],.001,.026,'B97C64')
    for row in range(3):
        r0, r1 = 2.75 + row*.15, 2.75 + (row+1)*.15
        count = round(math.tau * (r0+r1)/2 / .26)
        for j in range(count):
            a0, a1 = (j + (row % 2)*.5)*360/count, (j+1+(row%2)*.5)*360/count
            pts = [polar(r0+.004, a0+.12), polar(r1-.004, a0+.12),
                   polar(r1-.004, a1-.12), polar(r0+.004, a1-.12)]
            slab('Ring brick', pts, .002, .023, ['DE9174','DF987C','D3896F','E4A084'][(j+row*3)%4])
    # Cross paths join the centre, ring and entry. Grass beside them remains walkable.
    for axis in [0, 1]:
        for row in range(53 if axis == 0 else 58):
            z = -3.16 + (row+.5)*.12
            if axis == 0 and z > 3.16:
                continue
            x0=-.36;col=0
            while x0 < .359:
                length=min(.12 if row%2 and col==0 else .24,.36-x0)
                x=x0+length/2
                x0+=length;col+=1
                if abs(z)<1.04:continue
                at = (z, .018, x) if axis == 0 else (x, .018, z)
                size=(.112,.025,length-.008) if axis==0 else (length-.008,.025,.112)
                cube('Staggered cross axis brick',at,size,['DE9174','D58C71','E5A084'][(row+col)%3],0)
    for j in range(48):
        a0, a1 = j*7.5, (j+1)*7.5
        pts = [polar(.63,a0+.2), polar(1.06,a0+.2), polar(1.06,a1-.2), polar(.63,a1-.2)]
        slab('Radiating pale stone',pts,.022,.035,['E9DDC9','F0E6D5','DDCEB8'][j%3])
        if j%2 == 0:
            slab('White stone pointed ray',[polar(1.055,a0),polar(1.25,a0+3.75),polar(1.055,a1)],.022,.035,'F0E6D5')
    provenance('brick_paths', [], ['Outer ring diameter 6.40m; inner 5.50m; .72m cross and entry path', 'Radial white stone centre; SVG ring centre z=0.16m'])

    farm_parts('white_fence_segment','deco_fence',at=(20,0,0))
    begin('front_fence', (0,0,0), collision=[])
    for side in [-1,1]:
        for i in range(4):
            clone_into('white_fence_segment',(side*(1.235+i*.65),0,3.90))
        p.b.CURRENT['collision'].append(box_collision([2.62,.7,.12],[side*2.21,.35,3.90]))
    provenance('front_fence',[ROOT/'assets/farm/art/deco_fence.glb'],['Eight source segments; no rescaling or recolouring; centre entry left open'])


def benches():
    green = {'wood':'3F7256','wood_light':'638D65','wood_dark':'345744'}
    k = farm_parts('green_bench','deco_bench',(-1.12,0,CENTER_Z-1.12),45,
                   (.96/1.11,.715/.67,1),green)
    k['collision']=[box_collision([.96,1.12,.57],[0,.56,0])]
    for name,x,z,yaw in [('green_bench_2',1.12,-1.12,-45),('green_bench_3',-1.12,1.12,135),('green_bench_4',1.12,1.12,-135)]:
        p.instance('green_bench',name,(x,0,CENTER_Z+z),yaw)
    farm_parts('white_bench','deco_bench',(0,0,-3.45),0,(1.04/1.11,1,1),
               {'wood':'DDCEB8','wood_light':'F4EBD8','wood_dark':'C2BDAA'})
    p.KITS['white_bench']['collision']=[box_collision([1.04,1.05,.57])]
    farm_parts('bench_farm_control','deco_bench',(20,0,3))


def fountain():
    farm_parts('fountain','deco_fountain',(0,.035,CENTER_Z),omit=('still water',))
    p.KITS['fountain']['collision']=[box_collision([.86,.995,.86],[0,.4975,0],45),box_collision([1.12,.995,.42],[0,.4975,0]),box_collision([.42,.995,1.12],[0,.4975,0])]
    begin('fountain_water',(0,.035,CENTER_Z))
    for r,y in [(.511,.255),(.26,.7275)]:
        verts=[(0,y,0)]+[(r*math.cos(i*math.tau/48),y,r*math.sin(i*math.tau/48)) for i in range(48)]
        mesh('Basin water disc',verts,[(0,i+1,(i+1)%48+1) for i in range(48)],'82BBC5')
    for j in range(8):
        a=j*math.tau/8
        pts=[]
        for i in range(9):
            t=i/8;r=.295+.13*t
            pts.append((r*math.cos(a),.75-.49*t*t,r*math.sin(a)))
        tube('Thin falling water',pts,.007,'B9E1E5',5)
    NO_SHADOW.add('fountain_water')
    provenance('fountain_water',[ROOT/'modules/ponds/pond_water.gdshader'],['Existing pond shader, unchanged; two basin surfaces and eight short streams', 'No new shader; shared flow, ripple and caustic textures retained'])


def flowerbeds():
    begin('parterre_hedge',(0,0,CENTER_Z))
    # Three squared lobes per quadrant, joined along the outer edge.
    for j,angle in enumerate([30,45,60]):
        r0=2.02 if j!=1 else 1.92
        pts=[polar(r0,angle-7),polar(2.71,angle-7),polar(2.71,angle+7),polar(r0+.28,angle+7)]
        slab('Parterre recessed soil',pts,.01,.075,'715B3E')
        ribbon('Clipped zigzag hedge',pts+[pts[0]],.14,.018,.30,'6F9B3F' if j!=1 else '78A246')
        c=polar((r0+2.71)/2,angle)
        p.b.CURRENT['collision'].append(box_collision([2.71-r0+.14,.38,.72],[c[0],.19,c[1]],-angle))
        for k in range(19):
            a=angle-7+(k%7)*14/6
            r=2.71 if k//7==1 else r0+.28*(k%7)/6
            x,z=polar(r,a)
            ellipsoid('Clipped hedge crown',(x,.31,z),(.18,.075,.17),['79A644','82A94B','6C973B'][k%3],8,4)
    # A continuous outer band makes each three-lobed garden one readable group.
    ribbon('Joined outer garden hedge',[polar(2.70,a) for a in range(23,68,4)],.12,.02,.29,'759F41')
    provenance('parterre_hedge',[],['Four repeated three-lobed clipped beds; main-image silhouette overrides SVG placeholders','Height .35m; per-quadrant footprint measured from final vertices'])
    PLANTS.add('parterre_hedge')
    begin('parterre_flowers',(0,0,CENTER_Z))
    rng=random.Random(320)
    for j,a in enumerate([30,45,60]):
        for i in range(14):
            angle=a+rng.uniform(-4.5,4.5)
            inner=(2.02 if j!=1 else 1.92)+.28*(angle-(a-7))/14
            r=rng.uniform(inner+.11,2.55)
            x,z=polar(r,angle)
            h=rng.uniform(.18,.27)
            p.leaf('Small rounded garden leaf',(x-.045,.12,z),(x+.045,.21,z+.02),.04,'4C7B3B')
            color=['D74436','E9C34D','FFF2DD'][(i//3+j)%3]
            for petal in range(5):
                theta=petal*math.tau/5
                verts=[(x+.021*math.cos(theta),h+.004,z+.021*math.sin(theta))]
                for tip in range(6):
                    a2=tip*math.tau/6
                    verts.append((x+.030*math.cos(theta)+.026*math.cos(a2),h+.005*math.cos(a2-theta),z+.030*math.sin(theta)+.026*math.sin(a2)))
                mesh('Cupped six-triangle flower petal',verts,[(0,j+1,(j+1)%6+1) for j in range(6)],color,smooth=True)
            cylinder('Flower gold heart',(x,h+.01,z),.013,.008,'E6BE47',vertices=6)
    provenance('parterre_flowers',[ROOT/'assets/rooms/_shared/plants/source/build_plants.py'],['Shared small five-petal botanical vocabulary; red/yellow/ivory palette and compact planting'])
    PLANTS.add('parterre_flowers');NO_SHADOW.add('parterre_flowers')
    for n in ['parterre_hedge','parterre_flowers']:
        for i in range(1,4):
            p.instance(n,n+f'_{i+1}',(0,0,CENTER_Z),i*90)


def arch():
    # Retain the four farm pergola posts; replace the flat roof by a rose arch.
    k=farm_parts('rose_arch','deco_pergola',(0,0,-3.48),scale=(.88,.79,.55),
        recolor={'wood':'E7DDC9','wood_light':'F5ECD9'},
        omit=('load bearing','roof','climbing','attached','paired','post flower'))
    for z in [-.27,.27]:
        pts=[(.695*math.cos(i*math.pi/24),1.74+.66*math.sin(i*math.pi/24),z) for i in range(25)]
        tube('Ivory arched timber rib',pts,.055,'F4EBD8',8)
    for i in range(11):
        a=i*math.pi/10
        tube('Arch cross rafter',[(.695*math.cos(a),1.74+.66*math.sin(a),-.33),(.695*math.cos(a),1.74+.66*math.sin(a),.33)],.024,'DDD4C1',6)
    for side in [-1,1]:
        for j in range(7):
            y=.45+j*.21
            ellipsoid('Rose climbing leaf mass',(side*.70,y,.30),(.15,.24,.16),'507B45',8,4)
        for j in range(10):
            a=(j+.4)*math.pi/20+(0 if side>0 else math.pi/2)
            x,y=.72*math.cos(a),1.74+.70*math.sin(a)
            ellipsoid('Arch rose foliage',(x,y,.29),(.22,.19,.18),'5C854B',8,4)
            ellipsoid('Ivory rose blossom',(x,y+.04,.38),(.12,.12,.10),'FFF1DB' if j%3 else 'E6A7AE',10,5)
    k['collision']=[box_collision([.15,1.8,.15],[side*.695,.9,z]) for side in [-1,1] for z in [-.27,.27]]
    PROVENANCE['rose_arch']['changes'].append('Flat roof replaced by 2.45m rounded two-rib rose arch; rear white bench is decorative')


def street_furniture():
    begin('park_lamp',(-2.8,0,1.86))
    lathe('Lamp molded foot',(0,0,0),[(0,.13),(.035,.14),(.08,.11),(.16,.08),(.22,.06)],'3E5048',16)
    cylinder('Slender full-height park pole',(0,.94,0),.038,1.50,'43584E',vertices=12)
    for y in [.27,1.40,1.67]:
        lathe('Lamp collar',(0,y,0),[(0,.06),(.035,.065),(.07,.043)],'697466',12)
    cylinder('Lantern base',(0,1.72,0),.13,.055,'43584E',top=.10,vertices=8)
    cylinder('Warm opaque lantern panes',(0,1.865,0),.083,.25,'FFE9B6',top=.12,vertices=4)
    for i in range(4):
        a=math.pi/4+i*math.pi/2
        tube('Lantern frame',[(.085*math.cos(a),1.73,.085*math.sin(a)),(.125*math.cos(a),2.0,.125*math.sin(a))],.013,'43584E',6)
    cylinder('Lantern sloped crown',(0,2.065,0),.16,.15,'3E5048',top=.02,vertices=4)
    ellipsoid('Lamp top finial',(0,2.17,0),(.045,.06,.045),'576654',8,4)
    p.KITS['park_lamp']['collision']=[box_collision([.28,2.2,.28])]
    for i,(x,z) in enumerate([(2.8,1.86),(-1.60,-3.02),(1.60,-3.02)]):
        p.instance('park_lamp',f'park_lamp_{i+2}',(x,0,z))
    provenance('park_lamp',[],['New 2.20m slim lamp, not enlarged deco_lantern; four placed instances'])
    farm_parts('birdbath','deco_birdbath',(-2.62,0,-1.91))
    p.KITS['birdbath']['collision']=[box_collision([.58,.84,.58])]
    p.instance('birdbath','birdbath_2',(2.62,0,-1.91))
    begin('green_bin',(-3.25,0,1.20),collision=[box_collision([.42,.68,.42])])
    lathe('Fluted litter bin body',(0,0,0),[(0,.17),(.04,.19),(.58,.19),(.61,.205),(.64,.205),(.64,.14),(.57,.14)],'437D64',20)
    for i in range(20):
        a=i*math.tau/20
        tube('Bin vertical flute',[(.19*math.cos(a),.07,.19*math.sin(a)),(.19*math.cos(a),.57,.19*math.sin(a))],.008,'63916B',4)
    cylinder('Recessed bin opening',(0,.574,0),.14,.008,'314B3C',vertices=20)
    provenance('green_bin',[],['New reference-matched green bin; no farm bin asset found in wp-3d-scene or farm-dev inventory'])
    PROVENANCE['green_bin']['source_decision']='Shangguan confirmed New in Plane SGODOT-320 comment 77a66827-4aaa-4e0d-8dd5-c34bec3dead3'


def entry():
    begin('entry_gate',(0,0,3.72),collision=[])
    for side in [-1,1]:
        x=side*.85
        cube('Brick gate pier mortar',(x,.47,0),(.36,.94,.40),'C4AE92',.012)
        for level in range(10):
            y=.047+level*.09
            for front in [-1,1]:
                for col in range(2):
                    cube('Gate individual red brick',(x+(col-.5)*.17,y,front*.205),(.163,.079,.024),['C68166','DB9477'][(col+level)%2],0)
            for edge in [-1,1]:
                cube('Gate side brick',(x+edge*.186,y,0),(.025,.079,.39),'CF8A6E',0)
        cube('Pier pale coping',(x,.98,0),(.45,.10,.48),'EEE2CE',.027)
        cylinder('Sign support standard',(x,1.38,0),.025,.74,'476E59',vertices=10)
        ellipsoid('Sign post finial',(x,1.78,0),(.068,.08,.068),'8E9A7B',8,4)
        p.b.CURRENT['collision'].append(box_collision([.45,1.82,.48],[x,.91,0]))
    # The plaque is genuinely blank; the runtime sign socket carries text size.
    outline=[(x,1.45+.19*(1-(x/.82)**2)) for x in np.linspace(-.82,.82,25)]+[(x,1.75+.19*(1-(x/.82)**2)) for x in np.linspace(.82,-.82,25)]
    n=len(outline)
    vertices=[(x,y,z) for z in [-.035,.035] for x,y in outline]
    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh('Blank cream curved plaque',vertices,faces,'EEE3C9')
    for y in [1.45,1.75]:
        tube('Sign dark green curved edge',[(x,y+.19*(1-(x/.82)**2),.04) for x in np.linspace(-.82,.82,25)],.018,'476E59',6)
    for x in [-.82,.82]:tube('Sign end trim',[(x,1.45,.04),(x,1.75,.04)],.018,'476E59',6)
    for obj in p.b.CURRENT['objects']:
        if any(t in obj.name for t in ['plaque','Sign dark','Sign end','Sign post']):
            obj.location.z += .65
        elif 'Sign support' in obj.name:
            obj.scale.z *= 1.88
            obj.location.z += .325
    provenance('entry_gate',[],['Separate brick-pier and blank arched plaque module; sign_name runtime anchor; no baked lettering'])


def vegetation():
    farm_glb('park_tree','tree_0',(-3.18,.025,-2.90))
    PLANTS.add('park_tree')
    p.KITS['park_tree']['collision']=[box_collision([.30,2.8,.30],[0,1.4,0])]
    for i,(x,z,s) in enumerate([(3.18,-2.90,1.05),(-3.46,-.50,.95),(3.46,-.50,.95),(-3.50,2.75,.88),(3.50,2.75,.88)]):
        p.instance('park_tree',f'park_tree_{i+2}',(x,.025*s,z),i*73,scale=s)
    farm_glb('bush_control','bush',(20,.02,6))
    begin('shrub_layer',(0,0,0))
    for side in [-1,1]:
        for j,z in enumerate([-3.46,-2.55,-1.63,-.65,.43,1.50,2.54,3.29]):
            clone_into('bush_control',(side*(3.49 if j%2 else 3.64),.015,z),.65+(j%3)*.09,j*27)
        for x in [1.95,2.52]:clone_into('bush_control',(side*x,.015,-3.60),.72)
    provenance('shrub_layer',[ROOT/'assets/farm/art/bush.glb'],['Grouped farm bushes preserve original linear vertex colour; sized within border'])
    PLANTS.add('shrub_layer')
    begin('boundary_hedge',(0,0,0),collision=[])
    for x in [-3.80,3.80]:
        cube('Side clipped hedge',(x,.35,-.18),(.30,.70,7.47),'406D35',.055)
        p.b.CURRENT['collision'].append(box_collision([.30,.8,7.47],[x,.4,-.18]))
    cube('Rear clipped hedge',(0,.35,-3.83),(7.5,.70,.30),'406D35',.055)
    p.b.CURRENT['collision'].append(box_collision([7.5,.8,.30],[0,.4,-3.83]))
    for side in [-1,1]:cube('Front clipped hedge',(side*2.42,.25,3.75),(2.65,.50,.27),'5D883F',.05)
    provenance('boundary_hedge',[],['Main-reference clipped boundary; #406D35; corners stay inside 8m footprint'])
    PLANTS.add('boundary_hedge')
    begin('rear_topiary',(-1.03,0,-3.45),collision=[box_collision([.55,2.05,.55])])
    for level in range(6):
        y=.20+level*.31;r=.34*(1-level*.135)
        ellipsoid('Conical clipped crown tier',(0,y,0),(r*2,.62,r*2),'638C3B' if level%2 else '749E43',10,5)
    provenance('rear_topiary',[ROOT/'assets/farm/art/bush.glb'],['Compact six-tier clipped form in farm leaf palette; new silhouette'])
    PLANTS.add('rear_topiary')
    p.instance('rear_topiary','rear_topiary_2',(1.03,0,-3.45))


def backdrop():
    source=REF/'SGODOT-314_City_Park_Main_2026-10-31.png'
    target=SRC/'reference_backdrop.png'
    if not target.exists():
        image=bpy.data.images.load(str(source))
        w,h=image.size
        pixels=np.empty(w*h*4,dtype=np.float32);image.pixels.foreach_get(pixels)
        pixels=pixels.reshape(h,w,4)[h-210:h,:,:]
        crop=bpy.data.images.new('Approved distant village crop',width=w,height=210,alpha=False)
        crop.pixels.foreach_set(pixels.ravel());crop.filepath_raw=str(target);crop.file_format='PNG';crop.save()
    begin('village_backdrop',(-4.313,0,-4.313),45)
    obj=mesh('Single distant village card',[(-7,-.7,0),(7,-.7,0),(7,3.32,0),(-7,3.32,0)],[(0,1,2,3)],'FFFFFF')
    uv=obj.data.uv_layers.new(name='SourceBackdropUV')
    for loop,xy in zip(uv.data,[(0,0),(1,0),(1,1),(0,1)]):loop.uv=xy
    mat=obj.data.materials[0].copy();obj.data.materials[0]=mat
    node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=bpy.data.images.load(str(target),check_existing=True)
    coords=mat.node_tree.nodes.new('ShaderNodeUVMap');coords.uv_map='SourceBackdropUV'
    mat.node_tree.links.new(coords.outputs['UV'],node.inputs['Vector'])
    # A baked soft edge joins the one scenery card to the matching sky colour.
    separate=mat.node_tree.nodes.new('ShaderNodeSeparateXYZ')
    mat.node_tree.links.new(coords.outputs['UV'],separate.inputs[0])
    edge=[]
    for socket in [separate.outputs['X'],separate.outputs['Y']]:
        inverse=mat.node_tree.nodes.new('ShaderNodeMath');inverse.operation='SUBTRACT';inverse.inputs[0].default_value=1
        mat.node_tree.links.new(socket,inverse.inputs[1])
        minimum=mat.node_tree.nodes.new('ShaderNodeMath');minimum.operation='MINIMUM'
        mat.node_tree.links.new(socket,minimum.inputs[0]);mat.node_tree.links.new(inverse.outputs[0],minimum.inputs[1]);edge.append(minimum)
    minimum=mat.node_tree.nodes.new('ShaderNodeMath');minimum.operation='MINIMUM'
    for i,item in enumerate(edge):mat.node_tree.links.new(item.outputs[0],minimum.inputs[i])
    gain=mat.node_tree.nodes.new('ShaderNodeMath');gain.operation='MULTIPLY';gain.inputs[1].default_value=9;gain.use_clamp=True
    mat.node_tree.links.new(minimum.outputs[0],gain.inputs[0])
    mix=mat.node_tree.nodes.new('ShaderNodeMixRGB');mix.inputs[1].default_value=(*p.rgb('CFE5EF'),1)
    mat.node_tree.links.new(gain.outputs[0],mix.inputs[0]);mat.node_tree.links.new(node.outputs['Color'],mix.inputs[2])
    mat.node_tree.links.new(mix.outputs[0],mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
    provenance('village_backdrop',[source],['Approved main distant village/sky crop only; single noncolliding card, folded into same N5 atlas'])
    NO_SHADOW.add('village_backdrop')


def finish():
    anchors=[{'name':'spawn','position':[0,.04,2.65],'yaw_degrees':180},
             {'name':'exit','position':[0,.04,3.92],'yaw_degrees':0},
             {'name':'badge_exit','position':[0,1.1,3.92],'yaw_degrees':0},
             {'name':'sign_name','position':[0,2.40,3.77],'yaw_degrees':0,'size':[1.45,.22],'module':'entry_gate'},
             {'name':'cam_default','position':[0,.9,1.1],'yaw_degrees':45,'pitch_degrees':43,'width_m':6.72}]
    placements=[('green_bench',-1.12,-1.12,45),('green_bench_2',1.12,-1.12,-45),('green_bench_3',-1.12,1.12,135),('green_bench_4',1.12,1.12,-135)]
    for i,(name,x,z,yaw) in enumerate(placements):
        angle=math.radians(yaw)
        for j,offset in enumerate([-.23,.23]):
            anchors.append({'name':f'seat_bench_{i*2+j+1}','position':[x+math.cos(angle)*offset,.715,CENTER_Z+z-math.sin(angle)*offset],
                'yaw_degrees':yaw,'module':name,'approach':[x+math.sin(angle)*.60,.04,CENTER_Z+z+math.cos(angle)*.60]})
    p.MANIFEST_EXTRA.update({'anchors':anchors,'floor_size_m':[8,8],
        'reference_svg':{'scale_px_per_m':93.75,'park_rect_px':[80,175,750,750],'ring_center_px':[455,565]},
        'layout_adjustments':['Benches moved outward to radius 1.584m so a 0.5m capsule fits between seat fronts and the unchanged fountain; SVG furniture rectangles are schematic.',
                              'Parterres follow main-image three-lobed silhouette, not the 1.28x0.96m SVG placeholders.'],
        'boundaries':[box_collision([.12,3,8],[-4.06,1.5,0]),box_collision([.12,3,8],[4.06,1.5,0]),box_collision([8,3,.12],[0,1.5,-4.06]),
                      box_collision([3.2,3,.12],[-2.4,1.5,4.06]),box_collision([3.2,3,.12],[2.4,1.5,4.06])],
        'local_lights':[{'position':[x,1.86,z],'color':'FFE7B3','energy':.35,'range':1.4} for x,z in [(-2.8,1.86),(2.8,1.86),(-1.6,-3.02),(1.6,-3.02)]],
        'author':'Huangzhong','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80'})
    for image in bpy.data.images:
        if image.source=='FILE' and image.packed_file is None:
            image.pack()
    p.finalize({'position':[10,10,12],'target':[0,.7,0],'size':12},
               {'sun_color':'FFF3DA','sun_energy':1.05,'ambient_color':'E6EADA','ambient_energy':.50,'shadow':'single orthographic cascade'})
    for name,record in PROVENANCE.items():
        record['mesh_name']=name+'_mobile'
        save_json(SRC/'modules'/name/'reuse_provenance.json',record)
    save_json(SRC/'reuse_provenance.json',PROVENANCE)
    layout=json.loads((OUT/'layout.json').read_text())
    controls={'white_fence_segment','bench_farm_control','bush_control'}
    shell_names={'park_ground','front_fence','boundary_hedge','entry_gate'}
    for a in layout['assets']:
        a['review_only']=a['name'] in controls
        a['vegetation']=a['name'] in PLANTS
        a['cast_shadow']=a['name'] not in NO_SHADOW
        a['material']='pond_water' if a['name']=='fountain_water' else 'backdrop' if a['name']=='village_backdrop' else 'atlas'
        a['provenance']=f'tools/art/source/poi_city_park/modules/{a["name"]}/reuse_provenance.json'
        if a['name'] in shell_names:
            a['file']='../_shared/shell_park/'+a['file']
    save_json(OUT/'layout.json',layout)
    if '--geometry-only' in sys.argv:return
    p.bake_and_export()
    SHELL.mkdir(parents=True,exist_ok=True)
    for name in shell_names:
        (OUT/(name+'.glb')).replace(SHELL/(name+'.glb'))
    stats=json.loads((OUT/'asset_stats.json').read_text())
    by_name={a['name']:a for a in stats['assets']}
    placed=[a['name'] for a in layout['assets'] if not a['review_only']]+[a['asset'] for a in layout['instances']]
    stats.update({'scene_triangles':sum(by_name[n]['triangles'] for n in placed),
        'static_draw_surfaces':len(placed),'placed_instances':len(placed),'materials':3,
        'plant_triangles':sum(by_name[n]['triangles'] for n in placed if n in PLANTS),
        'review_only_assets':sorted(controls),'limits':{'triangles':150000,'surfaces':50,'plant_triangles':100000},
        'existing_water_textures':['assets/ponds/art/pond_ripple_field.png','assets/ponds/art/caustic_web.png','assets/farm/art/water/surface_flow.png'],
        'water_note':'Existing animated pond shader and textures are separate shared water resources, not additional N5 albedo atlases.'})
    save_json(OUT/'asset_stats.json',stats)
    assert stats['scene_triangles']<=150000 and stats['static_draw_surfaces']<=50,stats
    print('N5_EXPORT',stats['scene_triangles'],stats['static_draw_surfaces'],stats['plant_triangles'],flush=True)


def main():
    # Parse the actual approved SVG, so the scale evidence is not inferred from a PNG.
    tree=ET.parse(REF/'SGODOT-314_R3_topdown.svg')
    assert any(e.attrib.get('width')=='750' and e.attrib.get('height')=='750' for e in tree.iter())
    p.start('poi_city_park','SGODOT-314 R3 approved 4fa670a7')
    p.BAKE_SETTINGS.update({'ao_strength':.06,'floor_ao_strength':0,'ao_distance':.14})
    shell();benches();fountain();flowerbeds();arch();street_furniture();entry();vegetation();backdrop();finish()


if __name__=='__main__':main()
