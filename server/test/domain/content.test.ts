import { describe, expect, it } from 'vitest';
import { cpSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import {
  ContentError, DEFAULT_CONTENT_DIR, contentVersion, loadContent, CROP_IDS,
} from '../../src/domain/content.js';

const scratch = (): string => {
  const dir = mkdtempSync(path.join(tmpdir(), 'farm-content-'));
  cpSync(DEFAULT_CONTENT_DIR, dir, { recursive: true });
  return dir;
};
const edit = (dir: string, name: string, mutate: (d: any) => void): void => {
  const file = path.join(dir, `${name}.json`);
  const d = JSON.parse(readFileSync(file, 'utf8'));
  mutate(d);
  writeFileSync(file, JSON.stringify(d, null, 1));
};

describe('content tables', () => {
  it('八张表全部加载并通过校验', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    expect(Object.keys(c.crops.crops).sort()).toEqual([...CROP_IDS].sort());
    expect(c.weather.script).toHaveLength(7);
    expect(c.chapters.chapters).toHaveLength(7);
    expect(c.economy.initial_wallet).toBe(180);
  });

  it('PRD 的关键数值确实进了表里，而不是散在代码里', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    // §6.4 L425-428 四作物
    expect(c.crops.crops.R).toMatchObject({ seed_price: 4, unit_price: 8, yield: 1 });
    expect(c.crops.crops.H).toMatchObject({ seed_price: 10, unit_price: 19 });
    expect(c.crops.crops.C.duration_ms).toBe(12 * 3600_000);
    // §6.4 L429 D0 教学特例
    expect(c.crops.d0_tutorial).toMatchObject({ crop: 'R', count: 6, duration_ms: 180_000 });
    // §6.6 L453 受控天气序列 + L459 保护槽
    expect(c.weather.script).toEqual(['sunny', 'rain', 'sunny', 'sunny', 'rain', 'wind', 'sunny']);
    expect(c.weather.protected_slots).toEqual([0, 1, 5]);
    // §7.2 L488 等级阈值
    expect(c.xp.level_thresholds).toEqual([0, 40, 80, 120, 160, 220, 290]);
    // §7.5 L572 两条路线账户价值相同
    expect(c.economy.target_account_value_d6).toBe(545);
    // §8.2 L608-612 三阶段，熟悉需共同事件
    expect(c.relationships.stages.map(s => s.id)).toEqual(['first_sight', 'acquainted', 'familiar']);
    expect(c.relationships.stages[2]).toMatchObject({ min: 45, requires: 'shared_event' });
  });

  it('扩地固定篮恰好 12 枚且总价 84——账本里的 84 就是按它算的', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    const basket = c.economy.growth_choice.field.seed_basket;
    const count = Object.values(basket).reduce<number>((n, v) => n + (v ?? 0), 0);
    const cost = CROP_IDS.reduce((s, id) => s + (basket[id] ?? 0) * c.crops.crops[id].seed_price, 0);
    expect(count).toBe(12);
    expect(cost).toBe(84);
  });

  it('章节 Grant 总量与 PRD 账本的绑定种子一致', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    const total: Record<string, number> = {};
    for (const ch of c.chapters.chapters)
      for (const [id, n] of Object.entries(ch.grants)) total[id] = (total[id] ?? 0) + (n ?? 0);
    // D0 6R+3L / D1 3L / D2 2C / D3 2H / D4 2H / D6 1C+1H+1L（L530-536）
    expect(total).toEqual({ R: 6, L: 7, C: 3, H: 5 });
  });

  it('回购箱计入摊位预算——否则高频账户价值上界会越过 981', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    expect(c.recipes.buyback.counts_against_stall_budget).toBe(true);
    expect(c.recipes.buyback.per_player_day).toBe(1);
    expect(c.economy.account_value_cap_multiplier).toBe(1.8);
  });

  it('改任意一个字节 content_version 就变', () => {
    const dir = scratch();
    const before = contentVersion(dir);
    edit(dir, 'economy', d => { d.initial_wallet = 181; });
    expect(contentVersion(dir)).not.toBe(before);
  });

  it('改 PRD 行号注释也算内容变了——依据和数值不该脱节', () => {
    const dir = scratch();
    const before = contentVersion(dir);
    edit(dir, 'crops', d => { d._source = 'changed'; });
    expect(contentVersion(dir)).not.toBe(before);
  });

  it('内容非法时抛 ContentError 而不是静默降级', () => {
    const dir = scratch();
    edit(dir, 'economy', d => { d.growth_choice.field.seed_basket = { R: 11 }; });
    expect(() => loadContent(dir)).toThrowError(ContentError);

    const dir2 = scratch();
    edit(dir2, 'weather_script', d => { d.script = ['sunny']; });
    expect(() => loadContent(dir2)).toThrowError(/script 应有 7 项/);

    const dir3 = scratch();
    edit(dir3, 'chapters', d => { d.chapters[3].index = 9; });
    expect(() => loadContent(dir3)).toThrowError(/index 应为 3/);

    const dir4 = scratch();
    edit(dir4, 'requests', d => { d.requests.d1_bistro_lettuce.resident = 'nobody'; });
    expect(() => loadContent(dir4)).toThrowError(/resident 未知/);
  });
});

/**
 * 内容表与 PRD §7.5 账本的对账。这不是账本测试（那是 Task 5，要从 create_farm 起走
 * 公开命令），而是先证明**表里的数字本身**能凑出账本的每日种子支出与摊位收入——
 * 如果这一步就对不上，后面 reducer 再对也没用。
 */
describe('content vs PRD ledger arithmetic', () => {
  const c = loadContent(DEFAULT_CONTENT_DIR);
  const seedCost = (m: Record<string, number>) =>
    Object.entries(m).reduce((s, [id, n]) => s + c.crops.crops[id as 'R'].seed_price * n, 0);
  const stallIncome = (m: Record<string, number>) =>
    Object.entries(m).reduce((s, [id, n]) => s + c.crops.crops[id as 'R'].unit_price * n, 0);

  it('每日「下一轮付费播种」的种子支出等于 PRD 的 24/28/42/54/52/72/48', () => {
    const paid: Record<string, number>[] = [
      { R: 6 }, { R: 4, L: 2 }, { R: 2, L: 3, C: 2 }, { C: 4, L: 2, H: 1 },
      { C: 3, L: 3, H: 1 }, { C: 3, H: 3, L: 3 }, { C: 2, H: 2, L: 2 },
    ];
    expect(paid.map(seedCost)).toEqual([24, 28, 42, 54, 52, 72, 48]);
    expect(paid.map(seedCost).reduce((a, b) => a + b)).toBe(320); // L541
  });

  it('每日摊位出售收入等于 PRD 的 24/40/80/36/79/47/75，合计 381', () => {
    const sells: Record<string, number>[] = [
      { R: 3 }, { R: 5 }, { R: 4, L: 4 }, { C: 1, L: 1, R: 1 },
      { C: 3, H: 1, L: 1 }, { C: 1, H: 1, L: 1 }, { C: 2, H: 1, L: 2 },
    ];
    expect(sells.map(stallIncome)).toEqual([24, 40, 80, 36, 79, 47, 75]);
    expect(sells.map(stallIncome).reduce((a, b) => a + b)).toBe(381); // L545
    for (const day of sells.map(stallIncome)) expect(day).toBeLessThanOrEqual(c.economy.stall_budget_per_day);
  });

  it('请求与补贴合计等于 PRD 的 200 与 80', () => {
    const requests = Object.values(c.requests.requests).reduce((s, r) => s + r.coins, 0);
    const subsidies = Object.values(c.economy.subsidies).reduce((s, r) => s + r.coins, 0);
    expect(requests).toBe(200);
    expect(subsidies).toBe(80);
  });

  it('按内容表推算的七日钱包等于 PRD 的目标序列', () => {
    const income = [54, 105, 80, 91, 103, 117, 135]; // L530-536「金币来源」列
    const seeds = [24, 28, 42, 54, 52, 72, 48];
    let wallet = c.economy.initial_wallet;
    const run = income.map((inc, i) => {
      wallet += inc - seeds[i] - (i === 5 ? c.economy.growth_choice.tool.price : 0);
      return wallet;
    });
    expect(run).toEqual(c.economy.target_wallet_by_day.tool);
    expect(run[6] + c.economy.growth_choice.tool.price).toBe(c.economy.target_account_value_d6);
  });
});
