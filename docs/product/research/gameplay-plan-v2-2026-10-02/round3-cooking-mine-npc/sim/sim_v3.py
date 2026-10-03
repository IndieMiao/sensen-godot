#!/usr/bin/env python3
"""
sim_v3.py — Gensen 玩法方案 v2 第三轮复跑（内部校验工具，不进仓库）

从 sim_v2.py 复制后按第三轮定稿改四处：
  ① 加 Cooking 轨：阈值 0/30/100/220/400/650/950/1,350/1,700/2,350；第 3 投料槽在 Cooking Lv4（Lv1–3 = 2 槽，本期不开第 4/5 槽）；
     每锅 XP 按菜品稀有度 4/8/16/32，同一页每日第 1 锅 100%、第 2 锅 50%（向上取整）、第 3 锅起 0；Good ×1.25、Perfect ×1.5（向下取整）；
     内容等级按稀有度 Common 1 / Fine 2 / Rare 4 / Legendary 6，走与两轨相同的等级差衰减；首做 10/20/40/80 全归 Cooking；防脚本 3,000/日；
     升级回体力与两轨一致（账号首次升级 +50、其后 +30）；Lv2 升级礼 = 鲜鱼汤配方卡
     三类玩家做菜行为：5 分钟 1–2 锅/日、30 分钟 3–5 锅/日（含 1–2 道新页）、重度 6–10 锅/日；多余成品按赠礼/委托送出（库存上限 12）
  ② Fishing 首竿/首提 +5 → +10；首做料理 XP 从 Farming / Fishing 移除；"首次做成任何菜 +20 体力"按正文删除
  ③ 矿井按层计费：每层 2、电梯 0、A 局 28、B 局 56（原 34 / 58）
  ④ 其余不变

v2 规则（沿用）：
  体力池 200（Homestead +10/级）、+1/4 分钟线性回复、满停、无重置；新手祝福 7 天（回复 ×1.5、食物上限 +100）
  计费：播种按格按档 2/3/4/6（地区 4；多年生种下 6、每收 2）；抛竿 5（逃走退 3；Fishing Lv1–3 每日前 10 次失败全退）；
        进矿 10/局 + 2/岩石（A 局 34、B 局 58，每日 ≤2 局）；旅行 Trip 1–7 = 0/10/20/30/40/50/60 体力 + 0/20/60/120/200/300/500 金币
  回复：料理 20/40/70/70（品质 Good +5/+5/+10/+10、Perfect +20），每日食物上限 200（Homestead +10/级），同菜 100%/50%/0；
        Rest +60（每日 1 次）；茶 +30×3（40/50/60 金币）；居民赠餐（Common 20，占食物上限）；密友来访 +10；
        成就一次性（首次升级 +50、其后每级 +30、Homestead 升级回满、首次 Fine/Rare/Legendary 鱼 +20/30/50、首次做菜 +20、
        首道 Rare/Legendary +30/50、Cookbook 10/20/40 +30/50/70、Fish-dex 10/20 +30/50、首访新城 +10、探索者铜/银 +30/50）
  XP：等级差规则（d≤1 全额；2→75%；3→50%；4→25%；≥5 灰 5% 给 1），无日封顶；
      钓获 5/10/20/40，首钓 15/30/60/120，首城 +10，首竿/首提 +5/+5；收获 XP = 播种体力，首收 10/15/20/30（地区 20、多年生 15）；
      首做料理 10/20/40/80（归内容等级最高原料所在轨，同级含鱼归 Fishing）
  阈值：Fishing 0/70/220/480/850/1300/1850/2500/3300/4300；Farming 0/50/150/300/500/750/1050/1450/2050/2800
  鱼 20 种 / 作物 20 种 / 料理 47 页（标签匹配）/ 材料 8 种 / Homestead 十级（材料 + 金币 + 技能和 ≥ 2N−1）

用法：
  python3 sim_v2.py                       # 基表，120 天 × 6 seed
  python3 sim_v2.py --days 120 --seeds 6 --md out.md
  python3 sim_v2.py --fix A1,A2           # 叠加改表开关（见 FIX_DOC）
"""
import argparse, copy, math, random, statistics, sys
from collections import Counter, defaultdict

RAR = ['common', 'fine', 'rare', 'legendary']
RIDX = {r: i for i, r in enumerate(RAR)}


# ============================================================================
# 1. 内容表
# ============================================================================
def base_config():
    cfg = {}
    # --- 体力 ---
    cfg['energy_base'] = 200; cfg['energy_per_hs'] = 10
    cfg['regen_min'] = 4.0
    cfg['newcomer_days'] = 7; cfg['newcomer_mult'] = 1.5; cfg['newcomer_food'] = 100
    cfg['food_base'] = 200; cfg['food_per_hs'] = 10
    cfg['bonus_cap'] = 50
    cfg['meal_decay'] = [1.0, 0.5, 0.0]
    cfg['restore'] = {'common': 20, 'fine': 40, 'rare': 70, 'legendary': 70}
    cfg['good_bonus'] = {'common': 5, 'fine': 5, 'rare': 10, 'legendary': 10}
    cfg['p_good'] = 0.5; cfg['p_perfect'] = 0.2
    cfg['rest'] = 60; cfg['tea'] = 30; cfg['tea_price'] = [40, 50, 60]; cfg['tea_cups'] = 3
    cfg['gift_meal'] = 20; cfg['gift_meal_day'] = 5
    cfg['friend_visit'] = 10
    cfg['lvup_first'] = 50; cfg['lvup'] = 30
    cfg['first_fish_energy'] = {'fine': 20, 'rare': 30, 'legendary': 50}
    cfg['first_dish_energy'] = 0; cfg['first_rare_dish_energy'] = 30; cfg['first_legendary_dish_energy'] = 50   # r3：首次做成任何菜 +20 已删
    cfg['cookbook_energy'] = {10: 30, 20: 50, 40: 70}; cfg['cookbook_coins'] = {20: 100}
    cfg['fishdex_energy'] = {10: 30, 20: 50}; cfg['fishdex_coins'] = {10: 100, 20: 300}
    cfg['first_city_energy'] = 10
    cfg['explorer'] = {3: 30, 10: 50, 30: 70}
    # --- 计费 ---
    cfg['sow_cost'] = {1: 2, 2: 3, 3: 4, 4: 6, 'reg': 4}
    cfg['perennial_plant'] = 6; cfg['perennial_harvest'] = 2
    cfg['cast'] = 5; cfg['refund'] = 3; cfg['free_fail'] = 10; cfg['free_fail_lv'] = 3
    cfg['cast_sec'] = 40; cfg['cast_sec_worm'] = 30
    cfg['mine'] = {'A': (28, 4, {'stone': 12, 'copper': 3.9, 'rock_salt': 2.7, 'clay': 0.9, 'quartz': 0.9}),   # r3：层费 2×2 + 12 岩 × 2 = 28（原 34）
                   'B': (56, 8, {'stone': 24, 'copper': 8.1, 'rock_salt': 4.8, 'clay': 0.9, 'quartz': 3.0})}   # r3：层费 2×4 + 24 岩 × 2 = 56（原 58）
    cfg['mine_runs_per_day'] = 2
    cfg['travel'] = {1: (0, 0), 2: (10, 20), 3: (20, 60), 4: (30, 120), 5: (40, 200), 6: (50, 300), 7: (60, 500)}
    cfg['travel_time'] = {1: 0, 2: 0, 3: 2, 4: 5, 5: 10, 6: 20, 7: 30}
    cfg['stamp_req'] = {4: 3, 5: 5, 6: 8, 7: 12}
    cfg['permit_craft'] = 100; cfg['permit_buy'] = 250
    cfg['ticket_craft'] = (150, 2, 2); cfg['ticket_buy'] = 600
    # --- XP ---
    cfg['fish_th'] = [0, 70, 220, 480, 850, 1300, 1850, 2400, 3100, 4000]   # v2 终表（原 2,500/3,300/4,300，−7%）
    cfg['farm_th'] = [0, 50, 150, 300, 500, 750, 1050, 1450, 2050, 2800]
    cfg['fish_xp'] = {'common': 5, 'fine': 10, 'rare': 20, 'legendary': 40}
    cfg['first_species'] = {'common': 15, 'fine': 30, 'rare': 60, 'legendary': 120}
    cfg['first_city_xp'] = 10; cfg['first_cast_xp'] = 10; cfg['first_hook_xp'] = 10   # r3：+5/+5 → +10/+10
    cfg['first_harvest'] = {1: 10, 2: 15, 3: 20, 4: 30, 'reg': 20, 'per': 15}
    cfg['dish_first_xp'] = {'common': 10, 'fine': 20, 'rare': 40, 'legendary': 80}   # r3：全部归 Cooking
    # --- Cooking 轨（r3）---
    cfg['cook_th'] = [0, 30, 100, 220, 400, 650, 950, 1350, 1700, 2350]
    cfg['cook_xp'] = {'common': 4, 'fine': 8, 'rare': 16, 'legendary': 32}
    cfg['cook_content_lv'] = {'common': 1, 'fine': 2, 'rare': 4, 'legendary': 6}
    cfg['cook_page_decay'] = [1.0, 0.5, 0.0]
    cfg['cook_quality_mult'] = {'normal': 1.0, 'good': 1.25, 'perfect': 1.5}
    cfg['cook_slot_lv3'] = 4          # 第 3 投料槽的 Cooking 等级
    cfg['dish_stock_cap'] = 12        # 成品库存上限；超出按赠礼 / 委托送出（0 体力 0 金币）
    cfg['friend_xp_mult'] = 1.2
    cfg['anti_script_cap'] = 3000
    # --- 作物: id -> dict ---
    C = {}
    def crop(i, tier, lv, seed, hours, yld, price, fam, rar, reg=False):
        C[i] = dict(tier=tier, lv=lv, seed=seed, hours=hours, yld=yld, price=price, fam=fam, rar=rar, reg=reg)
    crop('radish', 1, 1, 4, 4, 1, 5, 'field', 'common')
    crop('lettuce', 1, 1, 6, 8, 1, 8, 'field', 'common')
    crop('herb', 1, 2, 2, 3, 3, 1, 'seasoning', 'common')
    crop('carrot', 2, 2, 9, 12, 1, 12, 'field', 'common')
    crop('potato', 2, 3, 9, 10, 2, 6, 'field', 'common')
    crop('chamomile', 3, 3, 12, 18, 1, 16, 'orchard', 'fine')
    crop('chili', 1, 4, 3, 6, 2, 2, 'seasoning', 'common')
    crop('tomato', 3, 4, 12, 14, 2, 8, 'field', 'fine')
    crop('cabbage', 2, 5, 10, 12, 1, 13, 'field', 'common')
    crop('corn', 3, 5, 11, 16, 3, 5, 'field', 'fine')
    crop('cucumber', 2, 6, 7, 9, 2, 5, 'field', 'common')
    crop('strawberry', 4, 8, 17, 20, 3, 8, 'orchard', 'rare')
    crop('melon', 4, 9, 20, 24, 1, 27, 'orchard', 'rare')
    crop('sweet_potato', 'reg', 5, 15, 16, 2, 10, 'field', 'rare', True)   # 家城（亚热带）地区作物
    cfg['crops'] = C
    cfg['regional_per_day'] = 10
    # 多年生: id -> (lv, price, first_h, regrow_h, yield, unit_price, rar)
    cfg['perennials'] = {'apple': (7, 40, 48, 48, 2, 3, 'fine'), 'citrus': (9, 80, 72, 48, 2, 5, 'rare'), 'grape': (9, 60, 60, 48, 3, 3, 'rare')}
    # --- 鱼: id -> (rar, lv, price, sites, regional_climates, night_only) ---
    F = {}
    def fish(i, rar, lv, price, sites, clim=None, night=False):
        F[i] = dict(rar=rar, lv=lv, price=price, sites=sites, clim=clim, night=night)
    fish('crucian', 'common', 1, 3, ('pond', 'river'))
    fish('carp', 'common', 1, 4, ('pond', 'river'))
    fish('mullet', 'common', 1, 4, ('coast', 'river'))
    fish('perch', 'fine', 2, 7, ('river', 'pond'))
    fish('bass', 'fine', 2, 7, ('pond', 'river'))
    fish('trout', 'fine', 2, 8, ('river',))
    fish('mackerel', 'fine', 2, 8, ('coast',))
    fish('koi', 'rare', 4, 13, ('pond',))
    fish('catfish', 'rare', 4, 14, ('river', 'pond'))
    fish('seabass', 'rare', 5, 14, ('coast',))
    fish('sturgeon', 'legendary', 7, 28, ('pond', 'river', 'coast'))
    fish('eel', 'legendary', 9, 30, ('river', 'pond'), night=True)
    fish('tilapia', 'common', 1, 4, ('pond', 'river'), ('tropical', 'subtropical'))
    fish('smelt', 'common', 1, 4, ('coast', 'river'), ('temperate', 'cool'))
    fish('grass_carp', 'fine', 3, 8, ('pond', 'river'), ('tropical', 'subtropical', 'temperate'))
    fish('arctic_char', 'fine', 3, 9, ('pond', 'river'), ('temperate', 'cool'))
    fish('snakehead', 'rare', 5, 14, ('pond', 'river'), ('tropical', 'subtropical', 'temperate'))
    fish('pike', 'rare', 5, 14, ('pond', 'river'), ('temperate', 'cool'))
    fish('barramundi', 'rare', 6, 15, ('coast', 'river'), ('tropical', 'subtropical'), night=True)
    fish('salmon', 'legendary', 8, 32, ('river', 'coast'), ('temperate', 'cool'))
    cfg['fish'] = F
    cfg['home_regional'] = ('grass_carp', 'snakehead'); cfg['home_climate'] = 'subtropical'
    cfg['sites'] = {'pond': [60, 30, 9, 1], 'river': [35, 40, 20, 5], 'coast': [30, 35, 25, 10]}
    cfg['bait_mod'] = {None: [0, 0, 0, 0], 'worm': [-10, 10, 0, 0], 'lure': [-15, -5, 15, 5]}
    cfg['bait_price'] = {'worm': (2, 2, 30), 'lure': (5, 6, 10)}   # (lv, price, stock/day)
    cfg['rods'] = {'starter': dict(cap=1, p=[0.90, 0.80, 0, 0], lv=1, price=0),
                   'reed': dict(cap=2, p=[0.90, 0.80, 0.72, 0], lv=3, price=80),
                   'carbon': dict(cap=3, p=[0.90, 0.82, 0.78, 0.62], lv=6, price=350)}
    cfg['trap'] = dict(lv=5, price=120, per_8h=1, cap=3); cfg['trap_slots'] = {5: 1, 8: 2, 10: 3}
    # 异城地区鱼（簇序号 → 两种）
    cfg['city_pairs'] = {'subtropical': [('tilapia', 'snakehead'), ('grass_carp', 'barramundi'), ('tilapia', 'grass_carp'), ('tilapia', 'barramundi')],
                         'temperate': [('smelt', 'pike'), ('smelt', 'salmon'), ('arctic_char', 'snakehead'), ('smelt', 'arctic_char'), ('arctic_char', 'salmon'), ('grass_carp', 'pike')]}
    # --- 料理 47 页: (id, rarity, ingredients[list of id|tag], has_fish) ---
    D = []
    def dish(i, rar, ingr):
        D.append(dict(id=i, rar=rar, ingr=ingr, slots=len(ingr)))
    dish('grilled_crucian', 'common', ['crucian']); dish('grilled_fish', 'common', ['tag_fish_common'])
    dish('carp_cakes', 'common', ['carp', 'carp']); dish('mullet_skewers', 'common', ['mullet', 'mullet'])
    dish('radish_salad', 'common', ['radish', 'lettuce']); dish('veggie_plate', 'common', ['tag_veg_common'])
    dish('carrot_cake', 'common', ['carrot', 'carrot']); dish('cabbage_stew', 'common', ['cabbage', 'potato'])
    dish('herb_grilled_fish', 'fine', ['tag_fish_common', 'tag_seasoning']); dish('salt_grilled_fish', 'fine', ['tag_fish_common', 'rock_salt'])
    dish('fish_soup', 'fine', ['tag_fish_common', 'tag_veg_common']); dish('tilapia_wraps', 'fine', ['tilapia', 'lettuce'])
    dish('crispy_smelt', 'fine', ['smelt', 'rock_salt']); dish('pan_fried_fish', 'fine', ['tag_fish_fine'])
    dish('rock_salt_soup', 'fine', ['tag_veg_common', 'rock_salt']); dish('salted_potatoes', 'fine', ['potato', 'potato', 'rock_salt'])
    dish('cucumber_salad', 'fine', ['cucumber', 'herb']); dish('fruit_tea', 'fine', ['tag_fruit_fine'])
    dish('apple_tea', 'fine', ['chamomile', 'apple', 'apple']); dish('roast_veggies', 'fine', ['tag_veg_fine'])
    dish('corn_cake', 'fine', ['corn', 'corn'])
    dish('charcoal_fish', 'rare', ['tag_fish_rare']); dish('fruit_platter', 'rare', ['tag_fruit_rare']); dish('harvest_roast', 'rare', ['tag_veg_rare'])
    dish('herb_baked_perch', 'rare', ['perch', 'herb']); dish('bass_tomato_stew', 'rare', ['bass', 'tomato'])
    dish('smoked_trout', 'rare', ['trout', 'wild_herb', 'rock_salt']); dish('salt_mackerel', 'rare', ['mackerel', 'rock_salt'])
    dish('grass_carp_soup', 'rare', ['grass_carp', 'radish']); dish('char_chowder', 'rare', ['arctic_char', 'potato'])
    dish('catfish_stew', 'rare', ['catfish', 'potato']); dish('sea_bass_salt', 'rare', ['seabass', 'rock_salt'])
    dish('chili_snakehead', 'rare', ['snakehead', 'chili']); dish('grilled_pike', 'rare', ['pike', 'wild_herb'])
    dish('pineapple_barra', 'rare', ['barramundi', 'pineapple']); dish('fisher_stew', 'rare', ['tag_fish_fine', 'potato', 'rock_salt'])
    dish('strawberry_tart', 'rare', ['strawberry', 'strawberry', 'herb']); dish('melon_platter', 'rare', ['melon', 'strawberry'])
    dish('orchard_tea', 'rare', ['grape', 'citrus', 'chamomile'])
    dish('legend_sashimi', 'legendary', ['tag_fish_legendary']); dish('steamed_sturgeon', 'legendary', ['sturgeon', 'herb', 'rock_salt'])
    dish('eel_skewers', 'legendary', ['eel', 'chili', 'rock_salt']); dish('herb_salmon', 'legendary', ['salmon', 'herb'])
    dish('pineapple_fish', 'legendary', ['pineapple', 'tag_fish_common', 'chili']); dish('sweet_potato_cakes', 'legendary', ['sweet_potato', 'tag_fish_common', 'herb'])
    dish('pumpkin_chowder', 'legendary', ['pumpkin', 'tag_fish_fine', 'rock_salt']); dish('beet_fish_soup', 'legendary', ['beet', 'tag_fish_common', 'rock_salt'])
    cfg['dishes'] = {d['id']: d for d in D}
    cfg['tags'] = {'tag_fish_common': ['crucian', 'carp', 'mullet', 'tilapia', 'smelt'],
                   'tag_fish_fine': ['perch', 'bass', 'trout', 'mackerel', 'grass_carp', 'arctic_char'],
                   'tag_fish_rare': ['catfish', 'seabass', 'snakehead', 'pike', 'barramundi'],
                   'tag_fish_legendary': ['sturgeon', 'eel', 'salmon'],
                   'tag_veg_common': ['radish', 'lettuce', 'carrot', 'potato', 'cabbage', 'cucumber'],
                   'tag_veg_fine': ['tomato', 'corn'], 'tag_veg_rare': ['sweet_potato', 'pumpkin', 'beet'],
                   'tag_fruit_fine': ['chamomile', 'apple'], 'tag_fruit_rare': ['pineapple', 'strawberry', 'melon', 'citrus', 'grape'],
                   'tag_seasoning': ['herb', 'chili', 'wild_herb', 'rock_salt']}
    # --- 材料 ---
    cfg['gather'] = {'wood': 6, 'stone': 4, 'fiber': 3, 'wild_herb': 2, 'clay': 2, 'hardwood': 1}   # 每轮
    cfg['gather_hs'] = {'clay': 2, 'hardwood': 3}
    cfg['gather_cd'] = 8 * 60; cfg['gather_worms'] = 2
    cfg['material_floor'] = {'wood': 2, 'stone': 0.5, 'fiber': 1, 'copper': 4, 'rock_salt': 2, 'clay': 2, 'quartz': 5, 'hardwood': 4, 'wild_herb': 1}
    cfg['pickaxe'] = {'copper': 5, 'wood': 4}; cfg['gloves'] = {'fiber': 8, 'wood': 4}
    # --- Homestead Lv2..10: (coins, wood, stone, fiber, copper, clay, quartz, hardwood, rock_salt) ---
    cfg['homestead'] = [
        (250, 12, 8, 6, 0, 0, 0, 0, 3),
        (400, 16, 12, 10, 0, 4, 0, 0, 4),
        (550, 20, 16, 10, 6, 6, 0, 0, 4),
        (750, 20, 16, 12, 10, 8, 2, 0, 4),
        (1000, 20, 18, 12, 10, 8, 3, 3, 0),
        (1450, 20, 20, 10, 12, 8, 4, 4, 0),   # Lv7–10 金币 +10%（原 1,300/1,650/2,050/2,600）
        (1800, 18, 18, 8, 12, 8, 4, 6, 0),
        (2250, 14, 16, 6, 12, 4, 4, 7, 0),
        (2850, 10, 16, 6, 13, 4, 5, 8, 0),
    ]
    cfg['hs_skill_gate'] = lambda n: 2 * n - 1
    cfg['plot_cap'] = lambda hs: 200 + 40 * (hs - 1) if hs <= 6 else 400 + 50 * (hs - 6)
    cfg['perennial_slots'] = lambda hs: min(8, 1 + hs)
    cfg['slots'] = lambda cook_lv: 2 if cook_lv < cfg['cook_slot_lv3'] else 3   # r3：槽位随 Cooking Lv，不随 Homestead
    cfg['bag_upgrade'] = {3: (150, {'fiber': 10, 'wood': 6}), 6: (400, {'hardwood': 4, 'clay': 6, 'copper': 4}), 9: (1000, {'hardwood': 8, 'quartz': 4, 'copper': 8})}
    cfg['greenhouse'] = (8, 300, {'wood': 20, 'stone': 12, 'copper': 8})
    cfg['barter'] = dict(per_day=6, share=0.5)
    # --- 经济 ---
    cfg['initial_wallet'] = 180; cfg['wallet_floor'] = 40
    cfg['compost_price'] = 2
    cfg['recipe_card'] = [30, 80]
    cfg['decor'] = [30, 40, 50, 60, 80, 90, 120]
    return cfg


FIX_DOC = {
    'A1': '技能节阈值表：Fishing Lv7–10 1,850/2,500/3,300/4,300 → 1,700/2,300/3,000/3,900（−10%，对照：让 25 竿/日的 30 分钟玩家落进 21±5）',
    'A2': '技能节阈值表：Farming Lv8–10 1,450/2,050/2,800 → 1,350/1,900/2,600（−7%，对照）',
    'A3': '（已并入基表）农场等级节 8.2.1：Lv7–10 金币 1,450/1,800/2,250/2,850；开关保留无效果',
    'A3B': '对照：Lv7–10 金币 +15%（1,500/1,900/2,350/3,000）',
    'A4': '农场等级节 8.2.1：Lv8–10 硬木 6/7/8 → 7/8/9（对照：重度冲刺不早于 30 天）',
    'A5': '体力节 3.4.4：茶价 40/50/60 → 60/75/90（对照：重度金币去向）',
    'A6': '鱼节 6.2：全部售价 ×0.85（对照：压重度/休闲账户价值比）',
    'A7': '经济节 9.14：农场驿站每日前 40 条鱼全价，第 41 条起 ×0.5（对照：压重度/休闲账户价值比）',
    'A8': '（已并入基表）技能节阈值表：Fishing Lv8–10 2,400/3,100/4,000；开关保留无效果',
    'A9': '对照（不推荐）：食物上限 200 → 120、茶 3 杯 → 1 杯——验证“把重度/休闲压到 1.8 要付出什么”',
    'C1': '旋钮：Farming Lv8–10 阈值 1,450/2,050/2,800 → 1,375/1,950/2,650（−5%，补首做 XP 移出的损失）',
    'C2': '旋钮：Fishing Lv8–10 阈值 2,400/3,100/4,000 → 2,300/2,950/3,800（−5%）',
    'C3': '对照：第 3 投料槽在 Cooking Lv3（100 XP）而不是 Lv4（220 XP）',
    'C4': '对照：矿洞体力回到原模型 34 / 58（只看矿井改表的影响）',
    'C5': '对照：首做料理 XP 不移交（仍归原料轨），只看“做菜给 XP”对两轨的影响为 0 的核验',
    'C6': '对照：首会话前 3 竿不强制（90% 成功率随机），看 Cooking Lv2 的慢路径',
    'C7': '对照：厨房不为 Homestead 预留岩盐（做菜与升级抢盐）',
    'C8': '对照：省料做法——重复锅按原料最便宜排序（Common/Fine 为主），不追 XP；看 Homestead 与收入的另一端',
    'C1X': '对照：Farming Lv8–10 阈值 −10%（1,300/1,850/2,500）——把 30 分钟下端拉回 26 天内需要的幅度',
    'C2X': '对照：Fishing Lv8–10 阈值 −10%（2,150/2,800/3,600）',
    'C9': '对照：Homestead Lv7–10 金币回到上一轮前的 1,300/1,650/2,050/2,600（抵消厨房吃掉的收入）',
}


def apply_fixes(cfg, fixes):
    cfg = copy.deepcopy(cfg)
    if 'A1' in fixes:
        cfg['fish_th'] = [0, 70, 220, 480, 850, 1300, 1700, 2300, 3000, 3900]
    if 'A2' in fixes:
        cfg['farm_th'] = [0, 50, 150, 300, 500, 750, 1050, 1350, 1900, 2600]
    if 'A3' in fixes:
        hs = cfg['homestead']
        for i, c in zip(range(5, 9), [1450, 1800, 2250, 2850]):
            r = list(hs[i]); r[0] = c; hs[i] = tuple(r)
    if 'A3B' in fixes:
        hs = cfg['homestead']
        for i, c in zip(range(5, 9), [1500, 1900, 2350, 3000]):
            r = list(hs[i]); r[0] = c; hs[i] = tuple(r)
    if 'A4' in fixes:
        hs = cfg['homestead']
        for i, h in zip(range(6, 9), [7, 8, 9]):
            r = list(hs[i]); r[7] = h; hs[i] = tuple(r)
    if 'A5' in fixes:
        cfg['tea_price'] = [60, 75, 90]
    if 'A6' in fixes:
        for f in cfg['fish'].values():
            f['price'] = max(1, round(f['price'] * 0.85))
    if 'A7' in fixes:
        cfg['fish_quota'] = 40
    if 'A8' in fixes:
        cfg['fish_th'] = [0, 70, 220, 480, 850, 1300, 1850, 2400, 3100, 4000]
    if 'A9' in fixes:
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
    if 'C6' in fixes:
        cfg['tutorial_forced_casts'] = False
    if 'C7' in fixes:
        cfg['reserve_salt_for_homestead'] = False
    if 'C8' in fixes:
        cfg['cook_economical'] = True
    if 'C1X' in fixes:
        cfg['farm_th'] = [0, 50, 150, 300, 500, 750, 1050, 1300, 1850, 2500]
    if 'C2X' in fixes:
        cfg['fish_th'] = [0, 70, 220, 480, 850, 1300, 1850, 2150, 2800, 3600]
    if 'C9' in fixes:
        hs = cfg['homestead']
        for i, c in zip(range(5, 9), [1300, 1650, 2050, 2600]):
            r = list(hs[i]); r[0] = c; hs[i] = tuple(r)
    return cfg


# ============================================================================
# 2. 玩家画像
# ============================================================================
ARCHETYPES = {
    'P5':  dict(label='5 分钟/日 · 钓鱼向（20 格 + 10 竿；40 s/竿 实际会话约 9 分钟）', sessions=[(20 * 60, 9)], farm_energy=[50], casts=[10],
                gather=True, mine=('A', 3), cook_target=2, discover=0.7, worms=3, lures=2, tea='never', travel='none',
                friend=False, buy='light', requests=4, helper=0, meal_plan=False, pots=(1, 2)),
    'P5B': dict(label='5 分钟/日 · 体力章画像（30 格 + 5 竿）', sessions=[(20 * 60, 5)], farm_energy=[70], casts=[5],
                gather=True, mine=('A', 3), cook_target=2, discover=0.7, worms=2, lures=0, tea='never', travel='none',
                friend=False, buy='light', requests=4, helper=0, meal_plan=False, pots=(1, 2)),
    'P30': dict(label='30 分钟/日 · 钓鱼向（≈34 竿 + 130 体力种植，隔日 1 局 A）', sessions=[(20 * 60, 30)], farm_energy=[130], casts=[34],
                gather=True, mine=('A', 2), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',
                friend=False, buy='balanced', requests=15, helper=3, meal_plan=True, pots=(3, 5)),
    'P30B': dict(label='30 分钟/日 · 体力章画像（40 格 + 1 局 A + 15 竿）', sessions=[(20 * 60, 30)], farm_energy=[112], casts=[15],
                 gather=True, mine=('A', 1), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',
                 friend=False, buy='balanced', requests=15, helper=3, meal_plan=True, pots=(3, 5)),
    'P30C': dict(label='30 分钟/日 · 折中（25 竿 + 110 体力，隔日 1 局 A）', sessions=[(20 * 60, 30)], farm_energy=[110], casts=[25],
                 gather=True, mine=('A', 2), cook_target=5, discover=1.5, worms=10, lures=5, tea='need', travel='weekly',
                 friend=False, buy='balanced', requests=15, helper=3, meal_plan=True, pots=(3, 5)),
    'HEAVY': dict(label='重度（08:00 与 20:00 各 2 小时；77 竿 + 80 格 + A + B + 每日 Trip 3）', sessions=[(8 * 60, 120), (20 * 60, 120)],
                  farm_energy=[180, 50], casts=[27, 50], gather=True, mine=[('B', 1), ('A', 1)], cook_target=6, discover=2.5,
                  worms=30, lures=10, tea='daily', travel='daily', friend=True, buy='balanced', requests=32, helper=6, meal_plan=True, pots=(6, 10)),
}
ARCHETYPES['H_FOCUS'] = dict(ARCHETYPES['HEAVY'], label='重度 · 冲刺（只买必需，不喝茶）', buy='sprint', tea='need')
ARCHETYPES['P30_FOCUS'] = dict(ARCHETYPES['P30'], label='30 分钟 · 冲刺（只买必需）', buy='sprint')
ARCHETYPES['HF_FISH'] = dict(ARCHETYPES['HEAVY'], label='重度 · 全钓（上界）', farm_energy=[0, 0], casts=[200, 200], mine=[])
ARCHETYPES['HF_FARM'] = dict(ARCHETYPES['HEAVY'], label='重度 · 全种（上界）', farm_energy=[10 ** 6, 10 ** 6], casts=[0, 0], mine=[])

CROP_KEEP = {'potato': 6, 'radish': 4, 'lettuce': 3, 'tomato': 3, 'cabbage': 2, 'corn': 2, 'cucumber': 2, 'carrot': 3,
             'chamomile': 2, 'strawberry': 3, 'melon': 2, 'sweet_potato': 8, 'apple': 3, 'citrus': 2, 'grape': 2,
             'pineapple': 2, 'pumpkin': 2, 'beet': 2}
FISH_KEEP = {'common': 6, 'fine': 4, 'rare': 3, 'legendary': 2}


class Player:
    def __init__(self, arch, cfg, rng):
        self.a = ARCHETYPES[arch]; self.arch = arch; self.cfg = cfg; self.rng = rng
        self.t = 0.0; self.t0_reg = 12 * 60
        self.hs = 1
        self.energy = self.energy_max(); self.regen_acc = 0.0; self.last_t = 0.0
        self.wallet = cfg['initial_wallet']
        self.inv = Counter()          # 鱼 / 作物 / 调味 / 鱼饵
        self.dishes = Counter()       # dish id -> n（含品质差异合并，品质用 good 概率即时结算）
        self.dish_bonus = {}          # dish id -> 累计品质加成（吃时按均值）
        self.mats = Counter()
        self.plots = []               # (crop, ready_at, xp_locked, first)
        self.perennials = []          # [pid, ready_at, first_pending_xp]
        self.xp = {'farming': 0, 'fishing': 0, 'cooking': 0}
        self.rod = 'starter'; self.traps = 0; self.trap_last = None
        self.pickaxe = False; self.gloves = False; self.greenhouse = False; self.bag_levels = set()
        self.discovered = set(['grilled_crucian', 'radish_salad'])
        self.cooked_once = set()
        self.first_crops = set(); self.first_fish = set(); self.first_rar = set(); self.first_dish_rar = set()
        self.first_cast = False; self.first_hook = False; self.first_levelup = False
        self.cities = {'home'}; self.city_visits = Counter({'home': 1}); self.stamps = 0; self.climates = {cfg['home_climate']}
        self.next_city = 1; self.explorer_got = set()
        self.permits = 0; self.tickets = 0
        self.gather_next = {k: 0.0 for k in cfg['gather']}
        self.day_id = None
        self.reset_day()
        self.daily = defaultdict(Counter)
        self.milestones = {}
        self.sink_total = Counter(); self.income_total = Counter(); self.seed_total = 0
        self.first_session_lv2_minute = None
        self.first_session_cook_lv2_minute = None
        self.gifted_total = 0
        self.walls = Counter()
        self.p30_meal = []            # (used_before_meal, meal_restore, max)
        self.wall_reason = Counter()
        self.last_session_end = -10 ** 9

    # ------------------------------------------------------------ 基础
    def reset_day(self):
        self.meals_today = 0; self.dish_count_today = Counter(); self.tea_today = 0; self.rest_today = False
        self.fails_today = 0; self.mine_runs_today = 0; self.regional_today = 0; self.friend_today = False
        self.discover_today = 0.0; self.stamps_today = 0; self.bait_bought_today = Counter(); self.barter_today = 0
        self.wall_today = 0; self.gift_today = 0; self.request_paid = False; self.day_xp = {'farming': 0, 'fishing': 0, 'cooking': 0}; self.fish_sold_today = 0
        self.page_pots_today = Counter(); self.pots_done_today = 0
        lo, hi = self.a.get('pots', (0, 0)); self.pots_today = self.rng.randint(lo, hi) if hi > 0 else 0

    def energy_max(self):
        return self.cfg['energy_base'] + self.cfg['energy_per_hs'] * (self.hs - 1)

    def newcomer(self):
        return (self.t - self.t0_reg) < self.cfg['newcomer_days'] * 1440

    def food_cap(self):
        return self.cfg['food_base'] + self.cfg['food_per_hs'] * (self.hs - 1) + (self.cfg['newcomer_food'] if self.newcomer() else 0)

    def settle(self, t):
        if t < self.t:
            t = self.t
        dt = t - self.last_t
        self.last_t = t; self.t = t
        mx = self.energy_max()
        if self.energy < mx and dt > 0:
            rate = (1.0 / self.cfg['regen_min']) * (self.cfg['newcomer_mult'] if self.newcomer() else 1.0)
            self.regen_acc += dt * rate
            g = int(self.regen_acc)
            if g > 0:
                self.regen_acc -= g
                self.energy = min(mx, self.energy + g)
        else:
            self.regen_acc = 0.0
        self.check_day(t)

    def check_day(self, t):
        d = int((t - 4 * 60) // 1440) + 1
        if self.day_id != d:
            self.day_id = d
            self.reset_day()

    def day(self):
        return self.day_id

    def level(self, track):
        th = self.cfg['fish_th'] if track == 'fishing' else self.cfg['farm_th'] if track == 'farming' else self.cfg['cook_th']
        lv = 1
        for i, v in enumerate(th):
            if self.xp[track] >= v:
                lv = i + 1
        return lv

    def ld_xp(self, base, d):
        """等级差折减 + 随机取整"""
        if d <= 1:
            return base
        if d >= 5:
            return 1 if self.rng.random() < 0.05 else 0
        m = {2: 0.75, 3: 0.5, 4: 0.25}[d]
        v = base * m; lo = int(v)
        return lo + (1 if self.rng.random() < v - lo else 0)

    def add_energy_bonus(self, n, kind):
        """社交 / 成就类：可超上限 ≤ +50"""
        cap = self.energy_max() + self.cfg['bonus_cap']
        self.energy = min(cap, self.energy + n)
        self.daily[self.day()]['bonus_' + kind] += n
        self.daily[self.day()]['bonus'] += n

    def add_xp(self, track, amount, oneoff=False):
        if amount <= 0:
            return 0
        if not oneoff:
            room = self.cfg['anti_script_cap'] - self.day_xp[track]
            amount = max(0, min(amount, room)); self.day_xp[track] += amount
        before = self.level(track)
        self.xp[track] += amount
        self.daily[self.day()]['xp_' + track] += amount
        after = self.level(track)
        for lv in range(before + 1, after + 1):
            self.milestones.setdefault(f'{track}_lv{lv}', self.day())
            if not self.first_levelup:
                self.first_levelup = True; self.add_energy_bonus(self.cfg['lvup_first'], 'achv')
            else:
                self.add_energy_bonus(self.cfg['lvup'], 'achv')
            if track == 'fishing' and lv == 2 and self.first_session_lv2_minute is None:
                self.first_session_lv2_minute = self.t
            if track == 'cooking' and lv == 2 and self.first_session_cook_lv2_minute is None:
                self.first_session_cook_lv2_minute = self.t
                self.discovered.add('fish_soup')   # 升级礼：鲜鱼汤配方卡
        return amount

    def spend(self, n, kind):
        if self.energy < n:
            return False
        self.energy -= n
        self.daily[self.day()]['energy_' + kind] += n
        self.daily[self.day()]['energy'] += n
        return True

    def pay(self, coins, sink):
        if coins > self.wallet:
            return False
        self.wallet -= coins
        self.sink_total[sink] += coins
        self.daily[self.day()]['sink'] += coins; self.daily[self.day()]['sink_' + sink] += coins
        return True

    def earn(self, coins, src):
        self.wallet += coins; self.income_total[src] += coins
        self.daily[self.day()]['income'] += coins; self.daily[self.day()]['income_' + src] += coins

    # ------------------------------------------------------------ 恢复
    def recover(self, need, allow_tea=True, allow_rest=True):
        """让 energy ≥ need；顺序 吃 → Rest → 茶。返回是否成功。"""
        if self.energy >= need:
            return True
        self.eat(need=need)
        if self.energy >= need:
            return True
        if allow_rest and not self.rest_today and self.rest_ok:
            self.rest_today = True
            gain = min(self.cfg['rest'], self.energy_max() - self.energy)
            self.energy += gain; self.daily[self.day()]['rest'] += gain
            if self.energy >= need:
                return True
        if allow_tea and self.a['tea'] != 'never':
            while self.energy < need and self.tea_today < self.cfg['tea_cups']:
                price = self.cfg['tea_price'][self.tea_today]
                if self.wallet - price < self.cfg['wallet_floor'] + (0 if self.a['tea'] == 'daily' else 150):
                    break
                self.pay(price, 'tea'); self.tea_today += 1
                gain = min(self.cfg['tea'], self.energy_max() - self.energy)
                self.energy += gain; self.daily[self.day()]['tea'] += gain
        return self.energy >= need

    def wall(self, reason):
        self.wall_today += 1; self.walls[self.day()] += 1; self.wall_reason[reason] += 1
        self.daily[self.day()]['walls'] += 1

    def eat(self, need=None):
        """need=None：只在不浪费时吃；need 给定：吃到 energy ≥ need 为止（允许少量浪费）"""
        cfg = self.cfg; cap = self.food_cap(); mx = self.energy_max()
        ate_total = 0
        while True:
            if need is None:
                headroom = mx - self.energy
                if headroom < 20:
                    break
            elif self.energy >= need:
                break
            if self.meals_today >= cap or self.energy >= mx:
                break
            best = None
            for did, n in self.dishes.items():
                if n <= 0:
                    continue
                rar = 'common' if did == 'gift' else cfg['dishes'][did]['rar']
                nominal = cfg['restore'][rar] + self.dish_bonus.get(did, 0)
                mult = cfg['meal_decay'][min(self.dish_count_today[did], 2)]
                eff = math.ceil(nominal * mult)
                # 新手祝福只作用于自然回复（体力章 3.4.6），料理不乘 1.5
                if eff <= 0:
                    continue
                if need is None and eff > mx - self.energy:
                    continue
                if best is None or eff > best[0]:
                    best = (eff, did, nominal)
            if best is None:
                break
            eff, did, nominal = best
            self.dishes[did] -= 1; self.dish_count_today[did] += 1
            remaining = cap - self.meals_today
            eff = min(eff, remaining); nominal = min(nominal, remaining)
            self.meals_today += nominal
            gain = min(eff, mx - self.energy)
            self.energy += gain; ate_total += gain
            self.daily[self.day()]['meal'] += gain; self.daily[self.day()]['meal_nominal'] += nominal; self.daily[self.day()]['meals'] += 1
        return ate_total

    # ------------------------------------------------------------ 作物
    def crop_unlocked(self, cid):
        return self.level('farming') >= self.cfg['crops'][cid]['lv']

    def harvest(self):
        ripe = [p for p in self.plots if p[1] <= self.t]
        self.plots = [p for p in self.plots if p[1] > self.t]
        value = 0
        for cid, _, xpl, _ in ripe:
            c = self.cfg['crops'][cid]
            self.inv[cid] += c['yld']; value += c['yld'] * c['price']
            if cid not in self.first_crops:
                self.first_crops.add(cid)
                self.add_xp('farming', self.cfg['first_harvest']['reg' if c['reg'] else c['tier']], oneoff=True)
            self.add_xp('farming', xpl)
        self.daily[self.day()]['harvest_value'] += value; self.daily[self.day()]['harvest_plots'] += len(ripe)
        for p in self.perennials:
            if p[1] <= self.t:
                if not self.recover(2, allow_tea=False):
                    continue
                lv, price, fh, rh, yld, up, rar = self.cfg['perennials'][p[0]]
                self.spend(2, 'farm')
                self.inv[p[0]] += yld; p[1] = self.t + rh * 60
                d = self.level('farming') - lv
                if p[2] is not None:
                    self.add_xp('farming', p[2]); p[2] = None
                    if p[0] not in self.first_crops:
                        self.first_crops.add(p[0]); self.add_xp('farming', self.cfg['first_harvest']['per'], oneoff=True)
                self.add_xp('farming', self.ld_xp(2, d))
                self.daily[self.day()]['harvest_value'] += yld * up

    def crop_cost(self, cid):
        c = self.cfg['crops'][cid]
        return self.cfg['sow_cost']['reg' if c['reg'] else c['tier']]

    def sow(self, energy_budget):
        """按等级差优先（d≤1 全额）与每格毛利选作物；受钱包、开垦上限、地区日额度约束。"""
        if energy_budget <= 0:
            return 0
        cfg = self.cfg; lv = self.level('farming')
        cands = []
        for cid, c in cfg['crops'].items():
            if not self.crop_unlocked(cid):
                continue
            d = lv - c['lv']
            cost = self.crop_cost(cid)
            net = (c['yld'] * c['price'] - c['seed']) / cost
            cands.append((0 if d <= 1 else d, -net, c['hours'], cid))
        cands.sort()
        # 调味 / 料理第二原料：少量固定种植
        fixed = []
        if self.crop_unlocked('herb'):
            fixed.append(('herb', 3))
        if self.crop_unlocked('chili'):
            fixed.append(('chili', 1))
        if self.crop_unlocked('potato'):
            fixed.append(('potato', 3))
        main = [cid for _, _, _, cid in cands if cid not in ('herb', 'chili')][:3]
        shares = [0.5, 0.3, 0.2]
        sown_e = 0; cost_coins = 0
        def plant(cid, n):
            nonlocal sown_e, cost_coins
            c = cfg['crops'][cid]; e = self.crop_cost(cid); k = 0
            while k < n:
                if sown_e + e > energy_budget or self.wallet - c['seed'] < 0 or self.energy < e:
                    break
                if len(self.plots) + len(self.perennials) * 4 >= cfg['plot_cap'](self.hs):
                    break
                if c['reg'] and self.regional_today >= cfg['regional_per_day']:
                    break
                self.spend(e, 'farm'); self.wallet -= c['seed']; cost_coins += c['seed']; sown_e += e
                self.seed_total += c['seed']
                d = self.level('farming') - c['lv']
                self.plots.append((cid, self.t + c['hours'] * 60, self.ld_xp(e, d), cid not in self.first_crops))
                if c['reg']:
                    self.regional_today += 1
                k += 1
                self.t += 2 / 60
            return k
        for cid, n in fixed:
            if self.inv[cid] < 6:
                plant(cid, n)
        # 新解锁作物各试 1 格（首收）
        for cid in cfg['crops']:
            if self.crop_unlocked(cid) and cid not in self.first_crops and not any(p[0] == cid for p in self.plots):
                plant(cid, 1)
        for cid, sh in zip(main, shares):
            e = self.crop_cost(cid)
            plant(cid, int((energy_budget - sown_e) * sh / e) + 1)
        for cid in main:
            plant(cid, 10 ** 6)
        if sown_e < energy_budget and self.energy >= 2:
            # 预算没花完（钱包或格数限制）：记录
            self.daily[self.day()]['sow_short'] += energy_budget - sown_e
        self.daily[self.day()]['seed_cost'] += cost_coins; self.daily[self.day()]['sown_energy'] += sown_e
        return sown_e

    # ------------------------------------------------------------ 采集 / 矿
    def gather(self):
        cfg = self.cfg
        for k, n in cfg['gather'].items():
            if self.hs < cfg['gather_hs'].get(k, 1):
                continue
            if self.t >= self.gather_next[k]:
                self.gather_next[k] = self.t + cfg['gather_cd']
                got = n + (1 if self.gloves else 0)
                self.mats[k] += got
                self.daily[self.day()]['material_value'] += got * cfg['material_floor'][k]
                if k == 'fiber':
                    self.inv['worm'] += cfg['gather_worms']
        self.t += 0.5

    def mine(self, kind):
        e, mins, out = self.cfg['mine'][kind]
        if self.mine_runs_today >= self.cfg['mine_runs_per_day']:
            return False
        if not self.recover(e):
            self.wall('mine'); return False
        self.spend(e, 'mine'); self.mine_runs_today += 1
        for mat, v in out.items():
            n = int(v) + (1 if self.rng.random() < v - int(v) else 0)
            if mat == 'stone' and self.pickaxe:
                n *= 2
            self.mats[mat] += n
            self.daily[self.day()]['material_value'] += n * self.cfg['material_floor'][mat]
        self.t += mins
        return True

    # ------------------------------------------------------------ 钓鱼
    def pick_bait(self):
        if self.inv['lure'] > 0 and self.level('fishing') >= 5:
            self.inv['lure'] -= 1; return 'lure'
        if self.inv['worm'] > 0 and self.level('fishing') >= 2:
            self.inv['worm'] -= 1; return 'worm'
        return None

    def fish_site(self, city):
        lv = self.level('fishing')
        if lv >= 5 and self.rod in ('reed', 'carbon'):
            return 'coast'
        if lv >= 4 and self.rod in ('reed', 'carbon'):
            return 'river'
        return 'pond'

    def cast(self, site, city='home', regional=None, friend=False, night=False):
        cfg = self.cfg; lv = self.level('fishing')
        if not self.recover(cfg['cast']):
            self.wall('cast'); return None
        self.spend(cfg['cast'], 'fish')
        bait = self.pick_bait()
        w = [max(0, a + b) for a, b in zip(cfg['sites'][site], cfg['bait_mod'][bait])]
        tier = self.rng.choices([0, 1, 2, 3], weights=w)[0]
        regional = regional or cfg['home_regional']
        cands = []
        for fid, f in cfg['fish'].items():
            if RIDX[f['rar']] != tier or site not in f['sites']:
                continue
            if f['night'] and not night:
                continue
            if f['clim'] is not None and fid not in regional:
                continue
            cands.append((fid, (2 if bait == 'lure' else 1) * 2 if f['clim'] is not None else 1))
        while not cands and tier > 0:
            tier -= 1
            cands = [(fid, 1) for fid, f in cfg['fish'].items() if RIDX[f['rar']] == tier and site in f['sites'] and f['clim'] is None and not f['night']]
        fid = self.rng.choices([c for c, _ in cands], weights=[w for _, w in cands])[0]
        f = cfg['fish'][fid]
        if not self.first_cast:
            self.first_cast = True; self.add_xp('fishing', cfg['first_cast_xp'], oneoff=True)
        self.t += (cfg['cast_sec_worm'] if bait == 'worm' else cfg['cast_sec']) / 60
        self.daily[self.day()]['casts'] += 1
        escaped = f['lv'] > lv or tier > cfg['rods'][self.rod]['cap']
        ok = (not escaped) and self.rng.random() < cfg['rods'][self.rod]['p'][tier]
        if not ok:
            self.fails_today += 1
            refund = cfg['cast'] if (lv <= cfg['free_fail_lv'] and self.fails_today <= cfg['free_fail']) else cfg['refund']
            self.energy = min(self.energy_max(), self.energy + refund)
            self.daily[self.day()]['energy'] -= refund; self.daily[self.day()]['energy_fish'] -= refund
            return False
        if not self.first_hook:
            self.first_hook = True; self.add_xp('fishing', cfg['first_hook_xp'], oneoff=True)
        self.inv[fid] += 1
        self.daily[self.day()]['fish_value'] += f['price']; self.daily[self.day()]['fish_caught'] += 1
        if f['clim'] is not None:
            self.climates.add(cfg['home_climate'] if city == 'home' else self.city_climate(city))
        if fid not in self.first_fish:
            self.first_fish.add(fid); self.add_xp('fishing', cfg['first_species'][f['rar']], oneoff=True)
            n = len(self.first_fish)
            if n in cfg['fishdex_energy']:
                self.add_energy_bonus(cfg['fishdex_energy'][n], 'achv'); self.earn(cfg['fishdex_coins'][n], 'achv')
        if f['rar'] in cfg['first_fish_energy'] and f['rar'] not in self.first_rar:
            self.first_rar.add(f['rar']); self.add_energy_bonus(cfg['first_fish_energy'][f['rar']], 'achv')
        if city not in self.cities:
            self.cities.add(city); self.add_xp('fishing', cfg['first_city_xp'], oneoff=True)
        d = lv - f['lv']
        g = self.ld_xp(cfg['fish_xp'][f['rar']], d)
        if friend:
            g = int(g * cfg['friend_xp_mult'])
        self.add_xp('fishing', g)
        return True

    def city_climate(self, city):
        i = int(city[4:]) if city.startswith('city') else 0
        return 'temperate' if i % 4 == 3 else 'subtropical'

    def city_regional(self, city):
        i = int(city[4:]); clim = self.city_climate(city)
        pairs = self.cfg['city_pairs'][clim]
        return pairs[i % len(pairs)]

    def collect_traps(self):
        if self.traps == 0:
            return
        if self.trap_last is None:
            self.trap_last = self.t; return
        n = min(self.cfg['trap']['cap'], int((self.t - self.trap_last) // 480))
        if n <= 0:
            return
        self.trap_last += n * 480
        for _ in range(n * self.traps):
            tier = self.rng.choices([0, 1], weights=[60, 30])[0]
            fid = self.rng.choice(['crucian', 'carp']) if tier == 0 else self.rng.choice(['perch', 'bass'])
            self.inv[fid] += 1
            self.daily[self.day()]['fish_value'] += self.cfg['fish'][fid]['price']
            d = self.level('fishing') - self.cfg['fish'][fid]['lv']
            self.add_xp('fishing', self.ld_xp(self.cfg['fish_xp'][self.cfg['fish'][fid]['rar']] // 2, d))

    # ------------------------------------------------------------ 料理
    def item_level(self, key):
        cfg = self.cfg
        if key.startswith('tag_'):
            ids = cfg['tags'][key]
            return min(self.item_level(i)[0] for i in ids), ('fishing' if 'fish' in key else 'farming')
        if key in cfg['fish']:
            return cfg['fish'][key]['lv'], 'fishing'
        if key in cfg['crops']:
            return cfg['crops'][key]['lv'], 'farming'
        if key in cfg['perennials']:
            return cfg['perennials'][key][0], 'farming'
        return 1, 'none'

    def resolve(self, key, tmp):
        if key.startswith('tag_'):
            opts = [i for i in self.cfg['tags'][key] if tmp[i] > 0]
            if not opts:
                return None
            return min(opts, key=lambda i: self.cfg['fish'][i]['price'] if i in self.cfg['fish'] else self.cfg['crops'].get(i, {'price': 1})['price'])
        return key if tmp[key] > 0 else None

    def can_make(self, d):
        if d['slots'] > self.cfg['slots'](self.level('cooking')):
            return None
        tmp = Counter({k: v for k, v in self.inv.items()}); tmp.update({k: self.mats[k] for k in ('rock_salt', 'wild_herb')})
        # r3：岩盐同时是 Homestead Lv2–5 配额与料理调味；厨房只用“下一级升级所需”之外的盈余
        if self.hs < 10 and self.cfg.get('reserve_salt_for_homestead', True):
            tmp['rock_salt'] -= self.hs_row()[8]
        used = []
        for key in d['ingr']:
            fid = self.resolve(key, tmp)
            if fid is None:
                return None
            tmp[fid] -= 1; used.append(fid)
        return used

    def cook(self, did, used):
        cfg = self.cfg; d = cfg['dishes'][did]
        for fid in used:
            if fid in ('rock_salt', 'wild_herb'):
                self.mats[fid] -= 1
            else:
                self.inv[fid] -= 1
        self.dishes[did] += 1
        self.t += (5 if d['rar'] == 'common' else 15 if d['rar'] == 'fine' else 30 if d['rar'] == 'rare' else 60) / 60 + 0.1
        # 品质：Good 概率 p_good；Rare/Legendary 两次火候 → Perfect 概率
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
                self.add_energy_bonus(cfg['first_dish_energy'], 'achv')
            if d['rar'] in ('rare', 'legendary') and d['rar'] not in self.first_dish_rar:
                self.add_energy_bonus(cfg['first_rare_dish_energy'] if d['rar'] == 'rare' else cfg['first_legendary_dish_energy'], 'achv')
            self.first_dish_rar.add(d['rar'])
            n = len(self.cooked_once)
            if n in cfg['cookbook_energy']:
                self.add_energy_bonus(cfg['cookbook_energy'][n], 'achv')
            if n in cfg['cookbook_coins']:
                self.earn(cfg['cookbook_coins'][n], 'achv')

    def expected_cook_xp(self, d, did):
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
                if cfg.get('cook_economical'):
                    cands.append((0 if new else 1, cost, -r, self.dishes[did], -exp_xp, did, used))
                else:
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

    # ------------------------------------------------------------ 买卖 / 升级
    def sell(self):
        cfg = self.cfg
        for k, n in list(self.inv.items()):
            if n <= 0 or k in ('worm', 'lure'):
                continue
            if k in cfg['fish']:
                keep = FISH_KEEP[cfg['fish'][k]['rar']]
                price = cfg['fish'][k]['price']; src = 'fish'
                if 'fish_quota' in cfg and self.fish_sold_today >= cfg['fish_quota']:
                    price = price * 0.5
            elif k in cfg['crops']:
                if k in ('herb', 'chili'):
                    continue
                keep = CROP_KEEP.get(k, 2); price = cfg['crops'][k]['price']; src = 'crops'
            elif k in cfg['perennials']:
                keep = CROP_KEEP.get(k, 2); price = cfg['perennials'][k][5]; src = 'crops'
            else:
                continue
            sellable = n - keep
            if sellable > 0:
                self.inv[k] -= sellable; self.earn(sellable * price, src)
                if src == 'fish':
                    self.fish_sold_today += sellable

    def hs_row(self):
        return self.cfg['homestead'][self.hs - 1]

    def try_upgrade(self):
        cfg = self.cfg
        if self.hs >= 10:
            return
        coins, wood, stone, fiber, copper, clay, quartz, hardwood, salt = self.hs_row()
        need = {'wood': wood, 'stone': stone, 'fiber': fiber, 'copper': copper, 'clay': clay, 'quartz': quartz, 'hardwood': hardwood, 'rock_salt': salt}
        n = self.hs + 1
        if self.level('farming') + self.level('fishing') < cfg['hs_skill_gate'](n):
            self.daily[self.day()]['hs_block'] = 'skills'; return
        # 换料：缺矿物时用地区作物 2:1 换（≤50% 配额，≤6 次/日）
        for m in ('stone', 'clay', 'copper', 'quartz'):
            lack = need[m] - self.mats[m]
            while lack > 0 and self.inv['sweet_potato'] >= 2 and self.barter_today < cfg['barter']['per_day'] and self.mats[m] < need[m] * cfg['barter']['share'] + lack:
                self.inv['sweet_potato'] -= 2; self.mats[m] += 1; self.barter_today += 1; lack -= 1
                self.daily[self.day()]['barter'] += 1
        lacking = [m for m, q in need.items() if self.mats[m] < q]
        if lacking:
            self.daily[self.day()]['hs_block'] = ','.join(lacking); return
        if self.wallet - coins < cfg['wallet_floor'] + self.seed_reserve():
            self.daily[self.day()]['hs_block'] = 'coins'; return
        for m, q in need.items():
            self.mats[m] -= q
        self.pay(coins, 'homestead'); self.hs = n
        self.energy = self.energy_max()   # 升级当场回满到新上限
        self.milestones.setdefault(f'hs_lv{self.hs}', self.day())

    def seed_reserve(self):
        return int(sum(self.a['farm_energy']) * 2.5)

    def purchases(self):
        cfg = self.cfg; a = self.a; reserve = self.seed_reserve() + cfg['wallet_floor']
        buy = a['buy']
        # 工具（材料）
        if not self.pickaxe and all(self.mats[k] >= v for k, v in cfg['pickaxe'].items()):
            for k, v in cfg['pickaxe'].items():
                self.mats[k] -= v
            self.pickaxe = True
        if not self.gloves and all(self.mats[k] >= v for k, v in cfg['gloves'].items()) and self.hs >= 2:
            for k, v in cfg['gloves'].items():
                self.mats[k] -= v
            self.gloves = True
        # 鱼竿（必需）
        for rod, r in cfg['rods'].items():
            if r['cap'] > cfg['rods'][self.rod]['cap'] and self.level('fishing') >= r['lv'] and self.wallet - r['price'] >= cfg['wallet_floor'] + (300 if (buy == 'light' and r['price'] >= 300) else 60):
                self.pay(r['price'], 'gear'); self.rod = rod; self.milestones.setdefault('rod_' + rod, self.day())
        # 鱼饵（必需：蚯蚓；亮片按画像）
        want = {'worm': a['worms'], 'lure': a['lures']}
        for bait, (lv, price, stock) in cfg['bait_price'].items():
            if self.level('fishing') < lv or want[bait] <= 0:
                continue
            n = max(0, min(want[bait] * 2 - self.inv[bait], stock - self.bait_bought_today[bait]))
            if n > 0 and self.wallet - n * price >= cfg['wallet_floor'] + (60 if bait == 'worm' else reserve):
                self.pay(n * price, 'bait'); self.inv[bait] += n; self.bait_bought_today[bait] += n
        # 堆肥（金币去向）
        if buy != 'light' and self.level('farming') >= 3:
            n = 5 if not self.arch.startswith('H') else 10
            if self.wallet - n * cfg['compost_price'] >= reserve + 100:
                self.pay(n * cfg['compost_price'], 'fertilizer')
        if buy == 'light':
            return
        # 农场升级优先：以下可选去向只在钱包超过下一级所需 + 储备时买
        next_cost = self.hs_row()[0] if self.hs < 10 else 0
        rich = self.wallet - reserve - (next_cost if buy == 'sprint' else next_cost * 0.5)
        # 鱼笼
        slots = max([0] + [v for k, v in cfg['trap_slots'].items() if self.level('fishing') >= k])
        if buy == 'balanced' and self.traps < slots and rich >= cfg['trap']['price']:
            self.pay(cfg['trap']['price'], 'gear'); self.traps += 1; rich -= cfg['trap']['price']
            if self.trap_last is None:
                self.trap_last = self.t
        # 树苗
        if buy == 'balanced':
            for pid, (lv, price, fh, rh, yld, up, rar) in cfg['perennials'].items():
                if len(self.perennials) < cfg['perennial_slots'](self.hs) and self.level('farming') >= lv and rich >= price and self.energy >= 6 \
                        and len(self.plots) + len(self.perennials) * 4 + 4 <= cfg['plot_cap'](self.hs):
                    self.pay(price, 'saplings'); self.spend(6, 'farm'); rich -= price
                    d = self.level('farming') - lv
                    self.perennials.append([pid, self.t + fh * 60, self.ld_xp(6, d)])
        # 背包扩容（硬木优先给升级：只有硬木超出下一级需求时才买）
        if buy == 'balanced':
            for hs_lv, (price, mats) in cfg['bag_upgrade'].items():
                if self.hs >= hs_lv and hs_lv not in self.bag_levels and rich >= price:
                    hw_need = self.hs_row()[7] if self.hs < 10 else 0
                    if all(self.mats[k] >= v + (hw_need if k == 'hardwood' else 0) for k, v in mats.items()):
                        for k, v in mats.items():
                            self.mats[k] -= v
                        self.pay(price, 'bag1' if hs_lv == 3 else 'bag'); self.bag_levels.add(hs_lv); rich -= price
        # 温室
        glv, gprice, gmats = cfg['greenhouse']
        if buy == 'balanced' and not self.greenhouse and self.level('farming') >= glv and rich >= gprice and all(self.mats[k] >= v for k, v in gmats.items()):
            for k, v in gmats.items():
                self.mats[k] -= v
            self.pay(gprice, 'greenhouse'); self.greenhouse = True; rich -= gprice
        # 配方卡 / 摆件（纯去向）
        if buy == 'balanced':
            every = 3 if self.arch.startswith('H') else 4
            if self.day() % every == 0 and rich >= 200 and self.sink_total['recipes'] < 1200:
                price = cfg['recipe_card'][self.day() % 2]
                self.pay(price, 'recipes'); rich -= price
            if self.arch.startswith('H') and self.day() % 5 == 0 and rich >= 500 and self.sink_total['decor'] < 600:
                price = cfg['decor'][(self.day() // 5) % len(cfg['decor'])]
                self.pay(price, 'decor'); rich -= price
        # 茶（重度每日 3 杯，作为日常去向；需要时的茶在 recover 里）
        if a['tea'] == 'daily':
            while self.tea_today < cfg['tea_cups'] and self.energy <= self.energy_max() - cfg['tea'] and self.wallet - cfg['tea_price'][self.tea_today] >= cfg['wallet_floor']:
                self.pay(cfg['tea_price'][self.tea_today], 'tea'); self.tea_today += 1
                self.energy += cfg['tea']; self.daily[self.day()]['tea'] += cfg['tea']
        # 门禁物品（旅行章）：许可与长途票制作，作为去向
        if a['travel'] != 'none':
            if self.permits == 0 and self.stamps >= cfg['stamp_req'][5] and len(self.climates) >= 2 and rich >= cfg['permit_craft']:
                self.pay(cfg['permit_craft'], 'travel_items'); self.permits += 1; rich -= cfg['permit_craft']
                self.milestones.setdefault('permit', self.day())
            tc, thw, tqz = cfg['ticket_craft']
            if self.tickets == 0 and self.permits >= 1 and self.hs >= 4 and self.stamps >= cfg['stamp_req'][6] and rich >= tc \
                    and self.mats['hardwood'] >= thw + (self.hs_row()[7] if self.hs < 10 else 0) and self.mats['quartz'] >= tqz + (self.hs_row()[6] if self.hs < 10 else 0):
                self.pay(tc, 'travel_items'); self.permits -= 1; self.tickets += 1
                self.mats['hardwood'] -= thw; self.mats['quartz'] -= tqz
                self.milestones.setdefault('ticket', self.day())

    # ------------------------------------------------------------ 旅行
    def travel(self):
        """去下一座新城（Trip 1 ×3 → Trip 2 ×7 → Trip 3 …）。返回 city 或 None。"""
        cfg = self.cfg
        if self.stamps_today >= 2:
            return None
        i = self.next_city
        tier = 1 if i <= 3 else 2 if i <= 10 else 3
        en, coins = cfg['travel'][tier]
        if coins > 0 and self.wallet - coins < cfg['wallet_floor'] + self.seed_reserve():
            return None
        if en > 0 and not self.recover(en):
            return None
        self.spend(en, 'travel'); self.pay(coins, 'travel')
        city = f'city{i}'; self.next_city += 1
        self.city_visits[city] += 1; self.stamps += 1; self.stamps_today += 1
        self.add_energy_bonus(cfg['first_city_energy'], 'social')
        for n, e in cfg['explorer'].items():
            if self.stamps >= n and n not in self.explorer_got:
                self.explorer_got.add(n); self.add_energy_bonus(e, 'achv')
        self.t += cfg['travel_time'][tier] + 1
        self.daily[self.day()]['travel'] = tier
        self.milestones.setdefault(f'stamps_{self.stamps}', self.day()) if self.stamps in (3, 5, 8, 12) else None
        return city

    # ------------------------------------------------------------ 账户价值
    def inventory_value(self):
        v = 0
        for k, n in self.inv.items():
            if n <= 0:
                continue
            if k in self.cfg['crops']:
                v += n * self.cfg['crops'][k]['price']
            elif k in self.cfg['fish']:
                v += n * self.cfg['fish'][k]['price']
            elif k in self.cfg['perennials']:
                v += n * self.cfg['perennials'][k][5]
        for k, n in self.mats.items():
            v += n * self.cfg['material_floor'].get(k, 0)
        return v

    # ============================================================ 会话
    def first_session(self, t0):
        """第 14 章导演表：播 20 小萝卜（起始包），3 竿强制鲫鱼，5 s 烤鲫鱼吃，播 10 生菜，第 4 竿强制 Fine 挣脱，
        继续到 Lv2，挂蚯蚓第 7 竿强制 Fine，做香草烤鱼（Keep）。"""
        cfg = self.cfg
        self.t0_reg = t0
        self.settle(t0); self.rest_ok = False
        end = t0 + 30
        self.inv['seed_radish'] = 20; self.inv['seed_lettuce'] = 10   # 起始包（不动用金币）
        self.t = t0 + 2
        for _ in range(20):
            self.spend(2, 'farm'); self.plots.append(('radish', self.t + 4 * 60, 2, True))
        self.daily[self.day()]['sown_energy'] += 40
        self.t = t0 + 9
        for i in range(3):
            self.settle(self.t); self.spend(5, 'fish'); self.daily[self.day()]['casts'] += 1
            if not self.first_cast:
                self.first_cast = True; self.add_xp('fishing', cfg['first_cast_xp'], oneoff=True)
            ok = True if cfg.get('tutorial_forced_casts', True) else self.rng.random() < 0.9   # r3：导演表“3 竿强制鲫鱼”
            self.t += 40 / 60
            if not ok:
                self.fails_today += 1; self.energy += 5; self.daily[self.day()]['energy'] -= 5; self.daily[self.day()]['energy_fish'] -= 5
                continue
            if not self.first_hook:
                self.first_hook = True; self.add_xp('fishing', cfg['first_hook_xp'], oneoff=True)
            self.inv['crucian'] += 1; self.daily[self.day()]['fish_value'] += 3; self.daily[self.day()]['fish_caught'] += 1
            if 'crucian' not in self.first_fish:
                self.first_fish.add('crucian'); self.add_xp('fishing', cfg['first_species']['common'], oneoff=True)
            if 'home_fished' not in self.cities:
                self.cities.add('home_fished'); self.add_xp('fishing', cfg['first_city_xp'], oneoff=True)
            self.add_xp('fishing', cfg['fish_xp']['common'])
        # 14–16: 交委托 2 条（+16）、烤鲫鱼并吃
        self.t = t0 + 14; self.settle(self.t)
        if self.inv['crucian'] >= 2:
            self.inv['crucian'] -= 2; self.earn(16, 'requests')
        if self.inv['crucian'] >= 1:
            self.cook('grilled_crucian', ['crucian']); self.eat(need=self.energy + 1)
        # 16–18: 播 10 生菜
        self.t = t0 + 16; self.settle(self.t)
        for _ in range(10):
            if self.energy >= 2:
                self.spend(2, 'farm'); self.plots.append(('lettuce', self.t + 8 * 60, 2, True))
        self.daily[self.day()]['sown_energy'] += 20
        # 18+: 第 4 竿强制 Fine 挣脱（保护期全退）；之后正常权重直到 Lv2
        self.t = t0 + 18; self.settle(self.t)
        self.spend(5, 'fish'); self.fails_today += 1; self.energy += 5; self.daily[self.day()]['energy'] -= 5; self.daily[self.day()]['energy_fish'] -= 5
        self.daily[self.day()]['casts'] += 1; self.t += 40 / 60
        k = 0
        while self.t < end - 3 and self.level('fishing') < 2 and k < 20:
            self.settle(self.t); self.cast('pond'); k += 1
        if self.level('fishing') >= 2:
            self.inv['worm'] += 3; self.mats['wild_herb'] += 3; self.discovered.add('herb_grilled_fish')
            # 第 7 竿：挂饵强制 Fine（河鲈）
            self.settle(self.t)
            if self.energy >= 5 and self.t < end - 1:
                self.spend(5, 'fish'); self.inv['worm'] -= 1; self.daily[self.day()]['casts'] += 1; self.t += 30 / 60
                self.inv['perch'] += 1; self.daily[self.day()]['fish_value'] += 7; self.daily[self.day()]['fish_caught'] += 1
                self.first_fish.add('perch'); self.add_xp('fishing', cfg['first_species']['fine'], oneoff=True)
                self.add_xp('fishing', cfg['fish_xp']['fine'])
                if 'fine' not in self.first_rar:
                    self.first_rar.add('fine'); self.add_energy_bonus(cfg['first_fish_energy']['fine'], 'achv')
            used = self.can_make(cfg['dishes']['herb_grilled_fish'])
            if used:
                self.cook('herb_grilled_fish', used)
        self.settle(end)
        self.first_session_end_energy = self.energy
        self.sell(); self.purchases()
        self.last_session_end = end

    def session(self, idx, t0, minutes, day):
        a = self.a; cfg = self.cfg
        self.settle(t0)
        self.rest_ok = (t0 - self.last_session_end) >= 120
        end = t0 + minutes
        morning = (t0 % 1440) < 12 * 60
        night = (t0 % 1440) >= 20 * 60 or (t0 % 1440) < 5 * 60
        # 委托 / 帮工日入流（0 体力来源）
        if not self.request_paid:
            self.request_paid = True
            if day >= 2:
                self.earn(a['requests'], 'requests')
            if day >= 7 and a['helper']:
                self.earn(a['helper'], 'helper')
        # 密友来访（重度）
        if a['friend'] and not self.friend_today and day >= 6:
            self.friend_today = True; self.add_energy_bonus(cfg['friend_visit'], 'social')
        # 居民赠餐（熟悉后每日 1 份 Common，所有居民合计）
        if day >= cfg['gift_meal_day'] and self.gift_today == 0:
            n = 1
            self.dishes['gift'] += n; self.gift_today = n
        self.harvest(); self.t += 0.3
        if a['gather']:
            self.gather()
        self.collect_traps()
        # 早餐 / 进场餐：条低于一半时吃一顿（不浪费）
        if self.energy < self.energy_max() * 0.5:
            self.eat()
        # 播种（早会话 / 单会话优先；重度晚会话补播）
        budget = a['farm_energy'][idx] if idx < len(a['farm_energy']) else 0
        if budget > 0:
            if not self.recover(min(budget, 20)):
                self.wall('sow')
            self.sow(budget); self.t += 0.3
        # 矿洞
        mine_spec = a['mine']
        if isinstance(mine_spec, list):
            if idx < len(mine_spec) and mine_spec[idx]:
                kind, every = mine_spec[idx]
                if every == 1 or day % every == 0:
                    self.mine(kind)
        elif mine_spec:
            kind, every = mine_spec
            if every == 1 or day % every == 0:
                self.mine(kind)
        # 旅行（晚会话 / 单会话）
        city = 'home'; regional = None
        if a['travel'] != 'none' and (not morning or len(a['sessions']) == 1) and day >= 4:
            go = (a['travel'] == 'daily') or (a['travel'] == 'weekly' and (day - 4) % 7 == 0)
            if go:
                c = self.travel()
                if c:
                    city = c; regional = self.city_regional(c)
        # 正餐：钓鱼前把体力吃到够钓（P30 口径记录）
        casts_target = a['casts'][idx] if idx < len(a['casts']) else 0
        used_before = self.energy_max() - self.energy
        if casts_target > 0 and a['meal_plan']:
            need = min(self.energy_max(), casts_target * 4.4)
            m = self.eat(need=need)
            m += self.eat()
            if self.arch.startswith('P30') and m > 0:
                self.p30_meal.append((used_before, m, self.energy_max()))
        # 钓鱼
        site = self.fish_site(city)
        casts = 0
        home_casts = casts_target if city == 'home' else max(0, casts_target - 30)
        while casts < casts_target and self.t + 40 / 60 <= end - 0.5:
            if self.wall_today >= 3 and self.energy < 5 and not self.recover(5):
                break
            if city != 'home' and casts >= home_casts:
                r = self.cast(self.fish_site(city), city, regional, friend=False, night=night)
            else:
                r = self.cast(site, 'home', None, friend=(a['friend'] and not morning), night=night)
            if r is None:
                break
            casts += 1
        # 重度晚场剩余体力补播
        if self.arch.startswith('H') and not morning and a['farm_energy'][0] > 0 and self.energy >= 20:
            self.sow(min(self.energy - 10, 60))
        # 做菜（出锅即时）、卖、买、升级
        self.cook_plan(sessions_left=len(a['sessions']) - 1 - idx)
        self.sell(); self.purchases(); self.try_upgrade()
        self.settle(max(self.t, end))
        self.daily[self.day()]['sessions'] += 1
        self.last_session_end = end


def run(arch, cfg, seed=0, days=30):
    rng = random.Random(seed)
    p = Player(arch, cfg, rng)
    p.first_session(12 * 60)
    for day in range(1, days + 1):
        for idx, (mod, minutes) in enumerate(p.a['sessions']):
            t0 = (day - 1) * 1440 + mod
            if day == 1 and t0 < 12 * 60 + 30:
                continue
            p.session(idx, t0, minutes, day)
    out = []
    for d in range(1, days + 1):
        rec = p.daily.get(d, Counter())
        out.append(dict(day=d, **rec))
    return p, out


# ============================================================================
# 3. 首会话蒙特卡洛
# ============================================================================
def first_session_mc(cfg, trials=2000):
    res = []
    for s in range(trials):
        rng = random.Random(s)
        p = Player('P30', cfg, rng)
        p.first_session(12 * 60)
        m = p.first_session_lv2_minute; mc_ = p.first_session_cook_lv2_minute
        res.append(((m - 12 * 60) if m is not None else 99, p.xp['fishing'], p.first_session_end_energy, p.daily[1]['casts'],
                    (mc_ - 12 * 60) if mc_ is not None else 99, p.xp['cooking'], p.daily[1]['cooked']))
    mins = sorted(r[0] for r in res); cmins = sorted(r[4] for r in res)
    return dict(p30=sum(1 for m in mins if m <= 30) / trials, p45=sum(1 for m in mins if m <= 45) / trials,
                median=statistics.median(mins), p90=mins[int(0.9 * trials)],
                xp_med=statistics.median(r[1] for r in res), end_energy=statistics.median(r[2] for r in res),
                casts=statistics.mean(r[3] for r in res),
                cook_p30=sum(1 for m in cmins if m <= 30) / trials, cook_median=statistics.median(cmins), cook_p90=cmins[int(0.9 * trials)],
                cook_xp_med=statistics.median(r[5] for r in res), cook_pots=statistics.mean(r[6] for r in res))


# ============================================================================
# 4. 报告
# ============================================================================
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
    agg = []
    keys = ['energy', 'xp_farming', 'xp_fishing', 'income', 'seed_cost', 'sink', 'meal', 'meal_nominal', 'harvest_value', 'fish_value',
            'material_value', 'casts', 'energy_farm', 'energy_fish', 'energy_mine', 'energy_travel', 'walls', 'rest', 'tea', 'bonus',
            'sink_homestead', 'sink_gear', 'sink_recipes', 'sink_bait', 'sink_fertilizer', 'sink_travel', 'sink_saplings', 'sink_bag',
            'sink_greenhouse', 'sink_bag1', 'sink_tea', 'sink_decor', 'sink_travel_items', 'sown_energy', 'sow_short', 'meals', 'cooked', 'harvest_plots', 'fish_caught',
            'xp_cooking', 'gifted', 'income_fish', 'income_crops']
    for d in range(1, days + 1):
        rows = [o[d - 1] for _, o in runs]
        agg.append(dict(day=d, **{k: statistics.mean([r.get(k, 0) for r in rows]) for k in keys}))
    return runs, ms, agg


def snapshot_run(arch, cfg, seed, days):
    rng = random.Random(seed)
    p = Player(arch, cfg, rng)
    p.first_session(12 * 60)
    snaps = []
    for day in range(1, days + 1):
        for idx, (mod, minutes) in enumerate(p.a['sessions']):
            t0 = (day - 1) * 1440 + mod
            if day == 1 and t0 < 12 * 60 + 30:
                continue
            p.session(idx, t0, minutes, day)
        snaps.append(dict(wallet=p.wallet, inv=p.inventory_value(), farm_lv=p.level('farming'), fish_lv=p.level('fishing'), cook_lv=p.level('cooking'), hs=p.hs,
                          energy=p.energy, dishes=sum(p.dishes.values()), stamps=p.stamps, cookbook=len(p.cooked_once), fishdex=len(p.first_fish)))
    return snaps


def report(cfg, seeds, days, md=None, label=''):
    lines = []
    def P(s=''):
        lines.append(s); print(s)
    P(f'# v2 模拟结果 {label}（seeds={seeds}, days={days}）')
    results = {}
    for arch in ('P5', 'P5B', 'P30', 'P30B', 'P30C', 'HEAVY'):
        results[arch] = summarize(arch, cfg, seeds, days)
    variants = {}
    for arch in ('H_FOCUS', 'P30_FOCUS', 'HF_FISH', 'HF_FARM'):
        variants[arch] = summarize(arch, cfg, seeds, min(days, 90))
    mc = first_session_mc(cfg)
    P(f'\n## 首会话 Fishing Lv2（阈值 {cfg["fish_th"][1]}；2,000 次）')
    P(f'- P(≤30 min)={mc["p30"]:.3f}  P(≤45)={mc["p45"]:.3f}  中位 {mc["median"]:.1f} min  P90 {mc["p90"]:.1f} min  会话末 Fishing XP 中位 {mc["xp_med"]:.0f}  结束体力中位 {mc["end_energy"]:.0f}  平均竿数 {mc["casts"]:.1f}')
    P(f'- Cooking Lv2（阈值 {cfg["cook_th"][1]}）：P(≤30 min)={mc["cook_p30"]:.3f}  中位 {mc["cook_median"]:.1f} min  P90 {mc["cook_p90"]:.1f} min  会话末 Cooking XP 中位 {mc["cook_xp_med"]:.0f}  平均锅数 {mc["cook_pots"]:.2f}')
    # 里程碑
    P('\n## 里程碑到达日（多 seed 平均；— = 未达）')
    keys = ['fishing_lv2', 'fishing_lv4', 'fishing_lv6', 'fishing_lv8', 'fishing_lv10', 'farming_lv2', 'farming_lv4', 'farming_lv6', 'farming_lv8', 'farming_lv10',
            'cooking_lv2', 'cooking_lv4', 'cooking_lv6', 'cooking_lv8', 'cooking_lv10',
            'hs_lv2', 'hs_lv3', 'hs_lv4', 'hs_lv5', 'hs_lv6', 'hs_lv7', 'hs_lv8', 'hs_lv9', 'hs_lv10', 'rod_reed', 'rod_carbon', 'stamps_12', 'permit', 'ticket']
    P('| 画像 | ' + ' | '.join(k.replace('fishing_', 'Fi').replace('farming_', 'Fa').replace('cooking_', 'Co').replace('hs_', 'Hs').replace('rod_', '竿') for k in keys) + ' |')
    P('|' + '---|' * (len(keys) + 1))
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        P(f'| {arch} | ' + ' | '.join((f'{ms[k]:.0f}' if k in ms and ms[k] <= days else '—') for k in keys) + ' |')
    P('\n## 技能逐级到达日')
    lv_keys = [f'{t}_lv{n}' for t in ('fishing', 'farming', 'cooking') for n in range(2, 11)]
    P('| 画像 | ' + ' | '.join(k.replace('fishing_lv', 'Fi').replace('farming_lv', 'Fa').replace('cooking_lv', 'Co') for k in lv_keys) + ' |')
    P('|' + '---|' * (len(lv_keys) + 1))
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        P(f'| {arch} | ' + ' | '.join((f'{ms[k]:.0f}' if k in ms and ms[k] <= days else '—') for k in lv_keys) + ' |')
    # 账本
    P('\n## 矿井 / 做菜 / 卖鱼（d8–d30 稳态）')
    P('| 画像 | 日均体力 | 其中矿洞 | 矿洞占比 | 日均锅数 | 日均送出 | 日均 Cooking XP | 日均卖鱼收入 | 日均卖菜收入 | 日均料理名义回复 |')
    P('|---|---|---|---|---|---|---|---|---|---|')
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        w = agg[7:min(30, days)]
        def M(k):
            return statistics.mean(a[k] for a in w)
        P(f'| {arch} | {M("energy"):.0f} | {M("energy_mine"):.0f} | {M("energy_mine") / max(1, M("energy")):.1%} | {M("cooked"):.1f} | {M("gifted"):.1f} | {M("xp_cooking"):.0f} | {M("income_fish"):.0f} | {M("income_crops"):.0f} | {M("meal_nominal"):.0f} |')
    P('\n## 账本汇总（d8–d30 稳态；28 天吸收比）')
    P('| 画像 | 日均体力消耗 | 日均竿 | 日均格 | 稳态每体力净金币 | 日均料理回复(名义) | 日均 Rest/茶/成就社交 | 稳态日净收入 | 28 日总收入(含初始) | 28 日非种子去向 | 下界(必需+升级) | 中界(+成长可选) | 上界(全部) | 稳态日撞墙 | 期末钱包 |')
    P('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    summary = {}
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        w = agg[7:min(30, days)]
        def M(k):
            return statistics.mean(a[k] for a in w)
        prod = sum(a['harvest_value'] + a['fish_value'] + a['material_value'] - a['seed_cost'] for a in w)
        vpe = prod / max(1, sum(a['energy'] for a in w))
        net = statistics.mean(a['income'] - a['seed_cost'] for a in w)
        w28 = agg[:28]
        inc28 = cfg['initial_wallet'] + sum(a['income'] - a['seed_cost'] for a in w28)
        sink28 = sum(a['sink'] for a in w28)
        must28 = sum(a['sink_homestead'] + a['sink_gear'] + a['sink_bait'] + a['sink_fertilizer'] + a['sink_travel'] + a['sink_travel_items'] for a in w28)
        # 中界 = 必需 + 成长可选（树苗、扩容 I、配方卡）+ 升级；扩容 II / III 与温室按农场等级章“Lv10 之后再买”只进上界
        mid28 = must28 + sum(a['sink_saplings'] + a['sink_bag1'] + a['sink_recipes'] for a in w28)
        walls = M('walls')
        p = runs[0][0]
        summary[arch] = dict(energy=M('energy'), vpe=vpe, net=net, inc28=inc28, sink28=sink28, must28=must28, share=sink28 / max(1, inc28),
                             share_low=must28 / max(1, inc28), share_mid=mid28 / max(1, inc28), meal=M('meal_nominal'), walls=walls, walls_max=max(a['walls'] for a in w), wallet=p.wallet,
                             prod_daily=prod / len(w))
        P(f'| {arch} | {M("energy"):.0f} | {M("casts"):.0f} | {M("harvest_plots"):.0f} | {vpe:.2f} | {M("meal_nominal"):.0f} | {M("rest"):.0f}/{M("tea"):.0f}/{M("bonus"):.0f} | {net:.0f} | {inc28:.0f} | {sink28:.0f} | {must28 / max(1, inc28):.0%} | {mid28 / max(1, inc28):.0%} | {sink28 / max(1, inc28):.0%} | {walls:.2f}（峰 {max(a["walls"] for a in w):.0f}） | {p.wallet:.0f} |')
    P('\n## 去向构成（28 天，多 seed 平均）')
    P('| 画像 | 升级 | 渔具 | 鱼饵 | 堆肥 | 旅行 | 门禁物品 | 茶 | 配方卡 | 树苗 | 背包 | 温室 | 摆件 |')
    P('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for arch, (runs, ms, agg) in results.items():
        w28 = agg[:28]
        def S(k):
            return sum(a[k] for a in w28)
        P(f'| {arch} | {S("sink_homestead"):.0f} | {S("sink_gear"):.0f} | {S("sink_bait"):.0f} | {S("sink_fertilizer"):.0f} | {S("sink_travel"):.0f} | {S("sink_travel_items"):.0f} | {S("sink_tea"):.0f} | {S("sink_recipes"):.0f} | {S("sink_saplings"):.0f} | {S("sink_bag"):.0f} | {S("sink_greenhouse"):.0f} | {S("sink_decor"):.0f} |')
    # 公平性
    def cum(arch, nd):
        return cfg['initial_wallet'] + sum(a['harvest_value'] + a['fish_value'] + a['material_value'] - a['seed_cost'] for a in results[arch][2][:nd])
    ratios = {}
    for base in ('P30', 'P30B', 'P5'):
        ratios[base] = dict(rd=summary['HEAVY']['prod_daily'] / summary[base]['prod_daily'],
                            r7=cum('HEAVY', 7) / cum(base, 7), r14=cum('HEAVY', 14) / cum(base, 14), r30=cum('HEAVY', 30) / cum(base, 30),
                            re=summary['HEAVY']['energy'] / summary[base]['energy'], rv=summary['HEAVY']['vpe'] / summary[base]['vpe'],
                            rnet=summary['HEAVY']['net'] / summary[base]['net'])
    P('\n## 账户价值比（重度 ÷ 休闲）')
    P('| 基准 | 稳态单日产值比 | 7 日累计 | 14 日 | 30 日 | 日均体力比 | 每体力净金币比 | 稳态日净收入比 |')
    P('|---|---|---|---|---|---|---|---|')
    for base, r in ratios.items():
        P(f'| 重度/{base} | {r["rd"]:.2f} | {r["r7"]:.2f} | {r["r14"]:.2f} | {r["r30"]:.2f} | {r["re"]:.2f} | {r["rv"]:.2f} | {r["rnet"]:.2f} |')
    # P30 会话
    P('\n## 30 分钟会话：正餐前用池比例与正餐回复（d8–d30 平均）')
    for arch in ('P30', 'P30B', 'P30C'):
        rows = []
        for p, _ in results[arch][0]:
            rows += [(u / mx, m / mx) for u, m, mx in p.p30_meal[7:30]]
        if rows:
            P(f'- {arch}: 正餐前已用 {statistics.mean(r[0] for r in rows):.0%} 的池；正餐回复 {statistics.mean(r[1] for r in rows):.0%} 的池（样本 {len(rows)}）')
    # 永动 / 撞墙
    P('\n## 料理不永动 & 撞墙（d8–d30）')
    for arch, (runs, ms, agg) in results.items():
        w = agg[7:min(30, days)]
        cap = cfg['food_base'] + cfg['food_per_hs'] * (runs[0][0].hs - 1)
        P(f'- {arch}: 日均料理名义回复 {statistics.mean(a["meal_nominal"] for a in w):.0f}（最大单日 {max(a["meal_nominal"] for a in w):.0f}）≤ 食物上限 {cap}；'
          f'日均消耗 {statistics.mean(a["energy"] for a in w):.0f} ≤ 上界 360+{cap}+60+90+20={360 + cap + 170}；日均撞墙 {statistics.mean(a["walls"] for a in w):.2f}（峰 {max(a["walls"] for a in w):.0f}）')
    # 旅行
    P('\n## 旅行：北京→洛杉矶（Trip 7）可达日')
    d = haversine(39.9, 116.4, 34.05, -118.24)
    P(f'- haversine 北京–洛杉矶 = {d:.0f} km → Trip 7 Antipodal：60 体力 + 500 金币 + 长途票（许可 100 + 150 金币 + 硬木 2 + 石英 2）+ 印章 ≥12 + Homestead Lv5 + 30 分钟旅途')
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        hs5 = ms.get('hs_lv5', days + 1); st12 = ms.get('stamps_12', days + 1); tk = ms.get('ticket', days + 1)
        reach = max(hs5, st12, tk)
        P(f'- {arch}: Homestead Lv5 第 {hs5:.0f} 天；印章 12 枚第 {st12:.0f} 天；长途票制成第 {tk:.0f} 天 → {"第 %.0f 天起可达" % reach if reach <= days else "%d 天内不可达" % days}')
    P('\n## 农场升级被卡原因（seed0，天数计）与特产换料次数（120 天）')
    for arch, (runs, ms, agg) in list(results.items()) + list(variants.items()):
        blocks = Counter(o.get('hs_block', '') for o in runs[0][1] if o.get('hs_block'))
        barter = sum(o.get('barter', 0) for o in runs[0][1])
        P(f'- {arch}: {dict(blocks.most_common(5))}；换料 {barter} 次')
    P('\n## 诊断：每竿 XP 网格（等级 × 渔场；30 分钟玩家装备策略：Lv2 蚯蚓、Lv3 芦苇、Lv5 亮片、Lv6 碳素；含失败与挣脱；3,000 竿均值）')
    P('| Fishing Lv | Pond | River | Coast |')
    P('|---|---|---|---|')
    for lv in range(1, 11):
        row = []
        for site in ('pond', 'river', 'coast'):
            rng = random.Random(500 + lv)
            q = Player('P30', cfg, rng); q.t = 10 * 1440; q.last_t = q.t; q.check_day(q.t); q.t0_reg = -10 ** 6
            q.xp['fishing'] = cfg['fish_th'][lv - 1]; q.first_fish = set(cfg['fish']); q.first_cast = q.first_hook = True; q.cities.add('home')
            q.rod = 'carbon' if lv >= 6 else 'reed' if lv >= 3 else 'starter'
            tot = 0; n = 3000
            for _ in range(n):
                q.energy = 200; q.inv['worm'] = 99; q.inv['lure'] = 99 if lv >= 5 else 0
                before = q.xp['fishing']; q.cast(site); tot += q.xp['fishing'] - before
                q.xp['fishing'] = cfg['fish_th'][lv - 1]; q.fails_today = 99; q.day_xp['fishing'] = 0
            row.append(tot / n)
        P(f'| {lv} | ' + ' | '.join(f'{v:.1f}' for v in row) + ' |')
    # 逐日表
    P('\n## 逐日关键表（前 30 天；seed 平均；快照为 seed0 日末）')
    for arch in ('P5', 'P30', 'HEAVY'):
        runs, ms, agg = results[arch]
        p = runs[0][0]
        P(f'\n### {arch} · {p.a["label"]}')
        P('| 日 | 体力用 | 竿 | XP/竿 | 格 | Farm XP(累计/Lv) | Fish XP(累计/Lv) | Cook XP(累计/Lv) | 锅 | 料理回复 | Rest/茶/奖励 | 撞墙 | 钱包 | 库存价值 | Hs | 收入 | 种子 | 去向 | 图鉴 | 印章 |')
        P('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
        cf = cs = ck = 0
        snaps = snapshot_run(arch, cfg, 0, days)
        for a in agg[:min(days, 30)]:
            cf += a['xp_farming']; cs += a['xp_fishing']; ck += a['xp_cooking']
            s = snaps[a['day'] - 1]
            P(f'| {a["day"]} | {a["energy"]:.0f} | {a["casts"]:.0f} | {a["xp_fishing"] / max(1, a["casts"]):.1f} | {a["harvest_plots"]:.0f} | {cf:.0f}/{s["farm_lv"]} | {cs:.0f}/{s["fish_lv"]} | {ck:.0f}/{s["cook_lv"]} | {a["cooked"]:.1f} | {a["meal"]:.0f} | {a["rest"]:.0f}/{a["tea"]:.0f}/{a["bonus"]:.0f} | {a["walls"]:.1f} | {s["wallet"]:.0f} | {s["inv"]:.0f} | {s["hs"]} | {a["income"]:.0f} | {a["seed_cost"]:.0f} | {a["sink"]:.0f} | {s["cookbook"]}/{s["fishdex"]} | {s["stamps"]} |')
        P(f'去向构成（seed0，{days} 天）：' + ', '.join(f'{k} {v:.0f}' for k, v in sorted(p.sink_total.items())))
        blocks = Counter(o.get('hs_block', '') for o in runs[0][1] if o.get('hs_block'))
        P(f'农场升级被卡原因（seed0 天数计）：{dict(blocks.most_common(6))}；撞墙原因：{dict(p.wall_reason)}')
    if md:
        with open(md, 'w') as f:
            f.write('\n'.join(lines))
    results['_variants'] = variants
    return results, summary, mc, ratios


def checks(cfg, results, summary, mc, ratios, days):
    out = []
    def chk(name, ok, detail):
        out.append((name, ok, detail)); print(f'[{"PASS" if ok else "FAIL"}] {name}: {detail}')
    chk('首会话 Fishing Lv2（30 分钟内）', mc['p30'] >= 0.95, f'P(≤30min)={mc["p30"]:.3f} 中位 {mc["median"]:.1f} min P90 {mc["p90"]:.1f}')
    chk('首会话 Cooking Lv2（30 分钟内，≥95%）', mc['cook_p30'] >= 0.95, f'P(≤30min)={mc["cook_p30"]:.3f} 中位 {mc["cook_median"]:.1f} min P90 {mc["cook_p90"]:.1f} 会话末 Cooking XP 中位 {mc["cook_xp_med"]:.0f}')
    ms30c = results['P30'][1]; mshc = results['HEAVY'][1]; ms5c = results['P5'][1]; mscc = results['P30C'][1]
    chk('Cooking：30 分钟玩家 Lv10 在 21±5 天', 16 <= ms30c.get('cooking_lv10', 99) <= 26, f'P30 d{ms30c.get("cooking_lv10", 99):.0f}（Lv4 第 3 槽 d{ms30c.get("cooking_lv4", 99):.0f}）；P30C d{mscc.get("cooking_lv10", 99):.0f}（Lv4 d{mscc.get("cooking_lv4", 99):.0f}）')
    chk('Cooking：重度 Lv10 ≥ 8 天', mshc.get('cooking_lv10', 99) >= 8, f'HEAVY d{mshc.get("cooking_lv10", 99):.0f}（Lv4 d{mshc.get("cooking_lv4", 99):.0f}）')
    chk('Cooking：5 分钟玩家 Lv10 ≤ 90 天（口径：≈100 可接受）', ms5c.get('cooking_lv10', 999) <= 90, f'P5 d{ms5c.get("cooking_lv10", 999):.0f}（Lv4 d{ms5c.get("cooking_lv4", 999):.0f}）')
    def mine_share(arch):
        w = results[arch][2][7:min(30, days)]
        return statistics.mean(a['energy_mine'] for a in w) / max(1, statistics.mean(a['energy'] for a in w))
    chk('矿井按层计费：30 分钟 / 重度矿洞体力占比 ≤ 12.5% / 13%', mine_share('P30') <= 0.125 and mine_share('HEAVY') <= 0.13,
        f'P30 {mine_share("P30"):.1%}（矿洞日 1 局 A = 28）；HEAVY {mine_share("HEAVY"):.1%}（B 56 + A 28 = 84）')
    ms30 = results['P30'][1]
    chk('30 分钟玩家（钓鱼向 34 竿）两轨 21±5 天满级', 16 <= ms30.get('fishing_lv10', 99) <= 26 and 16 <= ms30.get('farming_lv10', 99) <= 26,
        f'Fishing d{ms30.get("fishing_lv10", 99):.0f} / Farming d{ms30.get("farming_lv10", 99):.0f}')
    msc = results['P30C'][1]; msb = results['P30B'][1]
    chk('（参考）30 分钟折中 25 竿 / 体力章画像 15 竿', 16 <= msc.get('fishing_lv10', 99) <= 26,
        f'25 竿：Fishing d{msc.get("fishing_lv10", 99):.0f} / Farming d{msc.get("farming_lv10", 99):.0f}；15 竿：Fishing d{msb.get("fishing_lv10", 99):.0f} / Farming d{msb.get("farming_lv10", 99):.0f}')
    msh = results['HEAVY'][1]; v = results['_variants']
    hf = v['HF_FISH'][1]; hfa = v['HF_FARM'][1]
    chk('重度 ≥8 天满级（均衡画像）', msh.get('fishing_lv10', 99) >= 8 and msh.get('farming_lv10', 99) >= 8,
        f'均衡重度 Fishing d{msh.get("fishing_lv10", 99):.0f} / Farming d{msh.get("farming_lv10", 99):.0f}；全押上界（文内已接受 4–6 天）全钓 d{hf.get("fishing_lv10", 99):.0f} / 全种 d{hfa.get("farming_lv10", 99):.0f}')
    ms5 = results['P5'][1]; ms5b = results['P5B'][1]
    chk('5 分钟玩家 ≤90 天满级（钓鱼向 10 竿）', ms5.get('fishing_lv10', 999) <= 90 and ms5.get('farming_lv10', 999) <= 90,
        f'10 竿：Fishing d{ms5.get("fishing_lv10", 999):.0f} / Farming d{ms5.get("farming_lv10", 999):.0f}；5 竿画像：Fishing d{ms5b.get("fishing_lv10", 999):.0f} / Farming d{ms5b.get("farming_lv10", 999):.0f}')
    chk('重度日撞墙 ≤1 次（d8–30 日均与峰值）', summary['HEAVY']['walls'] <= 1.0 and summary['HEAVY']['walls_max'] <= 1.0 + 1e-9,
        f'日均 {summary["HEAVY"]["walls"]:.2f}，峰值 {summary["HEAVY"]["walls_max"]:.0f}')
    rows = []
    for p, _ in results['P30'][0]:
        rows += [(u / mx, m / mx) for u, m, mx in p.p30_meal[7:30]]
    ub = statistics.mean(r[0] for r in rows) if rows else 0; mr = statistics.mean(r[1] for r in rows) if rows else 0
    chk('30 分钟会话用池 60–80% 且一顿正餐回一半', 0.55 <= ub <= 0.8 and mr >= 0.45, f'正餐前用 {ub:.0%}，正餐回 {mr:.0%}（P30 画像：130 体力播种 + 隔日 1 局 A）')
    ok_meal = all(summary[a]['meal'] <= cfg['food_base'] + 10 * 9 + 1 for a in ('P5', 'P30', 'HEAVY'))
    chk('料理不永动（日食物 ≤ 上限）', ok_meal, ', '.join(f'{a} {summary[a]["meal"]:.0f}' for a in ('P5', 'P30', 'HEAVY')))
    r = ratios['P30']
    chk('公平性①：每体力净金币比 ≤1.3（重度/P30）', r['rv'] <= 1.3, f'每体力净比 {r["rv"]:.2f}')
    chk('公平性②：稳态产值比 ≤ 日燃料比 ×1.1（重度/P30）', r['rd'] <= r['re'] * 1.1, f'单日产值比 {r["rd"]:.2f} ≤ 体力比 {r["re"]:.2f}×1.1={r["re"]*1.1:.2f}')
    chk('公平性③：7 日累计账户价值比 ≤3.0（首周爬坡容差）', r['r7'] <= 3.0, f'7 日 {r["r7"]:.2f}；30 日 {r["r30"]:.2f}（报告值）')
    for a in ('P5', 'P30', 'HEAVY'):
        s = summary[a]
        chk(f'{a} 金币去向吸收 60–80%（中界 = 必需 + 成长可选 + 升级）', 0.6 <= s['share_mid'] <= 0.8, f'下界 {s["share_low"]:.0%} / 中界 {s["share_mid"]:.0%} / 上界 {s["share"]:.0%}')
    hfo = v['H_FOCUS'][1]; p30f = v['P30_FOCUS'][1]
    chk('Homestead Lv10：重度（均衡）30–35 天', 30 <= msh.get('hs_lv10', 999) <= 35,
        f'均衡 d{msh.get("hs_lv10", 999):.0f}；冲刺（硬木封顶）d{hfo.get("hs_lv10", 999):.0f}')
    chk('Homestead Lv10：休闲 60–70 天（30 分钟折中画像 P30C）', 60 <= msc.get('hs_lv10', 999) <= 70,
        f'P30C d{msc.get("hs_lv10", 999):.0f}；P30（34 竿）d{ms30.get("hs_lv10", 999):.0f}；P30B（15 竿）d{msb.get("hs_lv10", 999):.0f}；P30 冲刺 d{p30f.get("hs_lv10", 999):.0f}；5 分钟 d{ms5.get("hs_lv10", 999):.0f}')
    reach = max(msh.get('hs_lv5', 999), msh.get('stamps_12', 999), msh.get('ticket', 999))
    chk('北京→洛杉矶算例可达（重度）', reach <= days, f'第 {reach:.0f} 天起（Hs5 d{msh.get("hs_lv5", 999):.0f} / 印章 12 d{msh.get("stamps_12", 999):.0f} / 长途票 d{msh.get("ticket", 999):.0f}）')
    return out


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--fix', default=''); ap.add_argument('--days', type=int, default=120)
    ap.add_argument('--seeds', type=int, default=6); ap.add_argument('--md', default=None)
    args = ap.parse_args()
    cfg = base_config()
    fixes = set()
    if args.fix:
        fixes = set(x.strip() for x in args.fix.split(','))
        cfg = apply_fixes(cfg, fixes)
        for f in sorted(fixes):
            print(f'[{f}] {FIX_DOC[f]}')
    results, summary, mc, ratios = report(cfg, args.seeds, args.days, args.md, label=('（对照 ' + '+'.join(sorted(fixes)) + '）') if fixes else '（基表）')
    print('\n## 校验结论')
    checks(cfg, results, summary, mc, ratios, args.days)
