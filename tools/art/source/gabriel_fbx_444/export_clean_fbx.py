"""Re-export Gabriel's source FBX without unused full-body material/image objects.

Keep FBX 7500 property payloads byte-for-byte, including compressed arrays. This
avoids a Blender import/export round trip changing skin, UV or transform values.
Only object removal, its connections, definition counts and container framing change.
"""
from dataclasses import dataclass, field
from pathlib import Path
import argparse
import hashlib
import json
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[4]
REL = 'assets/avatar/source/shoes3_npc_gabriel/SK_dt_skin03.fbx'
SOURCE_REF = '6151fef82a16e822367ee076dacc5eef85c19002'
SOURCE_SHA = 'fc8ea72a89c6f0d9b53842c066963af64fd0a3c617c3ed43f5c282ca596c5310'
MISSING = ('T_skin02_body_D.png', 'T_skin02_eyes_D.png',
           'T_skin03_cloth_D.png', 'T_skin03_hair_D.png')
NULL = bytes(25)

@dataclass
class Element:
    name: bytes
    count: int
    raw_props: bytes
    children: list = field(default_factory=list)
    terminated: bool = False

    def values(self):
        result, pos = [], 0
        for _ in range(self.count):
            kind = chr(self.raw_props[pos]); pos += 1
            if kind in 'SR':
                length = struct.unpack_from('<I', self.raw_props, pos)[0]; pos += 4
                value = self.raw_props[pos:pos+length]; pos += length
            elif kind in 'CYIFDL':
                fmt = {'C':'?', 'Y':'h', 'I':'i', 'F':'f', 'D':'d', 'L':'q'}[kind]
                value = struct.unpack_from('<'+fmt, self.raw_props, pos)[0]
                pos += struct.calcsize(fmt)
            else:
                assert kind in 'fdilbc', kind
                length, encoding, size = struct.unpack_from('<III', self.raw_props, pos)
                pos += 12
                value = (kind, length, encoding, self.raw_props[pos:pos+size]); pos += size
            result.append(value)
        assert pos == len(self.raw_props)
        return result

    def fingerprint(self):
        # End offsets are framing, not scene data. Everything else is compared.
        return (self.name, self.count, self.raw_props, self.terminated,
                tuple(c.fingerprint() for c in self.children))

    def serialize(self, start):
        payload = self.name + self.raw_props
        for child in self.children:
            payload += child.serialize(start + 25 + len(payload))
        if self.terminated: payload += NULL
        return struct.pack('<QQQB', start+25+len(payload), self.count,
                           len(self.raw_props), len(self.name)) + payload


def parse(raw):
    assert raw[:23] == b'Kaydara FBX Binary  \x00\x1a\x00'
    assert struct.unpack_from('<I', raw, 23)[0] == 7500
    def read(pos):
        end, count, plen, nlen = struct.unpack_from('<QQQB', raw, pos)
        if not end:
            assert raw[pos:pos+25] == NULL
            return None, pos+25
        pos += 25
        name = raw[pos:pos+nlen]; pos += nlen
        elem = Element(name, count, raw[pos:pos+plen]); pos += plen
        while pos < end:
            child, pos = read(pos)
            if child is None:
                elem.terminated = True
                assert pos == end
            else: elem.children.append(child)
        assert pos == end
        return elem, end
    roots, pos = [], 27
    while True:
        elem, pos = read(pos)
        if elem is None: break
        roots.append(elem)
    return roots, raw[pos:]


def one(elements, name):
    return next(e for e in elements if e.name == name)


def set_count(elem, value):
    assert elem.count == 1 and elem.raw_props[:1] == b'I'
    elem.raw_props = b'I' + struct.pack('<i', value)


def append_footer(prefix, footer, end_alignment):
    # Keep the original timestamp-related magic/version/tail, adjusting only
    # zero padding to retain the source exporter's file alignment convention.
    version_at = len(footer)-140
    assert footer[version_at:version_at+4] == struct.pack('<I', 7500)
    assert footer[20:version_at] == bytes(version_at-20)
    fixed = footer[:20]
    tail = footer[version_at:]
    pad = (end_alignment-len(prefix)-len(fixed)-len(tail)) % 16 or 16
    return prefix + fixed + bytes(pad) + tail


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--source-ref', default=SOURCE_REF)
    p.add_argument('--output', default=REL)
    p.add_argument('--audit', default='output/gabriel-fbx-444/source-audit.json')
    args = p.parse_args()
    raw = subprocess.check_output(['git', 'show', args.source_ref+':'+REL], cwd=ROOT)
    assert hashlib.sha256(raw).hexdigest() == SOURCE_SHA, 'Unexpected source; review before exporting'
    roots, footer = parse(raw)
    # Prove that this writer itself does not change any unedited file byte.
    roundtrip = raw[:27]
    for e in roots: roundtrip += e.serialize(len(roundtrip))
    assert append_footer(roundtrip + NULL, footer, len(raw)%16) == raw
    originals = {e.name:e.fingerprint() for e in roots}
    objects = one(roots, b'Objects')
    before = {e.values()[0]: e for e in objects.children}
    fingerprints = {uid:e.fingerprint() for uid,e in before.items()}
    removed = {}
    for uid, e in before.items():
        vals = e.values()
        if e.name == b'Material' and vals[1].split(b'\x00')[0] in (
                b'eyes_mat', b'body_mat', b'cloth_mat', b'hairHat_mat'):
            removed[uid] = e
        if e.name in (b'Texture', b'Video'):
            filenames = [c.values()[0] for c in e.children
                         if c.name in (b'Filename', b'FileName', b'RelativeFilename')]
            if any(n.encode() in filename for n in MISSING for filename in filenames):
                removed[uid] = e
    assert len(removed) == 12
    assert {t:sum(e.name==t for e in removed.values()) for t in
            (b'Material', b'Texture', b'Video')} == {b'Material':4,b'Texture':4,b'Video':4}
    connections = one(roots, b'Connections')
    old_connections = list(connections.children)
    connections.children = [e for e in old_connections
                            if not (set(e.values()[1:3]) & removed.keys())]
    objects.children = [e for uid,e in before.items() if uid not in removed]
    materials = [e for e in objects.children if e.name == b'Material']
    assert len(materials) == 1 and materials[0].values()[1] == b'shoes_mat\x00\x01Material'
    definitions = one(roots, b'Definitions')
    set_count(one(definitions.children, b'Count'), len(objects.children))
    for e in definitions.children:
        if e.name == b'ObjectType' and e.values()[0] in (b'Material',b'Texture',b'Video'):
            set_count(one(e.children, b'Count'), 1)
    result = raw[:27]
    for e in roots: result += e.serialize(len(result))
    result = append_footer(result + NULL, footer, len(raw)%16)
    assert all(n.encode() not in result for n in MISSING)
    assert b'T_skin03_shoes_D.png' in result
    after_roots, after_footer = parse(result)
    after = {e.values()[0]:e for e in one(after_roots,b'Objects').children}
    assert set(after) == set(before)-set(removed)
    assert all(after[uid].fingerprint() == fingerprints[uid] for uid in after)
    assert after_footer[:20] == footer[:20] and after_footer[-140:] == footer[-140:]
    assert len(result)%16 == len(raw)%16
    for e in after_roots:
        if e.name not in (b'Definitions',b'Objects',b'Connections'):
            assert e.fingerprint() == originals[e.name]
    assert [e.fingerprint() for e in one(after_roots,b'Connections').children] == [
        e.fingerprint() for e in old_connections if not (set(e.values()[1:3]) & removed.keys())]
    dst = ROOT/args.output
    dst.parent.mkdir(parents=True, exist_ok=True); dst.write_bytes(result)
    records = [{'type':e.name.decode(), 'id':uid,
                'name':e.values()[1].split(b'\x00')[0].decode()} for uid,e in removed.items()]
    report = {
        'source_ref': args.source_ref, 'source_sha256': SOURCE_SHA,
        'output_sha256': hashlib.sha256(result).hexdigest(),
        'source_bytes':len(raw), 'output_bytes':len(result),
        'method':'FBX 7500 source-document re-export; retained property payloads byte-identical',
        'unedited_roundtrip_byte_identical':True,
        'removed_objects':records,
        'removed_connections':len(old_connections)-len(connections.children),
        'retained_objects':len(after), 'retained_object_payloads_byte_identical':True,
        'preserved_object_counts':{t:sum(e.name.decode()==t for e in after.values()) for t in
            ['Geometry','Model','NodeAttribute','Deformer','Pose','AnimationStack','AnimationLayer','AnimationCurveNode']},
        'remaining_materials':['shoes_mat'], 'remaining_image':'T_skin03_shoes_D.png',
        'shoe_material_slot_name_unchanged':True,
        'all_geometry_skin_weights_uv_transforms_animations_byte_identical':True,
        'other_root_payloads_and_footer_metadata_unchanged':True,
        'footer_alignment_padding_recomputed':True,
    }
    audit=ROOT/args.audit; audit.parent.mkdir(parents=True,exist_ok=True)
    audit.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['source_bytes','output_bytes','removed_connections','retained_objects','output_sha256']}))

if __name__ == '__main__': main()
