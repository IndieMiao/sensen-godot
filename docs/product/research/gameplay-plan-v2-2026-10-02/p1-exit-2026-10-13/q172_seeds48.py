"""q(172) 贴线项补跑：重度玩家 48 seed，比较扩田的两个方向（A = 田前方、靠出生点一侧，用户 10-13 定；B = 靠房子一侧，作对照）。
输出每个方向 12 / 48 seed 的金币去向中界、Homestead Lv10（> 35 天的 seed 数）、Lv9 落在 28 天窗口外的 seed 数、第二座温室建成数、第 31–60 天播不下的体力。
用法：python3 -B q172_seeds48.py（约 6 分钟，8 进程）。"""
import sys, json, statistics
sys.dont_write_bytecode = True
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from concurrent.futures import ProcessPoolExecutor
import sim_p1 as P
LAYOUTS = {'A_camera': [(c, -1) for c in range(8)], 'B_house': [(c, 5) for c in range(8)]}
CFG = {}
def cfg_for(name):
    P.LV7_CELLS = LAYOUTS[name]; P.layout.cache_clear(); P.sprinkler_target.cache_clear()
    return P.p1_config(plot_ladder=P.BASE_LADDER)
def one(args):
    name, seed = args
    cfg = cfg_for(name)
    p, daily = P.run('HEAVY', P.ARCH['HEAVY'], cfg, seed, 120)
    w28 = daily[:28]
    inc = cfg['initial_wallet'] + sum((x.get('income', 0) or 0) - (x.get('seed_cost', 0) or 0) for x in w28)
    s = {k: sum((x.get('sink_' + k, 0) or 0) for x in w28) for k in P.SINKS}
    A = sum(s[k] for k in P.SINK_A); B = sum(s[k] for k in P.SINK_B)
    sow_short = statistics.mean((x.get('sow_short', 0) or 0) for x in daily[30:60]) if daily and 'sow_short' in daily[0] else None
    return dict(name=name, seed=seed, inc=inc, A=A, B=B, hs9=p.milestones.get('hs_lv9'), hs10=p.milestones.get('hs_lv10'), gh2=p.milestones.get('greenhouse_2'), sow_short=sow_short)
if __name__ == '__main__':
    jobs = [(n, s) for n in LAYOUTS for s in range(48)]
    with ProcessPoolExecutor(8) as ex: R = list(ex.map(one, jobs, chunksize=2))
    for name in LAYOUTS:
        rows = sorted([r for r in R if r['name'] == name], key=lambda r: r['seed'])
        for n in (12, 48):
            sub = rows[:n]; inc = statistics.mean(r['inc'] for r in sub); AB = statistics.mean(r['A'] + r['B'] for r in sub)
            hs10 = [r['hs10'] for r in sub if r['hs10']]
            ss = [r['sow_short'] for r in sub if r['sow_short'] is not None]
            print(f'{name} seeds 0-{n-1}: mid {AB/inc:.4f} | Hs10 {statistics.mean(hs10):.2f} (>35: {sum(h>35 for h in hs10)}/{len(hs10)}) | Hs9>28: {sum((r["hs9"] or 99)>28 for r in sub)}/{n} | GH2 built: {sum(1 for r in sub if r["gh2"])}/{n}' + (f' | sow_short d31-60 {statistics.mean(ss):.1f}' if ss else ''))
