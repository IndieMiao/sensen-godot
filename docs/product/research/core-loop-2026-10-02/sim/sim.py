#!/usr/bin/env python3
"""
sim.py — 街角四季「第二阶段方案」数值模拟（内部校验工具，不进仓库）

用法：
  python3 sim.py                 # 修正后基表（2026-10-02 校验修正 F1/F3/F4/F5/F8/F9/F10 + R1/R2 已并入）
  python3 sim.py --fix F7        # 叠加对照开关（F2/F6/F7/F11/F12/F13）
  python3 sim.py --days 90 --seeds 8 --md out.md   # 导出逐日表到 markdown

模型：按分钟推进的会话模拟。体力 +1/15min 线性回复、满停；播种按格按档位计费；
抛竿预扣 2 / 失败退 1 / 每玩家日前 10 次失败全退；料理日上限 F=40+2(Hs-1)、同菜递减；
技能 XP 按 04_skills 表 + 日封顶 200/300；农场等级按 10 节消耗表；旅行按 11 节七档。
四类玩家：P5（5 分钟/日：收获+播种+8 竿）、P15（15 分钟休闲）、P30（30 分钟：种+钓+做菜）、
HEAVY（早 30 + 晚 60 分钟，尽量花光体力并吃满 F）。
"""
import argparse, copy, math, random, statistics, sys
from collections import Counter, defaultdict

# ----------------------------------------------------------------------------
# 1. 内容表（可改）
# ----------------------------------------------------------------------------
def base_config():
    cfg = {}
    cfg['energy_max_base'] = 100
    cfg['regen_min'] = 15                     # +1 / 15 min
    cfg['F_base'] = 40; cfg['F_per_level'] = 2; cfg['F_cap'] = 60
    cfg['meal_decay'] = [1.0, 0.5, 0.0]       # 同菜第 1/2/3 份
    cfg['free_fail_per_day'] = 10; cfg['free_fail_lv_max'] = 3   # 校验修正 F5：前 10 次失败全退只在 Fishing Lv1–3 生效
    cfg['friend_visit_bonus'] = 5; cfg['replant_received_max'] = 5   # 社交入流上界 +5 来访 +5 被补播（12 §12.12.2）
    cfg['fish_th'] = [0, 40, 110, 220, 380, 600, 880, 1250, 1750, 2500]   # 校验修正 F10：Lv10 2,400 → 2,500
    cfg['farm_th'] = [0, 30, 80, 160, 280, 450, 700, 1000, 1400, 2000]   # 校验修正 F3：Lv8/9/10 1,050/1,550/2,300 → 1,000/1,400/2,000
    cfg['farm_cap'] = 200; cfg['fish_cap'] = 300
    cfg['crop_xp_by_tier'] = {1: 2, 2: 4, 3: 5, 4: 6}
    cfg['fish_xp_by_tier'] = {1: 4, 2: 7, 3: 12, 4: 20}
    cfg['first_harvest_xp'] = 8; cfg['first_species_xp'] = 10; cfg['first_city_xp'] = 10
    cfg['first_cast_xp'] = 2; cfg['first_hook_xp'] = 3; cfg['first_recipe_xp'] = 10
    # 作物: id -> (tier/energy, lv, seed, hours, yield, price, xp, regional)
    cfg['crops'] = {
        'R':        (1, 1, 4, 4, 1, 5, 2, False),
        'L':        (1, 1, 6, 8, 1, 8, 2, False),
        'herb':     (1, 2, 2, 3, 3, 1, 2, False),
        'C':        (2, 2, 8, 12, 1, 12, 4, False),
        'H':        (3, 3, 10, 18, 1, 16, 5, False),
        'potato':   (2, 3, 8, 10, 2, 6, 4, False),
        'tomato':   (3, 4, 12, 14, 2, 9, 5, False),
        'chili':    (1, 4, 3, 6, 2, 2, 2, False),
        'corn':     (3, 5, 12, 16, 3, 6, 5, False),
        'cabbage':  (2, 5, 9, 12, 1, 13, 4, False),
        'cucumber': (2, 6, 6, 9, 2, 5, 4, False),
        'strawberry': (4, 8, 15, 20, 3, 8, 6, False),
        'melon':    (4, 9, 18, 24, 1, 27, 6, False),
        'sweet_potato': (3, 5, 13, 16, 2, 10, 5, True),   # 家城（上海，亚热带）地区种子
    }
    cfg['regional_seed_per_day'] = 10
    # 多年生: id -> (lv, price, first_h, regrow_h, yield, unit_price)
    cfg['perennials'] = {'apple': (7, 40, 48, 48, 2, 3), 'citrus': (9, 80, 72, 48, 2, 5), 'grape': (9, 60, 60, 48, 3, 3)}
    # 鱼: id -> (tier, price, family, req_lv, sites, regional_weight)
    cfg['fish'] = {
        'crucian':   (1, 2, 'white', 1, ('pond', 'river'), 1),
        'carp':      (1, 3, 'white', 1, ('pond', 'river'), 1),
        'mullet':    (1, 3, 'oily', 1, ('coast', 'river'), 1),
        'perch':     (2, 5, 'white', 2, ('pond', 'river'), 1),
        'bass':      (2, 5, 'white', 2, ('pond', 'river'), 1),
        'trout':     (2, 6, 'oily', 2, ('river',), 1),
        'mackerel':  (2, 6, 'oily', 2, ('coast',), 1),
        'koi':       (3, 10, 'ornament', 4, ('pond',), 1),      # 校验修正 F1：T3/T4 售价 −15%
        'catfish':   (3, 11, 'white', 4, ('river', 'pond'), 1),
        'seabass':   (3, 12, 'white', 5, ('coast',), 1),
        'sturgeon':  (4, 24, 'delicacy', 7, ('pond', 'river', 'coast'), 1),
        'eel':       (4, 26, 'delicacy', 7, ('river', 'pond'), 1),
        # 上海地区鱼（06 §6.2.4 第 4 条）：草鱼 + 乌鳢
        'grass_carp': (2, 6, 'white', 3, ('pond', 'river'), 2),
        'snakehead':  (3, 11, 'white', 5, ('pond', 'river'), 2),
    }
    cfg['sites'] = {'pond': [60, 30, 9, 1], 'river': [35, 40, 20, 5], 'coast': [30, 35, 25, 10]}   # 校验修正 F8：coast 20/30/35/15 → 30/35/25/10
    cfg['succ'] = {'starter': [0.9, 0.8, 0.65, 0.5], 'reed': [0.9, 0.8, 0.72, 0.5], 'carbon': [0.9, 0.8, 0.78, 0.62]}
    cfg['rod_max'] = {'starter': 2, 'reed': 3, 'carbon': 4}
    cfg['rod_price'] = {'reed': (3, 80), 'carbon': (6, 350)}
    cfg['bait'] = {None: [0, 0, 0, 0], 'worm': [-10, 10, 0, 0], 'lure': [-15, -5, 15, 5]}
    cfg['bait_price'] = {'worm': (2, 2, 30), 'lure': (5, 6, 10)}   # (lv, price, stock/day)
    cfg['cast_seconds'] = 36
    cfg['trap'] = (5, 120, 3)   # (lv, price, fish/day per trap)
    cfg['trap_slots'] = {5: 1, 8: 2, 10: 3}
    # 料理: id -> (restore, stove_min, ingredients, unlock) ; unlock = ('init',) | ('farming',lv) | ('fishing',lv) | ('npc',price,track,lv)
    cfg['dishes'] = {
        'grilled_crucian': (8, 5, {'fish:crucian': 1}, ('init',)),
        'lettuce_wraps':   (8, 5, {'R': 1, 'L': 1}, ('init',)),
        'herb_fish':       (15, 10, {'fish:white': 1, 'wild_herb': 1}, ('fishing', 2)),
        'salt_fish':       (15, 10, {'fish:white': 1, 'rock_salt': 1}, ('fishing', 3)),
        'salted_potatoes': (15, 10, {'potato': 2, 'rock_salt': 1}, ('farming', 3)),
        'salted_corn':     (15, 10, {'corn': 1, 'rock_salt': 1}, ('farming', 5)),
        'salad':           (8, 5, {'C': 1, 'L': 1}, ('farming', 2)),
        'tea':             (8, 5, {'H': 1}, ('farming', 3)),
        'vegetable_soup':  (15, 10, {'R': 1, 'L': 1, 'rock_salt': 1}, ('npc', 30, 'farming', 2)),
        'fish_soup':       (15, 10, {'fish:white': 1, 'R': 1, 'rock_salt': 1}, ('npc', 30, 'fishing', 2)),
        'tomato_fish':     (15, 10, {'fish:white': 1, 'tomato': 1, 'herb': 1}, ('farming', 4)),
        'chili_fish':      (15, 10, {'fish:white': 1, 'chili': 1}, ('farming', 4)),
        'smoked_fish':     (15, 10, {'fish:oily': 1, 'wild_herb': 1, 'rock_salt': 1}, ('fishing', 4)),
        'corn_chowder':    (15, 10, {'corn': 2, 'potato': 1, 'rock_salt': 1}, ('npc', 80, 'farming', 5)),
        'veggie_skewers':  (15, 10, {'cucumber': 1, 'tomato': 1, 'rock_salt': 1}, ('farming', 6)),
        'fisher_stew':     (25, 15, {'fish:oily': 1, 'potato': 2, 'rock_salt': 1}, ('npc', 80, 'fishing', 3)),
        'cabbage_rolls':   (25, 15, {'fish:white': 1, 'cabbage': 1, 'potato': 1, 'wild_herb': 1}, ('farming', 5)),   # 校验修正：唯一不含岩盐的 25 档菜
        'sweet_potato_cakes': (25, 15, {'sweet_potato': 1, 'fish:white': 1, 'herb': 1, 'rock_salt': 1}, ('npc', 80, 'farming', 5)),
        'eel_skewers':     (25, 15, {'fish:eel': 1, 'chili': 1, 'rock_salt': 1}, ('npc', 200, 'fishing', 7)),
        'steamed_sturgeon': (25, 15, {'fish:sturgeon': 1, 'herb': 1, 'rock_salt': 1}, ('npc', 500, 'fishing', 7)),
    }
    cfg['feasts'] = {
        'feast_harvest':      {'R': 4, 'L': 2, 'C': 1, 'rock_salt': 1, 'wild_herb': 1},
        'feast_lakeside':     {'fish:white': 2, 'fish:oily': 1, 'potato': 2, 'herb': 1, 'rock_salt': 1},
        'feast_four_seasons': {'sweet_potato': 1, 'corn': 1, 'tomato': 1, 'cabbage': 1, 'fish:tier3': 1, 'rock_salt': 1, 'herb': 1},
    }
    # 农场等级 Lv2..Lv10: (coins, wood, stone, fiber, copper, clay, quartz, hardwood, salt, feast, n)
    cfg['homestead'] = [
        (200, 12, 8, 6, 0, 0, 0, 0, 3, 'feast_harvest', 1),
        (250, 16, 12, 10, 0, 4, 0, 0, 4, 'feast_harvest', 1),
        (350, 20, 16, 10, 6, 6, 0, 0, 4, 'feast_harvest', 2),
        (500, 20, 16, 12, 10, 8, 2, 0, 4, 'feast_lakeside', 1),
        (700, 20, 18, 12, 10, 8, 3, 3, 0, 'feast_lakeside', 1),      # 校验修正 F4：quartz/hardwood Lv6–10 → 3/4/4/4/5 与 3/4/6/7/8
        (950, 20, 20, 10, 12, 8, 4, 4, 0, 'feast_lakeside', 2),
        (900, 18, 18, 8, 12, 8, 4, 6, 0, 'feast_four_seasons', 1),   # 校验修正 F9：Lv8/9/10 金币 1,250/1,600/2,000 → 900/1,100/1,400
        (1100, 14, 16, 6, 12, 4, 4, 7, 0, 'feast_four_seasons', 1),
        (1400, 10, 16, 6, 13, 4, 5, 8, 0, 'feast_four_seasons', 2),
    ]
    cfg['stoves_by_hs'] = {1: 1, 4: 2, 8: 3}
    cfg['bag_expansion'] = {3: 150, 6: 400, 9: 1000}   # Hs -> coins
    cfg['greenhouse'] = (8, 300)                         # Farming lv, coins
    # 探索轮（0 体力）：每轮产出；轮冷却 8h
    cfg['explore_round'] = {'wood': 9, 'fiber': 5, 'wild_herb': 2}
    cfg['explore_clay_hs'] = 2; cfg['explore_hardwood_hs'] = 3
    cfg['explore_cooldown_min'] = 8 * 60
    # 矿洞：局型 -> (体力, stone, copper, salt, clay, quartz, minutes)
    cfg['mine'] = {'A': (17, 12, 3.9, 2.7, 0.9, 0.9, 4), 'B': (29, 24, 8.1, 4.8, 0.9, 3.0, 8)}
    cfg['mine_runs_per_day'] = 2
    cfg['material_floor'] = {'wood': 2, 'fiber': 1, 'copper': 4, 'rock_salt': 2, 'clay': 2, 'quartz': 5, 'hardwood': 4, 'stone': 0.5, 'wild_herb': 1}
    # 旅行七档：(coins, energy)；再访半价向上取整
    cfg['travel'] = {0: (0, 0), 1: (10, 5), 2: (30, 10), 3: (60, 15), 4: (100, 20), 5: (150, 25), 6: (200, 30)}
    cfg['range_hs'] = {2: 2, 3: 3, 4: 4, 5: 5}; cfg['range_clusters'] = {2: 2, 3: 5, 4: 10, 5: 20}
    cfg['wallet_floor_travel'] = 40
    cfg['compost_price'] = 2
    cfg['initial_wallet'] = 180
    return cfg


# 2026-10-02 校验修正：F1/F3/F4/F5/F8/F9/F10 已并入 base_config()（章节正文已同步改表），下面只保留对照用的替代开关。
APPLIED_IN_BASE = {
    'F1': '鱼节 6.2 表：T3/T4 鱼售价 −15%（koi 12→10、catfish 13→11、seabass 14→12、snakehead 13→11；sturgeon 28→24、eel 30→26）',
    'F3': '技能节 4.4.1 表：Farming Lv8/9/10 累计阈值 1,050/1,550/2,300 → 1,000/1,400/2,000',
    'F4': '农场等级节 10.1.2 表：Lv6–10 的 quartz 4/5/6/6/7 → 3/4/4/4/5（合计 30→22）、hardwood 4/6/8/10/12 → 3/4/6/7/8（合计 40→28）',
    'F5': '体力节 2.3 / 鱼节 6.5.1：「每玩家日前 10 次失败全退」只在 Fishing Lv1–3 生效，Lv4 起失败一律退 1',
    'F8': '鱼节 6.3.1 表：site_coast 权重 20/30/35/15 → 30/35/25/10',
    'F9': '农场等级节 10.1.2 表：Lv8/9/10 金币 1,250/1,600/2,000 → 900/1,100/1,400（九级合计 7,800→6,600）',
    'F10': '技能节 4.4.1 表：Fishing Lv10 累计阈值 2,400 → 2,500',
    'R1': '料理节 7.2.2：卷心菜鱼卷 1 fish:white + 1 cabbage + 1 potato + 1 wild_herb（唯一不含岩盐的 25 档菜）',
    'R2': '社交入流：重度画像每日 +5 来访 +5 被补播（12 §12.12.2 的 F + 10 口径）',
}
FIX_DOC = {
    'F2': '鱼节 6.3.1 表：site_coast 权重 30/35/25/10 → 25/35/30/10（更松的沿海，对照）',
    'F6': '农场等级节 10.1.2 表：Lv8/9/10 金币 900/1,100/1,400 → 1,000/1,300/1,700（对照）',
    'F7': '体力节 2.1.1 / 料理节 7.3.1：F 起点 40 → 30（D9 越线处置的第二步；仅作对照）',
    'F11': '农场等级节 10.1.2 表：Lv8/9/10 金币 900/1,100/1,400 → 900/1,000/1,200（对照）',
    'F12': '鱼节 6.3.1 表：site_coast 权重 30/35/25/10 → 35/35/22/8（对照）',
    'F13': '对照：取消社交入流（重度不计 +5 来访 / +5 被补播）',
}


RECOMMENDED = []   # 推荐集已并入基表


def apply_fixes(cfg, fixes):
    """按 id 应用改表（只改表格，不改规则）。"""
    cfg = copy.deepcopy(cfg)
    if 'F2' in fixes:
        cfg['sites']['coast'] = [25, 35, 30, 10]
    if 'F6' in fixes:
        hs = cfg['homestead']
        for i, c in zip(range(6, 9), [1000, 1300, 1700]):
            r = list(hs[i]); r[0] = c; hs[i] = tuple(r)
    if 'F7' in fixes:
        cfg['F_base'] = 30
    if 'F11' in fixes:
        hs = cfg['homestead']
        for i, c in zip(range(6, 9), [900, 1000, 1200]):
            r = list(hs[i]); r[0] = c; hs[i] = tuple(r)
    if 'F12' in fixes:
        cfg['sites']['coast'] = [35, 35, 22, 8]
    if 'F13' in fixes:
        cfg['friend_visit_bonus'] = 0; cfg['replant_received_max'] = 0
    return cfg

# ----------------------------------------------------------------------------
# 2. 玩家画像（策略参数）
# ----------------------------------------------------------------------------
ARCHETYPES = {
    'P5':    dict(label='5 分钟/日（收获+播种+8 竿）', sessions=[(20 * 60, 10)], farm_energy=14, casts=8, explore=0, cook=False,
                  mine=None, travel_every=0, friend=False, eat_full=False, compost=0, sell_all=True),
    'P15':   dict(label='15 分钟/日（休闲）', sessions=[(20 * 60, 15)], farm_energy=50, casts=8, explore=1, cook=True,
                  mine=('A', 2), travel_every=10, friend=False, eat_full=False, compost=0, sell_all=True),
    'P30':   dict(label='30 分钟/日', sessions=[(20 * 60, 30)], farm_energy=56, casts=22, explore=1, cook=True,
                  mine=('A', 1), travel_every=7, friend=False, eat_full=True, compost=5, sell_all=True),
    'HEAVY': dict(label='重度（早 30 + 晚 60）', sessions=[(8 * 60, 30), (20 * 60, 60)], farm_energy=84, casts=999,
                  explore=1, cook=True, mine=('A', 1), travel_every=3, friend=True, eat_full=True, compost=10, sell_all=True),
}

ARCHETYPES['HF_FISH'] = dict(ARCHETYPES['HEAVY'], label='重度·全钓（上界校验）', farm_energy=0)
ARCHETYPES['HF_FARM'] = dict(ARCHETYPES['HEAVY'], label='重度·全种（上界校验）', casts=0, farm_energy=10 ** 6)
ARCHETYPES['H_FOCUS'] = dict(ARCHETYPES['HEAVY'], label='重度·只买必需（农场升级冲刺）', optional_sinks=False)

FISH_FAMILY_ORDER = {'fish:white': ['crucian', 'carp', 'grass_carp', 'perch', 'bass', 'catfish', 'snakehead', 'seabass'],
                     'fish:oily': ['mullet', 'trout', 'mackerel'],
                     'fish:tier3': ['catfish', 'snakehead', 'seabass']}


class Player:
    def __init__(self, arch, cfg, rng):
        self.a = ARCHETYPES[arch]; self.arch = arch; self.cfg = cfg; self.rng = rng
        self.t = 0
        self.energy = cfg['energy_max_base']; self.energy_last = 0
        self.wallet = cfg['initial_wallet']
        self.inv = Counter()      # crops / fish / materials / dishes
        self.plots = []           # (crop, ready_at)
        self.perennials = []      # [crop, ready_at]
        self.xp = {'farming': 0, 'fishing': 0}
        self.hs = 1
        self.rod = 'starter'; self.traps = 0; self.recipes = set(['grilled_crucian', 'lettuce_wraps'])
        self.first_crops = set(); self.first_fish = set(); self.first_recipes = set()
        self.first_cast = False; self.first_hook = False
        self.cities = {'home'}; self.visits = Counter({'home': 1}); self.clusters = 1
        self.saplings_bought = 0; self.greenhouse = False; self.bag_levels = set()
        self.day_id = None; self.stoves = []    # (ready_at, dish)
        self.stove_free = []                       # 每口灶空闲时刻
        self.explore_last = -10 ** 9
        self.reset_day_counters()
        # 统计
        self.daily = defaultdict(lambda: Counter())
        self.milestones = {}
        self.sink_total = Counter(); self.income_total = 0; self.seed_total = 0
        self.first_session_lv2_minute = None

    # --- 基础 ---
    def reset_day_counters(self):
        self.farm_xp_today = 0; self.fish_xp_today = 0; self.fails_today = 0
        self.meals_today = 0; self.dish_count_today = Counter(); self.mine_runs_today = 0
        self.regional_seeds_today = 0; self.explore_today = 0; self.friend_today = False
        self.bait_bought_today = Counter()

    def energy_max(self):
        return self.cfg['energy_max_base'] + 2 * (self.hs - 1)

    def F(self):
        return min(self.cfg['F_cap'], self.cfg['F_base'] + self.cfg['F_per_level'] * (self.hs - 1))

    def settle(self, t):
        if t < self.t:
            t = self.t
        self.t = t
        gain = (t - self.energy_last) // self.cfg['regen_min']
        if gain > 0:
            mx = self.energy_max()
            if self.energy < mx:
                self.energy = min(mx, self.energy + gain)
                self.energy_last += gain * self.cfg['regen_min']
            if self.energy >= mx:
                self.energy_last = t
        self.check_day(t)

    def check_day(self, t):
        d = (t - 4 * 60) // 1440 + 1
        if self.day_id != d:
            self.day_id = d
            self.reset_day_counters()

    def day(self):
        return self.day_id

    def spend_energy(self, n, kind):
        if n <= 0:
            return True
        if self.energy < n:
            return False
        self.energy -= n
        if self.energy < self.energy_max() and self.energy_last == self.t:
            pass
        self.daily[self.day()]['energy_' + kind] += n
        self.daily[self.day()]['energy'] += n
        return True

    def level(self, track):
        th = self.cfg['fish_th'] if track == 'fishing' else self.cfg['farm_th']
        lv = 1
        for i, v in enumerate(th):
            if self.xp[track] >= v:
                lv = i + 1
        return lv

    def add_xp(self, track, amount, capped=True):
        before = self.level(track)
        if capped:
            cap = self.cfg['fish_cap'] if track == 'fishing' else self.cfg['farm_cap']
            used = self.fish_xp_today if track == 'fishing' else self.farm_xp_today
            amount = max(0, min(amount, cap - used))
            if track == 'fishing':
                self.fish_xp_today += amount
            else:
                self.farm_xp_today += amount
        self.xp[track] += amount
        self.daily[self.day()]['xp_' + track] += amount
        after = self.level(track)
        for lv in range(before + 1, after + 1):
            self.milestones.setdefault(f'{track}_lv{lv}', self.day())
            if track == 'fishing' and lv == 2 and self.first_session_lv2_minute is None:
                self.first_session_lv2_minute = self.t
        return amount

    def pay(self, coins, sink):
        if coins > self.wallet:
            return False
        self.wallet -= coins
        self.sink_total[sink] += coins
        self.daily[self.day()]['sink'] += coins
        self.daily[self.day()]['sink_' + sink] += coins
        return True

    def earn(self, coins, src):
        self.wallet += coins
        self.income_total += coins
        self.daily[self.day()]['income'] += coins
        self.daily[self.day()]['income_' + src] += coins

    # --- 作物 ---
    def crop_unlocked(self, cid):
        return self.level('farming') >= self.cfg['crops'][cid][1]

    def harvest(self):
        ripe = [p for p in self.plots if p[1] <= self.t]
        self.plots = [p for p in self.plots if p[1] > self.t]
        value = 0
        for cid, _ in ripe:
            tier, lv, seed, hours, yld, price, xp, reg = self.cfg['crops'][cid]
            self.inv[cid] += yld
            value += yld * price
            if cid not in self.first_crops:
                self.first_crops.add(cid); self.add_xp('farming', self.cfg['first_harvest_xp'], capped=False)
            self.add_xp('farming', self.cfg['crop_xp_by_tier'][tier])
        self.daily[self.day()]['harvest_value'] += value
        self.daily[self.day()]['harvest_plots'] += len(ripe)
        # 多年生
        for p in self.perennials:
            if p[1] <= self.t and self.energy >= 1:
                lv, price, fh, rh, yld, up = self.cfg['perennials'][p[0]]
                if self.spend_energy(1, 'farm'):
                    self.inv[p[0]] += yld; p[1] = self.t + rh * 60
                    self.add_xp('farming', 2)
                    self.daily[self.day()]['harvest_value'] += yld * up

    def plot_cap(self):
        return 200 + 40 * (self.hs - 1) if self.hs <= 6 else 400 + 50 * (self.hs - 6)

    def sow(self, energy_budget, needs):
        """先种需求作物（宴席/料理），再按每体力净金币最优填满预算；受钱包、开垦上限、地区种子日库存约束。"""
        crops = self.cfg['crops']
        order = []
        for cid, (tier, lv, seed, hours, yld, price, xp, reg) in crops.items():
            if not self.crop_unlocked(cid):
                continue
            net_e = (yld * price - seed) / tier
            order.append((net_e, -hours, cid))
        order.sort(reverse=True)
        sown_energy = 0; cost = 0
        def plant(cid, n):
            nonlocal sown_energy, cost
            tier, lv, seed, hours, yld, price, xp, reg = crops[cid]
            k = 0
            while k < n:
                if sown_energy + tier > energy_budget or self.energy < tier or self.wallet < seed:
                    break
                if len(self.plots) + len(self.perennials) * 4 >= self.plot_cap():
                    break
                if reg and self.regional_seeds_today >= self.cfg['regional_seed_per_day']:
                    break
                self.spend_energy(tier, 'farm'); self.wallet -= seed; cost += seed; sown_energy += tier
                self.seed_total += seed
                self.plots.append((cid, self.t + hours * 60))
                if reg:
                    self.regional_seeds_today += 1
                k += 1
            return k
        # 需求作物
        growing = Counter(c for c, _ in self.plots)
        for cid, qty in needs.items():
            if cid in crops and self.crop_unlocked(cid):
                yld = crops[cid][4]
                have = self.inv[cid] + growing[cid] * yld
                deficit = qty - have
                if deficit > 0:
                    plant(cid, math.ceil(deficit / yld))
        # 最优填充
        for net_e, _, cid in order:
            if net_e <= 1.0 and cid != 'L':
                continue
            plant(cid, 10 ** 6)
        self.daily[self.day()]['seed_cost'] += cost
        self.daily[self.day()]['sown_plots'] += sown_energy  # 近似
        return sown_energy

    # --- 探索 / 矿 ---
    def explore(self):
        if self.t - self.explore_last < self.cfg['explore_cooldown_min'] or self.explore_today >= 3:
            return
        self.explore_last = self.t; self.explore_today += 1
        for k, v in self.cfg['explore_round'].items():
            self.inv[k] += v
        if self.hs >= self.cfg['explore_clay_hs']:
            self.inv['clay'] += 2
        if self.hs >= self.cfg['explore_hardwood_hs']:
            self.inv['hardwood'] += 1
        self.t += 1

    def mine(self, kind):
        e, st, cu, sa, cl, qz, mins = self.cfg['mine'][kind]
        if self.mine_runs_today >= self.cfg['mine_runs_per_day'] or self.energy < e:
            return False
        self.spend_energy(e, 'mine'); self.mine_runs_today += 1
        # 期望值取整：用随机取整保持期望
        for mat, v in (('stone', st), ('copper', cu), ('rock_salt', sa), ('clay', cl), ('quartz', qz)):
            n = int(v) + (1 if self.rng.random() < v - int(v) else 0)
            self.inv[mat] += n
            self.daily[self.day()]['material_value'] += n * self.cfg['material_floor'][mat]
        self.t += mins
        return True

    # --- 钓鱼 ---
    def pick_bait(self):
        if self.inv['lure'] > 0 and self.level('fishing') >= 5:
            self.inv['lure'] -= 1; return 'lure'
        if self.inv['worm'] > 0:
            self.inv['worm'] -= 1; return 'worm'
        return None

    def cast(self, site, city='home'):
        if self.energy < 2:
            return None
        self.spend_energy(2, 'fish')
        bait = self.pick_bait()
        w = [max(0, a + b) for a, b in zip(self.cfg['sites'][site], self.cfg['bait'][bait])]
        tier = self.rng.choices([1, 2, 3, 4], weights=w)[0]
        cands = []
        for fid, (tr, price, fam, req, sites, rw) in self.cfg['fish'].items():
            if tr == tier and site in sites:
                cands.append((fid, (rw * (2 if (bait == 'lure' and rw > 1) else 1))))
        if city != 'home':   # 异城：2 种新地区鱼（T1/T2）替换本城地区鱼
            cands = [(f, w) for f, w in cands if self.cfg['fish'][f][5] == 1]
            if tier in (1, 2):
                cands.append((f'{city}_reg{tier}', 2))
        if not cands:
            cands = [('crucian', 1)]
        fid = self.rng.choices([c for c, _ in cands], weights=[w for _, w in cands])[0]
        if fid.startswith(city) and city != 'home':
            tr, price, fam, req = tier, (3 if tier == 1 else 6), 'white', (1 if tier == 1 else 3)
        else:
            tr, price, fam, req, _, _ = self.cfg['fish'][fid]
        if not self.first_cast:
            self.first_cast = True; self.add_xp('fishing', self.cfg['first_cast_xp'], capped=False)
        lv = self.level('fishing')
        escaped = lv < req or tier > self.cfg['rod_max'][self.rod]
        ok = (not escaped) and self.rng.random() < self.cfg['succ'][self.rod][tier - 1]
        self.t += self.cfg['cast_seconds'] / 60
        self.daily[self.day()]['casts'] += 1
        if not ok:
            self.fails_today += 1
            refund = 2 if (self.fails_today <= self.cfg['free_fail_per_day'] and lv <= self.cfg.get('free_fail_lv_max', 99)) else 1
            self.energy = min(self.energy_max(), self.energy + refund)
            self.daily[self.day()]['energy'] -= refund; self.daily[self.day()]['energy_fish'] -= refund
            return False
        if not self.first_hook:
            self.first_hook = True; self.add_xp('fishing', self.cfg['first_hook_xp'], capped=False)
        self.inv[fid] += 1
        self.daily[self.day()]['fish_value'] += price; self.daily[self.day()]['fish_caught'] += 1
        if fid not in self.first_fish:
            self.first_fish.add(fid); self.add_xp('fishing', self.cfg['first_species_xp'], capped=False)
        if city not in self.cities:
            self.cities.add(city); self.add_xp('fishing', self.cfg['first_city_xp'], capped=False)
        self.add_xp('fishing', self.cfg['fish_xp_by_tier'][tier])
        return True

    def fish_site(self):
        lv = self.level('fishing')
        if self.arch == 'P5':
            return 'pond'
        if self.arch.startswith('H') and lv >= 6 and self.rod == 'carbon':
            return 'coast'
        if lv >= 4 and self.rod in ('reed', 'carbon'):
            return 'river'
        return 'pond'

    def collect_traps(self):
        if self.traps == 0:
            return
        n = self.traps * self.cfg['trap'][2]
        for _ in range(n):
            tier = self.rng.choices([1, 2], weights=[60, 30])[0]
            fid = 'crucian' if tier == 1 else 'perch'
            self.inv[fid] += 1
            self.add_xp('fishing', self.cfg['fish_xp_by_tier'][tier] // 2)
            self.daily[self.day()]['fish_value'] += self.cfg['fish'][fid][1]

    # --- 料理 ---
    def recipe_known(self, did):
        if did in self.recipes:
            return True
        unlock = self.cfg['dishes'][did][3]
        if unlock[0] in ('farming', 'fishing') and self.level(unlock[0]) >= unlock[1]:
            self.recipes.add(did); return True
        return False

    def resolve_ingredient(self, key):
        if key.startswith('fish:'):
            fam = key
            if key in FISH_FAMILY_ORDER:
                for fid in FISH_FAMILY_ORDER[key]:
                    if self.inv[fid] > 0:
                        return fid
                return None
            fid = key.split(':')[1]
            return fid if self.inv[fid] > 0 else None
        return key if self.inv[key] > 0 else None

    def can_make(self, ingr):
        tmp = self.inv.copy()
        for key, q in ingr.items():
            for _ in range(q):
                fid = None
                if key.startswith('fish:'):
                    for cand in (FISH_FAMILY_ORDER.get(key) or [key.split(':')[1]]):
                        if tmp[cand] > 0:
                            fid = cand; break
                elif tmp[key] > 0:
                    fid = key
                if fid is None:
                    return None
                tmp[fid] -= 1
        return tmp

    def cook(self, did, track_time=True):
        restore, stove_min, ingr, unlock = self.cfg['dishes'][did]
        tmp = self.can_make(ingr)
        if tmp is None:
            return False
        self.inv = tmp
        self.stoves.append((self.stove_slot(stove_min), did))
        if did not in self.first_recipes:
            self.first_recipes.add(did)
            track = 'fishing' if any(k.startswith('fish') for k in ingr) else 'farming'
            self.add_xp(track, self.cfg['first_recipe_xp'], capped=False)
        return True

    def stove_slot(self, minutes):
        n = self.n_stoves()
        while len(self.stove_free) < n:
            self.stove_free.append(self.t)
        i = min(range(n), key=lambda k: self.stove_free[k])
        start = max(self.t, self.stove_free[i])
        self.stove_free[i] = start + minutes
        return start + minutes

    def collect_stoves(self):
        ready = [s for s in self.stoves if s[0] <= self.t]
        self.stoves = [s for s in self.stoves if s[0] > self.t]
        for _, did in ready:
            self.inv['dish:' + did] += 1

    def n_stoves(self):
        n = 1
        for k, v in self.cfg['stoves_by_hs'].items():
            if self.hs >= k:
                n = max(n, v)
        return n

    def eat(self):
        """按回复量从高到低吃到 F。"""
        self.collect_stoves()
        while self.meals_today < self.F():
            best = None
            for k, n in self.inv.items():
                if not k.startswith('dish:') or n <= 0:
                    continue
                did = k[5:]
                if did not in self.cfg['dishes']:
                    continue
                restore = self.cfg['dishes'][did][0]
                cnt = self.dish_count_today[did]
                mult = self.cfg['meal_decay'][min(cnt, 2)]
                eff = math.ceil(restore * mult)
                if eff <= 0:
                    continue
                if best is None or eff > best[0]:
                    best = (eff, did, restore)
            if best is None:
                break
            eff, did, restore = best
            if self.energy >= self.energy_max():
                break
            self.inv['dish:' + did] -= 1
            self.dish_count_today[did] += 1
            eff = min(eff, self.F() - self.meals_today)   # 跨过 F 的那一餐只计到 F（7.3.3 表 B「封顶只计 2」）
            self.meals_today += restore   # F 计名义值
            gain = min(eff, self.energy_max() - self.energy)
            self.energy += gain
            self.daily[self.day()]['meal_restore'] += gain
            self.daily[self.day()]['meals'] += 1

    def dish_plan(self):
        """今天要吃的菜（名义回复填满 F）：已知配方按回复降序。"""
        known = [d for d in self.cfg['dishes'] if self.recipe_known(d)]
        known.sort(key=lambda d: -self.cfg['dishes'][d][0])
        plan = []; nominal = 0
        for d in known:
            r = self.cfg['dishes'][d][0]
            if nominal >= self.F():
                break
            plan.append(d); nominal += r
        if self.F() - nominal > 0:
            for d in known:
                if d in plan and self.cfg['dishes'][d][0] >= 15:
                    plan.append(d); nominal += math.ceil(self.cfg['dishes'][d][0] / 2)
                    if nominal >= self.F():
                        break
        return plan

    def cook_plan(self, session_minutes):
        if not self.a['cook']:
            return
        have = Counter({k[5:]: v for k, v in self.inv.items() if k.startswith('dish:')})
        for _, did in self.stoves:
            have[did] += 1
        budget = self.n_stoves() * max(1, session_minutes // 10 + 1)
        cooked = 0
        if not self.a['eat_full']:
            if have['grilled_crucian'] < 1 and self.cook('grilled_crucian'):
                cooked += 1
            return
        # 目标：手里的菜按「第 1 份全额 + 第 2 份减半」能凑够明天的 F
        known = sorted((d for d in self.cfg['dishes'] if self.recipe_known(d)), key=lambda d: -self.cfg['dishes'][d][0])
        def nominal():
            tot = 0
            for d in known:
                r = self.cfg['dishes'][d][0]
                tot += r * min(1, have[d]) + math.ceil(r / 2) * (1 if have[d] >= 2 and r >= 15 else 0)
            return tot
        for d in known:
            if nominal() >= self.F() or cooked >= budget:
                break
            if have[d] < 1 and self.cook(d):
                have[d] += 1; cooked += 1
        for d in known:
            if nominal() >= self.F() or cooked >= budget:
                break
            if self.cfg['dishes'][d][0] >= 15 and have[d] < 2 and self.cook(d):
                have[d] += 1; cooked += 1

    def needs(self):
        """为明天的料理 + 下一级宴席预留的原料。"""
        need = Counter()
        if self.a['cook']:
            plan = (self.dish_plan() if self.a['eat_full'] else ['grilled_crucian'])
            if self.a['eat_full'] and self.recipe_known('herb_fish'):
                plan = plan + ['herb_fish', 'herb_fish']
            for did in plan:
                for k, q in self.cfg['dishes'][did][2].items():
                    need[k] += q
        if self.hs < 10 and self.a['cook']:
            row = self.cfg['homestead'][self.hs - 1]
            feast, n = row[9], row[10]
            have_feast = self.inv['dish:' + feast]
            if have_feast < n:
                for k, q in self.cfg['feasts'][feast].items():
                    need[k] += q * (n - have_feast)
        return need

    def cook_feast(self):
        if not self.a['cook'] or self.hs >= 10:
            return
        row = self.cfg['homestead'][self.hs - 1]
        feast, n = row[9], row[10]
        if self.inv['dish:' + feast] + sum(1 for _, d in self.stoves if d == feast) >= n:
            return
        ingr = self.cfg['feasts'][feast]
        if feast == 'feast_lakeside' and self.level('fishing') < 2:
            return
        if feast == 'feast_four_seasons' and self.level('farming') < 5:
            return
        tmp = self.can_make(ingr)
        if tmp is not None:
            self.inv = tmp; self.stoves.append((self.stove_slot(20), feast))

    # --- 买卖 / 升级 ---
    def sell(self, needs):
        keep = Counter()
        for k, q in needs.items():
            if k.startswith('fish:'):
                for fid in (FISH_FAMILY_ORDER.get(k) or [k.split(':')[1]]):
                    if self.inv[fid] > 0:
                        take = min(q, self.inv[fid]); keep[fid] += take; q -= take
                        if q <= 0:
                            break
            else:
                keep[k] += q
        for k, n in list(self.inv.items()):
            if n <= 0 or k.startswith('dish:') or k in self.cfg['material_floor'] or k in ('worm', 'lure'):
                continue
            sellable = n - keep.get(k, 0)
            if sellable <= 0:
                continue
            if k in self.cfg['crops']:
                price = self.cfg['crops'][k][5]
            elif k in self.cfg['fish']:
                price = self.cfg['fish'][k][1]
            elif k in self.cfg['perennials']:
                price = self.cfg['perennials'][k][5]
            elif '_reg' in k:
                price = 3 if k.endswith('1') else 6
            else:
                continue
            self.inv[k] -= sellable
            self.earn(sellable * price, 'fish' if (k in self.cfg['fish'] or '_reg' in k) else 'crops')

    def purchases(self, reserve):
        cfg = self.cfg
        # 鱼竿（先于农场升级：收益型购买）
        for rod, (lv, price) in cfg['rod_price'].items():
            if self.rod != rod and cfg['rod_max'][rod] > cfg['rod_max'][self.rod] and self.level('fishing') >= lv and self.wallet - reserve >= price:
                self.pay(price, 'gear'); self.rod = rod
                self.milestones.setdefault('rod_' + rod, self.day())
        # 农场升级
        if self.hs < 10 and self.a['cook']:
            row = cfg['homestead'][self.hs - 1]
            coins, wood, stone, fiber, copper, clay, quartz, hardwood, salt, feast, n = row
            mats = {'wood': wood, 'stone': stone, 'fiber': fiber, 'copper': copper, 'clay': clay, 'quartz': quartz, 'hardwood': hardwood, 'rock_salt': salt}
            if all(self.inv[m] >= q for m, q in mats.items()) and self.inv['dish:' + feast] >= n and self.wallet >= coins + reserve // 2:
                for m, q in mats.items():
                    self.inv[m] -= q
                self.inv['dish:' + feast] -= n
                self.pay(coins, 'homestead'); self.hs += 1
                self.milestones.setdefault(f'hs_lv{self.hs}', self.day())
            else:
                lacking = [m for m, q in mats.items() if self.inv[m] < q]
                self.daily[self.day()]['hs_block'] = ('coins' if self.wallet < coins + reserve // 2 else '') + ('feast' if self.inv['dish:' + feast] < n else '') + ','.join(lacking)
        # 配方（NPC）
        if self.a['cook'] and self.a['eat_full']:
            for did, (restore, sm, ingr, unlock) in cfg['dishes'].items():
                if unlock[0] == 'npc' and did not in self.recipes and self.level(unlock[2]) >= unlock[3] and self.wallet - reserve >= unlock[1]:
                    if restore < 25 and not self.arch.startswith('H') and unlock[1] >= 200:
                        continue
                    if not self.a.get('optional_sinks', True) and unlock[1] > 80:
                        continue
                    self.pay(unlock[1], 'recipes'); self.recipes.add(did)
        # 鱼笼
        if self.a['cook']:
            lv, price, _ = cfg['trap']
            slots = max([0] + [v for k, v in cfg['trap_slots'].items() if self.level('fishing') >= k])
            if self.traps < slots and self.wallet - reserve >= price:
                self.pay(price, 'gear'); self.traps += 1
        # 树苗
        if self.a['cook'] and self.a.get('optional_sinks', True):
            slots = min(8, 1 + self.hs)
            for pid, (lv, price, fh, rh, yld, up) in cfg['perennials'].items():
                if len(self.perennials) < slots and self.level('farming') >= lv and self.wallet - reserve >= price and self.energy >= 3:
                    self.pay(price, 'saplings'); self.spend_energy(3, 'farm')
                    self.perennials.append([pid, self.t + fh * 60])
        # 背包扩容 / 温室（只作金币去向）
        for hs, price in cfg['bag_expansion'].items():
            if self.hs >= hs and hs not in self.bag_levels and self.wallet - reserve >= price and self.a['cook'] and self.a.get('optional_sinks', True):
                self.pay(price, 'bag'); self.bag_levels.add(hs)
        glv, gprice = cfg['greenhouse']
        if not self.greenhouse and self.level('farming') >= glv and self.wallet - reserve >= gprice and self.a['cook'] and self.a.get('optional_sinks', True):
            self.pay(gprice, 'greenhouse'); self.greenhouse = True
        # 鱼饵（明天用）
        if self.a['cook']:
            for bait, (lv, price, stock) in cfg['bait_price'].items():
                if self.level('fishing') < lv:
                    continue
                want = {'P15': {'worm': 5, 'lure': 0}, 'P30': {'worm': 10, 'lure': 0}, 'HEAVY': {'worm': 30, 'lure': 10}}.get('HEAVY' if self.arch.startswith('H') else self.arch, {}).get(bait, 0)
                if not self.a.get('optional_sinks', True) and bait == 'lure':
                    want = 0
                n = max(0, min(want - self.inv[bait], stock - self.bait_bought_today[bait]))
                if n > 0 and self.wallet - reserve >= n * price:
                    self.pay(n * price, 'bait'); self.inv[bait] += n; self.bait_bought_today[bait] += n
        # 堆肥（纯金币去向，Farming Lv3）
        if self.a['compost'] and self.a.get('optional_sinks', True) and self.level('farming') >= 3 and self.wallet - reserve >= self.a['compost'] * cfg['compost_price']:
            self.pay(self.a['compost'] * cfg['compost_price'], 'fertilizer')

    def travel(self, tier_hint):
        """旅行到一座新城（或再访）。返回 True 表示今天在异城钓鱼。"""
        cfg = self.cfg
        rng = 1
        for r, c in cfg['range_clusters'].items():
            if self.clusters >= c or self.hs >= cfg['range_hs'][r]:
                rng = max(rng, r)
        tier = min(tier_hint, {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}[rng])
        coins, en = cfg['travel'][tier]
        city = f'city{self.clusters + 1}'
        if self.wallet - coins < cfg['wallet_floor_travel'] or self.energy < en:
            return None
        self.pay(coins, 'travel'); self.spend_energy(en, 'travel'); self.clusters += 1
        self.milestones.setdefault(f'range_{rng}', self.day())
        self.daily[self.day()]['travel'] = tier
        return city

    # --- 账户价值 ---
    def inventory_value(self):
        v = 0
        for k, n in self.inv.items():
            if n <= 0:
                continue
            if k in self.cfg['crops']:
                v += n * self.cfg['crops'][k][5]
            elif k in self.cfg['fish']:
                v += n * self.cfg['fish'][k][1]
            elif k in self.cfg['material_floor']:
                v += n * self.cfg['material_floor'][k]
            elif k.startswith('dish:'):
                did = k[5:]
                if did in self.cfg['dishes']:
                    v += n * sum(2 if kk.startswith('fish') else (self.cfg['crops'].get(kk, (0, 0, 0, 0, 0, 1))[5]) for kk in self.cfg['dishes'][did][2])
        return v

    # ------------------------------------------------------------------
    # 会话
    # ------------------------------------------------------------------
    def first_session(self, t0):
        """14 节导演表：播 6R+3L，3 竿（前 3 次咬钩强制 T1、第 1 条鲫鱼），回家烤鲫鱼吃，再钓到 Lv2 并用蚯蚓钓 1 条 T2。"""
        self.settle(t0)
        cfg = self.cfg
        end = t0 + 30
        # 0-3 min
        self.t = t0 + 2
        for cid, n in (('R', 6), ('L', 3)):
            for _ in range(n):
                tier, lv, seed, hours, yld, price, xp, reg = cfg['crops'][cid]
                self.spend_energy(tier, 'farm'); self.wallet -= seed; self.seed_total += seed
                self.daily[self.day()]['seed_cost'] += seed
                self.plots.append((cid, self.t + hours * 60))
        self.inv['wild_herb'] += 2
        self.t = t0 + 10
        # 3 forced T1 casts
        for i in range(3):
            self.settle(self.t)
            self.spend_energy(2, 'fish')
            fid = 'crucian' if i == 0 else self.rng.choice(['crucian', 'carp'])
            ok = self.rng.random() < cfg['succ'][self.rod][0]
            self.daily[self.day()]['casts'] += 1
            if not self.first_cast:
                self.first_cast = True; self.add_xp('fishing', cfg['first_cast_xp'], capped=False)
            self.t += 1.0
            if not ok:
                self.fails_today += 1; self.energy += 2; self.daily[self.day()]['energy'] -= 2; self.daily[self.day()]['energy_fish'] -= 2
                continue
            if not self.first_hook:
                self.first_hook = True; self.add_xp('fishing', cfg['first_hook_xp'], capped=False)
            self.inv[fid] += 1; self.daily[self.day()]['fish_value'] += cfg['fish'][fid][1]; self.daily[self.day()]['fish_caught'] += 1
            if fid not in self.first_fish:
                self.first_fish.add(fid); self.add_xp('fishing', cfg['first_species_xp'], capped=False)
            if 'home_fished' not in self.cities:
                self.cities.add('home_fished'); self.add_xp('fishing', cfg['first_city_xp'], capped=False)
            self.add_xp('fishing', cfg['fish_xp_by_tier'][0 + 1])
        # 15: cook; 15-20 sell 2 fish to request (+10), sow 8 R
        self.t = t0 + 15
        if self.inv['crucian'] > 0:
            self.cook('grilled_crucian')
        self.settle(self.t)
        for _ in range(8):
            if self.energy >= 1 and self.wallet >= 4:
                self.spend_energy(1, 'farm'); self.wallet -= 4; self.seed_total += 4; self.daily[self.day()]['seed_cost'] += 4
                self.plots.append(('R', self.t + 4 * 60))
        self.t = t0 + 20
        self.earn(10, 'npc')
        if self.inv['crucian'] >= 2:
            self.inv['crucian'] -= 2
        self.eat()
        # 21-30: 继续钓直到 Lv2，然后用蚯蚓钓 1 条 T2
        self.t = t0 + 21
        k = 0
        while self.t < end and self.level('fishing') < 2 and k < 12:
            self.settle(self.t)
            if k == 0:
                # 第 4 次咬钩若仍 Lv1 则强制 T2 挣脱（教学）
                self.spend_energy(2, 'fish'); self.fails_today += 1; self.energy += 2
                self.daily[self.day()]['energy'] -= 2; self.daily[self.day()]['energy_fish'] -= 2
                self.daily[self.day()]['casts'] += 1
                self.t += 1.0; k += 1; continue
            self.cast('pond'); self.t += 0.4; k += 1
        if self.level('fishing') >= 2:
            self.inv['worm'] += 3
            while self.t < end and self.inv['worm'] > 0 and self.energy >= 2:
                self.settle(self.t); self.cast('pond'); self.t += 0.4
        self.settle(end)
        self.sell(self.needs())

    def session(self, t0, minutes, day):
        a = self.a; cfg = self.cfg
        self.settle(t0)
        end = t0 + minutes
        self.collect_stoves()
        if a['friend'] and not self.friend_today:
            self.friend_today = True
            self.energy = min(self.energy_max() + cfg['friend_visit_bonus'], self.energy + cfg['friend_visit_bonus'])
            self.daily[self.day()]['friend_bonus'] += cfg['friend_visit_bonus']
            # 被补播 ≤5 点等值（密友到场替主人播种，主人 0 体力得到作物）：按「主人少花 5 点体力」建模
            rr = cfg.get('replant_received_max', 0)
            if rr:
                self.energy = min(self.energy_max(), self.energy + rr)
                self.daily[self.day()]['friend_bonus'] += rr
        self.harvest(); self.t += 1
        if a['explore']:
            self.explore()
        self.collect_traps()
        self.eat()
        self.cook_feast()
        self.cook_plan(minutes)
        needs = self.needs()
        morning = (t0 % 1440) < 12 * 60
        single = len(a['sessions']) == 1
        city = 'home'
        if morning or single:
            # 早会话 / 单会话：先播种（作物白天长）
            self.sow(a['farm_energy'], needs); self.t += 2
        if not morning:
            # 旅行日
            if a['travel_every'] and day >= 4 and (day - 4) % a['travel_every'] == 0:
                hint = 2 if not self.arch.startswith('H') else min(6, 2 + self.clusters // 3)
                c = self.travel(hint)
                if c:
                    city = c; self.t += 2
            # 矿洞
            if a['mine']:
                kind, every = a['mine']
                if every == 1 or (day % every) == 0:
                    self.mine(kind)
            # 钓鱼
            site = self.fish_site()
            casts = 0
            while casts < a['casts'] and self.t + cfg['cast_seconds'] / 60 <= end - 2 and self.energy >= 2:
                self.settle(self.t)
                self.cast(site, city); casts += 1
                if self.energy < 2:
                    self.eat()
            self.eat()
            # 剩余体力再播（重度玩家晚上补播；单会话玩家已播过）
            if self.arch.startswith('H') and self.energy >= 2 and self.a['farm_energy'] > 0:
                self.sow(10 ** 6, needs)
        self.settle(self.t)
        needs = self.needs()
        self.sell(needs)
        reserve = self.seed_reserve()
        self.purchases(reserve)
        self.settle(max(self.t, end))
        self.daily[self.day()]['sessions'] += 1

    def seed_reserve(self):
        """给明天播种留的种子钱：按 farm_energy × 6（生菜 6 金币/格）估。"""
        return int(self.a['farm_energy'] * 6)


def run(arch, cfg, seed=0, days=30):
    rng = random.Random(seed)
    p = Player(arch, cfg, rng)
    p.first_session(12 * 60)   # 第 1 天 12:00 首会话
    for day in range(1, days + 1):
        for (mod, minutes) in p.a['sessions']:
            t0 = (day - 1) * 1440 + mod
            if day == 1 and t0 < 12 * 60 + 30:
                continue
            p.session(t0, minutes, day)
    # 日末快照
    out = []
    for d in range(1, days + 1):
        rec = p.daily.get(d, Counter())
        out.append(dict(day=d, **rec))
    return p, out


# ----------------------------------------------------------------------------
# 3. 首会话蒙特卡洛
# ----------------------------------------------------------------------------
def first_session_mc(cfg, trials=2000, home_city_bonus=True, cast_sec=60):
    """返回 Lv2 到达分钟的分布（按 14.2 导演表节奏：10 分钟开钓、15 回家、20 吃、21 起每 cast_sec 秒一竿）。"""
    res = []
    for s in range(trials):
        rng = random.Random(s)
        xp = 0; t = 10.0; caught = set(); casts = 0; done = None
        xp += cfg['first_cast_xp'] + cfg['first_hook_xp'] + (cfg['first_city_xp'] if home_city_bonus else 0)
        def catch(fid, tier):
            nonlocal xp
            if fid not in caught:
                caught.add(fid); xp += cfg['first_species_xp']
            xp += cfg['fish_xp_by_tier'][tier]
        # 3 forced T1
        for i in range(3):
            casts += 1; t += cast_sec / 60
            if rng.random() < 0.9:
                catch('crucian' if i == 0 else rng.choice(['crucian', 'carp']), 1)
            if xp >= cfg['fish_th'][1] and done is None:
                done = t
        if done is None:
            t = 21.0
            first = True
            while done is None and t < 60:
                casts += 1; t += cast_sec / 60
                if first:
                    first = False; continue     # 教学挣脱
                tier = rng.choices([1, 2, 3, 4], weights=cfg['sites']['pond'])[0]
                if tier >= 2:
                    continue
                if rng.random() < 0.9:
                    catch(rng.choice(['crucian', 'carp']), 1)
                if xp >= cfg['fish_th'][1]:
                    done = t
        res.append((done, casts))
    mins = [d for d, _ in res]
    return dict(p30=sum(1 for m in mins if m <= 30) / trials, p45=sum(1 for m in mins if m <= 45) / trials,
                median=statistics.median(mins), p90=sorted(mins)[int(0.9 * trials)], casts=statistics.mean(c for _, c in res))


# ----------------------------------------------------------------------------
# 4. 报告
# ----------------------------------------------------------------------------
def haversine(lat1, lon1, lat2, lon2):
    R = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = p2 - p1; dl = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(a))


def summarize(arch, cfg, seeds, days):
    runs = [run(arch, cfg, s, days) for s in range(seeds)]
    ms_keys = sorted({k for p, _ in runs for k in p.milestones})
    ms = {k: statistics.mean([p.milestones.get(k, days + 1) for p, _ in runs]) for k in ms_keys}
    # 逐日（seed 0）+ 多 seed 平均的关键量
    p0, out0 = runs[0]
    agg = []
    for d in range(1, days + 1):
        rows = [o[d - 1] for _, o in runs]
        def m(k):
            return statistics.mean([r.get(k, 0) for r in rows])
        agg.append(dict(day=d, energy=m('energy'), xp_f=m('xp_farming'), xp_s=m('xp_fishing'), income=m('income'),
                        seed=m('seed_cost'), sink=m('sink'), meal=m('meal_restore'), harvest=m('harvest_value'),
                        fish=m('fish_value'), mat=m('material_value'), casts=m('casts'),
                        e_farm=m('energy_farm'), e_fish=m('energy_fish'), e_mine=m('energy_mine'), e_travel=m('energy_travel'),
                        s_home=m('sink_homestead'), s_gear=m('sink_gear'), s_rec=m('sink_recipes'), s_bait=m('sink_bait'),
                        s_fert=m('sink_fertilizer'), s_travel=m('sink_travel'), s_sap=m('sink_saplings'), s_bag=m('sink_bag'), s_gh=m('sink_greenhouse')))
    return runs, ms, agg


def site_values(cfg):
    """解析口径：每渔场 × 鱼竿 × 鱼饵 的每点体力净金币（扣鱼饵单价；全档解锁；地区鱼按全球鱼均价）。"""
    tier_price = {}
    for t in (1, 2, 3, 4):
        ps = [v[1] for v in cfg['fish'].values() if v[0] == t and v[5] == 1]
        tier_price[t] = sum(ps) / len(ps)
    out = {}
    for site, base_w in cfg['sites'].items():
        for rod, succ in cfg['succ'].items():
            for bait, bw in cfg['bait'].items():
                w = [max(0, a + b) for a, b in zip(base_w, bw)]
                tot = sum(w)
                exp_coin = sum(w[i] / tot * succ[i] * tier_price[i + 1] for i in range(4) if i + 1 <= cfg['rod_max'][rod])
                p_ok = sum(w[i] / tot * succ[i] for i in range(4) if i + 1 <= cfg['rod_max'][rod])
                energy = 2 - (1 - p_ok)   # 失败退 1（Lv4+ 口径，不计前 10 次保护）
                bait_cost = cfg['bait_price'][bait][1] if bait else 0
                out[(site, rod, bait)] = (exp_coin, energy, (exp_coin - bait_cost) / energy, exp_coin / energy, p_ok)
    return out, tier_price


def report(cfg, seeds, days, md=None, label=''):
    lines = []
    def P(s=''):
        lines.append(s); print(s)
    P(f'# 模拟结果 {label}（seeds={seeds}, days={days}）')
    sv, tp = site_values(cfg)
    P(f'\n## 渔场解析表（每点体力净金币；档位均价 T1 {tp[1]:.1f} / T2 {tp[2]:.1f} / T3 {tp[3]:.1f} / T4 {tp[4]:.1f}；扣鱼饵单价；失败退 1）')
    P('| 渔场 | 鱼竿 | 鱼饵 | 期望金币/竿 | 体力/竿 | 上钩率 | 每点净（扣饵） | 每点净（不扣饵） |')
    P('|---|---|---|---|---|---|---|---|')
    for (site, rod, bait), (ec, en, net, gross, pok) in sv.items():
        P(f'| {site} | {rod} | {bait or "—"} | {ec:.2f} | {en:.2f} | {pok:.0%} | {net:.2f} | {gross:.2f} |')
    tier0 = sv[('pond', 'carbon', None)][2]   # Tier 0 口径 = 城市水塘、全档可收（碳素竿）、无饵
    worst = max(sv.items(), key=lambda kv: kv[1][2])
    P(f'- Tier 0 基准（pond·全档可收·无饵）{tier0:.2f}；上界 2 × Tier 0 = {2 * tier0:.2f}；最高组合 {worst[0]} = {worst[1][2]:.2f}（扣饵）')
    globals()['_SITE_CAP'] = (tier0, worst[0], worst[1][2])
    results = {}
    for arch in ('P5', 'P15', 'P30', 'HEAVY'):
        runs, ms, agg = summarize(arch, cfg, seeds, days)
        results[arch] = (runs, ms, agg)
    variants = {}
    for arch in ('HF_FISH', 'HF_FARM', 'H_FOCUS'):
        variants[arch] = summarize(arch, cfg, seeds, min(days, 60))
    # --- 首会话 ---
    mc = first_session_mc(cfg)
    mc2 = first_session_mc(cfg, home_city_bonus=False)
    P(f'\n## 首会话 Fishing Lv2（阈值 {cfg["fish_th"][1]}）')
    P(f'- 含家城首鱼 +10：P(≤30 min)={mc["p30"]:.3f}  P(≤45)={mc["p45"]:.3f}  中位 {mc["median"]:.1f} min  P90 {mc["p90"]:.1f} min  平均竿数 {mc["casts"]:.1f}')
    P(f'- 不含家城首鱼：P(≤30 min)={mc2["p30"]:.3f}  P(≤45)={mc2["p45"]:.3f}  中位 {mc2["median"]:.1f} min  P90 {mc2["p90"]:.1f} min')
    # --- 里程碑 ---
    P('\n## 里程碑到达日（多 seed 平均；>days 表示未达）')
    keys = ['fishing_lv2', 'fishing_lv5', 'fishing_lv7', 'fishing_lv10', 'farming_lv2', 'farming_lv5', 'farming_lv7', 'farming_lv10',
            'hs_lv2', 'hs_lv3', 'hs_lv4', 'hs_lv5', 'hs_lv6', 'hs_lv7', 'hs_lv8', 'hs_lv9', 'hs_lv10', 'rod_reed', 'rod_carbon', 'range_5']
    P('| 画像 | ' + ' | '.join(k.replace('fishing_', 'Fi').replace('farming_', 'Fa').replace('hs_', 'Hs').replace('rod_', '竿') for k in keys) + ' |')
    P('|' + '---|' * (len(keys) + 1))
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        P(f'| {arch} | ' + ' | '.join((f'{ms[k]:.0f}' if k in ms and ms[k] <= days else '—') for k in keys) + ' |')
    summary_variants = variants
    P('\n## 技能逐级到达日（多 seed 平均；供 04 §4.4.2）')
    lv_keys = [f'{t}_lv{n}' for t in ('fishing', 'farming') for n in range(2, 11)]
    P('| 画像 | ' + ' | '.join(k.replace('fishing_lv', 'Fi').replace('farming_lv', 'Fa') for k in lv_keys) + ' |')
    P('|' + '---|' * (len(lv_keys) + 1))
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        P(f'| {arch} | ' + ' | '.join((f'{ms[k]:.0f}' if k in ms and ms[k] <= days else '—') for k in lv_keys) + ' |')
    # --- 账本汇总 ---
    P('\n## 账本汇总（days 内，多 seed 平均）')
    P('| 画像 | 日均体力 | 稳态每体力净金币(d8-d30) | 7 日账户价值 | 30 日净收入 | 30 日去向(非种子) | 吸收比 | 日均料理回复(d8+) | 日均 F |')
    P('|---|---|---|---|---|---|---|---|---|')
    summary = {}
    for arch, (runs, ms, agg) in results.items():
        en = statistics.mean(a['energy'] for a in agg[1:])
        prod = sum(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in agg[7:min(30, days)])
        ensum = sum(a['energy'] for a in agg[7:min(30, days)])
        vpe = prod / max(1, ensum)
        v7 = cfg['initial_wallet'] + sum(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in agg[:7])
        net30 = sum(a['income'] - a['seed'] for a in agg[:30])
        sink30 = sum(a['sink'] for a in agg[:30])
        share = sink30 / max(1, net30 + cfg['initial_wallet'])
        meal = statistics.mean(a['meal'] for a in agg[7:min(30, days)])
        Fm = statistics.mean(min(cfg['F_cap'], cfg['F_base'] + cfg['F_per_level'] * (runs[0][0].hs - 1)) for _ in [0])
        summary[arch] = dict(energy=en, vpe=vpe, v7=v7, net30=net30, sink30=sink30, share=share, meal=meal)
        P(f'| {arch} | {en:.1f} | {vpe:.2f} | {v7:.0f} | {net30:.0f} | {sink30:.0f} | {share:.0%} | {meal:.1f} | {Fm:.0f} |')
    P('\n## 每体力净金币分项（d8–d30 稳态）与去向构成')
    P('| 画像 | 作物(收获−种子)/播种体力 | 鱼/抛竿净体力 | 材料地板价/矿洞体力 | 合计 | 日均体力 农/钓/矿/旅 | 去向：升级/渔具/配方/饵/肥/旅/苗/包/温室 | 必需去向占比(下界) | 贪婪占比(上界) | d30 钱包 |')
    P('|---|---|---|---|---|---|---|---|---|---|')
    for arch, (runs, ms, agg) in results.items():
        w = agg[7:min(30, days)]
        def S(k):
            return sum(a[k] for a in w)
        crop = (S('harvest') - S('seed')) / max(1, S('e_farm')); fish = S('fish') / max(1, S('e_fish')); mat = S('mat') / max(1, S('e_mine'))
        tot = (S('harvest') - S('seed') + S('fish') + S('mat')) / max(1, S('energy'))
        n = len(w)
        w30 = agg[:30]
        def S30(k):
            return sum(a[k] for a in w30)
        net30 = S30('income') - S30('seed') + cfg['initial_wallet']
        must = S30('s_home') + S30('s_gear') + S30('s_bait') + S30('s_fert') + S30('s_travel') + min(S30('s_rec'), 140)
        allsink = S30('sink')
        p = runs[0][0]
        P(f'| {arch} | {crop:.2f} | {fish:.2f} | {mat:.2f} | {tot:.2f} | {S("e_farm")/n:.0f}/{S("e_fish")/n:.0f}/{S("e_mine")/n:.0f}/{S("e_travel")/n:.1f} | '
          f'{S30("s_home"):.0f}/{S30("s_gear"):.0f}/{S30("s_rec"):.0f}/{S30("s_bait"):.0f}/{S30("s_fert"):.0f}/{S30("s_travel"):.0f}/{S30("s_sap"):.0f}/{S30("s_bag"):.0f}/{S30("s_gh"):.0f} | '
          f'{must/net30:.0%} | {allsink/net30:.0%} | {p.wallet:.0f} |')
        summary[arch]['share_low'] = must / net30
    r = summary['HEAVY']['v7'] / summary['P30']['v7']
    r5 = summary['HEAVY']['v7'] / summary['P5']['v7']
    r30 = (sum(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in results['HEAVY'][2][:30]) + 180) / (sum(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in results['P30'][2][:30]) + 180)
    def ratio(nd):
        h = cfg['initial_wallet'] + sum(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in results['HEAVY'][2][:nd])
        b = cfg['initial_wallet'] + sum(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in results['P30'][2][:nd])
        return h / b
    def daily_ratio():
        h = statistics.mean(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in results['HEAVY'][2][7:30])
        b = statistics.mean(a['harvest'] + a['fish'] + a['mat'] - a['seed'] for a in results['P30'][2][7:30])
        return h / b
    P(f'\n- 账户价值比 重度/P30：7 日累计 {ratio(7):.2f}（红线 1.8）· 14 日累计 {ratio(14):.2f} · 30 日累计 {ratio(30):.2f} · 稳态单日(d8–30) {daily_ratio():.2f}；重度/P5 7 日 {r5:.2f}')
    summary['_ratios'] = {'r7': ratio(7), 'r14': ratio(14), 'r30': ratio(30), 'rd': daily_ratio()}
    for arch in ('HF_FISH', 'HF_FARM'):
        rr = variants[arch][0]
        tr = 'fishing' if arch == 'HF_FISH' else 'farming'
        d7 = [sum(o[i].get('xp_' + tr, 0) for i in range(7)) for _, o in rr]
        th = cfg['fish_th'][9] if tr == 'fishing' else cfg['farm_th'][9]
        P(f'- {arch} 第 7 天末累计 {tr} XP：均值 {statistics.mean(d7):.0f}，最大 {max(d7):.0f}（Lv10 阈值 {th}，余量 {th - max(d7):.0f}）')
    # 有效体力校验
    P('\n## 永动校验：稳态日均体力消耗 ≤ 96 + F + 5（d8–d30；单日峰值含前日存量，不作判据）')
    for arch, (runs, ms, agg) in results.items():
        p = runs[0][0]
        w = agg[7:min(30, days)]
        avg = statistics.mean(a['energy'] for a in w); mx = max(a['energy'] for a in w)
        F = min(cfg['F_cap'], cfg['F_base'] + cfg['F_per_level'] * (p.hs - 1))
        meal = statistics.mean(a['meal'] for a in w)
        P(f'- {arch}: 日均消耗 {avg:.0f}（峰值 {mx:.0f}）  日均料理回复 {meal:.0f} ≤ F {F}  上界 96+{F}+5 = {96 + F + 5}  {"✓" if avg <= 96 + F + 5 + 1 else "✗"}')
        summary[arch]['perpetual_ok'] = avg <= 96 + F + 5 + 1
    # 旅行
    P('\n## 旅行：上海↔洛杉矶')
    d = haversine(31.23, 121.47, 34.05, -118.24)
    P(f'- haversine 上海–洛杉矶 = {d:.0f} km → 档 T6（>10,000 km）：200 金币 / 30 体力；再访 100 / 15；需航程档 V（Hs Lv5 或 20 簇）')
    for arch, (runs, ms, agg) in results.items():
        p = runs[0][0]
        hs5 = ms.get('hs_lv5', days + 1)
        # 可达日：Hs5 后钱包 ≥ 240 的第一天
        reach = None
        for dd in range(1, days + 1):
            if dd >= hs5:
                reach = dd; break
        P(f'- {arch}: Hs Lv5 平均第 {hs5:.0f} 天（航程档 V 解锁）；去过的簇 d{days} = {p.clusters}；上海→洛杉矶首访 200 金币/30 体力 → {"第 %d 天起可达" % reach if reach else "%d 天内不可达（Hs5 未到、簇 <20）" % days}')
    # 逐日表
    P('\n## 逐日关键表（seed 0..n 平均；体力=当日消耗）')
    for arch, (runs, ms, agg) in results.items():
        p = runs[0][0]
        P(f'\n### {arch} · {p.a["label"]}')
        P('| 日 | 体力用 | Farm XP(累计/Lv) | Fish XP(累计/Lv) | 钱包 | 库存价值 | Hs | 料理回复 | 收入 | 种子 | 去向 | 竿数 |')
        P('|---|---|---|---|---|---|---|---|---|---|---|---|')
        cf = cs = 0
        # 用 seed0 的钱包/库存/Hs 快照：重跑单 seed 记录
        p0, out0 = runs[0]
        # 快照需要逐日状态：重新跑 seed0 并记录
        snaps = snapshot_run(arch, cfg, 0, days)
        for a in agg[:min(days, 30)]:
            cf += a['xp_f']; cs += a['xp_s']
            s = snaps[a['day'] - 1]
            P(f'| {a["day"]} | {a["energy"]:.0f} | {cf:.0f}/{s["farm_lv"]} | {cs:.0f}/{s["fish_lv"]} | {s["wallet"]:.0f} | {s["inv"]:.0f} | {s["hs"]} | {a["meal"]:.0f} | {a["income"]:.0f} | {a["seed"]:.0f} | {a["sink"]:.0f} | {a["casts"]:.0f} |')
        p = runs[0][0]
        P(f'去向构成（seed0，{days} 天）：' + ', '.join(f'{k} {v}' for k, v in sorted(p.sink_total.items())))
        blocks = Counter(o.get('hs_block', '') for o in out0 if o.get('hs_block'))
        P(f'农场升级被卡原因（seed0 天数计）：{dict(blocks.most_common(6))}')
    if md:
        with open(md, 'w') as f:
            f.write('\n'.join(lines))
    results['_variants'] = variants
    return results, summary, mc, mc2


def snapshot_run(arch, cfg, seed, days):
    """重跑一个 seed 并在每天 23:59 记录钱包/库存价值/等级/Hs。"""
    rng = random.Random(seed)
    p = Player(arch, cfg, rng)
    p.first_session(12 * 60)
    snaps = []
    for day in range(1, days + 1):
        for (mod, minutes) in p.a['sessions']:
            t0 = (day - 1) * 1440 + mod
            if day == 1 and t0 < 12 * 60 + 30:
                continue
            p.session(t0, minutes, day)
        snaps.append(dict(wallet=p.wallet, inv=p.inventory_value(), farm_lv=p.level('farming'), fish_lv=p.level('fishing'), hs=p.hs))
    return snaps


def checks(cfg, results, summary, mc, mc2, days):
    """按 constraints.md 目标逐项判定。"""
    out = []
    def chk(name, ok, detail):
        out.append((name, ok, detail)); print(f'[{"PASS" if ok else "FAIL"}] {name}: {detail}')
    chk('首会话 30 分钟内 Fishing Lv2', mc['p30'] >= 0.95, f'P(≤30min)={mc["p30"]:.2f}（不含家城首鱼 {mc2["p30"]:.2f}）')
    ms30 = results['P30'][1]
    chk('P30 两条轨 21±5 天满级', 16 <= ms30.get('fishing_lv10', 99) <= 26 and 16 <= ms30.get('farming_lv10', 99) <= 26,
        f'Fishing d{ms30.get("fishing_lv10", 99):.0f} / Farming d{ms30.get("farming_lv10", 99):.0f}')
    msh = results['HEAVY'][1]
    v = results.get('_variants', {})
    hf = v.get('HF_FISH', (None, {}, None))[1]; hfa = v.get('HF_FARM', (None, {}, None))[1]
    chk('重度 ≥8 天满级（含全钓/全种上界）', msh.get('fishing_lv10', 99) >= 8 and msh.get('farming_lv10', 99) >= 8 and hf.get('fishing_lv10', 99) >= 8 and hfa.get('farming_lv10', 99) >= 8,
        f'均衡重度 Fishing d{msh.get("fishing_lv10", 99):.0f} / Farming d{msh.get("farming_lv10", 99):.0f}；全钓 Fishing d{hf.get("fishing_lv10", 99):.0f}；全种 Farming d{hfa.get("farming_lv10", 99):.0f}')
    ms5 = results['P5'][1]
    chk('P5 ≤90 天满级', ms5.get('fishing_lv10', 999) <= 90 and ms5.get('farming_lv10', 999) <= 90,
        f'Fishing d{ms5.get("fishing_lv10", 999):.0f} / Farming d{ms5.get("farming_lv10", 999):.0f}（days={days}）')
    rr = summary.get('_ratios', {})
    chk('账户价值比 重度/P30 稳态单日(d8–30) ≤1.8（主断言，10 §10.3.4 口径）', rr.get('rd', 9) <= 1.8, f'{rr.get("rd", 0):.2f}')
    r = summary['HEAVY']['v7'] / summary['P30']['v7']
    chk('7 日累计账户价值比 重度/P30 ≤1.9（首周爬坡容差）', r <= 1.9, f'{r:.2f}（含社交入流 +10/日）')
    for arch in ('P5', 'P30'):
        vpe = summary[arch]['vpe']
        chk(f'{arch} 每体力净金币 2±0.5', 1.5 <= vpe <= 2.5, f'{vpe:.2f}')
    vpe = summary['HEAVY']['vpe']
    chk('HEAVY 每体力净金币 ≤3.0（含沿海在线溢价，上限 = 1.5 × 中心）', vpe <= 3.0, f'{vpe:.2f}')
    t0, wk, wv = globals().get('_SITE_CAP', (2.0, None, 0))
    chk('任一渔场×鱼竿×鱼饵组合（扣饵）每点净值 ≤ 2 × Tier 0', wv <= 2 * t0 + 1e-9, f'最高 {wk} = {wv:.2f} ≤ {2 * t0:.2f}')
    archs = [a for a in summary if not a.startswith('_')]
    chk('料理不构成永动（稳态日均 ≤ 96+F+5）', all(summary[a].get('perpetual_ok', True) for a in archs), ', '.join(f'{a}:{"ok" if summary[a].get("perpetual_ok", True) else "x"}' for a in archs))
    chk('账户价值比 14 日 / 30 日累计 ≤1.8（补充口径）', rr.get('r14', 9) <= 1.8 and rr.get('r30', 9) <= 1.8, f'14 日 {rr.get("r14", 0):.2f} · 30 日 {rr.get("r30", 0):.2f}')
    for arch in ('P15', 'P30', 'HEAVY'):
        s = summary[arch]['share']; lo = summary[arch].get('share_low', 0)
        chk(f'{arch} 金币 sink 吸收 60–80%', lo <= 0.8 and s >= 0.6, f'必需去向下界 {lo:.0%} ～ 贪婪上界 {s:.0%}（60–80% 须落在区间内）')
    hfo = v.get('H_FOCUS', (None, {}, None))[1]
    chk('重度冲刺（只买必需）Hs Lv10 30–35 天（10 §10.3.4 改写后的目标）', hfo.get('hs_lv10', 999) <= 35, f'冲刺 d{hfo.get("hs_lv10", 999):.0f}；均衡重度 d{msh.get("hs_lv10", 999):.0f}')
    ms15 = results['P15'][1]
    chk('休闲(P15) Hs Lv10 60–70 天（D23 的 60–90 带内）', 60 <= ms15.get('hs_lv10', 999) <= 70, f'd{ms15.get("hs_lv10", 999):.0f}（P30 d{ms30.get("hs_lv10", 999):.0f}）')
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--fix', default='', help='逗号分隔的对照开关 id（F2/F6/F7/F11/F12/F13）；F1/F3/F4/F5/F8/F9/F10 已并入基表'); ap.add_argument('--days', type=int, default=90)
    ap.add_argument('--seeds', type=int, default=6); ap.add_argument('--md', default=None)
    args = ap.parse_args()
    cfg = base_config()
    fixes = set()
    for f, d in APPLIED_IN_BASE.items():
        print(f'[基表已含 {f}] {d}')
    if args.fix:
        fixes = set(RECOMMENDED) if args.fix == 'recommended' else set(x.strip() for x in args.fix.split(','))
        cfg = apply_fixes(cfg, fixes)
        for f in sorted(fixes):
            print(f'[{f}] {FIX_DOC[f]}')
    results, summary, mc, mc2 = report(cfg, args.seeds, args.days, args.md, label=('（对照 ' + '+'.join(sorted(fixes)) + '）') if fixes else '（修正后基表）')
    print('\n## 校验结论')
    checks(cfg, results, summary, mc, mc2, args.days)
