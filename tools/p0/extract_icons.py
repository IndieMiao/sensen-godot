"""Pull <symbol> icons out of the design-kit sprites into standalone SVGs for the Godot P0 client.

usage: python3 tools/p0/extract_icons.py symbol_id[:out_name] ...
Sprites: docs/design/ui-anchors-2026-10-03/ui/icons*.svg; output: assets/p0/icons/<out_name>.svg
"""
import glob, re, sys

SPRITES = sorted(glob.glob('docs/design/ui-anchors-2026-10-03/ui/icons*.svg'))
symbols = {}
for path in SPRITES:
    text = open(path, encoding='utf-8').read()
    for m in re.finditer(r'<symbol\s+id="([^"]+)"([^>]*)>(.*?)</symbol>', text, re.S):
        symbols.setdefault(m.group(1), (m.group(2), m.group(3)))

for arg in sys.argv[1:]:
    sid, _, out = arg.partition(':')
    if sid not in symbols:
        print('missing', sid); continue
    attrs, body = symbols[sid]
    vb = re.search(r'viewBox="([^"]+)"', attrs)
    view = vb.group(1) if vb else '0 0 64 64'
    name = out or sid.removeprefix('i-').replace('-', '_')
    with open(f'assets/p0/icons/{name}.svg', 'w', encoding='utf-8') as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view}" width="128" height="128">{body}</svg>\n')
    print('wrote', name)
