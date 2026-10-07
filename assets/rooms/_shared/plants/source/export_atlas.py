"""Explicit botanical UV tiles: 12px guards at every mip-facing tile boundary.
Leaves use their authored LeafDetailUV; planters use continuous cylindrical UVs.
Small components use a single safe colour per source object, never per-face patches.
"""
import json,math
import bpy,numpy as np
from mathutils import Vector
import kit as k

def export():
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    mats=list(k.MATS.values());assert len(mats)<=256
    pixels=np.zeros((2048,2048,4),np.float32);pixels[:,:,:3]=k.rgb('E2CEA6');pixels[:,:,3]=1
    tiles={m.name:i for i,m in enumerate(mats)}
    yy,xx=np.mgrid[0:128,0:128];u=np.clip((xx-12)/104,0,1);v=np.clip((yy-12)/104,0,1)
    for i,m in enumerate(mats):
        color=np.array(m.diffuse_color[:3]);shade=np.ones((128,128,1),np.float32)
        if '_leaf_' in m.name:
            mid=np.exp(-((u-.5)/.016)**2)
            vein=np.exp(-(np.sin((v*5+abs(u-.5)*1.35)*math.pi)/.18)**2)*.32
            shade=(.94+.055*v+.07*np.maximum(mid,vein))[:,:,None]
        elif '_woven_' in m.name:
            a=np.floor(u*22);b=np.floor(v*16)
            over=((a+b)%2)==0
            grain=np.where(over,np.sin(u*22*math.tau),np.sin(v*16*math.tau))
            groove=(np.abs(np.sin(u*22*math.pi))<.15)|(np.abs(np.sin(v*16*math.pi))<.12)
            shade=(.94+.065*grain-.12*groove)[:,:,None]
        elif 'planter' in m.name.lower():shade=(.91+.09*v)[:,:,None]
        tile=np.zeros((128,128,4),np.float32);tile[:,:,:3]=np.clip(color*shade,0,1);tile[:,:,3]=1
        if '_split_leaf_' in m.name:
            shape=np.sin(np.pi*v)**.55
            mask=(abs(u-.5)<.49*shape)&(v>.018)&(v<.988)
            for j,level in enumerate((.30,.54,.76)):
                diagonal=level+.20*(abs(u-.5)-.12)
                slit=(abs(v-diagonal)<.030)&(abs(u-.5)>.15)&(abs(u-.5)<.50)
                mask &= ~slit
            for side in (-1,1):
                for level in (.40,.64):
                    hole=((u-(.5+side*.105))/.035)**2+((v-level)/.048)**2<1
                    mask &= ~hole
            tile[:,:,3]=mask
        row,col=divmod(i,16);pixels[row*128:(row+1)*128,col*128:(col+1)*128]=tile
    # Generated sRGB image pixel storage is encoded, unlike shader linear colours.
    # Writing linear values directly here made R1-style swatches dark/saturated.
    linear=pixels[:,:,:3].copy()
    pixels[:,:,:3]=np.where(linear<=.0031308,linear*12.92,1.055*np.power(linear,1/2.4)-.055)
    tex=bpy.data.images.new('Botanical_Detail_Atlas_R2',width=2048,height=2048,alpha=True)
    tex.colorspace_settings.name='sRGB';tex.pixels.foreach_set(pixels.ravel());tex.update()
    tex.filepath_raw=str(k.OUT/'room_albedo_ao.png');tex.file_format='PNG';tex.save()
    material=bpy.data.materials.new('BotanicalSharedAtlasR2');material.use_nodes=True
    image=material.node_tree.nodes.new('ShaderNodeTexImage');image.image=tex
    material.node_tree.links.new(image.outputs['Color'],material.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    material.node_tree.links.new(image.outputs['Alpha'],material.node_tree.nodes.get('Principled BSDF').inputs['Alpha'])
    stats={'revision':'R2.1','atlas':{'size':[2048,2048],'file':'room_albedo_ao.png','purpose':'authored UV leaf veins, wicker weave, per-component safe colour; no baked direct light','guard_pixels':12,'tile_pixels':128,'bytes':(k.OUT/'room_albedo_ao.png').stat().st_size},'assets':[]}
    for name,record in k.KITS.items():
        verts=[];faces=[];uvs=[];normals=[];smooth=[]
        for source in record['objects']:
            ev=source.evaluated_get(deps);d=bpy.data.meshes.new_from_object(ev,depsgraph=deps)
            transform=record['root'].matrix_world.inverted()@source.matrix_world
            normal_transform=transform.to_3x3().inverted().transposed()
            offset=len(verts);verts.extend(transform@v.co for v in d.vertices)
            detail=d.uv_layers.get('LeafDetailUV')
            for f in d.polygons:
                faces.append(tuple(offset+vi for vi in f.vertices));smooth.append(f.use_smooth)
                mi=tiles[d.materials[f.material_index].name];row,col=divmod(mi,16)
                for li in f.loop_indices:
                    if detail is not None:
                        a,b=detail.data[li].uv
                    elif 'cylindrical_uv_height' in source:
                        p=d.vertices[d.loops[li].vertex_index].co
                        a=(math.atan2(p.y,p.x)/math.tau)%1;b=p.z/float(source['cylindrical_uv_height'])
                    else:a,b=.35,.48
                    a=max(.001,min(.999,a));b=max(.001,min(.999,b))
                    uvs.append(((col*128+12+a*104)/2048,(row*128+12+b*104)/2048))
                    normals.append((normal_transform@d.corner_normals[li].vector).normalized())
            bpy.data.meshes.remove(d)
        d=bpy.data.meshes.new(name+'_R2_runtime');d.from_pydata(verts,[],faces);d.update()
        uv=d.uv_layers.new(name='RoomAtlas')
        for i,val in enumerate(uvs):uv.data[i].uv=val
        for p,s in zip(d.polygons,smooth):p.use_smooth=s
        d.normals_split_custom_set(normals);d.materials.append(material)
        obj=bpy.data.objects.new(name+'_export',d);bpy.context.scene.collection.objects.link(obj)
        bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
        bpy.ops.export_scene.gltf(filepath=str(k.OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_image_format='NONE',export_animations=False,export_cameras=False,export_lights=False)
        d.calc_loop_triangles();stats['assets'].append({'name':name,'vertices':len(d.vertices),'triangles':len(d.loop_triangles),'surfaces':1,'bytes':(k.OUT/(name+'.glb')).stat().st_size})
        bpy.data.objects.remove(obj,do_unlink=True)
    stats.update(unique_triangles=sum(a['triangles'] for a in stats['assets']),unique_assets=len(stats['assets']),static_draw_surfaces=len(stats['assets']),glb_bytes=sum(a['bytes'] for a in stats['assets']))
    (k.OUT/'asset_stats.json').write_text(json.dumps(stats,indent=2)+'\n')
    # Retain exactly the same painted appearance in the editable Blender source.
    for record in k.KITS.values():
        for source in record['objects']:
            data=source.data;detail=data.uv_layers.get('LeafDetailUV');target=data.uv_layers.new(name='RoomAtlas')
            for face in data.polygons:
                mi=tiles[data.materials[face.material_index].name];row,col=divmod(mi,16)
                for li in face.loop_indices:
                    if detail is not None:a,b=detail.data[li].uv
                    elif 'cylindrical_uv_height' in source:
                        co=data.vertices[data.loops[li].vertex_index].co
                        a=(math.atan2(co.y,co.x)/math.tau)%1;b=co.z/float(source['cylindrical_uv_height'])
                    else:a,b=.35,.48
                    a=max(.001,min(.999,a));b=max(.001,min(.999,b))
                    target.data[li].uv=((col*128+12+a*104)/2048,(row*128+12+b*104)/2048)
            data.uv_layers.active_index=len(data.uv_layers)-1;target.active_render=True
            data.materials.clear();data.materials.append(material)
    tex.pack()
    print('BOTANICAL_R2_READY',stats['unique_triangles'],flush=True)
