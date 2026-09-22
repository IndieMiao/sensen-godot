/** Isolated UI action account copied from a read-only DTO, never production. */
import { randomUUID } from 'node:crypto';
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { buildApp, plotFor } from '../src/http/app.js';
import { MemoryStore } from '../src/http/memory_store.js';
import { installKeyHmac } from '../src/http/auth.js';
import { DEFAULT_CONTENT_DIR, loadContent, contentVersion } from '../src/domain/content.js';
import type { FarmRow } from '../src/http/dto.js';

const content = loadContent(DEFAULT_CONTENT_DIR), cv = contentVersion(DEFAULT_CONTENT_DIR), plot = plotFor(content);
const directory = path.resolve(DEFAULT_CONTENT_DIR, '../../../output/farm-mode-2026-09-22/private');
mkdirSync(directory, { recursive: true, mode: 0o700 });
const source = JSON.parse(readFileSync(path.join(directory, 'source-farm.json'), 'utf8'));
const pepper = 'isolated-game-ui-only';
const store = new MemoryStore({ content, contentVersion: cv, plot, timezone: 'America/Los_Angeles', now: Date.now });
const key = randomUUID().replaceAll('-', ''), auth = await store.authAnonymous(installKeyHmac(key, pepper));
const farm: FarmRow = { id: randomUUID(), owner_id: auth.player.id, region_id: source.region_id,
  layout_patch_id: source.layout_patch_id, blueprint_revision: source.blueprint_revision,
  location: source.location, farm_terrain: source.farm_terrain, state: structuredClone(source.state), version: 0,
  location_visible: true, visit_access: 'only_me', relocation_available: false, relocation_used: true };
await store.createFarm({ ownerId: auth.player.id, idempotencyKey: 'isolated-ui', payloadHash: 'isolated-ui',
  regionId: farm.region_id, layoutPatchId: farm.layout_patch_id, blueprintRevision: farm.blueprint_revision, build: () => farm });
writeFileSync(path.join(directory, 'qa-account.json'), JSON.stringify({ key, farm_id: farm.id, player_id: auth.player.id }), { mode: 0o600 });
writeFileSync(path.join(directory, 'qa-before.json'), JSON.stringify(farm, null, 2), { mode: 0o600 });
const app = await buildApp({ store, content, contentVersion: cv, plot, now: Date.now, pepper,
  blueprintDir: path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints'), regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json') });
await app.listen({ port: 3195, host: '127.0.0.1' });
console.log(JSON.stringify({ ready: true, port: 3195, isolated: true, crops: Object.keys(farm.state.cells).length }));
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
