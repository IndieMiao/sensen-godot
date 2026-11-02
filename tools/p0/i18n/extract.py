#!/usr/bin/env python3
"""P0 中文版 (0.2.21): every English line P0 may show, for the translators.

Scans P0's GDScript (modules/p0, scenes/p0, scenes/ui_kit, modules/ui, scenes/map, modules/map) for string literals
that read as copy, and the content tables (assets/p0/*.json, assets/p0/content/*.json) for their text fields. Writes
tools/p0/i18n/p0_strings_en.json: {source: {"where": [file:line, ...], "kind": "line" | "template"}}, sorted.
A literal ending in ` · ` (a line built by `+`) is kept without it: Localization.P0Translation translates by ` · `
parts. Lines already in assets/localization/p0_zh_CN.json are marked "done". Run from the repo root.
"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
DIRS = ['modules/p0', 'scenes/p0', 'scenes/ui_kit', 'modules/ui', 'scenes/map', 'modules/map']
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
SKIP_LINE = re.compile(r'^\s*(#|class_name|extends|const [A-Z_]+ := preload|signal |@export)')
NOT_COPY = re.compile(r'res://|user://|\.(png|svg|glb|tscn|tres|gd|json|ogg|wav)$|^[A-Za-z_]+[:/][A-Za-z_]|^[a-z_0-9]+$|^%[a-z]$|^#')
TEXT_KEYS = re.compile(r'^(name|title|text|line|lines|pip|blurb|word|desc|description|subtitle|label|note|hint|greeting|'
                       r'toast|caption|short|body|message|reason|tip|seed_name|category|badge|a|b)$')

def copy_like(t: str) -> bool:
    if len(t) < 2 or NOT_COPY.search(t): return False
    if not re.search(r'[A-Za-z]{2}', t): return False
    if re.fullmatch(r'[A-Z][a-zA-Z0-9]*', t) and not re.search(r'[aeiou]', t[1:]): return False
    if re.fullmatch(r'[A-Z][a-z]+(?:[A-Z][a-z0-9]+)+', t): return False   # NodeNames / CamelCase
    return t[0].isupper() or t[0] in '%·+-–' or ' ' in t

def norm(t: str) -> str:
    t = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), t)   # GDScript's \u2060 and the like, as shown
    t = t.replace('\\n', '\n').replace('\\"', '"')
    return re.sub(r'\s*·\s*$', '', re.sub(r'^\s*·\s*', '', t)).strip()

def main() -> None:
    out: dict = {}
    def add(src: str, where: str) -> None:
        src = norm(src)
        if not src or not copy_like(src): return
        e = out.setdefault(src, {"where": [], "kind": "template" if re.search(r'%[+-]?\d*(?:\.\d+)?[dsf]', src.replace('%%', '')) else "line"})
        if len(e["where"]) < 5: e["where"].append(where)
    files = subprocess.run(['git', 'ls-files', *DIRS], capture_output=True, text=True, cwd=ROOT).stdout.split()
    for f in files:
        if not f.endswith('.gd') or re.search(r'gallery|/dev/|_probe', f): continue   # dev pages no player sees
        for n, line in enumerate((ROOT / f).read_text(encoding='utf-8').splitlines(), 1):
            if SKIP_LINE.match(line): continue
            code = line.split(' # ')[0] if ' # ' in line else line
            for m in LIT.finditer(code):
                before = code[:m.start()].rstrip()
                if before.endswith(('find_child(', '.name =', 'has_method(', 'call(', 'emit(', 'get(', 'has(', 'connect(', '==', 'in [')):
                    continue
                add(m.group(1), f'{f}:{n}')
    content = sorted((ROOT / 'assets/p0').glob('*.json')) + sorted((ROOT / 'assets/p0/content').glob('*.json'))
    for p in content:
        if p.name in ('city_clusters.json',): continue   # place names stay English in 0.2.21
        try: data = json.loads(p.read_text(encoding='utf-8'))
        except Exception: continue
        def walk(x, k=None):
            if isinstance(x, dict):
                for kk, v in x.items():
                    if not kk.startswith('_'): walk(v, kk)
            elif isinstance(x, list):
                for v in x: walk(v, k)
            elif isinstance(x, str) and k and TEXT_KEYS.match(k):
                add(x, f'{p.relative_to(ROOT)}#{k}')
        walk(data)
    table = ROOT / 'assets/localization/p0_zh_CN.json'
    done = json.loads(table.read_text(encoding='utf-8')) if table.exists() else {}
    for src, e in out.items():
        if src in done: e["done"] = True
    dest = ROOT / 'tools/p0/i18n/p0_strings_en.json'
    dest.write_text(json.dumps(dict(sorted(out.items())), ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    kinds = {k: sum(1 for e in out.values() if e["kind"] == k) for k in ("line", "template")}
    print(f'{len(out)} lines ({kinds["line"]} lines, {kinds["template"]} templates), {sum(1 for e in out.values() if e.get("done"))} done → {dest.relative_to(ROOT)}')

if __name__ == '__main__':
    sys.exit(main())
