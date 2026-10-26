import { describe, expect, it } from 'vitest';
import { itemKind, loadP0Content, recipeById } from '../../src/p0/content.js';
import { applyP0, count, type P0Command, type P0Event } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { pageState } from '../../src/p0/cookbook.js';
import { likesDish, residentState } from '../../src/p0/residents.js';

// P1 residents (SGODOT-284): the other ten of §9.4.3, the 24 h request gap (§9.6.1), lessons (§7.5.3), story rewards.
const content = loadP0Content();
const c = { ...content, profile: { ...content.profile, timezone: 'Asia/Shanghai' } };
const T0 = Date.UTC(2026, 9, 10, 2, 0, 0);
const H = 3_600_000, DAY = 24 * H;

function step(s: P0State, cmd: P0Command, now = T0): { s: P0State; ev: P0Event[] } {
  const r = applyP0(c, s, cmd, now);
  if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
  return { s: r.state, ev: r.events };
}
const refuse = (s: P0State, cmd: P0Command, now = T0) => applyP0(c, s, cmd, now);
const fresh = () => ({ ...freshState(c, 'player-p1-res', T0, 3), created_at: T0 - 8 * DAY });
const at = (s: P0State, id: string, affinity: number) => {
  s.residents[id] = { affinity, chat_day: '', gift_day: '', next: 0, req: null, done_day: '' };
  return s;
};

describe('the twelve residents (§9.4.3)', () => {
  const ids = ['res_pip', 'res_granny_wu', 'res_mira', 'res_old_kai', 'res_rafa', 'res_ivo', 'res_hana', 'res_sam', 'res_lena', 'res_tomo', 'res_theo', 'res_nadia'];

  it('all twelve are in the table with 3–6 requests each, lines for every stage and a Common gift meal', () => {
    expect(Object.keys(c.residents).sort()).toEqual([...ids].sort());
    const stages = c.affinity.stages.map(([n]) => n);
    for (const id of ids) {
      const d = c.residents[id];
      expect(d.requests.length, id).toBeGreaterThanOrEqual(3);
      expect(d.requests.length, id).toBeLessThanOrEqual(6);
      if (id !== 'res_pip' && id !== 'res_old_kai') for (const st of stages) expect(d.lines[st], `${id} ${st}`).toBeTruthy();
      expect(itemKind(d.gift_meal), id).toBe('dish');
      expect(recipeById(c, d.gift_meal), id).toBeTruthy();
      for (const p of d.teaches ?? []) expect(recipeById(c, p), `${id} teaches ${p}`).toBeTruthy();
    }
  });

  it('every request asks for something that exists, in stage order, and pays 20–100 coins (§9.13.2)', () => {
    const stages = c.affinity.stages.map(([n]) => n);
    const ids = new Set<string>();
    for (const [rid, d] of Object.entries(c.residents)) {
      let last = 0;
      for (const q of d.requests) {
        expect(ids.has(q.id), q.id).toBe(false);
        ids.add(q.id);
        expect(q.id.startsWith('req_res_'), q.id).toBe(true);
        const st = stages.indexOf(q.stage);
        expect(st, q.id).toBeGreaterThanOrEqual(last);
        last = st;
        expect(q.coins, q.id).toBeGreaterThanOrEqual(20);
        expect(q.coins, q.id).toBeLessThanOrEqual(100);
        if (q.need.id) {
          const known = q.need.kind === 'dish' ? !!recipeById(c, q.need.id) : q.need.kind === 'material' ? !!c.materials[q.need.id]
            : q.need.kind === 'crop' ? c.crops.some(x => x.id === q.need.id) : c.fish.some(x => x.id === q.need.id);
          expect(known, `${rid} ${q.id}`).toBe(true);
        }
        if (q.need.style) expect(c.cooking.recipes.some(r => r.style === q.need.style), q.id).toBe(true);
        // §9.6.2: system requests top out at Fine; Rare asks belong to Old Kai, Lena, Tomo (and the trader Mira)
        if ((q.need.rarity ?? 0) >= 3 && q.need.kind === 'fish') expect(['res_old_kai', 'res_lena', 'res_tomo', 'res_mira']).toContain(rid);
      }
    }
  });
});

describe('a P1 resident request line (§9.6.1)', () => {
  it('Granny Wu: wood, then the next one 24 h after delivery once Acquainted; the bag pays the floor first', () => {
    let s = fresh();
    expect(viewOf(c, s, T0).residents.res_granny_wu).toMatchObject({ request_state: 'open', request: { id: 'req_res_wu_1', kind: 'material', item: 'wood', qty: 6 } });
    s = step(s, { type: 'accept', request: 'req_res_wu_1' }).s;
    s.storage.wood = 6;
    const r = step(s, { type: 'deliver', request: 'req_res_wu_1' }, T0 + H);
    expect(r.s.storage.wood ?? 0).toBe(0);
    expect(r.s.residents.res_granny_wu).toMatchObject({ affinity: 5, done_at: T0 + H });
    // Stranger still: the second (Something Warm) needs Acquainted
    expect(viewOf(c, r.s, T0 + 2 * DAY).residents.res_granny_wu).toMatchObject({ request_state: 'stage', need_stage: 'Acquainted' });
    r.s.residents.res_granny_wu.affinity = 15;
    expect(viewOf(c, r.s, T0 + 20 * H).residents.res_granny_wu).toMatchObject({ request_state: 'wait', next_in: 5 * H });
    expect(refuse(r.s, { type: 'accept', request: 'req_res_wu_2' }, T0 + 20 * H)).toMatchObject({ ok: false, code: 'request_wait', detail: { next_in: 5 * H } });
    expect(viewOf(c, r.s, T0 + 25 * H).residents.res_granny_wu).toMatchObject({ request_state: 'open', request: { id: 'req_res_wu_2', kind: 'dish', style: 'Soup' } });
  });

  it('a style request takes only dishes of that style; a named dish only that dish', () => {
    let s = at(fresh(), 'res_granny_wu', 20);
    s.residents.res_granny_wu.next = 1;
    s = step(s, { type: 'accept', request: 'req_res_wu_2' }).s;
    s.bag.push({ id: 'dish_carrot_cake', qty: 1 });
    expect(refuse(s, { type: 'deliver', request: 'req_res_wu_2' })).toMatchObject({ ok: false, code: 'not_enough' });
    s.bag.push({ id: 'dish_fish_soup', qty: 1 });
    const r = step(s, { type: 'deliver', request: 'req_res_wu_2' });
    expect(count(r.s.bag, 'dish_fish_soup')).toBe(0);
    expect(count(r.s.bag, 'dish_carrot_cake')).toBe(1);
  });

  it('a Trusted story request gives its title once (§9.4.4)', () => {
    let s = at(fresh(), 'res_sam', 95);
    s.residents.res_sam.next = 2;
    s = step(s, { type: 'accept', request: 'req_res_sam_3' }).s;
    s.bag.push({ id: 'dish_grilled_fish', qty: 2 });
    const r = step(s, { type: 'deliver', request: 'req_res_sam_3' });
    expect(r.ev).toContainEqual({ kind: 'title', id: 'On Schedule', resident: 'res_sam' });
    expect(r.s.rewards).toContain('title:On Schedule');
    expect(viewOf(c, r.s, T0 + 2 * DAY).residents.res_sam.request_state).toBe('none');
  });

  it('a request line can hand over a Cookbook page (§7.16.3 bracketed pages): Tasted, said as a lesson', () => {
    let s = at(fresh(), 'res_rafa', 20);
    s.residents.res_rafa.next = 2;
    s = step(s, { type: 'accept', request: 'req_res_rafa_3' }).s;
    s.bag.push({ id: 'dish_fish_soup', qty: 9 });
    const r = step(s, { type: 'deliver', request: 'req_res_rafa_3' });
    expect(r.ev).toContainEqual({ kind: 'recipe', page: 'dish_catfish_stew', from: 'request', resident: 'res_rafa' });
    expect(pageState(c, r.s, 'dish_catfish_stew')).toBe('tasted');
    expect(count(r.s.bag, 'recipe:dish_catfish_stew')).toBe(0);
  });
});

describe('likes by rarity (§7.16.3: Hana Fine+, Mira and Tomo Rare+)', () => {
  it('Hana loves a Fine dish of any style, and takes a Common one as a plain gift', () => {
    const s = fresh();
    for (const id of ['res_hana', 'res_mira']) residentState(s, id).gift_day = '2026-01-01';   // given before: q(220)'s first-gift +10 is spent
    s.bag.push({ id: 'dish_fruit_tea', qty: 1 }, { id: 'dish_radish_salad', qty: 1 }, { id: 'dish_smoked_trout', qty: 1 });
    const aff = (ev: P0Event[]) => ev.find(e => e.kind === 'affinity');
    expect(aff(step(s, { type: 'gift', resident: 'res_hana', item: 'dish_fruit_tea' }).ev)).toMatchObject({ delta: 3, verdict: 'loved' });
    expect(aff(step(s, { type: 'gift', resident: 'res_hana', item: 'dish_radish_salad' }).ev)).toMatchObject({ delta: 1, verdict: 'received' });
    expect(aff(step(s, { type: 'gift', resident: 'res_mira', item: 'dish_fruit_tea' }).ev)).toMatchObject({ delta: 1 });
    expect(aff(step(s, { type: 'gift', resident: 'res_mira', item: 'dish_smoked_trout' }).ev)).toMatchObject({ delta: 3, verdict: 'loved' });
  });
});

describe('Recipe lesson (§7.5.3 Taught)', () => {
  const page = (id: string) => recipeById(c, id)!.n;
  const pages = (id: string) => (c.residents[id].teaches ?? []).map(page);
  // §7.16.3 by Cookbook page; Mira: any Rare / Legendary, these four first. Request lines give the bracketed pages as cards.
  const plan: Record<string, number[]> = {
    res_pip: [7, 22, 38, 39], res_granny_wu: [12, 16, 31, 47], res_mira: [34, 36, 41, 45], res_old_kai: [2, 15, 23, 26, 28, 33, 44],
    res_theo: [6, 13, 18, 24], res_hana: [22, 38, 39, 46], res_sam: [3, 4, 14], res_lena: [19, 20, 40], res_nadia: [8, 17, 27, 32, 37],
    res_ivo: [11, 29, 33], res_tomo: [40, 41, 42], res_rafa: [12, 30, 48],
  };
  const line: Record<string, number[]> = { res_granny_wu: [30, 48], res_lena: [35, 43], res_nadia: [21, 25], res_rafa: [32, 37] };

  it('each resident teaches the pages of §7.16.3, all in the style they like', () => {
    for (const [id, want] of Object.entries(plan)) {
      const def = c.residents[id];
      if (id === 'res_mira') {
        expect(pages(id).slice(0, 4), id).toEqual(want);
        const rarePlus = c.cooking.recipes.filter(r => (r.rarity ?? 0) >= 3).map(r => r.n!);
        expect(pages(id).slice(4), id).toEqual(rarePlus.filter(n => !want.includes(n)));   // the rest by page, the order she teaches
      } else expect(pages(id), id).toEqual(want);
      for (const p of def.teaches ?? []) {
        const r = recipeById(c, p)!;
        expect(likesDish(c, def, r.style, r.rarity ?? 1), `${id} likes #${r.n} ${r.style}`).toBe(true);
      }
    }
  });

  it('the bracketed pages come with the request line: Acquainted request 3, then the Trusted one', () => {
    for (const [id, want] of Object.entries(line)) {
      const got = c.residents[id].requests.map(q => q.reward?.recipe).filter((p): p is string => !!p).map(page);
      expect(got, id).toEqual(want);
    }
  });

  it('from Familiar, one page a week the player does not have yet; Tasted, not Discovered', () => {
    const [first, second] = c.residents.res_old_kai.teaches!;
    let s = fresh();
    expect(viewOf(c, s, T0).residents.res_old_kai.lesson).toMatchObject({ state: 'stage', need_stage: 'Familiar' });
    expect(refuse(s, { type: 'learn', resident: 'res_old_kai' })).toMatchObject({ ok: false, code: 'lesson_stage' });
    s = at(s, 'res_old_kai', 45);
    expect(viewOf(c, s, T0).residents.res_old_kai.lesson).toMatchObject({ state: 'ready', recipe: first });
    const r = step(s, { type: 'learn', resident: 'res_old_kai' });
    expect(r.ev).toContainEqual({ kind: 'recipe', page: first, from: 'taught', resident: 'res_old_kai' });
    expect(r.s.cookbook).toContain(first);
    expect(pageState(c, r.s, first)).toBe('tasted');
    expect(refuse(r.s, { type: 'learn', resident: 'res_old_kai' }, T0 + 6 * DAY)).toMatchObject({ ok: false, code: 'lesson_wait', detail: { next_in: DAY } });
    expect(viewOf(c, r.s, T0 + 7 * DAY).residents.res_old_kai.lesson).toMatchObject({ state: 'ready', recipe: second });
  });

  it('a page the player already has is skipped; none left means no lesson', () => {
    const lena = c.residents.res_lena.teaches!;
    const s = at(fresh(), 'res_lena', 60);
    expect(viewOf(c, s, T0).residents.res_lena.lesson).toMatchObject({ state: 'ready', recipe: lena[0] });
    s.cookbook.push(...lena.slice(0, -1));
    expect(viewOf(c, s, T0).residents.res_lena.lesson).toMatchObject({ state: 'ready', recipe: lena.at(-1) });
    s.cookbook.push(lena.at(-1)!);
    expect(viewOf(c, s, T0).residents.res_lena.lesson).toMatchObject({ state: 'none', recipe: null });
    expect(refuse(s, { type: 'learn', resident: 'res_lena' })).toMatchObject({ ok: false, code: 'no_lesson' });
  });
});
