import { describe, expect, it } from 'vitest';
import type { Command } from '../../src/domain/commands.js';
import { derive } from '../../src/domain/derive.js';
import { projectFarmState } from '../../src/domain/progress.js';
import type { FarmState } from '../../src/domain/state.js';
import { BEDS, HOUR, SH, T0, at, blueprint, content, freshFarm, run, runAll } from './helpers.js';
import { ledgerScript } from '../fixtures/build_ledger.js';

const six = BEDS.slice(0, 6);
const remaining = BEDS.slice(6);
const project = (s: FarmState, now = T0) => projectFarmState(s, now, SH, content, blueprint);
const chapterEntries = (s: FarmState) => s.handbook.filter(entry => entry.kind === 'chapter_done');

function activeChapter(index: number): FarmState {
  const s = freshFarm();
  s.clock.chapter_index = index;
  s.chapters[index].status = 'active';
  s.chapters[index].activated_day = s.clock.player_day_id;
  s.inventory.produce = { R: 6, L: 6, C: 6, H: 6 };
  return s;
}

function harvestedTutorial(earlyLettuce = false): FarmState {
  const steps: [Command, number?][] = [
    [{ type: 'clear_cells', cell_ids: BEDS }],
    [{ type: 'till_cells', cell_ids: BEDS }],
    [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bound' }],
  ];
  if (earlyLettuce) steps.push([{ type: 'sow_cells', cell_ids: remaining, crop: 'L', lot: 'bound' }]);
  steps.push([{ type: 'apply_care', cell_ids: earlyLettuce ? BEDS : six, kind: 'water' }]);
  steps.push([{ type: 'harvest_cells', cell_ids: six }, T0 + 180_000]);
  return runAll(freshFarm(), steps);
}

function completeTutorial(): FarmState {
  return runAll(harvestedTutorial(), [
    [{ type: 'buy_seeds', crop: 'R', qty: 6 }],
    [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bought' }],
    [{ type: 'sow_cells', cell_ids: remaining, crop: 'L', lot: 'bound' }],
    [{ type: 'apply_care', cell_ids: BEDS, kind: 'water' }],
  ], T0 + 180_000);
}

function prepareCare(s: FarmState, kind: 'rain' | 'wind'): FarmState {
  const next = structuredClone(s);
  next.clock.field_condition = kind;
  next.cells[BEDS[0]].state = 'tilled';
  return runAll(next, [[{ type: 'sow_cells', cell_ids: [BEDS[0]], crop: 'R', lot: 'bound' }]]);
}

describe('D0 event-backed next batch', () => {
  it('requires nine distinct newly sown and cared cells after the first harvest', () => {
    let s = harvestedTutorial();
    expect(s.chapters[0].step_flags).toMatchObject({ farm_created: true, first_harvest: true });
    expect(s.chapters[0].status).toBe('active');
    s = runAll(s, [
      [{ type: 'buy_seeds', crop: 'R', qty: 6 }],
      [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bought' }],
      [{ type: 'sow_cells', cell_ids: remaining, crop: 'L', lot: 'bound' }],
      [{ type: 'apply_care', cell_ids: BEDS.slice(0, 8), kind: 'water' }],
    ], T0 + 180_000);
    expect(s.chapters[0].status).toBe('active');
    const last = run(s, { type: 'apply_care', cell_ids: [BEDS[8]], kind: 'water' }, T0 + 180_000);
    expect(last.ok).toBe(true);
    if (!last.ok) return;
    expect(last.state.chapters[0].status).toBe('done');
    expect(last.state.chapters[0].step_flags.next_batch_sown_and_cared).toBe(true);
    expect(last.events.filter(event => event.type === 'chapter_done')).toEqual([{ type: 'chapter_done', chapter: 0 }]);
    expect(last.state.clock.chapter_index).toBe(0);
  });

  it('old lettuce plus six replanted radishes cannot impersonate a nine-cell next batch', () => {
    const s = runAll(harvestedTutorial(true), [
      [{ type: 'buy_seeds', crop: 'R', qty: 6 }],
      [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bought' }],
      [{ type: 'apply_care', cell_ids: six, kind: 'water' }],
    ], T0 + 180_000);
    expect(BEDS.every(id => s.cells[id].state === 'growing')).toBe(true);
    expect(s.chapters[0].status).toBe('active');
    expect(project(s, T0 + HOUR).chapters[0].status).toBe('active');
    expect(s.chapters[0].step_flags[`next_batch_sown:${remaining[0]}`]).toBeUndefined();
  });

  it('a legacy farm with harvested crops and nine growing slots gains no fabricated sow evidence', () => {
    const s = completeTutorial();
    s.chapters[0].status = 'active';
    s.chapters[0].step_flags = {};
    s.handbook = s.handbook.filter(entry => entry.kind !== 'chapter_done');
    const p = project(s);
    expect(p.chapters[0].step_flags.first_harvest).toBe(true);
    expect(p.chapters[0].status).toBe('active');
    expect(chapterEntries(p)).toEqual([]);
    expect(s.chapters[0].step_flags).toEqual({});
  });

  it('harvesting a partial next batch clears its live-cycle evidence', () => {
    let s = runAll(harvestedTutorial(), [
      [{ type: 'buy_seeds', crop: 'R', qty: 6 }],
      [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bought' }],
      [{ type: 'apply_care', cell_ids: six, kind: 'water' }],
    ], T0 + 180_000);
    s = runAll(s, [[{ type: 'harvest_cells', cell_ids: six }]], T0 + 5 * HOUR);
    for (const id of six) {
      expect(s.chapters[0].step_flags[`next_batch_sown:${id}`]).toBeUndefined();
      expect(s.chapters[0].step_flags[`next_batch_cared:${id}`]).toBeUndefined();
    }
    expect(s.chapters[0].status).toBe('active');
  });

  it('rejected care cannot record even a partial batch or mutate the input', () => {
    const s = runAll(harvestedTutorial(), [
      [{ type: 'buy_seeds', crop: 'R', qty: 6 }],
      [{ type: 'sow_cells', cell_ids: six, crop: 'R', lot: 'bought' }],
    ], T0 + 180_000);
    const before = structuredClone(s);
    const rejected = run(s, { type: 'apply_care', cell_ids: BEDS, kind: 'water' }, T0 + 180_000);
    expect(rejected.ok).toBe(false);
    expect(s).toEqual(before);
    expect(s.chapters[0].step_flags[`next_batch_cared:${BEDS[0]}`]).toBeUndefined();
  });
});

describe('chapter-specific completion facts', () => {
  it('D1 needs actual rain care and the bistro lettuce request', () => {
    let s = prepareCare(activeChapter(1), 'rain');
    expect(run(s, { type: 'apply_care', cell_ids: [BEDS[0]], kind: 'water' }).ok).toBe(false);
    s = runAll(s, [[{ type: 'apply_care', cell_ids: [BEDS[0]], kind: 'drain' }]]);
    expect(s.chapters[1].status).toBe('active');
    expect(s.chapters[1].step_flags.rain_care_done).toBe(true);
    s = runAll(s, [[{ type: 'submit_request', request_id: 'd1_bistro_lettuce' }]]);
    expect(s.chapters[1].status).toBe('done');
  });

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

  it('D5 completes with an unpaid intent and wind care, without inventing purchase money', () => {
    let s = prepareCare(activeChapter(5), 'wind');
    s.wallet = 0;
    s = runAll(s, [[{ type: 'set_growth_intent', choice: 'field' }]]);
    expect(s.chapters[5].status).toBe('active');
    s = runAll(s, [[{ type: 'apply_care', cell_ids: [BEDS[0]], kind: 'shelter' }]]);
    expect(s.chapters[5].status).toBe('done');
    expect(s.wallet).toBe(0);
    expect(s.growth_choice.purchase).toBeNull();
    expect(s.beds_unlocked).toBe(3);
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
  it('the first D4 projection includes engineering submitted through real commands during D3', () => {
    let s = freshFarm();
    let day = 0;
    let within = 0;
    for (const step of ledgerScript('tool', 'life')) {
      if (step.day !== day) { day = step.day; within = 0; }
      s = runAll(s, [[step.cmd]], T0 + day * 24 * HOUR + within++ * 300_000);
      if (day === 3 && s.chapters[3].status === 'done') break;
    }
    expect(s.clock.chapter_index).toBe(3);
    s = runAll(s, [
      [{ type: 'reserve_engineering', items: { C: 1 } }],
      [{ type: 'submit_engineering', items: { C: 1 } }],
    ], T0 + 3 * 24 * HOUR + within * 300_000);
    const p = project(s, T0 + 4 * 24 * HOUR);
    expect(p.chapters[4].step_flags.engineering_first_submitted).toBe(true);
    expect(p.chapters[4].status).toBe('active');
    expect(p.clock.chapter_index).toBe(4);
    expect(project(p, T0 + 4 * 24 * HOUR)).toEqual(p);
    expect(s.chapters[4].status).toBe('locked');
  });

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
    let s = project(prepareCare(activeChapter(1), 'rain'), today);
    s = runAll(s, [[{ type: 'apply_care', cell_ids: [BEDS[0]], kind: 'drain' }]], today);
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

  it('opening D6 never builds the nursery before its material quota is submitted', () => {
    let s = prepareCare(activeChapter(5), 'wind');
    s = runAll(s, [
      [{ type: 'set_growth_intent', choice: 'tool' }],
      [{ type: 'apply_care', cell_ids: [BEDS[0]], kind: 'shelter' }],
    ]);
    expect(project(s, T0 + 24 * HOUR).nursery.stage).not.toBe('built');
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
    expect(projectFarmState(s, opening - 1, 'America/Los_Angeles', content, blueprint).clock.chapter_index).toBe(0);
    const opened = projectFarmState(s, opening, 'America/Los_Angeles', content, blueprint);
    expect(opened.clock.chapter_index).toBe(1);
    expect(derive(opened, opening, 'America/Los_Angeles', content).next_chapter_opens_at).toBeNull();
  });
});
