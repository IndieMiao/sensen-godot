#!/usr/bin/env python3
"""P0 中文版: checks assets/localization/p0_zh_CN.json — each Chinese line keeps its English's %d / %s (same count and
order, or {1}…{n} for all of them), its ` · ` and `›`, and is not empty. Exit 1 with the lines that do not."""
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SPEC = re.compile(r'%[+-]?\d*(?:\.\d+)?[dsf]')   # the specs P0Translation reads; %% is a percent sign

def main() -> int:
    table = json.loads((ROOT / 'assets/localization/p0_zh_CN.json').read_text(encoding='utf-8'))
    bad = []
    for en, zh in table.items():
        if en.startswith('_'): continue
        if not isinstance(zh, str) or not zh.strip(): bad.append((en, zh, 'empty')); continue
        ph = SPEC.findall(en.replace('%%', ''))
        if re.search(r'\{\d+\}', zh):
            idx = sorted(set(int(i) for i in re.findall(r'\{(\d+)\}', zh)))
            # {n} may leave one out (a plural ending), never point past the English's specs nor mix with them
            if not idx or idx[-1] > len(ph) or SPEC.search(zh.replace('%%', '')): bad.append((en, zh, 'placeholders {n}'))
        elif SPEC.findall(zh.replace('%%', '')) != ph: bad.append((en, zh, 'format specs'))
        for mark in (' · ', '›'):
            if en.count(mark) != zh.count(mark): bad.append((en, zh, f'"{mark.strip()}" count'))
    for en, zh, why in bad: print(f'✗ {why}: {en!r} → {zh!r}')
    print(f'{len(table)} entries, {len(bad)} problems')
    return 1 if bad else 0

if __name__ == '__main__':
    sys.exit(main())
