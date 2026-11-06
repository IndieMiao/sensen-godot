/** q(218) (SGODOT-338 / 344): Nadia's two teaching requests — A Fresh Radish (hand in 1) and Six Radishes (harvest 6
 * after accepting) — only for a save that went into the new-player guide and has not started her line. They sit outside
 * her `requests`, so `next` and req_res_nadia_1–4 never move; done ones are kept by id (intro_done). */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { requestState } from '../../src/p0/residents.js';

const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const H = 3_600_000, DAY = 24 * H;
const NADIA = 'res_nadia', ONE = 'req_res_nadia_radish', FOUR = 'req_res_nadia_six_radishes';   // Four Radishes (v4q(4) ⑥ 丁20); the id kept

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
/** A save as 341 leaves it: in the guide (ended or not), or legacy (made before the guide, or by a client without it). */
function save(guide: 'on' | 'done' | 'legacy' | 'none'): P0State {
  const s = { ...freshState(c, 'player-nadia-intro', T0, 3), created_at: T0 - 8 * DAY };
  if (guide === 'none') delete s.guide;
  else s.guide = guide === 'on' ? { step: 't_nadia_1', n: {}, at: T0 } : { step: null, n: {}, end: guide, at: T0 };
  return s;
}
const nadia = (s: P0State, now = T0) => requestState(c, s, NADIA, now);
/** Radish plots ready to harvest: plot ids from 0. */
function ripe(s: P0State, n: number, now = T0): number[] {
  const ids = s.plots.slice(0, n).map(p => p.id);
  for (const p of s.plots.slice(0, n)) Object.assign(p, { state: 'growing', crop: 'crop_radish', xp_pct: 100, ready_at: now - 1 });
  return ids;
}
const harvest = (s: P0State, ids: number[], now = T0) => ids.reduce((acc, id) => {
  const r = step(acc.s, { type: 'harvest', plot: id }, now);
  return { s: r.s, ev: [...acc.ev, ...r.ev] };
}, { s, ev: [] as P0Event[] });

describe('Nadia\'s teaching requests (q(218))', () => {
  it('a save without the guide starts her line at Potatoes, Please as before', () => {
    for (const g of ['legacy', 'none'] as const) {
      const st = nadia(save(g));
      expect(st.req?.id, g).toBe('req_res_nadia_1');
      expect(st.state, g).toBe('open');
    }
  });

  it('A Fresh Radish: Stranger, one radish, 20 coins (4 floor + 16 bonus), +5, the Fresh Fish Soup page; next stays 0', () => {
    let s = save('on');
    expect(nadia(s)).toMatchObject({ req: { id: ONE }, state: 'open' });
    s = step(s, { type: 'accept', request: ONE }).s;
    s.bag.push({ id: 'crop_radish', qty: 3 });
    const coins = s.coins, bonus = s.day.bonus ?? 0;
    const r = step(s, { type: 'deliver', request: ONE });
    expect(r.s.coins - coins).toBe(20);
    expect(count(r.s.bag, 'crop_radish')).toBe(2);
    expect(r.ev).toContainEqual({ kind: 'request', id: ONE, status: 'done', coins: 20, bonus: 16 });
    expect((r.s.day.bonus ?? 0) - bonus).toBe(16);
    expect(r.ev).toContainEqual(expect.objectContaining({ kind: 'affinity', resident: NADIA, delta: 5, reason: 'request' }));
    expect(r.ev).toContainEqual({ kind: 'recipe', page: 'dish_fish_soup', from: 'request', resident: NADIA, request: ONE });
    expect(r.s.cookbook).toContain('dish_fish_soup');
    expect(count(r.s.bag, 'recipe:dish_fish_soup')).toBe(0);
    expect(r.s.residents[NADIA]).toMatchObject({ next: 0, intro_done: [ONE], req: null });
    expect(r.s.req_done).toContain(ONE);
    expect(refuse(r.s, { type: 'deliver', request: ONE })).toMatchObject({ ok: false });
  });

  it('Four Radishes opens at Acquainted right away (no 24 h, same day) and counts only radishes harvested after accepting', () => {
    let s = save('on');
    s = step(s, { type: 'accept', request: ONE }).s;
    s.bag.push({ id: 'crop_radish', qty: 1 });
    s = step(s, { type: 'deliver', request: ONE }, T0 + 60_000).s;
    expect(nadia(s, T0 + 2 * 60_000)).toMatchObject({ req: { id: FOUR }, state: 'stage', need_stage: 'Acquainted' });
    s.residents[NADIA].affinity = 17;   // first chat +2, this request +5, the first gift +10 (q(220))
    expect(nadia(s, T0 + 2 * 60_000)).toMatchObject({ req: { id: FOUR }, state: 'open' });
    // what is harvested before accepting does not count (the known cost, q(218) ②)
    s = harvest(s, ripe(s, 2, T0 + 3 * 60_000), T0 + 3 * 60_000).s;
    s = step(s, { type: 'accept', request: FOUR }, T0 + 4 * 60_000).s;
    expect(viewOf(c, s, T0 + 4 * 60_000).residents[NADIA].request).toMatchObject({ id: FOUR, kind: 'harvest', item: 'crop_radish', qty: 4, have: 0, ready: false });
    expect(refuse(s, { type: 'deliver', request: FOUR }, T0 + 4 * 60_000)).toMatchObject({ ok: false, code: 'not_ready', detail: { progress: 0, need: 4 } });
    // q(134): `Four Radishes 2/4` as they come in
    let r = harvest(s, ripe(s, 2, T0 + 5 * 60_000), T0 + 5 * 60_000);
    expect(r.ev.filter(e => e.kind === 'request_progress')).toEqual([
      { kind: 'request_progress', id: FOUR, have: 1, qty: 4 }, { kind: 'request_progress', id: FOUR, have: 2, qty: 4 }]);
    s = r.s;
    s.bag = s.bag.filter(b => b.id !== 'crop_radish');   // sold or cooked: harvested ones still count
    r = harvest(s, ripe(s, 5, T0 + 6 * 60_000), T0 + 6 * 60_000);
    expect(r.ev.filter(e => e.kind === 'request_progress').at(-1)).toEqual({ kind: 'request_progress', id: FOUR, have: 4, qty: 4, done: true });
    expect(r.s.residents[NADIA].req?.progress).toBe(4);   // capped at qty
    s = r.s;
    const radishes = count(s.bag, 'crop_radish'), coins = s.coins;
    const d = step(s, { type: 'deliver', request: FOUR }, T0 + 7 * 60_000);
    expect(count(d.s.bag, 'crop_radish')).toBe(radishes);   // nothing handed in
    expect(d.s.coins - coins).toBe(20);
    expect(d.ev).toContainEqual({ kind: 'request', id: FOUR, status: 'done', coins: 20, bonus: 20 });
    expect(d.s.residents[NADIA]).toMatchObject({ next: 0, intro_done: [ONE, FOUR] });
    // ③ then her line from Potatoes, Please, right away (q(268); 24 h after the second teaching request before 0.2.18)
    expect(nadia(d.s, T0 + 8 * 60_000)).toMatchObject({ req: { id: 'req_res_nadia_1' }, state: 'open' });
  });

  it('only a harvest request for that crop counts, and only once accepted', () => {
    let s = save('on');
    s.residents[NADIA] = { affinity: 20, chat_day: '', gift_day: '', next: 0, req: null, done_day: '', intro_done: [ONE] };
    s = step(s, { type: 'accept', request: FOUR }).s;
    const ids = ripe(s, 2);
    s.plots[1].crop = 'crop_lettuce';
    s = harvest(s, ids).s;
    expect(s.residents[NADIA].req?.progress).toBe(1);
  });

  it('a Quick Radish harvested after accepting counts as a Radish (q(217) / q(218), 周瑜 on #488)', () => {
    let s = save('on');
    s.residents[NADIA] = { affinity: 20, chat_day: '', gift_day: '', next: 0, req: null, done_day: '', intro_done: [ONE] };
    s = step(s, { type: 'accept', request: FOUR }).s;
    s.bag.push({ id: 'seed_quick_radish', qty: 1 });
    const id = s.plots.find(p => p.state === 'tilled')!.id;
    s = step(s, { type: 'sow', plot: id, seed: 'seed_quick_radish' }).s;
    s = step(s, { type: 'water', plot: id }, T0 + 1_000).s;
    const r = step(s, { type: 'harvest', plot: id }, T0 + 60_000);
    expect(r.ev).toContainEqual({ kind: 'request_progress', id: FOUR, have: 1, qty: 4 });
    expect(r.s.residents[NADIA].req?.progress).toBe(1);
  });

  it('an undone teaching request stays once the guide has ended', () => {
    const s = save('done');
    expect(nadia(s)).toMatchObject({ req: { id: ONE }, state: 'open' });
  });

  it('a guided save that already started her line gets none: next past 0, or Potatoes, Please taken', () => {
    const past = save('on');
    past.residents[NADIA] = { affinity: 20, chat_day: '', gift_day: '', next: 1, req: null, done_day: '' };
    expect(nadia(past).req?.id).toBe('req_res_nadia_2');
    const taken = save('on');
    taken.residents[NADIA] = { affinity: 0, chat_day: '', gift_day: '', next: 0, req: { id: 'req_res_nadia_1', at: T0, progress: 0 }, done_day: '' };
    expect(nadia(taken)).toMatchObject({ req: { id: 'req_res_nadia_1' }, state: 'accepted' });
    expect(refuse(taken, { type: 'accept', request: ONE })).toMatchObject({ ok: false, code: 'not_available' });
  });

  it('a save without the guide cannot take a teaching request', () => {
    expect(refuse(save('legacy'), { type: 'accept', request: ONE })).toMatchObject({ ok: false, code: 'not_available' });
  });

  it('the teaching requests stay out of her line: four requests, nadia_1–4 in order', () => {
    expect(c.residents[NADIA].requests.map(q => q.id)).toEqual(['req_res_nadia_1', 'req_res_nadia_2', 'req_res_nadia_3', 'req_res_nadia_4']);
    expect(c.residents[NADIA].intro_requests?.map(q => [q.id, q.stage, q.need.kind, q.qty, q.coins])).toEqual([
      [ONE, 'Stranger', 'crop', 1, 20], [FOUR, 'Acquainted', 'harvest', 4, 20]]);
  });
});
