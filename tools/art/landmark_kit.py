"""Shared Blender helpers for landmark scenes (same conventions as build_farm_assets.py).

Modeling helpers take Godot Y-up coordinates (x east, y up, z toward the camera).
Each asset collection exports as one merged mesh with one vertex-paint material;
ambient occlusion is baked into the vertex colors so runtime needs no SSAO.
"""

import json
import math
from pathlib import Path

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def reset_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    bpy.context.preferences.filepaths.save_version = 0
    for block in list(bpy.data.collections):
        bpy.data.collections.remove(block)


def linear(c):
    return c / 12.92 if c < 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hex_rgb(h):
    return tuple(linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))


class Kit:
    def __init__(self, out_dir, colors):
        self.out = Path(out_dir)
        self.out.mkdir(parents=True, exist_ok=True)
        self.colors = colors
        self.mats = {}
        for name, h in colors.items():
            mat = bpy.data.materials.new(name)
            mat.diffuse_color = (*hex_rgb(h), 1)
            self.mats[name] = mat
        self.current = None
        self.assets = {}
        self.no_ao = set()

    # -- collections -------------------------------------------------------
    def begin(self, name, ao=True):
        self.current = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(self.current)
        self.assets[name] = self.current
        if not ao:
            self.no_ao.add(name)

    def _finish(self, obj, name, color, smooth=False):
        obj.name = name
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        self.current.objects.link(obj)
        obj.data.materials.append(self.mats[color])
        if smooth:
            for f in obj.data.polygons:
                f.use_smooth = True
        return obj

    @staticmethod
    def v(p):
        return Vector((p[0], -p[2], p[1]))

    # -- primitives --------------------------------------------------------
    def box(self, name, center, size, color, bevel=0.03, rot_y=0.0):
        bpy.ops.mesh.primitive_cube_add(size=1, location=self.v(center))
        obj = bpy.context.object
        obj.scale = (size[0], size[2], size[1])
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        obj.rotation_euler.z = rot_y
        self._finish(obj, name, color)
        if bevel:
            m = obj.modifiers.new("bevel", "BEVEL")
            m.width = min(bevel, min(size) * 0.45)
            m.segments = 2
            m = obj.modifiers.new("wn", "WEIGHTED_NORMAL")
            m.keep_sharp = True
        return obj

    def ellipsoid(self, name, center, size, color, seg=14, rings=9):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings, radius=1, location=self.v(center))
        obj = bpy.context.object
        obj.scale = (size[0] / 2, size[2] / 2, size[1] / 2)
        return self._finish(obj, name, color, True)

    def cylinder(self, name, center, radius, height, color, top=None, seg=24, smooth=True, bevel=0.0):
        bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=radius, radius2=radius if top is None else top,
                                        depth=height, location=self.v(center))
        obj = self._finish(bpy.context.object, name, color, smooth)
        # Cylinder caps must not smooth into the wall, which bends wall normals
        # downwards and makes cream facades render muddy under the daylight key.
        if smooth:
            for face in obj.data.polygons:
                if abs(face.normal.z) > 0.9: face.use_smooth = False
        if bevel:
            m = obj.modifiers.new("bevel", "BEVEL")
            m.width = bevel
            m.segments = 2
            m.limit_method = "ANGLE"
            obj.modifiers.new("wn", "WEIGHTED_NORMAL")
        return obj

    def beam(self, name, a, b, width, color, depth=None):
        va, vb = self.v(a), self.v(b)
        obj = self.box(name, (0, 0, 0), (width, (vb - va).length, depth or width), color, width * 0.2 if width >= 0.04 else 0)
        obj.location = (va + vb) / 2
        obj.rotation_mode = "QUATERNION"
        obj.rotation_quaternion = (vb - va).to_track_quat("Z", "Y")
        return obj

    def mesh(self, name, verts, faces, color, smooth=False, colors=None):
        data = bpy.data.meshes.new(name)
        data.from_pydata([self.v(p) for p in verts], [], faces)
        data.update()
        obj = bpy.data.objects.new(name, data)
        self.current.objects.link(obj)
        data.materials.append(self.mats[color])
        for p in data.polygons:
            p.use_smooth = smooth
        if colors is not None:
            obj["vertex_rgb"] = True
            attr = data.color_attributes.new(name="Paint", type="FLOAT_COLOR", domain="POINT")
            for i, c in enumerate(colors):
                attr.data[i].color = (*c, 1)
        return obj

    def lathe(self, name, profile, color, seg=32, cap=True, center=(0, 0, 0)):
        cx, cy, cz = center
        verts = []
        for r, h in profile:
            for i in range(seg):
                a = i * math.tau / seg
                verts.append((cx + math.cos(a) * r, cy + h, cz + math.sin(a) * r))
        faces = []
        for row in range(len(profile) - 1):
            for i in range(seg):
                a = row * seg + i
                b = row * seg + (i + 1) % seg
                faces.append((a, a + seg, b + seg, b))
        if cap:
            faces.append(tuple(range(seg)))
            faces.append(tuple(reversed([(len(profile) - 1) * seg + i for i in range(seg)])))
        return self.mesh(name, verts, faces, color, True)

    def dome(self, name, center, radius, color, height=None, seg=32, rings=10):
        h = radius if height is None else height
        prof = [(radius * math.cos(t * math.pi / 2), h * math.sin(t * math.pi / 2))
                for t in [i / rings for i in range(rings + 1)]]
        prof[-1] = (0.001, h)
        return self.lathe(name, prof, color, seg, True, center)

    def slab(self, name, outline, y0, y1, color, top_color=None, bevel=0.03):
        """Extruded polygon (outline in x,z) from y0 to y1."""
        # X/Z has the opposite winding to a Y-up face. Normalize so every cap
        # points upward; the old counter-clockwise caps culled the roof/paving.
        outline = list(outline)
        area = sum(a[0]*b[1]-b[0]*a[1] for a,b in zip(outline, outline[1:]+outline[:1]))
        if area > 0:
            outline.reverse()
        n = len(outline)
        verts = [(x, y0, z) for x, z in outline] + [(x, y1, z) for x, z in outline]
        faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
        faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
        obj = self.mesh(name, verts, faces, color)
        if bevel:
            m = obj.modifiers.new("bevel", "BEVEL")
            m.width = bevel
            m.segments = 2
            m.limit_method = "ANGLE"
            obj.modifiers.new("wn", "WEIGHTED_NORMAL")
        if top_color:
            self.slab(name + " top", outline, y1 - 0.002, y1 + 0.004, top_color, bevel=0)
        return obj

    def place_collection(self, name, yaw_deg, offset):
        """Rotate a finished collection about the origin (Godot yaw, +x toward +z for negative yaw) and move it."""
        from mathutils import Matrix
        m = Matrix.Translation(self.v(offset)) @ Matrix.Rotation(math.radians(yaw_deg), 4, "Z")
        for obj in self.assets[name].objects:
            obj.matrix_world = m @ obj.matrix_world

    # -- export ------------------------------------------------------------
    def export(self, name, ao_radius=0.38):
        coll = self.assets[name]
        bpy.ops.object.select_all(action="DESELECT")
        copies = []
        dg = bpy.context.evaluated_depsgraph_get()
        for src in coll.objects:
            data = bpy.data.meshes.new_from_object(src.evaluated_get(dg), depsgraph=dg)
            obj = bpy.data.objects.new(src.name + "_x", data)
            bpy.context.scene.collection.objects.link(obj)
            obj.matrix_world = src.matrix_world.copy()
            obj.select_set(True)
            copies.append(obj)
        bpy.context.view_layer.objects.active = copies[0]
        if len(copies) > 1:
            bpy.ops.object.join()
        obj = bpy.context.object
        obj.name = name
        bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
        data = obj.data
        paint = data.color_attributes.get("Paint")
        tree = None
        if name not in self.no_ao:
            tree = BVHTree.FromPolygons([p.co for p in data.vertices], [list(p.vertices) for p in data.polygons])
        attr = data.color_attributes.new(name="Color", type="FLOAT_COLOR", domain="CORNER")
        data.color_attributes.active_color = attr
        data.color_attributes.render_color_index = data.color_attributes.find("Color")
        cache = {}
        for face in data.polygons:
            base = data.materials[face.material_index].diffuse_color[:3]
            for li in face.loop_indices:
                loop = data.loops[li]
                col = base
                if paint is not None and data.materials[face.material_index].name == "__paint__":
                    col = paint.data[loop.vertex_index].color[:3]
                shade = 1.0
                if tree is not None:
                    key = (loop.vertex_index, tuple(round(n, 2) for n in data.corner_normals[li].vector))
                    if key not in cache:
                        nrm = data.corner_normals[li].vector.normalized()
                        o = data.vertices[loop.vertex_index].co + nrm * 0.008
                        t = nrm.cross(Vector((0, 0, 1)))
                        if t.length < 0.01:
                            t = nrm.cross(Vector((1, 0, 0)))
                        t.normalize()
                        bt = nrm.cross(t)
                        hits = 0.0
                        for r_i in range(8):
                            a = r_i * 2.399
                            r = math.sqrt((r_i + 0.5) / 8) * 0.88
                            d = (nrm * math.sqrt(1 - r * r) + t * (math.cos(a) * r) + bt * (math.sin(a) * r)).normalized()
                            res = tree.ray_cast(o, d, ao_radius)
                            if res[0] is not None:
                                hits += 1 - res[3] / ao_radius
                        cache[key] = 1 - 0.36 * hits / 8
                    shade = cache[key]
                attr.data[li].color = (*(c * shade for c in col), 1)
        data.materials.clear()
        mat = bpy.data.materials.get("Landmark vertex paint")
        if mat is None:
            # The glTF exporter only writes COLOR_0 when a material samples it.
            mat = bpy.data.materials.new("Landmark vertex paint")
            mat.use_nodes = True
            nodes = mat.node_tree.nodes
            sh = nodes.get("Principled BSDF")
            sh.inputs["Roughness"].default_value = 0.9
            vc = nodes.new("ShaderNodeVertexColor")
            vc.layer_name = "Color"
            mat.node_tree.links.new(vc.outputs["Color"], sh.inputs["Base Color"])
        data.materials.append(mat)
        for f in data.polygons:
            f.material_index = 0
        if paint is not None:
            data.color_attributes.remove(paint)
        bpy.ops.export_scene.gltf(filepath=str(self.out / (name + ".glb")), export_format="GLB", use_selection=True,
                                  export_yup=True, export_materials="EXPORT", export_attributes=False, export_vertex_color="ACTIVE",
                                  export_cameras=False, export_lights=False, export_animations=False)
        data.calc_loop_triangles()
        tris = len(data.loop_triangles)
        bpy.data.objects.remove(obj, do_unlink=True)
        return {"triangles": tris, "bytes": (self.out / (name + ".glb")).stat().st_size}
