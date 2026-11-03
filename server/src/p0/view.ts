/** What the client receives: the settled state plus everything it would otherwise have to re-derive. */
import { cropBySeed, fastCrop, dishId, fishById, ingredient, itemKind, itemName, QUALITIES, rodById, SHOPS, SKILLS, type BoardId, type P0Content, type QuotaId, type ResidentRequest, type ShopId, recipeById } from './content.js';
import { count, freeSlots } from './bag.js';
import { cardPage, cardPrice, marketCards, stallCards } from './cards.js';
import { batchRoom, burners, cookSlots, keptIndex, keptReason, mealValue, recipeRarity, servingPicks, settleStove } from './cooking.js';
import { sellPrice, stallOffer } from './reducer.js';
import { blessed, dayKey, foodCap, levelEnergy, maxEnergy, nextTickIn, regenMs, settleEnergy, skillLevel, untilRollover } from './rules.js';
import { emptyDay, SAVE_VERSION, type P0State } from './state.js';
import { buyback, catalog, drinkPrice, isSpecialty, offerOf, owns, quotaKey, quotaScope, regionalOf, sellDistance, walletNeed } from './shops.js';
import { boardsOf, farFish, farTries, handIn, hasMarket, haveForRequest, heldSlot, lockedTemplate, payout, settleBoards, slotCount, slotsOf } from './boards.js';
import { cityName, giverOf, settleLocals, shownLocals } from './locals.js';
import { expireGiftMeals, giftClues, giftPointsView, kindredGifts, lessonState, progressOf, requestOpensIn, requestState, residentState, stageIndex } from './residents.js';
import { bonusCap, floorPrice, haveFor, matches, pick } from './requests.js';
import type { BoardRequest, Pot } from './state.js';
import { bigPot, boardSlots, chefSignGold, coinsNeeded, GATE_SKILLS, lookOf, nextLevel, stepAt, stoveCount, unlocked, upgradeBlock } from './homestead.js';
import { cabinetCap, cabinetCount, rackOn, rackStock } from './kitchen_storage.js';
import { haveTotal, stored } from './storage.js';
import { mineView, settleMine } from './mine.js';
import { firstDigView, pipLine } from './first_dig.js';
import { gatherView } from './gathering.js';
import { workbenchView } from './workbench.js';
import { compostView, coveredPlots, cropGrowH, facilitiesView, facilityAt, fieldCap, fieldsUsed, greenhousePlots, plotCount } from './garden.js';
import { cityStamps, climateAt, climatesVisited, clusterById, clusterOf, homeClimate, travelShown } from './travel.js';
import { cityPlaces, clusterAdmin } from './world.js';
import { orchardView, treeOf } from './orchard.js';
import { inboxView, settleParcels } from './parcels.js';
import { cookbookView, hasConvenience, masteredCount } from './cookbook.js';
import { litEvents, mapMarkers } from './markers.js';
import { cityOutposts, cityRegion, homeSetOf, homeView, residentPlace } from './home_city.js';
import { everFish, forecast, pondAt, pondFishIds, timeWord } from './fishing_world.js';
import { trapsView } from './fish_trap.js';
import { sureBite } from './fishing.js';
import { homeOf } from './travel.js';
import { homeFacts } from './home.js';
import { decorView } from './decor.js';
import { titlesView } from './titles.js';
import { guideView } from './guide.js';
import { blackjackView } from './blackjack.js';
import { isWild, near3Sites, siteFor, wildById, wildNear3 } from './wild.js';

/** opts.online: players in the outpost rooms of the town the player is in (q(206), routes' townOnline), for the Tea Host's
 * answer; null when not known. */
export function viewOf(c: P0Content, input: P0State, now: number, opts: { online?: number | null; locals?: boolean } = {}) {
  const s = structuredClone(input);
  settleEnergy(c, s, now);
  if (s.day.key !== dayKey(c, s, now)) s.day = emptyDay(dayKey(c, s, now));
  expireGiftMeals(s);
  settleBoards(c, s, now);   // same draw as the next command makes (both start from the stored rng)
  settleLocals(c, s, now);   // q(272): the same local requests the next command finds
  settleStove(c, s, now, []);   // Queue ×2: show the waiting pot already fired, as the next command will
  settleMine(c, s, now);
  settleParcels(c, s, now);
  const skills = Object.fromEntries(SKILLS.map(skill => {
    const level = skillLevel(c, s, skill), th = c.skills[skill];
    return [skill, { level, xp: s.skills[skill], floor: th[level - 1], next: level < th.length ? th[level] : null }];
  }));
  const fishingLevel = skillLevel(c, s, 'fishing');
  const f = c.fishing;
  const covered = coveredPlots(c, s), greenhouse = greenhousePlots(c, s);
  return {
    now, content_version: c.version, seq: s.seq,
    // v7 (355 b1): the save version this server writes. A client built for v7 that meets an older server (the new build
    // out before the server) shows the maintenance card instead of playing on it (v4q(2) B review ③).
    save_version: SAVE_VERSION,
    energy: { value: s.energy.value, max: maxEnergy(c, s), next_in: nextTickIn(c, s, now), regen_ms: regenMs(c, s, now) },
    blessing: blessed(c, s, now) ? { left: s.created_at + c.blessing.days * 86_400_000 - now, regen_mult: c.blessing.regen_mult, food_bonus: c.blessing.food_bonus } : null,
    coins: s.coins,
    inbox: inboxView(s, now),   // §10.4.8 parcels; the Inbox panel comes with stage 4, the bell reads `badge`
    // Map pin markers (§9.5.2, q(48)): one per place, deliver > request > new; the map draws the first five on screen
    map_markers: mapMarkers(c, s, now, { locals: opts.locals ?? true }),
    // §9.3.3 event venues lit now (from 2 h before until the end; their ★ is in map_markers): empty in the prototype
    event_venues: litEvents(c, now).map(e => ({ id: e.id, place: e.place, name: e.name, starts: e.starts, ends: e.ends })),
    blackjack: blackjackView(c, s, now),   // SGODOT-351 the card room's table: the gate, the hand in play, a result not yet seen
    guide: guideView(c, s, now),   // SGODOT-341: the new-player guide's step (or the recover entry to show), {step: null, end} when off
    home: homeView(c, s, now),   // SGODOT-303: home city, pending pick, home set, the free change's window (home_city.ts)
    // v4q(3) (contract-c §5): the free 3 wild sites, and the one the player is at with all its fields (null elsewhere);
    // near3_sites the same 3 with their type, main and name, for Today's vein row (v4q(9))
    wild: { near3: wildNear3(c, s), near3_sites: near3Sites(c, s), here: wildHere(c, s, now) },
    // Cross-city (v5, SGODOT-278, note 0fc0bc5e §2): home / here / passes / visits / stamps / fallback / explorer
    travel: { ...s.travel, ...travelShown(c, s.travel), today: dayKey(c, s, now),   // today: the day key stamps count on (Passport: first visits today 1/2)
      // q(256) (contract 043c0bc8 D): the fare table as content has it, for the confirm card, the Fare Board and the
      // silhouette card to price locally; travel charges fareOf's
      fares: c.travel?.fares ?? null,
      // MAP-8 Nearby cities: the state or province of each near10 city (`Salinas · California`); none for a city without
      admins: Object.fromEntries(s.travel.fallback.near10.map(id => [id, clusterAdmin(id)]).filter(([, a]) => a)),
      // q(208) ①: the row's second part as shown (cityRegion: state in the US, else the country, none when it is the
      // city's own name); `admins` stays for clients from before
      regions: Object.fromEntries(s.travel.fallback.near10.map(id => [id, cityRegion(c, id)])) },
    decor: decorView(c, s),   // Decorate (SGODOT-284): {placed, cap, used, stored}; catalog and yard are in the content
    skills,
    plots: s.plots.map(p => ({
      id: p.id, state: p.state === 'growing' && (p.ready_at ?? Infinity) <= now ? 'ready' : p.state,
      crop: p.crop ?? null, ready_in: p.state === 'growing' && p.ready_at ? Math.max(0, p.ready_at - now) : null,
      xp_pct: p.xp_pct ?? null, fert: !!p.fert,
      covered: covered.has(p.id), facility: facilityAt(c, s, p.id)?.id ?? null,   // P1: watered by a sprinkler / one stands here
      greenhouse: greenhouse.has(p.id),                                         // P1: under a greenhouse's glass (q(118) ②)
      ...(treeOf(c, p) ? { tree: true, picks: p.picks ?? 0 } : {}),            // P1: a tree stands here (q(118))
    })),
    orchard: orchardView(c, s),
    facilities: facilitiesView(c, s),
    compost: compostView(c, s, now),   // the Compost Bin's quota (q(118) ③); null without a bin
    // plots: beds open on the grid; fields: annuals standing of the level's Plots (`Plots 41/41`, SGODOT-355 b1)
    garden: { plots: plotCount(c, s), fields: { used: fieldsUsed(c, s), cap: fieldCap(c, s) } },
    bag: {
      capacity: s.bag_cap, free: freeSlots(s),
      // Every slot says locked / gifted (the item-info rules gate Lock and Gift on these fields, SGODOT-224).
      slots: s.bag.map(b => ({ id: b.id, qty: b.qty, locked: s.locked.includes(b.id), gifted: !!b.gift,
        ...(b.gift ? { from: b.gift.from, expires_in: untilRollover(c, s, now) } : {}) })),
      creel_value: creelValue(c, s),   // q(259): away, the full creel's toast says what its fish fetch here and at home
    },
    drinks: drinksView(c, s, now),
    shops: Object.fromEntries(SHOPS.map(shop => [shop, shopView(c, s, shop, now)])),
    quotas: Object.fromEntries((Object.keys(c.quotas) as QuotaId[]).map(q => [q, quotaView(c, s, q, now)])),
    storage: { items: Object.entries(s.storage).map(([id, qty]) => ({ id, name: itemName(c, id), qty })),
      auto: s.storage_auto },   // last auto-store on coming home (q(40)): the client floats it once per new `at`
    mine: mineView(c, s, now),
    // 355 G (contract-efg §9.2): Pip's First Dig — null before Lv3, {giver, floor, have, done} after (done stays shown);
    // pip_line, Pip's one line toward the iron vein while it is due ({key, vein, name}, v4q(9) ②), else null
    first_dig: firstDigView(c, s), pip_line: pipLine(c, s),
    gather: gatherView(c, s, now),
    workbench: workbenchView(c, s),
    homestead: homesteadView(c, s),
    profile: { name: c.profile.name, city: homeFacts(c, s).name, climate: homeFacts(c, s).climate, since_ms: s.created_at,
      farm: { name: c.profile.farm_name, level: s.homestead.level } },
    titles: titlesView(c, s),   // q(180): {list: title ids in the fixed order, wearing: the one worn or null} (titles.ts)
    // q(270): `market` is the board of the city the player is in (the home city's where that city has no market square);
    // `elsewhere`, the requests tracked on other cities' boards, each with where it is handed in
    boards: { stall: boardView(c, s, 'stall', now), market: boardView(c, s, 'market', now, marketCity(c, s)), elsewhere: elsewhereView(c, s, now) },
    // q(272): the keepers' local requests — today's in the city the player is in and the tracked ones elsewhere; a client
    // without it shows none
    locals: localsView(c, s, now),
    gift_clues: giftClues(c, s),   // Fishing Lv7 Gift Clues (q(167)): bag dishes → the met residents who love / like them
    residents: Object.fromEntries(Object.keys(c.residents).map(id => [id, residentView(c, s, id, now)])),
    keepers: keepersView(c, s, now, opts.online ?? null),
    // q(269): once a player day, no 2 h away first — no away_h / away_ready_in (clients up to 0.2.17 read their absence
    // as open, never as null's "not left yet")
    rest: { used: s.day.rest, limit: 1, resets_in: untilRollover(c, s, now), amount: c.energy.rest_amount },
    stall: {
      keeper: c.stall.keeper,
      board: legacyBoard(c, s, now),   // the current Homestead Stall panel; SGODOT-224 reads boards.stall
      buy: [...c.stall.buy, ...(c.fast_crops ?? []).map(f => f.seed)].map(id => {
        const offer = stallOffer(c, id);
        const level = skillLevel(c, s, offer.skill);
        return { id, name: itemName(c, id), price: offer.price, energy: (cropBySeed(c, id) ?? fastCrop(c, id))?.energy ?? 0, gate: offer.gate, skill: offer.skill,
          unlocked: level >= offer.gate, xp_to_go: Math.max(0, c.skills[offer.skill][offer.gate - 1] - s.skills[offer.skill]),
          left: offer.daily ? Math.max(0, offer.daily - (s.day.bought[id] ?? 0)) : null };
      }),
    },
    fishing: {
      sites: Object.fromEntries(Object.entries(f.sites).map(([id, site]) => [id, { name: site.name, template: site.template }])),
      // q(36): every catalog pond with its template; place = the pond the player is at (null away from ponds).
      // SGODOT-283: and what that pond is like now — its time of day and today's weather in its city — and every fish
      // it can ever give there (habitat × the city's regional fish), for the pond card and its Details list.
      places: Object.fromEntries(Object.entries(f.places).map(([id, p]) => {
        const pond = pondAt(c, id, now);
        return [id, { name: p.name, site: p.site, template: f.sites[p.site]?.template ?? '', beginner: p.beginner === true,
          daypart: pond.part, weather: pond.weather, fish: [...pondFishIds(c, id)],
          // the card's and the Bite Board's words (283 e61cda10): Dawn / Day / Dusk / Night now, the next three days
          time: timeWord(c, pond.tz, now), forecast: forecast(c, pond.cluster, pond.tz, now) }];
      })),
      place: s.presence.place ?? null,
      rod: (rodById(c, s.gear.rod) ?? f.rods[0]).name, rod_reach: (rodById(c, s.gear.rod) ?? f.rods[0]).reach,
      hook_bonus_ms: (rodById(c, s.gear.rod) ?? f.rods[0]).hook_bonus_ms, band_bonus: (rodById(c, s.gear.rod) ?? f.rods[0]).band_bonus,
      loss_mult: (rodById(c, s.gear.rod) ?? f.rods[0]).loss_mult ?? 1,   // Carbon Rod 0.9: the minigame's out-of-band loss
      cast_energy: f.cast_energy,
      cast: s.cast ? { rarity: fishById(c, s.cast.fish)!.rarity, site: s.cast.site, bite_in: Math.max(0, s.cast.at + s.cast.bite_ms - now),
        hook_ms: f.hook_window_ms + (rodById(c, s.gear.rod)?.hook_bonus_ms ?? 0), breaks: s.cast.breaks, bait: s.cast.bait,
        sure: sureBite(s) && !s.cast.breaks } : null,   // q(219): one of the first two bites — the hook window stays open, the reel can't fail
      protection_left: fishingLevel <= f.protect_max_level ? Math.max(0, f.protect_fails - s.day.fails) : null,
      caught: s.fishing.caught, seen: s.fishing.seen,
      dex: c.fish.map(fish => ({ id: fish.id, rarity: fish.rarity, level: fish.level, where: fish.where, caught: s.fishing.caught[fish.id] ?? 0,
        seen: s.fishing.seen.includes(fish.id), cook: fish.cook !== false })),
      baits: Object.keys(f.baits).map(id => ({ id, have: count(s.bag, id) })),
      trap: trapsView(c, s, now),   // Fish Traps (SGODOT-283): {traps [{place, fish, keep, next_in}], slots, next_level, have, here}
    },
    cooking: {
      slots: cookSlots(c, s),
      // Stove 1 (stove / queued) as before; stoves = every stove the Homestead level gives (Lv4 2, Lv8 3, SGODOT-282),
      // each its pot view (with that stove's queued pot) or null when empty. big_pot: Double is offered (Lv6).
      stove: potView(s, s.stove, now),
      queued: queuedView(s, s.stove, s.queue, now),
      stoves: burners(c, s).map(b => b.stove ? { ...potView(s, b.stove, now), queued: queuedView(s, b.stove, b.queue, now) } : null),
      big_pot: bigPot(c, s),
      // Batch Cook (Cooking Lv8, q(200)): how many pots the stoves can take now (empty stoves, then queue slots);
      // null before Lv8. The card's stepper stops at this or at what the page's picks cover, whichever is less.
      batch: hasConvenience(c, s, 'batch_cook') ? { room: batchRoom(c, s) } : null,
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
        // q(200) / q(201): each known page that can cook carries the servings its ingredients make, one set after
        // another as the stove picks them (picks, at most what every stove and queue could take, doubled with the Big
        // Pot), and saved: why a picked item was rather kept (an accepted request, or another known page's id), so the
        // card shows a batch's ×N, its servings and the amber slot before Cook.
        const most = Math.max(1, (hasConvenience(c, s, 'batch_cook') ? batchRoom(c, s) : 1) * (bigPot(c, s) ? 2 : 1));
        const index = keptIndex(c, s);
        const pages = book.pages.map(p => {
          const r = p.can_cook ? recipeById(c, p.id) : undefined;
          if (!r) return p;
          const picks = servingPicks(c, s, r, most, index);
          const why = keptReason(c, s, r, index);
          const saved = Object.fromEntries([...new Set(picks.flat())].flatMap(id => (why(id) ? [[id, why(id)]] : [])));
          return { ...p, picks, saved };
        });
        return { cookbook: pages, pages_total: book.total, discovered: book.discovered, mishaps: book.mishaps,
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
      slots: { farming: s.gear.hoe, fishing: s.gear.rod, mining: s.gear.pick, combat: s.gear.weapon },
      weapons: s.gear.weapons, weapon: s.gear.weapon,
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
    meals: { used: s.day.meals, cap: foodCap(c, s, now), resets_in: untilRollover(c, s, now), eaten: s.day.eaten },
    items: Object.fromEntries(bagIds(c, s).map(id => [id, itemInfo(c, s, id)])),
    rarity_names: c.rarity_names,
    prices: Object.fromEntries([...c.crops, ...(c.fast_crops ?? [])].map(crop => [crop.id, crop.price])),
    names: Object.fromEntries([...[...c.crops, ...(c.quick_seeds ?? []), ...(c.fast_crops ?? [])].flatMap(crop => [[crop.id, crop.name], [crop.seed, crop.seed_name]]),
      ...c.fish.map(fish => [fish.id, fish.name]), ...c.cooking.recipes.map(r => [r.id, r.name]),
      ...Object.entries(c.goods).map(([id, g]) => [id, g.name]), ...c.fishing.rods.map(r => [r.id, r.name]),
      ...Object.entries(c.tools.names), [c.cooking.mystery.id, c.cooking.mystery.name],
      ...Object.entries(c.materials).map(([id, m]) => [id, m.name]), ...Object.entries(c.drinks.items).map(([id, d]) => [id, d.name]),
      ...Object.entries(c.specialty).map(([id, sp]) => [id, sp.name]), ...c.bag_upgrades.map(u => [u.id, u.name]),
      ...Object.entries(c.supplies).map(([id, x]) => [id, x.name]),
      // SGODOT-296: city postcards the account has or this Market sells (postcard_<cluster id>: `Tokyo Postcard`)
      ...[...new Set([...s.owned, ...Object.keys(s.storage), ...catalog(c, 'market', s)])].filter(id => isSpecialty(c, id))
        .map(id => [id, itemName(c, id)])]),
    // grow_h is this farm's: a regional crop away from its zone ripens in off_zone_grow_h (§5.2.3, `native` false).
    crops: c.crops.map(crop => ({ id: crop.id, seed: crop.seed, energy: crop.energy, grow_h: cropGrowH(c, s, crop), level: crop.level,
      ...(crop.regional ? { zone: crop.zone, native: crop.zone === homeClimate(c, s) } : {}),
      ...(crop.perennial ? { perennial: true, regrow_h: crop.perennial.regrow_h, pick_energy: crop.perennial.harvest_energy } : {}) })),
    // q(217) teaching seeds, by their plot crop: `teach` (never in a list of crops), a fixed grow_s, harvested as `harvest`
    quick_seeds: (c.quick_seeds ?? []).map(q => ({ id: q.id, seed: q.seed, energy: q.energy, grow_s: q.grow_s, harvest: q.harvest })),
    fast_crops: (c.fast_crops ?? []).map(f => ({ ...f })),   // q(245): separate from ordinary crops/ingredients
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

/** HOME-1 facts (§8.6.1; v4q(1), 哪吒's A view contract): what the next level needs — each skill, the travel gate from
 * Lv16, materials (storage and bag apart), coins — what it brings, and what is unlocked. */
function homesteadView(c: P0Content, s: P0State) {
  const next = nextLevel(c, s);
  const upgrade = c.bag_upgrades[0];
  const bagTier = (id: string) => s.owned.includes(id) ? 'owned' : unlocked(c, s, id) ? 'for_sale' : 'locked';
  const plotsAt = (level: number) => stepAt(c.homestead.plots, level, c.start.tilled_plots + c.start.wild_plots);
  return {
    level: s.homestead.level, max: c.homestead.max_level, plaque: s.homestead.plaque,
    plots: { now: plotsAt(s.homestead.level), max: plotsAt(c.homestead.max_level) },   // the level's Plots and the batch's most
    next: next && {
      level: next.level,
      coins: { need: coinsNeeded(c, next.coins), have: s.coins },
      // only the skills the level gates (no Cooking before Lv6), in the button's order
      skills: GATE_SKILLS.filter(k => next.skills[k] !== undefined).map(k => ({ skill: k, need: next.skills[k]!, have: skillLevel(c, s, k) })),
      travel: next.travel ? { stamps: { need: next.travel.stamps, have: cityStamps(s) },
        climates: { need: next.travel.climates, have: climatesVisited(c, s) } } : null,
      materials: next.materials.map(([id, need]) => ({ id, name: itemName(c, id), need, have: haveTotal(s, id), storage: stored(s, id), bag: haveTotal(s, id) - stored(s, id) })),
      energy: c.energy.max_base + levelEnergy(c, next.level),   // the pool after the upgrade
      meals: c.cooking.food_cap + levelEnergy(c, next.level),   // the day's meal cap after it (one formula, v4q(1) ⑦)
      energy_gain: next.energy,                                 // what the upgrade gives back (Lv2–15 50, Lv16 on 0)
      plots: plotsAt(next.level),
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
      // P1 (SGODOT-282, §8.3.1): stoves 1 / 2 / 3, Big Pot, Notice Board, Chef's Sign (gold +5 points), Bag II / III.
      stoves: stoveCount(c, s), big_pot: bigPot(c, s), notice_board: unlocked(c, s, 'notice_board'),
      chefs_sign: chefSignGold(c, s) > 0, cabinet: cabinetCap(c, s),
      ...Object.fromEntries(c.bag_upgrades.slice(1).map(u => [u.id, bagTier(u.id)])),
    },
    // LOOK-PICK / HOME-1 Looks (SGODOT-282, q(112)): every stage in level order; look is null until the stage is reached.
    looks: (c.homestead.looks ?? []).map(l => ({ id: l.id, level: l.level, name: l.name, a: l.a, b: l.b,
      look: s.homestead.level >= l.level ? lookOf(s, l.id) : null })),
  };
}

/** Tea / coffee facts (§3.4.4): cups used of the shared 3, next price, what the next cup would actually add. */
function drinksView(c: P0Content, s: P0State, now: number) {
  const max = maxEnergy(c, s), price = drinkPrice(c, s);
  return {
    used: s.day.drinks, limit: c.drinks.daily, left: c.drinks.daily - s.day.drinks, resets_in: untilRollover(c, s, now),
    price, need: price === null ? null : coinsNeeded(c, price), energy: c.drinks.energy,
    gain: Math.max(0, Math.min(c.drinks.energy, max - s.energy.value)), full: s.energy.value >= max,
    items: Object.entries(c.drinks.items).map(([id, d]) => ({ id, name: d.name, shop: d.shop })),
  };
}

/** q(259): what the creel's sellable fish fetch at this city's Tackle Shop and at home, unit by unit as a sale pays
 * (q(251): max(1, ⌊full × the city's share⌋)); Gifted fish, crops and dishes left out. Away only: null at home, in a
 * city without a Tackle Shop (an S-tier town has only its Trading Post, whose counter buys nothing; the hand-written
 * city has Mission's), with no fish to sell, or when the two sums are equal — the toast then keeps `Sell or cook first`
 * (周瑜 on #567). */
function creelValue(c: P0Content, s: P0State): { here: number; home: number } | null {
  const city = s.travel?.here ?? homeOf(c, s);
  if (sellDistance(c, s, 'tackle', city).home) return null;
  const places = cityPlaces(c, city);   // null: the hand-written city
  if (places && !places.detail.outposts.some(o => o.role === 'tackle')) return null;
  let here = 0, home = 0;
  for (const b of s.bag) {
    if (b.gift || itemKind(b.id) !== 'fish') continue;
    const away = buyback(c, 'tackle', b.id, undefined, { s, cluster: city });
    const full = buyback(c, 'tackle', b.id, undefined, { s, cluster: homeOf(c, s) });
    if (!('unit' in away) || !('unit' in full)) continue;
    here += away.unit * b.qty;
    home += full.unit * b.qty;
  }
  return here > 0 && here !== home ? { here, home } : null;
}

function quotaView(c: P0Content, s: P0State, q: QuotaId, now: number) {
  // a per-city quota shows the city the player is in (§11.7.3: one count per account × city cluster), and its scope
  // names it (NPC-3 482:120: `all San Francisco markets`)
  const city = s.travel?.here ?? homeOf(c, s);
  const used = q === 'request_bonus' ? s.day.bonus : q === 'sys_requests' ? s.day.sys_done
    : s.day.quota[quotaKey(c, q, city)] ?? 0;
  return { used, cap: q === 'request_bonus' ? bonusCap(c, s) : c.quotas[q].cap, resets_in: untilRollover(c, s, now), scope: quotaScope(c, q, city) };
}

/** One counter (§9.11): what it sells with every gate as a fact, and which kinds it buys back at what rate / quota. */
function shopView(c: P0Content, s: P0State, shop: ShopId, now: number) {
  // q(251): the counters of the city the player is in (the Homestead Stall always home): `distance` says how far from
  // home and the share it pays, and each sell rate already carries that share, so an older client shows what it pays
  const distance = sellDistance(c, s, shop, s.travel?.here ?? homeOf(c, s));
  return {
    distance,
    buy: catalog(c, shop, s).map(id => {
      const o = offerOf(c, id)!;
      const unlocked = !o.skill || skillLevel(c, s, o.skill) >= o.gate;
      return {
        id, name: itemName(c, id), price: o.price, need: walletNeed(c, o), to: o.to,
        skill: o.skill, gate: o.gate, unlocked,
        xp_to_go: o.skill ? Math.max(0, c.skills[o.skill][o.gate - 1] - s.skills[o.skill]) : 0,
        homestead: o.homestead ?? null, homestead_ok: !o.homestead || s.homestead.level >= o.homestead,
        once: o.once, owned: o.once && owns(c, s, id),
        ...(shop === 'market' && isSpecialty(c, id) ? { specialty: true } : {}),   // the City Specialty shelf's row (SGODOT-296)
        left: o.daily ? Math.max(0, o.daily - (s.day.bought[id] ?? 0)) : null, daily: o.daily || null,
        materials: (o.materials ?? []).map(([m, n]) => ({ id: m, name: itemName(c, m), need: n, have: haveTotal(s, m) })),
        in_bag: count(s.bag, id),
      };
    }),
    // regional: only this climate's regional items (`items` lists them), as the Market Square takes them (§9.13.1)
    sell: Object.entries(c.shops[shop].buys).map(([kind, r]) => ({ kind, rate: r.rate * distance.factor, quota: r.quota,
      ...(r.regional ? { regional: true, items: regionalItems(c, kind, climateAt(c, s)) } : {}) })),
    // Recipe cards on this counter today (§7.16.1): the Stall's daily two (home), a Market's city's climate cards (q(182)).
    cards: (shop === 'homestead' ? stallCards(c, s) : shop === 'market' ? marketCards(c, climateAt(c, s)) : []).map(id => {
      const page = cardPage(id), price = cardPrice(c, id) ?? 0, recipe = recipeById(c, page);
      return { id, page, name: recipe?.name ?? page, rarity: recipe ? recipeRarity(c, recipe) : 1, price, need: coinsNeeded(c, price),
        owned: s.cookbook.includes(page) };
    }),
  };
}

/** Ids a request could take, cheapest floor first: the fixed items, or every crop / fish / dish that fits its kind and rarity. */
function candidates(c: P0Content, s: P0State, r: Pick<BoardRequest, 'items' | 'kind' | 'where' | 'rarity' | 'style' | 'family'>): string[] {
  if (r.items.length || r.kind === 'visit') return r.items;
  if (r.where === 'not_home') return [...farFish(c, s)].sort((a, b) => floorPrice(c, a) - floorPrice(c, b));   // Far Pond: q(128) estimates at the cheapest
  const ids = r.kind === 'fish' ? c.fish.map(f => f.id) : r.kind === 'dish' ? c.cooking.recipes.map(x => x.id)
    : r.kind === 'material' ? Object.keys(c.materials) : c.crops.map(x => x.id);
  return ids.filter(id => matches(c, { kind: r.kind, rarity: r.rarity, style: r.style, family: r.family }, [], id)).sort((a, b) => floorPrice(c, a) - floorPrice(c, b));
}

/**
 * An explore request's check-in: {place, done} — the client names a home outpost itself (Stamp Run); one in another
 * city (q(128)) also carries {name, city, cluster, lat, lng}, since that city's places are rarely loaded on the client
 * when the card shows (亚瑟). Null for any other request.
 */
function visitView(c: P0Content, s: P0State, r: BoardRequest) {
  if (!r.visit) return null;
  const cluster = clusterOf(c, r.visit.place);
  if (!cluster || cluster === s.travel.home) return r.visit;
  const o = cityPlaces(c, cluster)?.detail.outposts.find(x => x.id === r.visit!.place);
  return { ...r.visit, name: o?.name ?? '', city: clusterById(c, cluster)?.name ?? '', cluster, lat: o?.lat ?? null, lng: o?.lng ?? null };
}

/** One request as facts (§9.6.5): what it takes, what the bag holds for it, and what delivering now would pay. */
function requestView(c: P0Content, s: P0State, r: BoardRequest, now: number) {
  const parts = handIn(c, s, r);
  const each = r.kind === 'visit' ? (r.visit?.done ? 1 : 0)
    : r.items.length > 1 ? Math.min(...r.items.map(i => haveFor(c, s, { kind: r.kind as 'crop' }, [i])))
    : haveForRequest(c, s, r);
  const cheapest = candidates(c, s, r)[0];
  const estimate = parts ? payout(c, r, parts)
    : { base: r.items.length > 1 ? r.items.reduce((n, i) => n + floorPrice(c, i) * r.qty, 0) : (cheapest ? floorPrice(c, cheapest) : 0) * r.qty, bonus: r.bonus };
  return {
    id: r.id, template: r.template, title: c.requests.templates[r.template]?.title ?? r.template, kind: r.kind,
    items: r.items, rarity: r.rarity ?? null, icon: r.items[0] ?? cheapest ?? null,
    // P1: dishes of a style (`Soup`, or several), crops of a family (`O`); the client names them
    style: r.style === undefined ? null : Array.isArray(r.style) ? r.style : [r.style], family: r.family ?? null,
    visit: visitView(c, s, r),   // explore: {place: outpost id, done}; in another city also its name, city and point
    where: r.where ?? null,     // Far Pond (q(128)): `not_home`, fish the home city's ponds don't have
    ...(r.where === 'not_home' ? { tries: farTries(c, s) } : {}),   // its example line, at the player's level now
    qty: r.qty, have: Math.min(each, r.qty), ready: parts !== null,
    coins: estimate.base + estimate.bonus, base: estimate.base, bonus: estimate.bonus,
    status: r.status,
    accepted_at: r.status === 'accepted' ? r.accepted_at ?? null : null,   // q(143); null on saves from before it
    expires_in: r.status === 'open' && r.id !== c.requests.tutorial.id ? Math.max(0, r.drawn_at + c.requests.expire_h * 3_600_000 - now) : null,
  };
}

/** q(272): each local request as a board's, with the keeper giving it (outpost, name plate, role) and its city; an
 * untracked one goes at the day's end (the next player day draws anew). */
function localsView(c: P0Content, s: P0State, now: number) {
  const here = s.travel?.here || homeOf(c, s);
  return shownLocals(c, s, now).map(({ city, req, place }) => ({ ...requestView(c, s, req, now),
    expires_in: req.status === 'open' ? untilRollover(c, s, now) : null,
    place, ...giverOf(c, city, place), cluster: city, city: cityName(c, city), here: city === here }));
}

/** q(270): the city whose Market Board the player sees — the one they are in, or home where that city has no market square. */
function marketCity(c: P0Content, s: P0State): string {
  const here = s.travel?.here || homeOf(c, s);
  return hasMarket(c, s, here) ? here : homeOf(c, s);
}

/** A city's market square a board request is handed in at, and the city's name as the location chip writes it (q(270) ⑥). */
function marketOf(c: P0Content, s: P0State, city: string): { place: string | null; name: string; city: string } {
  if (city === homeOf(c, s)) return { place: homeSetOf(c, s)?.market ?? null, name: '', city: homeFacts(c, s).name };
  const o = cityPlaces(c, city)?.detail.outposts.find(x => x.role === 'market') ?? null;
  return { place: o?.id ?? cityOutposts(c, city).find(x => x.role === 'market')?.id ?? null, name: o?.name ?? '',
    city: homeFacts(c, { travel: { home: city } }).name };
}

/** Requests tracked on other cities' Market Boards (q(270) ⑥): Today, the map's ✓ and the tracked list name where each goes. */
function elsewhereView(c: P0Content, s: P0State, now: number) {
  const shown = marketCity(c, s);
  return boardsOf(c, s).filter(b => b.board === 'market' && b.city !== shown).flatMap(b => {
    const at = marketOf(c, s, b.city);
    return b.slots.filter(sl => sl.req?.status === 'accepted').map(sl => ({ ...requestView(c, s, sl.req!, now),
      cluster: b.city, city: at.city, home: b.city === homeOf(c, s), deliver_place: at.place, deliver_name: at.name }));
  });
}

/** A board: its slots as requests, empty slots with their refill time, or the lowest gate when nothing is open yet. A
 * Market Board says which city it hangs in (q(270): its copy names that city, `any Tokyo market`). */
function boardView(c: P0Content, s: P0State, board: BoardId, now: number, city = homeOf(c, s)) {
  const locked = lockedTemplate(c, s, board, city);
  const at = board === 'market' ? marketOf(c, s, city) : null;
  return {
    title: c.requests.boards[board].title, deliver_at: board === 'stall' ? 'homestead' : 'market',
    ...(at ? { cluster: city, city: at.city, home: city === homeOf(c, s), deliver_place: at.place, deliver_name: at.name } : {}),
    slots: slotsOf(c, s, board, city).slice(0, slotCount(c, s, board)).map(sl => sl.req ? requestView(c, s, sl.req, now)
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

/** q(262): display-only listed coins minus the hand-in floor. A negative difference retains a floor above the price. */
function residentRequestBonus(c: P0Content, s: P0State, q: ResidentRequest): number {
  if (q.need.kind === 'sow' || q.need.kind === 'harvest') return q.coins;
  const items = q.need.id ? [q.need.id] : [];
  const parts = pick(c, s, q.need, items, q.qty);
  const cheapest = candidates(c, s, { ...q.need, kind: q.need.kind, items })[0];
  const floor = parts ? parts.reduce((sum, [id, n]) => sum + floorPrice(c, id) * n, 0)
    : (cheapest ? floorPrice(c, cheapest) : 0) * q.qty;
  return q.coins - floor;
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
    place: residentPlace(c, s, id),   // where this player finds them (home_city.residentPlace): the Today `Show on map`
    affinity: r.affinity, stage: stages[i][0], stage_from: stages[i][1],
    next_stage: stages[i + 1]?.[0] ?? null, next_at: stages[i + 1]?.[1] ?? null,
    chatted_today: r.chat_day === s.day.key, gift_today: r.gift_day === s.day.key,
    meal,   // ready = the next talk gives today's gift meal (into the Inbox when the bag is full)
    request: st.req && {
      id: st.req.id, kind: st.req.need.kind, rarity: st.req.need.rarity ?? null, qty: st.req.qty, coins: st.req.coins,
      bonus: residentRequestBonus(c, s, st.req),   // optional to clients predating q(262); never stored or used to settle
      item: st.req.need.id ?? null, style: st.req.need.style ?? null,   // P1: one named item, or dishes of one style
      have: Math.min(st.req.qty, progressOf(c, s, id, st.req)),
      ready: st.state === 'accepted' && progressOf(c, s, id, st.req) >= st.req.qty,
      accepted_at: st.state === 'accepted' ? r.req?.at ?? null : null,   // q(143): when it was tracked (the save's req.at)
    },
    request_state: st.state,   // open | accepted | wait (next player day) | stage (need_stage) | none
    need_stage: st.need_stage ?? null,
    next_in: st.state === 'wait' ? requestOpensIn(c, s, id, now) : null,
    // §7.5.3 Recipe lesson: ready = `learn` teaches `recipe` now; wait = next_in ms; stage = from need_stage; none
    lesson: { state: lesson.state, recipe: lesson.recipe ?? null, next_in: lesson.next_in ?? null, need_stage: lesson.need_stage ?? null },
    gift_points: giftPointsView(c, s, id),   // Fishing Lv7 Gift Clues: bag dish → what giving it adds (the drawer's ♥ +3)
    // q(171): their postcard in the Passport once Kindred gave it — `Postcard from Pip`, its text, when; null before
    kindred: r.kindred_at !== undefined ? { ...kindredGifts(c, id), at: r.kindred_at } : null,
  };
}

/** Facts behind the four keepers' greeting cards (Li Bai b7d8b665 D); the client picks the line (SGODOT-224 keeper_lines). */
function keepersView(c: P0Content, s: P0State, now: number, online: number | null) {
  const left = c.drinks.daily - s.day.drinks, full = s.energy.value >= maxEnergy(c, s);
  const city = marketCity(c, s);   // q(270): the board of the city the player is in
  const market = boardView(c, s, 'market', now, city).slots;
  const marketOpen = market.filter(x => 'id' in x) as { template: string }[];
  const refills = slotsOf(c, s, 'market', city).filter(sl => !sl.req).map(sl => Math.max(0, sl.refill_at - now));
  const pip = requestState(c, s, 'res_pip', now).state;
  const fishing = skillLevel(c, s, 'fishing');
  const reed = c.fishing.rods.find(r => r.id === 'rod_reed');
  const nextFish = Object.fromEntries(Object.entries(c.fishing.sites).map(([site, def]) => {
    const above = everFish(c, def, homeOf(c, s)).filter(f => f.level > fishing).sort((a, b) => a.level - b.level)[0];
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

/** The regional items of a kind a counter of this climate takes (crops by zone, fish by zones). */
function regionalItems(c: P0Content, kind: string, zone: string): string[] {
  const ids = kind === 'crop' ? c.crops.map(x => x.id) : kind === 'fish' ? c.fish.map(x => x.id) : [];
  return ids.filter(id => regionalOf(c, id, zone));
}

/** view.wild.here: the wild site the player is at, as the viewport read gives it (catalogue and the player's fields). */
function wildHere(c: P0Content, s: P0State, now: number) {
  const here = s.travel?.here, site = isWild(here) ? wildById(c, here) : undefined;
  return site ? siteFor(c, s, site, now) : null;
}
