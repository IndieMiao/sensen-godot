/** SGODOT-275 (亚瑟's cross-city plan §6): from P1 on, each line adds its content in its own file under
 * assets/p0/content/, merged into the main table in name order. A fragment only adds: an id, a key or a scalar that
 * is already there fails loudly, naming the file and the path, so two lines can never change the same entry. */
import { mkdtempSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { CONTENT_FRAGMENT, DEFAULT_P0_CONTENT, itemName, loadP0Content, mergeContent, mergeContentDir, sellPriceOf } from '../../src/p0/content.js';
import { freshState } from '../../src/p0/state.js';
import { viewOf } from '../../src/p0/view.js';
import { worldOf } from '../../src/p0/world.js';

const base = () => ({
  crops: [{ id: 'crop_radish', energy: 2 }],
  shops: { market: { buy: ['seed_radish'] } },
  residents: { res_pip: { name: 'Pip' } },
  wallet_floor: 40,
});

describe('P0 content fragments (SGODOT-275)', () => {
  it('rejects divergent ore thresholds and accepts a jointly changed content/catalogue threshold', () => {
    const c = loadP0Content(), dir = mkdtempSync(path.join(tmpdir(), 'p0-mine-threshold-'));
    const file = path.join(dir, 'p0_content.json');
    const rule = (worldOf(c) as unknown as { wild: { mines: { vein: { main_from: number } } } }).wild.mines.vein;
    try {
      c.mine.types.vein.main_weight![1][0] = rule.main_from + 3;
      writeFileSync(file, JSON.stringify(c));
      expect(() => loadP0Content(file)).toThrow('main_weight[1].from must equal world.wild.mines.vein.main_from');
      rule.main_from = c.mine.types.vein.main_weight![1][0];
      writeFileSync(file, JSON.stringify(c));
      expect(loadP0Content(file).mine.types.vein.main_weight![1][0]).toBe(rule.main_from);
      c.mine.types.vein.main_weight!.pop();
      writeFileSync(file, JSON.stringify(c));
      expect(() => loadP0Content(file)).toThrow('main_weight[1].from must equal');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('exposes monster drop names and selling rules without redefining shared ore or flax', () => {
    const c = loadP0Content(), now = Date.UTC(2026, 10, 2), v = viewOf(c, freshState(c, 'mine-materials', now), now);
    const drops = {
      drop_t1_bat_wing: { name: 'Bat Wing', price: 4 },
      drop_t2_beetle_shell: { name: 'Beetle Shell', price: null, floor: 5 },
      drop_t2_glow_spore: { name: 'Glow Spores', price: 5 },
      drop_crown_shard: { name: 'Crown Shard', price: null },
    };
    for (const [id, def] of Object.entries(drops)) {
      expect(c.materials[id]).toEqual(def);
      expect(itemName(c, id)).toBe(def.name);
      expect(v.names[id]).toBe(def.name);
      expect(sellPriceOf(c, id)).toBe(def.price);
    }
    expect(c.materials.iron_ore).toEqual({ name: 'Iron Ore', price: null, floor: 5 });
    expect(c.materials.coal).toEqual({ name: 'Coal', price: 4 });
    expect(c.materials.flax).toEqual({ name: 'Flax', price: null, floor: 4 });
  });

  it('rejects unsupported mine fee periods while loading content', () => {
    const c = loadP0Content(), dir = mkdtempSync(path.join(tmpdir(), 'p0-mine-fee-'));
    const file = path.join(dir, 'p0_content.json');
    try {
      writeFileSync(file, JSON.stringify(c));
      expect(loadP0Content(file).mine.fee_per_day).toBe(true);
      c.mine.fee_per_day = false;
      writeFileSync(file, JSON.stringify(c));
      expect(() => loadP0Content(file)).toThrow('mine.fee_per_day must be true');
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('a fragment adds new ids, new keys and new entries without touching what is there', () => {
    const c = base();
    mergeContent(c, {
      _note: 'skipped',
      crops: [{ id: 'crop_corn', energy: 3 }],
      shops: { tea: { buy: ['drink_hot_tea'] }, market: { sells: ['seed_corn'] } },
      residents: { res_ama: { name: 'Ama' }, res_pip: { likes: ['dish_grilled_crucian'] } },
      fish_regional: [{ id: 'fish_smelt' }],
    }, 'farm_crops.json');
    expect(c.crops.map(x => x.id)).toEqual(['crop_radish', 'crop_corn']);
    expect(c.crops[0].energy).toBe(2);
    expect(c.shops).toEqual({ market: { buy: ['seed_radish'], sells: ['seed_corn'] }, tea: { buy: ['drink_hot_tea'] } });
    expect(c.residents.res_pip).toEqual({ name: 'Pip', likes: ['dish_grilled_crucian'] });
    expect(c).not.toHaveProperty('_note');
    expect((c as Record<string, unknown>).fish_regional).toEqual([{ id: 'fish_smelt' }]);
  });

  it('an id already there, a key already set or a plain list fails with the file and the path', () => {
    expect(() => mergeContent(base(), { crops: [{ id: 'crop_radish', energy: 9 }] }, 'farm_crops.json'))
      .toThrow('p0 content: farm_crops.json: crops already has id crop_radish');
    expect(() => mergeContent(base(), { residents: { res_pip: { name: 'Pippa' } } }, 'res_p1.json'))
      .toThrow('p0 content: res_p1.json: residents.res_pip.name is already set');
    expect(() => mergeContent(base(), { wallet_floor: 50 }, 'econ_p1.json')).toThrow('wallet_floor is already set');
    expect(() => mergeContent(base(), { shops: { market: { buy: ['seed_corn'] } } }, 'farm_crops.json'))
      .toThrow('shops.market.buy is already set');   // a list without ids cannot be merged safely
    // A clash inside one fragment, or between two fragments, is the same error.
    expect(() => mergeContent(base(), { crops: [{ id: 'crop_corn' }, { id: 'crop_corn' }] }, 'farm_crops.json'))
      .toThrow('crops already has id crop_corn');
  });

  it('a content folder merges in name order and its names must be <line>_<topic>.json', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-content-'));
    writeFileSync(path.join(dir, 'fish_p1.json'), JSON.stringify({ fish: [{ id: 'fish_smelt' }] }));
    writeFileSync(path.join(dir, 'farm_crops.json'), JSON.stringify({ crops: [{ id: 'crop_corn' }] }));
    const c: Record<string, unknown> = { crops: [], fish: [] };
    expect(mergeContentDir(c, dir)).toEqual(['farm_crops.json', 'fish_p1.json']);
    expect(c).toEqual({ crops: [{ id: 'crop_corn' }], fish: [{ id: 'fish_smelt' }] });
    writeFileSync(path.join(dir, 'Farm Crops.json'), '{}');
    expect(() => mergeContentDir({}, dir)).toThrow('Farm Crops.json: name must be <line>_<topic>.json');
    expect(mergeContentDir({}, path.join(dir, 'missing'))).toEqual([]);
  });

  it("the repo's fragments load, and every item id is unique across crops, seeds, fish, dishes, goods and gear", () => {
    const dir = path.join(path.dirname(DEFAULT_P0_CONTENT), 'content');
    for (const f of readdirSync(dir).filter(f => f.endsWith('.json'))) expect(f).toMatch(CONTENT_FRAGMENT);
    const c = loadP0Content();
    const ids = [
      ...c.crops.flatMap(x => [x.id, x.seed]),
      ...(c.fast_crops ?? []).flatMap(x => [x.id, x.seed]),
      ...(c.quick_seeds ?? []).flatMap(x => [x.id, x.seed]),
      ...c.fish.map(x => x.id),
      ...c.cooking.recipes.map(x => x.id),
      ...Object.keys(c.goods), ...Object.keys(c.materials), ...Object.keys(c.drinks.items), ...Object.keys(c.specialty),
      ...c.fishing.rods.map(x => x.id),
      ...Object.keys(c.tools.names),
    ];
    const seen = new Set<string>();
    const twice = ids.filter(id => (seen.has(id) ? true : (seen.add(id), false)));
    expect(twice).toEqual([]);
  });
});
