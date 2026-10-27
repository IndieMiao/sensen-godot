#!/usr/bin/env python3
"""第 15 章全量模拟（sim_v3 基表，120 天）换上 v3 首会话后的里程碑对照（SGODOT-339，2026-10-27）。
用法：python3 full_v3.py --seeds 24 > out_full120.md（方案 15.1.2 用 24 个种子）；full_mc() 是首会话蒙特卡洛（out_full_mc.txt）；只换首会话，其余规则与第 15 章基表相同（不加 q(101) 等后来的改动，以便单看首会话的影响）。"""
import argparse, statistics
import p0_v3 as M
S = M.S

KEYS = [('fishing_lv2', 'Fi2'), ('fishing_lv3', 'Fi3'), ('farming_lv2', 'Fa2'), ('farming_lv3', 'Fa3'), ('cooking_lv2', 'Co2'),
        ('cooking_lv4', 'Co4'), ('hs_lv2', 'Hs2'), ('fishing_lv10', 'Fi10'), ('farming_lv10', 'Fa10'), ('cooking_lv10', 'Co10'), ('hs_lv10', 'Hs10')]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument('--seeds', type=int, default=6); ap.add_argument('--days', type=int, default=120)
    a = ap.parse_args()
    cfg = S.base_config()
    print(f'# 第 15 章基表 · v2 / v3 首会话里程碑对照（{a.days} 天 × {a.seeds} seed；均值日，— = 期内未到）\n')
    print('| 画像 | 首会话 | ' + ' | '.join(k for _, k in KEYS) + ' |')
    print('|---|---|' + '---|' * len(KEYS))
    orig = S.Player
    for arch in ('P5', 'P30', 'P30C', 'HEAVY'):
        for mode in ('v2', 'v3'):
            S.Player = orig if mode == 'v2' else M.FullV3
            M.FullV3.first_mode = 'v3'; M.FullV3.guide_only = False
            try:
                runs, ms, agg = S.summarize(arch, cfg, a.seeds, a.days)
            finally:
                S.Player = orig
            cells = []
            for k, _ in KEYS:
                v = ms.get(k)
                cells.append('—' if v is None or v > a.days else f'{v:.1f}')
            print(f'| {arch} | {mode} | ' + ' | '.join(cells) + ' |')


if __name__ == '__main__':
    main()


def full_mc(trials=2000):
    """第 15 章基表规则下的 v3 首会话蒙特卡洛（P30 画像；引导 + 播萝卜 + 可选钓到第 30 分钟）。"""
    import random
    cfg = S.base_config(); res = []
    for s in range(trials):
        M.FullV3.first_mode = 'v3'; M.FullV3.guide_only = False
        p = M.FullV3('P30', cfg, random.Random(s)); p.first_session(12 * 60)
        fl = p.first_session_lv2_minute; cl = p.first_session_cook_lv2_minute
        res.append(((fl - 720) if fl is not None else 99, (cl - 720) if cl is not None else 99, p.xp['fishing'], p.xp['cooking'],
                    p.first_session_end_energy, p.marks['energy_before_eat'], p.marks['energy_after_eat'], p.daily[1]['casts'], p.daily[1]['cooked']))
    col = lambda i: sorted(r[i] for r in res)  # noqa: E731
    fm, cm = col(0), col(1)
    return dict(fish30=sum(1 for m in fm if m <= 30) / trials, fish_med=statistics.median(fm), fish_p90=fm[int(.9 * trials)],
                cook30=sum(1 for m in cm if m <= 30) / trials, cook_med=statistics.median(cm), cook_p90=cm[int(.9 * trials)],
                fx=statistics.median(col(2)), cx=statistics.median(col(3)), end=statistics.median(col(4)),
                before=statistics.median(col(5)), after=statistics.median(col(6)), casts=statistics.mean(col(7)), pots=statistics.mean(col(8)))
