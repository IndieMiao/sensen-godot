"""Cloth1 shirt + authored wine vest/bow tie + isolated cloth36 trousers in the cloth1 FBX."""
import argparse
import json
import math
from pathlib import Path
import sys
import bpy
from mathutils import Vector

sys.path.insert(0,str(Path(__file__).resolve().parent))
from build_nadia_batch3 import Geometry, load, write_fbx, components, OUT


def pants_source(runtime):
    source=runtime/'assets/avatar/source/cloth36_npc_sigrid/SK_dt_skin36.fbx'
    obj=load(source,'cloth');mesh=obj.data;group=components(mesh)[7]
    assert len(group)==522
    indices=sorted(group);mapping={v:i for i,v in enumerate(indices)}
    vertices=[tuple(mesh.vertices[i].co) for i in indices]
    weights=[{obj.vertex_groups[g.group].name:g.weight for g in mesh.vertices[i].groups} for i in indices]
    faces=[];uv=[];normals=[]
    for face in mesh.polygons:
        if face.vertices[0] not in group:continue
        faces.append(tuple(mapping[i] for i in face.vertices))
        uv.append([(mesh.uv_layers.active.data[i].uv.x*.5,mesh.uv_layers.active.data[i].uv.y*.5) for i in face.loop_indices])
        normals.append([tuple(mesh.corner_normals[i].vector) for i in face.loop_indices])
    return vertices,faces,uv,normals,weights


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--runtime-root',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    runtime=args.runtime_root
    trousers=pants_source(runtime)
    source=runtime/'assets/avatar/source/cloth1/SK_dt_skin01.fbx'
    dest=runtime/'assets/avatar/source/cloth1_npc_lou'
    obj=load(source,'cloth')
    builder=Geometry(obj,components(obj.data)[0])
    builder.labels[0]=('Original cloth1 shirt',list(range(builder.original_vertices)))
    assert builder.original_vertices==591
    tucked=0
    for i,(x,y,z) in enumerate(builder.vertices):
        if y<84:
            builder.vertices[i]=(x,80+(y-84)*.25,z)
            tucked+=1
    builder.uvs=[[(u,.5+.5*(v-.125)/.875) for u,v in row] for row in builder.uvs]
    vertices,faces,uv,normals,weights=trousers
    offset=len(builder.vertices)
    builder.vertices.extend(vertices);builder.faces.extend(tuple(i+offset for i in f) for f in faces)
    builder.uvs.extend(uv);builder.normals.extend(normals);builder.weights.extend(weights)
    builder.labels.append(('Dark trousers from cloth36 independent pants',list(range(offset,len(builder.vertices)))))

    def depth(x,y,front=True):
        direction=-1 if front else 1
        point,normal,index,distance=builder.bvh.ray_cast(Vector((x,y,-direction*45)),Vector((0,0,direction)),90)
        if point is None:return 17.2 if front else -14.0
        value=point.z-direction*2.5
        if front and y<=110: value=max(value,17.2)
        if not front and y<=110: value=min(value,-14.0)
        return value

    # Separate front panels open in a V around the retained shirt collar.
    rows=[(72,15.0,0),(80,16.0,0),(90,15.8,0),(98,15.5,0),(106,15.0,3.4),(114,11.8,5.9),(119,9.2,6.7)]
    edge_points={}
    for sign in [-1,1]:
        verts=[]
        for y,width,inner in rows:
            for col in range(5):
                x=sign*(inner+(width-inner)*col/4)
                yy=y+(3.5*col/4 if y==72 else 0)
                verts.append((x,yy,depth(x,yy)))
        faces=[(r*5+c,r*5+c+1,(r+1)*5+c+1,(r+1)*5+c) for r in range(len(rows)-1) for c in range(4)]
        if sign<0:faces=[tuple(reversed(f)) for f in faces]
        builder.add('Wine vest front '+str(sign),verts,faces,8)
        edge_points[sign]=[verts[r*5+4] for r in range(len(rows))]
    # Back and side panels sit over the same original shirt shell.
    back_rows=[(75,15.0),(80,16),(90,15.8),(98,15.5),(106,15),(114,11.8),(119,9.2)]
    verts=[]
    for y,width in back_rows:
        for c in range(9):
            x=-width+width*c/4;verts.append((x,y,depth(x,y,False)))
    faces=[(r*9+c,(r+1)*9+c,(r+1)*9+c+1,r*9+c+1) for r in range(len(back_rows)-1) for c in range(8)]
    builder.add('Wine vest back',verts,faces,8)
    for sign in [-1,1]:
        side=[]
        for i,(y,width) in enumerate(back_rows):
            front=edge_points[sign][i];back=(sign*width,y,depth(sign*width,y,False))
            side.extend([front,(sign*(width+2.8),y,0),back])
        faces=[(r*3+c,(r+1)*3+c,(r+1)*3+c+1,r*3+c+1) for r in range(len(back_rows)-1) for c in range(2)]
        if sign>0:faces=[tuple(reversed(f)) for f in faces]
        builder.add('Vest armhole side '+str(sign),side,faces,8)
        shoulder=[(sign*x,y,z) for y,z in [(118,depth(sign*8,118)),(122,2),(122,-3),(118,depth(sign*8,118,False))] for x in [6.7,9.2]]
        faces=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(3)]
        if sign<0:faces=[tuple(reversed(f)) for f in faces]
        builder.add('Sleeveless shoulder '+str(sign),shoulder,faces,8)

    def ellipsoid(label,at,radius,color,segments=12,rings=6):
        vertices=[]
        for j in range(rings+1):
            phi=-math.pi/2+math.pi*j/rings
            for i in range(segments):
                theta=i*math.tau/segments
                vertices.append((at[0]+radius[0]*math.cos(phi)*math.cos(theta),
                                 at[1]+radius[1]*math.sin(phi),
                                 at[2]+radius[2]*math.cos(phi)*math.sin(theta)))
        faces=[(j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i)
               for j in range(rings) for i in range(segments)]
        # Parameterization runs counterclockwise from a +Z view.
        faces=[tuple(reversed(f)) for f in faces]
        builder.add(label,vertices,faces,color)

    for sign in [-1,1]:
        # Puffy butterfly wings, narrower at the centre knot.
        outline=[(sign*.6,115.2),(sign*5.2,118),(sign*5.8,112.3),(sign*.7,112.5)]
        if sign>0:outline.reverse()
        vertices=[(x,y,z) for z in [10.4,12.7] for x,y in outline]
        faces=[(0,3,2,1),(4,5,6,7)]+[(i,(i+1)%4,(i+1)%4+4,i+4) for i in range(4)]
        builder.add('Black bow wing '+str(sign),vertices,faces,10)
    ellipsoid('Black bow centre',(0,114.5,12.1),(1.25,1.8,1.1),10,12,6)
    for y in [95,86,77]:
        ellipsoid('Vest button '+str(y),(0,y,depth(0,y)+.8),(.85,.85,.4),11,10,4)
    builder.finish(dest/'T_lou_cloth01_D.png')
    report=write_fbx(source,dest/source.name,builder,rebuild_skin=True)
    report.update(base='cloth1',base_triangles=1629,triangle_delta=report['triangles']-1629,
                  retained_shirt_vertices=591,retained_shirt_triangles=1111,
                  shirt_hem_tucked_vertices=tucked,
                  trousers_source='cloth36_npc_sigrid independent component 7',
                  trousers_vertices=522,trousers_triangles=1040)
    # Every assigned bone already belongs to the original cloth1 hierarchy.
    valid={g.name for g in builder.obj.vertex_groups if not g.name.startswith('EDIT_')}
    assert {'Knee_L','Knee_R','Hip_L','Hip_R'} <= valid
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'lou-dealer.blend'))
    (OUT/'lou-geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n')
    print('LOU_GEOMETRY',json.dumps(report),flush=True)


if __name__=='__main__':main()
