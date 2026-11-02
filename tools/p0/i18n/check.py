#!/usr/bin/env python3
"""P0 中文版: checks assets/localization/p0_zh_CN.json — each Chinese line keeps its English's %d / %s (same count and
order, or {1}…{n} for all of them), its ` · ` and `›`, and is not empty. Exit 1 with the lines that do not."""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def main() -> int:
    table = json.loads((ROOT / 'assets/localization/p0_zh_CN.json').read_text(encoding='utf-8'))
    bad = []
    for en, zh in table.items():
        if en.startswith('_'): continue
        if not isinstance(zh, str) or not zh.strip(): bad.append((en, zh, 'empty')); continue
        ph = re.findall(r'%[ds]', en)
        if re.search(r'\{\d+\}', zh):
            idx = sorted(set(int(i) for i in re.findall(r'\{(\d+)\}', zh)))
            if idx != list(range(1, len(ph) + 1)) or re.search(r'%[ds]', zh): bad.append((en, zh, 'placeholders {n}'))
        elif re.findall(r'%[ds]', zh) != ph: bad.append((en, zh, 'placeholders %d/%s'))
        for mark in (' · ', '›'):
            if en.count(mark) != zh.count(mark): bad.append((en, zh, f'"{mark.strip()}" count'))
    for en, zh, why in bad: print(f'✗ {why}: {en!r} → {zh!r}')
    print(f'{len(table)} entries, {len(bad)} problems')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
