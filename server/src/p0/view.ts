/** What the client receives: the settled state plus everything it would otherwise have to re-derive. */
import { cropBySeed, dishId, fishById, ingredient, itemKind, itemName, QUALITIES, rodById, SHOPS, SKILLS, type BoardId, type P0Content, type QuotaId, type ShopId } from './content.js';
import { count, freeSlots } from './bag.js';
import { cookSlots, ingredientsFor, mealValue, recipeRarity } from './cooking.js';
import { sellPrice, stallOffer } from './reducer.js';
import { blessed, dayKey, foodCap, maxEnergy, nextTickIn, regenMs, settleEnergy, skillLevel, untilRollover } from './rules.js';
import { emptyDay, type P0State } from './state.js';
import { catalog, drinkPrice, offerOf, owns, walletNeed } from './shops.js';
import { BOARDS, handIn, lockedTemplate, payout, settleBoards, slotCount } from './boards.js';
import { expireGiftMeals, progressOf, requestState, residentState, stageIndex } from './residents.js';
import { floorPrice, haveFor, matches } from './requests.js';
import type { BoardRequest } from './state.js';
import { boardSlots, coinsNeeded, nextLevel, skillsTotal, unlocked, upgradeBlock } from './homestead.js';
import { haveTotal, stored } from './storage.js';

/** opts.online: players in the P0 outpost rooms right now (SGODOT-227), for the Tea Host's answer; null when not known. */
export function viewOf(c: P0Content, input: P0State, now: number, opts: { online?: number | null } = {}) {
  const s = structuredClone(input);
  settleEnergy(c, s, now);
  if (s.day.key !== dayKey(c, now)) s.day = emptyDay(dayKey(c, now));
  expireGiftMeals(s);
  settleBoards(c, s, now);   // same draw as the next command makes (both start from the stored rng)
  const skills = Object.fromEntries(SKILLS.map(skill => {
    const level = skillLevel(c, s, skill), th = c.skills[skill];
    return [skill, { level, xp: s.skills[skill], floor: th[level - 1], next: level < th.length ? th[level] : null }];
  }));
  const fishingLevel = skillLevel(c, s, 'fishing');
  const f = c.fishing;
  return {
    now, content_version: c.version, seq: s.seq,
    energy: { value: s.energy.value, max: maxEnergy(c, s), next_in: nextTickIn(c, s, now), regen_ms: regenMs(c, s, now) },
    blessing: blessed(c, s, now) ? { left: s.created_at + c.blessing.days * 86_400_000 - now, regen_mult: c.blessing.regen_mult, food_bonus: c.blessing.food_bonus } : null,
    coins: s.coins,
    skills,
    plots: s.plots.map(p => ({
      id: p.id, state: p.state === 'growing' && (p.ready_at ?? Infinity) <= now ? 'ready' : p.state,
      crop: p.crop ?? null, ready_in: p.state === 'growing' && p.ready_at ? Math.max(0, p.ready_at - now) : null,
      xp_pct: p.xp_pct ?? null, fert: !!p.fert,
    })),
    bag: {
      capacity: s.bag_cap, free: freeSlots(s),
      // Every slot says locked / gifted (the item-info rules gate Lock and Gift on these fields, SGODOT-224).
      slots: s.bag.map(b => ({ id: b.id, qty: b.qty, locked: s.locked.includes(b.id), gifted: !!b.gift,
        ...(b.gift ? { from: b.gift.from, expires_in: untilRollover(c, now) } : {}) })),
    },
    drinks: drinksView(c, s, now),
    shops: Object.fromEntries(SHOPS.map(shop => [shop, shopView(c, s, shop)])),
    quotas: Object.fromEntries((Object.keys(c.quotas) as QuotaId[]).map(q => [q, quotaView(c, s, q, now)])),
    storage: { items: Object.entries(s.storage).map(([id, qty]) => ({ id, name: itemName(c, id), qty })) },
    homestead: homesteadView(c, s),
    boards: Object.fromEntries(BOARDS.map(b => [b, boardView(c, s, b, now)])),
    residents: Object.fromEntries(Object.keys(c.residents).map(id => [id, residentView(c, s, id, now)])),
    keepers: keepersView(c, s, now, opts.online ?? null),
    rest: { used: s.day.rest, limit: 1, resets_in: untilRollover(c, now), amount: c.energy.rest_amount },
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
      stove: s.stove ? {
        dish: s.cookbook.includes(s.stove.dish) && !s.stove.mystery ? s.stove.dish : null, rarity: s.stove.rarity,
        ms: s.stove.ms, elapsed: Math.max(0, now - s.stove.started_at), ready_in: Math.max(0, s.stove.started_at + s.stove.ms - now),
        heats: s.stove.heats,
      } : null,
      first_fire: s.fires === 0,
      cookbook: c.cooking.recipes.map(r => {
        const known = s.cookbook.includes(r.id);
        const rarity = recipeRarity(c, r);
        return { id: r.id, name: known ? r.name : null, rarity, in: known ? r.in : r.in.map(() => '?'),
          known, cooked: s.firsts.includes(`cook:${r.id}`), slots: r.in.length,
          can_cook: known && r.in.length <= cookSlots(c, s) && ingredientsFor(c, s, r) !== null,
          today: s.day.cooked[r.id] ?? 0 };
      }),
      derive: c.cooking.derive,
      tiers: Object.fromEntries(Object.entries(c.cooking.tiers).map(([k, t]) => [k, { energy: t.energy, ms: t.ms, bonus: t.bonus }])),
    },
    gear: {
      slots: { farming: s.gear.hoe, fishing: s.gear.rod, mining: c.tools.mining, combat: c.tools.combat },
      // Hoes (§9.11.2): sow = plots per Sow action (Starter Hoe 1, Row Hoe 3).
      hoes: [c.tools.farming, c.tools.row_hoe.id].map(id => ({ id, name: itemName(c, id), owned: s.gear.hoes.includes(id),
        equipped: s.gear.hoe === id, sow: id === c.tools.row_hoe.id ? c.tools.row_hoe.sow : 1,
        price: id === c.tools.row_hoe.id ? c.tools.row_hoe.price : 0, gate: id === c.tools.row_hoe.id ? c.tools.row_hoe.gate : 1 })),
      rods: c.fishing.rods.map(r => ({ ...r, owned: s.gear.rods.includes(r.id), equipped: s.gear.rod === r.id })),
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
      ...Object.entries(c.specialty).map(([id, sp]) => [id, sp.name]), ...c.bag_upgrades.map(u => [u.id, u.name])]),
    crops: c.crops.map(crop => ({ id: crop.id, seed: crop.seed, energy: crop.energy, grow_h: crop.grow_h, level: crop.level })),
    firsts: s.firsts,
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

/** HOME-1 facts (§8.6.1): what the next level needs, what the player has (storage and bag apart) and what is unlocked. */
function homesteadView(c: P0Content, s: P0State) {
  const next = nextLevel(c, s);
  const upgrade = c.bag_upgrades[0];
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
      bag_upgrade_1: s.owned.includes(upgrade.id) ? 'owned' : unlocked(c, s, upgrade.id) ? 'for_sale' : 'locked',
      board_slots: boardSlots(c, s),
      fence: unlocked(c, s, 'fence'),
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
  return ids.filter(id => matches(c, { kind: r.kind, rarity: r.rarity }, [], id)).sort((a, b) => floorPrice(c, a) - floorPrice(c, b));
}

/** One request as facts (§9.6.5): what it takes, what the bag holds for it, and what delivering now would pay. */
function requestView(c: P0Content, s: P0State, r: BoardRequest, now: number) {
  const parts = handIn(c, s, r);
  const each = r.items.length > 1 ? Math.min(...r.items.map(i => haveFor(c, s, { kind: r.kind }, [i]))) : haveFor(c, s, { kind: r.kind, rarity: r.rarity }, r.items);
  const cheapest = candidates(c, r)[0];
  const estimate = parts ? payout(c, r, parts)
    : { base: r.items.length > 1 ? r.items.reduce((n, i) => n + floorPrice(c, i) * r.qty, 0) : (cheapest ? floorPrice(c, cheapest) : 0) * r.qty, bonus: r.bonus };
  return {
    id: r.id, template: r.template, title: c.requests.templates[r.template]?.title ?? r.template, kind: r.kind,
    items: r.items, rarity: r.rarity ?? null, icon: r.items[0] ?? cheapest ?? null,
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
      : { empty: true, refill_in: Math.max(0, sl.refill_at - now) }),
  };
}

/** The pre-SGODOT-224 shape of the Stall Board (scenes/p0/p0_ui.gd _board, P0Logic Today lines). */
function legacyBoard(c: P0Content, s: P0State, now: number) {
  const slots = s.boards.stall.slice(0, slotCount(c, s, 'stall'));
  const empty = slots.filter(sl => !sl.req).map(sl => sl.refill_at);
  return {
    slots: slots.length,
    requests: slots.filter(sl => sl.req).map(sl => {
      const r = requestView(c, s, sl.req!, now);
      return { id: r.id, title: r.title, item: r.icon ?? '', qty: r.qty, coins: r.coins, where: r.items.length ? 'any pond' : 'any kind', status: r.status, have: r.have };
    }),
    refill_in: empty.length ? Math.max(0, Math.min(...empty) - now) : 0,
  };
}

/** A resident as facts (§9.4.4, LOCK-18): names, lines and request copy stay in the content table the client reads. */
function residentView(c: P0Content, s: P0State, id: string, now: number) {
  const r = structuredClone(residentState(s, id)), stages = c.affinity.stages;
  const i = stageIndex(c, r.affinity), st = requestState(c, s, id);
  const meal = s.day.gift_meal === id ? 'given'
    : s.day.gift_meal ? 'none'
    : i < stages.findIndex(([n]) => n === c.affinity.gift_meal_stage) ? 'none'
    : freeSlots(s) < 1 ? 'bag_full' : 'ready';
  return {
    affinity: r.affinity, stage: stages[i][0], stage_from: stages[i][1],
    next_stage: stages[i + 1]?.[0] ?? null, next_at: stages[i + 1]?.[1] ?? null,
    chatted_today: r.chat_day === s.day.key, gift_today: r.gift_day === s.day.key,
    meal,   // ready = the next talk gives today's gift meal; bag_full = it would, once a slot is free
    request: st.req && {
      id: st.req.id, kind: st.req.need.kind, rarity: st.req.need.rarity ?? null, qty: st.req.qty, coins: st.req.coins,
      have: Math.min(st.req.qty, progressOf(c, s, id, st.req)),
      ready: st.state === 'accepted' && progressOf(c, s, id, st.req) >= st.req.qty,
    },
    request_state: st.state,   // open | accepted | wait (next player day) | stage (need_stage) | none
    need_stage: st.need_stage ?? null,
    next_in: st.state === 'wait' ? untilRollover(c, now) : null,
  };
}

/** Facts behind the four keepers' greeting cards (Li Bai b7d8b665 D); the client picks the line (SGODOT-224 keeper_lines). */
function keepersView(c: P0Content, s: P0State, now: number, online: number | null) {
  const left = c.drinks.daily - s.day.drinks, full = s.energy.value >= maxEnergy(c, s);
  const market = boardView(c, s, 'market', now).slots;
  const marketOpen = market.filter(x => 'id' in x) as { template: string }[];
  const refills = s.boards.market.filter(sl => !sl.req).map(sl => Math.max(0, sl.refill_at - now));
  const pip = requestState(c, s, 'res_pip').state;
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
