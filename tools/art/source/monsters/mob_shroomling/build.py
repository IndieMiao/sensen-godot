"""SGODOT-355 shroomling blockout and the final seven-bone animation contract."""
from pathlib import Path
import math
import sys
import bpy
import bmesh
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent.parent))
import rigid_model as m

ID='mob_shroomling'
ANIMS={'idle':{'length':1.2,'loop':True},'move':{'length':.6,'loop':True},
    'windup':{'length':.55,'loop':False},'attack':{'length':.4,'loop':False,'hit_at':.18},
    'recover':{'length':.45,'loop':False},'hit':{'length':.25,'loop':False},
    'die':{'length':.75,'loop':False},'hide':{'length':1.0,'loop':False},
    'spore':{'length':.8,'loop':False,'emit_at':.35}}


def mesh(name,vertices,faces,color,bone,mask,mat):
    data=bpy.data.meshes.new(name);data.from_pydata([m.v(p) for p in vertices],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
    obj=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(obj)
    bpy.ops.object.select_all(action='DESELECT');obj.select_set(True)
    return m.paint(obj,name,color,bone,mask,mat)


PROFILE=[(0,.40),(.265,.39),(.295,.40),(.30,.435),(.28,.51),(.235,.59),(.16,.657),(.08,.69),(0,.70)]


def cap(mat):
    vertices=[];rings=[];faces=[];segments=32
    for radius,y in PROFILE:
        ring=[]
        for i in range(1 if radius==0 else segments):
            ring.append(len(vertices));a=i*math.tau/segments
            vertices.append((radius*math.cos(a),y,radius*math.sin(a)))
        rings.append(ring)
    for a,b in zip(rings,rings[1:]):
        for i in range(segments):
            j=(i+1)%segments
            if len(a)==1:faces.append((a[0],b[j],b[i]))
            elif len(b)==1:faces.append((a[i],a[j],b[0]))
            else:faces.append((a[i],a[j],b[j],b[i]))
    obj=mesh('Rounded coral mushroom cap',vertices,faces,'D9857D','cap',1,mat)
    colors=obj.data.color_attributes['Color']
    rgb=[int('D8C6A6'[i:i+2],16)/255 for i in [0,2,4]]
    linear=[((v+.055)/1.055)**2.4 for v in rgb]
    for face in obj.data.polygons:
        if face.center.z<.4:
            for loop in face.loop_indices:colors.data[loop].color=(*linear,1)
    surface=BVHTree.FromPolygons([vertex.co for vertex in obj.data.vertices],
        [list(face.vertices) for face in obj.data.polygons])
    def height(x,z):
        hit=surface.ray_cast(Vector((x,-z,1)),Vector((0,0,-1)))
        assert hit[0] is not None
        return hit[0].z+.006
    for index,(x,z,r) in enumerate([(-.14,.12,.047),(.14,.13,.05),(0,-.02,.06),(-.08,-.19,.044),(.17,-.13,.046),(0,.245,.04)]):
        points=[(x,height(x,z),z)]
        for fraction in [.5,1.0]:
            for i in range(12):
                px=x+math.cos(i*math.tau/12)*r*fraction;pz=z+math.sin(i*math.tau/12)*r*fraction
                points.append((px,height(px,pz),pz))
        faces=[(0,i+1,(i+1)%12+1) for i in range(12)]
        faces += [(i+1,13+i,13+(i+1)%12,1+(i+1)%12) for i in range(12)]
        patch=mesh('Cream cap spot '+str(index+1),points,faces,'F7E5C4','cap',0,mat)
        for face in patch.data.polygons:
            if face.normal.z<0:
                bm=bmesh.new();bm.from_mesh(patch.data);bmesh.ops.reverse_faces(bm,faces=bm.faces);bm.to_mesh(patch.data);bm.free();break
        # Keep the whole curved patch above the actual triangulated cap, not just its vertices.
        patch.data.calc_loop_triangles();lift=0.0
        for triangle in patch.data.loop_triangles:
            a,b,c=[patch.data.vertices[i].co for i in triangle.vertices]
            for u in range(17):
                for w in range(17-u):
                    point=a+(b-a)*(u/16)+(c-a)*(w/16)
                    hit=surface.ray_cast(Vector((point.x,point.y,1)),Vector((0,0,-1)))
                    if hit[0] is not None:lift=max(lift,hit[0].z-point.z+.001)
        for vertex in patch.data.vertices:vertex.co.z+=lift
        patch['surface_clearance_lift_m']=lift
        print('CAP_SPOT_CLEARANCE',index+1,round(lift,6),flush=True)


def pose(name,u,t,bones):
    stem=bones['stem'];capbone=bones['cap'];phase=u*math.tau
    if name=='idle':
        stem.scale.z=1+.018*math.sin(phase)
        capbone.rotation_euler.y=.025*math.sin(phase*2)
        capbone.scale=(1+.012*math.sin(phase*2),1+.012*math.sin(phase*2),1)
    elif name=='move':
        stem.location.z=.016*(1-math.cos(phase*2));stem.rotation_euler.y=.055*math.sin(phase)
        capbone.rotation_euler.y=-.035*math.sin(phase)
        for side,sign in [('l',-1),('r',1)]:
            bones['foot_'+side].rotation_euler.x=sign*.30*math.sin(phase)
            bones['foot_'+side].location.z=.02*max(0,sign*math.sin(phase))
            bones['arm_'+side].rotation_euler.x=-sign*.22*math.sin(phase)
    elif name=='windup':
        stem.scale.z=1-.16*u;stem.rotation_euler.x=-.15*u;capbone.rotation_euler.x=-.10*u
    elif name=='attack':
        k=math.sin(math.pi*u);stem.rotation_euler.x=.42*k;stem.scale.z=1+.12*k
        for side in ['l','r']:bones['arm_'+side].rotation_euler.x=.55*k
        capbone.rotation_euler.x=.18*k
    elif name=='recover':
        stem.rotation_euler.x=.14*(1-u);capbone.rotation_euler.y=.045*math.sin(math.tau*u)*(1-u)
    elif name=='hit':
        k=math.sin(math.pi*u);stem.rotation_euler.x=-.24*k;stem.scale.z=1-.14*k
        capbone.rotation_euler.x=.08*k
    elif name=='die':
        k=min(1,u/.85);stem.scale=(max(.12,1-.88*k),)*3
        stem.location.z=-.19*k;stem.rotation_euler.y=.85*k
        for side in ['l','r']:bones['foot_'+side].scale=(max(.1,1-k*.9),)*3
    elif name=='hide':
        k=min(1,u/.35);k=k*k*(3-2*k)
        sx=1-.18*k;sy=1-.75*k;stem.scale=(sx,sx,sy);stem.location.z=-.12*k
        capbone.scale=(1/sx,1/sx,1/sy)
        for side,sign in [('l',-1),('r',1)]:
            bones['arm_'+side].location.x=-sign*.10*k
            bones['foot_'+side].location.z=.12*k;bones['foot_'+side].scale=(1-.65*k,)*3
    elif name=='spore':
        k=math.sin(math.pi*min(t/.70,1));capbone.scale=(1+.15*k,1+.15*k,1+.08*k)
        stem.scale.z=1-.06*k
        for side,sign in [('l',-1),('r',1)]:bones['arm_'+side].rotation_euler.y=sign*.18*k


def main():
    mat=m.start(ID)
    m.ellipsoid('Cream rounded stem',(0,.255,0),(.29,.36,.265),'EEE0BD','stem',1,mat,16,8)
    for side,sign in [('l',-1),('r',1)]:
        m.ellipsoid('Rounded arm '+side,(sign*.162,.255,.012),(.07,.17,.082),'DFCEAA','arm_'+side,1,mat,8,6,sign*22)
        m.ellipsoid('Rounded foot '+side,(sign*.075,.055,.025),(.095,.11,.13),'D1C09C','foot_'+side,1,mat,10,4)
        m.ellipsoid('Black eye '+side,(sign*.054,.307,.127),(.031,.046,.022),'30303C','stem',0,mat,8,6)
        m.ellipsoid('White eye glint '+side,(sign*.054-.005,.318,.138),(.011,.013,.006),'FFF8ED','stem',0,mat,6,4)
        m.ellipsoid('Rose cheek '+side,(sign*.092,.271,.111),(.040,.025,.010),'E8B0C6','stem',0,mat,8,4)
    cap(mat)
    bones=[('root',None,(0,0,0)),('stem','root',(0,.24,0)),('cap','stem',(0,.40,0)),
        ('arm_l','stem',(-.14,.32,0)),('arm_r','stem',(.14,.32,0)),
        ('foot_l','root',(-.075,.08,0)),('foot_r','root',(.075,.08,0))]
    rig=m.skeleton(bones);m.animate(rig,ANIMS,pose)
    m.export(ID,rig,{'radius':.32,'height':.70,'hit_point':[0,.28,.04],'badge_point':[0,.92,0],
        'spore_point':[0,.65,0],'anims':ANIMS,
        'note':'hide is a one-shot 1.0s clip ending tucked; consumer controls hold time. Spore emission is at .35s. No root motion.'})


if __name__=='__main__':main()
