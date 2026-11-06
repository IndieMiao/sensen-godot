/**
 * City gathering points (v4q(4), SGODOT-355; v4 §4.1): the table tools/gather_points_build.ts made
 * (server/data/gather_points.json), read once. A point is `<cluster>~<kind><n>` in San Francisco, an open home city or one
 * of their nearest 10; the city read sends a city's (contract-c §9). The gathering rules (Energy, cooldown, the bag,
 * where the player must be) are D's (gathering.ts); this module only says where the points are and what they give.
 */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { P0Content } from './content.js';
import { worldOf } from './world.js';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

interface KindRule { tier: string; word: string; yield: [string, number][] }
interface GatherRules { energy: number; cooldown_h: number; kinds: Record<string, KindRule> }
interface GatherTable { seed: string; revision: number; fields: string[]; rows: unknown[][] }

export interface GatherPoint {
  id: string; cluster: string; kind: string; tier: string; name: string; short: string;
  lat: number; lng: number; yield: [string, number][]; energy: number; cooldown_h: number;
}
export interface GatherCatalogue { byId: Map<string, GatherPoint>; byCluster: Map<string, GatherPoint[]> }

const loaded = new WeakMap<object, GatherCatalogue | null>();
const rulesOf = (c: P0Content) => (worldOf(c) as unknown as { gather_points?: GatherRules } | undefined)?.gather_points;

/** The points of a table: this world's (seed and revision) or an error — another world's are never used. */
export function gatherCatalogueOf(c: P0Content, table: GatherTable): GatherCatalogue {
  const w = worldOf(c), rules = rulesOf(c);
  if (!w || !rules) throw new Error('world_gen.json has no world / gather_points block');
  if (table.seed !== w.seed || table.revision !== w.revision) {
    throw new Error(`server/data/gather_points.json is for seed ${table.seed} revision ${table.revision}, the world is ${w.seed} revision ${w.revision}: rerun tools/gather_points_build.ts`);
  }
  const [cluster, kind, n, lat, lng, word] = ['cluster', 'kind', 'n', 'lat', 'lng', 'word'].map(f => table.fields.indexOf(f));
  const byId = new Map<string, GatherPoint>(), byCluster = new Map<string, GatherPoint[]>();
  for (const r of table.rows) {
    const k = r[kind] as string, rule = rules.kinds[k];
    if (!rule) continue;   // a kind the content no longer has
    const p: GatherPoint = { id: `${r[cluster]}~${k}${r[n]}`, cluster: r[cluster] as string, kind: k, tier: rule.tier,
      name: `${r[word]} ${rule.word}`, short: r[word] as string, lat: r[lat] as number, lng: r[lng] as number,
      yield: rule.yield.map(([item, qty]) => [item, qty] as [string, number]), energy: rules.energy, cooldown_h: rules.cooldown_h };
    byId.set(p.id, p);
    (byCluster.get(p.cluster) ?? byCluster.set(p.cluster, []).get(p.cluster)!).push(p);
  }
  return { byId, byCluster };
}

/** The points, read once per content; null without the file (no city has points). */
export function gatherCatalogue(c: P0Content): GatherCatalogue | null {
  if (!loaded.has(c)) {
    let table: GatherTable | null = null;
    try { table = JSON.parse(readFileSync(path.join(ROOT, 'server/data/gather_points.json'), 'utf8')) as GatherTable; }
    catch { table = null; }
    loaded.set(c, table && rulesOf(c) ? gatherCatalogueOf(c, table) : null);
  }
  return loaded.get(c)!;
}
/** Tests and tools: a catalogue given, not read. */
export const useGatherCatalogue = (c: P0Content, cat: GatherCatalogue | null) => { loaded.set(c, cat); };

export const gatherPointById = (c: P0Content, id: unknown): GatherPoint | undefined =>
  (typeof id === 'string' ? gatherCatalogue(c)?.byId.get(id) : undefined);
/** A city's points (none for a city without any), in table order. */
export const gatherPointsOf = (c: P0Content, cluster: string): GatherPoint[] => gatherCatalogue(c)?.byCluster.get(cluster) ?? [];
