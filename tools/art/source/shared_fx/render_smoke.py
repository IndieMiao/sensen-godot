"""Render accepted R2.1 editable smoke clouds into four transparent original sprites."""
from pathlib import Path
import bpy, math
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[4];out=ROOT/'output/shared-fx';out.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'tools/art/source/blacksmith_shop/blacksmith_shop.blend'))
scene=bpy.context.scene
clouds=sorted([o for o in scene.objects if o.name.startswith('Smoke cloud ')],key=lambda o:o.name)
assert len(clouds)==4
for o in scene.objects:o.hide_render=True
scene.render.engine='CYCLES';scene.cycles.samples=16;scene.cycles.use_denoising=True
scene.render.resolution_x=256;scene.render.resolution_y=256;scene.render.resolution_percentage=100
scene.render.film_transparent=True;scene.render.image_settings.file_format='PNG';scene.render.image_settings.color_mode='RGBA'
scene.view_settings.view_transform='Standard';scene.view_settings.look='None';scene.view_settings.exposure=0;scene.view_settings.gamma=1
scene.world=bpy.data.worlds.new('Smoke studio');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(1,1,1,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.7
mat=bpy.data.materials.new('Neutral cartoon cloud');mat.use_nodes=True;bs=mat.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(.72,.74,.76,1);bs.inputs['Roughness'].default_value=1;bs.inputs['Specular IOR Level'].default_value=0
cam_data=bpy.data.cameras.new('Sprite camera');cam=bpy.data.objects.new('Sprite camera',cam_data);scene.collection.objects.link(cam);scene.camera=cam;cam_data.type='ORTHO'
light_data=bpy.data.lights.new('Cloud key','AREA');light_data.energy=150;light_data.size=4;light=bpy.data.objects.new('Cloud key',light_data);scene.collection.objects.link(light)
for i,o in enumerate(clouds):
 o.hide_render=False;o.data.materials.clear();o.data.materials.append(mat)
 bpy.context.view_layer.update();corners=[o.matrix_world@Vector(c) for c in o.bound_box];center=sum(corners,Vector())/8
 cam.location=center+Vector((2,-4,2));cam.rotation_euler=(center-cam.location).to_track_quat('-Z','Y').to_euler();cam_data.ortho_scale=max(o.dimensions)*1.35
 light.location=center+Vector((-2,-3,4));light.rotation_euler=(center-light.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=str(out/f'smoke-{i}.png');bpy.ops.render.render(write_still=True);o.hide_render=True
