/**
 * Titles (q(180), §10.6.2): the ones the player has been given, in a fixed order, and the one they wear.
 *
 * The list is derived from the records each source already keeps — never stored on its own and never read against
 * today's thresholds, so a level or count moved later takes none back (q(180) ①, as q(171) ⑤):
 *   homestead          Homestead Master: the plaque of the upgrade to Lv10
 *   level:<skill>      a skill's Lv10 title: the Lv10 level gift (inbox.granted `level:<skill>:10`, given even when empty)
 *   milestone:<id>     the Cookbook's: Home Cook from the first Cookbook reward (rewards `cookbook_<n>`, P0's
 *                      cookbook_8; milestone:home_cook), the others from their milestones (firsts `milestone:<id>`)
 *   explorer:<n>       Wanderer (3) / Globetrotter (100): the Explorer medal given (travel.explorer)
 *   kindred:<resident> `<Name>'s Best Friend`: kindred_at
 *   req:<request>      a Trusted request's title: its reward (inbox.granted `req:<id>`)
 * The Lv10 here is the level those titles were given at (the content's title_* keys and Homestead Lv10 unlocks say the
 * same today), fixed rather than read from the content: no save records which level gave a title, so moving one to
 * another level later needs its own q row, which says how the records name it then (周瑜 on #413).
 * Ids are stable; their text is the client's (P0Logic.TITLE_NAMES: Homestead, skills, Explorer, Home Cook) or the
 * content's (milestones, Kindred, requests), so a renamed title (Harbour → Harbor, q(170)) needs no save change.
 *
 * s.title is the one worn, an optional field nothing fills in: absent — or an id not in the list — wears the first,
 * and that is not written, so a title earlier in the order shows of itself; once worn by choice it stays on.
 */
import type { P0Content } from './content.js';
import type { P0State } from './state.js';

const SKILLS = ['farming', 'fishing', 'cooking'] as const;
// The levels the titles came with, fixed here so that content raising a threshold never takes one back (q(180) ①):
// the skills' titles with a skill's Lv10, Homestead Master with Homestead Lv15 since v4q(1) ⑧ (Lv10 before).
const SKILL_TITLE_LEVEL = 10;
const MASTER_LEVEL = 15;
const EXPLORER_TITLES = [100, 3];   // Globetrotter (Explorer Platinum), Wanderer (Explorer Bronze), §11.9.2
const HOME_COOK = 'home_cook';
const COOKBOOK_REWARD = /^cookbook_\d+$/;   // the Cookbook reward Home Cook came with (cookbook_8), whatever count it is at

/** The titles given, in the order q(180) ③ fixes (also the Titles drawer's rows). */
export function ownedTitles(c: P0Content, s: P0State): string[] {
  const out: string[] = [];
  if (s.homestead.plaque.some(p => p.level === MASTER_LEVEL)) out.push('homestead');
  for (const skill of SKILLS) if (s.inbox.granted.includes(`level:${skill}:${SKILL_TITLE_LEVEL}`)) out.push(`level:${skill}`);
  // Cookbook: the Discovered titles from the most pages down (Master Chef 48 … Home Cook 8), then Mastered ones. The
  // counts only order them (a given milestone is kept by its id); Home Cook sits last of the Discovered ones.
  const discovered = (c.cooking.milestones ?? []).filter(m => m.discovered !== undefined)
    .sort((a, b) => b.discovered! - a.discovered!);
  for (const m of discovered) if (s.firsts.includes(`milestone:${m.id}`)) out.push(`milestone:${m.id}`);
  if (s.rewards.some(k => COOKBOOK_REWARD.test(k))) out.push(`milestone:${HOME_COOK}`);
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
