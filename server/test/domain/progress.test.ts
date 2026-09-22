import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { derive } from '../../src/domain/derive.js';
import { projectFarmState } from '../../src/domain/progress.js';
import type { FarmState } from '../../src/domain/state.js';
import { BEDS, HOUR, SH, T0, at, content, freshFarm, plot, run, runAll } from './helpers.js';

const six = BEDS.slice(0, 6);
const remaining = BEDS.slice(6);
const project = (s: FarmState, now = T0) => projectFarmState(s, now, SH, content, plot);
const chapterEntries = (s: FarmState) => s.handbook.filter(entry => entry.kind === 'chapter_done');

function activeChapter(index: number): FarmState {
  const s = freshFarm();
  s.clock.chapter_index = index;
  s.chapters[index].status = 'active';
  s.chapters[index].activated_day = s.clock.player_day_id;
  s.inventory.produce = { R: 6, L: 6, C: 6, H: 6, T: 0 };
  return s;
}

function harvestedTutorial(earlyLettuce = false): FarmState {
  const steps: [Command, number?][] = [
      [{ type: 'till_cells', cell_ids: BEDS }],
    [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bound' }],
  ];
  if (earlyLettuce) steps.push([{ type: 'sow_cells', cell_ids: remaining, crop: 'L', lot: 'bound' }]);
  steps.push([{ type: 'water_cells', cell_ids: earlyLettuce ? BEDS : six }]);
  steps.push([{ type: 'harvest_cells', cell_ids: six }, T0 + 4 * HOUR]);
  return runAll(freshFarm(), steps);
}

function completeTutorial(): FarmState {
  return runAll(harvestedTutorial(), [
    [{ type: 'buy_seeds', crop: 'R', qty: 6 }],
    [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bought' }],
    [{ type: 'sow_cells', cell_ids: remaining, crop: 'L', lot: 'bound' }],
    [{ type: 'water_cells', cell_ids: BEDS }],
  ], T0 + 4 * HOUR);
}


/*
 * 原「D0 event-backed next batch」整组已随 SGODOT-128 退役：它断言第 0 章要求恰好 9 格
 * 固定田畦同时 sown+cared，而自由格子种田下既没有固定 9 格，也没有教学批次的概念。
 * 第 0 章现在只要求 farm_created + first_harvest，由 chapters.json 声明。
 */

describe('chapter-specific completion facts', () => {

  it('D2 requires talking to the bistro owner after the real choice, without extra points', () => {
    let s = runAll(activeChapter(2), [[{ type: 'talk_to_resident', resident_id: 'bistro_owner' }]]);
    s = runAll(s, [[{ type: 'resolve_life_choice', chapter: 2, choice: 'keep' }]]);
    expect(s.chapters[2].status).toBe('active');
    expect(s.residents.bistro_owner.choice_memories).toBeUndefined();
    s = runAll(s, [[{ type: 'talk_to_resident', resident_id: 'nursery_keeper' }]]);
    expect(s.chapters[2].status).toBe('active');
    const wallet = s.wallet;
    s = runAll(s, [[{ type: 'talk_to_resident', resident_id: 'bistro_owner' }]]);
    expect(s.chapters[2].status).toBe('done');
    expect(s.residents.bistro_owner.choice_memories).toEqual({ 2: 'keep' });
    expect(s.residents.bistro_owner.points).toBe(2);
    expect(s.wallet).toBe(wallet);
  });

  it('D3 requires both the shared salad scene and nursery request', () => {
    let s = runAll(activeChapter(3), [
      [{ type: 'cook_dish', recipe: 'salad' }],
      [{ type: 'submit_request', request_id: 'd3_nursery_basket' }],
    ]);
    expect(s.chapters[3].status).toBe('active');
    s = runAll(s, [[{ type: 'attend_shared_event', event_id: 'cooking_together' }]]);
    expect(s.chapters[3].status).toBe('done');
  });

  it('D4 needs visit return and an actual submission, not merely a reservation', () => {
    let s = runAll(activeChapter(4), [
      [{ type: 'record_visit_return', visited_farm_id: 'preset_a' }],
      [{ type: 'reserve_engineering', items: { C: 1, H: 1 } }],
    ]);
    expect(s.chapters[4].status).toBe('active');
    s = runAll(s, [[{ type: 'submit_engineering', items: { C: 1, H: 1 } }]]);
    expect(s.chapters[4].status).toBe('done');
  });


  it('D6 needs the entire quota and shared scene; the final chapter stays final', () => {
    let s = runAll(activeChapter(6), [
      [{ type: 'reserve_engineering', items: { C: 2, H: 4 } }],
      [{ type: 'submit_engineering', items: { C: 2, H: 3 } }],
      [{ type: 'attend_shared_event', event_id: 'nursery_activity' }],
    ]);
    expect(s.chapters[6].status).toBe('active');
    s = runAll(s, [[{ type: 'submit_engineering', items: { H: 1 } }]]);
    expect(s.chapters[6].status).toBe('done');
    expect(project(s, T0 + 48 * HOUR).clock.chapter_index).toBe(6);
    expect(derive(s, T0, SH, content).next_chapter_opens_at).toBeNull();
  });
});

describe('projection, daily activation, and completion idempotency', () => {

  it('repeated reads and successful commands never duplicate chapter completion or grants', () => {
    const s = completeTutorial();
    const original = structuredClone(s);
    const tomorrow = T0 + 24 * HOUR;
    const p = project(s, tomorrow);
    expect(p.clock.chapter_index).toBe(1);
    expect(p.inventory.seeds.L.bound).toBe(3);
    expect(p.clock.last_effective_now).toBe(s.clock.last_effective_now);
    expect(project(p, tomorrow)).toEqual(p);
    expect(s).toEqual(original);
    const written = runAll(p, [[{ type: 'talk_to_resident', resident_id: 'bistro_owner' }]], tomorrow);
    expect(chapterEntries(written)).toEqual([{ kind: 'chapter_done', key: '0', day: '2026-09-04' }]);
    expect(written.inventory.seeds.L.bound).toBe(3);
  });

  it('finishing an old chapter after absence opens one chapter today without resetting spent daily budgets', () => {
    const today = T0 + 72 * HOUR;
    let s = project(activeChapter(1), today);
    s = runAll(s, [
      [{ type: 'till_cells', cell_ids: [BEDS[0]] }],
      [{ type: 'sow_cells', cell_ids: [BEDS[0]], crop: 'R', lot: 'bound' }],
      [{ type: 'water_cells', cell_ids: [BEDS[0]] }],
    ], today);
    s.stall.settled = 73;
    s.buyback.sold = 1;
    s.xp.harvest_counted.plants = 4;
    s = runAll(s, [[{ type: 'submit_request', request_id: 'd1_bistro_lettuce' }]], today);
    expect(s.chapters[1].status).toBe('done');
    expect(s.clock.chapter_index).toBe(2);
    expect(s.chapters[2].activated_day).toBe('2026-09-07');
    expect(s.stall.settled).toBe(73);
    expect(s.buyback.sold).toBe(1);
    expect(s.xp.harvest_counted.plants).toBe(4);
    s = runAll(s, [
      [{ type: 'resolve_life_choice', chapter: 2, choice: 'keep' }],
      [{ type: 'talk_to_resident', resident_id: 'bistro_owner' }],
    ], today);
    expect(s.chapters[2].status).toBe('done');
    expect(project(s, today).clock.chapter_index).toBe(2);
    expect(project(s, today + 24 * HOUR).clock.chapter_index).toBe(3);
  });


  it.each([
    ['2026-03-07T12:00:00-08:00', '2026-03-07', '2026-03-08T04:00:00-07:00'],
    ['2026-10-31T12:00:00-07:00', '2026-10-31', '2026-11-01T04:00:00-08:00'],
  ])('next opening follows Los Angeles 04:00 across DST from %s', (iso, day, nextIso) => {
    const s = completeTutorial();
    s.clock.player_day_id = day;
    s.chapters[0].activated_day = day;
    const now = at(iso);
    const opening = at(nextIso);
    const d = derive(s, now, 'America/Los_Angeles', content);
    expect(d.next_chapter_opens_at).toBe(opening);
    expect(projectFarmState(s, opening - 1, 'America/Los_Angeles', content, plot).clock.chapter_index).toBe(0);
    const opened = projectFarmState(s, opening, 'America/Los_Angeles', content, plot);
    expect(opened.clock.chapter_index).toBe(1);
    expect(derive(opened, opening, 'America/Los_Angeles', content).next_chapter_opens_at).toBeNull();
  });
});
