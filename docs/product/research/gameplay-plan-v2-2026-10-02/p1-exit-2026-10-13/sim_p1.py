#!/usr/bin/env python3
"""
sim_p1.py — P1 出口：模拟器全套复跑（2026-10-13，李白；方案 v2 §17.3.2，q(155)）

做法：import round3 的 sim_v3.py（第 15 章全量模型：体力、三条技能轨、等级差、做菜、进食、旅行、画像），
用子类覆盖把它换成 P1 的真实数据与 P1 口径；不改 sim_v3.py / p0_v1.py / p1_step1.py 任何一行。

数据：一律从 assets/p0/p0_content.json + assets/p0/content/*.json 读（按文件名合并，规则同服务端
server/src/p0/content.ts 的 mergeContentDir：对象按键合并、带 id 的数组按 id 追加、重复即报错）。
读进来的：体力 / 回复 / 新手祝福 / 茶；三轨阈值；作物 20（含 4 种地区作物、3 种多年生）；鱼 20（时段 / 天气 / 地区）；
渔场模板 Pond / River / Coast；鱼竿 reach、蚯蚓 / 亮片（Lv5、10 枚 / 日、地区鱼 ×2）；鱼笼（Lv5 / 8 / 10、8 h、存 3、XP 50%）；
菜谱 48（稀有度按 cooking.derive 现算、标签按族 × 稀有度精确匹配）、Cooking 槽位 / XP / 首做 / 品质倍率；
一次性奖励（升级回体力 = 0，q(101)；首鱼 / 首道 Rare 菜 / Cookbook 8 / Fish-dex 10·20）；Homestead Lv2–10 金币 / 材料 / 技能和；
田数阶梯（Lv1–2 30、Lv3 起 40）、多年生槽、洒水器上限、扩容 I–III；采集点（含 Lv3 老树）；矿洞 1–5 层岩石权重、层费 / 敲岩、
史莱姆 / 精英掉落与石英日限、Express；工作台（铜镐、手套、洒水器、堆肥箱、温室）；堆肥 −20%、果木肥 regrow ×0.5、
Seed Saver 5%；配方卡价、摆件目录、明信片；委托模板（门槛、完成奖）、完成奖日上限 100、系统委托日上限 6、地板率 0.8；
特产换料规则（2 : 1、每级每种矿物 ≤ 50%、每日 6 次）；钱包地板 40、起始 180。

P1 口径（方案 q 行）：田 Lv1–2 30 / Lv3 起 40（q(59)），Lv4–10 暂 40（q(118) ⑦ 的变体见 --plots）；多年生每株 1 块田；
温室盖 4 × 4 = 16 块田、一年生 −25%、Farming Lv8 一座 / Lv10 两座；洒水器占 1 块田、浇周围 8 格、−15%；
减时封顶 0.45（设施 + 堆肥）；旧金山 Pond 3 / River 2 / Coast 1、地区鱼北极红点鲑 + 大西洋鲑（q(109)）；
家城固定旧金山（温带）；旅行 = P2 第一版（0 体力 0 金币、首访 +10 体力）；无社交（密友、帮工、客票）；无共做委托（q(159)）。

出口主表的基线：Homestead Lv7 起 48 格（BASE_LADDER；q(172) 已提出，待批），现数据 40 格并列作对照。
判定照 sim_v3 的约定：两轨与 Cooking 21 ± 5 看 P30（34 竿），P30C 参考；Homestead 看 HEAVY 与 P30C；中界看 P5 / P30 / HEAVY，P30C 参考。
金币去向的记账按方案 §9.15.1 分类表：蚯蚓归 A（必需），亮片（6 × ≤ 10 / 日）归 C（日常可选）——表里「蚯蚓 + 亮片 | A / C」
是"蚯蚓 A、亮片 C"；sim_v3 把整笔鱼饵算进 A，本脚本 10-13 起按方案拆开（sink 'bait' = 蚯蚓、'lure' = 亮片）。

模型简化（读数时记住；README / out_p1.md 里同样列出）：
  S1 玩家行为沿用 sim_v3 的画像（会话时刻、每日播种体力 / 竿数 / 锅数 / 矿洞局、"均衡 / 轻量"购买策略、选种与选菜排序），
     只加了 P1 新增东西的买法（洒水器盖满露天田、温室有钱有料就建、果园默认种 4 株、配方卡有钱就买未发现页）。
  S2 钓鱼成功率仍是 sim_v3 的玩家手感常数（新手 / 芦苇 / 碳素竿 90·80·72·62%），不模拟小游戏；渔场按等级固定（Lv4 River、Lv5 起 Coast）。
  S3 田块按真实田格网（farm_garden.json 的 8 × 5）算洒水器覆盖与温室块；温室固定在两个 4 × 4 锚点、树放在最下最右，
     扩田变体在网格下方加整行。作物不跟踪具体在哪一格，只按"温室格 / 洒水覆盖格 / 露天格"三类计数。
  S4 委托：每天按画像接 k 单（P5 0.5、P30 2、重度 4），从门槛已满足、不交材料、不需外城（不旅行的画像）的模板里随机抽；
     收入 = 完成奖（日上限 100）− 交付物按地板价 0.8 少拿的 20%（作物 / 鱼按单价估）+ 料理单的料理地板价；不扣真实库存。
  S5 居民赠餐第 10 天起每日 1 份（Familiar 的估计到达日）；Big Pot / 三口灶 / Cook All / Lucky Double / 熟练金区等只省时间或
     小幅改品质的便利不建模；料理品质沿用固定命中率。
  S6 天气每天随机（晴 50 / 雨 30 / 风 20），时段按会话开始时刻；鱼笼按 Pond 模板（无时段 / 天气）。
  S7 背包容量、鱼篓、摆件上限、仓库不建模；矿洞战斗必胜、不掉 HP；外城地区鱼沿用 sim_v3 的簇派生。
  S8 特产换料：#364 起数据不再列 homestead.barter.items，换料物品按地区数据派生，与方案 §8.4.5 规则相同（原先 items 为空 = 换不了）
     （本带地区作物 + 本城 2 种地区鱼），"data" 模式按空表跑作对照。

用法：
  python3 -B sim_p1.py                       # 全套：120 天 × 12 seed，写 out_p1.md 第 1–6 节与第 8 节「结论」
  python3 -B knobs_p1.py                     # 之后再跑：把第 7 节「旋钮对照」插到「结论」之前
  python3 -B sim_p1.py --seeds 6             # 快一点
  python3 -B sim_p1.py --only main           # 只跑主表
"""
import argparse
import copy
import functools
import json
import math
import os
import random
import re
import statistics
import sys
import time
from collections import Counter, defaultdict

sys.dont_write_bytecode = True   # 不在旧模拟器目录里留 __pycache__
HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..', '..', '..', '..'))
sys.path.insert(0, os.path.join(HERE, '..', 'round3-cooking-mine-npc', 'sim'))
import sim_v3 as S  # noqa: E402

RAR = S.RAR
CONTENT_MAIN = os.path.join(REPO, 'assets', 'p0', 'p0_content.json')


# ============================================================================
# 1. 读数据（同 server/src/p0/content.ts mergeContentDir）
# ============================================================================
def _merge(base, add, f, at=''):
    for k, v in add.items():
        if at == '' and k.startswith('_'):
            continue
        where = k if at == '' else f'{at}.{k}'
        if k not in base:
            base[k] = v
            continue
        have = base[k]
        if isinstance(have, dict) and isinstance(v, dict):
            _merge(have, v, f, where)
            continue
        if isinstance(have, list) and isinstance(v, list) and all(isinstance(e, dict) and 'id' in e for e in have + v):
            ids = {e['id'] for e in have}
            for e in v:
                if e['id'] in ids:
                    raise ValueError(f'{f}: {where} already has id {e["id"]}')
                ids.add(e['id'])
                have.append(e)
            continue
        raise ValueError(f'{f}: {where} is already set')


def load_content(path=CONTENT_MAIN):
    with open(path) as fh:
        c = json.load(fh)
    d = os.path.join(os.path.dirname(path), 'content')
    files = sorted(x for x in os.listdir(d) if x.endswith('.json'))
    for f in files:
        with open(os.path.join(d, f)) as fh:
            _merge(c, json.load(fh), f)
    c['_files'] = files
    return c


CONTENT = load_content()


def ladder(pairs, v, default=0):
    out = default
    for at, n in pairs:
        if v >= at:
            out = n
    return out


def mat(i):
    return 'copper' if i == 'copper_ore' else i


CLIMATES = ('Tropical', 'Subtropical', 'Temperate', 'Cool')
# 家城的 2 种地区鱼：温带 = 旧金山、亚热带 = 上海（fishing.regional.curated）；热带 / 寒带按 §6.2.5 规则取一个代表组合
# （第 1 种取低档组里 Pond 全天可钓者，第 2 种取其余）。
_CUR = CONTENT['fishing']['regional']['curated']
HOME_FISH = {'Temperate': _CUR['san francisco'], 'Subtropical': _CUR['shanghai'],
             'Tropical': ['fish_tilapia', 'fish_snakehead'], 'Cool': ['fish_arctic_char', 'fish_pike']}


# ============================================================================
# 2. 配置：sim_v3 的字段形状，数值换成 JSON
# ============================================================================
# 换料模式：(岩盐能不能换：None / 'cap' 受每级 50% / 'free' 不受, 四种矿物是否受每级 50%)
BARTER_MODES = {'data': (None, True), 'rule': (None, True), 'nocap': (None, False),
                'salt_cap': ('cap', True), 'salt_free': ('free', True), 'nocap_salt': ('free', False)}


def p1_config(climate='Temperate', plot_ladder=None, barter='rule', orchard=4, gift_meal_day=10, content=None, stall_salt=None):
    C = content or CONTENT
    base = S.base_config()        # 只借模型参数（钓鱼成功率、竿时长、品质命中率、同页递减、外城地区鱼派生），其余全部由 JSON 覆盖
    cfg = {'climate': climate}
    e, hs, bl, ck, f, g = C['energy'], C['homestead'], C['blessing'], C['cooking'], C['fishing'], C['goods']
    cfg.update(energy_base=e['max_base'], energy_per_hs=hs['per_level']['energy'], regen_min=e['regen_ms'] / 60000,
               newcomer_days=bl['days'], newcomer_mult=bl['regen_mult'], newcomer_food=bl['food_bonus'],
               food_base=ck['food_cap'], food_per_hs=hs['per_level']['meals'], bonus_cap=C['rewards']['max_over'],
               meal_decay=base['meal_decay'], rest=e['rest_amount'])
    tiers = ck['tiers']
    tr = {RAR[int(k) - 1]: v for k, v in tiers.items()}
    cfg['restore'] = {r: v['energy'] for r, v in tr.items()}
    cfg['good_bonus'] = {r: v['bonus'][1] for r, v in tr.items()}
    cfg['p_good'] = base['p_good']; cfg['p_perfect'] = base['p_perfect']
    dr = C['drinks']
    cfg['tea'] = dr['energy']; cfg['tea_price'] = list(dr['prices']); cfg['tea_cups'] = dr['daily']
    cfg['gift_meal'] = cfg['restore']['common']; cfg['gift_meal_day'] = gift_meal_day
    cfg['friend_visit'] = 0
    lu = C['level_up_energy']
    cfg['lvup_first'] = lu['first']; cfg['lvup'] = lu['later']
    rw = C['rewards']
    cfg['first_fish_energy'] = {RAR[i]: v for i, v in enumerate(rw['first_fish']) if v}
    cfg['first_dish_energy'] = 0
    cfg['first_rare_dish_energy'] = rw['first_dish'][2]; cfg['first_legendary_dish_energy'] = rw['first_dish'][3]
    cfg['cookbook_energy'] = {n: v for n, v in rw['cookbook']}
    cfg['cookbook_coins'] = {m['discovered']: m['coins'] for m in ck['milestones'] if m.get('discovered') and m.get('coins')}
    cfg['fishdex_energy'] = {n: v for n, v in rw['fishdex']}
    cfg['fishdex_coins'] = {m['kinds']: m['coins'] for m in f['dex_milestones']}
    cfg['first_city_energy'] = 10                                   # server/src/p0/travel.ts FIRST_VISIT_ENERGY（不在 JSON）
    cfg['explorer'] = {3: 30, 10: 50, 30: 70, 100: 100}             # travel.ts EXPLORER（不在 JSON）
    cfg['cast'] = f['cast_energy']; cfg['refund'] = f['refund_fail']
    cfg['free_fail'] = f['protect_fails']; cfg['free_fail_lv'] = f['protect_max_level']
    cfg['cast_sec'] = base['cast_sec']; cfg['cast_sec_worm'] = base['cast_sec_worm']
    m = C['mine']
    cfg['mine_rules'] = dict(runs=m['runs_per_day'], floor_e=m['floor_energy'], rock_e=m['rock_energy'], rocks=m['rocks'],
                             floors={fl['floor']: fl for fl in m['floors']}, monsters=m['monsters'], picks=m['picks'],
                             express=m['express_unlock_floor'])
    cfg['mine_runs_per_day'] = m['runs_per_day']
    cfg['travel'] = {k: (0, 0) for k in range(1, 8)}               # P2 第一版：免费、即达（travel.ts cost 0 / 0）
    cfg['travel_time'] = {k: 0 for k in range(1, 8)}
    cfg['stamp_req'] = base['stamp_req']
    sk = C['skills']
    cfg['farm_th'] = list(sk['farming']); cfg['fish_th'] = list(sk['fishing']); cfg['cook_th'] = list(sk['cooking'])
    cfg['fish_xp'] = {RAR[i]: v for i, v in enumerate(f['catch_xp'])}
    cfg['first_species'] = {RAR[i]: v for i, v in enumerate(f['first_xp'])}
    cfg['first_city_xp'] = f['first_city_xp']; cfg['first_cast_xp'] = f['first_cast_xp']; cfg['first_hook_xp'] = f['first_landed_xp']
    cfg['dish_first_xp'] = {r: v['first_xp'] for r, v in tr.items()}
    cfg['cook_xp'] = {r: v['xp'] for r, v in tr.items()}
    cfg['cook_content_lv'] = {r: v['level'] for r, v in tr.items()}
    cfg['cook_page_decay'] = base['cook_page_decay']
    qx = ck['quality_xp']
    cfg['cook_quality_mult'] = {'normal': qx[0], 'good': qx[1], 'perfect': qx[2]}
    slots = [tuple(x) for x in ck['slots']]
    cfg['slots'] = lambda lv, s=slots: ladder(s, lv, 1)
    cfg['dish_stock_cap'] = base['dish_stock_cap']; cfg['friend_xp_mult'] = 1.0; cfg['anti_script_cap'] = C['skill_daily_cap']
    # --- 作物 ---
    crops, pers, perx = {}, {}, {}
    for c in C['crops']:
        cid = c['id'][5:]
        if 'perennial' in c:
            p = c['perennial']
            pers[cid] = (c['level'], c['seed_price'], c['grow_h'], p['regrow_h'], c['yield'], c['price'], RAR[c['ingr'][1] - 1])
            perx[cid] = dict(plant_e=c['energy'], pick_e=p['harvest_energy'], pick_xp=p['harvest_xp'], plant_xp=c['xp'],
                             first_xp=c['first_xp'], ingr=tuple(c['ingr']))
            continue
        crops[cid] = dict(tier=c['tier'], lv=c['level'], seed=c['seed_price'], hours=c['grow_h'], yld=c['yield'], price=c['price'],
                          energy=c['energy'], xp=c['xp'], first_xp=c['first_xp'], ingr=tuple(c['ingr']), rar=RAR[c['ingr'][1] - 1],
                          fam=c['ingr'][0], reg=bool(c.get('regional')), zone=c.get('zone'), off_h=c.get('off_zone_grow_h'),
                          seed_daily=c.get('seed_daily'))
    cfg['crops'] = crops; cfg['perennials'] = pers; cfg['perx'] = perx
    home_crop = [k for k, c in crops.items() if c['reg'] and c['zone'] == climate]
    cfg['home_crop'] = home_crop[0] if home_crop else None
    cfg['plantable'] = [k for k, c in crops.items() if not c['reg'] or c['zone'] == climate]
    cfg['regional_per_day'] = crops[cfg['home_crop']]['seed_daily'] if cfg['home_crop'] else 0
    # --- 鱼 ---
    fish = {}
    for x in C['fish']:
        fid = x['id'][5:]
        t = x.get('time')
        fish[fid] = dict(rar=RAR[x['rarity'] - 1], tier=x['rarity'] - 1, lv=x['level'], price=x['price'], sites=tuple(x['where']),
                         clim=tuple(x['zones']) if x.get('regional') else None, regional=bool(x.get('regional')), time=t,
                         weather=x.get('weather', {}), cook=x.get('cook', True), night=(t == 'night_only'))
    cfg['fish'] = fish
    cfg['home_climate'] = climate.lower()
    cfg['home_regional'] = tuple(i[5:] for i in HOME_FISH[climate])
    cfg['sites'] = {k: list(v['weights']) for k, v in f['sites'].items()}
    cfg['baits'] = {'worm': dict(shift=f['baits']['bait_worm']['shift'], mult=1),
                    'lure': dict(shift=f['baits']['bait_lure']['shift'], mult=f['baits']['bait_lure'].get('regional_mult', 1))}
    cfg['bait_price'] = {'worm': (g['bait_worm']['gate'], g['bait_worm']['price'], g['bait_worm']['daily']),
                         'lure': (g['bait_lure']['gate'], g['bait_lure']['price'], g['bait_lure']['daily'])}
    rods = {}
    for r in f['rods']:
        rid = r['id'][4:]
        rods[rid] = dict(cap=r['reach'] - 1, p=base['rods'][rid]['p'], lv=r['level'], price=r['price'])
    cfg['rods'] = rods
    tp, gt = f['trap'], g['trap_fish']
    cfg['trap'] = dict(lv=gt['gate'], price=gt['price'], every=tp['every_h'] * 60, cap=tp['keep'], rare_from=tp['rare_from'],
                       rare_pct=tp['rare_pct'], xp_pct=tp['xp_pct'])
    cfg['trap_slots'] = {lv: n for lv, n in tp['slots']}
    cfg['city_pairs'] = base['city_pairs']
    cfg['windows'] = f['regional']['time_windows']
    cfg['weather_odds'] = f['regional']['weather']['odds']
    # --- 料理 48 页（稀有度按 derive 现算）---
    mats_ingr = {k: tuple(v['ingr']) for k, v in C['materials'].items() if v.get('ingr')}

    def token(t):
        if re.fullmatch(r'[WFOS]\d', t):
            return 'tag_' + t
        return t[5:] if t.startswith(('fish_', 'crop_')) else t

    def info(t):
        if re.fullmatch(r'[WFOS]\d', t):
            return t[0], int(t[1])
        if t.startswith('fish_'):
            x = fish.get(t[5:])
            return ('W', x['tier'] + 1) if x and x['cook'] else None
        if t.startswith('crop_'):
            k = t[5:]
            if k in crops:
                return crops[k]['ingr']
            if k in perx:
                return perx[k]['ingr']
            return None
        return mats_ingr.get(t)
    dishes, mismatch = {}, []
    derive = ck['derive']
    for r in ck['recipes']:
        if r.get('cookable') is False or not r['in']:
            continue
        parts = [info(t) for t in r['in']]
        if any(p is None for p in parts):
            continue
        top = max(p[1] for p in parts); fams = len({p[0] for p in parts})
        rr = derive[top - 1][min(fams, 3) - 1]
        if r.get('rarity') and r['rarity'] != rr:
            mismatch.append((r['id'], r['rarity'], rr))
        did = r['id'][5:]
        dishes[did] = dict(id=did, rar=RAR[rr - 1], ingr=[token(t) for t in r['in']], slots=len(r['in']), n=r['n'],
                           card_price=r.get('card_price'), card_zones=r.get('card_zones'), card_zone=r.get('card_zone'),
                           regional=bool(r.get('regional')))
    cfg['dishes'] = dishes; cfg['derive_mismatch'] = mismatch
    tags = defaultdict(list)
    for k, x in fish.items():
        if x['cook']:
            tags[f'tag_W{x["tier"] + 1}'].append(k)
    for k, c in crops.items():
        tags[f'tag_{c["ingr"][0]}{c["ingr"][1]}'].append(k)
    for k, x in perx.items():
        tags[f'tag_{x["ingr"][0]}{x["ingr"][1]}'].append(k)
    for k, ig in mats_ingr.items():
        tags[f'tag_{ig[0]}{ig[1]}'].append(k)
    cfg['tags'] = dict(tags)
    # --- 材料 / 采集 / 工作台 ---
    floor = {}
    for k, v in C['materials'].items():
        floor[mat(k)] = v.get('price') if v.get('price') is not None else v.get('floor', 0.5 if k == 'stone' else 0)
    cfg['material_floor'] = floor
    cfg['spots'] = [dict(id=k, yld=[(mat(i), n) for i, n in v['yield']], hs=v['homestead']) for k, v in C['gather']['spots'].items()]
    cfg['gather'] = {s['id']: 0 for s in cfg['spots']}
    cfg['gather_cd'] = C['gather']['regen_h'] * 60; cfg['gloves_bonus'] = C['gather']['gloves_bonus']
    wb = {r['id']: r for r in C['workbench']['recipes']}
    fac = C['facilities']
    cost = lambda r: {mat(i): n for i, n in wb[r]['cost']}  # noqa: E731
    cfg['pickaxe'] = cost('craft_copper_pickaxe'); cfg['gloves'] = cost('craft_gather_gloves')
    cfg['sprinkler'] = dict(cost=cost('craft_sprinkler'), gate=wb['craft_sprinkler']['gate'][1], cut=fac['kinds']['sprinkler']['grow_cut'])
    cfg['compost_bin'] = dict(cost=cost('craft_compost_bin'), gate=wb['craft_compost_bin']['gate'][1], daily=fac['kinds']['compost_bin']['daily'])
    cfg['greenhouse'] = dict(cost=cost('craft_greenhouse'), coins=wb['craft_greenhouse'].get('coins', 0),
                             cut=fac['kinds']['greenhouse']['grow_cut'], caps=[tuple(x) for x in fac['kinds']['greenhouse']['cap_by_farming']])
    cfg['grow_cut_cap'] = fac['grow_cut_cap']
    fc = g['fert_compost']
    cfg['compost'] = dict(price=fc['price'], gate=fc['gate'], daily=fc['daily'], cut=round(1 - fc['grow_mult'], 4))
    fo = g['fert_orchard']
    cfg['orchard_feed'] = dict(price=fo['price'], gate=fo['gate'], daily=fo['daily'], mult=fo['regrow_mult'])
    fv = C['farming']
    cfg['seed_saver'] = dict(lv=fv['conveniences']['seed_saver'], p=fv['seed_saver_chance'])
    rh = C['tools']['row_hoe']
    cfg['row_hoe'] = dict(price=rh['price'], gate=rh['gate'])
    # --- Homestead ---
    lv = {l['level']: l for l in hs['levels']}
    cfg['hs_levels'] = {n: dict(coins=l['coins'], skills=l['skills'], mats={mat(i): q for i, q in l['materials']}) for n, l in lv.items()}
    order = ['wood', 'stone', 'fiber', 'copper', 'clay', 'quartz', 'hardwood', 'rock_salt']
    cfg['homestead'] = [tuple([cfg['hs_levels'][n]['coins']] + [cfg['hs_levels'][n]['mats'].get(k, 0) for k in order]) for n in range(2, 11)]
    cfg['hs_skill_gate'] = lambda n, L=cfg['hs_levels']: L[n]['skills']
    pl = [tuple(x) for x in (plot_ladder or hs['plots'])]
    cfg['plot_ladder'] = pl
    cfg['plot_cap'] = lambda h, p=pl: ladder(p, h, 30)
    ps, sm = hs['perennial_slots'], hs['sprinkler_max']
    cfg['perennial_slots'] = lambda h, p=ps: min(p['max'], p['base'] + p['per_level'] * h)
    cfg['sprinkler_max'] = lambda h, p=sm: min(p['max'], p['base'] + p['per_level'] * h)
    cfg['orchard_cap'] = orchard
    cfg['bag_upgrade'] = {b['homestead']: (b['price'], {mat(i): n for i, n in b['materials']}) for b in C['bag_upgrades']}
    bt = hs['barter']
    rule_items = ([cfg['home_crop']] if cfg['home_crop'] else []) + list(cfg['home_regional'])
    salt_rule, mineral_cap = BARTER_MODES[barter]
    cfg['stall_salt'] = stall_salt          # (每日份数, 单价)：农场驿站卖岩盐的假设（s4 / s5）；None = 不卖（现数据）
    cfg['barter'] = dict(give=bt['give'], minerals=[mat(x) for x in bt['minerals']], share=bt['level_share'], per_day=bt['daily'],
                         salt=salt_rule, mineral_cap=mineral_cap, mode=barter, items=[i.split('_', 1)[1] if i.startswith(('crop_', 'fish_')) else i for i in bt['items'].get(climate, [])]
                         if barter == 'data' and 'items' in bt else rule_items, data_items=bt.get('items', {}))   # #364 起数据不再列 items，按地区数据派生，同规则
    # --- 经济 ---
    cfg['initial_wallet'] = C['start']['coins']; cfg['wallet_floor'] = C['wallet_floor']
    cfg['cards'] = dict(prices={int(k): v for k, v in ck['cards']['prices'].items()}, stall_daily=ck['cards']['stall_daily'])
    cfg['decor_items'] = sorted((v['price'], k, v['homestead']) for k, v in C['decor']['items'].items() if v.get('buy'))
    cfg['postcard'] = C['city_postcard']['price']
    cfg['quotas'] = C['quotas']
    cfg['req_templates'] = C['requests']['templates']
    cfg['req_qty'] = [tuple(x) for x in C['requests']['qty']]
    cfg['req_floor'] = C['requests']['floor_rate']
    cfg['wallet_floor'] = C['wallet_floor']
    return cfg


# ============================================================================
# 3. 田格网：温室块、树、洒水器覆盖（farm_garden.json 的真实格网）
# ============================================================================
_BASE_CELLS = [tuple(x) for x in CONTENT['garden']['plots']]
# 出口主表的基线田数：Homestead Lv7 起 48 格（q(172) 已提出，待批）；现数据是 homestead.plots = Lv1–2 30、Lv3 起 40
BASE_LADDER = [(1, 30), (3, 40), (7, 48)]
GH_ANCHORS = [(0, 0), (4, 0)]


# q(172) 的 8 格：用户 10-13 定「往下延伸、扩展农场边界」（302 64adaa0b），方向 A（奕星转，10-14 凌晨）——在现有 8 × 5 田
# 靠镜头 / 出生点一侧加一整行 8 格（网格第 −1 行，世界格 y1，编号 40–47），篱笆前段前移；不放左沿（刘邦方案 C 作废）
LV7_CELLS = [(c, -1) for c in range(8)]


def grid_cells(n):
    if n <= len(_BASE_CELLS):
        return _BASE_CELLS[:n]
    out = list(_BASE_CELLS) + LV7_CELLS[:n - len(_BASE_CELLS)]
    cols = max(c for c, _ in _BASE_CELLS) + 1
    rows = max(r for _, r in _BASE_CELLS) + 1
    for i in range(n - len(out)):              # 超过 48 格时（只在敏感性里用到）才在网格下方加整行
        out.append((i % cols, rows + i // cols))
    return out


def ring8(c):
    x, y = c
    return {(x + i, y + j) for i in (-1, 0, 1) for j in (-1, 0, 1) if (i, j) != (0, 0)}


@functools.lru_cache(maxsize=None)
def layout(n, n_gh, n_trees, n_spr):
    """一年生能用的格：gh（温室下）/ cov（洒水器覆盖）/ open（露天未覆盖）。放不下返回 None。"""
    cells = grid_cells(n)
    cs = set(cells)
    gh = set()
    for k in range(n_gh):
        if k >= len(GH_ANCHORS):
            return None
        ax, ay = GH_ANCHORS[k]
        block = {(ax + i, ay + j) for i in range(4) for j in range(4)}
        if not block <= cs or block & gh:
            return None
        gh |= block
    rest = [c for c in cells if c not in gh]
    if n_trees + n_spr > len(rest):
        return None
    trees = set(sorted(rest, key=lambda c: (-c[1], -c[0]))[:n_trees])     # 树种在最下、最右
    free = [c for c in rest if c not in trees]
    spr = set()
    covered = set()
    for _ in range(n_spr):
        best = None
        for c in free:
            if c in spr:
                continue
            gain = len({x for x in ring8(c) if x in cs and x not in gh and x not in trees and x not in spr and x != c and x not in covered})
            key = (gain, -c[1], -c[0])
            if best is None or key > best[0]:
                best = (key, c)
        if best is None:
            return None
        spr.add(best[1])
        covered = {x for s in spr for x in ring8(s)}
    annual = [c for c in free if c not in spr]
    cov = sum(1 for c in annual if c in covered)
    return dict(gh=len(gh), cov=cov, open=len(annual) - cov, cells=n, trees=n_trees, spr=n_spr)


@functools.lru_cache(maxsize=None)
def sprinkler_target(n, n_gh, n_trees, cap):
    """把露天一年生全部盖住要几台（不超上限）。"""
    best = 0
    for s in range(0, cap + 1):
        L = layout(n, n_gh, n_trees, s)
        if L is None:
            return best
        best = s
        if L['open'] == 0:
            return s
    return best


# ============================================================================
# 4. 画像（沿用 sim_v3；P1 去掉社交，旅行免费）
# ============================================================================
def p1_archetypes():
    B = S.ARCHETYPES
    A = {}
    A['P5'] = dict(copy.deepcopy(B['P5']), travel='none', friend=False, helper=0, requests=0, req_per_day=0.5, mine=('A', 3))
    A['P30'] = dict(copy.deepcopy(B['P30']), travel='weekly', friend=False, helper=0, requests=0, req_per_day=2, mine=('A', 2))
    A['P30C'] = dict(copy.deepcopy(B['P30C']), travel='weekly', friend=False, helper=0, requests=0, req_per_day=2, mine=('A', 2))
    A['P30B'] = dict(copy.deepcopy(B['P30B']), travel='weekly', friend=False, helper=0, requests=0, req_per_day=2, mine=('A', 1))
    A['HEAVY'] = dict(copy.deepcopy(B['HEAVY']), travel='daily', friend=False, helper=0, requests=0, req_per_day=4,
                      mine=[('C', 1), ('A', 1)],
                      label='重度（08:00 与 20:00 各 2 小时；早 180 + 晚 50 体力播种、27 + 50 竿、早 C 局（1–5 层）晚 A 局、每日 Trip 免费旅行、3 杯茶）')
    A['P30C']['label'] = '30 分钟/日 · 折中（25 竿 + 110 体力，隔日 1 局 A）'
    return A


ARCH = p1_archetypes()


def variant(base, **kw):
    a = copy.deepcopy(ARCH[base])
    a.update(kw)
    return a


# ============================================================================
# 5. 玩家：sim_v3.Player 的 P1 子类
# ============================================================================
RUNS = {'A': (1, 2), 'B': (1, 2, 3, 4), 'C': (1, 2, 3, 4, 5), 'D': (5,)}
RUN_MIN = {'A': 4, 'B': 8, 'C': 13, 'D': 3}


class P1Player(S.Player):
    def __init__(self, arch, cfg, rng, arch_def):
        saved = S.ARCHETYPES.get(arch)
        S.ARCHETYPES[arch] = arch_def
        try:
            super().__init__(arch, cfg, rng)
        finally:
            if saved is None:
                del S.ARCHETYPES[arch]
            else:
                S.ARCHETYPES[arch] = saved
        self.a = arch_def
        self.base_casts = list(arch_def['casts'])
        self.sprinklers = 0; self.ghs = 0; self.compost_bin = False; self.row_hoe = False
        self.express = False; self.elite_quartz_day = None
        self.free_seeds = Counter(); self.carded = set()
        self.decor_bought = set(); self.postcard = False
        self.bartered_lv = Counter()
        self.weather = {}
        self.req_day = None; self.cur_idx = 0; self._redirect = False
        self.layout_log = []

    # ------------------------------------------------------------ 基础
    def reset_day(self):
        super().reset_day()
        self.feed_today = 0; self.compost_bought_today = 0; self.bin_today = 0; self.cards_today = 0; self.salt_today = 0

    def settle(self, t):
        d = self.day_id
        before = self.energy
        mx = self.energy_max()
        dt = max(0.0, (t if t > self.t else self.t) - self.last_t)
        rate = (1.0 / self.cfg['regen_min']) * (self.cfg['newcomer_mult'] if self.newcomer() else 1.0)
        super().settle(t)
        if d is not None and dt > 0:
            gain = max(0, min(self.energy, mx) - before) if before < mx else 0
            waste = dt * rate - gain
            if waste > 1:
                self.daily[d]['cap_waste'] += waste

    def daypart(self):
        h = (self.t % 1440) / 60
        w = self.cfg['windows']
        if any(a <= h < b for a, b in w['night']):
            return 'night'
        if any(a <= h < b for a, b in w['dawn_dusk']):
            return 'dawn_dusk'
        return 'day'

    def weather_today(self):
        d = self.day()
        w = self.weather.get(d)
        if w is None:
            odds = self.cfg['weather_odds']
            w = self.rng.choices(list(odds), weights=list(odds.values()))[0]
            self.weather[d] = w
        return w

    def got(self, m, n):
        if n <= 0:
            return
        self.mats[m] += n
        self.daily[self.day()]['material_value'] += n * self.cfg['material_floor'].get(m, 0)

    # ------------------------------------------------------------ 田
    def layout(self):
        n = self.cfg['plot_cap'](self.hs)
        L = layout(n, self.ghs, len(self.perennials), self.sprinklers)
        if L is None:   # 理论上不会：建造前都检查过放得下
            L = dict(gh=0, cov=0, open=max(0, n - len(self.perennials) - self.sprinklers), cells=n)
        return L

    def annual_free(self):
        L = self.layout()
        occ = Counter(p[4] if len(p) > 4 else 'open' for p in self.plots)
        free = {k: max(0, L[k] - occ[k]) for k in ('gh', 'cov', 'open')}
        total = L['gh'] + L['cov'] + L['open'] - len(self.plots)
        over = sum(free.values()) - max(0, total)
        for k in ('open', 'cov', 'gh'):
            if over <= 0:
                break
            cut = min(over, free[k]); free[k] -= cut; over -= cut
        return free

    def crop_cost(self, cid):
        return self.cfg['crops'][cid]['energy']

    def harvest(self):
        cfg = self.cfg
        ripe = [p for p in self.plots if p[1] <= self.t]
        self.plots = [p for p in self.plots if p[1] > self.t]
        value = 0
        ss = cfg['seed_saver']; saver = self.level('farming') >= ss['lv']
        for p in ripe:
            cid, xpl = p[0], p[2]
            c = cfg['crops'][cid]
            self.inv[cid] += c['yld']; value += c['yld'] * c['price']
            if cid not in self.first_crops:
                self.first_crops.add(cid)
                self.add_xp('farming', c['first_xp'], oneoff=True)
            self.add_xp('farming', xpl)
            if saver and not c['reg'] and self.rng.random() < ss['p']:
                self.free_seeds[cid] += 1; self.daily[self.day()]['seed_saver'] += 1
        self.daily[self.day()]['harvest_value'] += value; self.daily[self.day()]['harvest_plots'] += len(ripe)
        fo = cfg['orchard_feed']
        for p in self.perennials:
            if p[1] > self.t:
                continue
            px = cfg['perx'][p[0]]
            if not self.recover(px['pick_e'], allow_tea=False):
                continue
            lv, price, fh, rh, yld, up, rar = cfg['perennials'][p[0]]
            self.spend(px['pick_e'], 'farm')
            self.inv[p[0]] += yld
            regrow = rh * 60
            if (self.a['buy'] == 'balanced' and self.level('farming') >= fo['gate'] and self.feed_today < fo['daily']
                    and self.wallet - fo['price'] >= self.cfg['wallet_floor'] + self.seed_reserve() + 100):
                self.pay(fo['price'], 'fertilizer'); self.feed_today += 1; regrow *= fo['mult']
            p[1] = self.t + regrow
            d = self.level('farming') - lv
            if p[2] is not None:
                self.add_xp('farming', p[2]); p[2] = None
                if p[0] not in self.first_crops:
                    self.first_crops.add(p[0]); self.add_xp('farming', px['first_xp'], oneoff=True)
            self.add_xp('farming', self.ld_xp(px['pick_xp'], d))
            self.daily[self.day()]['harvest_value'] += yld * up

    def sow(self, energy_budget):
        if energy_budget <= 0:
            return 0
        cfg = self.cfg; lv = self.level('farming')
        free = self.annual_free()
        cuts = {'gh': cfg['greenhouse']['cut'], 'cov': cfg['sprinkler']['cut'], 'open': 0.0}
        cands = []
        for cid in cfg['plantable']:
            c = cfg['crops'][cid]
            if lv < c['lv']:
                continue
            d = lv - c['lv']
            net = (c['yld'] * c['price'] - c['seed']) / c['energy']
            cands.append((0 if d <= 1 else d, -net, c['hours'], cid))
        cands.sort()
        fixed = []
        hc = cfg['home_crop']
        if self.a.get('regional_fixed') and hc and lv >= cfg['crops'][hc]['lv'] and self.inv[hc] < self.a.get('barter_hoard', 24):
            fixed.append((hc, self.a['regional_fixed']))
        for cid, n in (('herb', 3), ('chili', 1), ('potato', 3)):
            if lv >= cfg['crops'][cid]['lv']:
                fixed.append((cid, n))
        main = [cid for _, _, _, cid in cands if cid not in ('herb', 'chili')][:3]
        sown_e = 0; cost_coins = 0

        def take_cell(hours):
            order = ('gh', 'cov', 'open') if hours >= 10 else ('open', 'cov', 'gh')
            for k in order:
                if free[k] > 0:
                    free[k] -= 1
                    return k
            return None

        def plant(cid, n):
            nonlocal sown_e, cost_coins
            c = cfg['crops'][cid]; e = c['energy']; k = 0
            while k < n:
                if sown_e + e > energy_budget or self.energy < e:
                    break
                freebie = self.free_seeds[cid] > 0
                if not freebie and self.wallet - c['seed'] < 0:
                    break
                if sum(free.values()) <= 0:
                    break
                if c['reg'] and self.regional_today >= cfg['regional_per_day']:
                    break
                cell = take_cell(c['hours'])
                cut = cuts[cell]
                if self.inv['compost'] > 0 and c['hours'] >= 10:
                    self.inv['compost'] -= 1; cut += cfg['compost']['cut']; self.daily[self.day()]['compost_used'] += 1
                hours = c['hours'] * (1 - min(cut, cfg['grow_cut_cap']))
                self.spend(e, 'farm'); sown_e += e
                if freebie:
                    self.free_seeds[cid] -= 1
                else:
                    self.wallet -= c['seed']; cost_coins += c['seed']; self.seed_total += c['seed']
                d = lv - c['lv']
                self.plots.append((cid, self.t + hours * 60, self.ld_xp(c['xp'], d), cid not in self.first_crops, cell))
                if c['reg']:
                    self.regional_today += 1
                k += 1
                self.t += (2 / 60) / (3 if self.row_hoe else 1)
            return k
        for cid, n in fixed:
            if cid == hc or self.inv[cid] < 6:
                plant(cid, n)
        for cid in cfg['plantable']:
            if lv >= cfg['crops'][cid]['lv'] and cid not in self.first_crops and not any(p[0] == cid for p in self.plots):
                plant(cid, 1)
        for cid, sh in zip(main, (0.5, 0.3, 0.2)):
            e = cfg['crops'][cid]['energy']
            plant(cid, int((energy_budget - sown_e) * sh / e) + 1)
        for cid in main:
            plant(cid, 10 ** 6)
        if sown_e < energy_budget and self.energy >= 2:
            self.daily[self.day()]['sow_short'] += energy_budget - sown_e
            if self._redirect:
                extra = int((energy_budget - sown_e) // self.cfg['cast'])
                self.a['casts'][self.cur_idx] = self.base_casts[self.cur_idx] + extra
                self.daily[self.day()]['redirect_casts'] += extra
        self._redirect = False
        self.daily[self.day()]['seed_cost'] += cost_coins; self.daily[self.day()]['sown_energy'] += sown_e
        return sown_e

    # ------------------------------------------------------------ 采集 / 矿
    def gather(self):
        cfg = self.cfg
        for sp in cfg['spots']:
            if self.hs < sp['hs'] or self.t < self.gather_next[sp['id']]:
                continue
            self.gather_next[sp['id']] = self.t + cfg['gather_cd']
            for i, (m, n) in enumerate(sp['yld']):
                if m == 'bait_worm':
                    self.inv['worm'] += n
                    continue
                self.got(m, n + (cfg['gloves_bonus'] if self.gloves and i == 0 else 0))
        self.t += 0.5

    def mine(self, kind):
        mr = self.cfg['mine_rules']
        if self.mine_runs_today >= mr['runs']:
            return False
        if kind == 'D' and not self.express:
            kind = 'C'
        floors = RUNS[kind]
        e = 0
        for fl in floors:
            F = mr['floors'][fl]
            fee = 0 if (fl == 5 and self.express) else mr['floor_e']
            e += fee + mr['rock_e'] * F.get('rocks', mr['rocks'])
        if not self.recover(e):
            self.wall('mine')
            return False
        self.spend(e, 'mine'); self.mine_runs_today += 1
        stone = mr['picks']['pick_copper' if self.pickaxe else 'pick_starter']['stone']
        for fl in floors:
            F = mr['floors'][fl]
            drops = F['drops']
            for _ in range(F.get('rocks', mr['rocks'])):
                self.got('stone', stone)
                if drops:
                    item = self.rng.choices([d[0] for d in drops], weights=[d[1] for d in drops])[0]
                    if item:
                        self.got(mat(item), 1)
            for mob in F.get('mobs', []):
                M = mr['monsters'][mob]
                loot = [x for x in M['loot'] if not (M.get('once_a_day') == x[0] and self.elite_quartz_day == self.day())]
                item, qty, _ = self.rng.choices(loot, weights=[x[2] for x in loot])[0]
                if item == M.get('once_a_day'):
                    self.elite_quartz_day = self.day()
                if item == 'bait_worm':
                    self.inv['worm'] += qty
                else:
                    self.got(mat(item), qty)
            if fl == mr['express']:
                self.express = True
        self.t += RUN_MIN[kind]
        self.daily[self.day()]['mine_runs'] += 1
        return True

    # ------------------------------------------------------------ 钓鱼
    def pick_bait(self):
        lv = self.level('fishing')
        if self.inv['lure'] > 0 and lv >= self.cfg['bait_price']['lure'][0]:
            self.inv['lure'] -= 1
            return 'lure'
        if self.inv['worm'] > 0 and lv >= self.cfg['bait_price']['worm'][0]:
            self.inv['worm'] -= 1
            return 'worm'
        return None

    def _pool(self, site, regional, part, weather, rmult):
        cache = self.cfg.setdefault('_pool_cache', {})
        key = (site, regional, part, weather, rmult)
        if key in cache:
            return cache[key]
        tiers = [[], [], [], []]
        for fid, f in self.cfg['fish'].items():
            if site not in f['sites']:
                continue
            if f['regional'] and fid not in regional:
                continue
            t = f['time']
            if t == 'night_only' and part != 'night':
                continue
            if t == 'dawn_dusk_only' and part != 'dawn_dusk':
                continue
            w = 2 * rmult if f['regional'] else 1
            if isinstance(t, dict) and part != 'day':
                w *= t.get(part, 1)
            w *= f['weather'].get(weather, 1)
            tiers[f['tier']].append((fid, w))
        cache[key] = tiers
        return tiers

    def cast(self, site, city='home', regional=None, friend=False, night=False):
        cfg = self.cfg; lv = self.level('fishing')
        if not self.recover(cfg['cast']):
            self.wall('cast')
            return None
        self.spend(cfg['cast'], 'fish')
        bait = self.pick_bait()
        shift = cfg['baits'][bait]['shift'] if bait else (0, 0, 0, 0)
        w = [max(0, a + b) for a, b in zip(cfg['sites'][site], shift)]
        tier = self.rng.choices((0, 1, 2, 3), weights=w)[0]
        reg = tuple(regional) if regional else cfg['home_regional']
        tiers = self._pool(site, reg, self.daypart(), self.weather_today(), cfg['baits'][bait]['mult'] if bait else 1)
        while tier > 0 and not tiers[tier]:
            tier -= 1
        cands = tiers[tier]
        fid = self.rng.choices([c for c, _ in cands], weights=[x for _, x in cands])[0]
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
        if f['regional']:
            self.climates.add(cfg['home_climate'] if city == 'home' else self.city_climate(city))
        if fid not in self.first_fish:
            self.first_fish.add(fid); self.add_xp('fishing', cfg['first_species'][f['rar']], oneoff=True)
            n = len(self.first_fish)
            if n in cfg['fishdex_energy']:
                self.add_energy_bonus(cfg['fishdex_energy'][n], 'achv')
            if n in cfg['fishdex_coins']:
                self.earn(cfg['fishdex_coins'][n], 'achv')
        if f['rar'] in cfg['first_fish_energy'] and f['rar'] not in self.first_rar:
            self.first_rar.add(f['rar']); self.add_energy_bonus(cfg['first_fish_energy'][f['rar']], 'achv')
        if city not in self.cities:
            self.cities.add(city); self.add_xp('fishing', cfg['first_city_xp'], oneoff=True)
        self.add_xp('fishing', self.ld_xp(cfg['fish_xp'][f['rar']], lv - f['lv']))
        return True

    def collect_traps(self):
        if self.traps == 0:
            return
        tr = self.cfg['trap']
        if self.trap_last is None:
            self.trap_last = self.t
            return
        el = self.t - self.trap_last
        if el >= tr['every'] * tr['cap']:
            n = tr['cap']; self.trap_last = self.t
        else:
            n = int(el // tr['every']); self.trap_last += n * tr['every']
        if n <= 0:
            return
        tiers = self._pool('pond', self.cfg['home_regional'], 'day', 'sun', 1)
        lv = self.level('fishing')
        for _ in range(n * self.traps):
            rare = lv >= tr['rare_from'] and self.rng.random() * 100 < tr['rare_pct'] and tiers[2]
            pool = tiers[2] if rare else tiers[0] + tiers[1]
            fid = self.rng.choices([c for c, _ in pool], weights=[x for _, x in pool])[0]
            f = self.cfg['fish'][fid]
            self.inv[fid] += 1
            self.daily[self.day()]['fish_value'] += f['price']; self.daily[self.day()]['trap_fish'] += 1
            self.add_xp('fishing', self.ld_xp(round(self.cfg['fish_xp'][f['rar']] * tr['xp_pct'] / 100), lv - f['lv']))

    # ------------------------------------------------------------ 料理（sim_v3.cook_plan + 配方卡免发现额度）
    def cook_plan(self, sessions_left=0):
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
                if new and self.discover_today >= self.a['discover'] and did not in self.carded:
                    continue
                if not new and self.page_pots_today[did] >= 2:
                    continue
                cost = sum(cfg['fish'][i]['price'] if i in cfg['fish'] else cfg['crops'].get(i, {'price': 1})['price'] for i in used)
                cands.append((0 if new else 1, -self.expected_cook_xp(d, did), -cfg['restore'][d['rar']], self.dishes[did], cost, did, used))
            if not cands:
                break
            cands.sort(key=lambda x: x[:5])
            did, used = cands[0][5], cands[0][6]
            carded = did in self.carded and did not in self.cooked_once
            before = self.discover_today
            self.cook(did, used)
            if carded:
                self.discover_today = before
        total = sum(v for v in self.dishes.values() if v > 0)
        excess = total - cfg['dish_stock_cap']
        while excess > 0:
            did = max((k for k, v in self.dishes.items() if v > 0), key=lambda k: self.dishes[k])
            self.dishes[did] -= 1; excess -= 1; self.gifted_total += 1
            self.daily[self.day()]['gifted'] += 1

    # ------------------------------------------------------------ 卖
    def keep(self, k):
        cfg = self.cfg
        if self.a.get('barter_hoard') and (k == cfg['home_crop'] or k in cfg['home_regional']):
            return self.a['barter_hoard']          # 换料库存：留够两天的 6 次（12 件）× 2
        if self.a.get('v2sell'):
            return 2 if k in cfg['fish'] else 3
        if k in cfg['fish']:
            return S.FISH_KEEP[cfg['fish'][k]['rar']]
        if k == cfg['home_crop']:
            return 8
        return S.CROP_KEEP.get(k, 2)

    def sell(self):
        cfg = self.cfg
        for k, n in list(self.inv.items()):
            if n <= 0:
                continue
            if k in cfg['fish']:
                price = cfg['fish'][k]['price']; src = 'fish'
            elif k in cfg['crops']:
                if k in ('herb', 'chili'):
                    continue
                price = cfg['crops'][k]['price']; src = 'crops'
            elif k in cfg['perennials']:
                price = cfg['perennials'][k][5]; src = 'crops'
            else:
                continue
            sellable = n - self.keep(k)
            if sellable > 0:
                self.inv[k] -= sellable; self.earn(sellable * price, src)

    # ------------------------------------------------------------ 委托（简化 S4）
    def do_requests(self):
        cfg = self.cfg
        kf = self.a.get('req_per_day', 0)
        k = int(kf) + (1 if self.rng.random() < kf - int(kf) else 0)
        k = min(k, cfg['quotas']['sys_requests']['cap'])
        if k <= 0:
            return
        lv = {'farming': self.level('farming'), 'fishing': self.level('fishing'), 'cooking': self.level('cooking'), 'homestead': self.hs}
        avail = []
        for tid, tp in cfg['req_templates'].items():
            if tp.get('enabled') is False or tp.get('type') == 'together':
                continue
            if any(lv.get(s, 0) < n for s, n in tp.get('gate', [])):
                continue
            need = tp['need']; kind = need['kind']
            if kind == 'material':
                continue                    # 不交材料：材料留给 Homestead（简化）
            far = (kind == 'visit' and need['visit'].get('where') != 'same_city') or need.get('regional') == 'other_zone' or need.get('where') == 'not_home'
            if far and self.a['travel'] == 'none':
                continue
            avail.append(tp)
        if not avail:
            return
        left = cfg['quotas']['request_bonus']['cap']
        coins = 0.0; done = 0
        for _ in range(k):
            tp = self.rng.choice(avail)
            b = min(tp['bonus'], left)
            if b <= 0:
                break
            left -= b; done += 1
            slv = lv.get(tp.get('skill'), 1)
            lo, hi = next(((a, b2) for at, a, b2 in reversed(cfg['req_qty']) if slv >= at), (2, 3))
            qty = (lo + hi) / 2 * tp.get('scale', 1)
            kind = tp['need']['kind']
            if kind in ('crop', 'fish'):
                unit = {1: 4, 2: 8, 3: 14, 4: 30}.get(tp['need'].get('rarity'), 6 if slv < 4 else 9 if slv < 7 else 12)
                coins += b - (1 - cfg['req_floor']) * qty * unit
            elif kind == 'dish':
                coins += b + qty * 3        # 交出的是吃不完的菜：料理地板价约 3
            else:
                coins += b
        if coins > 0:
            self.earn(int(coins), 'requests')
        self.daily[self.day()]['requests_done'] += done

    # ------------------------------------------------------------ Homestead 与特产换料
    def next_need(self):
        return {} if self.hs >= 10 else self.cfg['hs_levels'][self.hs + 1]['mats']

    def barter_room(self, m, need):
        b = self.cfg['barter']
        capped = (b['salt'] == 'cap') if m == 'rock_salt' else b['mineral_cap']
        if not capped:
            return need - self.bartered_lv[m]
        return math.floor(need * b['share']) - self.bartered_lv[m]

    def barter(self, need):
        b = self.cfg['barter']
        if not b['items']:
            return
        for m in b['minerals'] + (['rock_salt'] if b['salt'] else []):
            q = need.get(m, 0)
            lack = q - self.mats[m]
            room = self.barter_room(m, q)
            while lack > 0 and room > 0 and self.barter_today < b['per_day']:
                it = next((i for i in b['items'] if self.inv[i] >= b['give']), None)
                if it is None:
                    return
                self.inv[it] -= b['give']; self.mats[m] += 1; self.bartered_lv[m] += 1
                self.barter_today += 1; lack -= 1; room -= 1
                self.daily[self.day()]['barter'] += 1
                if m == 'rock_salt':
                    self.daily[self.day()]['barter_salt'] += 1

    def try_upgrade(self):
        cfg = self.cfg
        if self.hs >= 10:
            return
        L = cfg['hs_levels'][self.hs + 1]; need = L['mats']
        if self.level('farming') + self.level('fishing') < L['skills']:
            self.daily[self.day()]['hs_block'] = 'skills'
            return
        self.barter(need)
        ss = cfg.get('stall_salt')
        if ss and self.mats['rock_salt'] < need.get('rock_salt', 0):     # 驿站卖盐（假设）：只为升级缺的那几份买
            n_day, price = ss
            while self.salt_today < n_day and self.mats['rock_salt'] < need['rock_salt'] and self.wallet - price >= cfg['wallet_floor']:
                self.pay(price, 'salt'); self.mats['rock_salt'] += 1; self.salt_today += 1
                self.daily[self.day()]['salt_bought'] += 1
        lacking = [m for m, q in need.items() if self.mats[m] < q]
        if lacking:
            self.daily[self.day()]['hs_block'] = ','.join(lacking)
            return
        if self.wallet - L['coins'] < cfg['wallet_floor'] + self.seed_reserve():
            self.daily[self.day()]['hs_block'] = 'coins'
            return
        for m, q in need.items():
            self.mats[m] -= q
        self.pay(L['coins'], 'homestead'); self.hs += 1
        self.bartered_lv.clear()
        self.energy = self.energy_max()
        self.milestones.setdefault(f'hs_lv{self.hs}', self.day())

    # ------------------------------------------------------------ 买
    def purchases(self):
        cfg = self.cfg; a = self.a; reserve = self.seed_reserve() + cfg['wallet_floor']; buy = a['buy']
        flv = self.level('farming'); filv = self.level('fishing')
        need = self.next_need()

        def surplus(cost):
            return all(self.mats[k] >= v + need.get(k, 0) for k, v in cost.items())

        def use(cost):
            for k, v in cost.items():
                self.mats[k] -= v
        if not self.pickaxe and a.get('mine') and all(self.mats[k] >= v for k, v in cfg['pickaxe'].items()):   # 不下矿的不做铜镐
            use(cfg['pickaxe']); self.pickaxe = True
        if not self.gloves and self.hs >= 2 and all(self.mats[k] >= v for k, v in cfg['gloves'].items()):
            use(cfg['gloves']); self.gloves = True
        for rod, r in cfg['rods'].items():
            if r['cap'] > cfg['rods'][self.rod]['cap'] and filv >= r['lv'] and \
                    self.wallet - r['price'] >= cfg['wallet_floor'] + (300 if (buy == 'light' and r['price'] >= 300) else 60):
                self.pay(r['price'], 'gear'); self.rod = rod; self.milestones.setdefault('rod_' + rod, self.day())
        want = {'worm': a['worms'], 'lure': a['lures']}
        for bait, (glv, price, stock) in cfg['bait_price'].items():
            if filv < glv or want[bait] <= 0:
                continue
            fill = a.get('lure_fill', 2) if bait == 'lure' else 2      # sim_v3：每场补到画像量的 2 倍
            n = max(0, min(want[bait] * fill - self.inv[bait], stock - self.bait_bought_today[bait]))
            if bait == 'lure' and a.get('lure_daily'):
                n = max(0, min(n, a['lure_daily'] - self.bait_bought_today[bait]))
            if n > 0 and self.wallet - n * price >= cfg['wallet_floor'] + (60 if bait == 'worm' else reserve):
                self.pay(n * price, 'bait' if bait == 'worm' else 'lure')   # §9.15.1：蚯蚓 A、亮片 C
                self.inv[bait] += n; self.bait_bought_today[bait] += n
        cp = cfg['compost']
        if buy != 'light' and flv >= cp['gate']:
            n = min(5 if not self.arch.startswith('H') else 10, cp['daily'] - self.compost_bought_today)
            if n > 0 and self.inv['compost'] < 20 and self.wallet - n * cp['price'] >= reserve + 100:
                self.pay(n * cp['price'], 'fertilizer'); self.inv['compost'] += n; self.compost_bought_today += n
        # 洒水器：盖满露天一年生（材料只用"下一级 Homestead 所需"之外的盈余；只要有一块空田）
        sp = cfg['sprinkler']
        if flv >= sp['gate'] and not a.get('no_facilities'):
            n = cfg['plot_cap'](self.hs)
            plan = max(self.ghs, a.get('spr_plan_gh', 0))
            if plan > self.ghs and layout(n, plan, len(self.perennials), 0) is not None:
                target = sprinkler_target(n, plan, len(self.perennials), cfg['sprinkler_max'](self.hs))
            else:
                target = sprinkler_target(n, self.ghs, len(self.perennials), cfg['sprinkler_max'](self.hs))
            while self.sprinklers < target and surplus(sp['cost']):
                fr = self.annual_free()
                if fr['cov'] + fr['open'] <= 0 or layout(n, self.ghs, len(self.perennials), self.sprinklers + 1) is None:
                    break
                use(sp['cost']); self.sprinklers += 1
                self.milestones.setdefault(f'sprinkler_{self.sprinklers}', self.day())
        cb = cfg['compost_bin']
        if buy != 'light' and flv >= cb['gate'] and not self.compost_bin and surplus(cb['cost']):
            use(cb['cost']); self.compost_bin = True; self.milestones.setdefault('compost_bin', self.day())
        if self.compost_bin:
            for k, keep in (('herb', 6), ('chili', 4)):
                while self.inv[k] > keep and self.bin_today < cb['daily']:
                    self.inv[k] -= 1; self.inv['compost'] += 1; self.bin_today += 1
        if buy == 'light':
            return
        next_cost = cfg['hs_levels'][self.hs + 1]['coins'] if self.hs < 10 else 0
        rich = self.wallet - reserve - (next_cost if buy == 'sprint' else next_cost * 0.5)
        tr = cfg['trap']
        slots = max([0] + [v for k, v in cfg['trap_slots'].items() if filv >= k])
        if buy == 'balanced' and self.traps < slots and rich >= tr['price']:
            self.pay(tr['price'], 'trap'); self.traps += 1; rich -= tr['price']
            if self.trap_last is None:
                self.trap_last = self.t
        if buy == 'balanced':
            n = cfg['plot_cap'](self.hs)
            cap = min(cfg['perennial_slots'](self.hs), cfg['orchard_cap'])
            for pid, (lv, price, fh, rh, yld, up, rar) in cfg['perennials'].items():
                fr = self.annual_free()
                if len(self.perennials) < cap and flv >= lv and rich >= price and self.energy >= cfg['perx'][pid]['plant_e'] \
                        and fr['cov'] + fr['open'] > 0 and layout(n, self.ghs, len(self.perennials) + 1, self.sprinklers) is not None \
                        and sum(1 for p in self.perennials if p[0] == pid) < (2 if pid == 'apple' else 1) + (cfg['orchard_cap'] > 4) * 2:
                    self.pay(price, 'saplings'); self.spend(cfg['perx'][pid]['plant_e'], 'farm'); rich -= price
                    d = flv - lv
                    self.perennials.append([pid, self.t + fh * 60, self.ld_xp(cfg['perx'][pid]['plant_xp'], d)])
        rhc = cfg['row_hoe']
        if buy == 'balanced' and not self.row_hoe and flv >= rhc['gate'] and rich >= rhc['price']:
            self.pay(rhc['price'], 'row_hoe'); self.row_hoe = True; rich -= rhc['price']
        if buy == 'balanced':
            for hs_lv, (price, mats_) in cfg['bag_upgrade'].items():
                if self.hs >= hs_lv and hs_lv not in self.bag_levels and rich >= price and surplus(mats_):
                    use(mats_)
                    self.pay(price, 'bag1' if hs_lv == min(cfg['bag_upgrade']) else 'bag'); self.bag_levels.add(hs_lv); rich -= price
        gh = cfg['greenhouse']
        if buy == 'balanced' and not a.get('no_facilities'):
            cap = ladder(gh['caps'], flv, 0)
            n = cfg['plot_cap'](self.hs)
            if self.ghs < cap and rich >= gh['coins'] and surplus(gh['cost']):
                if layout(n, self.ghs + 1, len(self.perennials), self.sprinklers) is not None:
                    use(gh['cost']); self.pay(gh['coins'], 'greenhouse'); self.ghs += 1; rich -= gh['coins']
                    self.milestones.setdefault(f'greenhouse_{self.ghs}', self.day())
                else:
                    self.daily[self.day()]['gh_blocked'] = 1
                    self.milestones.setdefault(f'greenhouse_{self.ghs + 1}_blocked', self.day())
        if buy == 'balanced':
            every = 3 if self.arch.startswith('H') else 4
            if self.day() % every == 0 and rich >= 200:
                elig = [did for did, d in cfg['dishes'].items() if d['card_price'] and not d['card_zone']
                        and (not d['card_zones'] or cfg['climate'] in d['card_zones'])
                        and did not in self.cooked_once and did not in self.carded]
                for _ in range(cfg['cards']['stall_daily']):
                    if not elig or rich < 200:
                        break
                    did = self.rng.choice(elig); elig.remove(did)
                    price = cfg['dishes'][did]['card_price']
                    self.pay(price, 'recipes'); self.carded.add(did); rich -= price
            if self.arch.startswith('H'):
                for did, d in cfg['dishes'].items():
                    if d['card_zone'] == cfg['climate'] and did not in self.cooked_once and did not in self.carded and rich >= d['card_price'] + 500:
                        self.pay(d['card_price'], 'recipes'); self.carded.add(did); rich -= d['card_price']
                if self.day() % 5 == 0 and rich >= 500:
                    for price, did, hlv in cfg['decor_items']:
                        if did not in self.decor_bought and self.hs >= hlv:
                            self.pay(price, 'decor'); self.decor_bought.add(did); rich -= price
                            break
                if not self.postcard and rich >= 300:
                    self.pay(cfg['postcard'], 'specialty'); self.postcard = True
        if a['tea'] == 'daily':
            while self.tea_today < cfg['tea_cups'] and self.energy <= self.energy_max() - cfg['tea'] and \
                    self.wallet - cfg['tea_price'][self.tea_today] >= cfg['wallet_floor']:
                self.pay(cfg['tea_price'][self.tea_today], 'tea'); self.tea_today += 1
                self.energy += cfg['tea']; self.daily[self.day()]['tea'] += cfg['tea']

    # ------------------------------------------------------------ 会话
    def session(self, idx, t0, minutes, day):
        self.settle(t0)
        if self.req_day != self.day():
            self.req_day = self.day()
            if day >= 2:
                self.do_requests()
        self.cur_idx = idx
        self.a['casts'] = list(self.base_casts)
        self._redirect = bool(self.a.get('redirect'))
        super().session(idx, t0, minutes, day)
        self._redirect = False
        L = self.layout()
        rec = self.daily[self.day()]
        rec['plots_cap'] = L['cells']; rec['plots_annual'] = L['gh'] + L['cov'] + L['open']
        rec['plots_gh'] = L['gh']; rec['plots_cov'] = L['cov']; rec['trees'] = len(self.perennials); rec['sprinklers'] = self.sprinklers


# ============================================================================
# 6. 跑、汇总
# ============================================================================
KEYS = ['energy', 'xp_farming', 'xp_fishing', 'xp_cooking', 'income', 'seed_cost', 'sink', 'meal', 'meal_nominal', 'harvest_value',
        'fish_value', 'material_value', 'casts', 'energy_farm', 'energy_fish', 'energy_mine', 'energy_travel', 'walls', 'rest', 'tea', 'bonus',
        'sown_energy', 'sow_short', 'cap_waste', 'meals', 'cooked', 'harvest_plots', 'fish_caught', 'gifted', 'income_fish', 'income_crops',
        'income_requests', 'income_achv', 'requests_done', 'trap_fish', 'compost_used', 'barter', 'redirect_casts', 'mine_runs',
        'plots_cap', 'plots_annual', 'plots_gh', 'plots_cov', 'trees', 'sprinklers', 'seed_saver', 'gh_blocked', 'salt_bought', 'barter_salt']
SINKS = ['homestead', 'gear', 'bait', 'fertilizer', 'travel', 'travel_items', 'salt', 'trap', 'saplings', 'bag1', 'recipes', 'row_hoe',
         'tea', 'lure', 'decor', 'bag', 'greenhouse', 'specialty']
SINK_A = ('homestead', 'gear', 'bait', 'fertilizer', 'travel', 'travel_items', 'salt')   # salt：驿站买岩盐（只在 s4 / s5 假设里有）
SINK_B = ('trap', 'saplings', 'bag1', 'recipes', 'row_hoe')
SINK_C = ('tea', 'lure', 'decor', 'bag', 'greenhouse', 'specialty')     # §9.15.1：亮片 6 × ≤ 10 / 日在 C 类（蚯蚓在 A）


def run(arch, a, cfg, seed, days):
    rng = random.Random(seed)
    p = P1Player(arch, cfg, rng, copy.deepcopy(a))
    p.first_session(12 * 60)
    for day in range(1, days + 1):
        for idx, (mod, minutes) in enumerate(p.a['sessions']):
            t0 = (day - 1) * 1440 + mod
            if day == 1 and t0 < 12 * 60 + 30:
                continue
            p.session(idx, t0, minutes, day)
    return p, [dict(day=d, **p.daily.get(d, Counter())) for d in range(1, days + 1)]


def summarize(arch, a, cfg, seeds, days):
    runs = [run(arch, a, cfg, s, days) for s in range(seeds)]
    keys = {k for p, _ in runs for k in p.milestones}
    ms = {k: statistics.mean([p.milestones.get(k, days + 1) for p, _ in runs]) for k in keys}
    reach = {k: sum(1 for p, _ in runs if k in p.milestones) / len(runs) for k in keys}
    agg = []
    for d in range(days):
        rows = [o[d] for _, o in runs]
        agg.append({k: statistics.mean([r.get(k, 0) or 0 for r in rows]) for k in KEYS + ['sink_' + s for s in SINKS]})
    return dict(arch=arch, a=a, runs=runs, ms=ms, reach=reach, agg=agg, days=days, seeds=seeds)


def win(R, lo, hi, k):
    w = R['agg'][lo:min(hi, R['days'])]
    return statistics.mean(x[k] for x in w) if w else 0.0


def ledger(R, cfg):
    w28 = R['agg'][:28]
    inc = cfg['initial_wallet'] + sum(x['income'] - x['seed_cost'] for x in w28)
    s = {k: sum(x['sink_' + k] for x in w28) for k in SINKS}
    A = sum(s[k] for k in SINK_A); B = sum(s[k] for k in SINK_B); Cc = sum(s[k] for k in SINK_C)
    return dict(inc=inc, A=A, B=B, C=Cc, low=A / inc, mid=(A + B) / inc, high=(A + B + Cc) / inc, sinks=s,
                mid_lureA=(A + B + s['lure']) / inc)        # sim_v3 旧口径（亮片算 A），只作对照


def walls(R, lo=7, hi=30):
    per = [sum(o[d].get('walls', 0) or 0 for d in range(lo, min(hi, R['days']))) / max(1, min(hi, R['days']) - lo) for _, o in R['runs']]
    peak = max((o[d].get('walls', 0) or 0) for _, o in R['runs'] for d in range(lo, min(hi, R['days'])))
    seed_mean_peak = max(statistics.mean((o[d].get('walls', 0) or 0) for _, o in R['runs']) for d in range(lo, min(hi, R['days'])))
    allday = statistics.mean(sum(o[d].get('walls', 0) or 0 for d in range(R['days'])) / R['days'] for _, o in R['runs'])
    return dict(mean=statistics.mean(per), peak=peak, seed_mean_peak=seed_mean_peak, all=allday)


def mday(R, k, digits=0):
    v = R['ms'].get(k)
    r = R['reach'].get(k, 0)
    if v is None or r == 0:
        return '—'
    s = f'{v:.{digits}f}'
    return s if r >= 0.999 else f'{s}*（{r * R["seeds"]:.0f}/{R["seeds"]}）'


def mval(R, k):
    v = R['ms'].get(k)
    return v if (v is not None and R['reach'].get(k, 0) >= 0.999) else None


def hs_max(R):
    return statistics.mean(p.hs for p, _ in R['runs'])


# ============================================================================
# 7. 报告
# ============================================================================
class Out:
    def __init__(self):
        self.lines = []

    def __call__(self, s=''):
        self.lines.append(s)
        print(s, flush=True)


def band(v, lo, hi):
    return v is not None and lo <= v <= hi


def fmt(v, d=0):
    return '—' if v is None else f'{v:.{d}f}'


def exit_checks(R, L, N, cfg):
    """§17.3.2 节奏与账本各条；判定照 sim_v3 约定（两轨 / Cooking 看 P30，Homestead 看 HEAVY 与 P30C，中界看 P5 / P30 / HEAVY）。"""
    out = []

    def chk(name, ok, detail):
        out.append((name, ok, detail))
    p30 = [mval(R['P30'], 'fishing_lv10'), mval(R['P30'], 'farming_lv10')]
    p30c = [mval(R['P30C'], 'fishing_lv10'), mval(R['P30C'], 'farming_lv10')]
    chk('30 分钟玩家两轨 21 ± 5 天（P30；P30C 参考）', all(band(v, 16, 26) for v in p30),
        f'P30 Fishing {fmt(p30[0], 1)} / Farming {fmt(p30[1], 1)}；P30C {fmt(p30c[0], 1)} / {fmt(p30c[1], 1)}')
    h = [mval(R['HEAVY'], 'fishing_lv10'), mval(R['HEAVY'], 'farming_lv10')]
    chk('重度两轨 ≥ 8 天', all(v is not None and v >= 8 for v in h), f'Fishing {fmt(h[0], 1)} / Farming {fmt(h[1], 1)}')
    p5 = [R['P5']['ms'].get('fishing_lv10'), R['P5']['ms'].get('farming_lv10')]
    p5r = [R['P5']['reach'].get('fishing_lv10', 0), R['P5']['reach'].get('farming_lv10', 0)]
    chk('5 分钟玩家两轨 ≤ 90 天', all(r >= 0.999 and v <= 90 for v, r in zip(p5, p5r)),
        f'Fishing {mday(R["P5"], "fishing_lv10", 1)} / Farming {mday(R["P5"], "farming_lv10", 1)}')
    c30 = mval(R['P30'], 'cooking_lv10'); c30c = mval(R['P30C'], 'cooking_lv10')
    chk('Cooking：30 分钟玩家 Lv10 21 ± 5 天（P30；P30C 参考）', band(c30, 16, 26),
        f'P30 {fmt(c30, 1)}；P30C {fmt(c30c, 1)}；（参考）5 分钟 {mday(R["P5"], "cooking_lv10", 1)}')
    c4 = [mval(R['P30'], 'cooking_lv4'), mval(R['P30C'], 'cooking_lv4')]
    chk('Cooking：30 分钟玩家 Lv4 在首周内（≤ 第 7 天）', c4[0] is not None and c4[0] <= 7, f'P30 第 {fmt(c4[0], 1)} 天；P30C 第 {fmt(c4[1], 1)} 天')
    ch = mval(R['HEAVY'], 'cooking_lv10')
    chk('Cooking：重度 Lv10 ≥ 8 天', ch is not None and ch >= 8, f'HEAVY {fmt(ch, 1)}（Lv4 第 {fmt(mval(R["HEAVY"], "cooking_lv4"), 1)} 天）')
    hh = mval(R['HEAVY'], 'hs_lv10')
    chk('Homestead Lv10：重度 30–35 天', band(hh, 30, 35), f'HEAVY {mday(R["HEAVY"], "hs_lv10", 1)}')
    hc = R['P30C']['ms'].get('hs_lv10'); hcr = R['P30C']['reach'].get('hs_lv10', 0)
    chk('Homestead Lv10：30 分钟玩家（P30C）60–70 天（58–59 按口径接受）', hcr >= 0.999 and 58 <= hc <= 70,
        f'P30C {mday(R["P30C"], "hs_lv10", 1)}；（参考）P30 {mday(R["P30"], "hs_lv10", 1)}、P30B {mday(R["P30B"], "hs_lv10")}、P5 {mday(R["P5"], "hs_lv10")}（120 天末 Lv{hs_max(R["P5"]):.1f}）')
    for k in ('P5', 'P30', 'HEAVY'):
        extra = f'；P30C 参考 {L["P30C"]["low"]:.0%} / {L["P30C"]["mid"]:.0%} / {L["P30C"]["high"]:.0%}' if k == 'P30' else ''
        chk(f'金币去向中界 60–80%（{k}）', 0.6 <= L[k]['mid'] <= 0.8, f'下 / 中 / 上 {L[k]["low"]:.0%} / {L[k]["mid"]:.0%} / {L[k]["high"]:.0%}{extra}')
    W = walls(R['HEAVY'])
    chk('重度日撞墙 ≤ 1（第 8–30 天日均与单日峰值）', W['mean'] <= 1 and W['peak'] <= 1,
        f'日均 {W["mean"]:.2f}；单日峰值（{N} seed 中最高）{W["peak"]:.0f}')
    mm = cfg['derive_mismatch']
    chk('（附）一道菜一套数值：48 页稀有度 = derive 现算', not mm, '全部一致' if not mm else f'{len(mm)} 页不一致：{mm}')
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--days', type=int, default=120)
    ap.add_argument('--seeds', type=int, default=12)
    ap.add_argument('--only', default='all', help='all / main')
    ap.add_argument('--md', default=os.path.join(HERE, 'out_p1.md'))
    args = ap.parse_args()
    D, N = args.days, args.seeds
    t_start = time.time()
    P = Out()
    cfg = p1_config(plot_ladder=BASE_LADDER)
    P(f'# P1 出口 · 模拟器全套复跑（sim_p1.py，{D} 天 × {N} seed；基线 = Homestead Lv7 起 48 格）')
    P()
    P(f'数据：`assets/p0/p0_content.json` + `assets/p0/content/` {len(CONTENT["_files"])} 个片段（{", ".join(CONTENT["_files"])}），'
      f'版本 `{CONTENT.get("version")}`；作物 {len(cfg["crops"]) + len(cfg["perennials"])}、鱼 {len(cfg["fish"])}、可做菜谱 {len(cfg["dishes"])} / 48、'
      f'Homestead Lv2–10 金币合计 {sum(L["coins"] for L in cfg["hs_levels"].values()):,}。家城旧金山（温带），本带地区作物 {cfg["home_crop"]}、本城地区鱼 {" + ".join(cfg["home_regional"])}。')
    P()

    # ---------------- 主表：Lv7 起 48 格为基线，现数据 40 格作对照 ----------------
    main_arch = ['P5', 'P30', 'P30C', 'P30B', 'HEAVY']
    cfg40 = p1_config()
    R = {k: summarize(k, ARCH[k], cfg, N, D) for k in main_arch}
    R40 = {k: summarize(k, ARCH[k], cfg40, N, D) for k in main_arch}
    L = {k: ledger(R[k], cfg) for k in main_arch}
    L40 = {k: ledger(R40[k], cfg40) for k in main_arch}
    checks = exit_checks(R, L, N, cfg)
    checks40 = exit_checks(R40, L40, N, cfg40)
    P('## 1. §17.3.2 出口标准逐条（节奏、账本）')
    P()
    P(f'基线 = **Homestead Lv7 起 48 格**（q(172) 已提出，待批）；右两列是现数据 40 格的对照。第 N 天 = {N} seed 均值。'
      '判定照 sim_v3 的约定：两轨与 Cooking 看 P30（34 竿），P30C 只作参考；Homestead 看 HEAVY 与 P30C；中界看 P5 / P30 / HEAVY，P30C 参考。'
      '中界的记账按 §9.15.1：蚯蚓在 A（必需），亮片在 C（日常可选）。')
    P()
    P('| # | 标准 | Lv7 起 48 格（基线） | 数字 | 现数据 40 格 | 数字 |')
    P('|---|---|---|---|---|---|')
    for i, ((name, ok, detail), (_, ok40, d40)) in enumerate(zip(checks, checks40), 1):
        P(f'| {i} | {name} | **{"PASS" if ok else "FAIL"}** | {detail} | {"PASS" if ok40 else "**FAIL**"} | {d40} |')
    P()
    W = walls(R['HEAVY'])

    P('## 2. 里程碑（第 N 天；* = 未全部到达，括号为到达 seed 数；— = 120 天未达）')
    P()
    keys = [f'{t}_lv{n}' for t in ('fishing', 'farming', 'cooking') for n in (2, 4, 6, 8, 10)] + [f'hs_lv{n}' for n in range(2, 11)] + \
           ['rod_reed', 'rod_carbon', 'sprinkler_1', 'greenhouse_1', 'greenhouse_2', 'greenhouse_2_blocked', 'compost_bin']
    lab = lambda k: k.replace('fishing_lv', 'Fi').replace('farming_lv', 'Fa').replace('cooking_lv', 'Co').replace('hs_lv', 'Hs').replace('rod_', '竿 ').replace('sprinkler_1', '洒水器').replace('greenhouse_2_blocked', '温室2放不下').replace('greenhouse_', '温室').replace('compost_bin', '堆肥箱')  # noqa: E731
    P('| 画像 | ' + ' | '.join(lab(k) for k in keys) + ' |')
    P('|' + '---|' * (len(keys) + 1))
    for k in main_arch:
        P(f'| {k} | ' + ' | '.join(mday(R[k], x) for x in keys) + ' |')
    P()

    P('## 3. 账本（第 8–30 天稳态日均；28 天吸收比）')
    P()
    P('| 画像 | 日均体力 | 播种 / 钓鱼 / 矿洞 | 日均竿 | 播种没花完 | 满条溢出回复 | 日均锅 | 料理名义回复 | Rest / 茶 / 成就 | 日撞墙 | 稳态日净收入 | 其中委托 | 28 日收入（含 180） | 下界 / 中界 / 上界 | 120 天末钱包 / Hs |')
    P('|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for k in main_arch:
        r = R[k]
        net = win(r, 7, 30, 'income') - win(r, 7, 30, 'seed_cost')
        wl = walls(r)
        P(f'| {k} | {win(r, 7, 30, "energy"):.0f} | {win(r, 7, 30, "energy_farm"):.0f} / {win(r, 7, 30, "energy_fish"):.0f} / {win(r, 7, 30, "energy_mine"):.0f} | '
          f'{win(r, 7, 30, "casts"):.0f} | {win(r, 7, 30, "sow_short"):.0f} | {win(r, 7, 30, "cap_waste"):.0f} | {win(r, 7, 30, "cooked"):.1f} | {win(r, 7, 30, "meal_nominal"):.0f} | '
          f'{win(r, 7, 30, "rest"):.0f} / {win(r, 7, 30, "tea"):.0f} / {win(r, 7, 30, "bonus"):.0f} | {wl["mean"]:.2f} | {net:.0f} | {win(r, 7, 30, "income_requests"):.0f} | '
          f'{L[k]["inc"]:.0f} | {L[k]["low"]:.0%} / {L[k]["mid"]:.0%} / {L[k]["high"]:.0%} | '
          f'{statistics.mean(p.wallet for p, _ in r["runs"]):.0f} / {hs_max(r):.1f} |')
    P()
    P('28 天去向构成（金币，seed 均值；按 §9.15.1：A 必需 = 升级 + 渔具 + 蚯蚓（bait）+ 肥料 + 旅行；B 成长可选 = 鱼笼 + 树苗 + 扩容 I + 配方卡 + 行锄；C = 茶 + 亮片（lure）+ 摆件 + 扩容 II/III + 温室 + 明信片）：')
    P()
    P('| 画像 | ' + ' | '.join(SINKS) + ' |')
    P('|' + '---|' * (len(SINKS) + 1))
    for k in main_arch:
        P(f'| {k} | ' + ' | '.join(f'{L[k]["sinks"][s]:.0f}' for s in SINKS) + ' |')
    P()
    P('Homestead 被卡原因（seed 0，按天计）：')
    P()
    for k in main_arch:
        blocks = Counter(o.get('hs_block', '') for o in R[k]['runs'][0][1] if o.get('hs_block'))
        P(f'- {k}：{dict(blocks.most_common(6))}')
    P()
    if args.only == 'main':
        write(P, args.md, t_start)
        return

    # ---------------- 田数变体 ----------------
    P('## 4. 田数变体（q(118) ⑦）：Lv4–10 一直 40 格 vs Lv7 起 +8 vs Lv8 起 +8')
    P()
    ladders = {'40 格（现数据）': [(1, 30), (3, 40)], 'Lv7 起 48 格': [(1, 30), (3, 40), (7, 48)], 'Lv8 起 48 格': [(1, 30), (3, 40), (8, 48)]}
    plot_arch = [('HEAVY', ARCH['HEAVY'], 4), ('HEAVY（果园种满 8 株）', ARCH['HEAVY'], 8),
                 ('HEAVY（播不下的体力转去钓鱼）', variant('HEAVY', redirect=True), 4),
                 ('HEAVY（洒水器按两座温室规划）', variant('HEAVY', spr_plan_gh=2), 4), ('P30C', ARCH['P30C'], 4)]
    PR = {}
    P('| 画像 | 田数 | 一年生可用格（d31–60：温室 / 洒水 / 总） | 播种体力 d8–30 · d31–60 | 播种没花完 d8–30 · d31–60 | 满条溢出 d31–60 | 日撞墙 d8–30 · 全程 | 转去钓鱼的竿 / 日 | Fa10 | Fi10 | Hs7 | Hs8 | Hs10 |')
    P('|---|---|---|---|---|---|---|---|---|---|---|---|---|')
    for name, a, orch in plot_arch:
        for ln, ld in ladders.items():
            c2 = p1_config(plot_ladder=ld, orchard=orch)
            r = summarize(name.split('（')[0], a, c2, N, D)
            PR[(name, ln)] = r
            wl = walls(r)
            P(f'| {name} | {ln} | {win(r, 30, 60, "plots_gh"):.0f} / {win(r, 30, 60, "plots_cov"):.0f} / {win(r, 30, 60, "plots_annual"):.0f} | '
              f'{win(r, 7, 30, "energy_farm"):.0f} · {win(r, 30, 60, "energy_farm"):.0f} | {win(r, 7, 30, "sow_short"):.0f} · {win(r, 30, 60, "sow_short"):.0f} | '
              f'{win(r, 30, 60, "cap_waste"):.0f} | {wl["mean"]:.2f} · {wl["all"]:.2f} | {win(r, 7, 60, "redirect_casts"):.0f} | '
              f'{mday(r, "farming_lv10")} | {mday(r, "fishing_lv10")} | {mday(r, "hs_lv7")} | {mday(r, "hs_lv8")} | {mday(r, "hs_lv10")} |')
    P()
    h40, h7, h8 = (PR[('HEAVY', k)] for k in ladders)
    gh2 = lambda r: f'{r["reach"].get("greenhouse_2", 0) * r["seeds"]:.0f}/{r["seeds"]}'  # noqa: E731
    P(f'读法：重度在 40 格上第 31–60 天每天有 {win(h40, 30, 60, "sow_short"):.0f} 点播种预算播不下、{win(h40, 30, 60, "cap_waste"):.0f} 点自然回复满条溢出；'
      f'Lv7 / Lv8 起 48 格把播不下的降到 {win(h7, 30, 60, "sow_short"):.0f} / {win(h8, 30, 60, "sow_short"):.0f}、播种体力 +{win(h7, 30, 60, "energy_farm") - win(h40, 30, 60, "energy_farm"):.0f} / 日，'
      f'Homestead Lv10 {mday(h40, "hs_lv10", 1)} → {mday(h7, "hs_lv10", 1)} / {mday(h8, "hs_lv10", 1)}、Farming Lv10 {mday(h40, "farming_lv10")} → {mday(h7, "farming_lv10")}（Farming 满级早于 Hs7，扩田碰不到它），'
      f'日撞墙都 ≈ 0。第二座温室在 40 格上放下的 seed 数 {gh2(h40)}，48 格 {gh2(h7)}（洒水器盖满露天田 + 4 株树后，40 格里温室块外只剩 8 格）。'
      f'P30C 播种从来花得完（播不下 {win(PR[("P30C", "40 格（现数据）")], 30, 60, "sow_short"):.0f} / 日），扩田对他没有可见影响。')
    P()

    # ---------------- 公平 ----------------
    P('## 5. 公平：四个气候带（同一画像只换家城气候带：地区作物 + 本城 2 种地区鱼）')
    P()
    P('| 气候带 | 地区作物（档 / 时长 / 产量 × 单价） | 本城地区鱼 | P30C Hs10 | P30C Fa10 / Fi10 / Co10 | HEAVY Hs10 | HEAVY Fa10 / Fi10 / Co10 | P30C 120 天换料次数 |')
    P('|---|---|---|---|---|---|---|---|')
    FR = {}
    for cl in CLIMATES:
        c2 = p1_config(climate=cl, plot_ladder=BASE_LADDER)
        rc = R['P30C'] if cl == 'Temperate' else summarize('P30C', ARCH['P30C'], c2, N, D)
        rh = R['HEAVY'] if cl == 'Temperate' else summarize('HEAVY', ARCH['HEAVY'], c2, N, D)
        FR[cl] = (rc, rh)
        hc_ = c2['crops'][c2['home_crop']]
        bart = statistics.mean(sum(o.get('barter', 0) or 0 for o in run_[1]) for run_ in rc['runs'])
        P(f'| {cl} | {c2["home_crop"]}（Lv{hc_["lv"]} / {hc_["hours"]} h / {hc_["yld"]} × {hc_["price"]}，种子 {hc_["seed"]}） | {" + ".join(c2["home_regional"])} | '
          f'{mday(rc, "hs_lv10")} | {mday(rc, "farming_lv10")} / {mday(rc, "fishing_lv10")} / {mday(rc, "cooking_lv10")} | '
          f'{mday(rh, "hs_lv10")} | {mday(rh, "farming_lv10")} / {mday(rh, "fishing_lv10")} / {mday(rh, "cooking_lv10")} | {bart:.0f} |')
    spread = {}
    for i, who in enumerate(('P30C', 'HEAVY')):
        vals = [mval(FR[cl][i], 'hs_lv10') for cl in CLIMATES]
        if all(v is not None for v in vals):
            spread[who] = (max(vals) - min(vals)) / min(vals)
    cook = {}
    for i, who in enumerate(('P30C', 'HEAVY')):
        vals = [mval(FR[cl][i], 'cooking_lv10') for cl in CLIMATES]
        if all(v is not None for v in vals):
            cook[who] = (min(vals), max(vals))
    P()
    P('Homestead Lv10 天数的气候带极差 ÷ 最快带：' + '；'.join(f'{k} {v:.1%}' for k, v in spread.items()) + '（目标 ≤ 10%）。'
      '（附）Cooking Lv10 的气候带范围：' + '；'.join(f'{k} 第 {a:.0f}–{b:.0f} 天' for k, (a, b) in cook.items()) +
      '——温带 / 寒带的地区 Legendary 页（南瓜浓汤、甜菜鱼汤）要岩盐，热带 / 亚热带的（菠萝鱼、甘薯饼）不要。')
    P()
    # 从不下矿
    P('### 5.1 从不下矿、只靠特产换料（2 件本带特产 → 1 件材料；每日 ≤ 6 次）')
    P()
    D5 = max(D, 240)
    P('"从不下矿"画像 = 原画像去掉矿洞，每天固定种 10 格本带地区作物（§8.4.4 的建议；库存不到 24 件时才种），地区作物与本城地区鱼各留 24 件换料、多的照卖；'
      f'换料只在升级缺料时做。P30C 跑 {D} 天，P5 跑 {D5} 天（照常下矿的 P5 在 120 天里也到不了 Lv10，要看"能走完、慢多少"得跑长一点）。'
      '"驿站卖盐"是假设：只为下一级缺的岩盐买，每天 ≤ 1 份、20 金币，记在 A 类去向。卡在什么 = 全部 seed 最后 30 天按天计。')
    P()
    SALT = (1, 20)
    MODES = [('data', 'data', None, '数据现状：#364 起按地区数据派生，同规则'),
             ('rule', 'rule', None, '方案 §8.4.5：矿物每级 ≤ 50%，岩盐不能换'),
             ('nocap', 'nocap', None, '矿物不设上限，岩盐不能换'),
             ('s1', 'salt_cap', None, '(s1) 岩盐也能换；岩盐与四种矿物都受每级 ≤ 50%'),
             ('s2', 'salt_free', None, '(s2) 岩盐也能换且不受上限；四种矿物仍受 50%'),
             ('s3', 'nocap_salt', None, '(s3) 岩盐也能换；所有材料都不设上限'),
             ('s4', 'rule', SALT, '(s4) 岩盐不能换，驿站每天卖 1 份 20 金币；矿物仍受 50%'),
             ('s5', 'nocap', SALT, '(s5，补充) 驿站每天卖 1 份岩盐 + 矿物不设上限')]
    P('| 画像 | 规则 | 天数 | 期末 Homestead（均值） | Hs4 | Hs6 | Hs8 | Hs10 | 换料次数 | 买盐次数 | 卡在什么 |')
    P('|---|---|---|---|---|---|---|---|---|---|---|')
    NR, NM = {}, {}
    tot = lambda r, k: statistics.mean(sum(o.get(k, 0) or 0 for o in run_[1]) for run_ in r['runs'])  # noqa: E731
    for who in ('P30C', 'P5'):
        days = D if who == 'P30C' else D5
        for key, mode, salt, desc in MODES:
            c2 = p1_config(barter=mode, stall_salt=salt, plot_ladder=BASE_LADDER)
            r = summarize(who + '_NOMINE', variant(who, mine=None, barter_hoard=24, regional_fixed=10), c2, N, days)
            NR[(who, key)] = r
            blocks = Counter(o.get('hs_block', '') for run_ in r['runs'] for o in run_[1][-30:] if o.get('hs_block'))
            P(f'| {who} 不下矿 | {desc} | {days} | {hs_max(r):.1f} | {mday(r, "hs_lv4")} | {mday(r, "hs_lv6")} | {mday(r, "hs_lv8")} | {mday(r, "hs_lv10")} | '
              f'{tot(r, "barter"):.0f} | {tot(r, "salt_bought"):.0f} | {", ".join(f"{k} {v / len(r["runs"]):.0f}" for k, v in blocks.most_common(2)) or "—"} |')
        ref = R[who] if days == D else summarize(who, ARCH[who], cfg, N, days)
        NM[(who, 'rule')] = ref
        P(f'| {who}（照常下矿，对照） | 方案 §8.4.5 | {days} | {hs_max(ref):.1f} | {mday(ref, "hs_lv4")} | {mday(ref, "hs_lv6")} | {mday(ref, "hs_lv8")} | {mday(ref, "hs_lv10")} | '
          f'{tot(ref, "barter"):.0f} | — | — |')
    P()
    P('**照常下矿的玩家**在同样规则下（换料 / 买盐会不会让他们也绕过矿洞）：')
    P()
    P('| 画像 | 规则 | 天数 | 期末 Homestead（均值） | Hs4 | Hs6 | Hs8 | Hs10 | 换料次数（其中岩盐） | 买盐次数 | 中界 |')
    P('|---|---|---|---|---|---|---|---|---|---|---|')
    for who in ('P30C', 'P5'):
        days = D if who == 'P30C' else D5
        for key, mode, salt, desc in MODES[1:2] + MODES[3:]:
            if key == 'rule':
                r = NM[(who, 'rule')]
            else:
                c2 = p1_config(barter=mode, stall_salt=salt, plot_ladder=BASE_LADDER)
                r = summarize(who, ARCH[who], c2, N, days)
                NM[(who, key)] = r
            lg = ledger(r, cfg)
            P(f'| {who} 照常下矿 | {desc} | {days} | {hs_max(r):.1f} | {mday(r, "hs_lv4")} | {mday(r, "hs_lv6")} | {mday(r, "hs_lv8")} | {mday(r, "hs_lv10", 1)} | '
              f'{tot(r, "barter"):.0f}（{tot(r, "barter_salt"):.0f}） | {tot(r, "salt_bought"):.0f} | {lg["mid"]:.0%} |')
    P()

    # ---------------- 敏感性 ----------------
    P('## 6. 敏感性（各只改一处，对照主表）')
    P()
    P('| 情形 | 画像 | Fa10 | Fi10 | Co10 | Hs10 | 中界 | 日撞墙 d8–30 |')
    P('|---|---|---|---|---|---|---|---|')
    SR = {}
    sens = [('主表（对照）', None, None), ('换料按数据现状（#364 起同规则）', dict(barter='data'), None),
            ('V2 机器人卖法（每种鱼留 2、作物留 3）', None, dict(v2sell=True)),
            ('委托按 sim_v3 常数（30 分钟 15、重度 32 金币 / 日）', None, 'req_const'),
            ('委托接满板（30 分钟 3 单 / 日、重度 5 单 / 日）', None, 'req_full'),
            ('居民赠餐第 5 天起（sim_v3 口径）', dict(gift_meal_day=5), None),
            ('亮片每天只买画像量（30 分钟 5、重度 10 枚；sim_v3 买法是补到 2 倍）', None, 'lure5')]
    for name, ckw, akw in sens:
        for who in ('P30', 'P30C', 'HEAVY'):
            if ckw is None and akw is None:
                r = R[who]
            else:
                c2 = p1_config(plot_ladder=BASE_LADDER, **(ckw or {}))
                if akw == 'req_const':
                    a = variant(who, req_per_day=0, requests={'P30': 15, 'P30C': 15, 'HEAVY': 32}[who])
                elif akw == 'lure5':
                    a = variant(who, lure_daily={'P30': 5, 'P30C': 5, 'HEAVY': 10}[who])
                elif akw == 'req_full':
                    a = variant(who, req_per_day={'P30': 3, 'P30C': 3, 'HEAVY': 5}[who])
                else:
                    a = variant(who, **(akw or {}))
                r = summarize(who, a, c2, N, D)
            lg = ledger(r, cfg)
            key = akw if isinstance(akw, str) else tuple(akw) if akw else tuple(ckw) if ckw else 'main'
            SR[(key, who)] = (r, lg)
            P(f'| {name} | {who} | {mday(r, "farming_lv10", 1)} | {mday(r, "fishing_lv10", 1)} | {mday(r, "cooking_lv10", 1)} | {mday(r, "hs_lv10", 1)} | {lg["mid"]:.0%} | {walls(r)["mean"]:.2f} |')
    P()
    conclusion(P, R, L, R40, checks, checks40, SR, N, spread, NR, NM)
    write(P, args.md, t_start)


def nomine_summary(NR, NM):
    """§8.4.5「从不下矿的 5 分钟玩家靠换料也能走完十级，只是慢一倍」在 s1–s5 下成不成立（数字取自 5.1 节）。"""
    def end(r):
        v = mval(r, 'hs_lv10')
        return f'第 {v:.0f} 天到 Lv10' if v is not None else f'{r["days"]} 天末 Lv{hs_max(r):.1f}'
    m5, m30 = mval(NM[('P5', 'rule')], 'hs_lv10'), mval(NM[('P30C', 'rule')], 'hs_lv10')
    parts = []
    ok = []
    for key in ('s1', 's2', 's3', 's4', 's5'):
        r5, r30 = NR[('P5', key)], NR[('P30C', key)]
        v5 = mval(r5, 'hs_lv10')
        ratio = f'，是下矿玩家的 {v5 / m5:.2f} 倍' if (v5 is not None and m5) else ''
        parts.append(f'{key}：5 分钟 {end(r5)}{ratio}；30 分钟 {end(r30)}')
        if v5 is not None:
            ok.append(key)
    drift = []
    for key in ('s1', 's2', 's3', 's4', 's5'):
        d = []
        for who, base in (('P30C', m30), ('P5', m5)):
            v = mval(NM.get((who, key), {'ms': {}, 'reach': {}}), 'hs_lv10') if (who, key) in NM else None
            if v is not None and base:
                d.append(f'{who} {v - base:+.1f}')
        if d:
            drift.append(f'{key} ' + ' / '.join(d))
    head = (f'**"只种田不挖矿也能走完十级"（§8.4.5）：** 现数据（#364 起）换料物品按地区数据派生，与方案规则相同，仍然不行——岩盐只出在矿洞且不能换（Lv2–5 共 15 份），'
            f'铜 / 石英每级又只能换一半，从不下矿的人停在 Lv1。照常下矿的 5 分钟玩家 {("第 %.0f 天到 Lv10" % m5) if m5 else "也到不了 Lv10"}，30 分钟玩家第 {m30:.0f} 天。')
    body = '各假设：' + '；'.join(parts) + '。'
    stuck = [f'{k} 停在 Lv{hs_max(NR[("P5", k)]):.0f}' for k in ('s1', 's2', 's3', 's4', 's5') if k not in ok]
    if ok:
        rat = [mval(NR[('P5', k)], 'hs_lv10') / m5 for k in ok if m5]
        rat30 = [mval(NR[('P30C', k)], 'hs_lv10') / m30 for k in ok if mval(NR[('P30C', k)], 'hs_lv10') and m30]
        tail = (f'能让 5 分钟不下矿玩家走完十级的只有 {"、".join(ok)}：岩盐要有出路，铜和石英也必须能全额换（它们同样只出在矿洞）；'
                + ('；'.join(stuck) + '（s1 的 50% 上限只给 Lv2 换 1 份盐、要 3 份；s2 / s4 有盐但 Lv4 要 6 份铜、只能换 3 份）。' if stuck else '')
                + (f'走完的话比下矿慢 {min(rat):.2f}–{max(rat):.2f} 倍（30 分钟玩家 {min(rat30):.2f}–{max(rat30):.2f} 倍），不是"慢一倍"。' if rat else ''))
    else:
        tail = '没有一个假设能让 5 分钟不下矿玩家在模拟期内走完十级。'
    if drift:
        ds = [float(x.split()[-1]) for d in drift for x in d.split(' / ')]
        faster = min(ds) < -2.5
        tail += ('照常下矿的玩家在 s1–s5 下 Homestead Lv10 的变化（天，相对现规则；正 = 更晚）：' + '；'.join(drift) +
                 (f'——有的变体让他们快了 {-min(ds):.1f} 天以上，见 5.1 第二张表。' if faster else
                  f'——没有一个变快（{min(ds):+.1f} 到 {max(ds):+.1f} 天）：他们的铜、石英、盐照样从矿洞来，卡他们的是金币；'
                  '能换盐时还会拿本来要卖的地区作物去换，反而略慢。换料 / 买盐不会让正常玩家绕过矿洞。'))
    return head + body + tail


def _req_verdict(SR):
    out = []
    for who, lo, hi in (('HEAVY', 30, 35), ('P30C', 58, 70)):
        if ('req_const', who) in SR:
            x = mval(SR[('req_const', who)][0], 'hs_lv10')
            out.append(f'{who} Homestead Lv10 {"在带内" if x is not None and lo <= x <= hi else "出带"}（{fmt(x, 1)}，带 {lo}–{hi}）')
    return '委托按 sim_v3 常数时 ' + '、'.join(out) + '。'


def conclusion(P, R, L, R40, checks, checks40, SR, N, spread, NR, NM):
    """末节：判定汇总、贴边项、敏感性最大的假设（数字全部取自本次运行）。knobs_p1.py 把第 7 节插在本节之前。"""
    P('## 8. 结论')
    P()
    ok = [n for n, k, _ in checks if k and not n.startswith('（附）')]
    bad = [n for n, k, _ in checks if not k]
    P(f'**基线（Lv7 起 48 格）：§17.3.2 节奏 / 账本 {len(ok) + len(bad)} 项里 {len(ok)} 项通过' + (f'，不过：{"、".join(bad)}' if bad else '，全部通过') + '。**'
      + ('现数据 40 格不过的：' + '、'.join(n for n, k, _ in checks40 if not k) + '。' if any(not k for _, k, _ in checks40) else ''))
    P()
    edge = []

    def day(R_, k):
        return mval(R_, k)
    items = [('P30 Cooking Lv10（≤ 26）', day(R['P30'], 'cooking_lv10'), 26, 'hi'), ('P30 Farming Lv10（≤ 26）', day(R['P30'], 'farming_lv10'), 26, 'hi'),
             ('P30 Fishing Lv10（≤ 26）', day(R['P30'], 'fishing_lv10'), 26, 'hi'), ('重度 Homestead Lv10（≤ 35）', day(R['HEAVY'], 'hs_lv10'), 35, 'hi'),
             ('重度 Homestead Lv10（≥ 30）', day(R['HEAVY'], 'hs_lv10'), 30, 'lo'), ('P30C Homestead Lv10（≥ 60，58 可接受）', day(R['P30C'], 'hs_lv10'), 60, 'lo'),
             ('5 分钟 Fishing Lv10（≤ 90）', day(R['P5'], 'fishing_lv10'), 90, 'hi')]
    for name, v, lim, side in items:
        if v is None:
            continue
        m = (lim - v) if side == 'hi' else (v - lim)
        if m <= 3:
            edge.append(f'{name} 第 {v:.1f} 天（余量 {m:+.1f} 天）')
    for k in ('P5', 'P30', 'HEAVY'):
        mid = L[k]['mid']
        if min(mid - 0.6, 0.8 - mid) <= 0.04:
            edge.append(f'{k} 中界 {mid:.0%}（带 60–80%）')
    c = R['P30C']
    P('**贴边（离判定线 ≤ 3 天或 ≤ 4 个百分点）：** ' + ('；'.join(edge) if edge else '无') + '。P30 Cooking Lv10 一直落在 26 天上下，'
      '第 7 节里不碰做菜的旋钮也让它在这附近来回，属随机种子的差；'
      f'P30C（25 竿）两轨 {mday(c, "fishing_lv10", 1)} / {mday(c, "farming_lv10", 1)} 天、Cooking Lv10 {mday(c, "cooking_lv10", 1)} 天，按约定只作参考，但都在 21 ± 5 带外。')
    P()
    req = {k: win(R[k], 7, 30, 'income_requests') for k in ('P30', 'P30C', 'HEAVY')}
    lines = []
    for who in ('P30', 'P30C', 'HEAVY'):
        if ('req_const', who) not in SR:
            continue
        r0, l0 = SR[('main', who)]; r1, l1 = SR[('req_const', who)]
        lines.append(f'{who} Homestead Lv10 {mday(r0, "hs_lv10", 1)} → {mday(r1, "hs_lv10", 1)}、Farming Lv10 {mday(r0, "farming_lv10", 1)} → {mday(r1, "farming_lv10", 1)}、中界 {l0["mid"]:.0%} → {l1["mid"]:.0%}')
    others = []
    for key, label in (('req_full', '委托接满板'), (('barter',), '换料按数据现状'), (('v2sell',), 'V2 卖法'), (('gift_meal_day',), '赠餐第 5 天'), ('lure5', '亮片只买画像量')):
        if (key, 'HEAVY') in SR:
            hs = [mval(SR[(key, w)][0], 'hs_lv10') for w in ('P30C', 'HEAVY')]
            base = [mval(R[w], 'hs_lv10') for w in ('P30C', 'HEAVY')]
            if all(x is not None for x in hs + base):
                others.append(f'{label} {hs[0] - base[0]:+.1f} / {hs[1] - base[1]:+.1f}')
    P('**记账改按 §9.15.1（蚯蚓 A、亮片 C）之后的中界：** ' + '；'.join(
        f'{k} {L[k]["mid"]:.0%}（旧口径亮片算 A 时 {L[k]["mid_lureA"]:.0%}；亮片占 28 日收入 {L[k]["sinks"]["lure"] / L[k]["inc"]:.0%}）' for k in ('P5', 'P30', 'P30C', 'HEAVY')) +
      '。30 分钟玩家回到带内，但 5 分钟与重度玩家买亮片的份额也一起挪出去了，' +
      '、'.join(f'{k} {"落到 60% 以下" if L[k]["mid"] < 0.6 else "贴着 60% 下沿" if L[k]["mid"] < 0.64 else "仍在带内"}' for k in ('P5', 'HEAVY')) + '。')
    P()
    P(f'**敏感性最大的假设是委托收入。** 本模型从委托模板估算，第 8–30 天 P30 约 {req["P30"]:.0f}、P30C 约 {req["P30C"]:.0f}、重度约 {req["HEAVY"]:.0f} 金币 / 日；'
      f'sim_v3（方案 §9.14.2）用的是 15 / 15 / 32。换成 sim_v3 常数：' + '；'.join(lines) + '。'
      + _req_verdict(SR) +
      '所以 Homestead 两条判定取决于真实委托收入落在哪一端，P1 上线后委托的完成量与完成奖是第一个要看的数。'
      f'其余单项假设对 Homestead Lv10 的影响（P30C / 重度，天，相对基线）：' + '；'.join(others) + '。')
    P()
    sp = '；'.join(f'{k} {v:.1%}' for k, v in spread.items())
    fair = all(v <= 0.10 for v in spread.values()) and spread
    P(f'**"公平"一行：** 到 Homestead Lv10 的天数四个气候带之间相差 {sp}（目标 ≤ 10%）——{"通过" if fair else "不过"}。')
    P()
    P(nomine_summary(NR, NM))
    P()


def write(P, path, t0):
    P(f'_生成：sim_p1.py，用时 {time.time() - t0:.0f} 秒。_')
    with open(path, 'w') as fh:
        fh.write('\n'.join(P.lines) + '\n')


if __name__ == '__main__':
    main()
