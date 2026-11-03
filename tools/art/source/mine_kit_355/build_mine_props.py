"""Four ore rocks and two decorative mine modules, with measured local contracts."""
from pathlib import Path
import math
import random
import sys
import argparse
import json
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
import static_asset as s

SOURCE='tools/art/source/mine_kit_355/models'
ROCKS='assets/mine/rocks'
PROPS='assets/mine/props'

def colour(hexcode,gain):
    return tuple(min(1,int(hexcode[i:i+2],16)/255*gain) for i in [0,2,4])

def split_patch(poly,side):
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=(a[1]-a[0])*side;db=(b[1]-b[0])*side
        if da>=0:result.append(a)
        if (da>=0)!=(db>=0):
            t=da/(da-db);result.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))
    return result

def ore(kind,index):
    s.start('rock_'+kind,.52 if kind=='coal' else .82)
    rng=random.Random(355+index*73);n=7;points=[]
    for layer,(radius,y) in enumerate(zip([.36,.47,.34,.15],[0,.15,.49,.61])):
        for i in range(n):
            angle=math.tau*i/n+.17*index
            r=radius*rng.uniform(.94,1.)
            points.append(Vector((math.cos(angle)*r,y+(rng.uniform(-.012,.012) if layer else 0),math.sin(angle)*r)))
    points.append(Vector((.015,.63,-.018)))
    faces=[]
    for layer in range(3):
        for i in range(n):
            a=layer*n+i;b=layer*n+(i+1)%n;c=(layer+1)*n+(i+1)%n;d=(layer+1)*n+i
            faces.extend([(a,b,c),(a,c,d)])
    faces += [(28,21+i,21+(i+1)%n) for i in range(n)]
    faces += [tuple(reversed(range(n)))]
    stone={'coal':'333B43','iron_ore':'606D75','copper_ore':'9D6852'}.get(kind,'69777B')
    colors=[colour(stone,rng.uniform(.92,1.09)) for p in points]
    s.mesh('Seven-sided four-tier stone',points,faces,stone,False,colors)
    palette={'iron_ore':['703C3E','8B4840','B4BFC3'], 'quartz':['D6C7EF','FAF8F1','C6ADE6'],
        'coal':['202A33','536471','374550'], 'copper_ore':['EB994D','F2B46A','6EAB94']}[kind]
    for layer in [1,2]:
        for i in [0,1,3,4,6]:
            a,b,c,d=[points[j] for j in [layer*n+i,layer*n+(i+1)%n,(layer+1)*n+(i+1)%n,(layer+1)*n+i]]
            shift=rng.uniform(-.06,.08)
            polygon=[(.13+shift,.02),(.48+shift,.01),(.66+shift,.37),(.50+shift,.98),(.20+shift,.98),(.29+shift,.43)]
            # Split along the source diagonal so each patch lies on its real rock face.
            for side in [-1,1]:
                uv=split_patch(polygon,side)
                normal=((b-a).cross(c-a) if side<0 else (c-a).cross(d-a)).normalized()
                if normal.dot((a+b+c+d)/4-Vector((0,.28,0)))<0:normal=-normal
                patch=[a+(b-a)*(u-v)+(c-a)*v+normal*.002 for u,v in uv] if side<0 else [a+(c-a)*u+(d-a)*(v-u)+normal*.002 for u,v in uv]
                tint=palette[(i+index)%3]
                if kind=='iron_ore' and layer==2 and i in [1,6]:tint=palette[2]
                if kind=='copper_ore':tint=palette[2] if layer==1 and i==4 else palette[(i+layer)%2]
                s.mesh('Irregular mineral seam '+str(layer)+' '+str(i)+' '+str(side),patch,[tuple(range(len(patch)))],tint,False)
    return s.export('rock_'+kind,ROCKS,SOURCE,400,{'origin':'bottom centre; Y up; front +Z',
        'reference':'mine_art.gd _ore: four seven-sided tiers at r=.36/.47/.34/.15 and top Y=.63',
        'shadow_radius_m':.52,'notes':['Fixed rock variant with exposed mineral colour patches; no texture or collision.',
            'v1.1 vertex colours only: deep rust and silver iron, bright copper with minor patina, white and lavender quartz.']})

def pebble(name,at,size,seed,color):
    obj=s.ellipsoid(name,at,size,color,7,4)
    rng=random.Random(seed)
    center=s.vector(at)
    for vertex in obj.data.vertices:
        offset=vertex.co-center;offset.x*=rng.uniform(.92,1);offset.y*=rng.uniform(.92,1)
        vertex.co=center+offset
    return obj

def flame(x,z):
    n=7;points=[];colors=[]
    for row,(y,r,dx) in enumerate([(1.22,.055,0),(1.30,.105,0),(1.40,.075,-.025),(1.51,.028,.025),(1.56,.006,.035)]):
        for i in range(n):
            a=math.tau*i/n;points.append((x+dx+r*math.cos(a),y,z+r*math.sin(a)*.8))
            colors.append(['DC8942','F7C967','FFDB85','FFE9A3','FFF0BF'][row])
    faces=[(row*n+i,row*n+(i+1)%n,(row+1)*n+(i+1)%n,(row+1)*n+i) for row in range(4) for i in range(n)]
    faces += [tuple(reversed(range(n))),tuple(4*n+i for i in range(n))]
    s.mesh('Warm yellow flame',points,faces,'FFDB85',True,colors)

def stele_crown(z):
    # A recessed-looking dark crown silhouette, inset in the front of the stone.
    outline=[(-.23,.43),(.23,.43),(.23,.68),(.12,.60),(0,.77),(-.12,.60),(-.23,.68)]
    s.mesh('Carved crown dark inset',[(x,y,z) for x,y in outline],[tuple(range(len(outline)))],'4C5C63',False)
    s.tube('Crown lower carved groove',[(-.21,.40,z),(0,.40,z),(.21,.40,z)],.012,'566670',6)

def arena():
    s.start('guard_arena',.9)
    rng=random.Random(355)
    for i in range(44):
        a=math.tau*i/44
        x=3.27*math.cos(a);z=2.04*math.sin(a);h=rng.uniform(.13,.23)
        pebble('Low boundary rubble '+str(i+1),(x,h/2,z),(.36,h,.29),i,['899295','A4A39A','777F88'][i%3])
    for x in [-1.65,1.5]:
        z=-2.01
        pebble('Torch stone foot',(x,.095,z),(.30,.19,.28),int((x+3)*10),'899295')
        s.tube('Torch timber post',[(x,.11,z),(x,1.27,z)],.055,'916447',8)
        s.tube('Torch iron lower collar',[(x,1.08,z),(x,1.14,z)],.079,'455D67',8)
        s.tube('Torch iron cup',[(x,1.18,z),(x,1.27,z)],.105,'586F79',8)
        flame(x,z)
    s.box('Stele stone foot',(-.05,.08,-2.02),(.90,.16,.31),'747F87',.04,1)
    s.box('Rounded crown stele',(-.05,.61,-2.04),(.70,1.08,.24),'A0A5A5',.09,2)
    stele_crown(-1.918)
    return s.export('guard_arena',PROPS,SOURCE,3000,{'origin':'ground centre','placement_world':[4.9,0,-3.8],
        'clear_ellipse_m':[6.0,3.6],'rubble_height_limit_m':.25,'collision':'none',
        'tall_geometry_world_x_range':[2.7,6.8],
        'notes':['Decorative oval rubble boundary; centre empty, no collision anywhere.',
            'Two rear torches and crown-carved stele only within world X 2.7..6.8.',
            'Ellipse rounds the rear-left corner away from the coexisting elevator.']})

def beam(name,a,b,width,color):
    a=Vector(a);b=Vector(b);mid=(a+b)/2
    obj=s.box(name,mid,(width,(b-a).length,width),color,.012,1)
    # Vertices are already baked in Blender world axes; rotate around the midpoint.
    center=s.vector(mid);rotation=Vector((0,0,1)).rotation_difference(s.vector((b-a).normalized()))
    for vertex in obj.data.vertices:vertex.co=center+rotation@(vertex.co-center)
    return obj

def hoop(name,x,y,z,radius,color):
    points=[(x,y+radius*math.cos(math.tau*i/12),z+radius*math.sin(math.tau*i/12)) for i in range(13)]
    s.tube(name,points,.015,color,5)

def elevator():
    s.start('elevator_station',.78)
    s.box('Iron platform base',(0,.065,0),(1.45,.13,1.30),'455D64',.025,1)
    for i in range(7):
        s.box('Platform plank '+str(i+1),((i-3)*.192,.15,0),(.184,.04,1.20),['B58C63','C19970','AF835C'][i%3],.006,1)
    for x in [-.62,.62]:
        for z in [-.48,.46]:
            s.box('Timber corner column',(x,.99,z),(.135,1.66,.14),'9C7454',.018,1)
            for y in [.27,1.65]:
                s.box('Teal post collar',(x,y,z),(.15,.09,.15),'3E7477',.008,1)
    for z in [-.48,.46]:
        s.box('Top timber crossbeam',(0,1.87,z),(1.45,.16,.16),'B1875F',.025,1)
    for x in [-.62,.62]:
        s.box('Top side beam',(x,1.87,-.01),(.14,.16,1.11),'9C7454',.018,1)
        beam('Side diagonal timber brace',(x,.30,-.40),(x,1.55,.39),.065,'816147')
    for i in range(5):
        s.box('Rear safety slat',((i-2)*.24,.96,-.49),(.045,1.35,.045),'59777B',.006,1)
    s.tube('Hoist axle',[(-.66,2.06,-.24),(.66,2.06,-.24)],.045,'455D64',8)
    s.tube('Rear rope drum',[(-.23,2.06,-.24),(.23,2.06,-.24)],.14,'A38666',12)
    for x in [-.25,.25]:
        s.tube('Drum end wheel',[(x-.018,2.06,-.24),(x+.018,2.06,-.24)],.18,'456D74',12)
    for i in range(5):hoop('Coiled hoist rope',(i-2)*.085,2.06,-.24,.145,'C5AB83')
    s.tube('Hanging hoist rope',[(0,2.05,-.085),(0,1.18,-.085)],.017,'C5AB83',6)
    for x in [-.49,.49]:
        s.box('Axle support',(x,1.99,-.24),(.10,.26,.13),'3E7477',.015,1)
    s.box('Blank plate backing',(0,.99,.455),(.58,.38,.05),'775B46',.012,1)
    s.box('Blank floor number plate',(0,.99,.495),(.50,.30,.03),'DFD8BA',.008,1)
    # Plate front is .510, backing front .480; text origin is a further 5 mm forward.
    s.box('Indicator support column',(.8,.60,.30),(.14,1.20,.14),'9C7454',.015,1)
    anchors=[{'name':'PlateAnchor','position':[0,.99,.515],'normal':[0,0,1],'size':[.50,.30]},
        {'name':'LampAnchor','position':[.8,.73,.47],'normal':[0,0,1]}]
    return s.export('elevator_station',PROPS,SOURCE,2500,{'origin':'ground centre','placement_world':[1.25,0,-6.75],
        'base_size_m':[1.45,1.3],'platform_top_m':.17,'plate_face_z':.510,'plate_backing_front_z':.480,
        'collision':'none','notes':['Timber station, four posts, bracing, rear drum and hanging rope; no modelled lamp.',
            'Blank 0.50 x 0.30 m plate projects 0.03 m from backing; PlateAnchor is 0.005 m in front of plate.',
            'LampAnchor matches runtime indicator; support post retained.']},anchors)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--ores-only',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    previous={row['name']:row for row in json.loads((s.RUNTIME/ROCKS/'manifest.json').read_text())['assets']} if args.ores_only else {}
    rocks=[previous['rock_coal'] if args.ores_only and kind=='coal' else ore(kind,i) for i,kind in enumerate(['iron_ore','quartz','coal','copper_ore'])]
    props=json.loads((s.RUNTIME/PROPS/'manifest.json').read_text())['assets'] if args.ores_only else [arena(),elevator()]
    for directory,assets in [(ROCKS,rocks),(PROPS,props)]:
        manifest={'task':'SGODOT-355','group':'mine_props','author':'黄忠',
            'virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80','axes':'metres; Y up; front +Z','assets':assets}
        s.save(s.RUNTIME/directory/'manifest.json',manifest)
        s.save(s.ROOT/SOURCE/(Path(directory).name+'_manifest.json'),manifest)

if __name__=='__main__':main()
