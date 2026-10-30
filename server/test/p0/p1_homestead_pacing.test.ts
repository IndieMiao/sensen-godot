/** SGODOT-354 q(246)/q(247): early gates and content-driven actual Energy, with v5 saves retained. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type P0Content } from '../../src/p0/content.js';
import { applyP0 } from '../../src/p0/reducer.js';
import { maxEnergy } from '../../src/p0/rules.js';
import { freshState, upgradeState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content(), T = Date.UTC(2026, 9, 28, 2);
function ready(level: number, energy: number, cc = c) {
  const s = freshState(cc, 'pacing-old-account', T, 4);
  s.created_at = T - 30 * 86400000;
  s.homestead.level = level - 1;
  const next = cc.homestead.levels.find(x => x.level === level)!;
  s.skills = { farming: cc.skills.farming[9], fishing: cc.skills.fishing[9], cooking: 0 };
  s.coins = next.coins + 40; s.storage = Object.fromEntries(next.materials);
  s.energy = { value: energy, tick_ms: T };
  return s;
}
function upgrade(level: number, energy: number, cc = c) {
  const before = ready(level, energy, cc);
  const r = applyP0(cc, before, { type: 'homestead_upgrade', space: 'home' }, T);
  if (!r.ok) throw new Error(r.code);
  return { before, ...r };
}

describe('q(246) gates for every account, not just new saves', () => {
  it('matches the approved Lv2–4 gates including Lv4 300 and the SGODOT-355 option A Lv5–10 ladder', () => {
    expect(c.homestead.levels.slice(0, 5).map(l => [l.level, l.coins, l.skills, l.materials, l.energy])).toEqual([
      [2, 40, 3, [['wood', 6], ['stone', 4], ['fiber', 3]], 40],
      [3, 80, 4, [['stone', 8], ['copper_ore', 2], ['clay', 2]], 40],
      [4, 300, 6, [['wood', 12], ['stone', 10], ['fiber', 6], ['copper_ore', 4], ['clay', 4], ['rock_salt', 3]], 40],
      [5, 450, 8, [['wood', 12], ['stone', 10], ['fiber', 7], ['copper_ore', 6], ['clay', 5], ['quartz', 1], ['rock_salt', 2]], 'full'],
      [6, 800, 10, [['wood', 16], ['stone', 14], ['fiber', 10], ['copper_ore', 8], ['clay', 6], ['quartz', 2], ['hardwood', 2]], 'full'],
    ]);
    expect(c.homestead.levels.slice(5).map(l => [l.coins, l.skills, l.energy])).toEqual([
      [1300, 12, 'full'], [1800, 14, 'full'], [2300, 16, 'full'], [3000, 19, 'full'],
    ]);
  });

  it.each([2, 3, 4])('Lv%d gives only actual Energy: 40, remaining room, zero at/above the new cap', level => {
    const cap = 200 + 10 * (level - 1);
    for (const [before, gain] of [[0, 40], [cap - 1, 1], [cap, 0], [cap + 15, 0]]) {
      const r = upgrade(level, before);
      expect(r.state.energy.value).toBe(before + gain);
      expect(r.events.find(e => e.kind === 'homestead')).toMatchObject({ level, energy: gain });
      expect(r.events.filter(e => e.kind === 'energy')).toEqual(gain ? [{ kind: 'energy', delta: gain, reason: 'homestead' }] : []);
      expect(r.state.v).toBe(r.before.v);
    }
  });

  it('reads the reward from content, not a hardcoded level check, and retains full-refill semantics from Lv5', () => {
    const cc: P0Content = structuredClone(c);
    cc.homestead.levels[0].energy = 7;
    expect(upgrade(2, 100, cc).state.energy.value).toBe(107);
    for (const level of [5, 6, 7, 8, 9, 10]) {
      const r = upgrade(level, 1);
      expect(r.state.energy.value).toBe(maxEnergy(c, r.state));
      expect(r.events.find(e => e.kind === 'homestead')).toMatchObject({ energy: maxEnergy(c, r.state) - 1 });
    }
    expect(upgrade(5, 270).state.energy.value).toBe(270);
  });

  it('can perform two affordable upgrades on an old Lv1 account, with separate payments/rewards and no automatic upgrade', () => {
    let s = ready(2, 0); s.coins = 160; s.storage = { wood: 6, stone: 12, fiber: 3, copper_ore: 2, clay: 2 };
    s.skills = { farming: c.skills.farming[1], fishing: c.skills.fishing[1], cooking: 0 };
    expect(viewOf(c, s, T).homestead.next!.can_upgrade).toBe(true);
    expect(s.homestead.level).toBe(1);
    for (const level of [2, 3]) {
      const r = applyP0(c, s, { type: 'homestead_upgrade', space: 'home' }, T);
      if (!r.ok) throw new Error(r.code);
      s = r.state;
      expect(s.homestead.level).toBe(level);
      expect(r.events.find(e => e.kind === 'homestead')).toMatchObject({ energy: 40 });
    }
    expect(s.energy.value).toBe(80); expect(s.coins).toBe(40); expect(s.storage).toEqual({});
    expect(s.homestead.plaque.map(p => p.level)).toEqual([2, 3]); expect(s.plots).toHaveLength(40);
  });

  it('loading existing reached levels neither downgrades nor refunds historical payments or rewards', () => {
    for (const level of [2, 3, 4, 5, 10]) {
      const s = ready(level, 123); s.homestead.level = level; s.coins = 71;
      s.homestead.plaque = [{ level, at: T - 10 * 86400000 }];
      const before = { level, coins: s.coins, energy: s.energy.value, plaque: structuredClone(s.homestead.plaque) };
      const r = upgradeState(c, JSON.parse(JSON.stringify(s)), T);
      expect({ level: r.homestead.level, coins: r.coins, energy: r.energy.value, plaque: r.homestead.plaque }).toEqual(before);
      expect(r.v).toBe(5);
    }
  });
});
