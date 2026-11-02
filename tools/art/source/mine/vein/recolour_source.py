"""Synchronize the editable white-quartz colour without re-exporting geometry."""
from pathlib import Path
import sys
import bpy

SRC=Path(__file__).resolve().parent;sys.path.insert(0,str(SRC))
from quartz_colour import facet_colours
bpy.ops.wm.open_mainfile(filepath=str(SRC/'vein.blend'))
obj=bpy.data.objects['Quartz_White_Seam']
normals=[]
for polygon in obj.data.polygons:
    n=obj.matrix_world.to_3x3().inverted().transposed()@polygon.normal
    normals.append((n.x,n.z,-n.y))
colors=facet_colours(normals);layer=obj.data.color_attributes['StrataGray']
for polygon,color in zip(obj.data.polygons,colors):
    for index in polygon.loop_indices:layer.data[index].color=(*color,1)
bpy.ops.wm.save_as_mainfile(filepath=str(SRC/'vein.blend'))
print('Updated quartz colour only:',len(colors),'facets')
