/** SGODOT-232 S6: the pond template follows the map point (q(36)), casts use the pond the player entered, and the
 * per-skill daily XP cap (§4.3.4). */
import Fastify from 'fastify';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { gainXp, type P0Event } from '../../src/p0/progress.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T = Date.UTC(2026, 9, 8, 2);   // 10:00 Shanghai
const FERN = 'pond_san_francisco_03', BLOSSOM = 'pond_san_francisco_06';   // Fern Pond (beginner, Pond) / Blossom Pond (River)
const fresh = () => freshState(c, 'pond-rules-player', T, 7);
function step(s: P0State, cmd: P0Command, at = T) {
  const r = applyP0(c, s, cmd, at);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}

describe('pond templates by point and the cast check (q(36), SGODOT-232 S6)', () => {
  it('maps the six San Francisco ponds (SGODOT-270): Fern is the beginner pond; Fern, Willow and Reed are Pond, the others River', () => {
    const t = (id: string) => c.fishing.sites[c.fishing.places[id].site].template;
    expect(Object.keys(c.fishing.places)).toHaveLength(6);
    expect(['pond_san_francisco_03', 'pond_san_francisco_01', 'pond_san_francisco_05'].map(t)).toEqual(['Pond', 'Pond', 'Pond']);
    expect(['pond_san_francisco_06', 'pond_san_francisco_02', 'pond_san_francisco_04'].map(t)).toEqual(['River', 'River', 'River']);
    expect(Object.entries(c.fishing.places).filter(([, p]) => p.beginner).map(([id]) => id)).toEqual([FERN]);
    const v = viewOf(c, fresh(), T);
    expect(v.fishing.places[FERN]).toEqual({ name: 'Fern Pond', site: 'pond', template: 'Pond', beginner: true });
    expect(v.fishing.place).toBeNull();
  });

  it('a cast takes the template of the pond the player entered and ignores a site in the command', () => {
    let s = step(fresh(), { type: 'cast', space: 'pond', place: BLOSSOM, site: 'pond' } as P0Command);
    expect(s.cast).toMatchObject({ site: 'river', place: BLOSSOM });
    expect(viewOf(c, s, T).fishing.place).toBe(BLOSSOM);
    s = step(s, { type: 'reel', outcome: 'cancel' }, T + 10);
    // a pond command without a place keeps the pond (older clients send the space only)
    s = step(s, { type: 'cast', space: 'pond' }, T + 20);
    expect(s.cast).toMatchObject({ place: BLOSSOM });
  });

  it('is refused away from a pond, and leaving for another space forgets the pond', () => {
    expect(applyP0(c, fresh(), { type: 'cast' }, T)).toMatchObject({ ok: false, code: 'not_at_pond' });
    let s = step(fresh(), { type: 'cast', space: 'pond', place: FERN });
    s = step(s, { type: 'reel', outcome: 'cancel' }, T + 10);
    s = step(s, { type: 'read_inbox', keys: [], space: 'home' }, T + 20);   // any command from home
    expect(s.presence.place).toBeNull();
    expect(applyP0(c, s, { type: 'cast', space: 'pond' }, T + 30)).toMatchObject({ ok: false, code: 'not_at_pond' });
  });

  it('ignores ponds the server does not know or that are not in the home city, and forgets the last pond for them', () => {
    const s = fresh();
    for (const place of ['pond_los_angeles_05', 'pond_shanghai_05', 'pond_san_francisco_99', '']) {   // Shanghai: P0's city before SGODOT-270
      expect(applyP0(c, s, { type: 'cast', space: 'pond', place }, T)).toMatchObject({ ok: false, code: 'not_at_pond' });
    }
    s.presence.place = FERN;
    expect(applyP0(c, s, { type: 'cast', space: 'pond', place: 'pond_san_francisco_99' }, T)).toMatchObject({ ok: false, code: 'not_at_pond' });
    expect(applyP0(c, s, { type: 'cast', space: 'pond' }, T).ok).toBe(true);   // no place: the last pond stays
  });

  it('the entry read records the pond, so the first cast needs no place', async () => {
    const app = Fastify();
    const store = new P0Store(c);
    registerP0Routes(app, { content: c, store, now: () => T, dev: false });
    const headers = { 'x-p0-player': 'pond-rules-player' };
    try {
      const read = await app.inject({ method: 'GET', url: `/v1/p0/state?space=pond&place=${BLOSSOM}`, headers });
      expect(read.json().state.fishing.place).toBe(BLOSSOM);
      const cast = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'cast' } });
      expect(cast.json()).toMatchObject({ ok: true });
      expect(store.get('pond-rules-player', T).cast).toMatchObject({ site: 'river', place: BLOSSOM });
    } finally { await app.close(); }
  });
});

describe('the daily XP cap per skill (§4.3.4, SGODOT-232 S6)', () => {
  it('stops at 3,000 XP per skill per player day, says so, and opens again after 04:00', () => {
    const s = fresh();
    const ev: P0Event[] = [];
    gainXp(c, s, T, 'fishing', 2_990, 100, ev);
    expect(s.skills.fishing).toBe(2_990);
    gainXp(c, s, T, 'fishing', 50, 100, ev);
    expect(s.skills.fishing).toBe(3_000);
    expect(ev.at(-1)).toMatchObject({ kind: 'xp', skill: 'fishing', amount: 10, capped: true });
    gainXp(c, s, T, 'fishing', 50, 100, ev);
    expect(s.skills.fishing).toBe(3_000);
    expect(ev.filter(e => e.kind === 'xp' && e.capped)).toHaveLength(2);
    // another skill has its own cap
    gainXp(c, s, T, 'cooking', 40, 100, ev);
    expect(s.skills.cooking).toBe(40);
    // a first-time bonus the cap took says nothing (no "First cast · +10 XP" for 0)
    const capped = fresh();
    capped.day = { ...capped.day, key: '2026-10-08', xp: { fishing: 3_000 } };
    const cast = applyP0(c, capped, { type: 'cast', space: 'pond', place: FERN }, T);
    if (!cast.ok) throw new Error(cast.code);
    expect(cast.events.some(e => e.kind === 'first')).toBe(false);
    expect(cast.events).toContainEqual({ kind: 'xp', skill: 'fishing', amount: 0, percent: 100, capped: true });
    // part of it: 2,995 already today, so the first cast's 10 says +5
    const part = fresh();
    part.day = { ...part.day, key: '2026-10-08', xp: { fishing: 2_995 } };
    const cast5 = applyP0(c, part, { type: 'cast', space: 'pond', place: FERN }, T);
    if (!cast5.ok) throw new Error(cast5.code);
    expect(cast5.events.find(e => e.kind === 'first')).toMatchObject({ xp: 5 });
    expect(cast5.events).toContainEqual({ kind: 'xp', skill: 'fishing', amount: 5, percent: 100, capped: true });
    // the next player day (after the 04:00 rollover) starts from 0
    const next = step(s, { type: 'cast', space: 'pond', place: FERN }, T + 24 * 3_600_000);
    expect(next.day.xp).toEqual({ fishing: 10 });   // first cast +10
  });
});
