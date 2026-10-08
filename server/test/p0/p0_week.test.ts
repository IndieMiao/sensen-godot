/**
 * SGODOT-232 V2: seven days of the §14.6 target player against the real P0 rules (tools/p0_week.ts), held to the
 * §14.6.2 P0 rerun: Energy 1,389 over the week, Farming 567, Fishing 989, Cooking 426, Homestead Lv2 about day 5,
 * Cooking Lv4 by day 4–5, no Energy wall. Cooking Lv6 (Quick Fire) and the pre-dinner pool are recorded, never failed
 * (user's knobs C and D, 2026-10-08). Coins are recorded too: the rerun counts no fish or dish sales.
 */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { playWeek } from '../../tools/p0_week.js';

const c = loadP0Content();
const RERUN = { energy: 1389, farming: 567, fishing: 989, cooking: 426 };
const within = (v: number, target: number, pct: number) => Math.abs(v - target) / target <= pct;

describe('seven days of the target player (§14.6.2; SGODOT-232 V2)', () => {
  it('stays within the P0 rerun\'s ledger and reaches its milestones', () => {
    const runs = ['week-target-00', 'week-target-01', 'week-target-02'].map(p => playWeek(c, p, 7));
    const mean = (f: (r: typeof runs[number]) => number) => runs.reduce((n, r) => n + f(r), 0) / runs.length;
    const energy = mean(r => r.stats.reduce((n, d) => n + d.spent, 0));
    const day7 = (k: 'farming' | 'fishing' | 'cooking') => mean(r => r.stats[6][k]);
    expect(within(energy, RERUN.energy, 0.2)).toBe(true);
    expect(within(day7('farming'), RERUN.farming, 0.25)).toBe(true);
    expect(within(day7('fishing'), RERUN.fishing, 0.25)).toBe(true);
    expect(within(day7('cooking'), RERUN.cooking, 0.25)).toBe(true);
    // Homestead Lv2 waits on 3 Rock Salt from the mine (≈ 2.7 a run, drawn per player), so one unlucky player may miss
    // the week; the mean day holds (rerun 4.8)
    expect(mean(r => r.reached.homestead_lv2 ?? 8)).toBeLessThanOrEqual(6);
    for (const r of runs) {
      expect(r.walls).toBe(0);
      expect(r.reached.cooking_lv4 ?? 8).toBeLessThanOrEqual(5);
      expect(r.reached.farming_lv4 ?? 8).toBeLessThanOrEqual(5);
      expect(r.stats.every(d => d.spent >= 100 && d.spent <= 300)).toBe(true);   // every day is played, none runs dry
    }
    console.log(JSON.stringify({ energy: Math.round(energy), farming: day7('farming'), fishing: day7('fishing'), cooking: day7('cooking'),
      coins: mean(r => r.stats[6].coins), cooking_lv5: runs.map(r => r.reached.cooking_lv5 ?? null) }));
  }, 120_000);
});
