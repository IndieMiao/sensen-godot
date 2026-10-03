#!/usr/bin/env python3
"""对照表：每个开关一行（6 seed × 120 天），输出 markdown 行。"""
import sys, io, statistics, contextlib
sys.path.insert(0, '/tmp/gensen_design/v2/sim_r3')
import sim_v3 as S
VARS = sys.argv[1].split(';') if len(sys.argv) > 1 else ['']
def ms(res, arch, k):
    v = res[arch][1].get(k, 999)
    return f'{v:.0f}' if v <= 120 else '—'
rows = []
for v in VARS:
    fixes = set(x for x in v.split(',') if x)
    cfg = S.apply_fixes(S.base_config(), fixes) if fixes else S.base_config()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        results, summary, mc, ratios = S.report(cfg, 6, 120)
    r = results; var = results['_variants']
    def mine_share(arch):
        w = r[arch][2][7:30]
        return statistics.mean(a['energy_mine'] for a in w) / statistics.mean(a['energy'] for a in w)
    row = [v or '基表（r3）',
           f"{ms(r,'P30','fishing_lv10')} / {ms(r,'P30','farming_lv10')} / {ms(r,'P30','cooking_lv10')}",
           f"{ms(r,'P30C','fishing_lv10')} / {ms(r,'P30C','farming_lv10')} / {ms(r,'P30C','cooking_lv10')}",
           f"{ms(r,'HEAVY','fishing_lv10')} / {ms(r,'HEAVY','farming_lv10')} / {ms(r,'HEAVY','cooking_lv10')}",
           f"{ms(r,'P5','fishing_lv10')} / {ms(r,'P5','farming_lv10')} / {ms(r,'P5','cooking_lv10')}",
           f"{ms(r,'HEAVY','hs_lv10')} / {ms(var,'H_FOCUS','hs_lv10')}",
           f"{ms(r,'P30C','hs_lv10')} / {ms(r,'P30','hs_lv10')} / {ms(r,'P30B','hs_lv10')}",
           f"{ratios['P30']['rd']:.2f}",
           f"{summary['P5']['share_mid']:.0%} / {summary['P30']['share_mid']:.0%} / {summary['HEAVY']['share_mid']:.0%}",
           f"{summary['HEAVY']['walls']:.2f}",
           f"{mine_share('P30'):.1%} / {mine_share('HEAVY'):.1%}",
           f"{summary['P30']['net']:.0f} / {summary['HEAVY']['net']:.0f}",
           f"{mc['cook_p30']:.1%}"]
    print('| ' + ' | '.join(row) + ' |', flush=True)
