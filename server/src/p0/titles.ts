/**
 * Titles (q(180), §10.6.2): the ones the player has been given, in a fixed order, and the one they wear.
 *
 * The list is derived from the records each source already keeps — never stored on its own and never recomputed from
 * today's thresholds, so a later change of numbers takes none back (as q(171) ⑤):
 *   homestead          Homestead Master: the homestead's level, from the level whose unlocks name the title
 *   level:<skill>      a skill's Lv10 title: that level's gift (inbox.granted `level:<skill>:<n>`, given even when empty)
 *   milestone:<id>     the Cookbook's: Home Cook from the P0 reward `cookbook_8` (milestone:home_cook), the others from
 *                      their milestones (firsts `milestone:<id>`)
 *   explorer:<n>       Wanderer (3) / Globetrotter (100): the Explorer medal given (travel.explorer)
 *   kindred:<resident> `<Name>'s Best Friend`: kindred_at
 *   req:<request>      a Trusted request's title: its reward (inbox.granted `req:<id>`)
 * Ids are stable; their text is the client's (P0Logic.TITLE_NAMES: Homestead, skills, Explorer, Home Cook) or the
 * content's (milestones, Kindred, requests), so a renamed title (Harbour → Harbor, q(170)) needs no save change.
 *
 * s.title is the one worn, an optional field nothing fills in: absent — or an id not in the list — wears the first,
 * and that is not written, so a title earlier in the order shows of itself; once worn by choice it stays on.
 */
import type { P0Content } from './content.js';
import type { P0State } from './state.js';

const SKILLS = ['farming', 'fishing', 'cooking'] as const;
const EXPLORER_TITLES = [100, 3];   // Globetrotter (Explorer Platinum), Wanderer (Explorer Bronze), §11.9.2
const HOME_COOK = 'home_cook';

/** The Lv a skill's title comes at, from its conveniences (`title_*`, SGODOT-275); null when the skill has none. */
function skillTitleLevel(c: P0Content, skill: typeof SKILLS[number]): number | null {
  const table: Partial<Record<string, number>> | undefined = skill === 'farming' ? c.farming?.conveniences
    : skill === 'fishing' ? c.fishing.conveniences : c.cooking.conveniences as Partial<Record<string, number>>;
  const key = Object.keys(table ?? {}).find(k => k.startsWith('title_'));
  return key ? table![key] ?? null : null;
}

/** The titles given, in the order q(180) ③ fixes (also the Titles drawer's rows). */
export function ownedTitles(c: P0Content, s: P0State): string[] {
  const out: string[] = [];
  const masterAt = c.homestead.levels.find(l => l.unlocks.includes('title_homestead_master'))?.level;
  if (masterAt !== undefined && s.homestead.level >= masterAt) out.push('homestead');
  for (const skill of SKILLS) {
    const at = skillTitleLevel(c, skill);
    if (at !== null && s.inbox.granted.includes(`level:${skill}:${at}`)) out.push(`level:${skill}`);
  }
  // Cookbook: the Discovered titles from the most pages down (Master Chef 48 … Home Cook 8), then Mastered ones.
  const [homeCookAt] = c.rewards.cookbook[0] ?? [];
  const discovered = (c.cooking.milestones ?? []).filter(m => m.discovered !== undefined)
    .map(m => ({ id: m.id, n: m.discovered!, got: s.firsts.includes(`milestone:${m.id}`) }));
  if (homeCookAt !== undefined) discovered.push({ id: HOME_COOK, n: homeCookAt, got: s.rewards.includes(`cookbook_${homeCookAt}`) });
  for (const m of discovered.sort((a, b) => b.n - a.n)) if (m.got) out.push(`milestone:${m.id}`);
  for (const m of c.cooking.milestones ?? []) {
    if (m.discovered === undefined && s.firsts.includes(`milestone:${m.id}`)) out.push(`milestone:${m.id}`);
  }
  for (const n of EXPLORER_TITLES) if (s.travel.explorer >= n) out.push(`explorer:${n}`);
  const residents = Object.keys(c.residents);
  for (const id of residents) if (s.residents[id]?.kindred_at !== undefined) out.push(`kindred:${id}`);
  for (const id of residents) {
    for (const q of c.residents[id].requests) {
      if (q.reward?.title && s.inbox.granted.includes(`req:${q.id}`)) out.push(`req:${q.id}`);
    }
  }
  return out;
}

/** The title worn: the one picked while it is still in the list, else the first; null with none. */
export function wornTitle(c: P0Content, s: P0State, owned = ownedTitles(c, s)): string | null {
  return s.title !== undefined && owned.includes(s.title) ? s.title : owned[0] ?? null;
}

/** `wear_title`: put on a title the player has. Free, anywhere; the only write is s.title. */
export function wearTitle(c: P0Content, s: P0State, cmd: { id?: unknown }): { code: string } | null {
  if (typeof cmd.id !== 'string' || !ownedTitles(c, s).includes(cmd.id)) return { code: 'bad_title' };
  s.title = cmd.id;
  return null;
}

/** view.titles: the ids in order and the one worn (the profile's title and the Titles drawer). */
export function titlesView(c: P0Content, s: P0State): { list: string[]; wearing: string | null } {
  const list = ownedTitles(c, s);
  return { list, wearing: wornTitle(c, s, list) };
}
