"""Preserve the accepted collaborator GLBs while rebuilding the island assembly."""
import hashlib
import json
import bpy


def load_catalog(folder):
    manifest = folder / 'alc_far_manifest.json'
    if not manifest.exists():
        return {}
    rows = json.loads(manifest.read_text())['assets']
    for name, row in rows.items():
        data = (folder / row['file']).read_bytes()
        assert hashlib.sha256(data).hexdigest() == row['sha256'], name
    return rows


def replace_preview_modules(kit, folder, rows):
    # Named construction parts remain in the collaborator's linked source files;
    # the island blend contains imported module previews with identical pivots.
    for name in rows:
        old = kit.assets.pop(name)
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.collections.remove(old)
        kit.begin(name, ao=False)
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(folder / rows[name]['file']))
        for obj in set(bpy.data.objects) - before:
            for collection in list(obj.users_collection):
                collection.objects.unlink(obj)
            kit.current.objects.link(obj)
        assert len(kit.current.objects) > 0, name


def manifest_row(folder, row):
    return {'triangles': row['triangles'], 'bytes': (folder / row['file']).stat().st_size,
            'author': '黄忠', 'source': row['source'], 'sha256': row['sha256']}
