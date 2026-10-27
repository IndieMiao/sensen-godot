#!/usr/bin/env python3
"""
p0_v3.py — 首会话 v3（q(215)）之后的七日 / 十四日复跑（SGODOT-339，2026-10-27，李白）

在 p0_v1.py 的 P0 子集上，只换掉第 1 天 12:00 的首会话，其余规则按现行口径：
  · 旋钮 A：第 2 层石英并入岩盐（q(47)）；
  · 技能升级不回体力（q(101)；Cooking 原本就不回，q(37)）；
  · 经济基线 D：V2 机器人的买卖打法（q(54)；--no-v2 关掉，回到 V1 的 A 口径）。
同一套规则下并排跑「v2 首会话」（sim_v3 导演表：20 小萝卜、3 竿强制鲫鱼、交 Pond Catch 16、钓到 Lv2、香草烤鱼）
与「v3 首会话」（§14.2 / 14.2.1 / 14.2.2）：
  S2 播 2 格快熟萝卜（−4，45 秒熟）→ S4 播 10 格生菜（−20）→ S5 收 2 个萝卜（Farming 14）
  → S6 交 Nadia 1 个萝卜（+20 coins、鲜鱼汤配方卡）→ S7 两竿保证鲫鱼（Fishing 55）
  → S8 烤鲫鱼吃掉 → S9 鲜鱼汤（Keep）→ Cooking Lv2（升级礼 = Grilled Fish 配方卡，q(221)）→ S10 汤送 Nadia
  → 引导后回家播 20 格小萝卜（−40）→ 可选：继续钓到第 30 分钟（第 3 竿钉 1 鲫鱼、第 4 竿钉 2 Fine 挣脱、
    到 Lv2 后挂饵第 1 竿钉 3 Fine）；Nadia 委托 2 `Six Radishes`（+20 coins）第 2 天收萝卜后交。
Fishing Lv2 升级礼（蚯蚓 3、野香草 3、香草烤鱼配方卡）改为在任何时刻升到 Lv2 时发（v3 下有玩家在第 2 天才到 Lv2）。
不改 sim_v3.py、p0_v1.py。

用法：
  python3 p0_v3.py --seeds 30               # 7 天，四个画像 × 两种首会话
  python3 p0_v3.py --days 14 --seeds 30
  python3 p0_v3.py --mc 2000                # 只跑首会话蒙特卡洛
"""
import argparse, os, random, statistics, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'p0-v1-2026-10-08'))
import p0_v1 as V  # noqa: E402
S = V.S


def config(v2align=True):
    cfg = V.p0_config(30, quartz_to_salt=True)
    cfg['lvup_first'] = 0; cfg['lvup'] = 0          # q(101)
    return cfg


class V3Mixin:
    """v3 首会话；与 P0Player（P0 子集）或 sim_v3.Player（全量，第 15 章）组合。"""
    first_mode = 'v3'      # 'v3' / 'v2'
    guide_only = False     # True：只玩到引导结束 + 回家播萝卜（不做可选的继续钓）

    def __init__(self, arch, cfg, rng):
        super().__init__(arch, cfg, rng)
        self.fish_lv2_gift = False
        self.six_radishes = None      # None 未接 / 'open' 已接 / 'done'
        self.guide_end_t = None
        self.marks = {}

    def add_xp(self, track, amount, oneoff=False):
        before = self.level(track)
        r = super().add_xp(track, amount, oneoff)
        after = self.level(track)
        if self.first_mode == 'v3':
            if track == 'cooking' and before < 2 <= after:
                self.discovered.add('grilled_fish')          # q(221)：Cooking Lv2 礼 = Grilled Fish 卡
            if track == 'fishing' and before < 2 <= after and not self.fish_lv2_gift:
                self.fish_lv2_gift = True
                self.inv['worm'] += 3; self.mats['wild_herb'] += 3; self.discovered.add('herb_grilled_fish')
        return r

    def _forced_crucian(self, guaranteed=True):
        cfg = self.cfg
        self.settle(self.t); self.spend(cfg['cast'], 'fish'); self.daily[self.day()]['casts'] += 1
        if not self.first_cast:
            self.first_cast = True; self.add_xp('fishing', cfg['first_cast_xp'], oneoff=True)
        self.t += 40 / 60
        ok = True if guaranteed else self.rng.random() < cfg['rods']['starter']['p'][0]
        if not ok:
            self.fails_today += 1; self.energy += cfg['cast']
            self.daily[self.day()]['energy'] -= cfg['cast']; self.daily[self.day()]['energy_fish'] -= cfg['cast']
            return False
        if not self.first_hook:
            self.first_hook = True; self.add_xp('fishing', cfg['first_hook_xp'], oneoff=True)
        self.inv['crucian'] += 1; self.daily[self.day()]['fish_value'] += 3; self.daily[self.day()]['fish_caught'] += 1
        if 'crucian' not in self.first_fish:
            self.first_fish.add('crucian'); self.add_xp('fishing', cfg['first_species']['common'], oneoff=True)
        if 'home_fished' not in self.cities:
            self.cities.add('home_fished'); self.add_xp('fishing', cfg['first_city_xp'], oneoff=True)
        self.add_xp('fishing', cfg['fish_xp']['common'])
        return True

    def first_session(self, t0):
        if self.first_mode != 'v3':
            return super().first_session(t0)
        cfg = self.cfg
        self.t0_reg = t0
        self.settle(t0); self.rest_ok = False
        end = t0 + 30
        # S2：2 格快熟萝卜（档 1，2 / 格），浇水后 45 秒熟（q(217)）
        self.t = t0 + 2.5
        for _ in range(2):
            self.spend(2, 'farm'); self.plots.append(('radish', t0 + 3.75, 2, True))
        self.daily[1]['sown_energy'] += 4
        # S4：10 格生菜
        self.t = t0 + 3; self.settle(self.t)
        for _ in range(10):
            self.spend(2, 'farm'); self.plots.append(('lettuce', self.t + 8 * 60, 2, True))
        self.daily[1]['sown_energy'] += 20
        # S5：收快熟萝卜（只收这 2 格）
        self.t = t0 + 5; self.settle(self.t)
        self.harvest()
        self.marks['farm_after_s5'] = self.xp['farming']
        # S6：交 Nadia 1 个萝卜 → 20 coins、鲜鱼汤配方卡（q(218)、q(221)）
        self.t = t0 + 8; self.settle(self.t)
        self.inv['radish'] -= 1; self.earn(20, 'requests'); self.discovered.add('fish_soup')
        # S7：两竿保证鲫鱼（q(219)）
        self.t = t0 + 9
        for _ in range(2):
            self._forced_crucian(True)
        self.marks['fish_after_s7'] = self.xp['fishing']
        # S8：烤鲫鱼吃掉
        self.t = t0 + 12.5; self.settle(self.t)
        self.marks['energy_before_eat'] = self.energy
        self.cook('grilled_crucian', ['crucian']); self.eat(need=self.energy + 1)
        self.marks['energy_after_eat'] = self.energy
        # S9：鲜鱼汤 Keep（鱼 + 萝卜）→ Cooking Lv2
        self.t = t0 + 14; self.settle(self.t)
        self.cook('fish_soup', ['crucian', 'radish'])
        self.marks['cook_after_s9'] = self.xp['cooking']
        # S10：汤送 Nadia（不吃）；S11：接 Six Radishes = 引导结束
        self.t = t0 + 17; self.settle(self.t)
        self.dishes['fish_soup'] -= 1
        self.t = t0 + 19; self.settle(self.t)
        self.six_radishes = 'open'; self.guide_end_t = self.t
        # 引导后：回家播 20 格小萝卜（−40）
        for _ in range(20):
            if self.energy >= 2:
                self.spend(2, 'farm'); self.plots.append(('radish', self.t + 4 * 60, 2, False))
                self.t += 0.15
        self.daily[1]['sown_energy'] += 40
        self.t = max(self.t, t0 + 22); self.settle(self.t)
        self.marks['energy_t22'] = self.energy
        if not self.guide_only:
            # 可选：第 3 竿钉 1（鲫鱼，按新手竿成功率）、第 4 竿钉 2（Fine 挣脱，Lv1 全退），之后照常到 Lv2
            self._forced_crucian(False)
            self.settle(self.t); self.spend(cfg['cast'], 'fish'); self.fails_today += 1; self.energy += cfg['cast']
            self.daily[1]['energy'] -= cfg['cast']; self.daily[1]['energy_fish'] -= cfg['cast']; self.daily[1]['casts'] += 1
            self.t += 40 / 60
            k = 0
            while self.t < end - 1 and self.level('fishing') < 2 and k < 20:
                self.settle(self.t); self.cast('pond'); k += 1
            if self.level('fishing') >= 2 and self.energy >= 5 and self.t < end:
                # 钉 3：Lv2 后第一次挂饵 = Fine（河鲈）
                self.settle(self.t); self.spend(5, 'fish'); self.inv['worm'] -= 1; self.daily[1]['casts'] += 1; self.t += 30 / 60
                self.inv['perch'] += 1; self.daily[1]['fish_value'] += 7; self.daily[1]['fish_caught'] += 1
                self.first_fish.add('perch'); self.add_xp('fishing', cfg['first_species']['fine'], oneoff=True)
                self.add_xp('fishing', cfg['fish_xp']['fine'])
                if 'fine' not in self.first_rar:
                    self.first_rar.add('fine'); self.add_energy_bonus(cfg['first_fish_energy']['fine'], 'achv')
            self.settle(max(self.t, end))
        self.first_session_end_energy = self.energy
        self.marks['end_t'] = self.t
        self.sell(); self.purchases()
        self.last_session_end = self.t

    def harvest(self):
        super().harvest()
        # Six Radishes：接下后收的小萝卜够 6 个 → 下次去集市交（同城免费），20 coins（q(218)）
        if self.six_radishes == 'open' and self.t > (self.guide_end_t or 0) + 60 and self.inv['radish'] >= 6:
            self.six_radishes = 'done'; self.earn(20, 'requests')
            self.milestones.setdefault('six_radishes', self.day())


class V3Player(V3Mixin, V.P0Player):
    pass


class FullV3(V3Mixin, S.Player):
    pass


def run(arch, cfg, seed, days, mode, guide_only=False, day1_evening=True):
    rng = random.Random(seed)
    V3Player.first_mode = mode; V3Player.guide_only = guide_only
    p = V3Player(arch, cfg, rng)
    p.first_session(12 * 60)
    snaps = []
    for day in range(1, days + 1):
        for idx, (mod, minutes) in enumerate(p.a['sessions']):
            t0 = (day - 1) * 1440 + mod
            if day == 1 and (t0 < 12 * 60 + 30 or not day1_evening):
                continue
            p.session(idx, t0, minutes, day)
        rec = p.daily.get(day, Counter())
        snaps.append(dict(day=day, energy=rec.get('energy', 0), walls=rec.get('walls', 0),
                          xp_farm=p.xp['farming'], xp_fish=p.xp['fishing'], xp_cook=p.xp['cooking'],
                          wallet=p.wallet, cookbook=len(p.cooked_once), fishdex=len(p.first_fish),
                          three=sum(1 for k in p.cooked_once if p.cfg['dishes'][k]['slots'] == 3)))
    return p, snaps


def summarize(arch, mode, seeds, days, v2align=True, guide_only=False, day1_evening=True):
    a = dict(V.ARCH[arch])
    if v2align:
        a['v2align'] = True
    backup = V.ARCH[arch]; V.ARCH[arch] = a
    S.ARCHETYPES[arch] = a
    try:
        runs = [run(arch, config(), s, days, mode, guide_only, day1_evening) for s in range(seeds)]
    finally:
        V.ARCH[arch] = backup; S.ARCHETYPES[arch] = backup
    m = lambda f: statistics.mean(f(r) for r in runs)  # noqa: E731
    keys = {k for p, _ in runs for k in p.milestones}
    ms = {k: statistics.mean([p.milestones.get(k, days + 1) for p, _ in runs]) for k in keys}
    share = lambda k, d: sum(1 for p, _ in runs if p.milestones.get(k, 99) <= d) / len(runs)  # noqa: E731
    three = statistics.mean([next((s['day'] for s in sn if s['three'] > 0), days + 1) for _, sn in runs])
    daily = [statistics.mean(sn[d]['energy'] for _, sn in runs) for d in range(days)]
    last = lambda k, d=days: m(lambda r: r[1][d - 1][k])  # noqa: E731
    return dict(daily=daily, ms=ms, share=share, three=three, last=last, runs=runs,
                walls=m(lambda r: sum(s['walls'] for s in r[1])))


def fmt_day(ms, k, days):
    v = ms.get(k)
    return '—' if v is None or v > days else f'{v:.1f}'


def lv(track_xp, track):
    th = {'farming': [0, 50, 150, 300, 500, 750, 1050, 1400, 1800, 2300],
          'fishing': [0, 70, 220, 480, 850, 1300, 1850, 2500, 3250, 4100],
          'cooking': [0, 30, 100, 220, 400, 650, 950, 1350, 1700, 2350]}[track]
    return sum(1 for t in th if track_xp >= t)


def mc(trials):
    out = {}
    for guide_only in (False, True):
        res = []
        for s in range(trials):
            V3Player.first_mode = 'v3'; V3Player.guide_only = guide_only
            S.ARCHETYPES.setdefault('P0T', V.ARCH['P0T'])
            p = V3Player('P0T', config(), random.Random(s))
            p.first_session(12 * 60)
            fl = p.first_session_lv2_minute; cl = p.first_session_cook_lv2_minute
            res.append(dict(fish_lv2=(fl - 720) if fl is not None else 99, cook_lv2=(cl - 720) if cl is not None else 99,
                            before=p.marks['energy_before_eat'], after=p.marks['energy_after_eat'], t22=p.marks['energy_t22'],
                            end=p.first_session_end_energy, fx=p.xp['fishing'], cx=p.xp['cooking'], fa=p.xp['farming'],
                            casts=p.daily[1]['casts'], wallet=p.wallet))
        med = lambda k: statistics.median(r[k] for r in res)  # noqa: E731
        out[guide_only] = dict(
            fish30=sum(1 for r in res if r['fish_lv2'] <= 30) / trials, fish_med=med('fish_lv2'),
            cook30=sum(1 for r in res if r['cook_lv2'] <= 30) / trials, cook_med=med('cook_lv2'),
            before=med('before'), after=med('after'), t22=med('t22'), end=med('end'), fx=med('fx'), cx=med('cx'), fa=med('fa'),
            casts=statistics.mean(r['casts'] for r in res), wallet=med('wallet'))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--days', type=int, default=7)
    ap.add_argument('--seeds', type=int, default=30)
    ap.add_argument('--mc', type=int, default=0)
    ap.add_argument('--no-v2', action='store_true')
    args = ap.parse_args()
    D, N = args.days, args.seeds
    if args.mc:
        r = mc(args.mc)
        print(f'# 首会话 v3 蒙特卡洛（{args.mc} 次，P0 规则 + q(101)）\n')
        print('| 口径 | Fishing Lv2 ≤ 30 分钟 | 中位分钟 | Cooking Lv2 ≤ 30 分钟 | 中位分钟 | 吃前体力 | 吃后 | 第 22 分钟 | 会话末 | Farming / Fishing / Cooking XP | 竿数 | 钱包 |')
        print('|---|---|---|---|---|---|---|---|---|---|---|---|')
        for g, x in r.items():
            print(f"| {'只玩到引导结束 + 播萝卜' if g else '引导 + 播萝卜 + 可选钓到第 30 分钟'} | {x['fish30']:.1%} | {format(x['fish_med'], '.1f') if x['fish_med'] < 99 else '—'} | "
                  f"{x['cook30']:.1%} | {x['cook_med']:.1f} | {x['before']:.0f} | {x['after']:.0f} | {x['t22']:.0f} | {x['end']:.0f} | "
                  f"{x['fa']:.0f} / {x['fx']:.0f} / {x['cx']:.0f} | {x['casts']:.1f} | {x['wallet']:.0f} |")
        return
    v2 = not args.no_v2
    print(f"# 首会话 v3 复跑 · {D} 天 × {N} seed · 规则：P0 子集 + 旋钮 A + q(101) 升级不回体力{' + 经济基线 D（V2 买卖打法）' if v2 else ''}\n")
    cases = [('P0T', 'v2', False, True), ('P0T', 'v3', False, True), ('P0T', 'v3', True, True), ('P0T', 'v3', False, False), ('P0T', 'v3', True, False),
             ('P5', 'v2', False, True), ('P5', 'v3', False, True), ('P30C', 'v2', False, True), ('P30C', 'v3', False, True),
             ('HEAVY', 'v2', False, True), ('HEAVY', 'v3', False, True)]
    print('| 画像 | 首会话 | 逐日体力 | 合计 | 第 7 天 Farming / Fishing / Cooking XP（Lv） | 钱包 | Cookbook | Fish-dex | Fa2 / Fa3 / Fa4 / Fa5 | Fi2 / Fi3 / Fi4 / Fi5 | Co2 / Co3 / Co4 / Co5 / Co6 | Hs2 / Hs3 | 首道 3 槽菜 | Fi3 ≤ 第 2 天 | 撞墙 |')
    print('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for arch, mode, go, eve in cases:
        r = summarize(arch, mode, N, D, v2align=v2, guide_only=go, day1_evening=eve)
        f = lambda k: fmt_day(r['ms'], k, D)  # noqa: E731
        label = {('v2', False, True): 'v2', ('v3', False, True): 'v3', ('v3', True, True): 'v3 · 只玩到引导结束',
                 ('v3', False, False): 'v3 · 第 1 天无晚场', ('v3', True, False): 'v3 · 只玩到引导结束、第 1 天无晚场'}[(mode, go, eve)]
        X = lambda k: r['last'](k)  # noqa: E731
        d7 = min(D, 7)
        x7 = lambda k: r['last'](k, d7)  # noqa: E731
        print(f"| {arch} | {label} | {' / '.join(f'{x:.0f}' for x in r['daily'][:7])} | {sum(r['daily'][:7]):.0f} | "
              f"{x7('xp_farm'):.0f}（{lv(x7('xp_farm'), 'farming')}） / {x7('xp_fish'):.0f}（{lv(x7('xp_fish'), 'fishing')}） / {x7('xp_cook'):.0f}（{lv(x7('xp_cook'), 'cooking')}） | "
              f"{x7('wallet'):.0f} | {x7('cookbook'):.1f} | {x7('fishdex'):.1f} | "
              f"{f('farming_lv2')} / {f('farming_lv3')} / {f('farming_lv4')} / {f('farming_lv5')} | {f('fishing_lv2')} / {f('fishing_lv3')} / {f('fishing_lv4')} / {f('fishing_lv5')} | "
              f"{f('cooking_lv2')} / {f('cooking_lv3')} / {f('cooking_lv4')} / {f('cooking_lv5')} / {f('cooking_lv6')} | {f('hs_lv2')} / {f('hs_lv3')} | "
              f"{'—' if r['three'] > D else format(r['three'], '.1f')} | {r['share']('fishing_lv3', 2):.0%} | {r['walls']:.1f} |")
        if D >= 14 and arch == 'P0T':
            print(f"|  | └ 第 14 天 | | {sum(r['daily'][:14]):.0f} | {X('xp_farm'):.0f}（{lv(X('xp_farm'), 'farming')}） / {X('xp_fish'):.0f}（{lv(X('xp_fish'), 'fishing')}） / {X('xp_cook'):.0f}（{lv(X('xp_cook'), 'cooking')}） | {X('wallet'):.0f} | {X('cookbook'):.1f} | {X('fishdex'):.1f} | | | | | | | |")
    print('\n注：Fa / Fi / Co / Hs 为到达该级的均值日（— = 期内未到）；「Fi3 ≤ 第 2 天」是第 2 天结束前到 Fishing Lv3 的种子比例。')


if __name__ == '__main__':
    main()
