import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import pg from 'pg';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { buildApp, loadBlueprint, plotFor } from '../../src/http/app.js';
import type { FarmRow } from '../../src/http/dto.js';
import type { Store } from '../../src/http/store.js';
import { newInstallKey } from '../../src/http/auth.js';
import { createInitialState, type DecorationPlacement } from '../../src/domain/state.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { SH, T0 } from '../domain/helpers.js';

const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('TEST_DATABASE_URL is required in CI');
const content = loadContent(DEFAULT_CONTENT_DIR);
const cv = contentVersion(DEFAULT_CONTENT_DIR);
const blueprintDir = path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints');
const plot = plotFor(content);
const props: DecorationPlacement[] = [{ prop_id: 'bench', cell: [24, 3] },
  { prop_id: 'planter', cell: [27, 3] }];
let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (!DSN) return;
  pool = new pg.Pool({ connectionString: DSN, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

for (const storage of ['memory', 'postgres'] as const) {
  describe.skipIf(storage === 'postgres' && !DSN)(`decorations: ${storage}`, () => {
    let app: FastifyInstance;
    let store: Store;
    let clock: number;
    let token: string;
    let key: string;
    let ownerId: string;
    let farmId: string;
    const headers = () => ({ authorization: `Bearer ${token}` });
    const build = () => buildApp({ store, content, contentVersion: cv, blueprintDir,
      regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'decorations-test', now: () => clock });
    const me = () => app.inject({ method: 'GET', url: '/v1/farms/me', headers: headers() });
    const save = (placements: unknown, id: string = randomUUID(), base = 0, auth: Record<string, string> = headers()) =>
      app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: auth,
        payload: { type: 'save_decorations', payload: { props: placements }, idempotency_key: id, base_version: base } });
    const login = async (installKey: string) => {
      const response = await app.inject({ method: 'POST', url: '/v1/auth/anonymous', payload: { install_key: installKey } });
      expect(response.statusCode).toBe(200);
      return response.json() as { token: string; player_id: string };
    };

    beforeEach(async () => {
      if (pool) await truncateAll(pool);
      clock = T0;
      store = storage === 'memory'
        ? new MemoryStore({ content, contentVersion: cv, timezone: SH, plot, now: () => clock })
        : new PgStore({ pool: pool!, content, contentVersion: cv, timezone: () => SH,
          plot, now: () => clock });
      app = await build();
      key = newInstallKey();
      const identity = await login(key);
      token = identity.token;
      ownerId = identity.player_id;
      farmId = randomUUID();
      const state = createInitialState({ player_day_id: '2026-09-04', field_condition: 'sunny', now: clock,
        wallet: 218 });
      state.clock.chapter_index = 5;
      state.chapters[5] = { status: 'active', activated_day: state.clock.player_day_id, step_flags: {}, grants_issued: true };
      state.growth_choice = { intent: 'tool', purchase: 'tool', locked_at: clock, transaction_id: 'paid' };
      state.tools.row_tool = true;
      delete state.decorations;
      const farm: FarmRow = { id: farmId, owner_id: ownerId, region_id: 'shanghai', layout_patch_id: 'sh_a',
        blueprint_revision: 2, version: 0, location_visible: false, visit_access: 'anyone', state };
      await store.createFarm({ ownerId, idempotencyKey: 'create', payloadHash: 'create', regionId: 'shanghai',
        layoutPatchId: 'sh_a', blueprintRevision: 2, build: () => farm });
    });
    afterEach(async () => { await app.close(); });

    it('persists an old farm layout, replays saves, and reloads after a new login and app instance', async () => {
      const original = (await me()).json().state;
      expect(original.decorations ?? []).toEqual([]);
      const saved = await save(props, 'save');
      expect(saved.statusCode, saved.body).toBe(200);
      expect(saved.json().version).toBe(1);
      expect(saved.json().state.decorations).toEqual(props);
      expect(saved.json().state.wallet).toBe(original.wallet);
      expect(saved.json().state.cells).toEqual(original.cells);
      const replay = await save(props, 'save');
      expect(replay.json().outcome).toBe('replayed');
      expect(replay.json().version).toBe(1);
      await app.close();
      if (storage === 'postgres') store = new PgStore({ pool: pool!, content, contentVersion: cv,
        timezone: () => SH, plot, now: () => clock });
      app = await build();
      token = (await login(key)).token;
      expect((await me()).json().state.decorations).toEqual(props);
      expect((await store.farmById(farmId))!.state.decorations).toEqual(props);
      const removed = await save([], 'remove', 1);
      expect(removed.statusCode).toBe(200);
      expect((await me()).json().state.decorations).toEqual([]);
    });

    it('keeps the last saved layout on validation errors, stale versions, or reused keys', async () => {
      expect((await save(props, 'save')).statusCode).toBe(200);
      const invalid = await save([...props, { ...props[0], prop_id: 'lantern' }], 'invalid', 1);
      expect(invalid.statusCode).toBe(422);
      expect(invalid.json().code).toBe('INVALID_DECORATION');   // 两件道具压在同一格
      expect((await save([], 'stale', 0)).statusCode).toBe(409);
      expect((await save([], 'save', 0)).json().code).toBe('IDEMPOTENCY_MISMATCH');
      const actual = (await me()).json();
      expect(actual.version).toBe(1);
      expect(actual.state.decorations).toEqual(props);
    });

    it('isolates owner writes and exposes only public placement fields at the next snapshot slot', async () => {
      const visitor = await login(newInstallKey());
      const visitorHeaders = { authorization: `Bearer ${visitor.token}` };
      const snapshot = () => app.inject({ method: 'GET', url: `/v1/farms/${farmId}/snapshot`, headers: visitorHeaders });
      const initial = await snapshot();
      expect(initial.statusCode, initial.body).toBe(200);
      expect(initial.json().props).toEqual([]);
      expect((await save(props, 'save')).statusCode).toBe(200);
      expect((await snapshot()).json().props).toEqual([]);
      clock += 15 * 60_000;
      const published = (await snapshot()).json();
      expect(published.props).toEqual(props);
      expect(Object.keys(published.props[0]).sort()).toEqual(['cell', 'prop_id']);
      for (const privateField of ['owner_id', 'wallet', 'inventory', 'growth_choice', 'decorations', 'location'])
        expect(published).not.toHaveProperty(privateField);
      expect((await save([], 'intruder', 1, visitorHeaders)).statusCode).toBe(404);
      expect((await store.farmById(farmId))!.state.decorations).toEqual(props);
      expect((await save([], 'anonymous', 1, {})).statusCode).toBe(401);
    });
  });
}
