/** SGODOT-341 PR-C-s1 (341 c6f3189a): the guide framework's additions for 339's v3 table — the `guide_v3` header, the
 * home set's places and names, the new conditions, a read that settles, Pip's resend (q(217) ③), the fallback end. */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { guidePred, resendReady, validateGuide, type GuideContent } from '../../src/p0/guide.js';
import { homeSetOf } from '../../src/p0/home_city.js';
import { mapMarkers } from '../../src/p0/markers.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { maxEnergy } from '../../src/p0/rules.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';
import type { P0Event } from '../../src/p0/progress.js';

const T0 = Date.UTC(2026, 9, 26, 2);   // San Francisco 10-25 19:00 PDT: player day 10-25
const H = 3_600_000;
const SF = 'gn-5391959', SHANGHAI = 'gn-1796236';

/** A test table shaped like 339's v3 (the real one is PR-C-s2's). */
const TABLE: GuideContent = {
  steps: [
    { id: 't_sow_quick', done_on: { key: 'sow:crop_quick_radish', count: 2 }, row: { line: 'Sow 2 Quick Radishes' },
      marks: [{ plot: 'teach' }, { button: 'sow', pulse: true }], pip: "Hi, I'm Pip!" },
    { id: 't_water', done_on: { key: 'water:crop_quick_radish', count: 2 }, pip: 'Now water them.' },
    { id: 't_wait', done_if: { ripe: { crop_quick_radish: 2 } } },
    { id: 't_nadia_1', done_on: { key: 'enter:home:market' }, row: { line: 'Bring Nadia 1 Radish · {market}', go: 'home:market' },
      marks: [{ place: 'home:market', kind: 'request', why: 'Nadia · A Fresh Radish' }, { resident: 'res_nadia', kind: 'request' }] },
    { id: 't_meal', done_if: { any: [{ energy_full: true }, { keys: { eat: 1 } }] }, needs: [{ if: { fish: 1 }, else: ['rec_fish'] }] },
    { id: 't_gift', done_on: { key: 'gift:res_nadia' }, marks: [{ resident: 'res_nadia', kind: 'gift' }], needs: [{ if: { dish: 1 }, else: ['rec_cook'] }] },
    { id: 't_end', done_on: { key: 'ack:t_end' } },
  ],
  recover: [
    { id: 'rec_fish', row: { line: 'Catch 1 fish · {pond}', go: 'home:pond' }, marks: [{ place: 'home:pond', kind: 'request' }] },
    { id: 'rec_cook' },
  ],
  tips: {},
  pond_catch: false,
  resend: { item: 'seed_quick_radish', qty: 2, max: 2, line: 'Out of radishes? Here, two more quick ones.', radish: 'crop_radish',
    deliver: 'deliver:req_res_nadia_radish', dish: 'dish:dish_fish_soup', source: "Pip's seeds" },
  timeout_days: 2,
};

function content(): P0Content {
  const c = loadP0Content();
  c.guide = structuredClone(TABLE);
  return c;
}
function run(c: P0Content, s: P0State, cmd: P0Command, now = T0, events?: P0Event[]): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  events?.push(...r.events);
  return r.state;
}
const guided = (c: P0Content, player = 'guide-s1-player-01') => freshState(c, player, T0, 42, { guide: true });
const qty = (s: P0State, id: string) => s.bag.filter(x => x.id === id).reduce((n, x) => n + x.qty, 0);
const empty = (s: P0State, id: string) => { s.bag = s.bag.filter(x => x.id !== id); return s; };

describe('who starts the guide (341 c6f3189a ①)', () => {
  it('`guide_v3` starts it; `guide` alone (0.2.11) does not — that save stays legacy', async () => {
    const c = content();
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: false });
    const read = async (player: string, f: string) =>
      (await app.inject({ method: 'GET', url: '/v1/p0/state', headers: { 'x-p0-player': player, 'x-p0-features': f } })).json().state.guide;
    expect(await read('guide-s1-old-0211', 'choose_home,guide')).toMatchObject({ step: null, end: 'legacy' });
    expect(await read('guide-s1-new-0212', 'choose_home,guide_v3')).toMatchObject({ step: 't_sow_quick' });
    await app.close();
  });
});

describe('the home set (q(162))', () => {
  it('marks, `enter:` keys, Today\'s names and the go target follow the home city the player picked', () => {
    const c = content();
    for (const city of [SF, SHANGHAI]) {
      let s = freshState(c, `guide-s1-home-${city}`, T0, 42, { guide: true, pending: true });
      s = run(c, s, { type: 'choose_home', city, spot: 0, space: 'home' });
      const set = homeSetOf(c, s)!;
      s.guide!.step = 't_nadia_1';
      s.energy.value = 100;   // else the meal step after it passes at once (a full bar, q(215) S8)
      const v = viewOf(c, s, T0).guide as Record<string, any>;
      expect(v.row.go).toBe(set.market);
      expect(v.row.line).toMatch(/^Bring Nadia 1 Radish · \S/);
      expect(v.row.line).not.toContain('{market}');
      expect(v.marks[0]).toMatchObject({ place: set.market, kind: 'request', why: 'Nadia · A Fresh Radish' });
      expect(mapMarkers(c, s, T0).map(m => m.place)).toEqual([set.market]);
      s = run(c, s, { type: 'talk', resident: 'res_nadia', space: 'outpost', place: set.market });
      expect(s.guide!.step).toBe('t_meal');   // entering the home market (by its role) passed the step
    }
  });
  it('the San Francisco names: Mission Market Square, Fern Pond', () => {
    const c = content();
    const s = guided(c);
    s.guide!.step = 't_nadia_1';
    expect((viewOf(c, s, T0).guide as any).row.line).toBe('Bring Nadia 1 Radish · Mission Market Square');
    s.guide!.step = 't_meal';
    s.bag = s.bag.filter(x => !x.id.startsWith('fish_'));
    const v = viewOf(c, s, T0).guide as any;
    expect(v.recover).toBe('rec_fish');
    expect(v.row).toEqual({ line: 'Catch 1 fish · Fern Pond', go: 'pond_san_francisco_03' });
  });
});

describe('the new conditions', () => {
  const c = content();
  it('energy_full, fish, dish (not the Mystery Dish), common_crop', () => {
    const s = guided(c);
    s.energy.value = maxEnergy(c, s);
    expect(guidePred(c, s, { energy_full: true }, T0)).toBe(true);
    s.energy.value -= 1;
    expect(guidePred(c, s, { energy_full: true }, T0)).toBe(false);
    expect(guidePred(c, s, { energy_full: false }, T0)).toBe(true);
    expect(guidePred(c, s, { fish: 1 }, T0)).toBe(false);
    s.bag.push({ id: 'fish_crucian', qty: 1 });
    expect(guidePred(c, s, { fish: 1 }, T0)).toBe(true);
    s.bag.push({ id: 'dish_mystery', qty: 1 });
    expect(guidePred(c, s, { dish: 1 }, T0)).toBe(false);
    s.cabinet.push({ id: 'dish_fish_soup@good', qty: 1 } as P0State['cabinet'][number]);
    expect(guidePred(c, s, { dish: 1 }, T0)).toBe(true);
    expect(guidePred(c, s, { common_crop: 1 }, T0)).toBe(false);   // seeds are not crops
    s.storage.crop_radish = 1;
    expect(guidePred(c, s, { common_crop: 1 }, T0)).toBe(true);
  });
});

describe('a read settles a step passed by time (341 c6f3189a ③)', () => {
  it('Quick Radishes ripe while the player only watched: the plain state read moves the step on', async () => {
    const c = content();
    let now = T0;
    const store = new P0Store(c);
    const app = Fastify();
    registerP0Routes(app, { content: c, store, now: () => now, dev: false });
    const headers = { 'x-p0-player': 'guide-s1-read-01', 'x-p0-features': 'guide_v3', 'content-type': 'application/json' };
    const cmd = async (body: Record<string, unknown>) => (await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { ...body, space: 'home' } })).json();
    await app.inject({ method: 'GET', url: '/v1/p0/state', headers });
    const plots = store.peek('guide-s1-read-01')!.plots.filter(p => p.state === 'tilled').slice(0, 2).map(p => p.id);
    for (const plot of plots) expect((await cmd({ type: 'sow', plot, seed: 'seed_quick_radish' })).ok).toBe(true);
    for (const plot of plots) expect((await cmd({ type: 'water', plot })).ok).toBe(true);
    expect(store.peek('guide-s1-read-01')!.guide!.step).toBe('t_wait');
    now = T0 + 46_000;
    const read = (await app.inject({ method: 'GET', url: '/v1/p0/state', headers })).json();
    expect(read.state.guide.step).toBe('t_nadia_1');
    expect(store.peek('guide-s1-read-01')!.guide!.step).toBe('t_nadia_1');
    await app.close();
  });
});

describe('Pip on the farm (q(222)) and his resend (q(217) ③)', () => {
  it('his `!` until the first talk; the teaching plots are the two lowest empty tilled ones, then the sown ones', () => {
    const c = content();
    let s = guided(c);
    let v = viewOf(c, s, T0).guide as any;
    expect(v.pip).toEqual({ here: true, bang: true, line: "Hi, I'm Pip!", resend_left: 2 });
    const tilled = s.plots.filter(p => p.state === 'tilled').map(p => p.id);
    expect(v.marks.filter((m: any) => m.plot !== undefined).map((m: any) => m.plot)).toEqual(tilled.slice(0, 2));
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' });
    s = run(c, s, { type: 'sow', plot: tilled[3], seed: 'seed_quick_radish', space: 'home' });
    v = viewOf(c, s, T0).guide as any;
    expect(v.pip.bang).toBe(false);
    expect(v.marks.filter((m: any) => m.plot !== undefined).map((m: any) => m.plot)).toEqual([tilled[3], tilled[0]]);
  });
  it('out of radishes and quick seeds: his `!`, a talk on the farm gives 2, at most twice; not while any is left', () => {
    const c = content();
    let s = guided(c);
    s.guide!.step = 't_nadia_1';
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' });   // the first talk: nothing to give yet
    expect(qty(s, 'seed_quick_radish')).toBe(2);
    expect(resendReady(c, s)).toBe(false);
    empty(s, 'seed_quick_radish');
    expect(resendReady(c, s)).toBe(true);
    expect((viewOf(c, s, T0).guide as any).pip).toMatchObject({ bang: true, line: 'Out of radishes? Here, two more quick ones.' });
    // at the travel post it is the usual talk: the resend is the farm's
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'outpost', place: 'sh_post_1' });
    expect(qty(s, 'seed_quick_radish')).toBe(0);
    const events: P0Event[] = [];
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' }, T0, events);
    expect(qty(s, 'seed_quick_radish')).toBe(2);
    expect(events).toContainEqual({ kind: 'guide', action: 'resend', item: 'seed_quick_radish', qty: 2, bagged: 2, left: 1 });
    expect(resendReady(c, s)).toBe(false);
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' });   // seeds held: no second gift
    expect(qty(s, 'seed_quick_radish')).toBe(2);
    empty(s, 'seed_quick_radish');
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' });
    expect(s.guide!.n.resend).toBe(2);
    empty(s, 'seed_quick_radish');
    expect(resendReady(c, s)).toBe(false);   // both used
    expect((viewOf(c, s, T0).guide as any).pip).toMatchObject({ bang: false, resend_left: 0 });
  });
  it('a Radish held, a quick one growing, or one waiting in the Inbox: no resend; after the soup only a Common crop counts', () => {
    const c = content();
    const s = guided(c);
    empty(s, 'seed_quick_radish');
    s.bag.push({ id: 'crop_radish', qty: 1 });
    expect(resendReady(c, s)).toBe(false);
    empty(s, 'crop_radish');
    s.inbox.parcels.push({ key: 'k', id: 'seed_quick_radish', qty: 2, source: 'res_pip', created_at: T0, expires_at: T0 + 24 * H });
    expect(resendReady(c, s)).toBe(false);
    s.inbox.parcels = [];
    const plot = s.plots.find(p => p.state === 'tilled')!;
    plot.state = 'sown'; plot.crop = 'crop_quick_radish';
    expect(resendReady(c, s)).toBe(false);
    plot.state = 'tilled'; delete plot.crop;
    s.guide!.n['deliver:req_res_nadia_radish'] = 1;   // Nadia has her radish: now only the soup's crop matters
    s.storage.crop_lettuce = 1;
    expect(resendReady(c, s)).toBe(false);
    delete s.storage.crop_lettuce;
    expect(resendReady(c, s)).toBe(true);
    s.guide!.n['dish:dish_fish_soup'] = 1;
    expect(resendReady(c, s)).toBe(false);
  });
  it('a full bag: the two seeds wait as a parcel, and the retried talk does not give them twice', () => {
    const c = content();
    let s = guided(c);
    s.guide!.step = 't_nadia_1';
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' });
    empty(s, 'seed_quick_radish');
    // fill every slot with things that are neither a Radish nor a Common crop (they would stop the resend)
    for (const id of [...c.fish.map(f => f.id), ...Object.keys(c.goods)]) if (s.bag.length < s.bag_cap) s.bag.push({ id, qty: 1 });
    expect(s.bag.length).toBe(s.bag_cap);
    const events: P0Event[] = [];
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' }, T0, events);
    expect(s.inbox.parcels.filter(p => p.id === 'seed_quick_radish').map(p => p.qty)).toEqual([2]);
    expect(events).toContainEqual(expect.objectContaining({ kind: 'guide', action: 'resend', bagged: 0 }));
    s = run(c, s, { type: 'talk', resident: 'res_pip', space: 'home' });
    expect(s.inbox.parcels.filter(p => p.id === 'seed_quick_radish')).toHaveLength(1);
    expect(s.guide!.n.resend).toBe(1);
  });
});

describe('the fallback end (q(215))', () => {
  it('at the save\'s second home-day rollover the guide ends: timeout, Pip gone, the held first stall slot filled', () => {
    const c = content();
    let s = guided(c);
    const rollover2 = Date.UTC(2026, 9, 27, 11);   // 10-27 04:00 PDT: player day 10-27, two rollovers after 10-25
    s = run(c, s, { type: 'talk', resident: 'res_old_kai', space: 'outpost', place: 'sh_tackle_1' }, rollover2 - 60_000);
    expect(s.guide!.step).toBe('t_sow_quick');
    expect(s.boards.stall[0].req).toBeNull();   // the first slot held (no Pond Catch for a guided save)
    expect(s.boards.stall[0].refill_at).toBeGreaterThan(rollover2 + 60_000);
    const events: P0Event[] = [];
    s = run(c, s, { type: 'talk', resident: 'res_old_kai', space: 'outpost', place: 'sh_tackle_1' }, rollover2 + 60_000, events);
    expect(s.guide).toMatchObject({ step: null, end: 'timeout', ended_at: rollover2 + 60_000 });
    expect(events).toContainEqual({ kind: 'guide', action: 'end', from: 't_sow_quick', to: null, end: 'timeout' });
    expect(viewOf(c, s, rollover2 + 60_000).guide).toEqual({ step: null, end: 'timeout', ended_at: rollover2 + 60_000, pip: { here: false } });
    expect(s.boards.stall[0].refill_at).toBeLessThanOrEqual(rollover2 + 60_000);
    expect(resendReady(c, s)).toBe(false);
  });
});

describe('step changes in the command\'s events (§14.8.1) and the table check', () => {
  it('a command that passes steps says from → to; one that ends it says end', () => {
    const c = content();
    let s = guided(c);
    const tilled = s.plots.filter(p => p.state === 'tilled').map(p => p.id);
    const events: P0Event[] = [];
    s = run(c, s, { type: 'sow', plot: tilled[0], seed: 'seed_quick_radish', space: 'home' }, T0, events);
    expect(events.filter(e => e.kind === 'guide')).toEqual([]);
    s = run(c, s, { type: 'sow', plot: tilled[1], seed: 'seed_quick_radish', space: 'home' }, T0, events);
    expect(events.filter(e => e.kind === 'guide')).toEqual([{ kind: 'guide', action: 'step', from: 't_sow_quick', to: 't_water' }]);
  });
  it('validateGuide: the test table is clean; home roles and `teach` are known; speedup is no longer a key', () => {
    expect(validateGuide(content())).toEqual([]);
    const c = content();
    c.guide!.steps[0].marks = [{ place: 'home:mine' }, { plot: '3' }];
    c.guide!.steps[1].done_on = { key: 'speedup:crop_radish' };
    expect(validateGuide(c)).toEqual([
      'step t_sow_quick: unknown place home:mine', 'step t_sow_quick: unknown plot 3 (only "teach" / "teach1")', 'step t_water: unknown key speedup:crop_radish']);
  });
});
