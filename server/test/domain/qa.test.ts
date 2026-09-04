/** 导演模式时钟：分段线性变换、跳日、天气覆写，以及「有效时间永不倒退」。 */
import { describe, expect, it } from 'vitest';
import { DAY_MS, MAX_SCALE, effectiveNow, initialQa, normalizeQa, reanchor } from '../../src/domain/qa.js';
import { derive } from '../../src/domain/derive.js';
import { at, blueprint, content, freshFarm, run, SH, T0 } from './helpers.js';

describe('QA 时钟', () => {
  it('正式农场是恒等变换', () => {
    expect(effectiveNow(initialQa(T0), T0 + 5000)).toBe(T0 + 5000);
    expect(effectiveNow(undefined, T0)).toBe(T0);
  });

  it('倍率只拉伸锚定之后的时间，不追溯拉伸历史', () => {
    // 先真实走 10 秒，再调到 60 倍，再真实走 10 秒 → 应是 10 + 600 秒，不是 600 + 600。
    const q = reanchor(initialQa(T0), T0 + 10_000, 60);
    expect(effectiveNow(q, T0 + 10_000)).toBe(T0 + 10_000);
    expect(effectiveNow(q, T0 + 20_000)).toBe(T0 + 10_000 + 600_000);
  });

  it('倍率调回 1 后有效时间不倒退', () => {
    const fast = reanchor(initialQa(T0), T0, 60);
    const atFast = effectiveNow(fast, T0 + 10_000);
    const back = reanchor(fast, T0 + 10_000, 1);
    expect(effectiveNow(back, T0 + 10_000)).toBe(atFast);
    expect(effectiveNow(back, T0 + 11_000)).toBe(atFast + 1_000);
  });

  it('跳日与倍率叠加而不互相吞掉', () => {
    const q = { ...reanchor(initialQa(T0), T0, 2), offset_ms: 3 * DAY_MS };
    expect(effectiveNow(q, T0 + 1_000)).toBe(T0 + 2_000 + 3 * DAY_MS);
  });

  it('缺字段的老农场按未加速补齐', () => {
    const q = normalizeQa({ offset_ms: DAY_MS } as never, T0);
    expect(q.scale).toBe(1);
    expect(effectiveNow(q, T0)).toBe(T0 + DAY_MS);
  });
});

describe('QA 命令', () => {
  it('qa_skip_days 把有效时间推进整日', () => {
    const s = freshFarm();
    const r = run(s, { type: 'qa_skip_days', days: 2 } as never);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(effectiveNow(r.state.qa, T0)).toBe(T0 + 2 * DAY_MS);
  });

  it('qa_skip_days 只往前，回拨被拒', () => {
    // 回拨会撞上 last_effective_now 的单调守卫，也会让已发的 Grant 凭空复活。
    const s = freshFarm();
    for (const days of [0, -1, 1.5, 31]) {
      const r = run(s, { type: 'qa_skip_days', days } as never);
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.code).toBe('BAD_QA_PARAM');
    }
  });

  it('qa_set_clock 校验倍率范围', () => {
    const s = freshFarm();
    for (const scale of [0, -1, MAX_SCALE + 1, Number.NaN]) {
      const r = run(s, { type: 'qa_set_clock', scale } as never);
      expect(r.ok).toBe(false);
    }
    expect(run(s, { type: 'qa_set_clock', scale: 480 } as never).ok).toBe(true);
  });

  it('qa_set_clock 用真实墙钟锚定，不用有效时间', () => {
    // 用有效时间锚定会自我放大：每调一次倍率，锚点就被上一次的加速推远一次。
    const s = freshFarm();
    const first = run(s, { type: 'qa_set_clock', scale: 60 } as never, T0);
    expect(first.ok).toBe(true);
    if (!first.ok) return;
    expect(first.state.qa!.anchor_real).toBe(T0);
    expect(first.state.qa!.anchor_effective).toBe(T0);
  });

  it('qa_set_weather 覆写当日田况并拒绝无效值', () => {
    const s = freshFarm();
    const bad = run(s, { type: 'qa_set_weather', overrides: { '0': 'snow' } } as never);
    expect(bad.ok).toBe(false);
    const badKey = run(s, { type: 'qa_set_weather', overrides: { d0: 'rain' } } as never);
    expect(badKey.ok).toBe(false);
    const good = run(s, { type: 'qa_set_weather', overrides: { '0': 'wind' } } as never);
    expect(good.ok).toBe(true);
    if (!good.ok) return;
    // 脚本第 0 天是 sunny，覆写后 derive 必须报 wind。
    expect(content.weather.script[0]).toBe('sunny');
    expect(derive(good.state, T0, SH, content).field_condition).toBe('wind');
  });

  it('覆写在跨日后仍按天气日索引生效', () => {
    const s = freshFarm();
    const r = run(s, { type: 'qa_set_weather', overrides: { '1': 'wind' } } as never);
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    const nextDay = at('2026-09-05T10:00:00+08:00');
    const d = derive(r.state, nextDay, SH, content);
    expect(d.weather_day_index).toBe(1);
    expect(content.weather.script[1]).toBe('rain');   // 脚本本来是雨
    expect(d.field_condition).toBe('wind');           // 被覆写
  });
});

describe('验收：三分钟走完一日', () => {
  it('480 倍下 3 分钟真实时间跨过一个玩家日', () => {
    const s = freshFarm();
    const set = run(s, { type: 'qa_set_clock', scale: 480 } as never, T0);
    expect(set.ok).toBe(true);
    if (!set.ok) return;
    const threeMinutes = T0 + 3 * 60_000;
    const eff = effectiveNow(set.state.qa, threeMinutes);
    expect(eff - T0).toBe(DAY_MS);
    const d = derive(set.state, eff, SH, content);
    expect(d.days_elapsed).toBe(1);
    expect(d.weather_day_index).toBe(1);
  });

  it('加速不会让作物提前熟得比服务端记的 ready_at 早', () => {
    // 成熟仍是 ready_at <= 有效时间：加速改的是「现在几点」，不是作物时长。
    const s = freshFarm();
    const set = run(s, { type: 'qa_set_clock', scale: 60 } as never, T0);
    expect(set.ok).toBe(true);
    if (!set.ok) return;
    const cells = { ...set.state.cells };
    const id = Object.keys(cells)[0];
    cells[id] = { ...cells[id], state: 'growing', crop: 'R',
      care_done_at: T0, ready_at: T0 + 4 * 3600_000 };
    const withCrop = { ...set.state, cells };
    expect(derive(withCrop, T0 + 3 * 3600_000, SH, content).ripe_cells).toHaveLength(0);
    expect(derive(withCrop, T0 + 4 * 3600_000, SH, content).ripe_cells).toEqual([id]);
  });
});
