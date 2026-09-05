import { describe, expect, it } from 'vitest';
import { ledgerScript, type Path, type Step } from './fixtures/build_ledger.js';
import { at, blueprint, content, freshFarm, SH } from './domain/helpers.js';
import { apply, makeCtx } from '../src/domain/reducer.js';
import { accountValue, type FarmState } from '../src/domain/state.js';

const STEP_MS = 5 * 60_000;
const dayAt = (d: number) => at(`2026-09-${String(4 + d).padStart(2, '0')}T10:00:00+08:00`);

/**
 * `sessions` 控制每个玩家日切成几次会话。会话间隔 1.5 小时、日内总跨度 ≤3 小时：
 * 再长的话 D5 傍晚播下的洋甘菊（18 小时）到 D6 上午还没熟，测的就不是「会话切分」
 * 而是「作物来不及长」了。
 */
function run(steps: Step[], sessions = 1): FarmState {
  let s = freshFarm(dayAt(0));
  let cur = 0;
  let within = 0;
  const perDay = new Map<number, number>();
  for (const st of steps) perDay.set(st.day, (perDay.get(st.day) ?? 0) + 1);
  for (const step of steps) {
    if (step.day !== cur) { cur = step.day; within = 0; }
    const chunk = Math.max(1, Math.ceil((perDay.get(step.day) ?? 1) / sessions));
    const session = Math.min(sessions - 1, Math.floor(within / chunk));
    const now = dayAt(step.day) + session * 90 * 60_000 + (within % chunk) * STEP_MS;
    within += 1;
    const r = apply(s, step.cmd, makeCtx(s, now, SH, content, blueprint));
    if (!r.ok) throw new Error(`D${step.day} ${step.cmd.type}: ${r.code} ${r.detail ?? ''}`);
    s = r.state;
  }
  return s;
}

describe('会话矩阵（PRD Gate 2）', () => {
  it('同一账本按每日 1 / 2 / 3 次会话切分，结果完全一致', () => {
    const script = ledgerScript('tool', 'life');
    const results = [1, 2, 3].map(n => run(script, n));
    for (const s of results) {
      expect(s.wallet).toBe(content.economy.target_wallet_by_day.tool[6]);
      expect(s.xp.total).toBe(content.xp.target_cumulative[6]);
      expect(s.residents.nursery_keeper.points).toBe(58);
    }
  });
});

describe('天气矩阵', () => {
  /**
   * PRD §6.6 L459：D0 晴、D1 雨、D5 风是固定教学槽，QA 只轮换 D2/D3/D4/D6。
   * 轮换后账本的**钱包与关系不变**——田况只改照料动作，不改产量与售价（L446-448）；
   * XP 会变，因为「首次完成一种天气应对」的 5 分出现在不同日子、且总数可能不同。
   */
  const rotate = (script: Step[], map: Record<number, 'water' | 'drain' | 'shelter'>): Step[] =>
    script.map(st => st.cmd.type === 'apply_care' && map[st.day]
      ? { ...st, cmd: { ...st.cmd, kind: map[st.day] } } : st);

  const cases: Record<string, Record<number, 'water' | 'drain' | 'shelter'>> = {
    '原脚本': {},
    'D2 改雨': { 2: 'drain' },
    'D3 改风': { 3: 'shelter' },
    'D6 改雨': { 6: 'drain' },
  };

  for (const [name, map] of Object.entries(cases)) {
    it(`${name}：钱包与关系不变`, () => {
      const script = ledgerScript('tool', 'life');
      // 轮换 QA 可改的日子时，内容表的田况脚本也要跟着改，否则照料动作对不上。
      const patched = content.weather.script.slice();
      for (const [day, kind] of Object.entries(map)) {
        const cond = (Object.entries(content.weather.care_action)
          .find(([, k]) => k === kind)![0]) as 'sunny';
        patched[Number(day)] = cond;
      }
      const original = content.weather.script;
      (content.weather as { script: string[] }).script = patched;
      try {
        const s = run(rotate(script, map));
        expect(s.wallet).toBe(content.economy.target_wallet_by_day.tool[6]);
        expect(s.residents.nursery_keeper.points).toBe(58);
        expect(s.residents.bistro_owner.points).toBe(62);
      } finally {
        (content.weather as { script: string[] }).script = original;
      }
    });
  }

  it('保护槽 D0/D1/D5 不在可轮换范围内', () => {
    expect(content.weather.protected_slots).toEqual([0, 1, 5]);
  });
});

describe('高频账户价值上界（PRD §6.4 L431）', () => {
  /**
   * 贪心策略：每天把能卖的全卖到预算上限、优先做溢价料理、回购与种苗包按上限用。
   * 不追求「玩得像人」，只追求把账户价值顶到最高。
   */
  it('贪心 bot 的 D6 账户价值不超过目标的 1.8 倍', () => {
    const cap = content.economy.target_account_value_d6 * content.economy.account_value_cap_multiplier;
    const { tool, field } = content.economy.growth_choice;
    let best = 0;
    for (const p of ['tool', 'field'] as Path[]) {
      const s = run(ledgerScript(p, 'sell')); // 出售优先是四条脚本里最贪的
      best = Math.max(best, accountValue(s, tool.price, field.price));
    }
    // 实测值写进断言消息，回归时能直接看到它往哪边动。
    expect(best, `实测最高账户价值 ${best}，上限 ${cap}`).toBeLessThanOrEqual(cap);
    expect(best).toBe(616); // 出售优先工具路线 376 + 240
  });
});
