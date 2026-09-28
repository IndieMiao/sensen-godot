/** Isolated HTTP/WSS QA using a recorded real OSM response; never touches production. */
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { buildApp, plotFor } from '../src/http/app.js';
import { MemoryStore } from '../src/http/memory_store.js';
import { DEFAULT_CONTENT_DIR, loadContent, contentVersion } from '../src/domain/content.js';
import { GeographyError, type Geography } from '../src/geography/farm_terrain.js';

const content = loadContent(DEFAULT_CONTENT_DIR), cv = contentVersion(DEFAULT_CONTENT_DIR);
const plot = plotFor(content);
const store = new MemoryStore({ content, contentVersion: cv, plot, timezone: 'Asia/Shanghai', now: Date.now });
const evidence = path.resolve(DEFAULT_CONTENT_DIR, '../../../output/private-geographic-farm-2026-09-21/geo');
const geography = JSON.parse(readFileSync(path.join(evidence, 'shanghai-peoples-park-source.json'), 'utf8')) as Geography;
const app = await buildApp({ guestWrites: true, store, content, contentVersion: cv, plot, now: Date.now,
  pepper: 'isolated-private-farm-qa-only', regionsFile: path.join(DEFAULT_CONTENT_DIR, 'regions.json'),
  blueprintDir: path.resolve(DEFAULT_CONTENT_DIR, '../../blueprints'),
  geographyProvider: async location => {
    // Exact recorded WGS84 geometry is reprojected for each selection. Outside
    // its small recorded window, fail explicitly instead of inventing coverage.
    if (Math.abs(location.lat - 31.2341) > 0.0006 || Math.abs(location.lng - 121.4704) > 0.0006)
      throw new GeographyError('GEOGRAPHY_UNAVAILABLE');
    return structuredClone(geography);
  },
});
await app.listen({ port: 3191, host: '127.0.0.1' });
console.log('PRIVATE_FARM_QA_READY port=3191 source=recorded-real-osm persistence=isolated-memory');
for (const signal of ['SIGINT', 'SIGTERM'] as const) process.on(signal, () => { void app.close().then(() => process.exit(0)); });
