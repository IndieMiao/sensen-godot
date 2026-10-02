#!/usr/bin/env python3
"""
Gensen v2 — 技能节奏模型（内部工具，不是产品数据）。
目的：在 v2 体力尺度（池 200 / +1 per 4 min / 抛竿 5 / 播种 2-3-4-6）与
"等级差"XP 规则下，按三类玩家的日燃料反推两条技能轨的 10 级阈值，
并输出到达天数 / 首会话竿数。

用法：python3 pacing_v2.py [--seeds N]
"""
import random
import statistics
import sys
from dataclasses import dataclass, field

SEEDS = 40
for i, a in enumerate(sys.argv):
    if a == "--seeds":
        SEEDS = int(sys.argv[i + 1])

# ---------------------------------------------------------------- 规则常量
CAST_COST = 5          # 抛竿预扣
FAIL_REFUND = 3        # 逃走 / 挣脱退回 → 净 2
FREE_FAILS_LV = 3      # Fishing Lv1–3 每日前 10 次失败全退
FREE_FAILS_N = 10

XP_FISH = {"Common": 5, "Fine": 10, "Rare": 20, "Legendary": 40}
FIRST_FISH = {"Common": 15, "Fine": 30, "Rare": 60, "Legendary": 120}
FIRST_CAST, FIRST_HOOK, FIRST_CITY = 5, 5, 10

XP_CROP_BY_TIER = {1: 2, 2: 3, 3: 4, 4: 6}        # = 播种体力
FIRST_CROP_BY_TIER = {1: 10, 2: 15, 3: 20, 4: 30}
PERENNIAL_XP = 2
PERENNIAL_FIRST = 15
REGIONAL_SOW = 4

def level_diff_mult(player_lv, content_lv, rng):
    d = player_lv - content_lv
    if d <= 1:
        return 1.0
    if d == 2:
        return 0.75
    if d == 3:
        return 0.5
    if d == 4:
        return 0.25
    return 0.0  # 灰色：5% 概率 1 XP，另行处理

def apply_mult(base, mult, rng):
    if mult == 0.0:
        return 1 if rng.random() < 0.05 else 0
    v = base * mult
    lo = int(v)
    return lo + (1 if rng.random() < (v - lo) else 0)

# ---------------------------------------------------------------- 阈值（待调）
FISHING_THRESHOLDS = [0, 70, 220, 480, 850, 1300, 1850, 2500, 3300, 4300]
FARMING_THRESHOLDS = [0, 50, 150, 300, 500, 750, 1050, 1450, 2050, 2800]

def level_of(xp, th):
    lv = 1
    for i, t in enumerate(th):
        if xp >= t:
            lv = i + 1
    return lv

# ---------------------------------------------------------------- 鱼表（20 种）
RARITY_IDX = {"Common": 0, "Fine": 1, "Rare": 2, "Legendary": 3}
@dataclass
class Fish:
    fid: str
    rarity: str
    level: int
    sites: tuple
    regional: bool = False

FISH = [
    Fish("crucian", "Common", 1, ("pond", "river")),
    Fish("carp", "Common", 1, ("pond", "river")),
    Fish("mullet", "Common", 1, ("coast", "river")),
    Fish("perch", "Fine", 2, ("river", "pond")),
    Fish("bass", "Fine", 2, ("pond", "river")),
    Fish("trout", "Fine", 2, ("river",)),
    Fish("mackerel", "Fine", 2, ("coast",)),
    Fish("koi", "Rare", 4, ("pond",)),
    Fish("catfish", "Rare", 4, ("river", "pond")),
    Fish("seabass", "Rare", 5, ("coast",)),
    Fish("sturgeon", "Legendary", 7, ("pond", "river", "coast")),
    Fish("eel", "Legendary", 9, ("river", "pond")),
    # 地区鱼池（本城只抽到 2 种）
    Fish("tilapia", "Common", 1, ("pond", "river"), True),
    Fish("smelt", "Common", 1, ("coast", "river"), True),
    Fish("grass_carp", "Fine", 3, ("pond", "river"), True),
    Fish("arctic_char", "Fine", 3, ("pond", "river"), True),
    Fish("snakehead", "Rare", 5, ("pond", "river"), True),
    Fish("pike", "Rare", 5, ("pond", "river"), True),
    Fish("barramundi", "Rare", 6, ("coast", "river"), True),
    Fish("salmon", "Legendary", 8, ("river", "coast"), True),
]
HOME_REGIONAL = {"grass_carp", "snakehead"}   # 上海（亚热带）工作假设

SITE_WEIGHTS = {"pond": [60, 30, 9, 1], "river": [35, 40, 20, 5], "coast": [30, 35, 25, 10]}
BAIT_MOD = {None: [0, 0, 0, 0], "worm": [-10, 10, 0, 0], "lure": [-15, -5, 15, 5]}
RODS = {
    "starter": {"max": 1, "p": [0.90, 0.80, 0.0, 0.0]},
    "reed":    {"max": 2, "p": [0.90, 0.80, 0.72, 0.0]},
    "carbon":  {"max": 3, "p": [0.90, 0.82, 0.78, 0.62]},
}

def pool_for(site, rarity):
    out = []
    for f in FISH:
        if f.rarity != rarity or site not in f.sites:
            continue
        if f.regional and f.fid not in HOME_REGIONAL:
            continue
        out.append(f)
    return out

# ---------------------------------------------------------------- 作物表
@dataclass
class Crop:
    cid: str
    level: int
    tier: int
    hours: float
    perennial: bool = False
    regional: bool = False

CROPS = [
    Crop("radish", 1, 1, 4), Crop("lettuce", 1, 1, 8),
    Crop("herb", 2, 1, 3), Crop("carrot", 2, 2, 12),
    Crop("potato", 3, 2, 10), Crop("chamomile", 3, 3, 18),
    Crop("chili", 4, 1, 6), Crop("tomato", 4, 3, 14),
    Crop("cabbage", 5, 2, 12), Crop("corn", 5, 3, 16), Crop("sweet_potato", 5, 3, 16, regional=True),
    Crop("cucumber", 6, 2, 9),
    Crop("apple", 7, 0, 48, perennial=True),
    Crop("strawberry", 8, 4, 20),
    Crop("melon", 9, 4, 24), Crop("citrus", 9, 0, 72, perennial=True), Crop("grape", 9, 0, 60, perennial=True),
]
TILLED_CAP = 200

# ---------------------------------------------------------------- 玩家画像
@dataclass
class Profile:
    name: str
    fish_energy: float      # 日钓鱼体力
    max_casts: int          # 在线时间上限
    farm_energy: float      # 日播种体力
    cycles_short: int       # ≤8h 作物一日几轮（会话数决定）
    same_day_harvest: bool  # ≤8h 作物当天能收（两次会话）
    uses_worm: bool = True
    uses_lure: bool = True
    carbon_at: int = 6
    lure_at: int = 5
    blessing_mult: float = 1.08   # 前 7 天 Newcomer Blessing 的燃料增益

PROFILES = [
    Profile("P5a 5分钟·10竿+20格",      50, 10,  50, 1, False, carbon_at=7, lure_at=7, blessing_mult=1.10),
    Profile("P30a 30分钟·34竿+130体力",  150, 40, 130, 1, False, blessing_mult=1.08),
    Profile("HB  重度均衡·77竿+240体力", 340, 110, 240, 2, True, blessing_mult=1.14),
    Profile("HF-fish 重度全钓(上界)",    640, 170, 0, 2, True, blessing_mult=1.14),
    Profile("HF-farm 重度全种(上界)",    0, 0, 640, 2, True, blessing_mult=1.14),
    Profile("P30-fish 30分钟全钓",      280, 40, 0, 1, False, blessing_mult=1.08),
    Profile("P5b 5分钟·5竿+30格(体力章)", 25, 5,  70, 1, False, carbon_at=7, lure_at=7, blessing_mult=1.10),
    Profile("P30b 30分钟·15竿+40格+矿(体力章)", 66, 15, 100, 1, False, blessing_mult=1.08),
    Profile("P30c 30分钟·25竿+110体力",  110, 25, 110, 1, False, blessing_mult=1.08),
]

# ---------------------------------------------------------------- 钓鱼模拟
def site_for(lv):
    if lv >= 6:
        return "coast"
    if lv >= 4:
        return "river"
    return "pond"

def rod_for(lv, carbon_at):
    if lv >= carbon_at:
        return "carbon"
    if lv >= 3:
        return "reed"
    return "starter"

def bait_for(lv, prof):
    if lv >= prof.lure_at and prof.uses_lure:
        return "lure"
    if lv >= 2 and prof.uses_worm:
        return "worm"
    return None

@dataclass
class FishState:
    xp: int = 0
    caught: set = field(default_factory=set)
    first_cast: bool = False
    first_hook: bool = False
    first_city: bool = False

def one_cast(st, rng, prof, free_fails_left):
    """返回 (xp_gain, energy_cost, free_used, success)"""
    lv = level_of(st.xp, FISHING_THRESHOLDS)
    site = site_for(lv)
    rod = RODS[rod_for(lv, prof.carbon_at)]
    bait = bait_for(lv, prof)
    w = [max(0, a + b) for a, b in zip(SITE_WEIGHTS[site], BAIT_MOD[bait])]
    r = rng.choices(["Common", "Fine", "Rare", "Legendary"], weights=w)[0]
    pool = pool_for(site, r)
    if not pool:
        # 极端：该档无候选 → 落下一档
        r = ["Common", "Fine", "Rare", "Legendary"][max(0, RARITY_IDX[r] - 1)]
        pool = pool_for(site, r)
    pw = [(4 if bait == "lure" else 2) if f.regional else 1 for f in pool]
    fish = rng.choices(pool, weights=pw)[0]
    gain = 0
    if not st.first_cast:
        st.first_cast = True
        gain += FIRST_CAST
    free_ok = lv <= FREE_FAILS_LV and free_fails_left > 0
    fail_cost = 0 if free_ok else (CAST_COST - FAIL_REFUND)
    # 等级 → 鱼竿 → 小游戏
    if fish.level > lv or RARITY_IDX[r] > rod["max"]:
        return gain, fail_cost, free_ok, False
    if rng.random() > rod["p"][RARITY_IDX[r]]:
        return gain, fail_cost, free_ok, False
    # 成功
    if not st.first_hook:
        st.first_hook = True
        gain += FIRST_HOOK
    if not st.first_city:
        st.first_city = True
        gain += FIRST_CITY
    if fish.fid not in st.caught:
        st.caught.add(fish.fid)
        gain += FIRST_FISH[r]
    mult = level_diff_mult(lv, fish.level, rng)
    gain += apply_mult(XP_FISH[r], mult, rng)
    return gain, CAST_COST, False, True

def sim_fishing(prof, rng, days=120):
    st = FishState()
    reach = {}
    for day in range(1, days + 1):
        budget = prof.fish_energy * (prof.blessing_mult if day <= 7 else 1.0)
        casts = 0
        free_left = FREE_FAILS_N
        while budget >= CAST_COST and casts < prof.max_casts:
            g, cost, free_used, ok = one_cast(st, rng, prof, free_left)
            if free_used:
                free_left -= 1
            budget -= cost
            casts += 1
            st.xp += g
            lv = level_of(st.xp, FISHING_THRESHOLDS)
            for L in range(2, 11):
                if lv >= L and L not in reach:
                    reach[L] = day
        if level_of(st.xp, FISHING_THRESHOLDS) >= 10:
            break
    return reach, st.xp

def first_session(rng, casts_max=24, energy=200):
    """首会话：池 200，全部在家门口 Pond，新手竿无饵；返回到 Lv2 / Lv3 的竿数（0 = 未到）。"""
    st = FishState()
    prof = PROFILES[1]
    free_left = FREE_FAILS_N
    budget = energy
    c2 = c3 = 0
    casts = 0
    while budget >= CAST_COST and casts < casts_max:
        # 首会话强制：前 3 次咬钩全部 Common 全球鱼（导演表），这里用 Lv1 规则自然即可
        g, cost, free_used, ok = one_cast(st, rng, prof, free_left)
        if free_used:
            free_left -= 1
        budget -= cost
        casts += 1
        st.xp += g
        lv = level_of(st.xp, FISHING_THRESHOLDS)
        if lv >= 2 and c2 == 0:
            c2 = casts
        if lv >= 3 and c3 == 0:
            c3 = casts
    return c2, c3, st.xp, casts

# ---------------------------------------------------------------- 种植模拟
def sim_farming(prof, rng, days=120):
    xp = 0
    reach = {}
    pending = []  # (day_ready, xp)
    first_done = set()
    perennial_planted = set()
    for day in range(1, days + 1):
        # 到账
        for d, g in [p for p in pending if p[0] <= day]:
            xp += g
        pending = [p for p in pending if p[0] > day]
        lv = level_of(xp, FARMING_THRESHOLDS)
        for L in range(2, 11):
            if lv >= L and L not in reach:
                reach[L] = day
        if lv >= 10:
            break
        energy = prof.farm_energy * (prof.blessing_mult if day <= 7 else 1.0)
        if day == 1:
            energy = min(energy, 60)   # 首会话脚本只播约 30 格
        if energy <= 0:
            continue
        # 新解锁作物：各种 1 格拿首收（含多年生，多年生占槽位不占日体力太多）
        for c in CROPS:
            if c.level <= lv and c.cid not in first_done:
                first_done.add(c.cid)
                if c.perennial:
                    sow = PERENNIAL_XP
                    ready = day + (2 if prof.same_day_harvest else 2) + int(c.hours // 24)
                    pending.append((ready, PERENNIAL_FIRST + apply_mult(PERENNIAL_XP, level_diff_mult(lv, c.level, rng), rng)))
                else:
                    sow = REGIONAL_SOW if c.regional else XP_CROP_BY_TIER[c.tier]
                    ready = day if (prof.same_day_harvest and c.hours <= 8) else day + 1
                    pending.append((ready, FIRST_CROP_BY_TIER[c.tier] + apply_mult(sow, level_diff_mult(lv, c.level, rng), rng)))
                energy -= sow
        # 多年生每日收获（槽位 1 + Homestead，这里按 min(可用种类, 4) 株，每株每 2 天 2 XP，受等级差）
        for c in CROPS:
            if c.perennial and c.level <= lv:
                if day % 2 == 0:
                    pending.append((day, apply_mult(PERENNIAL_XP, level_diff_mult(lv, c.level, rng), rng)))
                    energy -= PERENNIAL_XP
        # 主力：d ≤ 1 的非多年生作物里，选占格效率最高（档位最高）的
        cands = [c for c in CROPS if not c.perennial and c.level <= lv and lv - c.level <= 1]
        if not cands:
            cands = [c for c in CROPS if not c.perennial and c.level <= lv]
        cands.sort(key=lambda c: (-(REGIONAL_SOW if c.regional else XP_CROP_BY_TIER[c.tier]), c.hours))
        plots_left = TILLED_CAP * prof.cycles_short
        for c in cands:
            if energy <= 0 or plots_left <= 0:
                break
            per = REGIONAL_SOW if c.regional else XP_CROP_BY_TIER[c.tier]
            cycles = prof.cycles_short if c.hours <= 8 else 1
            cap_plots = min(plots_left, TILLED_CAP * cycles)
            n = min(int(energy // per), cap_plots)
            if n <= 0:
                continue
            mult = level_diff_mult(lv, c.level, rng)
            g = sum(apply_mult(per, mult, rng) for _ in range(n)) if mult < 1.0 else n * per
            ready = day if (prof.same_day_harvest and c.hours <= 8) else day + 1
            pending.append((ready, g))
            energy -= n * per
            plots_left -= n
    return reach, xp

# ---------------------------------------------------------------- 报告
def fmt_reach(reach):
    return " ".join(f"{reach.get(L, '—'):>3}" for L in range(2, 11))

def main():
    print("Fishing thresholds:", FISHING_THRESHOLDS)
    print("Farming thresholds:", FARMING_THRESHOLDS)
    print()
    print("== 首会话（Pond，池 200，≤24 竿）==")
    c2s, c3s, xps = [], [], []
    for s in range(SEEDS * 5):
        rng = random.Random(1000 + s)
        c2, c3, xp, casts = first_session(rng)
        c2s.append(c2 if c2 else 99)
        c3s.append(c3 if c3 else 99)
        xps.append(xp)
    c2s.sort(); c3s.sort()
    n = len(c2s)
    print(f"  到 Lv2 竿数：中位 {c2s[n//2]}，P90 {c2s[int(n*0.9)]}，P(≤12 竿) = {sum(1 for c in c2s if c <= 12)/n:.1%}")
    print(f"  到 Lv3 竿数：中位 {c3s[n//2]}，P(24 竿内) = {sum(1 for c in c3s if c <= 24)/n:.1%}")
    print(f"  24 竿末 XP 中位 {statistics.median(xps):.0f}")
    print()
    print("== Fishing 到达天数（均值，列 Lv2…Lv10）==")
    for prof in PROFILES:
        if prof.fish_energy <= 0:
            continue
        rows = []
        for s in range(SEEDS):
            rng = random.Random(s)
            reach, xp = sim_fishing(prof, rng)
            rows.append(reach)
        avg = {L: statistics.mean(r.get(L, 200) for r in rows) for L in range(2, 11)}
        mn = {L: min(r.get(L, 200) for r in rows) for L in range(2, 11)}
        print(f"  {prof.name:<26} " + " ".join(f"{avg[L]:5.1f}" for L in range(2, 11)) + f"   (Lv10 最快 {mn[10]})")
    print()
    print("== Farming 到达天数（均值）==")
    for prof in PROFILES:
        if prof.farm_energy <= 0:
            continue
        rows = []
        for s in range(SEEDS):
            rng = random.Random(s)
            reach, xp = sim_farming(prof, rng)
            rows.append(reach)
        avg = {L: statistics.mean(r.get(L, 200) for r in rows) for L in range(2, 11)}
        print(f"  {prof.name:<26} " + " ".join(f"{avg[L]:5.1f}" for L in range(2, 11)))
    print()
    # 每日 XP 诊断：P30 在各等级的 XP/竿
    print("== 诊断：P30 不同等级下的 XP/竿（1,000 竿均值，含失败）==")
    prof = PROFILES[1]
    for lv in range(1, 11):
        tot = 0; casts = 2000
        rng = random.Random(77 + lv)
        for _ in range(casts):
            st = FishState(xp=FISHING_THRESHOLDS[lv-1], caught=set(f.fid for f in FISH), first_cast=True, first_hook=True, first_city=True)
            g, cost, _, ok = one_cast(st, rng, prof, 0)
            tot += g
        print(f"  Lv{lv:<2} site={site_for(lv):<5} rod={rod_for(lv, prof.carbon_at):<7} bait={str(bait_for(lv, prof)):<5} XP/竿 ≈ {tot/casts:.2f}")

if __name__ == "__main__":
    main()


# ---------------------------------------------------------------- 附加诊断
def diag_grid():
    """各等级 × 渔场 的 XP/竿（P30 装备策略：Lv3 芦苇、Lv6 碳素、Lv2 蚯蚓、Lv5 亮片）"""
    prof = PROFILES[1]
    global site_for
    keep = site_for
    print("\n== 诊断：XP/竿 网格（行 = Fishing Lv，列 = Pond / River / Coast；P30 装备）==")
    for lv in range(1, 11):
        row = []
        for site in ("pond", "river", "coast"):
            site_for = (lambda s: (lambda _lv: s))(site)
            rng = random.Random(500 + lv)
            tot = 0; n = 3000
            for _ in range(n):
                st = FishState(xp=FISHING_THRESHOLDS[lv-1], caught=set(f.fid for f in FISH), first_cast=True, first_hook=True, first_city=True)
                g, cost, _, ok = one_cast(st, rng, prof, 0)
                tot += g
            row.append(tot / n)
        print(f"  Lv{lv:<2}  " + "  ".join(f"{v:5.2f}" for v in row))
    site_for = keep

def diag_max_day():
    """重度全押的单日最大 XP（防脚本上限的参照）"""
    print("\n== 诊断：单日最大 XP（含首次类，60 seed）==")
    for prof in (PROFILES[3], PROFILES[2]):
        best = 0
        for s in range(60):
            rng = random.Random(900 + s)
            st = FishState()
            for day in range(1, 40):
                budget = prof.fish_energy * (prof.blessing_mult if day <= 7 else 1.0)
                casts = 0; free_left = FREE_FAILS_N; day_xp = 0
                while budget >= CAST_COST and casts < prof.max_casts:
                    g, cost, fu, ok = one_cast(st, rng, prof, free_left)
                    if fu: free_left -= 1
                    budget -= cost; casts += 1; st.xp += g; day_xp += g
                best = max(best, day_xp)
                if level_of(st.xp, FISHING_THRESHOLDS) >= 10: break
        print(f"  {prof.name:<26} Fishing 单日最大 ≈ {best}")
    # 种植：全押 = 体力 + 首收；按 HF-farm 日 640 体力 + 首收 ≤ 345
    print(f"  HF-farm 重度全种(上界)        Farming 单日最大 ≈ {640*1.14:.0f} + 首收 ≤ 100 → 约 830")

if __name__ == "__main__":
    diag_grid()
    diag_max_day()
