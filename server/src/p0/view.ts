/** What the client receives: the settled state plus everything it would otherwise have to re-derive. */
import { cropBySeed, dishId, fishById, ingredient, itemKind, itemName, QUALITIES, rodById, SHOPS, SKILLS, type BoardId, type P0Content, type QuotaId, type ShopId } from './content.js';
import { count, freeSlots } from './bag.js';
import { burners, cookSlots, mealValue, recipeRarity, settleStove } from './cooking.js';
import { sellPrice, stallOffer } from './reducer.js';
import { blessed, dayKey, foodCap, maxEnergy, nextTickIn, regenMs, settleEnergy, skillLevel, untilRollover } from './rules.js';
import { emptyDay, type P0State } from './state.js';
import { catalog, drinkPrice, offerOf, owns, walletNeed } from './shops.js';
import { BOARDS, handIn, heldSlot, lockedTemplate, payout, settleBoards, slotCount } from './boards.js';
import { expireGiftMeals, lessonState, progressOf, requestOpensIn, requestState, residentState, stageIndex } from './residents.js';
import { floorPrice, haveFor, matches } from './requests.js';
import type { BoardRequest, Pot } from './state.js';
import { bigPot, boardSlots, chefSignGold, coinsNeeded, nextLevel, skillsTotal, stoveCount, unlocked, upgradeBlock } from './homestead.js';
import { cabinetCap, cabinetCount, rackOn, rackStock } from './kitchen_storage.js';
import { haveTotal, stored } from './storage.js';
import { mineView, settleMine } from './mine.js';
import { gatherView } from './gathering.js';
import { workbenchView } from './workbench.js';
import { coveredPlots, facilitiesView, facilityAt, plotCount } from './garden.js';
import { restReadyIn } from './presence.js';
import { inboxView, settleParcels } from './parcels.js';
import { cookbookView, masteredCount } from './cookbook.js';
import { mapMarkers } from './markers.js';
import { decorView } from './decor.js';

/** opts.online: players in the P0 outpost rooms right now (SGODOT-227), for the Tea Host's answer; null when not known. */
export function viewOf(c: P0Content, input: P0State, now: number, opts: { online?: number | null } = {}) {
  const s = structuredClone(input);
  settleEnergy(c, s, now);
  if (s.day.key !== dayKey(c, now)) s.day = emptyDay(dayKey(c, now));
  expireGiftMeals(s);
  settleBoards(c, s, now);   // same draw as the next command makes (both start from the stored rng)
  settleStove(c, s, now, []);   // Queue ×2: show the waiting pot already fired, as the next command will
  settleMine(c, s, now);
  settleParcels(c, s, now);
  const skills = Object.fromEntries(SKILLS.map(skill => {
    const level = skillLevel(c, s, skill), th = c.skills[skill];
    return [skill, { level, xp: s.skills[skill], floor: th[level - 1], next: level < th.length ? th[level] : null }];
  }));
  const fishingLevel = skillLevel(c, s, 'fishing');
  const f = c.fishing;
  const covered = coveredPlots(c, s);
  return {
    now, content_version: c.version, seq: s.seq,
    energy: { value: s.energy.value, max: maxEnergy(c, s), next_in: nextTickIn(c, s, now), regen_ms: regenMs(c, s, now) },
    blessing: blessed(c, s, now) ? { left: s.created_at + c.blessing.days * 86_400_000 - now, regen_mult: c.blessing.regen_mult, food_bonus: c.blessing.food_bonus } : null,
    coins: s.coins,
    inbox: inboxView(s, now),   // §10.4.8 parcels; the Inbox panel comes with stage 4, the bell reads `badge`
    // Map pin markers (§9.5.2, q(48)): one per place, deliver > request > new; the map draws the first five on screen
    map_markers: mapMarkers(c, s, now),
    // Cross-city (v5, SGODOT-278, note 0fc0bc5e §2): home / here / passes / visits / stamps / fallback / explorer
    travel: s.travel,
    decor: decorView(c, s),   // Decorate (SGODOT-284): {placed, cap, used, stored}; catalog and yard are in the content
    skills,
    plots: s.plots.map(p => ({
      id: p.id, state: p.state === 'growing' && (p.ready_at ?? Infinity) <= now ? 'ready' : p.state,
      crop: p.crop ?? null, ready_in: p.state === 'growing' && p.ready_at ? Math.max(0, p.ready_at - now) : null,
      xp_pct: p.xp_pct ?? null, fert: !!p.fert,
      covered: covered.has(p.id), facility: facilityAt(s, p.id)?.id ?? null,   // P1: watered by a sprinkler / one stands here
    })),
    facilities: facilitiesView(c, s),
    garden: { plots: plotCount(c, s) },
    bag: {
      capacity: s.bag_cap, free: freeSlots(s),
      // Every slot says locked / gifted (the item-info rules gate Lock and Gift on these fields, SGODOT-224).
      slots: s.bag.map(b => ({ id: b.id, qty: b.qty, locked: s.locked.includes(b.id), gifted: !!b.gift,
        ...(b.gift ? { from: b.gift.from, expires_in: untilRollover(c, now) } : {}) })),
    },
    drinks: drinksView(c, s, now),
    shops: Object.fromEntries(SHOPS.map(shop => [shop, shopView(c, s, shop)])),
    quotas: Object.fromEntries((Object.keys(c.quotas) as QuotaId[]).map(q => [q, quotaView(c, s, q, now)])),
    storage: { items: Object.entries(s.storage).map(([id, qty]) => ({ id, name: itemName(c, id), qty })),
      auto: s.storage_auto },   // last auto-store on coming home (q(40)): the client floats it once per new `at`
    mine: mineView(c, s, now),
    gather: gatherView(c, s, now),
    workbench: workbenchView(c, s),
    homestead: homesteadView(c, s),
    profile: { name: c.profile.name, city: c.profile.city, climate: c.profile.climate, since_ms: s.created_at,
      farm: { name: c.profile.farm_name, level: s.homestead.level } },
    boards: Object.fromEntries(BOARDS.map(b => [b, boardView(c, s, b, now)])),
    residents: Object.fromEntries(Object.keys(c.residents).map(id => [id, residentView(c, s, id, now)])),
    keepers: keepersView(c, s, now, opts.online ?? null),
    // away_ready_in: ms until Rest opens by the 2 h away rule (0 = open, null = not left yet), q(41).
    rest: { used: s.day.rest, limit: 1, resets_in: untilRollover(c, now), amount: c.energy.rest_amount,
      away_h: c.energy.rest_away_h, away_ready_in: restReadyIn(c, s, now) },
    stall: {
      keeper: c.stall.keeper,
      board: legacyBoard(c, s, now),   // the current Homestead Stall panel; SGODOT-224 reads boards.stall
      buy: c.stall.buy.map(id => {
        const offer = stallOffer(c, id);
        const level = skillLevel(c, s, offer.skill);
        return { id, name: itemName(c, id), price: offer.price, energy: cropBySeed(c, id)?.energy ?? 0, gate: offer.gate, skill: offer.skill,
          unlocked: level >= offer.gate, xp_to_go: Math.max(0, c.skills[offer.skill][offer.gate - 1] - s.skills[offer.skill]),
          left: offer.daily ? Math.max(0, offer.daily - (s.day.bought[id] ?? 0)) : null };
      }),
    },
    fishing: {
      sites: Object.fromEntries(Object.entries(f.sites).map(([id, site]) => [id, { name: site.name, template: site.template }])),
      // q(36): every catalog pond with its template; place = the pond the player is at (null away from ponds).
      places: Object.fromEntries(Object.entries(f.places).map(([id, p]) => [id, {
        name: p.name, site: p.site, template: f.sites[p.site]?.template ?? '', beginner: p.beginner === true }])),
      place: s.presence.place ?? null,
      rod: (rodById(c, s.gear.rod) ?? f.rods[0]).name, rod_reach: (rodById(c, s.gear.rod) ?? f.rods[0]).reach,
      hook_bonus_ms: (rodById(c, s.gear.rod) ?? f.rods[0]).hook_bonus_ms, band_bonus: (rodById(c, s.gear.rod) ?? f.rods[0]).band_bonus,
      cast_energy: f.cast_energy,
      cast: s.cast ? { rarity: fishById(c, s.cast.fish)!.rarity, site: s.cast.site, bite_in: Math.max(0, s.cast.at + s.cast.bite_ms - now),
        hook_ms: f.hook_window_ms + (rodById(c, s.gear.rod)?.hook_bonus_ms ?? 0), breaks: s.cast.breaks, bait: s.cast.bait } : null,
      protection_left: fishingLevel <= f.protect_max_level ? Math.max(0, f.protect_fails - s.day.fails) : null,
      caught: s.fishing.caught, seen: s.fishing.seen,
      dex: c.fish.map(fish => ({ id: fish.id, rarity: fish.rarity, level: fish.level, where: fish.where, caught: s.fishing.caught[fish.id] ?? 0,
        seen: s.fishing.seen.includes(fish.id), cook: fish.cook !== false })),
      baits: Object.keys(f.baits).map(id => ({ id, have: count(s.bag, id) })),
    },
    cooking: {
      slots: cookSlots(c, s),
      // Stove 1 (stove / queued) as before; stoves = every stove the Homestead level gives (Lv4 2, Lv8 3, SGODOT-282),
      // each its pot view (with that stove's queued pot) or null when empty. big_pot: Double is offered (Lv6).
      stove: potView(s, s.stove, now),
      queued: queuedView(s, s.stove, s.queue, now),
      stoves: burners(c, s).map(b => b.stove ? { ...potView(s, b.stove, now), queued: queuedView(s, b.stove, b.queue, now) } : null),
      big_pot: bigPot(c, s),
      first_fire: s.fires === 0,
      // Spice Rack (Homestead Lv2, q(46)): stored seasonings the stove reaches; Experiment shows them with a Rack badge.
      rack: { on: rackOn(c, s), items: [...rackStock(c, s)].map(([id, qty]) => ({ id, name: itemName(c, id), qty })) },
      // Warming Cabinet (Homestead Lv3, §7.7): null until unlocked; energy = what one portion restores today.
      cabinet: cabinetCap(c, s) > 0 ? { cap: cabinetCap(c, s), have: cabinetCount(s),
        items: s.cabinet.map(b => ({ id: b.id, name: itemName(c, b.id), qty: b.qty, energy: mealValue(c, s, b.id) })) } : null,
      // §7.5 / q(39): all 48 pages in order (14 cookable P0 pages + 34 silhouettes), with state, clue slots ("?" =
      // not shown), Lv4 lock, "You might have it" and Mastered; then Kitchen Mishaps, conveniences and trial refunds.
      ...(() => {
        const book = cookbookView(c, s, now);
        return { cookbook: book.pages, pages_total: book.total, discovered: book.discovered, mishaps: book.mishaps,
          conveniences: book.conveniences, third_slot: book.third_slot, trial_refunds: book.trial_refunds,
          // Cookbook milestones (§7.6.1): each title, what it counts (Discovered or Mastered), the need and whether reached.
          milestones: (c.cooking.milestones ?? []).map(m => ({ id: m.id, title: m.title, counts: m.mastered !== undefined ? 'mastered' : 'discovered',
            need: m.mastered ?? m.discovered ?? 0, reached: s.firsts.includes(`milestone:${m.id}`) })),
          mastered_count: masteredCount(c, s) };
      })(),
      derive: c.cooking.derive,
      tiers: Object.fromEntries(Object.entries(c.cooking.tiers).map(([k, t]) => [k, { energy: t.energy, ms: t.ms, bonus: t.bonus }])),
    },
    gear: {
      slots: { farming: s.gear.hoe, fishing: s.gear.rod, mining: s.gear.pick, combat: c.tools.combat },
      // Hoes (§9.11.2): sow = plots per Sow action (Starter Hoe 1, Row Hoe 3).
      hoes: [c.tools.farming, c.tools.row_hoe.id].map(id => ({ id, name: itemName(c, id), owned: s.gear.hoes.includes(id),
        equipped: s.gear.hoe === id, sow: id === c.tools.row_hoe.id ? c.tools.row_hoe.sow : 1,
        price: id === c.tools.row_hoe.id ? c.tools.row_hoe.price : 0, gate: id === c.tools.row_hoe.id ? c.tools.row_hoe.gate : 1 })),
      rods: c.fishing.rods.map(r => ({ ...r, owned: s.gear.rods.includes(r.id), equipped: s.gear.rod === r.id })),
      // Pickaxes (§13.1.3, LOCK-29): stone = Stone per rock; the Copper Pickaxe comes from the workbench, not a shop.
      picks: Object.entries(c.mine.picks).map(([id, p]) => ({ id, name: itemName(c, id), owned: s.gear.picks.includes(id),
        equipped: s.gear.pick === id, stone: p.stone, level: 0, price: 0, source: id === c.tools.mining ? 'start' : 'workbench' })),
    },
    tackle: {
      keeper: c.tackle.keeper,
      buy: c.tackle.buy.map(id => {
        const offer = stallOffer(c, id);
        const level = skillLevel(c, s, offer.skill);
        return { id, name: itemName(c, id), price: offer.price, gate: offer.gate, skill: offer.skill, unlocked: level >= offer.gate,
          xp_to_go: Math.max(0, c.skills[offer.skill][offer.gate - 1] - s.skills[offer.skill]),
          owned: itemKind(id) === 'rod' ? s.gear.rods.includes(id) : false,
          left: offer.daily ? Math.max(0, offer.daily - (s.day.bought[id] ?? 0)) : null,
          reach: rodById(c, id)?.reach ?? null };
      }),
    },
    meals: { used: s.day.meals, cap: foodCap(c, s, now), resets_in: untilRollover(c, now), eaten: s.day.eaten },
    items: Object.fromEntries(bagIds(c, s).map(id => [id, itemInfo(c, s, id)])),
    rarity_names: c.rarity_names,
    prices: Object.fromEntries(c.crops.map(crop => [crop.id, crop.price])),
    names: Object.fromEntries([...c.crops.flatMap(crop => [[crop.id, crop.name], [crop.seed, crop.seed_name]]),
      ...c.fish.map(fish => [fish.id, fish.name]), ...c.cooking.recipes.map(r => [r.id, r.name]),
      ...Object.entries(c.goods).map(([id, g]) => [id, g.name]), ...c.fishing.rods.map(r => [r.id, r.name]),
      ...Object.entries(c.tools.names), [c.cooking.mystery.id, c.cooking.mystery.name],
      ...Object.entries(c.materials).map(([id, m]) => [id, m.name]), ...Object.entries(c.drinks.items).map(([id, d]) => [id, d.name]),
      ...Object.entries(c.specialty).map(([id, sp]) => [id, sp.name]), ...c.bag_upgrades.map(u => [u.id, u.name]),
      ...Object.entries(c.supplies).map(([id, x]) => [id, x.name])]),
    crops: c.crops.map(crop => ({ id: crop.id, seed: crop.seed, energy: crop.energy, grow_h: crop.grow_h, level: crop.level })),
    firsts: s.firsts,
    req_done: s.req_done,   // requests handed in (newest last, ≤ 20): the first session's Deliver row ticks on Pond Catch (q(58))
  };
}

/** Every id the client may show this turn: bag contents plus all dishes and ingredients by name. */
function bagIds(c: P0Content, s: P0State): string[] {
  const ids = new Set(s.bag.map(b => b.id));
  for (const crop of c.crops) ids.add(crop.id);
  for (const fish of c.fish) ids.add(fish.id);
  return [...ids];
}

function itemInfo(c: P0Content, s: P0State, id: string) {
  const kind = itemKind(id);
  const ing = ingredient(c, id);
  const info: Record<string, unknown> = { name: itemName(c, id), kind, sell: sellPrice(c, id), cook: !!ing };
  if (ing) { info.family = ing.family; info.rarity = ing.rarity; }
  if (kind === 'fish') info.rarity = fishById(c, id)?.rarity ?? 1;
  if (kind === 'dish') {
    const [base, q] = id.split('@');
    const quality = Math.max(0, QUALITIES.indexOf((q ?? 'plain') as typeof QUALITIES[number]));
    const recipe = c.cooking.recipes.find(r => r.id === base);
    info.base = base; info.quality = quality;
    info.rarity = recipe ? recipeRarity(c, recipe) : 0;
    info.meal = mealValue(c, s, dishId(base, quality));
    info.full = recipe ? c.cooking.tiers[String(info.rarity)].energy + (c.cooking.tiers[String(info.rarity)].bonus[quality] ?? 0) : c.cooking.mystery.energy;
  }
  return info;
}

/** A pot as the cooking drawer shows it; send `id` back as `pot` on heat / collect. */
function potView(s: P0State, pot: Pot | null, now: number) {
  return pot ? {
    id: pot.id ?? null,
    dish: s.cookbook.includes(pot.dish) && !pot.mystery ? pot.dish : null, rarity: pot.rarity,
    ms: pot.ms, elapsed: Math.max(0, now - pot.started_at), ready_in: Math.max(0, pot.started_at + pot.ms - now),
    heats: pot.heats,
    left: pot.left ?? null,   // portions waiting on the stove after a collect with no room (§7.2.6)
    double: pot.double ?? false,
  } : null;
}

/** Queue ×2 (Cooking Lv5): the pot waiting behind a stove's; it fires when that one is kept (starts_in from now).
 * null when it waits on the player: plates left on the stove, or a done pot with no place to keep it. */
function queuedView(s: P0State, stove: Pot | null, queue: Pot | null, now: number) {
  return queue ? { id: queue.id ?? null, dish: s.cookbook.includes(queue.dish) && !queue.mystery ? queue.dish : null,
    rarity: queue.rarity, ms: queue.ms,
    starts_in: stove && !stove.left && stove.started_at + stove.ms > now ? stove.started_at + stove.ms - now : null } : null;
}

/** HOME-1 facts (§8.6.1): what the next level needs, what the player has (storage and bag apart) and what is unlocked. */
function homesteadView(c: P0Content, s: P0State) {
  const next = nextLevel(c, s);
  const upgrade = c.bag_upgrades[0];
  const bagTier = (id: string) => s.owned.includes(id) ? 'owned' : unlocked(c, s, id) ? 'for_sale' : 'locked';
  return {
    level: s.homestead.level, max: c.homestead.max_level, plaque: s.homestead.plaque,
    next: next && {
      level: next.level,
      coins: { need: coinsNeeded(c, next.coins), have: s.coins },
      skills: { need: next.skills, have: skillsTotal(c, s), farming: skillLevel(c, s, 'farming'), fishing: skillLevel(c, s, 'fishing') },
      materials: next.materials.map(([id, need]) => ({ id, name: itemName(c, id), need, have: haveTotal(s, id), storage: stored(s, id), bag: haveTotal(s, id) - stored(s, id) })),
      energy: c.energy.max_base + c.homestead.per_level.energy * (next.level - 1),
      meals: c.cooking.food_cap + c.homestead.per_level.meals * (next.level - 1),
      unlocks: next.unlocks,
      can_upgrade: upgradeBlock(c, s) === null,
      block: upgradeBlock(c, s),
    },
    unlocks: {
      spice_rack: unlocked(c, s, 'spice_rack'),
      warming_cabinet: unlocked(c, s, 'warming_cabinet'),
      bag_upgrade_1: bagTier(upgrade.id),
      board_slots: boardSlots(c, s),
      fence: unlocked(c, s, 'fence'),
      clay_bank: unlocked(c, s, 'clay_bank'),
      // P1 (SGODOT-282, §8.3.1): stoves 1 / 2 / 3, Big Pot, Notice Board, Chef's Sign (gold +5 points), Bag II / III.
      stoves: stoveCount(c, s), big_pot: bigPot(c, s), notice_board: unlocked(c, s, 'notice_board'),
      chefs_sign: chefSignGold(c, s) > 0, cabinet: cabinetCap(c, s),
      ...Object.fromEntries(c.bag_upgrades.slice(1).map(u => [u.id, bagTier(u.id)])),
    },
  };
}

/** Tea / coffee facts (§3.4.4): cups used of the shared 3, next price, what the next cup would actually add. */
function drinksView(c: P0Content, s: P0State, now: number) {
  const max = maxEnergy(c, s), price = drinkPrice(c, s);
  return {
    used: s.day.drinks, limit: c.drinks.daily, left: c.drinks.daily - s.day.drinks, resets_in: untilRollover(c, now),
    price, need: price === null ? null : coinsNeeded(c, price), energy: c.drinks.energy,
    gain: Math.max(0, Math.min(c.drinks.energy, max - s.energy.value)), full: s.energy.value >= max,
    items: Object.entries(c.drinks.items).map(([id, d]) => ({ id, name: d.name, shop: d.shop })),
  };
}

function quotaView(c: P0Content, s: P0State, q: QuotaId, now: number) {
  const used = q === 'request_bonus' ? s.day.bonus : q === 'sys_requests' ? s.day.sys_done : s.day.quota[q] ?? 0;
  return { used, cap: c.quotas[q].cap, resets_in: untilRollover(c, now), scope: c.quotas[q].scope };
}

/** One counter (§9.11): what it sells with every gate as a fact, and which kinds it buys back at what rate / quota. */
function shopView(c: P0Content, s: P0State, shop: ShopId) {
  return {
    buy: catalog(c, shop).map(id => {
      const o = offerOf(c, id)!;
      const unlocked = !o.skill || skillLevel(c, s, o.skill) >= o.gate;
      return {
        id, name: itemName(c, id), price: o.price, need: walletNeed(c, o), to: o.to,
        skill: o.skill, gate: o.gate, unlocked,
        xp_to_go: o.skill ? Math.max(0, c.skills[o.skill][o.gate - 1] - s.skills[o.skill]) : 0,
        homestead: o.homestead ?? null, homestead_ok: !o.homestead || s.homestead.level >= o.homestead,
        once: o.once, owned: o.once && owns(c, s, id),
        left: o.daily ? Math.max(0, o.daily - (s.day.bought[id] ?? 0)) : null,
        materials: (o.materials ?? []).map(([m, n]) => ({ id: m, name: itemName(c, m), need: n, have: haveTotal(s, m) })),
        in_bag: count(s.bag, id),
      };
    }),
    sell: Object.entries(c.shops[shop].buys).map(([kind, r]) => ({ kind, rate: r.rate, quota: r.quota })),
  };
}

/** Ids a request could take, cheapest floor first: the fixed items, or every crop / fish / dish that fits its kind and rarity. */
function candidates(c: P0Content, r: BoardRequest): string[] {
  if (r.items.length) return r.items;
  const ids = r.kind === 'fish' ? c.fish.map(f => f.id) : r.kind === 'dish' ? c.cooking.recipes.map(x => x.id) : c.crops.map(x => x.id);
  return ids.filter(id => matches(c, { kind: r.kind, rarity: r.rarity, style: r.style, family: r.family }, [], id)).sort((a, b) => floorPrice(c, a) - floorPrice(c, b));
}

/** One request as facts (§9.6.5): what it takes, what the bag holds for it, and what delivering now would pay. */
function requestView(c: P0Content, s: P0State, r: BoardRequest, now: number) {
  const parts = handIn(c, s, r);
  const each = r.items.length > 1 ? Math.min(...r.items.map(i => haveFor(c, s, { kind: r.kind }, [i])))
    : haveFor(c, s, { kind: r.kind, rarity: r.rarity, style: r.style, family: r.family }, r.items);
  const cheapest = candidates(c, r)[0];
  const estimate = parts ? payout(c, r, parts)
    : { base: r.items.length > 1 ? r.items.reduce((n, i) => n + floorPrice(c, i) * r.qty, 0) : (cheapest ? floorPrice(c, cheapest) : 0) * r.qty, bonus: r.bonus };
  return {
    id: r.id, template: r.template, title: c.requests.templates[r.template]?.title ?? r.template, kind: r.kind,
    items: r.items, rarity: r.rarity ?? null, icon: r.items[0] ?? cheapest ?? null,
    // P1: dishes of a style (`Soup`, or several), crops of a family (`O`); the client names them
    style: r.style === undefined ? null : Array.isArray(r.style) ? r.style : [r.style], family: r.family ?? null,
    qty: r.qty, have: Math.min(each, r.qty), ready: parts !== null,
    coins: estimate.base + estimate.bonus, base: estimate.base, bonus: estimate.bonus,
    status: r.status,
    expires_in: r.status === 'open' && r.id !== c.requests.tutorial.id ? Math.max(0, r.drawn_at + c.requests.expire_h * 3_600_000 - now) : null,
  };
}

/** A board: its slots as requests, empty slots with their refill time, or the lowest gate when nothing is open yet. */
function boardView(c: P0Content, s: P0State, board: BoardId, now: number) {
  const locked = lockedTemplate(c, s, board);
  return {
    title: c.requests.boards[board].title, deliver_at: board === 'stall' ? 'homestead' : 'market',
    slots: s.boards[board].slice(0, slotCount(c, s, board)).map(sl => sl.req ? requestView(c, s, sl.req, now)
      : locked ? { empty: true, locked: { template: locked.template, title: c.requests.templates[locked.template].title, gate: locked.gate } }
      // q(99): the new account's held slot 2 shows no countdown (clients count only slots with refill_in)
      : heldSlot(c, s, board, sl) ? { empty: true, held: true }
      : { empty: true, refill_in: Math.max(0, sl.refill_at - now) }),
  };
}

/** The pre-SGODOT-224 shape of the Stall Board (scenes/p0/p0_ui.gd _board, P0Logic Today lines). */
function legacyBoard(c: P0Content, s: P0State, now: number) {
  const slots = s.boards.stall.slice(0, slotCount(c, s, 'stall'));
  const empty = slots.filter(sl => !sl.req && !heldSlot(c, s, 'stall', sl)).map(sl => sl.refill_at);   // q(99)
  return {
    slots: slots.length,
    requests: slots.filter(sl => sl.req).map(sl => {
      const r = requestView(c, s, sl.req!, now);
      const any = r.rarity ? `any ${c.rarity_names[r.rarity - 1]} ${r.kind}` : `any ${r.kind}`;
      const where = r.items.length ? (r.kind === 'fish' ? 'any pond' : 'from your farm') : any;
      return { id: r.id, title: r.title, item: r.icon ?? '', qty: r.qty, coins: r.coins, where, status: r.status, have: r.have };
    }),
    refill_in: empty.length ? Math.max(0, Math.min(...empty) - now) : 0,
  };
}

/** A resident as facts (§9.4.4, LOCK-18): names, lines and request copy stay in the content table the client reads. */
function residentView(c: P0Content, s: P0State, id: string, now: number) {
  const r = structuredClone(residentState(s, id)), stages = c.affinity.stages;
  const i = stageIndex(c, r.affinity), st = requestState(c, s, id, now), lesson = lessonState(c, s, id, now);
  const meal = s.day.gift_meal === id ? 'given'
    : s.day.gift_meal ? 'none'
    : i < stages.findIndex(([n]) => n === c.affinity.gift_meal_stage) ? 'none'
    : 'ready';
  return {
    affinity: r.affinity, stage: stages[i][0], stage_from: stages[i][1],
    next_stage: stages[i + 1]?.[0] ?? null, next_at: stages[i + 1]?.[1] ?? null,
    chatted_today: r.chat_day === s.day.key, gift_today: r.gift_day === s.day.key,
    meal,   // ready = the next talk gives today's gift meal (into the Inbox when the bag is full)
    request: st.req && {
      id: st.req.id, kind: st.req.need.kind, rarity: st.req.need.rarity ?? null, qty: st.req.qty, coins: st.req.coins,
      item: st.req.need.id ?? null, style: st.req.need.style ?? null,   // P1: one named item, or dishes of one style
      have: Math.min(st.req.qty, progressOf(c, s, id, st.req)),
      ready: st.state === 'accepted' && progressOf(c, s, id, st.req) >= st.req.qty,
    },
    request_state: st.state,   // open | accepted | wait (next player day) | stage (need_stage) | none
    need_stage: st.need_stage ?? null,
    next_in: st.state === 'wait' ? requestOpensIn(c, s, id, now) : null,
    // §7.5.3 Recipe lesson: ready = `learn` teaches `recipe` now; wait = next_in ms; stage = from need_stage; none
    lesson: { state: lesson.state, recipe: lesson.recipe ?? null, next_in: lesson.next_in ?? null, need_stage: lesson.need_stage ?? null },
  };
}

/** Facts behind the four keepers' greeting cards (Li Bai b7d8b665 D); the client picks the line (SGODOT-224 keeper_lines). */
function keepersView(c: P0Content, s: P0State, now: number, online: number | null) {
  const left = c.drinks.daily - s.day.drinks, full = s.energy.value >= maxEnergy(c, s);
  const market = boardView(c, s, 'market', now).slots;
  const marketOpen = market.filter(x => 'id' in x) as { template: string }[];
  const refills = s.boards.market.filter(sl => !sl.req).map(sl => Math.max(0, sl.refill_at - now));
  const pip = requestState(c, s, 'res_pip', now).state;
  const fishing = skillLevel(c, s, 'fishing');
  const reed = c.fishing.rods.find(r => r.id === 'rod_reed');
  const nextFish = Object.fromEntries(Object.entries(c.fishing.sites).map(([site, def]) => {
    const above = def.fish.map(f => fishById(c, f)!).filter(f => f.level > fishing).sort((a, b) => a.level - b.level)[0];
    return [site, above ? { id: above.id, level: above.level } : null];
  }));
  const tea = { cups_left: left, full, greet: left <= 0 ? 'cups_out' : full ? 'full' : 'cups_left', online };
  return {
    tea,
    post: { cups_left: left, full, greet: left <= 0 ? 'cups_out' : pip === 'open' ? 'request' : 'cups_left',
      request_by: pip === 'open' ? 'res_pip' : null, board_open: marketOpen.length,
      refill_in: refills.length ? Math.min(...refills) : null },
    tackle: { greet: reed && fishing >= reed.level && !s.gear.rods.includes(reed.id) ? 'reed_rod' : 'worms',
      worms_left: Math.max(0, (c.goods.bait_worm?.daily ?? 0) - (s.day.bought.bait_worm ?? 0)), next_fish: nextFish },
    market: { greet: s.gear.hoes.includes(c.tools.row_hoe.id) ? 'board' : 'row_hoe',
      board_open: marketOpen.length, board_templates: marketOpen.map(x => x.template),
      refill_in: refills.length ? Math.min(...refills) : null },
  };
}
