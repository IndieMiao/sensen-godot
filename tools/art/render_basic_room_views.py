"""Orthographic checks from the actual Blender model, not generated concept variants."""
from pathlib import Path
import bpy
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/"output/basic-room-2026-10-06/orthographic"
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(ROOT/"tools/art/source/basic_room/basic_room.blend"))
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=12
scene.cycles.use_denoising=True
scene.render.resolution_x=900
scene.render.resolution_y=900
scene.render.resolution_percentage=100
camera=scene.camera
camera.data.type="ORTHO"
camera.data.ortho_scale=8.0
def v(p):return Vector((p[0],-p[2],p[1]))
for name,position,target in [
    ("front",(0,1.75,18),(0,1.75,0)),
    ("side",(18,1.75,0),(0,1.75,0)),
    ("top",(0,18,0),(0,0,0)),
]:
    camera.location=v(position)
    camera.rotation_euler=(v(target)-camera.location).to_track_quat("-Z","Y").to_euler()
    scene.render.filepath=str(OUT/(name+".png"))
    bpy.ops.render.render(write_still=True)
    print("ORTHOGRAPHIC_READY",name,flush=True)
