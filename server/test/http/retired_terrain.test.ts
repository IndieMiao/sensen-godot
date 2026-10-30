/** A farm saved with map-generated terrain before SGODOT-304 takes no new commands (MemoryStore; PgStore in db/concurrency). */
import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { MemoryStore } from '../../src/http/memory_store.js';
import { plotFor } from '../../src/http/app.js';
import { installKeyHmac, newInstallKey } from '../../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { createInitialState } from '../../src/domain/state.js';
import { isTillable } from '../../src/domain/plot.js';
import { at, SH } from '../domain/helpers.js';

const content = loadContent(DEFAULT_CONTENT_DIR);
const plot = plotFor(content);
const NOW = at('2026-09-04T10:00:00+08:00');
const soil = Array.from({ length: plot.gx * plot.gy }, (_, n) => `${n % plot.gx},${Math.floor(n / plot.gx)}`)
  .filter(id => isTillable(plot, id)).slice(0, 2);

describe('MemoryStore: a map-generated farm', () => {
  it('replays its old commands and refuses new ones', async () => {
    const store = new MemoryStore({ content, timezone: SH, plot, now: () => NOW, contentVersion: contentVersion(DEFAULT_CONTENT_DIR) });
    const { player } = await store.authAnonymous(installKeyHmac(newInstallKey(), 'p'));
    await store.createFarm({ ownerId: player.id, idempotencyKey: 'seed', payloadHash: 'h', regionId: 'shanghai',
      layoutPatchId: 'sh_a', blueprintRevision: 2, build: () => ({ id: randomUUID(), owner_id: player.id, region_id: 'shanghai',
        layout_patch_id: 'sh_a', blueprint_revision: 2, version: 0, location_visible: true, visit_access: 'only_me' as const,
        state: createInitialState({ player_day_id: '2026-09-04', field_condition: 'sunny', now: NOW, wallet: 180 }) }) });
    const env = (key: string, base: number, cell: string) => ({ idempotency_key: key, base_version: base, type: 'till_cells' as const,
      payload: { cell_ids: [cell] } });
    expect((await store.applyCommand(player.id, env('before', 0, soil[0]), { type: 'till_cells', cell_ids: [soil[0]] })).kind).toBe('applied');
    const farm = (await store.farmByOwner(player.id)) as { farm_terrain?: unknown; version: number };
    farm.farm_terrain = { format: 1, layout_id: 'geo', plot: {}, source: {} };
    expect((await store.applyCommand(player.id, env('before', 0, soil[0]), { type: 'till_cells', cell_ids: [soil[0]] })).kind).toBe('replayed');
    expect((await store.applyCommand(player.id, env('after', 1, soil[1]), { type: 'till_cells', cell_ids: [soil[1]] })).kind).toBe('version_mismatch');
    expect(farm.version).toBe(1);
  });
});
