import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { DateTime } from 'luxon';
import pg from 'pg';
import path from 'node:path';
import { PgStore } from '../../src/db/pg_store.js';
import { migrate, truncateAll } from '../../src/db/migrate.js';
import { MemoryStore } from '../../src/http/memory_store.js';
import { buildApp, loadBlueprint, plotFor } from '../../src/http/app.js';
import { newInstallKey } from '../../src/http/auth.js';
import type { Store } from '../../src/http/store.js';
import type { Command } from '../../src/domain/commands.js';
import type { FarmState, WeekSummary } from '../../src/domain/state.js';
import { DEFAULT_CONTENT_DIR, contentVersion, loadContent } from '../../src/domain/content.js';
import { BEDS } from '../domain/helpers.js';
import { ledgerScript, type Path, type Step, type Style } from '../fixtures/build_ledger.js';
import { isTillable, type PlotLayout } from '../../src/domain/plot.js';

/** 一小片可开垦格，代替过去写死的固定田畦（SGODOT-128 自由格子种田）。 */
function soilCells(p: PlotLayout, count: number): string[] {
  const out: string[] = [];
  for (let j = 0; j < p.gy && out.length < count; j++)
    for (let i = 0; i < p.gx && out.length < count; i++)
      if (isTillable(p, `${i},${j}`)) out.push(`${i},${j}`);
  return out;
}


const DSN = process.env.TEST_DATABASE_URL;
if (process.env.CI === '1' && !DSN) throw new Error('TEST_DATABASE_URL is required in CI');
const content = loadContent(DEFAULT_CONTENT_DIR);
const cv = contentVersion(DEFAULT_CONTENT_DIR);
const blueprintDir = path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints');
let pool: pg.Pool | undefined;
beforeAll(async () => {
  if (!DSN) return;
  pool = new pg.Pool({ connectionString: DSN, max: 5 });
  await migrate(pool);
});
afterAll(async () => { await pool?.end(); });

for (const storage of ['memory', 'postgres'] as const) {
  for (const city of [
    { region: 'shanghai', layout: 'sh_a', zone: 'Asia/Shanghai', date: '2026-09-04' },
    { region: 'los_angeles', layout: 'la_a', zone: 'America/Los_Angeles', date: '2026-10-31' },
  ]) {
    describe.skipIf(storage === 'postgres' && !DSN)(`chapters: ${storage}, ${city.zone}`, () => {
      const start = DateTime.fromISO(`${city.date}T10:00:00`, { zone: city.zone });
      const dayAt = (day: number) => start.plus({ days: day }).toMillis();
      const sets = plotFor(content);
      const beds = soilCells(sets, 9);
      // 预留畦随渐进解锁一同退役，映射只保留这 9 格工作面。
      const cellMap = new Map(BEDS.map((id, i) => [id, beds[i]] as const));
      let app: FastifyInstance;
      let store: Store;
      let clock: number;
      let token: string;
      let installKey: string;
      let farmId: string;
      let version: number;
      let sequence: number;
      let firstSummary: WeekSummary | undefined;

      const headers = () => ({ authorization: `Bearer ${token}` });
      const me = () => app.inject({ method: 'GET', url: '/v1/farms/me', headers: headers() });
      const send = (command: Command, key = `c${++sequence}`, base = version) => {
        const { type, ...payload } = command;
        return app.inject({ method: 'POST', url: '/v1/farms/me/commands', headers: headers(),
          payload: { idempotency_key: key, base_version: base, type, payload } });
      };
      async function login() {
        const r = await app.inject({ method: 'POST', url: '/v1/auth/anonymous',
          payload: { install_key: installKey } });
        expect(r.statusCode).toBe(200);
        token = r.json().token;
      }
      async function run(steps: Step[]) {
        let lastDay = -1;
        let within = 0;
        for (const step of steps) {
          if (step.day !== lastDay) { lastDay = step.day; within = 0; }
          within += (step.waitMinutes ?? 5) / 5;
          clock = dayAt(step.day) + within * 5 * 60_000;
          const command = structuredClone(step.cmd);
          if ('cell_ids' in command) command.cell_ids = command.cell_ids.map(id => cellMap.get(id) ?? id);
          const response = await send(command);
          expect(response.statusCode, `D${step.day} ${command.type}: ${response.body}`).toBe(200);
          const body = response.json();
          version = body.version;
          expect(body.state.clock.chapter_index).toBe(body.derived.chapter_index);
          expect(body.state.clock.player_day_id).toBe(body.derived.player_day_id);
          if (body.state.week_summary && !firstSummary) {
            firstSummary = structuredClone(body.state.week_summary) as WeekSummary;
            expect(firstSummary.wallet).toBe(body.state.wallet);
            expect(firstSummary.xp).toBe(body.state.xp.total);
            expect(firstSummary.choices).toEqual(body.state.life_choices);
            for (const [id, relationship] of Object.entries(firstSummary.relationships))
              expect(relationship.points).toBe(body.state.residents[id].points);
          }
        }
        return (await me()).json();
      }

      beforeEach(async () => {
        if (pool) await truncateAll(pool);
        clock = start.toMillis();
        sequence = 0;
        firstSummary = undefined;
        store = storage === 'memory'
          ? new MemoryStore({ content, contentVersion: cv, timezone: city.zone, plot: sets, now: () => clock })
          : new PgStore({ pool: pool!, content, contentVersion: cv, timezone: () => city.zone,
            plot: sets, now: () => clock });
        app = await buildApp({ guestWrites: true, store, content, contentVersion: cv, blueprintDir, legacyGameplay: true,
          regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'chapter-test', now: () => clock });
        installKey = newInstallKey();
        await login();
        const created = await app.inject({ method: 'POST', url: '/v1/farms', headers: headers(),
          payload: { idempotency_key: 'create', region_id: city.region,
            layout_patch_id: city.layout, blueprint_revision: 2 } });
        expect(created.statusCode).toBe(201);
        farmId = created.json().farm_id;
        version = created.json().version;
      });
      afterEach(async () => { await app.close(); });

      for (const route of ['tool', 'field'] as Path[]) for (const style of ['life', 'sell'] as Style[]) {
      it(`completes seven chapters through HTTP: ${route}/${style}, with an immutable true summary`, async () => {
        const result = await run(ledgerScript(route, style));
        const state = result.state as FarmState;
        expect(state.chapters.map(chapter => chapter.status)).toEqual(Array(7).fill('done'));
        expect(state.handbook.filter(entry => entry.kind === 'chapter_done').map(entry => entry.key))
          .toEqual(['0', '1', '2', '3', '4', '5', '6']);
        // 精确的钱包/XP 目标值随七日账本一同退役（教学、渐进解锁、天气三选一照料被拆掉后，
        // 这些数字没有任何版本能幸存）。这里只守存储一致性关心的不变量。
        expect(state.wallet).toBeGreaterThanOrEqual(0);
        expect(state.xp.total).toBeGreaterThan(0);
        expect(state.residents.bistro_owner.choice_memories?.[2]).toBe(style === 'life' ? 'gift' : 'sold');
        expect(state.residents.nursery_keeper.points).toBe(style === 'life' ? 58 : 52);
        expect(state.residents.bistro_owner.points).toBe(style === 'life' ? 62 : 50);
        expect(state.residents.restorer.points).toBe(style === 'life' ? 31 : 19);
        expect(state.stall.settled).toBeLessThanOrEqual(content.economy.stall_budget_per_day);
        if (route === 'field' && style === 'sell') expect(state.inventory.produce.R).toBe(2);
        expect(state.nursery.stage).toBe('built');
        expect(state.week_summary).toEqual(firstSummary);
        expect(state.week_summary?.life_priority).toBe(style === 'life');
        expect(state.week_summary?.life_choice_count).toBe(style === 'life' ? 6 : 0);
        expect(state.week_summary?.photo_variant).toBe(style === 'life' ? 'personalized' : 'standard');
        expect(state.week_summary?.journal_pages).toHaveLength(style === 'life' ? 2 : 0);
        expect(state.week_summary?.growth_choice).toBe(route);
        expect(state.handbook.filter(entry => entry.kind === 'week_summary')).toHaveLength(1);
        expect(result.derived.next_chapter_opens_at).toBeNull();
        await login();
        expect((await me()).json().state).toEqual(state);
        expect((await store.farmById(farmId))?.state).toEqual(state);
        const base = version;
        const later: Command = { type: 'buy_seeds', crop: 'R', qty: 1 };
        const changed = await send(later, 'after-summary', base);
        expect(changed.statusCode).toBe(200);
        expect(changed.json().state.wallet).toBe(state.wallet - content.crops.crops.R.seed_price);
        expect(changed.json().state.week_summary).toEqual(firstSummary);
        const replay = await send(later, 'after-summary', base);
        expect(replay.json().outcome).toBe('replayed');
        expect(replay.json().state.week_summary).toEqual(firstSummary);
        expect((await me()).json().state.handbook.filter((entry: { kind: string }) => entry.kind === 'week_summary'))
          .toHaveLength(1);
      }, 30_000);
      }

      it('does not choose the ending before D6 harvest use is explicitly resolved', async () => {
        const script = ledgerScript('tool', 'life');
        const index = script.findIndex(step => step.day === 6 && step.cmd.type === 'resolve_life_choice');
        const waiting = await run(script.slice(0, index));
        expect(waiting.state.chapters[6].status).toBe('done');
        expect(waiting.state.life_choices[6]).toBeUndefined();
        expect(waiting.state.week_summary).toBeUndefined();
        const stored = structuredClone((await store.farmById(farmId))?.state);
        expect((await me()).json().state.week_summary).toBeUndefined();
        expect((await store.farmById(farmId))?.state).toEqual(stored);
        const choice = await send({ type: 'resolve_life_choice', chapter: 6, choice: 'gift' }, 'final-choice');
        expect(choice.statusCode).toBe(200);
        expect(choice.json().state.week_summary.life_priority).toBe(true);
        expect(choice.json().state.week_summary.choices[6]).toBe('gift');
        expect(choice.json().state.week_summary.journal_pages).toHaveLength(2);
        await login();
        expect((await me()).json().state.week_summary).toEqual(choice.json().state.week_summary);
      }, 30_000);

      it('projects the 04:00 opening without a write; retries, conflicts and reconnection issue one grant', async () => {
        const done = await run(ledgerScript('tool', 'life').filter(step => step.day === 0));
        const opens = start.plus({ days: 1 }).set({ hour: 4, minute: 0, second: 0, millisecond: 0 }).toMillis();
        expect(done.state.chapters[0].status).toBe('done');
        expect(done.derived.next_chapter_opens_at).toBe(opens);
        const stored = structuredClone(await store.farmById(farmId));
        clock = opens - 1;
        expect((await me()).json().state.clock.chapter_index).toBe(0);
        clock = opens;
        const projected = (await me()).json();
        expect(projected.version).toBe(version);
        expect(projected.state.clock.chapter_index).toBe(1);
        expect(projected.derived.chapter_index).toBe(1);
        expect(projected.state.chapters[1].grants_issued).toBe(true);
        expect(projected.state.inventory.seeds.L.bound).toBe(3);
        expect(projected.state.stall.settled).toBe(0);
        expect((await me()).json()).toEqual(projected);
        expect(await store.farmById(farmId)).toEqual(stored);
        const conflict = await send({ type: 'set_location_visible', visible: false }, 'conflict', version - 1);
        expect(conflict.statusCode).toBe(409);
        expect(conflict.json().state).toEqual(projected.state);
        expect(conflict.json().derived).toEqual(projected.derived);
        expect(await store.farmById(farmId)).toEqual(stored);
        const base = version;
        const command: Command = { type: 'set_location_visible', visible: false };
        const applied = await send(command, 'opening', base);
        expect(applied.statusCode).toBe(200);
        version = applied.json().version;
        const replay = await send(command, 'opening', base);
        expect(replay.json().outcome).toBe('replayed');
        expect(replay.json().state).toEqual(applied.json().state);
        await login();
        const refreshed = (await me()).json();
        expect(refreshed.version).toBe(base + 1);
        expect(refreshed.state).toEqual(applied.json().state);
        expect(refreshed.state.handbook.filter((entry: { kind: string }) => entry.kind === 'chapter_done'))
          .toHaveLength(1);
        expect((await store.farmById(farmId))?.state).toEqual(refreshed.state);
      });

      /*
       * 原「rejected care and duplicate commands cannot fabricate next-batch facts」已随
       * SGODOT-128 退役：它守的是第 0 章「恰好 9 格同时 sown+cared」这个教学批次条件，
       * 而第 0 章现在只要求 farm_created + first_harvest。命令重放与拒绝不写状态这两条
       * 更基础的保证，由同文件上方的幂等用例继续守着。
       */
    });
  }
}
