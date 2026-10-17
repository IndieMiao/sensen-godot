/**
 * Saves the first-pick bug left San Francisco visited in (李元芳 on 0.2.10, SGODOT-286 ad0c1580): before the fix,
 * choose_home from a pending save wrote visits[San Francisco] — the city a pending save stands in, where the player
 * never was. Read only: sorts saves for the data-fix proposal; nothing here writes.
 *
 * The written record: { n: 1, first_at: created_at (a pending save has no home_chosen_at), last_at: the pick, deliveries
 * 0 }, and never a San Francisco stamp (stamps come only from travel's first visit, which the record then hid).
 * - `never`: still that record, no change since: the player has not been to San Francisco.
 * - `went`: the record, then travel there (n ≥ 2, no stamp): a real visit, whose stamp, +10 Energy and Explorer count
 *   were missed (travel saw a visit already).
 * - `changed`: a free change since (home_changes ≥ 1). A save that played San Francisco before SGODOT-303 and changed
 *   away gets the same first_at (no home_chosen_at either) but last_at = the change (= home_chosen_at, the change being
 *   the last pick); the first pick's record is older than the change. Listed apart, with which it looks like.
 *   Not told apart: a first pick's record, then a real trip there (last_at moves on), then a change — it reads as
 *   `played_san_francisco` (刘邦 on #469). Check those by hand if any come up (the 10-17 run had no change at all).
 */
import type { P0Content } from './content.js';
import { writtenCluster } from './home.js';
import type { P0State } from './state.js';

export interface FirstPickAudit {
  never: string[]; went: string[];
  changed: { player: string; looks: 'first_pick' | 'played_san_francisco' }[];
}

export function auditFirstPickVisits(c: P0Content, saves: Record<string, P0State>): FirstPickAudit {
  const sf = writtenCluster(c), out: FirstPickAudit = { never: [], went: [], changed: [] };
  for (const [player, s] of Object.entries(saves)) {
    const t = s?.travel, v = t?.visits?.[sf];
    if (!t || !v || t.stamps?.some(x => x.cluster === sf) || v.first_at !== s.created_at) continue;
    if ((t.home_changes ?? 0) >= 1) {
      out.changed.push({ player, looks: v.n === 1 && v.last_at < (t.home_chosen_at ?? 0) ? 'first_pick' : 'played_san_francisco' });
    } else if (t.home === sf) continue;   // no change and home San Francisco: never picked elsewhere
    else if (v.n === 1 && v.deliveries === 0) out.never.push(player);
    else out.went.push(player);
  }
  return out;
}
