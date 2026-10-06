"""Art-only room kit helpers. Basic Room source and exports stay read-only.

Model coordinates are metres, Y-up, front +Z. Every kit is exported at its
local mounting/floor pivot. Each scene owns its editable source and AO atlas.
"""
from pathlib import Path
import json
import math
import random
import sys
import numpy as np
import bpy
import bmesh
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import build_basic_room as b
from build_basic_room import (v, rgb, material, cube, ellipsoid, cylinder, tube,
                             lathe, mesh, arch_solid, arch_trim, boolean_cut, leaf, plant)

ROOT = Path(__file__).resolve().parents[2]
KITS = b.KITS
INSTANCES = []
OUT = SOURCE = QA = None
SLUG = NODE = ""
CAMERA = {}


def start(slug, node):
    global OUT, SOURCE, QA, SLUG, NODE
    SLUG, NODE = slug, node
    OUT = ROOT / 'assets/rooms' / slug
    SOURCE = ROOT / 'tools/art/source' / slug
    QA = ROOT / 'output' / (slug + '-2026-10-07')
    for p in (OUT, SOURCE, QA): p.mkdir(parents=True, exist_ok=True)
    (ROOT/'output/.gdignore').touch(); (SOURCE/'.gdignore').touch()
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections): bpy.data.collections.remove(c)
    KITS.clear(); INSTANCES.clear(); b.MATS.clear()
    bpy.context.preferences.filepaths.save_version = 0
    random.seed(71007)


def begin(name, at=(0, .082, 0), yaw=0, collision=None):
    b.begin(name, at, yaw, collision)


def reuse(name, at, yaw=0, source='basic_room', original=None):
    """Append named editable source parts, never flatten an existing GLB."""
    original = original or name
    path = ROOT/'tools/art/source'/source/(source+'.blend')
    with bpy.data.libraries.load(str(path), link=False) as (src, dst):
        dst.collections = ['KIT_'+original]
    c = dst.collections[0]
    if c is None: raise ValueError((source, original))
    bpy.context.scene.collection.children.link(c)
    root = next(o for o in c.objects if o.type == 'EMPTY')
    c.name='KIT_'+name;root.name=name
    root.location=v(at);root.rotation_euler.z=math.radians(yaw)
    layout=json.loads((ROOT/'assets/rooms'/source/'layout.json').read_text())
    spec=next(x for x in layout['assets'] if x['name']==original)
    KITS[name]={'collection':c,'root':root,'objects':[o for o in c.objects if o.type=='MESH'],
                'at':list(at),'yaw':yaw,'collision':spec['colliders']}
    return KITS[name]


def instance(asset, name, at, yaw=0, scale=1.0):
    root=bpy.data.objects.new(name,None);bpy.context.scene.collection.objects.link(root)
    root.location=v(at);root.rotation_euler.z=math.radians(yaw);root['linked_asset']=asset
    root.scale=(scale,scale,scale)
    for src in KITS[asset]['objects']:
        o=src.copy();o.data=src.data;bpy.context.scene.collection.objects.link(o);o.parent=root
    INSTANCES.append({'name':name,'asset':asset,'position':list(at),'yaw_degrees':yaw})
    if scale!=1.0:INSTANCES[-1]['scale']=[scale,scale,scale]


def shell(width=8, depth=6.4, height=3.65, window_z=.05, door_x=3.15, stone_floor=False,
          open_left=True, open_back=True):
    x=width/2;z=depth/2
    begin('room_shell',at=(0,0,0),collision=[{'at':[0,-.09,0],'size':[width+.3,.34,depth+.3]},
          {'at':[-x,height/2,0],'size':[.22,height,depth+.2]},
          {'at':[0,height/2,-z],'size':[width+.2,height,.22]}])
    cube('Rounded timber foundation',(0,-.15,0),(width+.40,.38,depth+.40),'oak_edge',.14,'wood')
    cube('Floor joints',(0,.0,0),(width,.12,depth),'joint',.015)
    rows=round(depth/(.48 if stone_floor else .34));step=depth/rows
    for row in range(rows):
        a=-x;col=0
        while a < x-.01:
            length=min((.8 if row%2 and col==0 else 1.65), x-a)
            cube('Stone tile' if stone_floor else 'Staggered oak floorboard',
                 (a+length/2,.05,-z+(row+.5)*step),(length-.012,.065,step-.009),
                 ['stone','plaster','plaster_light'][col%3] if stone_floor else ['floor','floor_light','floor','floor_shade'][(row*7+col*3)%4],.012,'matte' if stone_floor else 'wood')
            a+=length;col+=1
    for xx in (-x-.03,x+.03):cube('Floor long edging',(xx,.01,0),(.20,.22,depth+.35),'oak_light',.05,'wood','Z')
    for zz in (-z-.03,z+.03):cube('Floor end edging',(0,.01,zz),(width,.22,.20),'oak',.05,'wood')
    for name,at,yaw,length,cutx,opening in [('window_wall',(-x,0,0),90,depth,-window_z,'window'),('back_wall',(0,0,-z),0,width,door_x,'door')]:
        begin(name,at,yaw)
        wall=cube('Cream plaster infill',(0,height/2,0),(length,height,.18),'plaster',.04,'plaster')
        if (opening=='window' and open_left) or (opening=='door' and open_back):
            if opening=='window':cut=arch_solid('Window opening',1.78,1.32,2.38,.62,.7,0,'plaster')
            else:cut=arch_solid('Door opening',1.04,.07,1.89,.50,.7,0,'plaster')
            cut.location.x=cutx;boolean_cut(wall,cut)
        for xx in ((-length/2+.08,length/2-.08) if opening=="window" else (length/2-.08,)):
            cube('Upright oak timber',(xx,height/2,.06),(.26,height+.15,.30),'oak',.07,'wood','Y')
            cube('Timber joint cap',(xx,height-.05,.06),(.43,.39,.43),'oak_end',.10,'wood')
            cube('Post foot',(xx,.12,.05),(.37,.27,.36),'oak_edge',.04,'wood')
        cube('Heavy top beam',(0,height-.07,.04),(length-.10,.28,.28),'oak_light',.055,'wood')
        for xx in range(-int(length/2)+1,int(length/2),2):cube('Beam peg',(xx,height-.32,.12),(.20,.32,.16),'oak_edge',.033,'wood','Y')
        if opening=='window':cube('Wall skirting',(0,.18,.11),(length-.34,.19,.14),'oak',.025,'wood')
        else:
            edge=-length/2+.2;end=cutx-.62
            cube('Door left skirting',((edge+end)/2,.18,.11),(end-edge,.19,.14),'oak',.025,'wood')
    if open_left:
        reuse('arched_window',(-x+.10,0,window_z),90)
        reuse('window_garden',(-x-.16,0,window_z),90)
    if open_back:
        reuse('green_door',(door_x,.05,-z+.115))
        reuse('entry_mat',(door_x,.092,-z+.72))


def stool(name,at,yaw=0, height=.59,radius=.29):
    begin(name,at,yaw,[{'at':[0,height/2,0],'size':[radius*2,height,radius*2]}])
    cylinder('Round stool seat',(0,height,0),radius,.12,'oak_light',vertices=24)
    for a in (0,2.094,4.189):
        x=math.cos(a)*radius*.66;z=math.sin(a)*radius*.66
        tube('Splayed stool leg',[(x*1.25,0,z*1.25),(x,height-.03,z)],.05,'oak',8)


def book(at,height=.36,width=.11,color='sage', tilt=0):
    o=cube('Book pages',(at[0],at[1]+height/2,at[2]),(width*.84,height*.91,.24),'linen',.01)
    for dx in (-width*.5,width*.5):cube('Book cloth cover',(at[0]+dx,at[1]+height/2,at[2]),(.018,height,.27),color,.012,'cloth')
    cube('Rounded book spine',(at[0],at[1]+height/2,at[2]+.128),(width,height,.035),color,.017,'cloth')
    for dy in (.065,height-.065):cube('Spine embossed band',(at[0],at[1]+dy,at[2]+.15),(width*.78,.016,.009),'brass',.003)


def basket(at=(0,0,0),width=.55,height=.4,depth=.4,handle=False):
    x,y,z=at
    cube('Wicker basket inner',(x,y+height/2,z),(width*.93,height,depth*.93),'terra',.07)
    for j in range(7):
        yy=y+.04+j*(height-.05)/7
        for zz in (-depth/2,depth/2):tube('Horizontal wicker weave',[(x-width/2+.04,yy,z+zz),(x,yy+.009*(j%2),z+zz+.006),(x+width/2-.04,yy,z+zz)],.018,'oak_light',6)
        for xx in (-width/2,width/2):tube('Wicker side weave',[(x+xx,yy,z-depth/2+.025),(x+xx,yy,z+depth/2-.025)],.018,'oak',6)
    for i in range(9):
        xx=x-width*.46+i*width*.115
        for zz in (-depth*.50,depth*.50):tube('Vertical wicker rib',[(xx,y+.03,z+zz),(xx,y+height,z+zz)],.011,'oak_edge',5)
    if handle:
        tube('Bent basket handle',[(x+width*.43*math.cos(t),y+height+.40*math.sin(t),z) for t in [j*math.pi/20 for j in range(21)]],.025,'oak',8)


def mug(at=(0,0,0),color='porcelain'):
    x,y,z=at
    lathe('Glazed ceramic mug',at,[(0,.10),(.04,.12),(.23,.12),(.25,.115),(.25,.091),(.05,.081)],color,20)
    cylinder('Tea surface',(x,y+.205,z),.088,.006,'oak_dark',vertices=20)
    tube('Mug handle',[(x+.10,y+.19,z),(x+.20,y+.21,z),(x+.24,y+.13,z),(x+.20,y+.06,z),(x+.10,y+.07,z)],.025,color,8)
    leaf('Small painted leaf',(x-.02,y+.08,z+.12),(x+.035,y+.17,z+.12),.025,'sage')


def rug(name,at,width,depth,round_shape=False):
    begin(name,at)
    if round_shape:
        cylinder('Flat woven backing',(0,.012,0),width/2,.035,'terra_light',vertices=64)
        for j in range(1,17):
            r=width/2*j/17
            pts=[(r*math.cos(a),.037+.007*math.sin(a*54+j),r*math.sin(a)*depth/width) for a in [i*2*math.pi/80 for i in range(81)]]
            tube('Braided concentric rope',pts,.022,'oak_light' if j%2 else 'terra_light',5)
    else:
        cube('Soft green woven rug',(0,.016,0),(width,.045,depth),'linen_dark',.03,'cloth')
        for x in (-width/2+.15,width/2-.15):
            for dx in (-.045,.045):cube('Cream woven border',(x+dx,.043,0),(.043,.008,depth-.09),'linen',.007,'cloth')
        for j in range(round(depth/.07)):
            z=-depth/2+.04+j*.07
            tube('Flat weave thread',[(-width/2+.04,.041,z),(width/2-.04,.041,z)],.008,'linen_green',4)


def frame(name,at,yaw=0,width=.45,height=.56,text=None):
    begin(name,at,yaw)
    cube('Picture backing',(0,0,0),(width,height,.045),'linen',.014)
    for x in (-width/2,width/2):cube('Picture vertical frame',(x,0,.015),(.052,height+.04,.075),'oak',.016,'wood','Y')
    for y in (-height/2,height/2):cube('Picture horizontal frame',(0,y,.015),(width,.052,.075),'oak',.016,'wood')
    if text: lettering(text,(0,-height*.1,.045),width*.7,'oak_dark')
    else:
        tube('Botanical stem',[(0,-height*.32,.03),(0,height*.28,.03)],.011,'sage_dark',6)
        for sign in (-1,1):
            for yy in (-.10,.04,.16):leaf('Botanical print leaf',(0,yy,.035),(sign*width*.27,yy+.09,.035),.05,'sage')


def lettering(text,at,width,color='linen'):
    d=bpy.data.curves.new('Lettering '+text,'FONT');d.body=text;d.align_x='CENTER';d.size=.30;d.extrude=.002;d.bevel_depth=.001;d.resolution_u=3
    o=bpy.data.objects.new('Sign '+text,d);bpy.context.scene.collection.objects.link(o)
    o.location=v(at);o.rotation_euler=(math.pi/2,0,0)
    bpy.context.view_layer.update()
    if o.dimensions.x>0:o.scale*=width/o.dimensions.x
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH')
    b.finish(o,'Sign '+text,color)


def finalize(camera=None, lighting=None):
    global CAMERA
    CAMERA=camera or {'position':[11,9.7,13],'target':[0,1.35,0],'size':12.4}
    layout={'units':'metres','axes':'Godot Y-up, front +Z; Blender (x,-z,y)',
            'reference':{'file_key':'OMLTC3yw3u2WDjOZhLnhaR','node_id':NODE},
            'assets':[{'name':k,'file':k+'.glb','position':d['at'],'yaw_degrees':d['yaw'],'colliders':d['collision']} for k,d in KITS.items()],
            'instances':INSTANCES,'camera':CAMERA,'sun_direction':[-6,7,1.5]}
    if lighting:layout['review_lighting']=lighting
    (OUT/'layout.json').write_text(json.dumps(layout,indent=2)+'\n')
    b.setup_render();scene=bpy.context.scene
    scene.camera.location=v(CAMERA['position']);scene.camera.rotation_euler=(v(CAMERA['target'])-scene.camera.location).to_track_quat('-Z','Y').to_euler();scene.camera.data.ortho_scale=CAMERA['size']
    scene.render.resolution_x=1440;scene.render.resolution_y=1080
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/(SLUG+'.blend')))
    print('GEOMETRY_READY',SLUG,len(KITS),sum(len(k['objects']) for k in KITS.values()),flush=True)


def render_views():
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/(SLUG+'.blend')))
    scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=12;scene.cycles.use_denoising=True
    scene.render.resolution_x=800;scene.render.resolution_y=800
    camera=scene.camera;camera.data.ortho_scale=11.5
    for name,at,target in [('front',(0,2,20),(0,2,0)),('side',(20,2,0),(0,2,0)),('top',(0,22,0),(0,0,0))]:
        camera.location=v(at);camera.rotation_euler=(v(target)-camera.location).to_track_quat('-Z','Y').to_euler()
        scene.render.filepath=str(QA/(name+'.png'));bpy.ops.render.render(write_still=True)
        print('ORTHOGRAPHIC_READY',SLUG,name,flush=True)


def complete():
    if '--geometry-only' in sys.argv:return
    bake_and_export()
    if '--views' in sys.argv:render_views()
def bake_and_export():
    scene=bpy.context.scene;scene.render.engine="CYCLES";scene.cycles.samples=16
    scene.cycles.bake_type="EMIT";scene.render.bake.margin=8;scene.render.bake.use_clear=True
    bpy.context.view_layer.update();deps=bpy.context.evaluated_depsgraph_get()
    all_source=list(scene.objects)
    work=bpy.data.collections.new("TEMP_EXPORT");scene.collection.children.link(work)
    copies=[];names=list(KITS)
    for ki,name in enumerate(names):
        for source in KITS[name]["objects"]:
            ev=source.evaluated_get(deps)
            d=bpy.data.meshes.new_from_object(ev,depsgraph=deps)
            d.transform(source.matrix_world)
            attr=d.attributes.new("kit_id","INT","FACE")
            for item in attr.data:item.value=ki
            o=bpy.data.objects.new("Baked_"+source.name,d);work.objects.link(o);copies.append(o)
    for o in all_source:o.hide_render=True;o.hide_set(True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in copies:o.select_set(True)
    bpy.context.view_layer.objects.active=copies[0]
    bpy.ops.object.join();joined=bpy.context.object;joined.name="Atlas working mesh"
    # Fix tessellation before baking so curved cloth, leaves and thin tubes use
    # exactly the same triangles for the bake and glTF/Godot interpolation.
    tri = joined.modifiers.new('Stable bake and export triangles', 'TRIANGULATE')
    bpy.ops.object.modifier_apply(modifier=tri.name)
    joined.data.uv_layers.new(name="RoomAtlas")
    joined.data.uv_layers.active_index=len(joined.data.uv_layers)-1
    joined.data.uv_layers.active.active_render=True
    bpy.ops.object.mode_set(mode="EDIT");bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66),island_margin=.0015,area_weight=.5,correct_aspect=True,scale_to_bounds=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    joined.data.uv_layers.active.name="RoomAtlas"
    tex=bpy.data.images.new("RoomKit_Albedo_AO",width=2048,height=2048,alpha=False)
    tex.colorspace_settings.name="sRGB"
    tex.generated_color=(.5,.5,.5,1)
    for mat in joined.data.materials:
        nt=mat.node_tree;p=nt.nodes.get("Principled BSDF");out=nt.nodes.get("Material Output")
        image=nt.nodes.new("ShaderNodeTexImage");image.image=tex;nt.nodes.active=image
        emission=nt.nodes.new("ShaderNodeEmission")
        ao=nt.nodes.new("ShaderNodeAmbientOcclusion");ao.samples=16;ao.inputs["Distance"].default_value=.68
        # Keep occluded surfaces legible; this is contact AO, not baked sun/shadows.
        mix=nt.nodes.new("ShaderNodeMixRGB");mix.blend_type="MIX";mix.inputs[0].default_value=.58
        mix.inputs[1].default_value=(1,1,1,1);nt.links.new(ao.outputs["Color"],mix.inputs[2])
        multiply=nt.nodes.new("ShaderNodeMixRGB");multiply.blend_type="MULTIPLY";multiply.inputs[0].default_value=1
        base=p.inputs["Base Color"]
        if base.is_linked:nt.links.new(base.links[0].from_socket,multiply.inputs[1])
        else:multiply.inputs[1].default_value=base.default_value
        nt.links.new(mix.outputs[0],multiply.inputs[2]);nt.links.new(multiply.outputs[0],emission.inputs[0])
        nt.links.new(emission.outputs[0],out.inputs["Surface"])
    print("BAKING_ATLAS",len(joined.data.polygons),"polygons",flush=True)
    scene.render.bake.margin_type = 'EXTEND'
    bpy.ops.object.bake(type="EMIT")
    # Tiny bevel/leaf UV islands can leave unbaked black gutter texels in Cycles.
    # Every authored color is above zero and softened AO has a .42 floor, so
    # exactly-black RGB identifies empty atlas space, not intentional shadows.
    # Extend island colors before mip generation; never alter baked pixels.
    pixels = np.empty(2048 * 2048 * 4, dtype=np.float32)
    tex.pixels.foreach_get(pixels)
    pixels = pixels.reshape((2048, 2048, 4))
    valid = np.max(pixels[:, :, :3], axis=2) > .000001
    for _ in range(8):
        sums = np.zeros_like(pixels)
        counts = np.zeros((2048, 2048), dtype=np.float32)
        for axis, shift in [(0,1),(0,-1),(1,1),(1,-1)]:
            mask = np.roll(valid, shift, axis)
            if axis == 0: mask[0 if shift == 1 else -1, :] = False
            else: mask[:, 0 if shift == 1 else -1] = False
            sums += np.roll(pixels, shift, axis) * mask[:, :, None]
            counts += mask
        fill = ~valid & (counts > 0)
        pixels[fill] = sums[fill] / counts[fill, None]
        valid |= fill
    tex.pixels.foreach_set(pixels.ravel())
    tex.update()
    tex.filepath_raw=str(OUT/"room_albedo_ao.png");tex.file_format="PNG";tex.save()
    runtime=bpy.data.materials.new("RoomKit_SharedAtlas");runtime.use_nodes=True
    n=runtime.node_tree.nodes.new("ShaderNodeTexImage");n.image=tex
    p=runtime.node_tree.nodes.get("Principled BSDF");runtime.node_tree.links.new(n.outputs["Color"],p.inputs["Base Color"])
    p.inputs["Roughness"].default_value=.80;p.inputs["Specular IOR Level"].default_value=.25
    data=joined.data;data.calc_loop_triangles();uv=data.uv_layers.active.data
    normal=data.corner_normals;kit_attr=data.attributes["kit_id"].data
    stats={"atlas":{"size":[2048,2048],"file":"room_albedo_ao.png","purpose":"base colour + static contact ambient occlusion; no baked direct light"},"assets":[]}
    for ki,name in enumerate(names):
        faces=[f for f in data.polygons if kit_attr[f.index].value==ki]
        root=KITS[name]["root"];inv=root.matrix_world.inverted();rot=inv.to_3x3()
        ids=sorted({vi for f in faces for vi in f.vertices});mapping={old:new for new,old in enumerate(ids)}
        d=bpy.data.meshes.new(name+"_mobile")
        d.from_pydata([inv@data.vertices[i].co for i in ids],[],[[mapping[i] for i in f.vertices] for f in faces]);d.update()
        layer=d.uv_layers.new(name="RoomAtlas");normals=[];loop_index=0
        for newface,oldface in zip(d.polygons,faces):
            newface.use_smooth=oldface.use_smooth
            for li in oldface.loop_indices:
                layer.data[loop_index].uv=uv[li].uv
                normals.append((rot@normal[li].vector).normalized());loop_index+=1
        d.normals_split_custom_set(normals);d.materials.append(runtime)
        o=bpy.data.objects.new(name,d);work.objects.link(o)
        bpy.ops.object.select_all(action="DESELECT");o.select_set(True);bpy.context.view_layer.objects.active=o
        bpy.ops.export_scene.gltf(filepath=str(OUT/(name+".glb")),export_format="GLB",use_selection=True,
            export_apply=True,export_yup=True,export_texcoords=True,export_normals=True,export_materials="EXPORT",
            export_image_format="NONE",export_animations=False,export_cameras=False,export_lights=False)
        d.calc_loop_triangles()
        stats["assets"].append({"name":name,"vertices":len(d.vertices),"triangles":len(d.loop_triangles),"surfaces":1,"bytes":(OUT/(name+".glb")).stat().st_size})
        bpy.data.objects.remove(o,do_unlink=True)
    stats["unique_triangles"]=sum(a["triangles"] for a in stats["assets"])
    stats["scene_triangles"]=stats["unique_triangles"]+sum(next(a["triangles"] for a in stats["assets"] if a["name"]==i["asset"]) for i in INSTANCES)
    stats["static_draw_surfaces"]=len(names)+len(INSTANCES)
    stats["glb_bytes"]=sum(a["bytes"] for a in stats["assets"])
    stats["atlas_bytes"]=(OUT/"room_albedo_ao.png").stat().st_size
    stats["placed_instances"]=len(names)+len(INSTANCES)
    stats["materials"]=1+int(any(n.endswith("garden") for n in names))+int("fire" in names or any(n.endswith("_glow") for n in names))+int("display_glass" in names)
    (OUT/"asset_stats.json").write_text(json.dumps(stats,indent=2)+"\n")
    print("EXPORT_READY",json.dumps({k:stats[k] for k in ["unique_triangles","scene_triangles","static_draw_surfaces"]}),flush=True)
