/** 355 G (contract-efg §9.2, v4q(7) ③; v4q(9) ②): Pip's First Dig — shown from Lv3, done on reaching F3 of any mine
 * (or on the Lv3 upgrade for one who got there first), the Copper Sword and +5 with Pip once — and Pip's one line toward
 * the iron vein, said once on a talk with Pip. */
import Fastify from 'fastify';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { setGuide } from '../../src/p0/guide.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { dayKey } from '../../src/p0/rules.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';
import { nearestFreeVein } from '../../src/p0/wild.js';

const T = Date.UTC(2026, 10, 3, 2), DAY = 86400000, Q = 'wd-dev-quarry';
const c = loadP0Content(); c.profile.timezone = 'Asia/Shanghai';
const dig = c.mine.first_dig!;

function scenario(level: number) {
  let s = freshState(c, 'first-dig-test', T, 7), now = T;
  s.created_at = T - 30 * DAY; s.homestead.level = level;
  const send = (cmd: Record<string, unknown>) => {
    now += 1000;
    const r = applyP0(c, s, { day: dayKey(c, s, now), ...cmd } as P0Command, now);
    if (!r.ok) throw new Error(JSON.stringify({ code: r.code, detail: r.detail }));
    s = r.state; return r.events;
  };
  const clear = () => {
    const at = s.mine.day!.at!, floor = s.mine.day!.floors[`${at.mine}:${at.floor}`];
    for (let i = 0, tries = 0; i < floor.mobs.length; i++) {
      while (s.mine.day!.floors[`${at.mine}:${at.floor}`].mobs[i] > 0) {
        if (++tries > 1000) throw new Error('clear did not terminate');
        send({ type: 'mine_attack', space: 'mine', floor: at.floor, targets: [i] });
      }
    }
  };
  /** Clear this floor and take the ladder down; the arrival's events. */
  const down = () => { clear(); return send({ type: 'mine_floor', space: 'mine', to: s.mine.day!.at!.floor + 1 }); };
  /** F1, then down the ladder to `to`; the events of each arrival. */
  const walk = (to: number) => {
    const out = [send({ type: 'mine_enter', space: 'mine', mine: Q })];
    while (s.mine.day!.at!.floor < to) out.push(down());
    return out;
  };
  const upgrade = () => {
    const next = c.homestead.levels.find(l => l.level === s.homestead.level + 1)!;
    s.skills = { farming: 99_999, fishing: 99_999, cooking: 99_999 };
    for (const [id, n] of next.materials) s.storage[id] = (s.storage[id] ?? 0) + n;
    s.coins = next.coins + 40;
    return send({ type: 'homestead_upgrade' });
  };
  const view = () => viewOf(c, s, now) as unknown as { first_dig: unknown; pip_line: unknown };
  return { send, walk, down, upgrade, view, get s(): P0State { return s; } };
}
const pip = (s: P0State) => s.residents[dig.giver]?.affinity ?? 0;
const kinds = (ev: P0Event[]) => ev.map(e => e.kind);

describe('Pip\'s First Dig (contract-efg §9.2)', () => {
  it('the content: res_pip, Floor 3, from Lv3, the Copper Sword and +5', () => {
    expect(dig).toEqual({ giver: 'res_pip', floor: 3, gate: { homestead: 3 }, reward: { weapon: 'weapon_copper_sword', affinity: 5 },
      lines: { pip_vein: "Copper's a start! There's iron at %s. Get down to Floor 10!" } });
  });

  it('below Lv3 it is not shown and reaching F3 does nothing', () => {
    const x = scenario(2);
    expect(x.view().first_dig).toBeNull();
    const arrivals = x.walk(3);
    expect(arrivals.flat().some(e => e.kind === 'first_dig')).toBe(false);
    expect(x.s.rewards).not.toContain('first_dig');
    expect(x.view().first_dig).toBeNull();
    expect(x.s.gear.weapons).toEqual(['weapon_wooden_sword']);
  });

  it('from Lv3 it counts the deepest floor; reaching F3 finishes it there: rewards, the sword in hand, +5 with Pip', () => {
    const x = scenario(3);
    expect(x.view().first_dig).toEqual({ giver: 'res_pip', floor: 3, have: 0, done: false });
    const [f1, f2, f3] = x.walk(3);
    expect([...kinds(f1), ...kinds(f2)]).not.toContain('first_dig');
    expect(f3.find(e => e.kind === 'first_dig')).toEqual({ kind: 'first_dig', done: true, weapon: 'weapon_copper_sword', equipped: true });
    expect(f3.find(e => e.kind === 'gear')).toEqual({ kind: 'gear', item: 'weapon_copper_sword', equipped: true });
    expect(f3.find(e => e.kind === 'affinity')).toMatchObject({ resident: 'res_pip', delta: 5, total: 5, reason: 'first_dig' });
    expect(kinds(f3).indexOf('mine_record')).toBeLessThan(kinds(f3).indexOf('first_dig'));
    expect(x.s.rewards).toContain('first_dig');
    expect(x.s.gear).toMatchObject({ weapons: ['weapon_wooden_sword', 'weapon_copper_sword'], weapon: 'weapon_copper_sword' });
    expect(x.view().first_dig).toEqual({ giver: 'res_pip', floor: 3, have: 3, done: true });   // done stays shown (v4q(9))
    expect((viewOf(c, x.s, T + DAY) as unknown as { mine: { weapon: { attack: number } } }).mine.weapon.attack).toBe(5);
  });

  it('counts the deepest floor of any mine while it is shown', () => {
    const x = scenario(3);
    x.walk(2);
    expect(x.view().first_dig).toEqual({ giver: 'res_pip', floor: 3, have: 2, done: false });
  });

  it('given once: a deeper record later gives nothing again', () => {
    const x = scenario(3);
    x.walk(3);
    const points = pip(x.s);
    const ev = x.down();
    expect(kinds(ev)).toContain('mine_record');
    expect(kinds(ev)).not.toContain('first_dig');
    expect(pip(x.s)).toBe(points);
    expect(x.s.gear.weapons.filter(w => w === 'weapon_copper_sword')).toHaveLength(1);
    expect(x.s.rewards.filter(r => r === 'first_dig')).toHaveLength(1);
  });

  it('one who reached F3 before Lv3 has it done on the Lv3 upgrade itself', () => {
    const x = scenario(2);
    x.s.mine.records[Q] = { deepest: 4, guards: [], first_at: T - DAY };
    const ev = x.upgrade();
    expect(x.s.homestead.level).toBe(3);
    expect(kinds(ev)).toEqual(expect.arrayContaining(['homestead', 'first_dig', 'gear', 'affinity']));
    expect(kinds(ev).indexOf('homestead')).toBeLessThan(kinds(ev).indexOf('first_dig'));
    expect(x.view().first_dig).toEqual({ giver: 'res_pip', floor: 3, have: 3, done: true });
    expect(x.s.gear.weapon).toBe('weapon_copper_sword');
  });

  it('an upgrade to Lv3 short of F3 only shows it; other upgrades leave it alone', () => {
    const x = scenario(2);
    x.s.mine.records[Q] = { deepest: 1, guards: [], first_at: T - DAY };
    expect(kinds(x.upgrade())).not.toContain('first_dig');
    expect(x.view().first_dig).toEqual({ giver: 'res_pip', floor: 3, have: 1, done: false });
  });

  it('an Iron Sword in hand stays there: the Copper Sword only joins the slot', () => {
    const x = scenario(2);
    x.s.gear.weapons.push('weapon_iron_sword'); x.s.gear.weapon = 'weapon_iron_sword';
    x.s.mine.records[Q] = { deepest: 3, guards: [], first_at: T - DAY };
    const ev = x.upgrade();
    expect(ev.find(e => e.kind === 'first_dig')).toMatchObject({ equipped: false });
    expect(ev.find(e => e.kind === 'gear')).toEqual({ kind: 'gear', item: 'weapon_copper_sword', equipped: false });
    expect(x.s.gear).toMatchObject({ weapon: 'weapon_iron_sword' });
    expect(x.s.gear.weapons).toContain('weapon_copper_sword');
  });

  it('does not care about Pip\'s request line: shown and done with one of Pip\'s requests taken', () => {
    const x = scenario(3);
    x.send({ type: 'accept', request: 'req_res_pip_1' });
    expect(x.s.residents.res_pip.req?.id).toBe('req_res_pip_1');
    expect(x.view().first_dig).toMatchObject({ done: false });
    x.walk(3);
    expect(x.s.rewards).toContain('first_dig');
    expect(x.s.residents.res_pip.req?.id).toBe('req_res_pip_1');   // the request is untouched
  });

  it('the playtest route that sets the Homestead level settles it as the upgrade would (后裔 on #697)', async () => {
    const player = 'first-dig-dev', s = freshState(c, player, T);
    s.mine.records[Q] = { deepest: 3, guards: [], first_at: T - DAY };
    const dir = mkdtempSync(path.join(tmpdir(), 'zhouyu-first-dig-')), store = new P0Store(c, path.join(dir, 'state.json'));
    const app = Fastify();
    store.put(s);
    registerP0Routes(app, { content: c, store, now: () => T, dev: true });
    try {
      await app.ready();
      const r = (await app.inject({ method: 'POST', url: '/v1/p0/dev/blackjack', headers: { 'x-p0-player': player }, payload: { homestead: 3 } })).json();
      expect(r).toMatchObject({ ok: true, state: { first_dig: { have: 3, done: true }, gear: { weapon: 'weapon_copper_sword' } } });
      expect(store.peek(player)!.rewards).toContain('first_dig');
    } finally { await app.close(); rmSync(dir, { recursive: true, force: true }); }
  });
});

describe('Pip\'s line toward the iron vein (v4q(9) ②)', () => {
  const done = () => {
    const x = scenario(2);
    x.s.mine.records[Q] = { deepest: 3, guards: [], first_at: T - DAY };
    x.upgrade();
    return x;
  };

  it('none before First Dig is done', () => {
    const x = scenario(3);
    expect(x.view().pip_line).toBeNull();
  });

  it('once done: the nearest free iron vein, the very one Today\'s vein row names', () => {
    const x = done(), vein = nearestFreeVein(c, x.s, 'iron_ore')!;
    expect(vein).not.toBeNull();
    expect(x.view().pip_line).toEqual({ key: 'pip_vein', vein: vein.id, name: vein.name });
  });

  it('a talk with Pip says it once, kept in seen; a talk with anyone else does not', () => {
    const x = done();
    x.send({ type: 'talk', resident: 'res_nadia' });
    expect(x.view().pip_line).not.toBeNull();
    x.send({ type: 'talk', resident: 'res_pip' });
    expect(x.s.seen).toContain('line:pip_vein');
    expect(x.view().pip_line).toBeNull();
    x.send({ type: 'talk', resident: 'res_pip' });
    expect(x.s.seen!.filter(k => k === 'line:pip_vein')).toHaveLength(1);
  });

  it('said even on a talk that gives no chat points (the day\'s first chat already had)', () => {
    const x = done();
    x.send({ type: 'talk', resident: 'res_pip' });   // the day's chat, and the line
    x.s.seen = x.s.seen!.filter(k => k !== 'line:pip_vein');
    const ev = x.send({ type: 'talk', resident: 'res_pip' });
    expect(kinds(ev)).not.toContain('affinity');
    expect(x.s.seen).toContain('line:pip_vein');
  });

  it('while the guide is on, Pip\'s guide line goes first: none given, a talk keeps it; the first talk after the guide says it (不知火舞)', () => {
    const x = done();
    expect(setGuide(c, x.s, 't_gift', T)).toBeNull();
    expect(x.view().pip_line).toBeNull();
    x.send({ type: 'talk', resident: 'res_pip' });
    expect(x.s.seen ?? []).not.toContain('line:pip_vein');   // not lost: still due
    expect(setGuide(c, x.s, 'end', T)).toBeNull();
    expect(x.view().pip_line).toMatchObject({ key: 'pip_vein' });
    x.send({ type: 'talk', resident: 'res_pip' });
    expect(x.s.seen).toContain('line:pip_vein');
    expect(x.view().pip_line).toBeNull();
  });

  it('not said once that vein\'s deepest has reached Floor 10, nor with no free iron vein', () => {
    const x = done(), vein = nearestFreeVein(c, x.s, 'iron_ore')!;
    x.s.mine.records[vein.id] = { deepest: 10, guards: [], first_at: T };
    expect(x.view().pip_line).toBeNull();
    x.send({ type: 'talk', resident: 'res_pip' });
    expect(x.s.seen ?? []).not.toContain('line:pip_vein');
    const y = done();
    y.s.travel.wild_near3 = y.s.travel.wild_near3!.filter(id => id !== vein.id);
    expect(y.view().pip_line).toBeNull();
  });
});
