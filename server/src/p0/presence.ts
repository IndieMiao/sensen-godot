/**
 * Rest's "2 h since you last left the homestead" (plan §3.4.3, q(41)). The P0 server has no position, so each
 * command says which space it comes from (home = the homestead and the farmhouse; pond / outpost / mine are away;
 * the map and commands without a space change nothing). Leaving = the first command from an away space after
 * home, or the previous command when two commands are ≥ 2 h apart (the session ended in between).
 */
import type { P0Content } from './content.js';
import type { P0State } from './state.js';

const AWAY = new Set(['pond', 'outpost', 'mine']);

/** Returns true when this command is the first one back at home (hook for auto-storing materials, SGODOT-231). */
export function trackPresence(c: P0Content, s: P0State, space: unknown, now: number): boolean {
  const p = s.presence;
  const wasHome = p.space === 'home';
  if (p.last_at > 0 && now - p.last_at >= c.energy.rest_away_h * 3_600_000) p.left_at = p.last_at;
  const where = typeof space === 'string' ? space : '';
  if (AWAY.has(where) && p.space !== 'away') p.left_at = now;
  if (AWAY.has(where)) p.space = 'away';
  else if (where === 'home') p.space = 'home';
  p.last_at = now;
  return where === 'home' && !wasHome;
}

/** ms until Rest opens by the away rule; 0 = open; null = the player has not left yet. */
export function restReadyIn(c: P0Content, s: P0State, now: number): number | null {
  const left = s.presence.left_at;
  if (left === null) return null;
  return Math.max(0, left + c.energy.rest_away_h * 3_600_000 - now);
}
