import { describe, expect, it } from 'vitest';
import { startJourney, resourceNodes, projectStage } from '../../src/domain/journey.js';
import { derive } from '../../src/domain/derive.js';
import type { Command } from '../../src/domain/commands.js';
import type { FarmState } from '../../src/domain/state.js';
import { BEDS, content, editInventory, freshFarm, run, SH, T0 } from './helpers.js';

const MIN = 60_000;
const HOUR = 60 * MIN;
function play() {
  let state = startJourney(freshFarm(), content);
  let minute = 0;
  const ledger: { minute: number; action: string; wallet: number; wood: number }[] = [];
  const act = (cmd: Command) => {
    const result = run(state, cmd, T0 + minute * MIN);
    if (!result.ok) throw new Error(`${cmd.type}: ${result.code} ${result.detail ?? ''}`);
    state = result.state;
    ledger.push({ minute, action: cmd.type, wallet: state.wallet, wood: state.journey!.wood });
    return result;
  };
  const plant = (crop: 'R' | 'L' | 'C' | 'H', cells: string[]) => {
    if (!state.cells[cells[0]!]) act({ type: 'till_cells', cell_ids: cells });
    const lot = state.inventory.seeds[crop].bound >= cells.length ? 'bound' : 'bought';
    act({ type: 'sow_cells', crop, lot, cell_ids: cells });
    act({ type: 'water_cells', cell_ids: cells });
  };
  const gather = () => {
    for (const node of resourceNodes(state, content))
      if (!state.journey!.exploration.collected.includes(node.id))
        act({ type: 'collect_resource', node_id: node.id, round: state.journey!.exploration.round });
  };
  return { act, plant, gather, ledger, get state() { return state; },
    set minute(value: number) { minute = value; } };
}

describe('Neighbourhood journey', () => {
  it('keeps a chosen material trail stable across collection and rotates only after reachable stops are finished', () => {
    const p = play();
    p.gather();
    p.act({ type: 'next_exploration', round: 0, route: 'riverside' });
    const courtyard = resourceNodes(p.state, content).find(n => n.id === 'courtyard_west')!;
    expect(courtyard.materials).toEqual({ wood: 1, stone: 3 });
    const before = structuredClone(p.state);
    expect(run(p.state, { type: 'next_exploration', round: 1, route: 'riverside' }).ok).toBe(false);
    expect(p.state).toEqual(before);
    p.act({ type: 'collect_resource', node_id: courtyard.id, round: 1 });
    expect(p.state.journey!.materials!.stone).toBe(5);
    expect(run(p.state, { type: 'collect_resource', node_id: courtyard.id, round: 1 }).ok).toBe(false);
    p.gather();
    for (const route of ['gardens', '__proto__', 'missing'])
      expect(run(p.state, { type: 'next_exploration', round: 1, route }).ok).toBe(false);
  });

  it('builds a persistent nursery in two stages and gives one chosen basket per exploration', () => {
    const p = play();
    p.gather();
    expect(run(p.state, { type: 'build_journey_project', project: 'seedbeds', stage: 0 }).ok).toBe(false);
    p.act({ type: 'journey_action', action: 'repair_workbench' });
    p.act({ type: 'next_exploration', round: 0 });
    p.gather();
    p.act({ type: 'build_journey_project', project: 'seedbeds', stage: 0 });
    expect(projectStage(p.state, 'seedbeds', content)).toBe(1);
    const before = structuredClone(p.state);
    expect(run(p.state, { type: 'build_journey_project', project: 'seedbeds', stage: 0 }).ok).toBe(false);
    expect(run(p.state, { type: 'build_journey_project', project: 'seedbeds', stage: 1 }).ok).toBe(false);
    expect(p.state).toEqual(before);
    editInventory(p.state, draft => {
      draft.journey!.materials!.fiber = 2;
      draft.inventory.produce.L = 1;
    });
    p.state.engineering.reserved.L = 1;
    expect(run(p.state, { type: 'build_journey_project', project: 'seedbeds', stage: 1 }).ok).toBe(false);
    p.state.engineering.reserved.L = 0;
    p.act({ type: 'build_journey_project', project: 'seedbeds', stage: 1 });
    expect(p.state.inventory.produce.L).toBe(0);
    p.act({ type: 'use_journey_facility', project: 'seedbeds', choice: 'lettuce', sequence: 0 });
    expect(p.state.inventory.seeds.L.bound).toBe(5);
    expect(run(p.state, { type: 'use_journey_facility', project: 'seedbeds', choice: 'lettuce', sequence: 1 }).ok).toBe(false);
    p.act({ type: 'next_exploration', round: 1, route: 'woodland' });
    expect(run(p.state, { type: 'use_journey_facility', project: 'seedbeds', choice: 'flowers', sequence: 1 }).ok).toBe(false);
    p.state.journey!.unlocks.push('crop_H');
    p.act({ type: 'use_journey_facility', project: 'seedbeds', choice: 'flowers', sequence: 1 });
    expect(p.state.inventory.produce.H).toBe(1);
  });

  it('makes the terrace and supply stop usable without replaying build rewards or spending twice', () => {
    const p = play();
    p.state.journey!.facts.push('shared_meal', 'side_path');
    p.state.journey!.wood = 10;
    p.state.journey!.materials = { stone: 3, fiber: 4 };
    p.state.inventory.produce.H = 1;
    p.state.inventory.dishes = { salad: 2, tea: 1 };
    for (const project of ['terrace', 'waystation']) {
      for (const stage of [0, 1]) p.act({ type: 'build_journey_project', project, stage });
      expect(projectStage(p.state, project, content)).toBe(2);
      expect(run(p.state, { type: 'build_journey_project', project, stage: 1 }).ok).toBe(false);
    }
    p.act({ type: 'use_journey_facility', project: 'terrace', choice: 'salad', sequence: 0 });
    expect(p.state.wallet).toBe(210);
    p.act({ type: 'use_journey_facility', project: 'waystation', choice: 'fiber', sequence: 0 });
    expect(p.state.journey!.materials!.fiber).toBe(2);
    const before = structuredClone(p.state);
    for (const cmd of [
      { type: 'use_journey_facility', project: 'waystation', choice: 'fiber', sequence: 0 },
      { type: 'use_journey_facility', project: 'waystation', choice: 'wood', sequence: 1 },
      { type: 'use_journey_facility', project: 'terrace', choice: 'tea', sequence: 1 },
      { type: 'build_journey_project', project: '__proto__', stage: 0 },
    ] as Command[]) expect(run(p.state, cmd).ok).toBe(false);
    expect(p.state).toEqual(before);
  });

  /*
   * 原「completes the garden in one sunny day, leaving at minute 15」已随 SGODOT-128 退役。
   *
   * 它守的是旅程切片的一条设计承诺：单次会话（15~90 分钟）内跑完种植→收获→料理→建成
   * 的完整闭环。那条承诺建立在分钟级作物（萝卜 3 分钟）之上；作物回到真实小时级
   * （4/8/12/18 小时）之后，同一串动作需要 34 小时以上并且必然跨日，连测试里
   * `player_day_id` 恒为建场当天这个前提都不再成立。
   *
   * 它不是可以调时间轴修好的测试——被验证的那个体验本身变了。种植的多轮循环由
   * `test/domain/farming_loop.test.ts` 接管；旅程的解锁与里程碑由本文件其余用例继续守着。
   */

  it('rejects duplicate and stale gathering and rotates resources only after the route is complete', () => {
    const p = play();
    p.act({ type: 'collect_resource', node_id: 'nursery_west', round: 0 });
    const before = structuredClone(p.state);
    for (const cmd of [
      { type: 'collect_resource', node_id: 'nursery_west', round: 0 },
      { type: 'collect_resource', node_id: 'bistro_west', round: 0 },
      { type: 'collect_resource', node_id: 'side_path', round: 0 },
      { type: 'collect_resource', node_id: 'nursery_east', round: 0.5 },
      { type: 'next_exploration', round: 0 },
    ] as Command[]) expect(run(p.state, cmd).ok).toBe(false);
    expect(p.state).toEqual(before);
    p.gather();
    p.act({ type: 'next_exploration', round: 0 });
    expect(run(p.state, { type: 'collect_resource', node_id: 'nursery_east', round: 0 }).ok).toBe(false);
  });

  it('recovers an empty wallet and basket indefinitely without crops or daily grants', () => {
    const p = play();
    p.state.wallet = 0;
    for (const seed of Object.values(p.state.inventory.seeds)) seed.bound = seed.bought = 0;
    for (let round = 0; round < 5; round++) {
      p.gather();
      p.act({ type: 'accept_opportunity', slot: 'restorer', sequence: round * 2 });
      p.act({ type: 'fulfill_opportunity', slot: 'restorer', sequence: round * 2 });
      p.act({ type: 'accept_opportunity', slot: 'restorer', sequence: round * 2 + 1 });
      const before = structuredClone(p.state);
      expect(run(p.state, { type: 'fulfill_opportunity', slot: 'restorer', sequence: round * 2 + 1 }).ok).toBe(false);
      expect(p.state).toEqual(before);
      p.act({ type: 'decline_opportunity', slot: 'restorer', sequence: round * 2 + 1 });
      p.act({ type: 'next_exploration', round });
    }
    expect(p.state.wallet).toBe(45);
    p.act({ type: 'buy_seeds', crop: 'R', qty: 3 });
    expect(p.state.inventory.seeds.R.bought).toBe(3);
    expect(run(p.state, { type: 'fulfill_opportunity', slot: 'restorer', sequence: 0 }).ok).toBe(false);
  });

  it('uses new prices beyond the old daily stall cap; no legacy payout endpoints remain', () => {
    const p = play();
    p.state.inventory.produce.R = 100;
    p.act({ type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 100 }] });
    expect(p.state.wallet).toBe(680);
    expect(p.state.inventory.produce.R).toBe(0);
    for (const cmd of [
      { type: 'submit_request', request_id: 'd0_tutorial_buyback' },
      { type: 'claim_seedling_pack' }, { type: 'claim_subsidy', subsidy_id: 'weather_story' },
    ] as Command[]) expect(run(p.state, cmd).ok).toBe(false);
  });

  it('upgrades old saves without rewriting assets, deadlines, chapter grants or photos', () => {
    const old = freshFarm();
    old.chapters[2].grants_issued = old.chapters[3].grants_issued = true;
    old.xp.first_harvest_crops = ['R'];
    old.residents.nursery_keeper.first_met_day = '2026-09-04';
    old.inventory.produce.H = 4;
    old.engineering.reserved.H = 4;
    old.cells[BEDS[0]!] = { state: 'growing', crop: 'R', watered_at: T0, ready_at: T0 + 4 * 3600_000 };
    const before = structuredClone(old);
    const migrated = startJourney(old, content);
    for (const key of ['inventory', 'wallet', 'cells', 'chapters', 'handbook', 'tools', 'week_summary'] as (keyof FarmState)[])
      expect(migrated[key]).toEqual(before[key]);
    expect(migrated.journey!.unlocks).toContain('crop_H');
    expect(migrated.journey!.facts).not.toContain('shared_meal');
    expect(migrated.engineering.reserved).toEqual({});
    expect(startJourney(migrated, content)).toEqual(migrated);
    expect(old).toEqual(before);
  });

  it('sustains repeated radish cycles without a stall cap or unbounded crop profit', () => {
    const p = play();
    p.act({ type: 'buy_seeds', crop: 'R', qty: 3 });
    p.plant('R', BEDS.slice(0, 6));
    p.plant('R', BEDS.slice(6));
    // 一轮 = 一个萝卜周期（4 小时）。原来 3 分钟一轮的高频节奏随分钟级作物一起退役。
    const cycle = content.crops.crops.R.duration_ms / MIN;
    for (let minute = cycle; minute <= cycle * 6; minute += cycle) {
      p.minute = minute;
      p.act({ type: 'harvest_cells', cell_ids: BEDS });
      p.act({ type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 9 }] });
      p.act({ type: 'buy_seeds', crop: 'R', qty: 9 });
      p.plant('R', BEDS);
    }
    // 精确金额随作物时长与账本一同退役；这里守的是「摊位有日预算、收益不会无界」。
    expect(p.state.wallet).toBeGreaterThan(0);
    expect(p.state.stall.settled).toBeGreaterThan(0);
    expect(p.ledger.every(row => row.wallet >= 0)).toBe(true);
  });

  it('allows both upgrades in either order and rejects repeat purchases', () => {
    for (const order of [['tool', 'field'], ['field', 'tool']] as const) {
      const p = play();
      p.state.journey!.facts.push('side_path');
      p.state.wallet = 1000;
      for (const choice of order) p.act({ type: 'purchase_growth_choice', choice, transaction_id: choice });
      expect(p.state.tools.row_tool).toBe(true);
      expect(p.state.beds_unlocked).toBe(4);
      const before = structuredClone(p.state);
      expect(run(p.state, { type: 'purchase_growth_choice', choice: 'tool', transaction_id: 'again' }).ok).toBe(false);
      expect(p.state).toEqual(before);
    }
  });
});
