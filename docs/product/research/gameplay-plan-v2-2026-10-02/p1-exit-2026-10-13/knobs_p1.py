#!/usr/bin/env python3
"""
knobs_p1.py — P1 出口的旋钮对照（2026-10-13，李白要求；接 sim_p1.py，不改它）

以「Lv7 起 48 格」为新基线，跑 (a)–(e) 五个变体与「委托按 sim_v3 常数」下的 (a) / (e)，
结果作为「7. 旋钮对照（10-13 李白要求）」追加到 out_p1.md 末尾（已有第 7 节则替换）。
判定口径（sim_v3 约定）：30 分钟两轨与 Cooking 21 ± 5 看 P30（34 竿），P30C 只作参考；Homestead 看 HEAVY 与 P30C；
中界看 P5 / P30 / HEAVY（P30C 参考）。记账同 sim_p1（§9.15.1：蚯蚓 A、亮片 C）；另列一列旧口径（亮片算 A）作对照。

用法：python3 -B knobs_p1.py [--seeds 12]
重跑 sim_p1.py 会覆盖 out_p1.md，之后再跑一次本脚本：第 7 节插在「## 8. 结论」之前（已有第 7 节则替换）。
"""
import argparse
import os
import statistics
import sys
import time
from collections import Counter

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import sim_p1 as M  # noqa: E402

L40 = [(1, 30), (3, 40)]
L7 = [(1, 30), (3, 40), (7, 48)]
ARCHS = ('P30', 'P30C', 'HEAVY', 'P5')
REQ_CONST = {'P5': 4, 'P30': 15, 'P30C': 15, 'HEAVY': 32}     # sim_v3 画像常数
A_SINKS = M.SINK_A          # 蚯蚓（bait）在 A
B_SINKS = M.SINK_B
C_SINKS = M.SINK_C          # 亮片（lure）在 C（§9.15.1）


def cfg_for(ladder=L7, rowhoe=None, hs_cut=None, trap=None):
    c = M.p1_config(plot_ladder=ladder)
    if rowhoe is not None:
        c['row_hoe']['price'] = rowhoe
    if trap is not None:
        c['trap']['price'] = trap
    if hs_cut:
        for n in range(7, 11):
            new = round(c['hs_levels'][n]['coins'] * (1 - hs_cut))
            c['hs_levels'][n]['coins'] = new
            c['homestead'][n - 2] = (new,) + tuple(c['homestead'][n - 2][1:])
    return c


VARIANTS = [
    ('(0) 现数据 40 格（对照）', dict(ladder=L40), False),
    ('(a) Lv7 起 +8 格（新基线）', dict(), False),
    ('(b) a + Row Hoe 240 → 180', dict(rowhoe=180), False),
    ('(c) a + Homestead Lv7–10 金币 −10%（1,305 / 1,620 / 2,025 / 2,565）', dict(hs_cut=0.10), False),
    ('(d) a + 鱼笼 120 → 100', dict(trap=100), False),
    ('(e) a + b + c + d', dict(rowhoe=180, hs_cut=0.10, trap=100), False),
    ('(a′) a，委托按 sim_v3 常数（4 / 15 / 15 / 32）', dict(), True),
    ('(e′) e，委托按 sim_v3 常数（4 / 15 / 15 / 32）', dict(rowhoe=180, hs_cut=0.10, trap=100), True),
]


def ledger(R, cfg):
    incs, sinks = [], Counter()
    for _, o in R['runs']:
        incs.append(cfg['initial_wallet'] + sum((o[d].get('income', 0) or 0) - (o[d].get('seed_cost', 0) or 0) for d in range(28)))
        for d in range(28):
            for k in A_SINKS + B_SINKS + C_SINKS:
                sinks[k] += (o[d].get('sink_' + k, 0) or 0) / len(R['runs'])
    inc = statistics.mean(incs)
    A = sum(sinks[k] for k in A_SINKS); B = sum(sinks[k] for k in B_SINKS); C = sum(sinks[k] for k in C_SINKS)
    return dict(inc=inc, low=A / inc, mid=(A + B) / inc, high=(A + B + C) / inc, mid_lureA=(A + B + sinks['lure']) / inc, sinks=sinks)


def v(R, k):
    return R['ms'].get(k) if R['reach'].get(k, 0) >= 0.999 else None


def run_variant(kw, req_const, seeds, days):
    cfg = cfg_for(**kw)
    out = {}
    for k in ARCHS:
        a = M.variant(k, req_per_day=0, requests=REQ_CONST[k]) if req_const else M.ARCH[k]
        R = M.summarize(k, a, cfg, seeds, days)
        out[k] = dict(R=R, L=ledger(R, cfg))
    out['_walls'] = M.walls(out['HEAVY']['R'])
    return out


def judge(o):
    P30, P30C, H, P5 = (o[k]['R'] for k in ARCHS)
    band = lambda x, lo, hi: x is not None and lo <= x <= hi  # noqa: E731
    W = o['_walls']
    res = [
        ('P30 两轨 21±5', all(band(v(P30, k), 16, 26) for k in ('fishing_lv10', 'farming_lv10'))),
        ('重度两轨 ≥8', all((v(H, k) or 0) >= 8 for k in ('fishing_lv10', 'farming_lv10'))),
        ('P5 两轨 ≤90', all(v(P5, k) is not None and v(P5, k) <= 90 for k in ('fishing_lv10', 'farming_lv10'))),
        ('P30 Co10 21±5', band(v(P30, 'cooking_lv10'), 16, 26)),
        ('P30 Co4 ≤7', (v(P30, 'cooking_lv4') or 99) <= 7),
        ('重度 Co10 ≥8', (v(H, 'cooking_lv10') or 0) >= 8),
        ('重度 Hs10 30–35', band(v(H, 'hs_lv10'), 30, 35)),
        ('P30C Hs10 60–70（58–59 可接受）', band(v(P30C, 'hs_lv10'), 58, 70)),
        ('中界 P5', 0.6 <= o['P5']['L']['mid'] <= 0.8),
        ('中界 P30', 0.6 <= o['P30']['L']['mid'] <= 0.8),
        ('中界 HEAVY', 0.6 <= o['HEAVY']['L']['mid'] <= 0.8),
        ('重度撞墙 ≤1', W['mean'] <= 1 and W['peak'] <= 1),
    ]
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--seeds', type=int, default=12)
    ap.add_argument('--days', type=int, default=120)
    ap.add_argument('--md', default=os.path.join(HERE, 'out_p1.md'))
    args = ap.parse_args()
    t0 = time.time()
    res = {}
    for name, kw, rc in VARIANTS:
        res[name] = run_variant(kw, rc, args.seeds, args.days)
        print('done', name, f'{time.time() - t0:.0f}s', flush=True)
    lines = []
    P = lines.append
    P('## 7. 旋钮对照（10-13 李白要求）')
    P('')
    P(f'`knobs_p1.py`（import sim_p1，不改它），120 天 × {args.seeds} seed。判定口径按 sim_v3 约定：30 分钟两轨与 Cooking 21 ± 5 看 **P30**（34 竿），P30C 只作参考；'
      'Homestead 看 **HEAVY** 与 **P30C**；中界看 P5 / P30 / HEAVY（P30C 参考）。新基线 = Lv7 起 48 格。'
      '记账同第 1 节（§9.15.1：蚯蚓 A、亮片 C）；"中界（亮片算 A）"是 sim_v3 的旧口径，只作对照。(0) 与 (a) 和第 1 节两列是同一组种子，数字相同。')
    P('')
    P('### 7.1 判定汇总')
    P('')
    names = [n for n, _, _ in VARIANTS]
    checks = [c for c, _ in judge(res[names[0]])]
    P('| 检查项 | ' + ' | '.join(n.split(' ')[0] for n in names) + ' |')
    P('|' + '---|' * (len(names) + 1))
    J = {n: dict(judge(res[n])) for n in names}
    for c in checks:
        P(f'| {c} | ' + ' | '.join('PASS' if J[n][c] else '**FAIL**' for n in names) + ' |')
    P('| 不过的项数 | ' + ' | '.join(str(sum(1 for c in checks if not J[n][c])) for n in names) + ' |')
    P('')
    P('变体：' + '；'.join(names) + '。')
    P('')
    P('### 7.2 各画像数字（第 N 天 = seed 均值；* = 未全部到达）')
    P('')
    P('| 变体 | 画像 | Fi10 | Fa10 | Co10 | Co4 | Hs7 | Hs10 | 28 日收入 | 下界 / 中界 / 上界 | 中界（亮片算 A，旧口径） | 重度日撞墙（均值 / 峰值） |')
    P('|---|---|---|---|---|---|---|---|---|---|---|---|')
    for n in names:
        o = res[n]
        for k in ARCHS:
            R, L = o[k]['R'], o[k]['L']
            ref = '（参考）' if k == 'P30C' else ''
            w = f'{o["_walls"]["mean"]:.2f} / {o["_walls"]["peak"]:.0f}' if k == 'HEAVY' else ''
            P(f'| {n.split(" ")[0]} | {k}{ref} | {M.mday(R, "fishing_lv10", 1)} | {M.mday(R, "farming_lv10", 1)} | {M.mday(R, "cooking_lv10", 1)} | '
              f'{M.mday(R, "cooking_lv4", 1)} | {M.mday(R, "hs_lv7", 1)} | {M.mday(R, "hs_lv10", 1)} | {L["inc"]:.0f} | '
              f'{L["low"]:.0%} / {L["mid"]:.0%} / {L["high"]:.0%} | {L["mid_lureA"]:.0%} | {w} |')
    P('')
    P('### 7.3 30 分钟玩家 28 天去向构成（占 28 日收入；(a) 与 (e)）')
    P('')
    cols = ('homestead', 'bait', 'lure', 'gear', 'fertilizer', 'trap', 'saplings', 'bag1', 'recipes', 'row_hoe')
    P('| 变体 | 画像 | 收入 | ' + ' | '.join(cols) + ' | A + B 合计 |')
    P('|' + '---|' * (len(cols) + 4))
    for n in (names[1], names[5]):
        for k in ('P30', 'P30C'):
            L = res[n][k]['L']
            P(f'| {n.split(" ")[0]} | {k} | {L["inc"]:.0f} | ' + ' | '.join(f'{L["sinks"][c]:.0f}（{L["sinks"][c] / L["inc"]:.0%}）' for c in cols) +
              f' | {L["mid"]:.0%} |')
    P('')
    P('（bait = 蚯蚓，算 A；lure = 亮片，算 C、不进中界。）')
    P('')
    # ---- 读法（按数字自动写）----
    a, e = res[names[1]], res[names[5]]
    mids = {n: res[n]['P30']['L']['mid'] for n in names}
    fails = {n: [c for c in checks if not J[n][c]] for n in names}
    P('### 7.4 读法')
    P('')
    inb = lambda x: 0.6 <= x <= 0.8  # noqa: E731
    P(f'- 按 §9.15.1 记账后，P30 中界 (0) {mids[names[0]]:.0%}、(a) {mids[names[1]]:.0%}、(b) {mids[names[2]]:.0%}、(c) {mids[names[3]]:.0%}、(d) {mids[names[4]]:.0%}、(e) {mids[names[5]]:.0%}'
      f'（{"都在" if all(inb(mids[n]) for n in names[:6]) else "不全在"} 60–80% 带内；旧口径亮片算 A 时 (a) {a["P30"]["L"]["mid_lureA"]:.0%}）。'
      f'同一记账下 P5 中界 (a) {a["P5"]["L"]["mid"]:.0%} / (e) {e["P5"]["L"]["mid"]:.0%}、重度 {a["HEAVY"]["L"]["mid"]:.0%} / {e["HEAVY"]["L"]["mid"]:.0%}（旧口径 {a["P5"]["L"]["mid_lureA"]:.0%}、{a["HEAVY"]["L"]["mid_lureA"]:.0%}）：'
      f'亮片占 28 日收入 P5 {a["P5"]["L"]["sinks"]["lure"] / a["P5"]["L"]["inc"]:.0%}、P30 {a["P30"]["L"]["sinks"]["lure"] / a["P30"]["L"]["inc"]:.0%}、重度 {a["HEAVY"]["L"]["sinks"]["lure"] / a["HEAVY"]["L"]["inc"]:.0%}，挪到 C 后三类一起往下走。')
    h0, ha = v(res[names[0]]["HEAVY"]["R"], "hs_lv10"), v(a["HEAVY"]["R"], "hs_lv10")
    P(f'- (a) 让重度 Homestead Lv10 {h0:.1f} → {ha:.1f}（{"在 30–35 带内" if 30 <= ha <= 35 else "仍在带外"}）。'
      f'各变体不过的项：' + '；'.join(f'{n.split(" ")[0]} ' + ('、'.join(fails[n]) if fails[n] else '无') for n in names) + '。')
    co = [v(res[n]['P30']['R'], 'cooking_lv10') for n in names[:6]]
    P(f'- P30 的 Cooking Lv10 在 (0)–(e) 里是第 {min(co):.1f}–{max(co):.1f} 天，压在 26 天的带边上；这几个旋钮都不碰做菜，PASS / FAIL 来回翻是随机种子的差。'
      f'(c) 让 P30C 的 Homestead Lv10 到 {v(res[names[3]]["P30C"]["R"], "hs_lv10"):.1f}（58 以下会出带），(e) {v(res[names[5]]["P30C"]["R"], "hs_lv10"):.1f}。')
    P(f'- (b)–(d) 是"中界太高"方向的旋钮（降价），在新记账下对 30 分钟玩家已不需要，对掉到 60% 附近的 5 分钟 / 重度玩家方向相反。委托按 sim_v3 常数时（(a′) / (e′)）重度 Homestead Lv10 {v(res[names[6]]["HEAVY"]["R"], "hs_lv10"):.1f} / {v(res[names[7]]["HEAVY"]["R"], "hs_lv10"):.1f}，'
      f'P30C {v(res[names[6]]["P30C"]["R"], "hs_lv10"):.1f} / {v(res[names[7]]["P30C"]["R"], "hs_lv10"):.1f}——Homestead 的判定对委托收入比对这些价格敏感得多。')
    P('')
    with open(args.md) as fh:
        text = fh.read()
    block = '\n'.join(lines) + f'\n_第 7 节生成：knobs_p1.py，用时 {time.time() - t0:.0f} 秒。_\n\n'
    a7 = text.find('## 7. 旋钮对照')
    a8 = text.find('## 8. 结论')
    if a7 >= 0:                                  # 替换旧的第 7 节
        end7 = a8 if a8 > a7 else len(text)
        text = text[:a7] + block + text[end7:]
    elif a8 >= 0:                                # 插在结论之前
        text = text[:a8] + block + text[a8:]
    else:
        text = text.rstrip() + '\n\n' + block
    with open(args.md, 'w') as fh:
        fh.write(text)
    print('\n'.join(lines))


if __name__ == '__main__':
    main()
