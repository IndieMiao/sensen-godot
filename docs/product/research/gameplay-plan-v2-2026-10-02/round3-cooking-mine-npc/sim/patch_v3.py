#!/usr/bin/env python3
"""把 sim_v2.py 的副本改成 sim_v3.py（第三轮定稿规则）。每处替换必须恰好命中一次。"""
import re, sys
P = '/tmp/gensen_design/v2/sim_r3/sim_v3.py'
s = open(P).read()
n_rep = 0

def rep(old, new, count=1):
    global s, n_rep
    c = s.count(old)
    if c != count:
        print(f'[ERR] expected {count} hit(s), got {c}:\n{old[:200]}'); sys.exit(1)
    s = s.replace(old, new); n_rep += 1

# ---------------------------------------------------------------- docstring
rep('''sim_v2.py — Gensen 玩法方案 v2 数值模拟（内部校验工具，不进仓库）

从 v1 sim.py 复制后按 v2 规则重写：''',
'''sim_v3.py — Gensen 玩法方案 v2 第三轮复跑（内部校验工具，不进仓库）

从 sim_v2.py 复制后按第三轮定稿改四处：
  ① 加 Cooking 轨：阈值 0/30/100/220/400/650/950/1,350/1,700/2,350；第 3 投料槽在 Cooking Lv4（Lv1–3 = 2 槽，本期不开第 4/5 槽）；
     每锅 XP 按菜品稀有度 4/8/16/32，同一页每日第 1 锅 100%、第 2 锅 50%（向上取整）、第 3 锅起 0；Good ×1.25、Perfect ×1.5（向下取整）；
     内容等级按稀有度 Common 1 / Fine 2 / Rare 4 / Legendary 6，走与两轨相同的等级差衰减；首做 10/20/40/80 全归 Cooking；防脚本 3,000/日；
     升级回体力与两轨一致（账号首次升级 +50、其后 +30）；Lv2 升级礼 = 鲜鱼汤配方卡
     三类玩家做菜行为：5 分钟 1–2 锅/日、30 分钟 3–5 锅/日（含 1–2 道新页）、重度 6–10 锅/日；多余成品按赠礼/委托送出（库存上限 12）
  ② Fishing 首竿/首提 +5 → +10；首做料理 XP 从 Farming / Fishing 移除；"首次做成任何菜 +20 体力"按正文删除
  ③ 矿井按层计费：每层 2、电梯 0、A 局 28、B 局 56（原 34 / 58）
  ④ 其余不变

v2 规则（沿用）：''')

# ---------------------------------------------------------------- base_config
rep("    cfg['first_dish_energy'] = 20; cfg['first_rare_dish_energy'] = 30; cfg['first_legendary_dish_energy'] = 50",
    "    cfg['first_dish_energy'] = 0; cfg['first_rare_dish_energy'] = 30; cfg['first_legendary_dish_energy'] = 50   # r3：首次做成任何菜 +20 已删")
rep("    cfg['mine'] = {'A': (34, 4, {'stone': 12, 'copper': 3.9, 'rock_salt': 2.7, 'clay': 0.9, 'quartz': 0.9}),\n                   'B': (58, 8, {'stone': 24, 'copper': 8.1, 'rock_salt': 4.8, 'clay': 0.9, 'quartz': 3.0})}",
    "    cfg['mine'] = {'A': (28, 4, {'stone': 12, 'copper': 3.9, 'rock_salt': 2.7, 'clay': 0.9, 'quartz': 0.9}),   # r3：层费 2×2 + 12 岩 × 2 = 28（原 34）\n                   'B': (56, 8, {'stone': 24, 'copper': 8.1, 'rock_salt': 4.8, 'clay': 0.9, 'quartz': 3.0})}   # r3：层费 2×4 + 24 岩 × 2 = 56（原 58）")
rep("    cfg['first_city_xp'] = 10; cfg['first_cast_xp'] = 5; cfg['first_hook_xp'] = 5",
    "    cfg['first_city_xp'] = 10; cfg['first_cast_xp'] = 10; cfg['first_hook_xp'] = 10   # r3：+5/+5 → +10/+10")
rep("    cfg['dish_first_xp'] = {'common': 10, 'fine': 20, 'rare': 40, 'legendary': 80}\n",
    """    cfg['dish_first_xp'] = {'common': 10, 'fine': 20, 'rare': 40, 'legendary': 80}   # r3：全部归 Cooking
    # --- Cooking 轨（r3）---
    cfg['cook_th'] = [0, 30, 100, 220, 400, 650, 950, 1350, 1700, 2350]
    cfg['cook_xp'] = {'common': 4, 'fine': 8, 'rare': 16, 'legendary': 32}
    cfg['cook_content_lv'] = {'common': 1, 'fine': 2, 'rare': 4, 'legendary': 6}
    cfg['cook_page_decay'] = [1.0, 0.5, 0.0]
    cfg['cook_quality_mult'] = {'normal': 1.0, 'good': 1.25, 'perfect': 1.5}
    cfg['cook_slot_lv3'] = 4          # 第 3 投料槽的 Cooking 等级
    cfg['dish_stock_cap'] = 12        # 成品库存上限；超出按赠礼 / 委托送出（0 体力 0 金币）
""")
rep("    cfg['slots'] = lambda hs: 2 if hs < 2 else 3\n",
    "    cfg['slots'] = lambda cook_lv: 2 if cook_lv < cfg['cook_slot_lv3'] else 3   # r3：槽位随 Cooking Lv，不随 Homestead\n")

# ---------------------------------------------------------------- FIX_DOC / apply_fixes
rep("    'A9': '对照（不推荐）：食物上限 200 → 120、茶 3 杯 → 1 杯——验证“把重度/休闲压到 1.8 要付出什么”',\n}",
    """    'A9': '对照（不推荐）：食物上限 200 → 120、茶 3 杯 → 1 杯——验证“把重度/休闲压到 1.8 要付出什么”',
    'C1': '旋钮：Farming Lv8–10 阈值 1,450/2,050/2,800 → 1,375/1,950/2,650（−5%，补首做 XP 移出的损失）',
    'C2': '旋钮：Fishing Lv8–10 阈值 2,400/3,100/4,000 → 2,300/2,950/3,800（−5%）',
    'C3': '对照：第 3 投料槽在 Cooking Lv3（100 XP）而不是 Lv4（220 XP）',
    'C4': '对照：矿洞体力回到原模型 34 / 58（只看矿井改表的影响）',
    'C5': '对照：首做料理 XP 不移交（仍归原料轨），只看“做菜给 XP”对两轨的影响为 0 的核验',
}""")
rep("    if 'A9' in fixes:\n        cfg['food_base'] = 120; cfg['tea_cups'] = 1\n    return cfg",
    """    if 'A9' in fixes:
        cfg['food_base'] = 120; cfg['tea_cups'] = 1
    if 'C1' in fixes:
        cfg['farm_th'] = [0, 50, 150, 300, 500, 750, 1050, 1375, 1950, 2650]
    if 'C2' in fixes:
        cfg['fish_th'] = [0, 70, 220, 480, 850, 1300, 1850, 2300, 2950, 3800]
    if 'C3' in fixes:
        cfg['cook_slot_lv3'] = 3
    if 'C4' in fixes:
        cfg['mine']['A'] = (34,) + cfg['mine']['A'][1:]; cfg['mine']['B'] = (58,) + cfg['mine']['B'][1:]
    if 'C5' in fixes:
        cfg['first_dish_to_source_track'] = True
    return cfg""")

# ---------------------------------------------------------------- 画像：每日锅数
rep("                gather=True, mine=('A', 3), cook_target=2, discover=0.7, worms=3, lures=2, tea='never', travel='none',\n                friend=False, buy='light', requests=4, helper=0, meal_plan=False),\n    'P5B'",
    "                gather=True, mine=('A', 3), cook_target=2, discover=0.7, worms=3, lures=2, tea='never', travel='none',\n                friend=False, buy='light', requests=4, helper=0, meal_plan=False, pots=(1, 2)),\n    'P5B'")
rep("                gather=True, mine=('A', 3), cook_target=2, discover=0.7, worms=2, lures=0, tea='never', travel='none',\n                friend=False, buy='light', requests=4, helper=0, meal_plan=False),",
    "                gather=True, mine=('A', 3), cook_target=2, discover=0.7, worms=2, lures=0, tea='never', travel='none',\n                friend=False, buy='light', requests=4, helper=0, meal_plan=False, pots=(1, 2)),")
rep("                gather=True, mine=('A', 2), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',\n                friend=False, buy='balanced', requests=15, helper=3, meal_plan=True),\n    'P30B'",
    "                gather=True, mine=('A', 2), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',\n                friend=False, buy='balanced', requests=15, helper=3, meal_plan=True, pots=(3, 5)),\n    'P30B'")
rep("                 gather=True, mine=('A', 1), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',\n                 friend=False, buy='balanced', requests=15, helper=3, meal_plan=True),",
    "                 gather=True, mine=('A', 1), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',\n                 friend=False, buy='balanced', requests=15, helper=3, meal_plan=True, pots=(3, 5)),")
rep("                 gather=True, mine=('A', 2), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',\n                 friend=False, buy='balanced', requests=15, helper=3, meal_plan=True),",
    "                 gather=True, mine=('A', 2), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',\n                 friend=False, buy='balanced', requests=15, helper=3, meal_plan=True, pots=(3, 5)),")
rep("                  worms=30, lures=10, tea='daily', travel='daily', friend=True, buy='balanced', requests=32, helper=6, meal_plan=True),",
    "                  worms=30, lures=10, tea='daily', travel='daily', friend=True, buy='balanced', requests=32, helper=6, meal_plan=True, pots=(6, 10)),")

# ---------------------------------------------------------------- Player.__init__ / reset_day / level
rep("        self.xp = {'farming': 0, 'fishing': 0}\n        self.rod = 'starter'",
    "        self.xp = {'farming': 0, 'fishing': 0, 'cooking': 0}\n        self.rod = 'starter'")
rep("        self.first_session_lv2_minute = None\n",
    "        self.first_session_lv2_minute = None\n        self.first_session_cook_lv2_minute = None\n        self.gifted_total = 0\n")
rep("        self.wall_today = 0; self.gift_today = 0; self.request_paid = False; self.day_xp = {'farming': 0, 'fishing': 0}; self.fish_sold_today = 0",
    "        self.wall_today = 0; self.gift_today = 0; self.request_paid = False; self.day_xp = {'farming': 0, 'fishing': 0, 'cooking': 0}; self.fish_sold_today = 0\n        self.page_pots_today = Counter(); self.pots_done_today = 0\n        lo, hi = self.a.get('pots', (0, 0)); self.pots_today = self.rng.randint(lo, hi) if hi > 0 else 0")
rep("        th = self.cfg['fish_th'] if track == 'fishing' else self.cfg['farm_th']\n",
    "        th = self.cfg['fish_th'] if track == 'fishing' else self.cfg['farm_th'] if track == 'farming' else self.cfg['cook_th']\n")
rep("            if track == 'fishing' and lv == 2 and self.first_session_lv2_minute is None:\n                self.first_session_lv2_minute = self.t\n",
    "            if track == 'fishing' and lv == 2 and self.first_session_lv2_minute is None:\n                self.first_session_lv2_minute = self.t\n            if track == 'cooking' and lv == 2 and self.first_session_cook_lv2_minute is None:\n                self.first_session_cook_lv2_minute = self.t\n                self.discovered.add('fish_soup')   # 升级礼：鲜鱼汤配方卡\n")

# ---------------------------------------------------------------- can_make：槽位看 Cooking Lv
rep("        if d['slots'] > self.cfg['slots'](self.hs):\n            return None",
    "        if d['slots'] > self.cfg['slots'](self.level('cooking')):\n            return None")

# ---------------------------------------------------------------- cook()：XP 归 Cooking
rep("""        # 品质：Good 概率 p_good；Rare/Legendary 两次火候 → Perfect 概率
        bonus = 0
        if self.rng.random() < cfg['p_good']:
            bonus = cfg['good_bonus'][d['rar']]
            if d['rar'] in ('rare', 'legendary') and self.rng.random() < cfg['p_perfect']:
                bonus = 20; self.dishes[did] += 1
        self.dish_bonus[did] = bonus   # 简化：按最近一次品质记
        self.daily[self.day()]['cooked'] += 1
        if did not in self.cooked_once:
            self.cooked_once.add(did); self.discovered.add(did); self.discover_today += 1
            # 归轨
            best = None
            for key in d['ingr']:
                lvx, tr = self.item_level(key)
                if tr == 'none':
                    continue
                if best is None or lvx > best[0] or (lvx == best[0] and tr == 'fishing'):
                    best = (lvx, tr)
            track = best[1] if best else 'farming'
            self.add_xp(track, cfg['dish_first_xp'][d['rar']], oneoff=True)
            if not self.first_dish_rar:
                self.add_energy_bonus(cfg['first_dish_energy'], 'achv')""",
"""        # 品质：Good 概率 p_good；Rare/Legendary 两次火候 → Perfect 概率
        bonus = 0; quality = 'normal'
        if self.rng.random() < cfg['p_good']:
            bonus = cfg['good_bonus'][d['rar']]; quality = 'good'
            if d['rar'] in ('rare', 'legendary') and self.rng.random() < cfg['p_perfect']:
                bonus = 20; self.dishes[did] += 1; quality = 'perfect'
        self.dish_bonus[did] = bonus   # 简化：按最近一次品质记
        self.daily[self.day()]['cooked'] += 1; self.pots_done_today += 1
        # r3：每锅 Cooking XP = 稀有度基数 → 等级差衰减 → 同页每日递减（50% 向上取整）→ 品质倍率（向下取整）
        n_before = self.page_pots_today[did]; self.page_pots_today[did] += 1
        decay = cfg['cook_page_decay'][min(n_before, 2)]
        if decay > 0:
            dlv = self.level('cooking') - cfg['cook_content_lv'][d['rar']]
            base = self.ld_xp(cfg['cook_xp'][d['rar']], dlv)
            v = math.ceil(base * decay)
            v = int(v * cfg['cook_quality_mult'][quality])
            self.add_xp('cooking', v)
        if did not in self.cooked_once:
            self.cooked_once.add(did); self.discovered.add(did); self.discover_today += 1
            # 首做 XP：r3 全归 Cooking（C5 对照时仍归原料轨）
            if cfg.get('first_dish_to_source_track'):
                best = None
                for key in d['ingr']:
                    lvx, tr = self.item_level(key)
                    if tr == 'none':
                        continue
                    if best is None or lvx > best[0] or (lvx == best[0] and tr == 'fishing'):
                        best = (lvx, tr)
                track = best[1] if best else 'farming'
            else:
                track = 'cooking'
            self.add_xp(track, cfg['dish_first_xp'][d['rar']], oneoff=True)
            if not self.first_dish_rar and cfg['first_dish_energy'] > 0:
                self.add_energy_bonus(cfg['first_dish_energy'], 'achv')""")

# ---------------------------------------------------------------- cook_plan：按每日锅数
rep('''    def cook_plan(self):
        """补足库存：不同菜 ≥ cook_target 种，优先未发现（受每日发现速率）、回复高、原料便宜。"""
        cfg = self.cfg; target = self.a['cook_target']
        for _ in range(12):
            distinct = sum(1 for k, v in self.dishes.items() if v > 0)
            if distinct >= target and sum(self.dishes.values()) >= target + 2:
                break
            cands = []
            for did, d in cfg['dishes'].items():
                used = self.can_make(d)
                if used is None:
                    continue
                new = did not in self.cooked_once
                if new and self.discover_today >= self.a['discover']:
                    continue
                if not new and self.dishes[did] >= 2:
                    continue
                cost = sum(cfg['fish'][i]['price'] if i in cfg['fish'] else cfg['crops'].get(i, {'price': 1})['price'] for i in used)
                r = cfg['restore'][d['rar']]
                cands.append((0 if new else 1, -r, cost, did, used))
            if not cands:
                break
            cands.sort(key=lambda x: (x[0], x[1], x[2]))
            _, _, _, did, used = cands[0]
            self.cook(did, used)
''',
'''    def expected_cook_xp(self, d, did):
        """一锅的期望 Cooking XP（不含首做、不含品质），用于排序。"""
        cfg = self.cfg
        n = self.page_pots_today[did]
        decay = cfg['cook_page_decay'][min(n, 2)]
        if decay <= 0:
            return 0.0
        dlv = self.level('cooking') - cfg['cook_content_lv'][d['rar']]
        m = 1.0 if dlv <= 1 else {2: 0.75, 3: 0.5, 4: 0.25}.get(dlv, 0.05)
        return cfg['cook_xp'][d['rar']] * m * decay

    def cook_plan(self, sessions_left=0):
        """r3：按画像每日锅数做菜（5 分钟 1–2、30 分钟 3–5、重度 6–10）；先做未发现页（受每日发现速率），
        再做重复页：优先今日未做（100%）、期望 XP 高、回复高、原料便宜；同一页今日第 3 锅起不做（0 XP）。
        多会话画像把当日剩余锅数均分到剩余会话。成品超过库存上限的部分视作赠礼 / 委托送出。"""
        cfg = self.cfg
        remaining = self.pots_today - self.pots_done_today
        if sessions_left > 0:
            remaining = math.ceil(remaining / (sessions_left + 1))
        for _ in range(max(0, remaining)):
            cands = []
            for did, d in cfg['dishes'].items():
                used = self.can_make(d)
                if used is None:
                    continue
                new = did not in self.cooked_once
                if new and self.discover_today >= self.a['discover']:
                    continue
                if not new and self.page_pots_today[did] >= 2:
                    continue
                cost = sum(cfg['fish'][i]['price'] if i in cfg['fish'] else cfg['crops'].get(i, {'price': 1})['price'] for i in used)
                r = cfg['restore'][d['rar']]
                exp_xp = self.expected_cook_xp(d, did)
                cands.append((0 if new else 1, -exp_xp, -r, self.dishes[did], cost, did, used))
            if not cands:
                break
            cands.sort(key=lambda x: x[:5])
            did, used = cands[0][5], cands[0][6]
            self.cook(did, used)
        # 库存上限：多出的成品送出（赠礼 / 委托），不回体力不计金币
        total = sum(v for v in self.dishes.values() if v > 0)
        excess = total - cfg['dish_stock_cap']
        while excess > 0:
            did = max((k for k, v in self.dishes.items() if v > 0), key=lambda k: self.dishes[k])
            self.dishes[did] -= 1; excess -= 1; self.gifted_total += 1
            self.daily[self.day()]['gifted'] += 1
''')

# ---------------------------------------------------------------- session：多会话均分锅数
rep("        # 做菜（出锅即时）、卖、买、升级\n        self.cook_plan()\n",
    "        # 做菜（出锅即时）、卖、买、升级\n        self.cook_plan(sessions_left=len(a['sessions']) - 1 - idx)\n")

# ---------------------------------------------------------------- 首会话蒙特卡洛：加 Cooking Lv2
rep('''        m = p.first_session_lv2_minute
        res.append(((m - 12 * 60) if m is not None else 99, p.xp['fishing'], p.first_session_end_energy, p.daily[1]['casts']))
    mins = sorted(r[0] for r in res)
    return dict(p30=sum(1 for m in mins if m <= 30) / trials, p45=sum(1 for m in mins if m <= 45) / trials,
                median=statistics.median(mins), p90=mins[int(0.9 * trials)],
                xp_med=statistics.median(r[1] for r in res), end_energy=statistics.median(r[2] for r in res),
                casts=statistics.mean(r[3] for r in res))''',
'''        m = p.first_session_lv2_minute; mc_ = p.first_session_cook_lv2_minute
        res.append(((m - 12 * 60) if m is not None else 99, p.xp['fishing'], p.first_session_end_energy, p.daily[1]['casts'],
                    (mc_ - 12 * 60) if mc_ is not None else 99, p.xp['cooking'], p.daily[1]['cooked']))
    mins = sorted(r[0] for r in res); cmins = sorted(r[4] for r in res)
    return dict(p30=sum(1 for m in mins if m <= 30) / trials, p45=sum(1 for m in mins if m <= 45) / trials,
                median=statistics.median(mins), p90=mins[int(0.9 * trials)],
                xp_med=statistics.median(r[1] for r in res), end_energy=statistics.median(r[2] for r in res),
                casts=statistics.mean(r[3] for r in res),
                cook_p30=sum(1 for m in cmins if m <= 30) / trials, cook_median=statistics.median(cmins), cook_p90=cmins[int(0.9 * trials)],
                cook_xp_med=statistics.median(r[5] for r in res), cook_pots=statistics.mean(r[6] for r in res))''')

# ---------------------------------------------------------------- summarize keys
rep("            'sink_greenhouse', 'sink_bag1', 'sink_tea', 'sink_decor', 'sink_travel_items', 'sown_energy', 'sow_short', 'meals', 'cooked', 'harvest_plots', 'fish_caught']",
    "            'sink_greenhouse', 'sink_bag1', 'sink_tea', 'sink_decor', 'sink_travel_items', 'sown_energy', 'sow_short', 'meals', 'cooked', 'harvest_plots', 'fish_caught',\n            'xp_cooking', 'gifted', 'income_fish', 'income_crops']")

# ---------------------------------------------------------------- snapshot：加 cook_lv
rep("        snaps.append(dict(wallet=p.wallet, inv=p.inventory_value(), farm_lv=p.level('farming'), fish_lv=p.level('fishing'), hs=p.hs,",
    "        snaps.append(dict(wallet=p.wallet, inv=p.inventory_value(), farm_lv=p.level('farming'), fish_lv=p.level('fishing'), cook_lv=p.level('cooking'), hs=p.hs,")

# ---------------------------------------------------------------- report：首会话行、里程碑、技能表、矿井占比、逐日表
rep('''    P(f'- P(≤30 min)={mc["p30"]:.3f}  P(≤45)={mc["p45"]:.3f}  中位 {mc["median"]:.1f} min  P90 {mc["p90"]:.1f} min  会话末 Fishing XP 中位 {mc["xp_med"]:.0f}  结束体力中位 {mc["end_energy"]:.0f}  平均竿数 {mc["casts"]:.1f}')''',
'''    P(f'- P(≤30 min)={mc["p30"]:.3f}  P(≤45)={mc["p45"]:.3f}  中位 {mc["median"]:.1f} min  P90 {mc["p90"]:.1f} min  会话末 Fishing XP 中位 {mc["xp_med"]:.0f}  结束体力中位 {mc["end_energy"]:.0f}  平均竿数 {mc["casts"]:.1f}')
    P(f'- Cooking Lv2（阈值 {cfg["cook_th"][1]}）：P(≤30 min)={mc["cook_p30"]:.3f}  中位 {mc["cook_median"]:.1f} min  P90 {mc["cook_p90"]:.1f} min  会话末 Cooking XP 中位 {mc["cook_xp_med"]:.0f}  平均锅数 {mc["cook_pots"]:.2f}')''')
rep("    keys = ['fishing_lv2', 'fishing_lv4', 'fishing_lv6', 'fishing_lv8', 'fishing_lv10', 'farming_lv2', 'farming_lv4', 'farming_lv6', 'farming_lv8', 'farming_lv10',\n            'hs_lv2',",
    "    keys = ['fishing_lv2', 'fishing_lv4', 'fishing_lv6', 'fishing_lv8', 'fishing_lv10', 'farming_lv2', 'farming_lv4', 'farming_lv6', 'farming_lv8', 'farming_lv10',\n            'cooking_lv2', 'cooking_lv4', 'cooking_lv6', 'cooking_lv8', 'cooking_lv10',\n            'hs_lv2',")
rep("    P('| 画像 | ' + ' | '.join(k.replace('fishing_', 'Fi').replace('farming_', 'Fa').replace('hs_', 'Hs').replace('rod_', '竿') for k in keys) + ' |')",
    "    P('| 画像 | ' + ' | '.join(k.replace('fishing_', 'Fi').replace('farming_', 'Fa').replace('cooking_', 'Co').replace('hs_', 'Hs').replace('rod_', '竿') for k in keys) + ' |')")
rep("    lv_keys = [f'{t}_lv{n}' for t in ('fishing', 'farming') for n in range(2, 11)]\n    P('| 画像 | ' + ' | '.join(k.replace('fishing_lv', 'Fi').replace('farming_lv', 'Fa') for k in lv_keys) + ' |')",
    "    lv_keys = [f'{t}_lv{n}' for t in ('fishing', 'farming', 'cooking') for n in range(2, 11)]\n    P('| 画像 | ' + ' | '.join(k.replace('fishing_lv', 'Fi').replace('farming_lv', 'Fa').replace('cooking_lv', 'Co') for k in lv_keys) + ' |')")
rep('''    P('\\n## 账本汇总（d8–d30 稳态；28 天吸收比）')''',
'''    P('\\n## 矿井 / 做菜 / 卖鱼（d8–d30 稳态）')
    P('| 画像 | 日均体力 | 其中矿洞 | 矿洞占比 | 日均锅数 | 日均送出 | 日均 Cooking XP | 日均卖鱼收入 | 日均卖菜收入 | 日均料理名义回复 |')
    P('|---|---|---|---|---|---|---|---|---|---|')
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        w = agg[7:min(30, days)]
        def M(k):
            return statistics.mean(a[k] for a in w)
        P(f'| {arch} | {M("energy"):.0f} | {M("energy_mine"):.0f} | {M("energy_mine") / max(1, M("energy")):.1%} | {M("cooked"):.1f} | {M("gifted"):.1f} | {M("xp_cooking"):.0f} | {M("income_fish"):.0f} | {M("income_crops"):.0f} | {M("meal_nominal"):.0f} |')
    P('\\n## 账本汇总（d8–d30 稳态；28 天吸收比）')''')
rep("        P('| 日 | 体力用 | 竿 | XP/竿 | 格 | Farm XP(累计/Lv) | Fish XP(累计/Lv) | 料理回复 | Rest/茶/奖励 | 撞墙 | 钱包 | 库存价值 | Hs | 收入 | 种子 | 去向 | 图鉴 | 印章 |')\n        P('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')\n        cf = cs = 0",
    "        P('| 日 | 体力用 | 竿 | XP/竿 | 格 | Farm XP(累计/Lv) | Fish XP(累计/Lv) | Cook XP(累计/Lv) | 锅 | 料理回复 | Rest/茶/奖励 | 撞墙 | 钱包 | 库存价值 | Hs | 收入 | 种子 | 去向 | 图鉴 | 印章 |')\n        P('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')\n        cf = cs = ck = 0")
rep('''            cf += a['xp_farming']; cs += a['xp_fishing']
            s = snaps[a['day'] - 1]
            P(f'| {a["day"]} | {a["energy"]:.0f} | {a["casts"]:.0f} | {a["xp_fishing"] / max(1, a["casts"]):.1f} | {a["harvest_plots"]:.0f} | {cf:.0f}/{s["farm_lv"]} | {cs:.0f}/{s["fish_lv"]} | {a["meal"]:.0f} |''',
'''            cf += a['xp_farming']; cs += a['xp_fishing']; ck += a['xp_cooking']
            s = snaps[a['day'] - 1]
            P(f'| {a["day"]} | {a["energy"]:.0f} | {a["casts"]:.0f} | {a["xp_fishing"] / max(1, a["casts"]):.1f} | {a["harvest_plots"]:.0f} | {cf:.0f}/{s["farm_lv"]} | {cs:.0f}/{s["fish_lv"]} | {ck:.0f}/{s["cook_lv"]} | {a["cooked"]:.1f} | {a["meal"]:.0f} |''')

# ---------------------------------------------------------------- checks：加 Cooking 与矿井
rep('''    chk('首会话 Fishing Lv2（30 分钟内）', mc['p30'] >= 0.95, f'P(≤30min)={mc["p30"]:.3f} 中位 {mc["median"]:.1f} min P90 {mc["p90"]:.1f}')''',
'''    chk('首会话 Fishing Lv2（30 分钟内）', mc['p30'] >= 0.95, f'P(≤30min)={mc["p30"]:.3f} 中位 {mc["median"]:.1f} min P90 {mc["p90"]:.1f}')
    chk('首会话 Cooking Lv2（30 分钟内，≥95%）', mc['cook_p30'] >= 0.95, f'P(≤30min)={mc["cook_p30"]:.3f} 中位 {mc["cook_median"]:.1f} min P90 {mc["cook_p90"]:.1f} 会话末 Cooking XP 中位 {mc["cook_xp_med"]:.0f}')
    ms30c = results['P30'][1]; mshc = results['HEAVY'][1]; ms5c = results['P5'][1]; mscc = results['P30C'][1]
    chk('Cooking：30 分钟玩家 Lv10 在 21±5 天', 16 <= ms30c.get('cooking_lv10', 99) <= 26, f'P30 d{ms30c.get("cooking_lv10", 99):.0f}（Lv4 第 3 槽 d{ms30c.get("cooking_lv4", 99):.0f}）；P30C d{mscc.get("cooking_lv10", 99):.0f}（Lv4 d{mscc.get("cooking_lv4", 99):.0f}）')
    chk('Cooking：重度 Lv10 ≥ 8 天', mshc.get('cooking_lv10', 99) >= 8, f'HEAVY d{mshc.get("cooking_lv10", 99):.0f}（Lv4 d{mshc.get("cooking_lv4", 99):.0f}）')
    chk('Cooking：5 分钟玩家 Lv10 ≤ 90 天（口径：≈100 可接受）', ms5c.get('cooking_lv10', 999) <= 90, f'P5 d{ms5c.get("cooking_lv10", 999):.0f}（Lv4 d{ms5c.get("cooking_lv4", 999):.0f}）')
    def mine_share(arch):
        w = results[arch][2][7:min(30, days)]
        return statistics.mean(a['energy_mine'] for a in w) / max(1, statistics.mean(a['energy'] for a in w))
    chk('矿井按层计费：30 分钟 / 重度矿洞体力占比 ≤ 12.5% / 13%', mine_share('P30') <= 0.125 and mine_share('HEAVY') <= 0.13,
        f'P30 {mine_share("P30"):.1%}（矿洞日 1 局 A = 28）；HEAVY {mine_share("HEAVY"):.1%}（B 56 + A 28 = 84）')''')

open(P, 'w').write(s)
print(f'ok: {n_rep} replacements')
