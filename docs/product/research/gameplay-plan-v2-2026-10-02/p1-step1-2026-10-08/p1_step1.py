#!/usr/bin/env python3
"""
p1_step1.py — P1 第一步（第 5 天之后的种田）的两周复跑（2026-10-08，李白）

在 P0 的经济基线 D（p0_v1.py --v2：旋钮 A + V2 机器人买卖打法，q(54)）上加 P1 第一步的内容（方案 v2 §17.3.3 第 1 行，q(58)）：
  作物 +3：卷心菜（Farming Lv5）、玉米（Lv5）、黄瓜（Lv6），种子在农场驿站；
  料理 +4 页：Cabbage Stew（#8）、Cucumber Salad（#18）、Roast Veggies（#21，田 × Fine 兜底页）、Corn Cake（#22）；
  田块：Homestead Lv1–2 30 格，Lv3 起 40 格；
  洒水器：Farming Lv6 起，覆盖的格成熟时长 −15%（模拟只算时长；浇水这一步模拟器本来就不计时间）。
不改 sim_v3.py 与 p0_v1.py。

用法：
  python3 p1_step1.py                  # 14 天 × 30 seed，全部情形
  python3 p1_step1.py --days 14 --seeds 6
"""
import argparse, os, statistics, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'p0-v1-2026-10-08'))
import p0_v1 as V  # noqa: E402
S = V.S

P1_CROPS = ['cabbage', 'corn', 'cucumber']
P1_DISHES = ['cabbage_stew', 'cucumber_salad', 'roast_veggies', 'corn_cake']


def p1_config(plots_lv3=40, plots_base=30, sprinkler=True, crops=True, takes_plot=False):
    cfg = V.p0_config(plots_base, quartz_to_salt=True)
    full = S.base_config()
    if crops:
        for k in P1_CROPS:
            cfg['crops'][k] = full['crops'][k]
        for k in P1_DISHES:
            cfg['dishes'][k] = full['dishes'][k]
        assert len(cfg['dishes']) == 18, sorted(cfg['dishes'])
        tags = {}
        for t, ids in full['tags'].items():
            tags[t] = [i for i in ids if i in cfg['fish'] or i in cfg['crops'] or i in ('rock_salt', 'wild_herb')]
        cfg['tags'] = tags
    cfg['plot_cap'] = lambda hs, a=plots_base, b=plots_lv3: b if hs >= 3 else a
    cfg['p1_sprinkler'] = sprinkler
    cfg['p1_takes_plot'] = takes_plot   # 方案原规则：洒水器占 1 格田、浇周围 8 格
    return cfg


class P1Player(V.P0Player):
    def sow(self, energy_budget):
        # 洒水器：Farming Lv6 的第二天起（留一天攒铜与木石），田里的一年生成熟 −15%
        lv6 = self.milestones.get('farming_lv6')
        if not (self.cfg.get('p1_sprinkler') and lv6 is not None and self.day() >= lv6 + 1):
            return super().sow(energy_budget)
        saved = {k: c['hours'] for k, c in self.cfg['crops'].items()}
        for k, c in self.cfg['crops'].items():
            c['hours'] = saved[k] * 0.85
        cap = self.cfg['plot_cap']
        if self.cfg.get('p1_takes_plot'):
            # 占田版：要把田全盖住，每 9 格放 1 台（受 3 + Homestead 上限），每台占掉 1 格
            def taken(hs, f=cap):
                n = f(hs)
                k = min(-(-n // 9), 3 + hs)
                return n - k
            self.cfg['plot_cap'] = taken
        try:
            return super().sow(energy_budget)
        finally:
            self.cfg['plot_cap'] = cap
            for k, c in self.cfg['crops'].items():
                c['hours'] = saved[k]


def run(arch, cfg, seed, days):
    V.P0Player, saved = P1Player, V.P0Player
    try:
        return V.run(arch, cfg, seed, days)
    finally:
        V.P0Player = saved


def scenario(name, cfg_fn, archs, seeds, days, mutate=None):
    """V.scenario 的同款，另算第 2 周日均播种体力。"""
    out = []
    for arch in archs:
        a = dict(V.ARCH[arch])
        if mutate:
            mutate(a)
        backup = V.ARCH[arch]; V.ARCH[arch] = a
        runs = [run(arch, cfg_fn(), s, days) for s in range(seeds)]
        V.ARCH[arch] = backup
        mean = lambda f: statistics.mean(f(r) for r in runs)  # noqa: E731
        keys = {k for p, _ in runs for k in p.milestones}
        ms = {k: statistics.mean([p.milestones.get(k, days + 1) for p, _ in runs]) for k in keys}
        daily = [statistics.mean(sn[d]['energy_spent'] for _, sn in runs) for d in range(days)]
        last = lambda k: mean(lambda r: r[1][days - 1][k])  # noqa: E731
        farm2 = statistics.mean(sum(s['farm_e'] for s in sn[7:14]) / 7 for _, sn in runs) if days >= 14 else 0
        out.append(dict(arch=arch, ms=ms, daily=daily, farm2=farm2,
                        xp_farm=last('xp_farm'), xp_fish=last('xp_fish'), xp_cook=last('xp_cook'),
                        lv_farm=last('lv_farm'), lv_fish=last('lv_fish'), lv_cook=last('lv_cook'),
                        wallet=last('wallet'), cookbook=last('cookbook'),
                        walls=statistics.mean(sum(s['walls'] for s in sn) for _, sn in runs),
                        sow_short=statistics.mean(sum(s['sow_short'] for s in sn) for _, sn in runs)))
    return name, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--days', type=int, default=14)
    ap.add_argument('--seeds', type=int, default=30)
    args = ap.parse_args()
    D, N = args.days, args.seeds
    archs = ['P0T', 'P5', 'P30C', 'HEAVY']
    v2 = lambda a: a.update(v2align=True)  # noqa: E731
    if True:
        scens = [
            scenario('D · P0 基线（30 格，P0 内容；= p0_v1.py --v2 的口径）', lambda: p1_config(30, sprinkler=False, crops=False), archs, N, D, mutate=v2),
            scenario('E · P1 第一步：Homestead Lv3 起 40 格 + 卷心菜 / 玉米 / 黄瓜 + 4 页料理 + 洒水器（Lv6）', lambda: p1_config(40), archs, N, D, mutate=v2),
            scenario('E1 · 对照：只加作物与料理，不扩田、没有洒水器', lambda: p1_config(30, sprinkler=False), archs, N, D, mutate=v2),
            scenario('E2 · 对照：一开局就 40 格（不挂 Homestead Lv3）', lambda: p1_config(40, plots_base=40), archs, N, D, mutate=v2),
            scenario('E3 · 对照：洒水器按方案原规则占 1 格田（40 格时放 5 台、30 格时 4 台）', lambda: p1_config(40, takes_plot=True), archs, N, D, mutate=v2),
        ]
    print(f'# P1 第一步两周复跑 · {D} 天 × {N} seed\n')
    print('口径同 p0_v1.py --v2（q(54)）：旋钮 A、每种鱼留 2 条、作物留 3 个、每天补 10 条蚯蚓；目标玩家早 15 + 晚 30 分钟。\n')
    for name, rows in scens:
        print(f'## {name}\n')
        print('| 画像 | 第 1 周体力 | 第 2 周体力 | 第 2 周播种体力 / 日 | Farming XP（Lv） | Fishing XP（Lv） | Cooking XP（Lv） | Fa4 / Fa5 / Fa6 / Fa7 | Hs2 / Hs3 | 钱包 | Cookbook | 播种没花完的体力（14 天） | 撞墙 |')
        print('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
        for r in rows:
            ms = r['ms']; f = lambda k: V.first_day(ms, k, D)  # noqa: E731
            w1, w2 = sum(r['daily'][:7]), sum(r['daily'][7:14])
            print(f"| {r['arch']} | {w1:.0f} | {w2:.0f} | {r['farm2']:.0f} | {r['xp_farm']:.0f}（{r['lv_farm']:.1f}） | {r['xp_fish']:.0f}（{r['lv_fish']:.1f}） | "
                  f"{r['xp_cook']:.0f}（{r['lv_cook']:.1f}） | {f('farming_lv4')} / {f('farming_lv5')} / {f('farming_lv6')} / {f('farming_lv7')} | "
                  f"{f('hs_lv2')} / {f('hs_lv3')} | {r['wallet']:.0f} | {r['cookbook']:.1f} | {r['sow_short']:.0f} | {r['walls']:.1f} |")
        print()


if __name__ == '__main__':
    main()
