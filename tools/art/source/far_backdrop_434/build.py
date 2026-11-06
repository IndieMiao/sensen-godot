"""Reuse Huang Zhong's editable XY cards, retaining named local-pivot parts.

No original Alcatraz file is written. RGB vertex data in the new GLBs are
linear palette weights (not baked final colour); a single shared shader shades them.
"""
from pathlib import Path
import hashlib, json, math
import bpy, bmesh

SRC = Path(__file__).resolve().parent
ROOT = SRC.parents[3]
KIT = ROOT / 'assets/landmarks/_shared/far_backdrop'
ORIGINAL = ROOT / 'tools/art/source/alcatraz_far_424'
WEIGHTS = {
    'bridge': (1, 0, 0), 'bridge_light': (0, 1, 0), 'bridge_shade': (0, 0, 1),
    'city': (.78, .22, 0), 'city_light': (1, 0, 0), 'city_blue': (0, 1, 0),
    'city_mid': (.45, .35, .20), 'city_shadow': (0, 0, 1),
    'hills': (1, 0, 0), 'hills_light': (0, 1, 0), 'hill_shadow': (0, 0, 1),
}

def build(name, source, variant=''):
    path = ORIGINAL / (source + '.blend')
    bpy.ops.wm.open_mainfile(filepath=str(path))
    bpy.context.preferences.filepaths.save_version = 0
    scene = bpy.context.scene
    waterfront = sorted([o for o in scene.objects if o.type == "MESH" and o.name.startswith("Distant waterfront block")], key=lambda o: min(v.co.x for v in o.data.vertices))
    sparse = {o.name for i,o in enumerate(waterfront) if i%4 in (0,1) or i==len(waterfront)-1}
    for obj in list(scene.objects):
        if obj.type != 'MESH':
            if obj.type == 'EMPTY':
                obj.name = name + ' / bottom centre'
                obj['author'] = '刘备'; obj['task'] = 'SGODOT-434'
            continue
        keep = len(obj.data.polygons) > 0
        if variant == 'medium':
            keep = keep and not obj.name.startswith(('Salesforce', 'Transamerica'))
        elif variant == 'low':
            keep = keep and obj.name in sparse
        if not keep:
            bpy.data.objects.remove(obj, do_unlink=True)
            continue
        if variant == 'low':
            for v in obj.data.vertices: v.co.z *= .82
        if variant == 'hills_b':
            for v in obj.data.vertices:
                x = -v.co.x
                v.co.x = x
                v.co.z *= .78 + .23*math.cos(x*.61+.45) + .10*math.sin(x*1.1)
        obj['palette_weights'] = 'RGB sum=1; primary / accent / shadow, alpha=1'
    parts = [o for o in scene.objects if o.type == 'MESH']
    if variant == 'hills_b':
        high = max(v.co.z for o in parts for v in o.data.vertices)
        for o in parts:
            for v in o.data.vertices: v.co.z *= .52/high
    bpy.context.view_layer.update()
    bpy.ops.wm.save_as_mainfile(filepath=str(SRC/(name+'.blend')))
    deps = bpy.context.evaluated_depsgraph_get()
    flat = bpy.data.materials.new('Far backdrop / palette weights')
    flat.use_nodes = True; flat.use_backface_culling = False
    q = flat.node_tree.nodes['Principled BSDF']
    q.inputs['Roughness'].default_value = 1
    vc = flat.node_tree.nodes.new('ShaderNodeVertexColor'); vc.layer_name = 'Color'
    flat.node_tree.links.new(vc.outputs['Color'], q.inputs['Base Color'])
    export = bpy.data.scenes.new('Export / single surface')
    copies = []
    for obj in parts:
        mesh = bpy.data.meshes.new_from_object(obj.evaluated_get(deps))
        mesh.transform(obj.matrix_world)
        for old in list(mesh.color_attributes): mesh.color_attributes.remove(old)
        color = mesh.color_attributes.new(name='Color', type='FLOAT_COLOR', domain='CORNER')
        for face in mesh.polygons:
            role = mesh.materials[face.material_index].name.split('.')[0]
            weight = WEIGHTS[role]
            for i in face.loop_indices: color.data[i].color = (*weight, 1)
        mesh.materials.clear(); mesh.materials.append(flat)
        for face in mesh.polygons: face.material_index = 0
        mesh.color_attributes.active_color = color; mesh.color_attributes.render_color_index = 0
        node = bpy.data.objects.new('Export part', mesh); export.collection.objects.link(node); copies.append(node)
    bpy.context.window.scene = export
    for node in copies: node.select_set(True)
    bpy.context.view_layer.objects.active = copies[0]
    bpy.ops.object.join(); node = bpy.context.object; node.name = name; node.data.name = name+'_mobile'
    bm = bmesh.new(); bm.from_mesh(node.data)
    bmesh.ops.triangulate(bm, faces=list(bm.faces)); bm.to_mesh(node.data); bm.free()
    node.data.calc_loop_triangles()
    target = KIT/(name+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(target), export_format='GLB', use_selection=True,
        use_active_scene=True, export_yup=True, export_materials='EXPORT',
        export_vertex_color='ACTIVE', export_all_vertex_colors=False, export_normals=True,
        export_texcoords=False, export_animations=False, export_cameras=False, export_lights=False)
    points = [(v.co.x, v.co.z, -v.co.y) for v in node.data.vertices]
    lo = [min(p[i] for p in points) for i in range(3)]
    hi = [max(p[i] for p in points) for i in range(3)]
    result = {'file':target.name, 'triangles':len(node.data.loop_triangles), 'surfaces':1,
              'bounds':[lo,hi], 'dimensions_m':[hi[i]-lo[i] for i in range(3)],
              'source_parts':len(parts), 'source':str((SRC/(name+'.blend')).relative_to(ROOT)),
              'derived_from':source, 'variant':variant or 'original silhouette',
              'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
    print('FAR_CARD', name, result['triangles'], result['dimensions_m'], flush=True)
    bpy.context.window.scene = scene
    return result

KIT.mkdir(parents=True, exist_ok=True)
provenance = json.loads((SRC/'reference/provenance.json').read_text())
for name, digest in provenance['source_hashes'].items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest, 'Source drift: '+name
assets = {}
for name, source, variant in [('far_city_high','alc_far_city',''),
                             ('far_city_medium','alc_far_city','medium'),
                             ('far_city_low','alc_far_city','low'),
                             ('far_hills_a','alc_far_hills',''),
                             ('far_hills_b','alc_far_hills','hills_b'),
                             ('far_bridge','alc_far_bridge','')]:
    assets[name] = build(name,source,variant)
manifest = {'task':'SGODOT-434','author':'刘备','units':'metres; Y up; XY card / front +Z / bottom-centre pivot',
            'vertex_color':'linear RGB palette weights, sum 1; alpha 1',
            'assets':assets,'unique_triangles':sum(a['triangles'] for a in assets.values()),
            'baseline':provenance['baseline'],
            'recommended_combinations':{'urban_bay':['far_bridge','far_city_high','far_hills_a'],
                                        'quiet_bay':['far_city_medium','far_city_low','far_hills_b']}}
(KIT/'manifest.json').write_text(json.dumps(manifest,indent=2,ensure_ascii=False)+'\n')
