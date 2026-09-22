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
  it.each(['duplicate_id', 'wrong_resident', 'unknown_slot', 'missing_reply', 'unknown_material', 'zero_material',
    'permanent_equipment', 'uncraftable_prop', 'null_cost'])('rejects invalid request definition %s', invalid => {
    const dir = scratch();
    edit(dir, 'journey', d => {
      const request = d.opportunities.restorer[2];
      if (invalid === 'duplicate_id') request.id = d.opportunities.nursery[0].id;
      if (invalid === 'wrong_resident') request.resident_id = 'nursery_keeper';
      if (invalid === 'unknown_slot') d.opportunities.unknown = d.opportunities.restorer;
      if (invalid === 'missing_reply') request.reply = '';
      if (invalid === 'unknown_material') request.materials = { gold: 3 };
      if (invalid === 'zero_material') request.materials = { copper_ore: 0 };
      if (invalid === 'permanent_equipment') request.props = { copper_pickaxe: 1 };
      if (invalid === 'uncraftable_prop') request.props = { bench: 1 };
      if (invalid === 'null_cost') request.materials = null;
    });
    expect(() => loadContent(dir)).toThrowError(ContentError);
  });
  it('keeps the six original request indices and permits new needs to contribute to existing street effects', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    expect(c.journey.opportunities.nursery.map(offer => offer.id)).toEqual(['fresh_nursery_leaves', 'nursery_flowers']);
    expect(c.journey.opportunities.bistro.slice(0, 2).map(offer => offer.id)).toEqual(['lunch_at_table', 'tea_for_neighbours']);
    expect(c.journey.opportunities.restorer.slice(0, 2).map(offer => offer.id)).toEqual(['timber_for_repairs', 'workshop_supplies']);
    expect(c.journey.opportunities.restorer[0].effect).toBe(c.journey.opportunities.restorer[2].effect);
    expect(c.journey.opportunities.restorer[1].effect).toBe(c.journey.opportunities.restorer[3].effect);
  });
  it.each(['negative_base', 'unknown_stat', 'wrong_slot', 'zero_cost', 'mineral_cost', 'duplicate_buff', 'zero_uses', 'unknown_food'])
  ('rejects invalid character %s', invalid => {
    const dir = scratch();
    edit(dir, 'character', d => {
      if (invalid === 'negative_base') d.base.gather_bonus = -1;
      if (invalid === 'unknown_stat') d.equipment.copper_pickaxe.modifiers = { health: 1 };
      if (invalid === 'wrong_slot') d.equipment.copper_pickaxe.slot = 'head';
      if (invalid === 'zero_cost') d.equipment.copper_pickaxe.materials.wood = 0;
      if (invalid === 'mineral_cost') d.equipment.copper_pickaxe.materials.gold = 1;
      if (invalid === 'duplicate_buff') d.consumables.tea.buff_id = d.consumables.salad.buff_id;
      if (invalid === 'zero_uses') d.consumables.tea.uses = 0;
      if (invalid === 'unknown_food') d.consumables.wood = d.consumables.tea;
    });
    expect(() => loadContent(dir)).toThrowError(ContentError);
  });
  it('includes character rules in the content checksum', () => {
    const dir = scratch();
    const before = contentVersion(dir);
    const legacy = contentVersion(dir, true);
    edit(dir, 'character', d => { d.consumables.salad.uses = 4; });
    expect(contentVersion(dir)).not.toBe(before);
    expect(contentVersion(dir, true)).toBe(legacy);
  });
  it.each(['floor_count', 'duplicate_rock', 'position', 'weight', 'unknown_material', 'no_drop_quantity'])('rejects invalid mining %s', invalid => {
    const dir = scratch();
    edit(dir, 'mining', d => {
      if (invalid === 'floor_count') d.floors = 6;
      if (invalid === 'duplicate_rock') d.rocks[1].id = d.rocks[0].id;
      if (invalid === 'position') d.rocks[0].position = [1];
      if (invalid === 'weight') d.bonus_drops[0].weight = 0;
      if (invalid === 'unknown_material') d.bonus_drops[0].material = 'gold';
      if (invalid === 'no_drop_quantity') d.bonus_drops[2].quantity = 1;
    });
    expect(() => loadContent(dir)).toThrowError(ContentError);
  });
  it('rejects invalid mineral costs in cooking recipes', () => {
    const dir = scratch();
    edit(dir, 'recipes', d => { d.recipes.vegetable_soup.materials = { unknown: 1 }; });
    expect(() => loadContent(dir)).toThrowError(ContentError);
  });

  it.each(['rockless_floor', 'combat_version', 'empty_loot', 'unknown_loot', 'wrong_loot_kind', 'loot_weight', 'loot_quantity', 'resistance'])
  ('rejects invalid combat and floor rule %s', invalid => {
    const dir = scratch();
    edit(dir, 'mining', d => {
      const elite = d.combat.monsters.elite_slime;
      if (invalid === 'rockless_floor') d.rockless_floors = [4];
      if (invalid === 'combat_version') d.combat.version = 1;
      if (invalid === 'empty_loot') elite.loot = [];
      if (invalid === 'unknown_loot') elite.loot[0].item_id = '__proto__';
      if (invalid === 'wrong_loot_kind') elite.loot[0].item_id = 'copper_sword';
      if (invalid === 'loot_weight') elite.loot[0].weight = 0;
      if (invalid === 'loot_quantity') elite.loot[0].quantity = -1;
      if (invalid === 'resistance') elite.knockback_resistance = 2;
    });
    expect(() => loadContent(dir)).toThrowError(ContentError);
  });
  it.each(['requirements', 'theme', 'item', 'dish', 'coins', 'null'])('rejects invalid gathering %s', invalid => {
    const dir = scratch();
    edit(dir, 'journey', d => {
      const g = d.gatherings;
      if (invalid === 'requirements') g.requires = ['missing_fact'];
      if (invalid === 'theme') { g.themes.unknown = g.themes.garden; delete g.themes.garden; }
      if (invalid === 'item') g.themes.garden.item = 'unknown';
      if (invalid === 'dish') g.themes.garden.dish = 'unknown';
      if (invalid === 'coins') g.themes.garden.coins = -1;
      if (invalid === 'null') g.themes.garden = null;
    });
    expect(() => loadContent(dir)).toThrowError(ContentError);
  });
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
    // §6.6 L453 受控天气序列 + L459 保护槽
    expect(c.weather.script).toEqual(['sunny', 'rain', 'sunny', 'sunny', 'rain', 'wind', 'sunny']);
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

  it('回购箱不占摊位预算，但周上限 1 次——PRD 把它算在「居民请求」栏', () => {
    const c = loadContent(DEFAULT_CONTENT_DIR);
    // L544-547：请求栏 224 = 30+45+55+70+24，摊位栏 381 不含回购。
    // 计入摊位预算会让账本 D4 的 79+24=103 超过 100，目标路径直接跑不通。
    expect(c.recipes.buyback.counts_against_stall_budget).toBe(false);
    expect(c.recipes.buyback.per_player_day).toBe(1);
    expect(c.recipes.buyback.per_week).toBe(1);
    // 高频闸门改由「回购周 1 次 + 种苗包周 2 次 + 收紧空仓判定」承担，宽松上界 972。
    expect(c.economy.seedling_pack.week_cap).toBe(2);
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
    // L546「具体居民请求 224」= 四条请求 200 + 茶回购 24（生活回购，L550）
    expect(requests + c.recipes.buyback.coins).toBe(224);
    expect(requests + subsidies + c.recipes.buyback.coins + 381).toBe(685); // L541 总收入
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
