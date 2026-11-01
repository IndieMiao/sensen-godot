/** q(180) (§10.6.2): titles derived from what was given, in a fixed order; one worn, picked with wear_title. */
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, upgradeState, type P0State, SAVE_VERSION } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { ownedTitles } from '../../src/p0/titles.js';
import { gainXp, type P0Event } from '../../src/p0/progress.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 14, 18, 0, 0);
const DAY = 24 * 3_600_000;
const fresh = (): P0State => ({ ...freshState(c, 'player-titles-01', T0, 5), created_at: T0 - 8 * DAY, fires: 1 });
const resident = (affinity = 0) => ({ affinity, chat_day: '', gift_day: '', next: 0, req: null, done_day: '' });
const titles = (s: P0State) => viewOf(c, s, T0).titles;
function step(s: P0State, cmd: P0Command, now = T0): P0State {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return r.state;
}
const refusal = (s: P0State, cmd: P0Command) => { const r = applyP0(c, s, cmd, T0); return r.ok ? null : r.code; };

/** Every source's record, as the code that gives each title writes it. */
function everything(): P0State {
  const s = fresh();
  s.homestead.level = 10;
  s.homestead.plaque.push({ level: 10, at: T0 });
  s.inbox.granted.push('level:farming:10', 'level:fishing:10', 'level:cooking:10', 'req:req_res_kai_3', 'req:req_res_pip_5');
  s.firsts.push('milestone:muscle_memory', 'milestone:line_cook', 'milestone:master_chef', 'milestone:head_chef');
  s.rewards.push('cookbook_8');
  s.travel.explorer = 100;
  s.residents.res_old_kai = { ...resident(150), kindred_at: T0 };
  s.residents.res_pip = { ...resident(150), kindred_at: T0 };
  return s;
}

describe('titles (q(180))', () => {
  it('a new player has none and wears none', () => {
    expect(titles(fresh())).toEqual({ list: [], wearing: null });
  });

  it('every source, in the fixed order: Homestead, skills, Cookbook (most pages down, then Mastered), Explorer, Kindred, requests', () => {
    expect(ownedTitles(c, everything())).toEqual([
      'homestead', 'level:farming', 'level:fishing', 'level:cooking',
      'milestone:master_chef', 'milestone:head_chef', 'milestone:line_cook', 'milestone:home_cook', 'milestone:muscle_memory',
      'explorer:100', 'explorer:3',
      'kindred:res_pip', 'kindred:res_old_kai',   // the residents' order in the content, not the order reached
      'req:req_res_pip_5', 'req:req_res_kai_3',   // by resident, then request
    ]);
  });

  it('from what was given, not recomputed: XP past Lv10 without the level gift is no title; a medal below Platinum is Wanderer only', () => {
    const s = fresh();
    s.skills.farming = 10_000_000;
    s.homestead.level = 9;
    s.homestead.plaque.push({ level: 9, at: T0 });
    s.travel.explorer = 30;
    expect(ownedTitles(c, s)).toEqual(['explorer:3']);
    s.inbox.granted.push('level:farming:9');   // a gift of another level names no title
    s.rewards.push('title:Route Buddy');   // only the request's own reward key counts (a text record changes with renames)
    expect(ownedTitles(c, s)).toEqual(['explorer:3']);
  });

  it('raised thresholds take nothing back: the records keep the Lv10 titles and Home Cook (q(180) ①)', () => {
    const raised = structuredClone(c);
    raised.homestead.max_level = 12;
    for (const l of raised.homestead.levels) l.unlocks = l.unlocks.filter(u => u !== 'title_homestead_master');
    raised.homestead.levels.push({ ...raised.homestead.levels.at(-1)!, level: 12, unlocks: ['title_homestead_master'] });
    raised.farming!.conveniences!.title_master_gardener = 12;
    raised.cooking.conveniences = { ...raised.cooking.conveniences, title_chef: 12 } as typeof raised.cooking.conveniences;
    raised.rewards.cookbook = [[10, 50]];
    for (const m of raised.cooking.milestones!) if (m.discovered !== undefined) m.discovered += 4;
    expect(ownedTitles(raised, everything())).toEqual(ownedTitles(c, everything()));
    // and a Lv10 homestead set by hand, with no plaque of the upgrade, has no Homestead Master
    const hand = fresh();
    hand.homestead.level = 10;
    expect(ownedTitles(c, hand)).toEqual([]);
  });

  it('wears the first until one is picked, and that is not written: a title earlier in the order shows of itself', () => {
    let s = fresh();
    s.travel.explorer = 3;
    expect(titles(s)).toEqual({ list: ['explorer:3'], wearing: 'explorer:3' });
    s.inbox.granted.push('level:fishing:10');
    s = step(s, { type: 'read_inbox', keys: [] });
    expect(titles(s).wearing).toBe('level:fishing');
    expect(s.title).toBeUndefined();
  });

  it('wear_title puts one on and it stays on when a title earlier in the order comes', () => {
    let s = fresh();
    s.travel.explorer = 3;
    s.residents.res_pip = { ...resident(150), kindred_at: T0 };
    s = step(s, { type: 'wear_title', id: 'kindred:res_pip' });
    expect(s.title).toBe('kindred:res_pip');
    expect(titles(s)).toEqual({ list: ['explorer:3', 'kindred:res_pip'], wearing: 'kindred:res_pip' });
    s.homestead.level = 10;
    s.homestead.plaque.push({ level: 10, at: T0 });
    expect(titles(s).list[0]).toBe('homestead');
    expect(titles(s).wearing).toBe('kindred:res_pip');
    expect({ coins: s.coins, energy: s.energy.value }).toEqual({ coins: fresh().coins, energy: fresh().energy.value });   // free
  });

  it('refuses a title not had, an unknown id or no id; nothing changes', () => {
    const s = fresh();
    s.travel.explorer = 3;
    expect(refusal(s, { type: 'wear_title', id: 'explorer:100' })).toBe('bad_title');
    expect(refusal(s, { type: 'wear_title', id: 'Wanderer' })).toBe('bad_title');   // ids, never the text
    expect(refusal(s, { type: 'wear_title' } as unknown as P0Command)).toBe('bad_title');
  });

  it('a worn id no longer in the list wears the first and is left as it is', () => {
    let s = fresh();
    s.travel.explorer = 3;
    s.title = 'req:req_gone';
    s = step(s, { type: 'read_inbox', keys: [] });
    expect(titles(s).wearing).toBe('explorer:3');
    expect(s.title).toBe('req:req_gone');
  });

  it('an old save gets no field at load; the save version is the current one (6 since q(270), not raised for titles)', () => {
    const old = structuredClone(fresh()) as P0State & { title?: string };
    delete old.title;
    const s = upgradeState(c, JSON.parse(JSON.stringify(old)), T0);
    expect('title' in s).toBe(false);
    expect(s.v).toBe(SAVE_VERSION);
    expect('title' in step(s, { type: 'read_inbox', keys: [] })).toBe(false);
  });

  it('levelling Farming to 10 in play adds `level:farming` (its level gift is the record)', () => {
    const s = fresh();
    s.skills.farming = c.skills.farming[9] - 1;
    const events: P0Event[] = [];
    gainXp(c, s, T0, 'farming', 5, 100, events);
    expect(events.some(e => e.kind === 'level' && e.level === 10)).toBe(true);
    expect(ownedTitles(c, s)).toEqual(['level:farming']);
  });

  it('reaching Kindred in play adds `kindred:<id>`', () => {
    const s = fresh();
    s.residents.res_pip = resident(148);
    expect(titles(step(s, { type: 'talk', resident: 'res_pip' })).list).toEqual(['kindred:res_pip']);
  });
});
