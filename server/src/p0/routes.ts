/** P0 HTTP surface: GET state, POST command, plus dev-only time skip and reset (local playtests only). */
import type { FastifyInstance } from 'fastify';
import type { P0Content } from './content.js';
import { applyP0, type P0Command } from './reducer.js';
import { dayKey, settleEnergy } from './rules.js';
import type { P0Store } from './store.js';
import { viewOf } from './view.js';
import type { P0State } from './state.js';
import { add } from './bag.js';
import { itemName } from './content.js';
import { putInStorage } from './storage.js';
import { notePresence } from './presence.js';
import { cityInfo, clusterById, clusterOf, writtenCluster, noteEntered, preview, requirePass, settleHere } from './travel.js';
import { noteVisit } from './boards.js';
import { parseBbox, viewport } from './wild.js';
import { changeOpen, dayHoldFor, homeCities, homeSpots, homeStatus, pinArea } from './home_city.js';
import type { IpNear } from './ip_city.js';
import type { OutpostRooms } from './online/rooms.js';
import { placeOf } from './world.js';
import { commandFields, uiEvent, type P0EventLog } from './telemetry.js';
import { guideKeys, settleGuide, setGuide } from './guide.js';

/** rooms: who is in the outpost rooms right now (SGODOT-227 OutpostRooms), for the Tea Host's count by town (q(206));
 * log: the observation log (S7). */
export interface P0RouteDeps { content: P0Content; store: P0Store; now: () => number; dev: boolean;
  rooms?: Pick<OutpostRooms, 'presence' | 'occupant'>; log?: P0EventLog;
  /** The address → nearest open home city for the home pick's `Near you` (ip_city.ts); none: no guess. */
  ipNear?: IpNear }

const UI_BATCH = 20, UI_PER_MINUTE = 120, UI_ALL_PER_MINUTE = 3_000;

const PLAYER_RE = /^[A-Za-z0-9_-]{8,64}$/;

export function registerP0Routes(app: FastifyInstance, deps: P0RouteDeps): void {
  const { content: c, store } = deps;
  const playerOf = (headers: Record<string, unknown>): string | null => {
    const id = String(headers['x-p0-player'] ?? '');
    return PLAYER_RE.test(id) ? id : null;
  };
  // A new save asks to pick a home only when the client says it can offer the pick (SGODOT-303, q(163) ⑤): an older
  // client's new player is San Francisco's, as every save before.
  // SGODOT-341 the same way: a new save starts the new-player guide only when the client says it can show it (`guide`).
  const features = (headers: Record<string, unknown>) => String(headers['x-p0-features'] ?? '').split(',').map(f => f.trim());
  // guide_v3: the client draws PR-C's guide (Pip, marks, Today). 0.2.11 sends `guide` without that layer, so its new saves
  // stay legacy (341 c6f3189a): `guide` alone no longer starts it.
  const newSave = (headers: Record<string, unknown>) => { const f = features(headers); return { pending: f.includes('choose_home'), guide: f.includes('guide_v3') }; };
  const stateOf = (player: string, headers: Record<string, unknown>) => store.get(player, deps.now(), newSave(headers));
  const clock = (offset: number) => deps.now() + offset;
  /** q(206): the people in the outpost rooms of the town the player is in (its pins' counts summed, a Mine Hut's too); the
   * player counts once they have walked into one of its outposts, though the room has not seen them yet (the state read
   * comes before the WebSocket join). Null when the rooms are not known. */
  const townOnline = (st: P0State): number | null => {
    if (!deps.rooms) return null;
    const here = st.travel.here;
    let n = 0;
    for (const [id, p] of Object.entries(deps.rooms.presence())) if (clusterOf(c, id) === here) n += p.online;
    const entered = st.presence.entered;
    // an outpost of this town, not a pond (presence.entered keeps either; 周瑜 on #448)
    if (!deps.rooms.occupant(st.player) && entered && !placeOf(c, entered) && clusterOf(c, entered) === here) n += 1;
    return n;
  };
  const view = (st: P0State, at: number) => viewOf(c, st, at, { online: townOnline(st) });

  app.get('/v1/p0/state', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = stateOf(player, req.headers);
    const { space, place } = (req.query ?? {}) as { space?: unknown; place?: unknown };
    if (typeof space === 'string' && space !== '') {   // the read a client makes on entering a space (q(41))
      // v5: entering a pond or outpost in a city without a pass is refused, with the confirm panel's preview.
      const refused = requirePass(c, s, space, place, clock(s.clock_ms));
      if (refused) return reply.send({ ok: false, code: refused.code, detail: refused.detail, state: view(s, clock(s.clock_ms)) });
      const before = { ...s, presence: { ...s.presence } };   // guideKeys reads only presence off it (no plots changed, no command)
      notePresence(c, s, space, clock(s.clock_ms), null, place);
      noteEntered(s, space, place);
      noteVisit(c, s, space, place, clock(s.clock_ms), []);   // the entry read checks in an explore request too (as noteSeenAt marks)
      if (space !== 'mine') settleHere(c, s, space, place, clock(s.clock_ms));
      settleGuide(c, s, guideKeys(c, before, s, null, []), clock(s.clock_ms));   // SGODOT-341: walking into a place is a guide step too
      store.put(s);
    } else {
      const moved = settleHere(c, s, space, place, clock(s.clock_ms));   // a Day Pass ran out on the map: home
      // SGODOT-341: a plain read settles the guide too — a step passed by time alone (Quick Radishes ripe), the fallback end
      const was = s.guide ? JSON.stringify(s.guide) : null;
      settleGuide(c, s, new Map(), clock(s.clock_ms));
      if (moved || (s.guide ? JSON.stringify(s.guide) : null) !== was) store.put(s);
    }
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });

  /** A city's places and silhouette card (note §4): home returns the hand-written tables; others come from the generator. */
  app.get('/v1/p0/city/:cluster', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const cluster = String((req.params as { cluster?: unknown }).cluster ?? '');
    if (!/^gn-\d{1,12}$/.test(cluster) || (!clusterById(c, cluster) && cluster !== writtenCluster(c))) return reply.code(404).send({ ok: false, code: 'unknown_city' });
    const s = stateOf(player, req.headers);
    // The generator's place details (SGODOT-280: ponds and outposts with their points and art) go out here, per city, and
    // never in the state view; the home city's hand-written places are in the client already.
    return reply.send({ ok: true, city: { ...cityInfo(c, cluster), preview: preview(c, s, cluster, clock(s.clock_ms)) } });
  });

  /** v4q(3) (contract-c §4): the open wild sites in the map's viewport, at most VIEWPORT_CAP, with what they are to the
   * player (free, visited, Trip, a pass); none below the continent zoom. The catalogue's revision rides along. */
  app.get('/v1/p0/wild', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const { bbox, zoom } = (req.query ?? {}) as { bbox?: unknown; zoom?: unknown };
    const box = parseBbox(bbox);
    if (!box) return reply.code(400).send({ ok: false, code: 'bad_bbox' });
    const s = stateOf(player, req.headers);
    const got = viewport(c, s, box, Number(zoom), clock(s.clock_ms));
    return reply.header('x-wild-revision', String(got.revision)).send({ ok: true, sites: got.sites, capped: got.capped, total: got.total });
  });

  /** The home pick page (SGODOT-303, q(160) ④): the open cities, and with ?q= the cities by name with why one is grey. */
  app.get('/v1/p0/home/cities', async (req, reply) => {
    if (!playerOf(req.headers)) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const { q } = (req.query ?? {}) as { q?: unknown };
    // q(188) ①: `Near you` — the open city nearest the address, guessed once for the page and kept nowhere
    const list = homeCities(c, typeof q === 'string' ? q.slice(0, 64) : ''), near = deps.ipNear?.(req.ip) ?? null;
    return reply.send({ ok: true, ...list, near: list.open.find(r => r.id === near) ?? null });   // only a city open today
  });

  /** The 3 farm spots this player is offered in a city (q(160) ②), the same every time for the same player. */
  app.get('/v1/p0/home/spots/:cluster', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const cluster = String((req.params as { cluster?: unknown }).cluster ?? '');
    const status = /^gn-\d{1,12}$/.test(cluster) ? homeStatus(c, cluster) : null;
    if (!status) return reply.code(404).send({ ok: false, code: 'unknown_city' });
    if (status !== 'open') return reply.send({ ok: false, code: 'home_not_open', detail: { city: cluster, status } });
    const spots = homeSpots(c, cluster, player);
    if (!spots) return reply.send({ ok: false, code: 'home_not_open', detail: { city: cluster, status: 'no_spot' } });
    // q(173) ④: the change confirm card says when today's limits reset if the home moves here (a first pick: none)
    const s = stateOf(player, req.headers), now = clock(s.clock_ms);
    const resets_at = !s.travel.pending && changeOpen(c, s, now).open ? dayHoldFor(c, s, cluster, now).until : null;
    // its weekday on the new home's calendar (`Your day resets Thu 4 AM, Tokyo time.`): the client has no time zones
    const resets_day = resets_at === null ? null
      : new Date(`${dayKey(c, { travel: { home: cluster } }, resets_at)}T00:00:00Z`).toLocaleDateString('en-US', { weekday: 'short', timeZone: 'UTC' });
    // q(216): the free pin's circle, its start and the places it keeps clear of (SGODOT-342; an older client reads only spots)
    return reply.send({ ok: true, city: cluster, spots, resets_at, resets_day, pin: pinArea(c, cluster, player) });
  });

  app.post('/v1/p0/commands', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = stateOf(player, req.headers);
    const now = clock(s.clock_ms);
    const result = applyP0(c, s, (req.body ?? {}) as P0Command, now);
    if (result.ok) store.put(result.state);   // saved before the log line: the log can never cost a command
    else if (result.code === 'new_day' && result.state) store.put(result.state);
    // Energy before = the stored value with natural recovery up to now, as the command saw it (a refusal: both the same).
    const before = { ...s, energy: { ...s.energy } };
    settleEnergy(c, before, now);
    deps.log?.write({ kind: 'command', t: deps.now(), clock: now, player, ip: req.ip, seq: s.seq, cmd: commandFields(req.body), ok: result.ok,
      ...(result.ok ? {} : { code: result.code, detail: result.detail ?? {} }),
      energy: [before.energy.value, result.ok ? result.state.energy.value : before.energy.value], events: result.ok ? result.events : [] });
    if (!result.ok) return reply.send({ ok: false, code: result.code, detail: result.detail ?? {}, state: view(result.state ?? s, now) });
    return reply.send({ ok: true, events: result.events, state: view(result.state, now) });
  });

  /** UI moments for the observation log (S7): known kinds only, a few a minute per player; nothing in the game changes. */
  // Counts are per minute: the map starts over each minute, and a total cap stops new player ids getting around it.
  const uiSeen = new Map<string, number>();
  let uiMinute = -1, uiTotal = 0;
  app.post('/v1/p0/telemetry', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const list = (req.body as { events?: unknown } | undefined)?.events;
    if (!Array.isArray(list) || list.length > UI_BATCH) return reply.code(400).send({ ok: false, code: 'bad_events' });
    const t = deps.now(), minute = Math.floor(t / 60_000);
    if (minute !== uiMinute) { uiSeen.clear(); uiMinute = minute; uiTotal = 0; }
    let accepted = 0;
    for (const raw of list) {
      const event = uiEvent(raw);
      const n = uiSeen.get(player) ?? 0;
      if (!event || n >= UI_PER_MINUTE || uiTotal >= UI_ALL_PER_MINUTE) continue;
      uiSeen.set(player, n + 1); uiTotal += 1; accepted += 1;
      deps.log?.write({ kind: 'ui', t, player, ip: req.ip, event });
    }
    return reply.send({ ok: true, accepted });
  });

  if (!deps.dev) return;
  app.post('/v1/p0/dev/skip', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const minutes = Number((req.body as { minutes?: number } | undefined)?.minutes ?? 0);
    if (!Number.isFinite(minutes) || minutes <= 0 || minutes > 7 * 24 * 60) return reply.code(400).send({ ok: false, code: 'bad_minutes' });
    const s = stateOf(player, req.headers);
    s.clock_ms += minutes * 60_000;
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  /** Playtests only: set the stored energy (eating, Energy Card and zero-energy states need a low bar). */
  app.post('/v1/p0/dev/energy', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const value = Number((req.body as { value?: number } | undefined)?.value);
    if (!Number.isInteger(value) || value < 0 || value > 1000) return reply.code(400).send({ ok: false, code: 'bad_value' });
    const s = stateOf(player, req.headers);
    const now = clock(s.clock_ms);
    s.energy = { value, tick_ms: now };
    store.put(s);
    return reply.send({ ok: true, state: view(s, now) });
  });
  /** Playtests only: fill every free bag slot with one item (the creel-full state, FISH-4). */
  app.post('/v1/p0/dev/fill', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const id = String((req.body as { id?: string } | undefined)?.id ?? 'fish_crucian');
    if (!c.fish.some(f => f.id === id)) return reply.code(400).send({ ok: false, code: 'bad_item' });
    const s = stateOf(player, req.headers);
    add(c, s, id, 1_000_000);
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  /** Playtests only: put items in the bag or the farm storage (materials have no P0 source until the mine / gathering land). */
  app.post('/v1/p0/dev/grant', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const body = (req.body ?? {}) as { id?: string; qty?: number; to?: string };
    const id = String(body.id ?? ''), qty = Number(body.qty ?? 1), to = body.to === 'storage' ? 'storage' : 'bag';
    if (!/^[a-z0-9_@]{2,48}$/.test(id) || itemName(c, id) === id) return reply.code(400).send({ ok: false, code: 'bad_item' });
    if (!Number.isInteger(qty) || qty < 1 || qty > 999) return reply.code(400).send({ ok: false, code: 'bad_qty' });
    const s = stateOf(player, req.headers);
    if (to === 'storage') putInStorage(s, id, qty);
    else add(c, s, id, qty);
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  app.post('/v1/p0/dev/reset', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = store.reset(player, deps.now(), newSave(req.headers));
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  /** Playtests only (SGODOT-351): the card room's table for a save — its Homestead level (the gate, Lv2) and coins. */
  app.post('/v1/p0/dev/blackjack', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const body = (req.body ?? {}) as { homestead?: number; coins?: number };
    const level = body.homestead, coins = body.coins;
    if (level !== undefined && (!Number.isInteger(level) || level < 1 || level > c.homestead.levels.length)) return reply.code(400).send({ ok: false, code: 'bad_level' });
    if (coins !== undefined && (!Number.isInteger(coins) || coins < 0 || coins > 1_000_000)) return reply.code(400).send({ ok: false, code: 'bad_qty' });
    const s = stateOf(player, req.headers);
    if (level !== undefined) s.homestead.level = level;
    if (coins !== undefined) s.coins = coins;
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
  /** Playtests only (SGODOT-341): put this save's guide on a step — `first`, `end` or a step id — counts cleared. */
  app.post('/v1/p0/dev/guide', async (req, reply) => {
    const player = playerOf(req.headers);
    if (!player) return reply.code(400).send({ ok: false, code: 'bad_player' });
    const s = stateOf(player, req.headers);
    const refusal = setGuide(c, s, String((req.body as { step?: string } | undefined)?.step ?? ''), clock(s.clock_ms));
    if (refusal) return reply.code(400).send({ ok: false, code: refusal.code });
    store.put(s);
    return reply.send({ ok: true, state: view(s, clock(s.clock_ms)) });
  });
}
