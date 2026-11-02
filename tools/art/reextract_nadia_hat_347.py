#!/usr/bin/env python3
"""Re-extract only Nadia's hat using --append, then preserve the original manifest text/order."""
import argparse
import json
import re
from pathlib import Path
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--runtime-root', type=Path, required=True)
args = parser.parse_args()
root = args.runtime_root.resolve()
path = root / 'assets/avatar/parts_manifest.json'
original_text = path.read_text()
original = json.loads(original_text)
target = 'hairhat41_npc_nadia_baker'
scene_path = root / ('assets/avatar/parts/' + target + '_scene.tscn')
original_scene = subprocess.check_output(
    ['git', 'show', 'HEAD:' + str(scene_path.relative_to(root))], cwd=root, text=True)
assert sum(p['id'] == target for p in original['parts']) == 1
reduced = {**original, 'parts': [p for p in original['parts'] if p['id'] != target]}
recipes = json.loads((root / 'assets/avatar/source/recipes_batch3.json').read_text())
have = {p['id'] for p in reduced['parts']}
assert [p['id'] for p in recipes['parts'] if p['id'] not in have] == [target]
try:
    path.write_text(json.dumps(reduced, indent='\t') + '\n')
    subprocess.run(['godot', '--headless', '--path', str(root),
                    '--script', 'res://tools/pipeline/extract_parts.gd', '--',
                    'res://assets/avatar/source/recipes_batch3.json', '--append'], cwd=root, check=True)
    extracted = json.loads(path.read_text())
    assert len(extracted['parts']) == len(original['parts'])
    assert {p['id']: p for p in extracted['parts']} == {p['id']: p for p in original['parts']}
    # Godot 4.7 assigns fresh scene-local node IDs when packing a new scene.
    # Keep the exact original node headers while retaining the new mesh data.
    old_headers = [line for line in original_scene.splitlines(keepends=True) if line.startswith('[node ')]
    new_scene = scene_path.read_text()
    new_headers = [line for line in new_scene.splitlines(keepends=True) if line.startswith('[node ')]
    strip_id = lambda line: re.sub(r' unique_id=\d+', '', line)
    assert [strip_id(s) for s in old_headers] == [strip_id(s) for s in new_headers]
    headers = dict(zip(new_headers, old_headers))
    scene_path.write_text(''.join(headers.get(line, line) for line in new_scene.splitlines(keepends=True)))
finally:
    path.write_text(original_text)
assert path.read_text() == original_text
print('NADIA_HAT_REEXTRACTED; manifest entries and original text/order exact')
