import Fastify from 'fastify';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { grantItems, PARCEL_LIFETIME_MS, settleParcels } from '../../src/p0/parcels.js';
import { gainXp, type P0Event } from '../../src/p0/progress.js';
import { applyP0, count, type P0Command } from '../../src/p0/reducer.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { freshState, upgradeState, type P0State } from '../../src/p0/state.js';
import { P0Store } from '../../src/p0/store.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const T = Date.UTC(2026, 9, 5, 2);
const player = 'parcel-test-player';
function full() {
  const s = freshState(c, player, T);
  s.presence.place = 'pond_san_francisco_03';   // at Fern Pond, so a cast reaches the creel check
  s.bag = Array.from({ length: 25 }, () => ({ id: 'fish_crucian', qty: 10 }));
  return s;
}
function grant(s: P0State, key = 'test-reward', gifts: [string, number][] = [['crop_herb', 3]], now = T) {
  const events: P0Event[] = [];
  grantItems(c, s, now, key, 'Test reward', gifts, events);
  return events;
}
function step(s: P0State, cmd: P0Command, now = T) {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code}`);
  return r.state;
}

describe('P0 passive rewards (§10.4.8, q(45); SGODOT-232 S1, rescued from SGODOT-158)', () => {
  it('keeps the entire Fishing Lv2 gift at full capacity, with the recipe in the Cookbook', () => {
    const s = full();
    const bag = structuredClone(s.bag);
    const events: P0Event[] = [];
    gainXp(c, s, T, 'fishing', 70, 100, events);
    expect(s.bag).toEqual(bag);
    expect(s.inbox.parcels.map(p => [p.id, p.qty])).toEqual([['bait_worm', 3], ['wild_herb', 3]]);
    expect(s.inbox.parcels.every(p => p.expires_at === T + PARCEL_LIFETIME_MS)).toBe(true);
    expect(s.cookbook).toContain('dish_herb_grilled_fish');
    expect(events.filter(e => e.kind === 'parcel')).toHaveLength(2);
    expect(events.find(e => e.kind === 'parcel')).toMatchObject({ waiting: false, expires_in: PARCEL_LIFETIME_MS });
    expect(events.some(e => e.kind === 'parcel' && 'gift' in e)).toBe(false);
    gainXp(c, s, T, 'fishing', 1, 100, events);
    expect(s.inbox.parcels).toHaveLength(2);
  });

  it('fills existing partial stacks, preserving only the exact remainder as a parcel', () => {
    const s = full();
    s.bag[0] = { id: 'crop_herb', qty: 49 };
    grant(s);
    expect(count(s.bag, 'crop_herb')).toBe(50);
    expect(s.inbox.parcels).toMatchObject([{ id: 'crop_herb', qty: 2 }]);
    expect(grant(s)).toEqual([]);
    expect(count(s.bag, 'crop_herb') + s.inbox.parcels[0].qty).toBe(52);
  });

  it('sends nothing to Inbox if the full reward fits, and grants a source only once', () => {
    const s = freshState(c, player, T);
    grant(s); grant(s);
    expect(count(s.bag, 'crop_herb')).toBe(3);
    expect(s.inbox.parcels).toEqual([]);
  });

  it('splits large rewards into stack-sized parcels; full Inbox retains waiting entitlements', () => {
    const s = full();
    grant(s, 'large', [['crop_herb', 501]]);
    expect(s.inbox.parcels).toHaveLength(8);
    expect(s.inbox.waiting).toHaveLength(3);
    expect([...s.inbox.parcels, ...s.inbox.waiting].reduce((n, p) => n + p.qty, 0)).toBe(501);
    expect(s.inbox.waiting.every(p => !('expires_at' in p))).toBe(true);
    expect(viewOf(c, s, T).inbox).toMatchObject({ badge: 8, waiting: 3 });   // queued rewards stay off the bell
    s.bag.pop();
    const claimed = step(s, { type: 'claim_parcel', key: s.inbox.parcels[0].key }, T + 1000);
    expect(claimed.inbox.parcels).toHaveLength(8);
    expect(claimed.inbox.waiting).toHaveLength(2);
    expect(claimed.inbox.parcels.at(-1)?.expires_at).toBe(T + 1000 + PARCEL_LIFETIME_MS);
    expect(s.inbox.waiting).toHaveLength(3); // reducer never mutates input
  });

  it('requires a free slot even for a matching stack, and a repeated claim cannot grant twice', () => {
    let s = full(); grant(s);
    s.bag[0] = { id: 'crop_herb', qty: 1 };
    const key = s.inbox.parcels[0].key;
    expect(applyP0(c, s, { type: 'claim_parcel', key }, T)).toMatchObject({ ok: false, code: 'bag_full', detail: { slots: 1 } });
    s.bag.pop();
    s = step(s, { type: 'claim_parcel', key });
    expect(count(s.bag, 'crop_herb')).toBe(4);
    s = step(s, { type: 'claim_parcel', key });
    expect(count(s.bag, 'crop_herb')).toBe(4);
    expect(s.inbox.updates).toHaveLength(1);
  });

  it('Claim all stops at free slots and never claims parcels promoted after its captured IDs', () => {
    let s = full();
    for (let i = 0; i < 9; i++) grant(s, `reward-${i}`);
    const keys = s.inbox.parcels.map(p => p.key);
    s.bag.splice(0, 2);
    s = step(s, { type: 'claim_parcels', keys });
    expect(count(s.bag, 'crop_herb')).toBe(6);
    expect(s.inbox.parcels).toHaveLength(7);
    expect(s.inbox.parcels.some(p => p.key === 'reward-8:0')).toBe(true);
    expect(applyP0(c, s, { type: 'claim_parcels', keys }, T)).toMatchObject({ ok: false, code: 'bag_full' });
    expect(applyP0(c, s, { type: 'claim_parcels', keys: null } as unknown as P0Command, T)).toMatchObject({ ok: false, code: 'bad_parcel' });
  });

  it('expiry at exactly 24h pays floor(80% total sale price) once; unsellable rewards leave a record', () => {
    const s = full(); grant(s, 'expiry', [['crop_herb', 3], ['seed_carrot', 5]]);
    const coins = s.coins;
    expect(settleParcels(c, s, T + PARCEL_LIFETIME_MS - 1)).toBe(false);
    expect(settleParcels(c, s, T + PARCEL_LIFETIME_MS)).toBe(true);
    expect(s.coins).toBe(coins + Math.floor(c.crops.find(p => p.id === 'crop_herb')!.price * 3 * 0.8));
    expect(s.inbox.updates.map(u => [u.id, u.status, u.coins])).toEqual([
      ['crop_herb', 'expired', s.coins - coins], ['seed_carrot', 'expired', 0],
    ]);
    expect(settleParcels(c, s, T + PARCEL_LIFETIME_MS + 1)).toBe(false);
    expect(s.inbox.updates).toHaveLength(2);
  });

  it('claim before expiry wins; at the boundary expiry wins, with no double payout', () => {
    let s = full(); grant(s); s.bag.pop();
    const key = s.inbox.parcels[0].key;
    const claimed = step(s, { type: 'claim_parcel', key }, T + PARCEL_LIFETIME_MS - 1);
    settleParcels(c, claimed, T + PARCEL_LIFETIME_MS);
    expect(claimed.coins).toBe(s.coins);
    expect(count(claimed.bag, 'crop_herb')).toBe(3);
    expect(applyP0(c, s, { type: 'claim_parcel', key }, T + PARCEL_LIFETIME_MS)).toMatchObject({ ok: false, code: 'parcel_expired' });
  });

  it('projects truthful badge, sources, countdown and unread expiry receipts without changing input', () => {
    let s = full(); grant(s);
    const v = viewOf(c, s, T + 1000);
    expect(v.inbox).toMatchObject({ badge: 1, waiting: 0, claim_slots: 0, parcels: [{ source: 'Test reward', left: PARCEL_LIFETIME_MS - 1000, can_claim: false }] });
    expect(viewOf(c, s, T + PARCEL_LIFETIME_MS).inbox).toMatchObject({ badge: 1, parcels: [], updates: [{ read: false }] });
    expect(s.inbox.parcels).toHaveLength(1);
    settleParcels(c, s, T + PARCEL_LIFETIME_MS);
    s = step(s, { type: 'read_inbox', keys: s.inbox.updates.map(u => u.key) }, T + PARCEL_LIFETIME_MS);
    expect(viewOf(c, s, T + PARCEL_LIFETIME_MS).inbox.badge).toBe(0);
  });

  it('gives v3 and v4 saves an empty Inbox without inventing historical rewards', () => {
    const s = full();
    s.skills.fishing = 70;
    const v4 = JSON.parse(JSON.stringify(s)); delete v4.inbox;
    const v3 = JSON.parse(JSON.stringify(v4)); v3.v = 3; delete v3.mine; delete v3.gather;
    expect(upgradeState(c, v3)).toMatchObject({ v: 6, inbox: { granted: [], parcels: [], waiting: [], updates: [] } });
    const upgraded = upgradeState(c, v4);
    expect(upgraded.inbox).toEqual({ granted: [], parcels: [], waiting: [], updates: [] });
    expect(upgraded.bag).toEqual(s.bag);
    expect(upgraded.skills).toEqual(s.skills);
  });

  it('never routes active fishing, cooking or buying outputs into Parcels', () => {
    const s = full();
    expect(applyP0(c, s, { type: 'cast' }, T)).toMatchObject({ ok: false, code: 'creel_full' });
    expect(applyP0(c, s, { type: 'buy', item: 'seed_radish', qty: 1 }, T)).toMatchObject({ ok: false, code: 'bag_full' });
    expect(s.inbox.parcels).toEqual([]);
  });

  it('persists grant/claim and expiry through HTTP retries, concurrent claims and file-store restarts', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-parcels-'));
    const file = path.join(dir, 'state.json');
    let app = Fastify();
    let now = T;
    const headers = { 'x-p0-player': player };
    try {
      const s = full(); grant(s, 'saved', [['crop_herb', 3], ['seed_carrot', 5]]); s.bag.pop();
      writeFileSync(file, JSON.stringify({ [player]: s }));
      registerP0Routes(app, { content: c, store: new P0Store(c, file), now: () => now, dev: false });
      const payload = { type: 'claim_parcel', key: s.inbox.parcels[0].key };
      const replies = await Promise.all([1, 2].map(() => app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload })));
      expect(replies.every(r => r.json().ok)).toBe(true);
      expect(count(new P0Store(c, file).get(player, now).bag, 'crop_herb')).toBe(3);
      await app.close();
      now += PARCEL_LIFETIME_MS;
      app = Fastify();
      registerP0Routes(app, { content: c, store: new P0Store(c, file), now: () => now, dev: false });
      const expired = await app.inject({ method: 'GET', url: '/v1/p0/state', headers });
      expect(expired.json().state.inbox.updates).toHaveLength(2);
      const restarted = new P0Store(c, file).get(player, now + 1);
      expect(restarted.inbox.parcels).toEqual([]);
      expect(restarted.inbox.updates).toHaveLength(2);
      expect(restarted.coins).toBe(s.coins); // seed reward has no sale price
      expect(restarted.inbox.granted).toEqual(['saved']);
    } finally { await app.close(); rmSync(dir, { recursive: true, force: true }); }
  });
});
