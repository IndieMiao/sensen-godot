#!/usr/bin/env python3
"""
p0_v1.py — P0 子集的七日账本复跑（审计 V1，2026-10-08，李白）

复用 round3 的 sim_v3.py（Cooking 轨、矿洞按层计费、首竿 / 首提 10 / 10、首做 XP 归 Cooking），
只把内容与规则收窄到 P0（方案 v2 §17.2.1，q(33)、q(36)–q(42)）：
  作物 8 种；鱼 7 种可钓（鲭鱼只在 Coast，P0 无 Coast；无鲇鱼、地区鱼）；Pond / River 两种模板；
  鱼竿 新手竿 + 芦苇竿；鱼饵只有蚯蚓；无鱼笼；料理 14 页（§7.14.0）；
  Homestead 封顶 Lv3；矿洞只有 1–2 层（A 局，每层 2 + 敲岩 2）；采集点无硬木、矿洞无石英；
  Cooking 升级不回体力（q(37)）；无旅行、无社交（客票 / 来访 / 帮工）；P0 农场田块 30 格（对照 40）。
不改 sim_v3.py 本身。

用法：
  python3 p0_v1.py                 # 全部情形，7 天 × 6 seed，输出 Markdown 到 stdout
  python3 p0_v1.py --days 14 --seeds 6
  python3 p0_v1.py --v2 --seeds 30  # 只跑 D：与蒙恬 V2 真实规则回放对齐的经济基线（q(54)）
"""
import argparse, copy, os, statistics, sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'round3-cooking-mine-npc', 'sim'))
import sim_v3 as S  # noqa: E402

P0_CROPS = ['radish', 'lettuce', 'herb', 'carrot', 'potato', 'chamomile', 'chili', 'tomato']
P0_FISH = ['crucian', 'carp', 'mullet', 'perch', 'bass', 'trout', 'koi']
P0_DISHES = ['grilled_crucian', 'grilled_fish', 'radish_salad', 'veggie_plate', 'carrot_cake',
             'herb_grilled_fish', 'salt_grilled_fish', 'fish_soup', 'pan_fried_fish', 'salted_potatoes', 'fruit_tea',
             'bass_tomato_stew', 'smoked_trout', 'fisher_stew']


def p0_config(plots=30, quartz_to_salt=False):
    cfg = S.base_config()
    cfg['crops'] = {k: v for k, v in cfg['crops'].items() if k in P0_CROPS}
    cfg['perennials'] = {}
    cfg['fish'] = {k: v for k, v in cfg['fish'].items() if k in P0_FISH}
    cfg['home_regional'] = ()
    cfg['sites'] = {'pond': cfg['sites']['pond'], 'river': cfg['sites']['river']}
    cfg['bait_price'] = {'worm': cfg['bait_price']['worm']}
    cfg['rods'] = {k: v for k, v in cfg['rods'].items() if k in ('starter', 'reed')}
    cfg['trap_slots'] = {99: 1}
    keep = set(P0_DISHES)
    cfg['dishes'] = {k: v for k, v in cfg['dishes'].items() if k in keep}
    assert len(cfg['dishes']) == 14, sorted(cfg['dishes'])
    tags = {}
    for t, ids in cfg['tags'].items():
        tags[t] = [i for i in ids if i in cfg['fish'] or i in cfg['crops'] or i in ('rock_salt', 'wild_herb')]
    cfg['tags'] = tags
    cfg['gather'] = {k: v for k, v in cfg['gather'].items() if k != 'hardwood'}
    e, mins, out = cfg['mine']['A']
    ores = {k: v for k, v in out.items() if k != 'quartz'}
    if quartz_to_salt:  # 旋钮 A（q(47)）：P0 第 2 层的石英并入岩盐
        ores['rock_salt'] = ores.get('rock_salt', 0) + out.get('quartz', 0)
    cfg['mine'] = {'A': (e, mins, ores)}
    cfg['plot_cap'] = lambda hs, n=plots: n
    cfg['p0_hs_cap'] = 3
    cfg['cook_levelup_energy'] = False
    return cfg


ARCH = {
    # §14.6 的目标玩家：早 15 分钟（收、播、采集），晚 30 分钟（20–25 竿、做菜、交委托）；第 3 天起隔日 1 局 A
    'P0T': dict(label='目标玩家（早 15 + 晚 30 分钟；§14.6 口径）', sessions=[(8 * 60, 15), (20 * 60, 30)],
                farm_energy=[110, 0], casts=[0, 25], gather=True, gather_morning_only=True, mine=[None, ('A', 1)], mine_odd_from3=True,
                cook_target=5, discover=1.5, worms=10, lures=0, tea='need', travel='none', friend=False, buy='balanced',
                requests=12, helper=0, meal_plan=True, pots=(3, 5)),
    'P5': dict(S.ARCHETYPES['P5'], label='5 分钟/日（20:00 单会话，20 格 + 10 竿，每 3 天 1 局 A）', lures=0, travel='none', requests=4, p0_seed_reserve=30),
    'P30C': dict(S.ARCHETYPES['P30C'], label='30 分钟/日（20:00 单会话，25 竿 + 110 体力，隔日 1 局 A）', lures=0, travel='none', helper=0, requests=12),
    'HEAVY': dict(S.ARCHETYPES['HEAVY'], label='重度（08:00 与 20:00 各 2 小时；P0 只有 1–2 层，两场各 1 局 A）', lures=0, travel='none',
                  friend=False, helper=0, mine=[('A', 1), ('A', 1)], tea='need', requests=20, p0_seed_reserve=120),
}


class P0Player(S.Player):
    def __init__(self, arch, cfg, rng):
        S.ARCHETYPES.setdefault(arch, ARCH[arch])
        super().__init__(arch, cfg, rng)
        self.a = ARCH[arch]
        self._session_idx = 0
        self._day_now = 1

    def add_xp(self, track, amount, oneoff=False):
        if track == 'cooking' and not self.cfg.get('cook_levelup_energy', True):
            bonus = self.add_energy_bonus
            self.add_energy_bonus = lambda n, kind: None if kind == 'achv' else bonus(n, kind)
            try:
                return super().add_xp(track, amount, oneoff)
            finally:
                self.add_energy_bonus = bonus
        return super().add_xp(track, amount, oneoff)

    def fish_site(self, city):
        if self.level('fishing') >= 4 and self.rod == 'reed':
            return 'river'
        return 'pond'

    def gather(self):
        if self.a.get('gather_morning_only') and (self.t % 1440) >= 12 * 60:
            return
        return super().gather()

    def mine(self, kind):
        if self.a.get('mine_odd_from3'):
            d = self.day()
            if d < 3 or d % 2 == 0:
                return False
        return super().mine(kind)

    def seed_reserve(self):
        # sim_v3 留 farm_energy × 2.5 的种子钱（30 分钟画像 275），是全量规则下的保守值；P0 按约一天的种子钱留（§14.6.1 每日 50–90）
        return self.a.get('p0_seed_reserve', 60)

    def try_upgrade(self):
        if self.hs >= self.cfg.get('p0_hs_cap', 10):
            return
        return super().try_upgrade()

    # —— V2 对齐（q(54)）：按蒙恬 server/tools/p0_week.ts 的机器人打法卖与买 ——
    def sell(self):
        if not self.a.get('v2align'):
            return super().sell()
        fk, ck = dict(S.FISH_KEEP), dict(S.CROP_KEEP)
        S.FISH_KEEP.update({k: 2 for k in fk})          # 每种鱼留 2 条做菜，其余卖
        S.CROP_KEEP.update({k: 3 for k in list(ck) + list(self.cfg['crops'])})   # 每种作物留 3 个
        try:
            return super().sell()
        finally:
            S.FISH_KEEP.clear(); S.FISH_KEEP.update(fk)
            S.CROP_KEEP.clear(); S.CROP_KEEP.update(ck)

    def purchases(self):
        if not self.a.get('v2align'):
            return super().purchases()
        # 蚯蚓：每天只在早场结束时补到 10 条（晚场 25 竿里前 10 竿挂饵），不再每场补到 2 倍
        lv, price, stock = self.cfg['bait_price']['worm']
        if (self.t % 1440) < 12 * 60 and self.level('fishing') >= lv:
            n = max(0, min(10 - self.inv['worm'], stock - self.bait_bought_today['worm']))
            if n > 0 and self.wallet - n * price >= self.cfg['wallet_floor'] + 60:
                self.pay(n * price, 'bait'); self.inv['worm'] += n; self.bait_bought_today['worm'] += n
        saved = self.a['worms']; self.a['worms'] = 0
        try:
            return super().purchases()
        finally:
            self.a['worms'] = saved

    def can_make(self, d):
        if self.hs >= self.cfg.get('p0_hs_cap', 10):
            saved = self.cfg.get('reserve_salt_for_homestead', True)
            self.cfg['reserve_salt_for_homestead'] = False
            try:
                return super().can_make(d)
            finally:
                self.cfg['reserve_salt_for_homestead'] = saved
        return super().can_make(d)


def run(arch, cfg, seed, days):
    import random
    rng = random.Random(seed)
    p = P0Player(arch, cfg, rng)
    p.first_session(12 * 60)
    snaps = []
    for day in range(1, days + 1):
        for idx, (mod, minutes) in enumerate(p.a['sessions']):
            t0 = (day - 1) * 1440 + mod
            if day == 1 and t0 < 12 * 60 + 30:
                continue
            p.session(idx, t0, minutes, day)
        rec = p.daily.get(day, Counter())
        snaps.append(dict(day=day, energy_spent=rec.get('energy', 0), farm_e=rec.get('energy_farm', 0), fish_e=rec.get('energy_fish', 0),
                          mine_e=rec.get('energy_mine', 0), meal=rec.get('meal', 0), walls=rec.get('walls', 0), sow_short=rec.get('sow_short', 0),
                          plots=rec.get('harvest_plots', 0),
                          xp_farm=p.xp['farming'], xp_fish=p.xp['fishing'], xp_cook=p.xp['cooking'],
                          lv_farm=p.level('farming'), lv_fish=p.level('fishing'), lv_cook=p.level('cooking'), hs=p.hs,
                          wallet=p.wallet, cookbook=len(p.cooked_once), fishdex=len(p.first_fish),
                          salt=p.mats['rock_salt'], three_slot=sum(1 for k in p.cooked_once if p.cfg['dishes'][k]['slots'] == 3)))
    return p, snaps


def first_day(ms, key, days):
    v = ms.get(key)
    return '—' if v is None or v > days else f'{v:.1f}'


def scenario(name, cfg_fn, archs, seeds, days, mutate=None):
    out = []
    for arch in archs:
        cfg = cfg_fn()
        a = dict(ARCH[arch])
        if mutate:
            mutate(a)
        ARCH_BACKUP = ARCH[arch]; ARCH[arch] = a
        runs = [run(arch, cfg, s, days) for s in range(seeds)]
        ARCH[arch] = ARCH_BACKUP
        mean = lambda f: statistics.mean(f(r) for r in runs)  # noqa: E731
        ms_keys = {k for p, _ in runs for k in p.milestones}
        ms = {k: statistics.mean([p.milestones.get(k, days + 1) for p, _ in runs]) for k in ms_keys}
        three = [next((s['day'] for s in sn if s['three_slot'] > 0), None) for _, sn in runs]
        three_day = statistics.mean([d if d else days + 1 for d in three])
        daily = [statistics.mean(sn[d]['energy_spent'] for _, sn in runs) for d in range(days)]
        last = lambda k: mean(lambda r: r[1][days - 1][k])  # noqa: E731
        meals = [u / mx for p, _ in runs for (u, m, mx) in p.p30_meal]
        meal_use = statistics.median(meals) if meals else None
        out.append(dict(arch=arch, label=a['label'], ms=ms, three_day=three_day, daily=daily,
                        xp_farm=last('xp_farm'), xp_fish=last('xp_fish'), xp_cook=last('xp_cook'),
                        lv_farm=last('lv_farm'), lv_fish=last('lv_fish'), lv_cook=last('lv_cook'), hs=last('hs'),
                        wallet=last('wallet'), cookbook=last('cookbook'), fishdex=last('fishdex'),
                        walls=statistics.mean(sum(s['walls'] for s in sn) for _, sn in runs),
                        sow_short=statistics.mean(sum(s['sow_short'] for s in sn) for _, sn in runs),
                        farm_e=statistics.mean(sum(s['farm_e'] for s in sn) for _, sn in runs), meal_use=meal_use))
    return name, out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--days', type=int, default=7)
    ap.add_argument('--seeds', type=int, default=6)
    ap.add_argument('--v2', action='store_true', help='只跑 D：V2 对齐的经济基线')
    args = ap.parse_args()
    D, N = args.days, args.seeds
    archs = ['P0T', 'P5', 'P30C', 'HEAVY']
    if args.v2:
        scens = [scenario('D · V2 对齐：旋钮 A（第 2 层石英并入岩盐）+ 机器人打法（每种鱼留 2、作物留 3，其余卖；每天补 10 条蚯蚓）',
                          lambda: p0_config(30, quartz_to_salt=True), ['P0T'], N, D, mutate=lambda a: a.update(v2align=True))]
    else:
        scens = [
        scenario('A · 基准：30 格田 + 材料链（采集 + 矿洞 1–2 层）', lambda: p0_config(30), archs, N, D),
        scenario('B · 对照：40 格田 + 材料链', lambda: p0_config(40), archs, N, D),
        scenario('C · 对照：30 格田、没有材料链（无采集、无矿洞）', lambda: p0_config(30), archs, N, D,
                 mutate=lambda a: a.update(gather=False, mine=None)),
        ]
    target = dict(daily=[115, 195, 218, 210, 238, 220, 238], xp_farm=750, xp_fish=1130, xp_cook=660, wallet=274)
    print(f'# P0 子集七日账本复跑（V1）· {D} 天 × {N} seed\n')
    print('§14.6 目标玩家（全量规则推演）：体力 115 / 195 / 218 / 210 / 238 / 220 / 238，合计 1,434；第 7 天 Farming 750（Lv6）、Fishing 1,130（Lv5）、Cooking 660（Lv6）、钱包约 274、Homestead Lv2 在第 5 天、Cooking Lv4 在第 4 天、首道 3 槽菜第 4 天。\n')
    for name, rows in scens:
        print(f'## {name}\n')
        print('| 画像 | 7 日体力（逐日） | 合计 | 与 §14.6 差 | Farming XP（Lv） | Fishing XP（Lv） | Cooking XP（Lv） | Homestead | 钱包 | Cookbook | Fish-dex | Fa2 / Fa3 / Fa4 / Fa5 | Fi2 / Fi3 / Fi4 / Fi5 | Co2 / Co3 / Co4 / Co5 / Co6 | Hs2 / Hs3 | 首道 3 槽菜 | 撞墙次数 | 播种没花完的体力 | 正餐前已用池（中位） |')
        print('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
        for r in rows:
            tot = sum(r['daily'][:7]); diff = (tot - sum(target['daily'])) / sum(target['daily']) * 100 if r['arch'] == 'P0T' else None
            ms = r['ms']
            three = '—' if r['three_day'] > D else f"{r['three_day']:.1f}"
            f = lambda k: first_day(ms, k, D)  # noqa: E731
            print(f"| {r['arch']} | {' / '.join(f'{x:.0f}' for x in r['daily'][:7])} | {tot:.0f} | {'' if diff is None else f'{diff:+.0f}%'} | "
                  f"{r['xp_farm']:.0f}（{r['lv_farm']:.1f}） | {r['xp_fish']:.0f}（{r['lv_fish']:.1f}） | {r['xp_cook']:.0f}（{r['lv_cook']:.1f}） | {r['hs']:.1f} | {r['wallet']:.0f} | "
                  f"{r['cookbook']:.1f} | {r['fishdex']:.1f} | {f('farming_lv2')} / {f('farming_lv3')} / {f('farming_lv4')} / {f('farming_lv5')} | "
                  f"{f('fishing_lv2')} / {f('fishing_lv3')} / {f('fishing_lv4')} / {f('fishing_lv5')} | "
                  f"{f('cooking_lv2')} / {f('cooking_lv3')} / {f('cooking_lv4')} / {f('cooking_lv5')} / {f('cooking_lv6')} | {f('hs_lv2')} / {f('hs_lv3')} | "
                  f"{three} | {r['walls']:.1f} | {r['sow_short']:.0f} | {'—' if r['meal_use'] is None else format(r['meal_use'], '.0%')} |")
        print()


if __name__ == '__main__':
    main()
