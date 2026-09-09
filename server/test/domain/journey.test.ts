import { describe, expect, it } from 'vitest';
import { startJourney, resourceNodes, projectStage } from '../../src/domain/journey.js';
import { derive } from '../../src/domain/derive.js';
import type { Command } from '../../src/domain/commands.js';
import type { FarmState } from '../../src/domain/state.js';
import { BEDS, content, freshFarm, run, SH, T0 } from './helpers.js';

const MIN = 60_000;
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
    if (state.cells[cells[0]].state === 'wild') {
      act({ type: 'clear_cells', cell_ids: cells });
      act({ type: 'till_cells', cell_ids: cells });
    }
    const lot = state.inventory.seeds[crop].bound >= cells.length ? 'bound' : 'bought';
    act({ type: 'sow_cells', crop, lot, cell_ids: cells });
    act({ type: 'apply_care', cell_ids: cells, kind: 'water' });
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
    p.state.journey!.materials!.fiber = 2;
    p.state.inventory.produce.L = 1;
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

  it.each([false, true])('completes the garden in one sunny day, leaving at minute 15: %s', leaves => {
    const p = play();
    p.plant('R', BEDS.slice(0, 3));
    p.minute = 1;
    p.act({ type: 'talk_to_resident', resident_id: 'nursery_keeper' });
    p.gather();
    p.act({ type: 'journey_action', action: 'repair_workbench' });
    p.minute = 3;
    p.act({ type: 'harvest_cells', cell_ids: BEDS.slice(0, 3) });
    expect(p.state.inventory.seeds.C.bound).toBe(2);
    expect(p.state.journey!.unlocks).toContain('kitchen');
    p.act({ type: 'talk_to_resident', resident_id: 'bistro_owner' });
    p.plant('C', [BEDS[0]]);
    p.plant('L', [BEDS[1]]);
    expect(p.state.cells[BEDS[0]].ready_at).toBe(T0 + 15 * MIN);
    p.gather();
    p.act({ type: 'journey_action', action: 'craft_planter' });
    p.act({ type: 'save_decorations', props: [{ anchor_id: 'courtyard', prop_id: 'planter', offset_q: [-6, 5], rotation_q: 1 }] });
    p.minute = leaves ? 30 : 15;
    p.act({ type: 'harvest_cells', cell_ids: BEDS.slice(0, 2) });
    p.act({ type: 'cook_dish', recipe: 'salad' });
    p.act({ type: 'journey_action', action: 'share_meal' });
    expect(p.state.inventory.dishes.salad).toBe(0);
    expect(p.state.inventory.seeds.H.bound).toBe(2);
    p.plant('H', [BEDS[0]]);
    p.act({ type: 'next_exploration', round: 0 });
    p.gather();
    p.act({ type: 'journey_action', action: 'clear_side_path' });
    p.gather();
    p.minute = leaves ? 48 : 33;
    p.act({ type: 'harvest_cells', cell_ids: [BEDS[0]] });
    p.act({ type: 'journey_action', action: 'plant_planter' });
    expect(p.state.journey!.completed).toHaveLength(6);
    expect(p.state.nursery.stage).toBe('built');
    expect(p.state.clock.chapter_index).toBe(0);
    expect(p.state.clock.player_day_id).toBe('2026-09-04');
    expect(derive(p.state, T0 + 8 * 3600_000, SH, content).opens_new_chapter).toBe(false);
    for (let round = 1; round < 4; round++) {
      p.act({ type: 'fulfill_opportunity', slot: 'restorer', sequence: (round - 1) * 2 });
      p.act({ type: 'fulfill_opportunity', slot: 'restorer', sequence: (round - 1) * 2 + 1 });
      p.act({ type: 'next_exploration', round });
      p.gather();
    }
    expect(p.ledger.every(row => row.wallet >= 0 && row.wood >= 0)).toBe(true);
  });

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
      p.act({ type: 'fulfill_opportunity', slot: 'restorer', sequence: round * 2 });
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
    old.cells[BEDS[0]] = { ...old.cells[BEDS[0]], state: 'growing', crop: 'R', ready_at: T0 + 4 * 3600_000 };
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

  it('sustains 90 minutes of high-frequency planting without a stall cap or unbounded crop profit', () => {
    const p = play();
    p.act({ type: 'buy_seeds', crop: 'R', qty: 3 });
    p.plant('R', BEDS.slice(0, 6));
    p.plant('R', BEDS.slice(6));
    for (let minute = 3; minute <= 90; minute += 3) {
      p.minute = minute;
      p.act({ type: 'harvest_cells', cell_ids: BEDS });
      p.act({ type: 'sell_at_stall', items: [{ kind: 'produce', id: 'R', qty: 9 }] });
      p.act({ type: 'buy_seeds', crop: 'R', qty: 9 });
      p.plant('R', BEDS);
    }
    expect(p.state.wallet).toBe(438);
    expect(p.state.stall.settled).toBe(1350);
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
