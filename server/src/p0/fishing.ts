/** Fishing at the homestead pond (plan §6): cast pre-pays energy, the fish is drawn server-side, gates run level → rod → reel. */
import { fishById, rodById, type Fish, type FishSite, type P0Content } from './content.js';
import { add, count, freeSlots, room, take } from './bag.js';
import { clusterById, clusterOf, homeCluster } from './travel.js';
import { placeOf } from './world.js';
import { firstXp, energyDetail, gainEnergy, gainXp, grantOnce, spendEnergy, type P0Event } from './progress.js';
import { draw, maxEnergy, scaledXp, skillLevel, xpPercent } from './rules.js';
import type { P0State } from './state.js';

export type Refusal = { code: string; detail?: Record<string, unknown> };
export type FishCommand =
  | { type: 'cast'; bait?: string | null }   // the pond is where the player is (presence.place), never named by the cast
  | { type: 'reel'; outcome: 'cancel' | 'escaped' | 'landed' };

const siteFish = (c: P0Content, site: FishSite): Fish[] => site.fish.map(id => fishById(c, id)!).filter(Boolean);

/**
 * Teaching pins (§14.2.2, the director's reading of §6.1.3): bites 1–3 are Pond Crucian (two of them fill
 * the Pond Catch request), bite 4 at Fishing Lv1 is a Fine fish that breaks free, and the first baited
 * bite after Lv2 is a Fine fish that stays on. They only touch the first few bites; weights never change.
 */
export function pickFish(c: P0Content, s: P0State, bait: string | null, site: FishSite = c.fishing.sites.pond): Fish {
  const pond = siteFish(c, site);
  const bites = s.fishing.bites;
  const ofRarity = (r: number) => pond.filter(f => f.rarity === r);
  const crucian = pond.find(f => f.id === 'fish_crucian');
  if (bites < 3 && crucian) return crucian;
  const level = skillLevel(c, s, 'fishing');
  if (bites === 3 && level === 1 && ofRarity(2).length) return ofRarity(2)[0];
  if (bait && level >= 2 && !s.firsts.includes('baited_bite') && ofRarity(2).length) {
    s.firsts.push('baited_bite');   // castLine records the pin on the cast so a line-in can hand it back
    return pond.find(f => f.id === 'fish_perch') ?? ofRarity(2)[0];
  }
  const shift = bait ? c.fishing.baits[bait]?.shift ?? [] : [];
  const weights = site.weights.map((w, i) => (ofRarity(i + 1).length ? Math.max(0, w + (shift[i] ?? 0)) : 0));
  let roll = draw(s) * weights.reduce((a, b) => a + b, 0);
  let rarity = 1;
  for (let i = 0; i < weights.length; i++) { roll -= weights[i]; if (roll < 0) { rarity = i + 1; break; } }
  const pool = ofRarity(rarity);
  return pool[Math.floor(draw(s) * pool.length)];
}

export function castLine(c: P0Content, s: P0State, cmd: { bait?: string | null }, now: number, events: P0Event[]): Refusal | null {
  const f = c.fishing;
  // q(36): the template comes from the server's table for the pond the player entered, not from the client.
  const place = s.presence.place ?? '';
  const siteId = placeOf(c, place)?.site ?? '';   // a generated pond (gn-…~pond0) answers like a hand-written one
  const site = f.sites[siteId];
  if (!site) return { code: 'not_at_pond' };
  if (s.cast) {
    if (now - s.cast.at < f.stale_ms) return { code: 'already_casting' };
    settleFailure(c, s, now, events, 'escaped'); // a line left in the water past the grace counts as got away
  }
  if (freeSlots(s) < 1) return { code: 'creel_full', detail: { free: 0 } };
  const bait = cmd.bait ? String(cmd.bait) : null;
  if (bait && (!f.baits[bait] || count(s.bag, bait) < 1)) return { code: 'no_bait', detail: { bait } };
  if (s.energy.value < f.cast_energy) return { code: 'need_energy', detail: energyDetail(c, s, now, f.cast_energy) };
  spendEnergy(c, s, now, f.cast_energy, events, 'cast');
  s.fishing.casts += 1;
  const pinnedBefore = s.firsts.includes('baited_bite');
  const fish = pickFish(c, s, bait, site);
  const pin = !pinnedBefore && s.firsts.includes('baited_bite') ? 'baited_bite' : undefined;
  const level = skillLevel(c, s, 'fishing');
  const wait = bait ? f.baits[bait].wait : 1;
  const bite_ms = Math.round((f.bite_min_ms + draw(s) * f.bite_spread_ms) * wait);
  const rod = rodById(c, s.gear.rod) ?? f.rods[0];
  const breaks = fish.level > level ? 'level' : fish.rarity > rod.reach ? 'rod' : null;
  s.cast = { fish: fish.id, site: siteId, place, at: now, bite_ms, bait, xp_pct: xpPercent(c, level, fish.level), breaks, ...(pin ? { pin } : {}) };
  events.push({ kind: 'cast', bite_in: bite_ms, rarity: fish.rarity, breaks, bait });
  if (!s.firsts.includes('cast')) {
    s.firsts.push('cast');
    firstXp(c, s, now, 'fishing', 'cast', f.first_cast_xp, events);
  }
  return null;
}

export function reelLine(c: P0Content, s: P0State, cmd: { outcome?: string }, now: number, events: P0Event[]): Refusal | null {
  const cast = s.cast;
  if (!cast) return { code: 'no_cast' };
  const bitten = now >= cast.at + cast.bite_ms;
  const outcome = String(cmd.outcome ?? '');
  if (outcome === 'cancel' && !bitten) {
    // Line in before the bite: full refund, bait kept, not a failure (§6.6.1); an unused teaching pin returns.
    if (cast.pin) s.firsts = s.firsts.filter(f => f !== cast.pin);
    s.cast = null;
    gainEnergy(c, s, now, c.fishing.cast_energy, events, 'line_in', maxEnergy(c, s) + c.energy.bonus_zone);
    events.push({ kind: 'catch', fish: '', rarity: 0, result: 'cancelled', refund: c.fishing.cast_energy });
    return null;
  }
  if (outcome === 'landed' && !bitten) return { code: 'too_early', detail: { bite_in: cast.at + cast.bite_ms - now } };
  if (outcome === 'landed' && !cast.breaks) {
    const fish = fishById(c, cast.fish)!;
    if (room(c, s, fish.id) < 1) return { code: 'bag_full' };
    s.cast = null;
    s.fishing.bites += 1;
    useBait(s, cast.bait, events);
    add(c, s, fish.id, 1);
    s.fishing.caught[fish.id] = (s.fishing.caught[fish.id] ?? 0) + 1;
    events.push({ kind: 'item', id: fish.id, delta: 1 });
    events.push({ kind: 'catch', fish: fish.id, rarity: fish.rarity, result: 'landed', refund: 0 });
    gainXp(c, s, now, 'fishing', scaledXp(s, c.fishing.catch_xp[fish.rarity - 1], cast.xp_pct), cast.xp_pct, events);
    // q(37): the first catch in a city counts the site's city from the server's table, never a city the client names.
    // v5: keyed by the place's city cluster (fishing_city:gn-5391959); the event names the city for the client.
    const city = cast.place ? clusterOf(c, cast.place) ?? '' : '';
    const cityName = clusterById(c, city)?.name || (city === homeCluster(c) ? c.profile.city : '');
    for (const [key, xp] of [[`catch:${fish.id}`, c.fishing.first_xp[fish.rarity - 1]], ['landed', c.fishing.first_landed_xp],
      [`fishing_city:${city}`, city ? c.fishing.first_city_xp : 0]] as const) {
      if (xp <= 0) continue;
      if (s.firsts.includes(key)) continue;
      s.firsts.push(key);
      firstXp(c, s, now, 'fishing', key, xp, events, key.startsWith('fishing_city:') ? cityName : undefined);
    }
    grantOnce(c, s, now, `first_fish_${fish.rarity}`, c.rewards.first_fish[fish.rarity - 1] ?? 0, events);
    const kinds = Object.keys(s.fishing.caught).length;
    for (const [n, energy] of c.rewards.fishdex) if (kinds >= n) grantOnce(c, s, now, `fishdex_${n}`, energy, events);
    return null;
  }
  if (!['cancel', 'escaped', 'landed'].includes(outcome)) return { code: 'bad_outcome' };
  settleFailure(c, s, now, events, outcome === 'landed' ? 'broke_free' : 'escaped');
  return null;
}

/** Got away / broke free share one price: refund 3, or 5 for the first 10 failures a day while Fishing Lv1–3 (§6.1.3). */
function settleFailure(c: P0Content, s: P0State, now: number, events: P0Event[], result: 'escaped' | 'broke_free'): void {
  const cast = s.cast!;
  const fish = fishById(c, cast.fish)!;
  s.cast = null;
  s.fishing.bites += 1;
  useBait(s, cast.bait, events);
  const f = c.fishing;
  const covered = skillLevel(c, s, 'fishing') <= f.protect_max_level;
  const protectedNow = covered && s.day.fails < f.protect_fails;
  s.day.fails += 1;
  const refund = protectedNow ? f.cast_energy : f.refund_fail;
  gainEnergy(c, s, now, refund, events, 'refund', maxEnergy(c, s) + c.energy.bonus_zone);
  if (result === 'broke_free' && !s.fishing.seen.includes(fish.id)) s.fishing.seen.push(fish.id);
  events.push({
    kind: 'catch', fish: result === 'broke_free' ? fish.id : '', rarity: fish.rarity, result, refund,
    ...(cast.breaks === 'level' && result === 'broke_free' ? { need_level: fish.level } : {}),
    ...(covered ? { protected_left: Math.max(0, f.protect_fails - s.day.fails) } : {}),
  });
}

function useBait(s: P0State, bait: string | null, events: P0Event[]): void {
  if (!bait || count(s.bag, bait) < 1) return;
  take(s.bag, bait, 1);
  events.push({ kind: 'item', id: bait, delta: -1 });
}
