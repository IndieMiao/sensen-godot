/** q(220) (SGODOT-338 / 345): each resident's first edible dish from you gives +10 instead of the usual +1–+4 (no Perfect
 * or Chef's Touch on top), once per resident, judged by the empty gift day; the Mystery Dish stays −2 and uses that first
 * time up. q(221): Cooking Lv2's level-up gift is the Grilled Fish card; the Fresh Fish Soup card is no level-up gift. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, recipeById } from '../../src/p0/content.js';
import { guideKeys } from '../../src/p0/guide.js';
import { applyP0, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { giftClues, giftPoints, lessonState, residentState } from '../../src/p0/residents.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';

const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 8, 2, 0, 0);   // 10:00 Shanghai
const H = 3_600_000, DAY = 24 * H;
const FIRST = c.affinity.gift.first;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const fresh = () => ({ ...freshState(c, 'player-q220', T0, 3), created_at: T0 - 8 * DAY });
const aff = (ev: P0Event[]) => ev.find(e => e.kind === 'affinity') as Extract<P0Event, { kind: 'affinity' }>;
const gift = (s: P0State, resident: string, item: string, now = T0) => step(s, { type: 'gift', resident, item }, now);

describe('first gift per resident (q(220))', () => {
  it('a resident\'s first dish gives +10 whatever it is, flagged first, its verdict kept; the next one the usual points', () => {
    const s = fresh();
    s.bag.push({ id: 'dish_fish_soup', qty: 2 });
    const first = gift(s, 'res_nadia', 'dish_fish_soup');   // Soup: Nadia likes Stew, so +1 as a plain gift
    expect(aff(first.ev)).toMatchObject({ resident: 'res_nadia', delta: FIRST, total: FIRST, reason: 'gift', verdict: 'received', first: true });
    const next = gift(first.s, 'res_nadia', 'dish_fish_soup', T0 + DAY);
    expect(aff(next.ev)).toMatchObject({ delta: c.affinity.gift.any, verdict: 'received' });
    expect(aff(next.ev).first).toBeUndefined();
  });

  it('+10 replaces a loved dish\'s points, Perfect and Chef\'s Touch: nothing on top', () => {
    const s = fresh();
    s.skills.cooking = 1700;   // Cooking Lv9: Chef's Touch
    s.bag.push({ id: 'dish_herb_grilled_fish@perfect', qty: 1 });   // Grilled and Fine: Old Kai loves it
    expect(giftPoints(c, s, c.residents.res_old_kai, 'dish_herb_grilled_fish@perfect').delta).toBe(5);
    expect(aff(gift(s, 'res_old_kai', 'dish_herb_grilled_fish@perfect').ev)).toMatchObject({ delta: FIRST, verdict: 'loved', first: true });
  });

  it('counted per resident: a first dish for Pip or Old Kai never takes Nadia\'s', () => {
    let s = fresh();
    s.bag.push({ id: 'dish_carrot_cake', qty: 3 });
    s = gift(s, 'res_pip', 'dish_carrot_cake').s;
    s = gift(s, 'res_old_kai', 'dish_carrot_cake').s;
    expect(aff(gift(s, 'res_nadia', 'dish_carrot_cake').ev)).toMatchObject({ delta: FIRST, first: true });
  });

  it('the Mystery Dish stays −2 and uses the first time up; an edible dish after it is a usual gift', () => {
    let s = fresh();
    residentState(s, 'res_pip').affinity = 20;   // Acquainted, so the −2 shows
    s.bag.push({ id: c.cooking.mystery.id, qty: 1 }, { id: 'dish_carrot_cake', qty: 1 });
    const mystery = gift(s, 'res_pip', c.cooking.mystery.id);
    expect(aff(mystery.ev)).toMatchObject({ delta: c.affinity.gift.mystery, verdict: 'not_a_fan' });
    expect(aff(mystery.ev).first).toBeUndefined();
    s = mystery.s;
    expect(aff(gift(s, 'res_pip', 'dish_carrot_cake', T0 + DAY).ev)).toMatchObject({ delta: c.affinity.gift.liked, verdict: 'liked' });
  });

  it('old saves: a resident given a dish before gets no +10 back; one never given a dish still gets it', () => {
    const s = fresh();
    residentState(s, 'res_pip').gift_day = '2026-09-01';
    s.bag.push({ id: 'dish_carrot_cake', qty: 2 });
    expect(aff(gift(s, 'res_pip', 'dish_carrot_cake').ev)).toMatchObject({ delta: c.affinity.gift.liked });
    expect(aff(gift(s, 'res_old_kai', 'dish_carrot_cake').ev)).toMatchObject({ delta: FIRST, first: true });
  });

  it('the first session: Nadia 2 (first chat) + 5 (request) + 10 (the soup) = 17 reaches Acquainted', () => {
    const s = fresh();
    residentState(s, 'res_nadia').affinity = 7;
    s.bag.push({ id: 'dish_fish_soup', qty: 1 });
    expect(aff(gift(s, 'res_nadia', 'dish_fish_soup').ev)).toMatchObject({ total: 17, stage: 'Acquainted' });
  });

  it('the gift drawer shows +10 for a resident\'s first gift, the Mystery Dish −2; Gift Clues are unchanged', () => {
    const s = fresh();
    s.skills.fishing = 2000;   // past Fishing Lv7: gift points and clues show
    residentState(s, 'res_old_kai').chat_day = '2026-10-07';   // met
    s.bag.push({ id: 'dish_herb_grilled_fish', qty: 1 }, { id: c.cooking.mystery.id, qty: 1 });
    const pts = () => viewOf(c, s, T0).residents.res_old_kai.gift_points!;
    expect(pts()).toMatchObject({ dish_herb_grilled_fish: FIRST, [c.cooking.mystery.id]: c.affinity.gift.mystery });
    expect(giftClues(c, s)!.dish_herb_grilled_fish).toEqual([{ resident: 'res_old_kai', verdict: 'loved' }]);
    residentState(s, 'res_old_kai').gift_day = '2026-10-07';
    expect(pts()).toMatchObject({ dish_herb_grilled_fish: c.affinity.gift.loved_fine });
  });

  it('the guide counts `gift:<resident>` for an edible dish only (q(215) S10); the item key names any gift', () => {
    const s = fresh();
    s.bag.push({ id: c.cooking.mystery.id, qty: 1 }, { id: 'dish_fish_soup', qty: 1 });
    const keys = (item: string) => {
      const r = gift(s, 'res_nadia', item);
      return [...guideKeys(c, s, r.s, { type: 'gift', resident: 'res_nadia', item }, r.ev).keys()];
    };
    expect(keys(c.cooking.mystery.id)).toEqual([`gift:res_nadia:${c.cooking.mystery.id}`]);
    expect(keys('dish_fish_soup')).toEqual(expect.arrayContaining(['gift:res_nadia', 'gift:res_nadia:dish_fish_soup']));
  });
});

describe('Cooking Lv2 gives the Grilled Fish card (q(221))', () => {
  it('level_gifts and the pages\' learn fields', () => {
    expect(c.level_gifts['cooking:2']).toEqual([['recipe:dish_grilled_fish', 1]]);
    const learn = (id: string) => recipeById(c, id)!.learn ?? [];
    expect(learn('dish_grilled_fish')).toContain('gift');
    expect(learn('dish_fish_soup')).not.toContain('gift');
    expect(Object.values(c.level_gifts).flat().some(([id]) => id === 'recipe:dish_fish_soup')).toBe(false);
  });

  it('Old Kai\'s first lesson skips Grilled Fish once the level-up gave it (his list is unchanged)', () => {
    const s = fresh();
    residentState(s, 'res_old_kai').affinity = 200;
    const teaches = c.residents.res_old_kai.teaches!;
    expect(teaches[0]).toBe('dish_grilled_fish');
    s.cookbook.push('dish_grilled_fish');
    expect(lessonState(c, s, 'res_old_kai', T0).recipe).toBe(teaches.find(p => p !== 'dish_grilled_fish' && !s.cookbook.includes(p)));
    expect(lessonState(c, s, 'res_old_kai', T0).recipe).not.toBe('dish_grilled_fish');
  });
});
