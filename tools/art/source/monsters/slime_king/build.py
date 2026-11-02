"""Three unrigged headpieces fitted to the real radius-one slime profile."""
from pathlib import Path
import math
import sys
import json
import argparse
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parents[2]/'mine_kit_355'))
import static_asset as s

DIRECTORY='assets/monsters/slime_king'
SOURCE='tools/art/source/monsters/slime_king'
TOP=1.43
PROFILE=[(.04,1.43),(.40,1.33),(.65,1.12),(.83,.88),(.94,.60),(1.0,.32)]


def height(x,z):
    radius=math.hypot(x,z)
    angle=math.atan2(z,x);sector=math.tau/32
    delta=(angle%sector)-sector/2
    radius*=math.cos(delta)/math.cos(sector/2)
    if radius<=PROFILE[0][0]:return TOP
    for (a,y),(b,w) in zip(PROFILE,PROFILE[1:]):
        if a<=radius<=b:return y+(w-y)*(radius-a)/(b-a)
    raise ValueError(('outside slime upper profile',x,z,radius))


def fit(obj,clearance=.001):
    obj.data.calc_loop_triangles();lift=0
    for triangle in obj.data.loop_triangles:
        a,b,c=[obj.data.vertices[i].co for i in triangle.vertices]
        for u in range(9):
            for w in range(9-u):
                p=a+(b-a)*(u/8)+(c-a)*(w/8);x,y,z=s.world(p)
                if x*x+z*z<.98**2:lift=max(lift,height(x,z)-TOP-y+clearance)
    for vertex in obj.data.vertices:vertex.co.z+=lift
    obj['slime_surface_lift_m']=lift
    return lift


def crown():
    s.start('crown');n=40;points=[];colors=[]
    for row in range(6):
        for i in range(n):
            a=i*math.tau/n;peak=(.5+.5*math.cos(5*(a-math.pi/2)))**2
            top=.105+.235*peak
            radius=[.30,.307,.30,.27,.26,.26][row]
            bottom=height(radius*math.cos(a),radius*math.sin(a))-TOP+.004
            y=[bottom,bottom+.022,top-.012,top,top-.014,bottom][row]
            points.append((radius*math.cos(a),y,radius*math.sin(a)))
            colors.append(['C98E3E','E9B34E','EDBC5E','F5D381','D6A14A','DDA745'][row])
    faces=[(row*n+i,row*n+(i+1)%n,((row+1)%6)*n+(i+1)%n,((row+1)%6)*n+i) for row in range(6) for i in range(n)]
    band=s.mesh('Fitted five-lobed gold crown',points,faces,'E9B34E',vertex_colors=colors);lift=fit(band)
    for i in range(5):
        a=math.pi/2+i*math.tau/5
        s.ellipsoid('Rounded crown tip '+str(i+1),(.285*math.cos(a),.337+lift,.285*math.sin(a)),(.044,.044,.044),'F6D888',6,3)
    s.ellipsoid('Front rounded gold gemstone setting',(0,.085+lift,.311),(.165,.17,.042),'DDA24C',8,5)
    s.ellipsoid('Front round coral jewel',(0,.085+lift,.339),(.125,.13,.035),'D86F79',8,5)
    return s.export('crown',DIRECTORY,SOURCE,800,{'pivot':'head contact centre; attach at Y=1.43*r',
        'slime_radius':1.0,'attachment_position':[0,TOP,0],'rounded_tips':5,
        'preview_body_tint':'79CDB6','reference':'mine_combat.gd _slime_body / director dispatch-huangzhong-2.txt',
        'notes':['Original gold crown with five rounded lobes and a front round jewel; bottom conforms to radius-one slime.']})


def plate(name,cx,cz,width,depth,color):
    xs=[-width/2,-width/2+.045,0,width/2-.045,width/2]
    zs=[-depth/2,-depth/2+.035,0,depth/2-.035,depth/2]
    points=[];colors=[]
    for layer in range(2):
        for j,z in enumerate(zs):
            for i,x in enumerate(xs):
                px=x;pz=z
                if i in [0,4] and j in [0,4]:px*=.92;pz*=.86
                xx=cx+px;zz=cz+pz;edge=i in [0,4] or j in [0,4]
                y=height(xx,zz)-TOP+.003+(0 if layer==0 else .036 if edge else .052)
                points.append((xx,y,zz));colors.append('354552' if layer==0 else 'AD9875' if edge else color)
    faces=[]
    for layer in range(2):
        for j in range(4):
            for i in range(4):
                a=layer*25+j*5+i;face=(a,a+1,a+6,a+5);faces.append(face if layer else tuple(reversed(face)))
    border=list(range(5))+[j*5+4 for j in range(1,5)]+list(range(23,19,-1))+[j*5 for j in range(3,0,-1)]
    for a,b in zip(border,border[1:]+border[:1]):faces.append((a,b,b+25,a+25))
    obj=s.mesh(name,points,faces,color,vertex_colors=colors);lift=fit(obj)
    return lift


def ironback():
    s.start('ironback_plates');specs=[('Wide forehead guard',0,.65,.94,.22),('Front helmet shell',0,.31,.96,.42),
        ('Top helmet shell',0,-.10,1.02,.40),('Upper back shell',0,-.49,.94,.34),('Lower back shell',0,-.765,.72,.20)]
    for index,(name,x,z,w,d) in enumerate(specs):
        plate(name,x,z,w,d,'4B6072')
        obj=s.PARTS[-1];obj.data.calc_loop_triangles()
        tree=BVHTree.FromPolygons([v.co for v in obj.data.vertices],[t.vertices for t in obj.data.loop_triangles],all_triangles=True)
        for dx in ([-w*.28,w*.28] if index in [0,2,4] else [0]):
            hit,normal,_,_=tree.ray_cast(s.vector((x+dx,2,z)),Vector((0,0,-1)))
            assert hit is not None
            if normal.z<0:normal=-normal
            centre=hit+normal*.009
            rivet=s.ellipsoid(name+' round rivet '+str(dx),s.world(centre),(.047,.022,.047),'E0C99C',6,3)
            rotation=Vector((0,0,1)).rotation_difference(normal)
            for vertex in rivet.data.vertices:vertex.co=centre+rotation@(vertex.co-centre)
    return s.export('ironback_plates',DIRECTORY,SOURCE,800,{'pivot':'head contact centre; rear along -Z',
        'slime_radius':1.0,'attachment_position':[0,TOP,0],'plate_count':5,
        'preview_body_tint':'8FAEB9','reference':'mine_combat.gd _slime_body / director dispatch-huangzhong-2.txt',
        'notes':['v1.1: wide contiguous blue-grey helmet shell with a forehead guard wider than the eyes.',
            'Darker iron centre, warm worn edges and eight bright rivets; same attachment origin and UID.']})


def quartz():
    s.start('quartz_cluster',.60)
    columns=[(0,0,.09,.53,.015,-.015),(-.15,.065,.075,.36,-.16,.04),
        (.15,.045,.08,.42,.17,.025),(-.095,-.14,.065,.31,-.095,-.14),(.09,-.13,.07,.46,.10,-.14)]
    for index,(x,z,r,h,lean_x,lean_z) in enumerate(columns):
        n=6;points=[];colors=[];profiles=[(0,.82),(.045,1),(.72,1),(.88,.62),(1,.035)]
        for row,(t,rr) in enumerate(profiles):
            for i in range(n):
                a=math.tau*i/n;xx=x+math.cos(a)*r*rr+lean_x*t;zz=z+math.sin(a)*r*rr+lean_z*t
                bottom=height(xx,zz)-TOP+.003
                y=bottom if row==0 else height(x,z)-TOP+t*h
                points.append((xx,y,zz));colors.append(['F5F3EA','FFFDF4','F0F0F3','D7C6E8','CAB7DD'][row])
        faces=[(row*n+i,row*n+(i+1)%n,(row+1)*n+(i+1)%n,(row+1)*n+i) for row in range(4) for i in range(n)]
        faces += [tuple(reversed(range(n))),tuple(4*n+i for i in range(n))]
        obj=s.mesh('Faceted pointed quartz column '+str(index+1),points,faces,'FFFDF4',False,colors);fit(obj)
        paint=obj.data.color_attributes['Color']
        for poly in obj.data.polygons:
            # Real prism faces alternate in value without transparent materials.
            gain=[1.0,.83,.95,.88,1.0,.86][poly.index%6]
            for loop_index in poly.loop_indices:
                color=paint.data[loop_index].color
                paint.data[loop_index].color=tuple(color[i]*gain if i<3 else color[i] for i in range(4))
    return s.export('quartz_cluster',DIRECTORY,SOURCE,800,{'pivot':'head contact centre; attach at Y=1.43*r',
        'slime_radius':1.0,'attachment_position':[0,TOP,0],'column_count':5,
        'preview_body_tint':'D7B8CF','reference':'mine_combat.gd _slime_body / director dispatch-huangzhong-2.txt',
        'notes':['v1.1: five outward-leaning faceted quartz prisms with different lengths and pointed tips.',
            'White bases, faint lavender tips, alternating light/dark facets; opaque vertex colour only.']})


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--only',nargs='+')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    builders={'crown':crown,'ironback_plates':ironback,'quartz_cluster':quartz}
    previous={}
    if args.only:
        previous={row['name']:row for row in json.loads((s.RUNTIME/DIRECTORY/'manifest.json').read_text())['assets']}
    assets=[build() if not args.only or name in args.only else previous[name] for name,build in builders.items()]
    manifest={'task':'SGODOT-355','group':'headgear','author':'黄忠','virtual_user_id':'5281cd25-6a49-4df8-9802-f3e534956e80',
        'axes':'metres; Y up; front +Z; normalized to slime radius 1.0',
        'attachment_origin':[0,TOP,0],'slime_profile':PROFILE,'slime_radial_segments':32,
        'body_colours':'Preview palette proposals only; runtime selects each king body tint.','assets':assets}
    s.save(s.RUNTIME/DIRECTORY/'manifest.json',manifest)
    s.save(Path(__file__).resolve().parent/'manifest.json',manifest)


if __name__=='__main__':main()
