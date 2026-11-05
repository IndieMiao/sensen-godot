#!/usr/bin/env python3
"""Clear obsolete texture filenames in C40's geometry-only FBX sources.

The part extractor assigns the textures from recipes_batch3.json. Keep FBX
objects, materials, connections and compressed mesh/skin/animation arrays;
only clear filename strings, rewriting the binary node offsets they affect.
Default is a dry run. Reapplying --write is a byte-preserving no-op.
"""
import argparse
from dataclasses import dataclass
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[2]
PARTS = ('cloth1_1_npc_nadia', 'cloth1_1_npc_rafa', 'cloth1_npc_lou')
HEADER = b'Kaydara FBX Binary  \x00\x1a\x00'
NODE = struct.Struct('<QQQB')  # FBX 7500, 64-bit offsets.
SCALARS = {'Y': 2, 'C': 1, 'B': 1, 'I': 4, 'F': 4, 'D': 8, 'L': 8}
OLD_TEXTURES = {f'T_skin01_{part}_D.png'.encode() for part in ('glasses', 'eyes', 'bag', 'shoes', 'cloth', 'body', 'hair')}


@dataclass
class Element:
    name: bytes
    props: list[bytes]
    children: list['Element']
    terminated: bool


def read_element(data, start):
    end, count, size, name_len = NODE.unpack_from(data, start)
    if end == 0:
        assert data[start:start + NODE.size] == bytes(NODE.size)
        return None, start + NODE.size
    assert start < end <= len(data)
    name_at = start + NODE.size
    pos = name_at + name_len
    props_end = pos + size
    props = []
    for _ in range(count):
        begin = pos
        kind = chr(data[pos]); pos += 1
        if kind in SCALARS:
            pos += SCALARS[kind]
        elif kind in 'SR':
            length, = struct.unpack_from('<I', data, pos)
            pos += 4 + length
        elif kind in 'fdlibc':
            _, _, length = struct.unpack_from('<III', data, pos)
            pos += 12 + length  # Preserve compressed data verbatim.
        else:
            raise ValueError(f'Unsupported FBX property {kind!r}')
        assert pos <= props_end <= end
        props.append(data[begin:pos])
    assert pos == props_end
    children, terminated = [], False
    while pos < end:
        child, pos = read_element(data, pos)
        if child is None:
            terminated = True
            break
        children.append(child)
    assert pos == end
    return Element(data[name_at:name_at + name_len], props, children, terminated), end


def parse(data):
    assert data[:23] == HEADER and struct.unpack_from('<I', data, 23)[0] == 7500
    elements, pos = [], 27
    while True:
        child, next_pos = read_element(data, pos)
        if child is None:
            return elements, data[pos:]  # Top-level terminator and original footer.
        elements.append(child)
        pos = next_pos


def encode_element(element, start):
    props = b''.join(element.props)
    pos = start + NODE.size + len(element.name) + len(props)
    children = []
    for child in element.children:
        encoded = encode_element(child, pos)
        children.append(encoded)
        pos += len(encoded)
    if element.terminated:
        children.append(bytes(NODE.size))
        pos += NODE.size
    return NODE.pack(pos, len(element.props), len(props), len(element.name)) + element.name + props + b''.join(children)


def clear_paths(element, active=False):
    active = active or element.name in (b'Texture', b'Video')
    cleared = 0
    if active:
        indexes = []
        if element.name in (b'FileName', b'Filename', b'RelativeFilename'):
            indexes = range(len(element.props))
        elif element.name == b'P' and element.props and element.props[0][0:1] == b'S':
            if element.props[0][5:] in (b'Path', b'RelPath'):
                indexes = range(4, len(element.props))
        for i in indexes:
            prop = element.props[i]
            if prop[:1] == b'S' and len(prop) > 5:
                filename = prop[5:].replace(b'\\', b'/').rsplit(b'/', 1)[-1]
                if filename not in OLD_TEXTURES:
                    raise ValueError(f'Refusing to clear an unrecognized texture: {filename!r}')
                element.props[i] = b'S\x00\x00\x00\x00'
                cleared += 1
    return cleared + sum(clear_paths(child, active) for child in element.children)


def clean(data):
    elements, footer = parse(data)
    # Before any mutation, prove the codec is byte-exact for this input.
    def encode():
        chunks, pos = [data[:27]], 27
        for element in elements:
            chunk = encode_element(element, pos)
            chunks.append(chunk); pos += len(chunk)
        return b''.join(chunks) + footer
    assert encode() == data
    count = sum(clear_paths(element) for element in elements)
    result = encode()
    # Round-trip proves every property/array except the cleared strings survived.
    assert parse(result) == (elements, footer)
    return result, count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    for part in PARTS:
        path = ROOT / 'assets/avatar/source' / part / 'SK_dt_skin01.fbx'
        before = path.read_bytes()
        after, count = clean(before)
        assert clean(after) == (after, 0), 'cleanup must be idempotent'
        if args.write and count:
            path.write_bytes(after)
        print(f'{part}: {count} obsolete filename strings; {len(before)} -> {len(after)} bytes')


if __name__ == '__main__':
    main()
