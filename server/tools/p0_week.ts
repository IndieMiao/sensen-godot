/**
 * Seven days of the §14.6 target player against the real P0 rules (SGODOT-232 V2): a scripted player, not a model.
 * Morning 08:00 for 15 minutes (harvest, sell, buy seeds, sow ~110 Energy, gather), evening 20:00 for 30 minutes
 * (a mine run on odd days from day 3, 25 casts, cooking new pages first, then dinner); day 1 starts with the
 * first session at 12:00. The read-out is the §14.6.2 P0 rerun's: Energy spent per day, XP and levels, Homestead,
 * wallet, Cookbook and Fish-dex. `node --import tsx tools/p0_week.ts [--players 6] [--days 7] [--json out.json]`.
 */
import { writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadP0Content, recipeById, type P0Content } from '../src/p0/content.js';
import { ingredientsFor, mealValue } from '../src/p0/cooking.js';
import { applyP0, count, type P0Command, type P0Event } from '../src/p0/reducer.js';
import { dayKey, maxEnergy, skillLevel } from '../src/p0/rules.js';
import { freshState, type P0State } from '../src/p0/state.js';

const MIN = 60_000, SEC = 1000;
const REED = 'pond_shanghai_05', PEBBLE = 'pond_shanghai_04';   // Pond and River templates in Shanghai (q(36))
const FARM_ENERGY = 110, CASTS = 25, POTS = 5, WORMS = 10, SEED_RESERVE = 60, KEEP_CROP = 3, KEEP_FISH = 2;

export interface DayStats {
  day: number; spent: number; walls: number; farming: number; fishing: number; cooking: number;
  levels: { farming: number; fishing: number; cooking: number }; homestead: number; coins: number;
  cookbook: number; fishdex: number; three_slot: number;
}

/** Local Shanghai wall clock (UTC+8) of day d (1-based) at hh:mm, the first day being 2026-10-08. */
const local = (d: number, hh: number, mm = 0) => Date.UTC(2026, 9, 7 + d, hh - 8, mm);

export class WeekPlayer {
  s: P0State;
  t = 0;
  log: { t: number; cmd: P0Command; events: P0Event[] }[] = [];
  walls = 0;
  reached: Record<string, number> = {};
  private day = 1;
  constructor(private c: P0Content, player: string, start: number) { this.s = freshState(c, player, start); this.t = start; }

  /** Apply one command `gap` after the last; refusals are returned, never thrown (a real player just moves on). */
  act(cmd: P0Command, gap = 5 * SEC): { ok: boolean; code?: string; events: P0Event[] } {
    this.t += gap;
    const r = applyP0(this.c, this.s, cmd, this.t);
    if (!r.ok) {
      if (r.code === 'need_energy') this.walls += 1;
      return { ok: false, code: r.code, events: [] };
    }
    this.s = r.state;
    this.log.push({ t: this.t, cmd, events: r.events });
    for (const e of r.events) if (e.kind === 'level') this.reached[`${e.skill}_lv${e.level}`] ??= this.day;
    for (const e of r.events) if (e.kind === 'homestead') this.reached[`homestead_lv${e.level}`] ??= this.day;
    return { ok: true, events: r.events };
  }
  lv(skill: 'farming' | 'fishing' | 'cooking') { return skillLevel(this.c, this.s, skill); }
  stored(id: string) { return count(this.s.bag, id) + (this.s.storage[id] ?? 0); }

  // ------------------------------------------------------------------ farm
  harvestAll(): void {
    for (const p of this.s.plots) if (p.state === 'sown') this.act({ type: 'water', plot: p.id, space: 'home' }, 2 * SEC);
    for (const p of this.s.plots) {
      if (!p.crop || !p.ready_at || p.ready_at > this.t) continue;
      let r = this.act({ type: 'harvest', plot: p.id, space: 'home' }, 3 * SEC);
      if (!r.ok && r.code === 'bag_full') { this.sellSurplus(); r = this.act({ type: 'harvest', plot: p.id, space: 'home' }, 3 * SEC); }
    }
  }
  sellSurplus(): void {
    for (const b of [...this.s.bag]) {
      const kind = b.id.split('_')[0];
      const keep = kind === 'crop' ? KEEP_CROP : kind === 'fish' ? KEEP_FISH : null;
      if (keep === null || b.gift) continue;
      const extra = count(this.s.bag, b.id) - keep;
      if (extra > 0) this.act({ type: 'sell', item: b.id, qty: extra, shop: 'homestead', space: 'home' }, 2 * SEC);
    }
  }
  gatherAll(): void {
    for (const spot of Object.keys(this.c.gather.spots)) this.act({ type: 'gather', spot, space: 'home' }, 8 * SEC);
  }
  /** Fill empty beds within the morning budget: crops never harvested first, then the higher-level ones. */
  sowMorning(): void {
    const crops = this.c.crops.filter(cr => cr.level <= this.lv('farming'))
      .sort((a, b) => Number(this.s.firsts.includes(`harvest:${a.id}`)) - Number(this.s.firsts.includes(`harvest:${b.id}`)) || b.level - a.level);
    const empty = this.s.plots.filter(p => p.state === 'tilled' && !p.crop).map(p => p.id);
    for (const p of this.s.plots.filter(pl => pl.state === 'wild')) { this.act({ type: 'till', plot: p.id, space: 'home' }, 2 * SEC); empty.push(p.id); }
    const reserve = SEED_RESERVE + (this.homesteadReady() ? this.c.homestead.levels[0].coins : 0);
    let budget = FARM_ENERGY, i = 0;
    while (empty.length && budget > 0 && crops.length) {
      const crop = crops[i % crops.length]; i += 1;
      if (i > crops.length * 8) break;
      const n = Math.min(5, empty.length, Math.floor(budget / crop.energy), Math.floor((this.s.coins - reserve) / Math.max(1, crop.seed_price)));
      if (n <= 0) continue;
      const have = count(this.s.bag, crop.seed);
      if (have < n && !this.act({ type: 'buy', item: crop.seed, qty: n - have, shop: 'homestead', space: 'home' }, 2 * SEC).ok) continue;
      for (const plot of empty.splice(0, n)) {
        if (!this.act({ type: 'sow', plot, seed: crop.seed, space: 'home' }, 4 * SEC).ok) break;
        this.act({ type: 'water', plot, space: 'home' }, 2 * SEC);
        budget -= crop.energy;
      }
    }
  }
  homesteadReady(): boolean {
    const next = this.c.homestead.levels.find(l => l.level === this.s.homestead.level + 1);
    return !!next && next.materials.every(([id, n]) => this.stored(id) >= n);
  }

  // ------------------------------------------------------------------ requests
  requests(): void {
    for (const slot of [...this.s.boards.stall, ...this.s.boards.market]) {
      const req = slot.req;
      if (!req || req.status === 'done') continue;
      const item = req.items.find(id => count(this.s.bag, id) >= req.qty);
      if (!item) continue;
      if (req.status === 'open') this.act({ type: 'accept', request: req.id, space: 'home' });
      this.act({ type: 'deliver', request: req.id, space: 'home' });
    }
  }

  /** Free bag slots for a mine run (a floor needs room for one rock's worst case, q(44)): sell the biggest stacks. */
  makeRoom(slots: number): void {
    this.sellSurplus();
    const sellable = () => this.s.bag.filter(b => !b.gift && /^(crop|fish|dish)_/.test(b.id)).sort((a, b) => b.qty - a.qty);
    while (this.s.bag_cap - this.s.bag.length < slots && sellable().length) {
      const b = sellable()[0];
      if (!this.act({ type: 'sell', item: b.id, qty: b.qty, shop: 'homestead', space: 'home' }, 2 * SEC).ok) break;
    }
  }

  // ------------------------------------------------------------------ mine
  mineRun(): void {
    this.makeRoom(4);
    if (!this.act({ type: 'mine_enter', space: 'home' }, 20 * SEC).ok) return;
    for (const floor of [1, 2]) {
      if (floor === 2 && !this.act({ type: 'mine_floor', floor, space: 'mine' }, 10 * SEC).ok) break;
      for (let rock = 0; rock < this.c.mine.rocks; rock++) if (!this.act({ type: 'mine_rock', floor, rock, space: 'mine' }, 6 * SEC).ok) return;
    }
    this.act({ type: 'read_inbox', keys: [], space: 'home' }, 20 * SEC);   // back home: materials go to storage
  }

  // ------------------------------------------------------------------ fishing
  fishEvening(): void {
    const rodReed = this.s.gear.rods.includes('rod_reed');
    if (!rodReed && this.lv('fishing') >= 3 && this.s.coins >= 80 + SEED_RESERVE) {
      if (this.act({ type: 'buy', item: 'rod_reed', qty: 1, shop: 'tackle' }).ok) this.act({ type: 'equip', item: 'rod_reed' });
    }
    if (this.lv('fishing') >= 2) {
      const want = WORMS - count(this.s.bag, 'bait_worm');
      if (want > 0) this.act({ type: 'buy', item: 'bait_worm', qty: want, shop: 'homestead', space: 'home' });
    }
    const place = this.lv('fishing') >= 4 && this.s.gear.rod === 'rod_reed' ? PEBBLE : REED;
    for (let i = 0; i < CASTS; i++) {
      const bait = count(this.s.bag, 'bait_worm') > 0 ? 'bait_worm' : undefined;
      let cast = this.act({ type: 'cast', space: 'pond', place, ...(bait ? { bait } : {}) }, 10 * SEC);
      if (!cast.ok && (cast.code === 'creel_full' || cast.code === 'bag_full')) {
        this.act({ type: 'read_inbox', keys: [], space: 'home' }, 60 * SEC);
        this.sellSurplus();
        cast = this.act({ type: 'cast', space: 'pond', place, ...(bait ? { bait } : {}) }, 60 * SEC);
      }
      if (!cast.ok) break;
      this.act({ type: 'reel', outcome: 'landed', space: 'pond', place }, (this.s.cast?.bite_ms ?? 3000) + 25 * SEC);
    }
  }

  // ------------------------------------------------------------------ kitchen
  /** A pot: tap the middle of every gold arc (one Good / Perfect pot as a practised player makes), eat or keep. */
  cookPot(cmd: { recipe?: string; items?: string[] }): boolean {
    if (!this.act({ type: 'cook', ...cmd, space: 'home' }, 15 * SEC).ok) return false;
    const pot = this.s.stove!;
    const taps = pot.heats.map(h => h.at + (h.gold + h.width / 2) * h.spin);
    const dish = cmd.recipe ?? pot.dish;
    const hungry = maxEnergy(this.c, this.s) - this.s.energy.value >= mealValue(this.c, this.s, dish) && this.s.day.meals < 300;
    const r = this.act({ type: 'collect', taps, eat: hungry, pot: pot.id, space: 'home' }, pot.ms + 2 * SEC);
    if (!r.ok) this.act({ type: 'collect', taps, pot: pot.id, space: 'home' }, SEC);
    return true;
  }
  saltSpare(): number {
    const keep = this.s.homestead.level < 2 ? 3 : this.s.homestead.level < 3 ? 4 : 0;
    return this.stored('rock_salt') - keep;
  }
  makeable(id: string): string[] | null {
    const recipe = recipeById(this.c, id);
    if (!recipe) return null;
    const items = ingredientsFor(this.c, this.s, recipe);
    if (!items) return null;
    const salt = items.filter(x => x === 'rock_salt').length;
    if (salt > 0 && salt > this.saltSpare()) return null;   // Rock Salt kept for the next Homestead level (§14.6.2)
    return items;
  }
  kitchen(): void {
    this.act({ type: 'homestead_upgrade', space: 'home' });
    if (this.s.homestead.level >= 2 && !this.s.gear.picks.includes('pick_copper')
        && this.act({ type: 'craft', recipe: 'craft_copper_pickaxe', space: 'home' }).ok) this.act({ type: 'equip', item: 'pick_copper' });
    let pots = 0, experiments = 0;
    // 1) pages known but never cooked; 2) a hidden page the player works out (≈ 1.5 a day); 3) dinner from the best page
    for (const id of this.s.cookbook) {
      if (pots >= POTS) break;
      if ((this.s.book.cooked[id] ?? 0) > 0 || !this.makeable(id)) continue;
      if (this.cookPot({ recipe: id })) pots += 1;
    }
    for (const r of this.c.cooking.recipes) {
      if (pots >= POTS || experiments >= 2) break;
      if (this.s.cookbook.includes(r.id)) continue;
      const items = this.makeable(r.id);
      if (!items || items.length > (this.lv('cooking') >= 4 ? 3 : 2)) continue;
      if (this.cookPot({ items })) { pots += 1; experiments += 1; }
    }
    // dinner: pages that still pay XP today (same page: full, half, then none, §7.6.2), the most filling first; what
    // is not eaten is kept for tomorrow (§14.6: 3–5 pots an evening)
    const today = (id: string) => this.s.day.cooked[id] ?? 0;
    const best = () => this.s.cookbook.filter(id => today(id) < 2 && this.makeable(id))
      .sort((a, b) => today(a) - today(b) || mealValue(this.c, this.s, b) - mealValue(this.c, this.s, a))[0];
    while (pots < POTS && this.s.bag.length < this.s.bag_cap - 2) {
      const id = best();
      if (!id || !this.cookPot({ recipe: id })) break;
      pots += 1;
    }
    // dishes kept earlier fill what is left of today's meals
    for (const b of [...this.s.bag]) {
      if (!b.id.startsWith('dish_')) continue;
      if (maxEnergy(this.c, this.s) - this.s.energy.value < mealValue(this.c, this.s, b.id)) continue;
      this.act({ type: 'eat', item: b.id, space: 'home' }, 3 * SEC);
    }
  }

  // ------------------------------------------------------------------ the week
  firstSession(): void {
    const at = (m: number) => local(1, 12, 0) + m * MIN;
    this.t = at(0);
    for (let i = 0; i < 20; i++) this.act({ type: 'sow', plot: i, seed: 'seed_radish', space: 'home' }, 6 * SEC);
    for (let i = 0; i < 20; i++) this.act({ type: 'water', plot: i, space: 'home' }, SEC);
    this.act({ type: 'accept', request: 'req_pond_catch', space: 'home' }, 60 * SEC);
    this.t = at(9);
    while (count(this.s.bag, 'fish_crucian') < 3) { this.act({ type: 'cast', space: 'pond', place: REED }, 10 * SEC); this.act({ type: 'reel', outcome: 'landed', space: 'pond', place: REED }, (this.s.cast?.bite_ms ?? 3000) + 25 * SEC); }
    this.act({ type: 'deliver', request: 'req_pond_catch', space: 'home' }, 60 * SEC);
    this.cookPot({ recipe: 'dish_grilled_crucian' });
    for (let i = 20; i < 30; i++) this.act({ type: 'till', plot: i, space: 'home' }, 3 * SEC);
    for (let i = 20; i < 30; i++) this.act({ type: 'sow', plot: i, seed: 'seed_lettuce', space: 'home' }, 6 * SEC);
    for (let i = 20; i < 30; i++) this.act({ type: 'water', plot: i, space: 'home' }, SEC);   // the key turns to Water · Free
    let casts = 0;
    while (this.lv('fishing') < 2 && casts++ < 15) { this.act({ type: 'cast', space: 'pond', place: REED }, 10 * SEC); this.act({ type: 'reel', outcome: 'landed', space: 'pond', place: REED }, (this.s.cast?.bite_ms ?? 3000) + 25 * SEC); }
    this.act({ type: 'cast', space: 'pond', place: REED, bait: 'bait_worm' }, 10 * SEC);
    this.act({ type: 'reel', outcome: 'landed', space: 'pond', place: REED }, (this.s.cast?.bite_ms ?? 2000) + 25 * SEC);
    this.cookPot({ recipe: 'dish_herb_grilled_fish' });
  }
  morning(d: number): void {
    this.t = Math.max(this.t, local(d, 8));
    this.act({ type: 'read_inbox', keys: [], space: 'home' }, SEC);
    this.harvestAll(); this.sellSurplus(); this.requests(); this.gatherAll(); this.sowMorning();
    this.act({ type: 'homestead_upgrade', space: 'home' });
  }
  evening(d: number): void {
    this.t = Math.max(this.t, local(d, 20));
    this.act({ type: 'read_inbox', keys: [], space: 'home' }, SEC);
    this.harvestAll(); this.sellSurplus(); this.requests();
    if (d >= 3 && d % 2 === 1) this.mineRun();
    this.fishEvening();
    this.act({ type: 'read_inbox', keys: [], space: 'home' }, 60 * SEC);
    this.requests(); this.kitchen(); this.sellSurplus();
  }
  play(days: number): DayStats[] {
    const out: DayStats[] = [];
    for (let d = 1; d <= days; d++) {
      this.day = d;
      if (d === 1) this.firstSession(); else this.morning(d);
      this.evening(d);
      const key = dayKey(this.c, local(d, 12));
      let spent = 0;
      for (const e of this.log.filter(l => dayKey(this.c, l.t) === key).flatMap(l => l.events)) {
        if (e.kind !== 'energy') continue;
        if (e.delta < 0) spent -= e.delta; else if (e.reason === 'refund') spent -= e.delta;
      }
      out.push({ day: d, spent, walls: this.walls, farming: this.s.skills.farming, fishing: this.s.skills.fishing, cooking: this.s.skills.cooking,
        levels: { farming: this.lv('farming'), fishing: this.lv('fishing'), cooking: this.lv('cooking') }, homestead: this.s.homestead.level,
        coins: this.s.coins, cookbook: Object.keys(this.s.book.cooked).length, fishdex: Object.keys(this.s.fishing.caught).length,
        three_slot: Object.keys(this.s.book.cooked).filter(id => (recipeById(this.c, id)?.in.length ?? 0) >= 3).length });
    }
    return out;
  }
}

export function playWeek(c: P0Content, player: string, days = 7) {
  const p = new WeekPlayer(c, player, local(1, 12));
  const stats = p.play(days);
  return { stats, reached: p.reached, walls: p.walls };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const opt = (name: string, dflt: number) => { const i = args.indexOf(name); return i >= 0 ? Number(args[i + 1]) : dflt; };
  const players = opt('--players', 6), days = opt('--days', 7);
  const c = loadP0Content();
  const runs = Array.from({ length: players }, (_, i) => playWeek(c, `week-target-${String(i).padStart(2, '0')}`, days));
  const mean = (f: (r: typeof runs[number]) => number) => Math.round(runs.reduce((n, r) => n + f(r), 0) / runs.length * 10) / 10;
  const daily = Array.from({ length: days }, (_, d) => mean(r => r.stats[d].spent));
  const last = (k: keyof DayStats) => mean(r => Number(r.stats[days - 1][k]));
  const first = (k: string) => mean(r => r.reached[k] ?? days + 1);
  const lines = [
    `| days | Energy per day | total | Farming | Fishing | Cooking | Homestead | coins | Cookbook | Fish-dex | walls |`,
    `|---|---|---|---|---|---|---|---|---|---|---|`,
    `| ${days} | ${daily.join(' / ')} | ${Math.round(daily.reduce((a, b) => a + b, 0))} | ${last('farming')} | ${last('fishing')} | ${last('cooking')} | ${last('homestead')} | ${last('coins')} | ${last('cookbook')} | ${last('fishdex')} | ${mean(r => r.walls)} |`,
    '',
    `Reached (mean day; ${days + 1} = not in ${days} days): Farming Lv2/3/4/5 ${['2', '3', '4', '5'].map(l => first(`farming_lv${l}`)).join(' / ')}; `
      + `Fishing Lv2/3/4/5 ${['2', '3', '4', '5'].map(l => first(`fishing_lv${l}`)).join(' / ')}; `
      + `Cooking Lv2/3/4/5/6 ${['2', '3', '4', '5', '6'].map(l => first(`cooking_lv${l}`)).join(' / ')}; Homestead Lv2 ${first('homestead_lv2')}`,
  ];
  console.log(lines.join('\n'));
  const jsonAt = args.indexOf('--json');
  if (jsonAt >= 0) writeFileSync(args[jsonAt + 1], JSON.stringify(runs, null, 2));
}
