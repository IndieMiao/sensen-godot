/**
 * SGODOT-304: the Journey server is being retired (its geography farm with it). The P0 server must not lean on any of
 * its code: everything under src/p0 and tools/p0_server.ts imports only from src/p0 (and packages). The avatar
 * catalog and the action list live in src/p0/online (Journey's realtime rooms re-export them while they last).
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';

const SERVER = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const P0 = path.join(SERVER, 'src/p0');
const files = (dir: string): string[] => readdirSync(dir).flatMap(f => {
  const p = path.join(dir, f);
  return statSync(p).isDirectory() ? files(p) : p.endsWith('.ts') ? [p] : [];
});
/** Relative imports (static and import('…') types) that leave src/p0. */
const outside = (file: string) => [...readFileSync(file, 'utf8').matchAll(/(?:from|import\()\s*'(\.[^']+)'/g)]
  .map(m => path.resolve(path.dirname(file), m[1]))
  .filter(target => !target.startsWith(P0 + path.sep))
  .map(target => path.relative(SERVER, target));

describe('the P0 server stands on its own code (SGODOT-304)', () => {
  it('src/p0 imports nothing outside src/p0', () => {
    const leaks = files(P0).flatMap(f => outside(f).map(t => `${path.relative(SERVER, f)} → ${t}`));
    expect(leaks).toEqual([]);
  });
  it('tools/p0_server.ts imports only src/p0', () => {
    expect(outside(path.join(SERVER, 'tools/p0_server.ts'))).toEqual([]);
  });
});
