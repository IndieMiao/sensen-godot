#!/usr/bin/env python3
"""P0 中文版 (0.2.21): every English line P0 may show, for the translators.

Scans P0's GDScript (modules/p0, scenes/p0, scenes/ui_kit, modules/ui, scenes/map, modules/map) for string literals
that read as copy, the copy rules beside it (modules/p0/item_info_rules.json: labels and facts), and the content tables
(assets/p0/*.json, assets/p0/content/*.json) for their text fields. Writes tools/p0/i18n/p0_strings_en.json:
{source: {"where": [file:line, ...], "kind": "line" | "template"}}, sorted. A literal ending in ` · ` (a line built by
`+`) is kept without it: Localization.P0Translation translates by ` · ` parts. Lines already in
assets/localization/p0_zh_CN.json are marked "done". Run from the repo root.

What reads as copy (SGODOT-385, 亚瑟's first-round shots 385 7d6077a4: names, jobs, stages and lines were missing):
- code: a literal that looks like a sentence or a Title; a template whose words are few (`%s's %s`, `%d s`); a short
  word in a UI place (a constructor's first argument, a `unit` / `title` / … value, so `ponds`, `XP`); the words a
  constant list shows capitalized (CAPITALIZED: the Gear slots' `Ring`, `Charm`). Never node names, debug output,
  shader source or keys (李白's skip list, p0_zh_CN.notes.md §2).
- content: the text keys (TEXT_KEYS) and everything under a text dict (TEXT_DICTS: a resident's `lines` by stage, the
  tools' `names` by id). Place-name pools stay English (city_clusters, pond / tea / keeper / terrain words,
  landmarks, country names), and world_gen's overrides are notes.

Cities (#649 第二批 ④, 口径「城市用通行中文名」): only the open home cities and each one's fallback ten (about 140, as the
server's homeCities / fallbackOf reach them: server/tools/i18n_city_names.ts) go to their own list,
tools/p0/i18n/p0_cities_en.json {name: {"ids", "country", "homes", "done"?, "also_line"?}}, and the states / provinces the
Nearby rows write after them to p0_admins_en.json {admin: {"cities", "done"?}} (0.2.23), for 李白; their Chinese goes in
the main table like any line. `also_line`: the name is also a line in the code (San Francisco): one key for both, so a city named like a word would read it.
"""
import json, re, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
## The fishing panel and the pond scene P0 opens are older code outside the P0 folders (scenes/fishing, modules/fishing,
## modules/ponds; 奕星 11-11). Other folders P0 reaches (the farm, inventory, net, place, account …) are the older app's
## screens P0 does not show: scanning them lists over 1,200 lines no player sees.
DIRS = ['modules/p0', 'scenes/p0', 'scenes/ui_kit', 'modules/ui', 'scenes/map', 'modules/map',
        'scenes/fishing', 'modules/fishing', 'modules/ponds']
LIT = re.compile(r'"((?:[^"\\]|\\.)*)"')
## … and the months (P0Logic.MONTHS): English date parts, never words of the table — under 中文 a date is written whole
## (P0Logic.month_day), and a bare `Jun` there read a keeper the world names Jun as 「6 月」 (SGODOT-492).
SKIP_LINE = re.compile(r'^\s*(#|class_name|extends|const [A-Z_]+ := preload|signal |@export|const MONTHS\b)')
NOT_COPY = re.compile(r'res://|user://|\.(png|svg|glb|tscn|tres|gd|json|ogg|wav)$|^[A-Za-z_]+[:/][A-Za-z_]|^[a-z_0-9]+$|^%[a-z]$|^#|^[A-Z][A-Z0-9]*(_[A-Z0-9]+)+$')   # … an error code (FISHING_TIMING)
SPEC = re.compile(r'%[+-]?\d*(?:\.\d+)?[dsf]')
## A template that is a key, a path, a header or a cache key, not a line (`%s:regional:%s:1`, `%s%s_%d.webp`,
## `x-p0-version: %d`, `%.1f|%d|…`, `%s?longitude=…`, `P0_AIM %d %s`).
TEMPLATE_JUNK = re.compile(r'[|={}\\_<>]|\?[a-z]+=|:[A-Za-z%]|^[a-z]+-[a-z0-9]|^[a-z]+%|\bP0[A-Za-z]*\b|^[A-Z0-9_]{3,}\b|https?:|\.[a-z]{3,4}\b')
## Where a short word is still copy: a constructor's first argument (`UiNeedTile.new("XP", …)`), a toast or a label,
## a UI value (`title = "All"`); a lower-case one only as a count's unit (`"unit": "ponds"`).
UI_PLACE = re.compile(r'(\.new\(|\btoast\(|\blabel\(|\.primary =|["\b](unit|title|effect|text|label|caption|line|fact|subtitle|hint|reason)"?\s*[:=])$')
UNIT_PLACE = re.compile(r'"unit"\s*:$')
HEX = re.compile(r'[0-9A-Fa-f]{6}(?:[0-9A-Fa-f]{2})?')
## Constant lists of keys a panel shows capitalized (String.capitalize): file → constant names.
CAPITALIZED = {'scenes/p0/panels/p0_bag_drawer.gd': ['GEAR_SLOTS']}

TEXT_KEYS = re.compile(r'^(name|title|text|line|lines|pip|blurb|word|desc|description|subtitle|label|note|hint|greeting|'
                       r'toast|caption|short|body|message|reason|tip|seed_name|category|badge|a|b|'
                       # SGODOT-385 round 2: a resident's job and favourite, stage names, dish styles, climate bands,
                       # plurals and plant names, request lines, the farm's name, guide marks, facts
                       r'role|likes|style|stage|stages|gift_meal_stage|mystery_line|plural|plant_name|need_line|thanks|'
                       r'postcard|where|scope|source|farm_name|climate|zone|zones|card_zone|card_zones|why|facts|unit)$')
TEXT_DICTS = re.compile(r'^(lines|names)$')   # every string below is copy, whatever its key (a stage, an item id)
## Content keys never walked: place-name pools stay English in 0.2.21 (李白 makes the country table apart), and notes.
SKIP_KEYS = re.compile(r'^(overrides|words|keeper_names|tea_words|terrain_words|landmarks|country_names|backdrop)$')
CODE_JSON = {'modules/p0/item_info_rules.json': re.compile(r'^(label|facts|fact_note|card_note)$')}

def copy_like(t: str, place: bool = False, unit: bool = False) -> bool:
    if len(t) < 2 or HEX.fullmatch(t) or NOT_COPY.search(t) and not (unit and re.fullmatch(r'[a-z]+', t)): return False
    if SPEC.search(t.replace('%%', '')):   # a template: a word around its specs is enough (`%s's %s`, `%d s`)
        return bool(re.search(r'[A-Za-z]', SPEC.sub('', t))) and not TEMPLATE_JUNK.search(t)
    if not re.search(r'[A-Za-z]{2}', t): return False
    if re.fullmatch(r'[A-Z][a-zA-Z0-9]*', t) and not re.search(r'[aeiouy]', t.lower()) and not place: return False
    if re.fullmatch(r'[A-Z]{3,}', t) and not place: return False   # GET, LEAVING, WFOS: a method, a close reason, a key
    if re.fullmatch(r'[A-Z][a-z]+(?:[A-Z][a-z0-9]+)+', t): return False   # NodeNames / CamelCase
    return place or unit or t[0].isupper() or t[0] in '%·+-–' or ' ' in t

def norm(t: str) -> str:
    t = re.sub(r'\\u([0-9a-fA-F]{4})', lambda m: chr(int(m.group(1), 16)), t)   # GDScript's ⁠ and the like, as shown
    t = t.replace('\\n', '\n').replace('\\"', '"')
    return re.sub(r'\s*·\s*$', '', re.sub(r'^\s*·\s*', '', t)).strip()

def main() -> None:
    out: dict = {}
    def add(src: str, where: str, place: bool = False, unit: bool = False) -> None:
        src = norm(src)
        if not src or not copy_like(src, place, unit): return
        e = out.setdefault(src, {"where": [], "kind": "template" if SPEC.search(src.replace('%%', '')) else "line"})
        if len(e["where"]) < 5: e["where"].append(where)
    files = subprocess.run(['git', 'ls-files', *DIRS], capture_output=True, text=True, cwd=ROOT).stdout.split()
    for f in files:
        if not f.endswith('.gd') or re.search(r'gallery|/dev/|_probe', f): continue   # dev pages no player sees
        text = (ROOT / f).read_text(encoding='utf-8')
        for n, line in enumerate(text.splitlines(), 1):
            if SKIP_LINE.match(line): continue
            code = line.split(' # ')[0] if ' # ' in line else line
            for m in LIT.finditer(code):
                before = code[:m.start()].rstrip()
                if before.endswith(('find_child(', '.name =', 'has_method(', 'call(', 'emit(', 'get(', 'has(', 'connect(', '==', 'in [',
                        'get_node(')):
                    continue
                add(m.group(1), f'{f}:{n}', bool(UI_PLACE.search(before)), bool(UNIT_PLACE.search(before)))
        for const in CAPITALIZED.get(f, []):
            m = re.search(r'const %s\b[^=]*=\s*\[([^\]]*)\]' % const, text)
            for w in LIT.findall(m.group(1)) if m else []: add(w.replace('_', ' ').title(), f'{f}#{const}', True)
    for rel, keys in CODE_JSON.items():
        def walk_rules(x, k=None):
            if isinstance(x, dict):
                for kk, v in x.items():
                    if not kk.startswith('_'): walk_rules(v, kk)
            elif isinstance(x, list):
                for v in x: walk_rules(v, k)
            elif isinstance(x, str) and k and keys.match(k):
                add(x, f'{rel}#{k}')   # whole, `{token}`s and all, as the content's guide lines go in
        walk_rules(json.loads((ROOT / rel).read_text(encoding='utf-8')))
    content = sorted((ROOT / 'assets/p0').glob('*.json')) + sorted((ROOT / 'assets/p0/content').glob('*.json'))
    for p in content:
        if p.name in ('city_clusters.json',): continue   # place names stay English in 0.2.21
        try: data = json.loads(p.read_text(encoding='utf-8'))
        except Exception: continue
        def walk(x, k=None, text=False):
            if isinstance(x, dict):
                for kk, v in x.items():
                    if not kk.startswith('_') and not SKIP_KEYS.match(kk): walk(v, kk, text or bool(TEXT_DICTS.match(kk)))
            elif isinstance(x, list):
                for v in x: walk(v, k, text)
            elif isinstance(x, str) and k and (text or TEXT_KEYS.match(k)):
                add(x, f'{p.relative_to(ROOT)}#{k}')
        walk(data)
    table = ROOT / 'assets/localization/p0_zh_CN.json'
    done = json.loads(table.read_text(encoding='utf-8')) if table.exists() else {}
    ctx_srcs = {k.rsplit('@', 1)[0] for k in done if '@' in k and not k.startswith('_')}
    for src, e in out.items():
        # … or by a key with a context (`Dawn@daypart`, `Orchard@family`: Localization.ctx reads them, the bare word left
        # to the names the world makes, SGODOT-492)
        if src in done or src in ctx_srcs: e["done"] = True
    dest = ROOT / 'tools/p0/i18n/p0_strings_en.json'
    dest.write_text(json.dumps(dict(sorted(out.items())), ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    kinds = {k: sum(1 for e in out.values() if e["kind"] == k) for k in ("line", "template")}
    print(f'{len(out)} lines ({kinds["line"]} lines, {kinds["template"]} templates), {sum(1 for e in out.values() if e.get("done"))} done → {dest.relative_to(ROOT)}')
    cities(out, done)

def cities(lines: dict, done: dict) -> None:
    rows = json.loads(subprocess.run(['node', '--import', 'tsx', 'tools/i18n_city_names.ts'], capture_output=True, text=True,
                                     cwd=ROOT / 'server', check=True).stdout)
    out: dict = {}
    for r in rows:
        e = out.setdefault(r['name'], {"ids": [], "country": r['country'], "homes": []})
        e["ids"].append(r['id'])
        e["homes"] += [h for h in r['homes'] if h not in e["homes"]]
    for name, e in out.items():
        if name in done: e["done"] = True
        if name in lines: e["also_line"] = True
    dest = ROOT / 'tools/p0/i18n/p0_cities_en.json'
    dest.write_text(json.dumps(dict(sorted(out.items())), ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    admins: dict = {}   # the states and provinces the Nearby rows write after these cities (`Salinas · California`)
    for r in rows:
        if r.get('admin'): admins.setdefault(r['admin'], {"cities": []})["cities"].append(r['name'])
    for a, e in admins.items():
        if a in done: e["done"] = True
    adest = ROOT / 'tools/p0/i18n/p0_admins_en.json'
    adest.write_text(json.dumps(dict(sorted(admins.items())), ensure_ascii=False, indent=1) + '\n', encoding='utf-8')
    print(f'{len(admins)} states / provinces, {sum(1 for e in admins.values() if e.get("done"))} done → {adest.relative_to(ROOT)}')
    homes = sorted({h for e in out.values() for h in e["homes"]})
    print(f'{len(out)} cities ({len(homes)} home cities and their fallback ten), {sum(1 for e in out.values() if e.get("done"))} done, '
          f'{sum(1 for e in out.values() if e.get("also_line"))} also lines the code shows → {dest.relative_to(ROOT)}')

if __name__ == '__main__':
    sys.exit(main())
