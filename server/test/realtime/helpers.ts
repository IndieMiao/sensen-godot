import { randomUUID } from 'node:crypto';
import path from 'node:path';
import { WebSocket } from 'ws';
import { MemoryStore } from '../../src/http/memory_store.js';
import { buildApp, plotFor, loadBlueprint } from '../../src/http/app.js';
import { DEFAULT_CONTENT_DIR, loadContent, contentVersion } from '../../src/domain/content.js';
import { initialFarmState } from '../../src/domain/farm_factory.js';
import { startJourney } from '../../src/domain/journey.js';
import { ensureBag } from '../../src/domain/bag.js';
import { ensureCharacter } from '../../src/domain/character.js';
import type { Store } from '../../src/http/store.js';
import type { FarmRow } from '../../src/http/dto.js';

export const content = loadContent(DEFAULT_CONTENT_DIR);
export const cv = contentVersion(DEFAULT_CONTENT_DIR);
export const blueprintDir = path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints');
export const sets = plotFor(content);
export const memory = () => new MemoryStore({ content, contentVersion: cv, plot: sets, timezone: 'Asia/Shanghai', now: Date.now });
export const appFor = (store: Store) => buildApp({ guestWrites: true, store, content, contentVersion: cv, blueprintDir,
  regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'), pepper: 'isolated-online-test', now: Date.now });
export async function seed(store: Store, location: { region?: string; layout?: string } = {}) {
  const auth = await store.authAnonymous(randomUUID());
  const region = location.region ?? 'shanghai', layout = location.layout ?? 'sh_a';
  const constraints = plotFor(content);
  const state = startJourney(initialFarmState(content, constraints, region === 'shanghai' ? 'Asia/Shanghai' : 'America/Los_Angeles', Date.now()), content);
  ensureBag(state, content); ensureCharacter(state, content);
  const farm: FarmRow = { id: randomUUID(), owner_id: auth.player.id, version: 0,
    region_id: region, layout_patch_id: layout, blueprint_revision: 2,
    visit_access: 'anyone', location_visible: true, state };
  await store.createFarm({ ownerId: auth.player.id, idempotencyKey: 'create', payloadHash: 'create',
    regionId: farm.region_id, layoutPatchId: farm.layout_patch_id, blueprintRevision: 2, build: () => farm });
  return { player: auth.player.id, token: auth.token, farm };
}

export class Client {
  ws: WebSocket;
  messages: Record<string, any>[] = [];
  frames: Buffer[] = [];
  joined: Record<string, any> = {};
  bytes = 0;
  binaryCount = 0;
  constructor(url: string) {
    this.ws = new WebSocket(url);
    this.ws.on('error', () => {});
    this.ws.on('message', (data, binary) => {
      this.bytes += Buffer.isBuffer(data) ? data.length : Array.isArray(data) ? data.reduce((n, b) => n + b.length, 0) : data.byteLength;
      if (binary) { this.binaryCount++; this.frames.push(Buffer.from(data as Buffer)); if (this.frames.length > 20) this.frames.shift(); }
      else { this.messages.push(JSON.parse(data.toString())); if (this.messages.length > 1000) this.messages.shift(); }
    });
  }
  send(body: object) { this.ws.send(JSON.stringify(body)); }
  async connect(token: string) {
    await new Promise<void>((resolve, reject) => { this.ws.once('open', resolve); this.ws.once('error', reject); });
    this.send({ t: 'auth', token });
    await this.next('authenticated');
  }
  async join(kind: string, args = {}) {
    this.send({ t: 'join', kind, ...args });
    const joined = await this.next('joined');
    this.joined = joined;
    return joined;
  }
  async next(type: string, predicate = (_: Record<string, any>) => true, timeout = 5000): Promise<Record<string, any>> {
    const start = Date.now();
    while (Date.now() - start < timeout) {
      const index = this.messages.findIndex(m => m.t === type && predicate(m));
      if (index >= 0) return this.messages.splice(index, 1)[0];
      await new Promise(resolve => setTimeout(resolve, 5));
    }
    throw new Error('Timed out waiting for ' + type + ': ' + JSON.stringify(this.messages.map(m => m.t)));
  }
  close() { this.ws.terminate(); }
}
