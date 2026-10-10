/** SGODOT-283 fishing part 2 (plan §6.2.5–6.2.7, §6.3.1, §6.4; 李白 q(109)): a pond's fish by habitat, the city's
 * regional fish, time of day and weather; the Carbon Rod and the Spinner Lure. The shared vectors at the bottom are the
 * ones tests/p0/test_p0_fish_world.gd checks the client against. */
import { describe, expect, it } from 'vitest';
import { loadP0Content, type Fish } from '../../src/p0/content.js';
import { pickFish } from '../../src/p0/fishing.js';
import {
  bitesAt, daypart, everFish, forecast, hash01, pondAt, pondCity, pondFishIds, poolAt, regionalFish, timeWord, weatherDate, weatherOn,
  type Pond,
} from '../../src/p0/fishing_world.js';
import { applyP0, type P0Command } from '../../src/p0/reducer.js';
import { freshState, type P0State } from '../../src/p0/state.js';
import { HOME_ALIAS } from '../../src/p0/travel.js';
import { viewOf } from '../../src/p0/view.js';

const c = loadP0Content();
const SF = HOME_ALIAS['san francisco'], SH = HOME_ALIAS.shanghai, LA = HOME_ALIAS['los angeles'];
const FERN = 'pond_san_francisco_03', BLOSSOM = 'pond_san_francisco_06', CLOVER = 'pond_san_francisco_02';
const fish = (id: string) => c.fish.find(f => f.id === id) as Fish;
const ids = (tiers: { fish: Fish }[][]) => tiers.map(t => t.map(p => p.fish.id).sort());
// 2026-10-10 in San Francisco (PDT, UTC−7): 13:00 day, 06:00 dawn, 22:00 night
const SF_DAY = Date.UTC(2026, 9, 10, 20), SF_DAWN = Date.UTC(2026, 9, 10, 13), SF_NIGHT = Date.UTC(2026, 9, 11, 5);
const at = (part: Pond['part'], weather: Pond['weather'] = 'sun', regional = regionalFish(c, SF)): Pond =>
  ({ cluster: SF, tz: 'America/Los_Angeles', part, weather, regional });

describe('the pond and its city (§6.2.7)', () => {
  it('the San Francisco ponds are in the San Francisco cluster, on its clock and climate', () => {
    expect(pondCity(c, FERN)).toEqual({ cluster: SF, tz: 'America/Los_Angeles', climate: 'Temperate' });
  });

  it('dawn/dusk 05–08 and 17–20, night 20–05, by the pond city\'s clock', () => {
    const tz = 'America/Los_Angeles';
    expect(daypart(c, tz, SF_DAY)).toBe('day');
    expect(daypart(c, tz, SF_DAWN)).toBe('dawn_dusk');
    expect(daypart(c, tz, SF_NIGHT)).toBe('night');
    expect(daypart(c, tz, Date.UTC(2026, 9, 11, 0, 30))).toBe('dawn_dusk');   // 17:30
    expect(daypart(c, tz, Date.UTC(2026, 9, 10, 11, 59))).toBe('night');     // 04:59
    expect(daypart(c, 'Asia/Shanghai', SF_DAY)).toBe('night');                // the same instant is 04:00 the next day in Shanghai
    expect(daypart(c, 'Asia/Shanghai', SF_DAY + 2 * 3_600_000)).toBe('dawn_dusk');   // 06:00 in Shanghai, 15:00 in San Francisco
    expect(daypart(c, 'America/Los_Angeles', SF_DAY + 2 * 3_600_000)).toBe('day');
  });

  it('weather turns at 04:00 in the pond\'s city, so one night keeps one weather', () => {
    const tz = 'America/Los_Angeles';
    expect(weatherDate(c, tz, Date.UTC(2026, 9, 11, 5))).toBe('2026-10-10');    // 22:00 on the 10th
    expect(weatherDate(c, tz, Date.UTC(2026, 9, 11, 10, 59))).toBe('2026-10-10');   // 03:59 on the 11th
    expect(weatherDate(c, tz, Date.UTC(2026, 9, 11, 11))).toBe('2026-10-11');    // 04:00 on the 11th
  });

  it('weather is the same for everyone, and over many city-days near sun 50 / rain 30 / wind 20 (q(109))', () => {
    expect(weatherOn(c, SF, '2026-10-10')).toBe(weatherOn(c, SF, '2026-10-10'));
    const n = { sun: 0, rain: 0, wind: 0 };
    for (let d = 0; d < 3000; d++) n[weatherOn(c, `gn-${d}`, '2026-10-10')]++;
    expect(Math.abs(n.sun / 30 - 50)).toBeLessThanOrEqual(3);
    expect(Math.abs(n.rain / 30 - 30)).toBeLessThanOrEqual(3);
    expect(Math.abs(n.wind / 30 - 20)).toBeLessThanOrEqual(3);
  });
});

describe('the city\'s regional fish (§6.2.5, q(109))', () => {
  it('the hand-picked cities: San Francisco Arctic Char + Atlantic Salmon, Shanghai Grass Carp + Snakehead, Los Angeles Tilapia + Grass Carp', () => {
    expect(regionalFish(c, SF)).toEqual(['fish_arctic_char', 'fish_salmon']);
    expect(regionalFish(c, SH)).toEqual(['fish_grass_carp', 'fish_snakehead']);
    expect(regionalFish(c, LA)).toEqual(['fish_tilapia', 'fish_grass_carp']);
  });

  it('every city\'s first is a low-tier fish of its climate that bites in a Pond all day; the second another of its climate', () => {
    const groups = (c.fishing as unknown as { regional: { groups: Record<string, { low: string[]; high: string[] }>; curated: Record<string, string[]> } }).regional;
    const check = (cluster: string, climate: string) => {
      const [a, b] = regionalFish(c, cluster);
      const g = groups.groups[climate];
      expect(g.low, cluster).toContain(a);
      expect(fish(a).where).toContain('pond');
      expect(typeof fish(a).time, cluster).not.toBe('string');
      expect([...g.low, ...g.high].filter(x => x !== a)).toContain(b);
    };
    for (const [city, pair] of Object.entries(groups.curated)) {   // the hand-picked ones follow the same rule
      const cl = HOME_ALIAS[city];
      const climate = city === 'san francisco' ? 'Temperate' : 'Subtropical';
      expect(groups.groups[climate].low, city).toContain(pair[0]);
      check(cl, climate);
    }
    for (const [cl, climate] of [['gn-1850147', 'Temperate'], ['gn-2643743', 'Temperate'], ['gn-2673730', 'Cool'], ['gn-1880252', 'Tropical']] as const) {
      if (!regionalFish(c, cl).length) continue;   // a cluster this table does not have
      check(cl, climate);
    }
  });

  it('a city\'s pair is fixed: the same answer every time (no state)', () => {
    expect(regionalFish(c, 'gn-1850147')).toEqual(regionalFish(c, 'gn-1850147'));
  });
});

describe('a pond\'s fish (§6.2.6)', () => {
  it('Pond and River by day give exactly the fish P0 had there, plus the new global and San Francisco fish', () => {
    const pond = poolAt(c, c.fishing.sites.pond, at('day'));
    expect(ids(pond)).toEqual([
      ['fish_carp', 'fish_crucian'],
      ['fish_arctic_char', 'fish_bass', 'fish_perch'],
      ['fish_catfish', 'fish_koi'],
      ['fish_sturgeon'],
    ]);
    const river = poolAt(c, c.fishing.sites.river, at('day'));
    expect(ids(river)).toEqual([
      ['fish_carp', 'fish_crucian', 'fish_mullet'],
      ['fish_arctic_char', 'fish_bass', 'fish_perch', 'fish_trout'],
      ['fish_catfish'],
      ['fish_salmon', 'fish_sturgeon'],
    ]);
  });

  it('the River has a Rare fish now: Catfish, ×2 at night (the second stretch\'s point, §17.3.3)', () => {
    const night = poolAt(c, c.fishing.sites.river, at('night'));
    expect(night[2].find(p => p.fish.id === 'fish_catfish')!.weight).toBe(2);
    expect(night[3].map(p => p.fish.id)).toContain('fish_eel');   // River Eel: night only
    expect(poolAt(c, c.fishing.sites.river, at('day'))[3].map(p => p.fish.id)).not.toContain('fish_eel');
  });

  it('Coast (Clover Pond): Mullet, Mackerel, Sea Bass, Sturgeon and the city\'s Salmon', () => {
    expect(c.fishing.places[CLOVER].site).toBe('coast');
    expect(ids(poolAt(c, c.fishing.sites.coast, at('day')))).toEqual([['fish_mullet'], ['fish_mackerel'], ['fish_seabass'], ['fish_salmon', 'fish_sturgeon']]);
  });

  it('weights: global 1, the city\'s regional 2 (4 with a lure), times time and weather', () => {
    const rain = poolAt(c, c.fishing.sites.river, at('dawn_dusk', 'rain'));
    const w = (id: string) => rain.flat().find(p => p.fish.id === id)!.weight;
    expect(w('fish_crucian')).toBe(1);
    expect(w('fish_carp')).toBe(1.5);         // rain ×1.5
    expect(w('fish_trout')).toBe(2);          // rain ×2
    expect(w('fish_bass')).toBe(2);           // dawn/dusk ×2
    expect(w('fish_arctic_char')).toBe(4);    // regional 2 × dawn/dusk 2
    expect(w('fish_salmon')).toBe(8);         // regional 2 × dawn/dusk 2 × rain 2
    const lure = poolAt(c, c.fishing.sites.river, at('dawn_dusk', 'rain'), 2);
    expect(lure.flat().find(p => p.fish.id === 'fish_salmon')!.weight).toBe(16);
  });

  it('another climate\'s regional fish never swims here; *_only fish leave the pool outside their window', () => {
    expect(pondFishIds(c)).not.toContain('fish_tilapia');
    expect(pondFishIds(c)).not.toContain('fish_smelt');     // San Francisco's are Char and Salmon (q(109))
    expect(bitesAt(fish('fish_eel'), 'day')).toBe(false);
    expect(bitesAt(fish('fish_eel'), 'night')).toBe(true);
    expect(bitesAt(fish('fish_catfish'), 'day')).toBe(true);
  });

  it('every pond can give something at any time and weather (no empty pond)', () => {
    for (const site of Object.values(c.fishing.sites))
      for (const part of ['day', 'dawn_dusk', 'night'] as const)
        for (const weather of ['sun', 'rain', 'wind'] as const)
          expect(poolAt(c, site, at(part, weather)).flat().length, `${site.template} ${part} ${weather}`).toBeGreaterThan(0);
  });

  it('the beginner pond still has Pond Crucian, and every P0 fish is still caught somewhere', () => {
    expect(pondFishIds(c, FERN)).toContain('fish_crucian');
    for (const id of ['fish_crucian', 'fish_carp', 'fish_mullet', 'fish_perch', 'fish_bass', 'fish_trout', 'fish_mackerel', 'fish_koi'])
      expect(pondFishIds(c), id).toContain(id);
    expect(everFish(c, c.fishing.sites.pond, SF).map(f => f.id)).toContain('fish_koi');
  });
});

describe('the draw and the teaching pins', () => {
  const T0 = Date.UTC(2026, 9, 10, 20);
  const fresh = () => {
    const s = freshState(c, 'p1-fish-01', T0, 7);
    s.presence.place = FERN;
    return s;
  };

  it('bites 1–3 are Pond Crucian, bite 4 at Lv1 is Perch (Fern Pond), as in P0', () => {
    const s = fresh();
    const pond = pondAt(c, FERN, T0);
    for (let i = 0; i < 3; i++) { expect(pickFish(c, s, null, c.fishing.sites.pond, pond).id).toBe('fish_crucian'); s.fishing.bites++; }
    expect(pickFish(c, s, null, c.fishing.sites.pond, pond).id).toBe('fish_perch');
  });

  it('the draw follows the template weights by tier and the fish weights within one', () => {
    const s = fresh();
    s.fishing.bites = 10;
    s.skills.fishing = 100_000;
    const pond = at('dawn_dusk', 'rain');
    const n: Record<string, number> = {};
    for (let i = 0; i < 20000; i++) { const f = pickFish(c, s, null, c.fishing.sites.river, pond); n[f.id] = (n[f.id] ?? 0) + 1; }
    const tier = (r: number) => Object.entries(n).filter(([id]) => fish(id).rarity === r).reduce((a, [, k]) => a + k, 0) / 200;
    expect(Math.abs(tier(1) - 35)).toBeLessThanOrEqual(1.5);
    expect(Math.abs(tier(2) - 40)).toBeLessThanOrEqual(1.5);
    expect(Math.abs(tier(3) - 20)).toBeLessThanOrEqual(1.5);
    // Fine at dawn in the rain: bass 2, char 4, perch 1, trout 2 → char is 4 / 9 of Fine
    const fine = n.fish_bass + n.fish_arctic_char + n.fish_perch + n.fish_trout;
    expect(Math.abs(n.fish_arctic_char / fine - 4 / 9)).toBeLessThanOrEqual(0.02);
  });

  it('a tier with nothing in it gives its weight to the next one down', () => {
    const s = fresh();
    s.fishing.bites = 10;
    // a Pond at noon with no regional fish: Legendary has only Sturgeon; take it out by a content copy
    const k = structuredClone(c);
    k.fish = k.fish.filter(f => f.id !== 'fish_sturgeon');
    const n: Record<number, number> = {};
    for (let i = 0; i < 4000; i++) { const f = pickFish(k, s, null, k.fishing.sites.pond, at('day', 'sun', [])); n[f.rarity] = (n[f.rarity] ?? 0) + 1; }
    expect(n[4]).toBeUndefined();
    expect(Math.abs(n[3] / 40 - 10)).toBeLessThanOrEqual(1.5);   // Rare 9 + Legendary 1
  });
});

describe('Carbon Rod and Spinner Lure (§6.4)', () => {
  const T0 = Date.UTC(2026, 9, 10, 20);
  function step(s: P0State, cmd: P0Command, now = T0) {
    const r = applyP0(c, s, cmd, now);
    if (!r.ok) throw new Error(`${cmd.type}: ${r.code} ${JSON.stringify(r.detail ?? {})}`);
    return r.state;
  }

  it('the Carbon Rod: Fishing Lv6, 350 coins, lands Legendary, +0.8 s, +5 points, loss ×0.9, a 1.8 s bite span', () => {
    expect(c.fishing.rods.find(r => r.id === 'rod_carbon')).toEqual({ id: 'rod_carbon', name: 'Carbon Rod', reach: 4, level: 6,
      price: 350, hook_bonus_ms: 800, band_bonus: 0.05, loss_mult: 0.9, bite_spread_ms: 1800 });
    expect(c.tackle.buy).toContain('rod_carbon');
  });

  it('a Carbon Rod cast waits 1.8 + [0, 1.8) s; the view gives its bonuses for the minigame', () => {
    let s = freshState(c, 'p1-carbon-01', T0, 7);
    s.gear.rods.push('rod_carbon'); s.gear.rod = 'rod_carbon';
    s.fishing.bites = 10; s.energy.value = 200;
    s = step(s, { type: 'cast', space: 'pond', place: FERN });
    expect(s.cast!.bite_ms).toBeGreaterThanOrEqual(c.fishing.bite_min_ms);
    expect(s.cast!.bite_ms).toBeLessThan(c.fishing.bite_min_ms + 1800);
    const v = viewOf(c, s, T0).fishing;
    expect(v).toMatchObject({ rod: 'Carbon Rod', rod_reach: 4, hook_bonus_ms: 800, band_bonus: 0.05, loss_mult: 0.9 });
  });

  it('the Spinner Lure: Fishing Lv5, 6 coins, 10 a day, Common −15 / Fine −5 → Rare +15 / Legendary +5, regional ×2', () => {
    expect(c.goods.bait_lure).toEqual({ name: 'Spinner Lure', price: 6, skill: 'fishing', gate: 5, daily: 10 });
    expect(c.fishing.baits.bait_lure).toEqual({ shift: [-15, -5, 15, 5], wait: 1, regional_mult: 2 });
    expect(c.tackle.buy).toContain('bait_lure');
  });
});

describe('the card\'s words: Dawn / Dusk apart, and the 3-day forecast (283 e61cda10)', () => {
  it('the morning window is Dawn, the evening one Dusk', () => {
    expect(timeWord(c, 'America/Los_Angeles', SF_DAWN)).toBe('Dawn');                 // 06:00
    expect(timeWord(c, 'America/Los_Angeles', Date.UTC(2026, 9, 11, 0, 30))).toBe('Dusk');   // 17:30
    expect(timeWord(c, 'America/Los_Angeles', SF_DAY)).toBe('Day');
    expect(timeWord(c, 'America/Los_Angeles', SF_NIGHT)).toBe('Night');
  });
  it('the next three days in the pond\'s city, from its 04:00, today left out', () => {
    const f = forecast(c, SF, 'America/Los_Angeles', SF_DAY);   // Sat 10 Oct 2026, 13:00
    expect(f.map(d => d.day)).toEqual(['Sun', 'Mon', 'Tue']);
    // each day its own date's weather (不知火舞 on #262: Sun / Mon / Tue all Rain is this seed's 11–13 Oct, not one day thrice)
    expect(f.map(d => d.weather)).toEqual(['2026-10-11', '2026-10-12', '2026-10-13'].map(d => weatherOn(c, SF, d)));
    expect(forecast(c, SF, 'America/Los_Angeles', SF_DAY + 2 * 86_400_000).map(d => d.weather))
      .toEqual(['2026-10-13', '2026-10-14', '2026-10-15'].map(d => weatherOn(c, SF, d)));
    expect(new Set(['2026-10-13', '2026-10-14', '2026-10-15'].map(d => weatherOn(c, SF, d))).size).toBeGreaterThan(1);
    expect(forecast(c, SF, 'America/Los_Angeles', Date.UTC(2026, 9, 11, 10)).map(d => d.day)).toEqual(['Sun', 'Mon', 'Tue']);   // 03:00 Sun is still Sat
  });
});

describe('the pond view (the card\'s time of day and weather)', () => {
  it('each pond in the view says its time of day and today\'s weather', () => {
    const s = freshState(c, 'p1-view-01', SF_NIGHT, 7);
    const place = viewOf(c, s, SF_NIGHT).fishing.places[FERN] as { daypart: string; weather: string };
    expect(place.daypart).toBe('night');
    expect(['sun', 'rain', 'wind']).toContain(place.weather);
    expect(place.weather).toBe(weatherOn(c, SF, '2026-10-10'));
  });
});

/** The client's p0_fish_world.gd must give these same answers (tests/p0/test_p0_fish_world.gd). */
describe('shared vectors with the client', () => {
  it('hash01, weather and the generated regional pair', () => {
    expect(hash01('gensen-p1:weather:gn-5391959:2026-10-10').toFixed(8)).toBe(VECTORS.hash);
    expect(weatherOn(c, SF, '2026-10-10')).toBe(VECTORS.weather_sf);
    expect(weatherOn(c, SH, '2026-10-11')).toBe(VECTORS.weather_sh);
    expect(regionalFish(c, 'gn-1850147')).toEqual(VECTORS.regional_tokyo);
    expect(ids(poolAt(c, c.fishing.sites.river, at('night', 'rain')))).toEqual(VECTORS.river_rain_night);
  });
});

// Frozen: a change here is a change to every player's weather and every city's fish — bump fishing.regional.seed only on
// purpose, and update tests/p0/test_p0_fish_world.gd with it.
const VECTORS = {
  hash: '0.14122267',
  weather_sf: 'sun',
  weather_sh: 'sun',
  regional_tokyo: ['fish_grass_carp', 'fish_smelt'],
  river_rain_night: [['fish_carp', 'fish_crucian', 'fish_mullet'], ['fish_arctic_char', 'fish_bass', 'fish_perch', 'fish_trout'], ['fish_catfish'],
    ['fish_eel', 'fish_salmon', 'fish_sturgeon']],
};
