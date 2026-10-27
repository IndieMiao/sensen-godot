/**
 * Before rolling the P0 server back to a build without blackjack (SGODOT-351, plan §7 / q(238)): with the new server
 * STOPPED, give every hand still open its stakes back (blackjack.refundHand), so no coins stay on a table the old
 * server cannot see. Then start the old server. Never run it while a server is taking commands on this file.
 *   tsx tools/bj_rollback_settle.ts <state.json> [--dry-run]
 * Keeps <state.json>.bj-rollback-<time>.bak first; writes through P0Store (the same whole-file write the server
 * makes); prints one JSON line per hand refunded and a summary.
 */
import { copyFileSync, existsSync } from 'node:fs';
import { loadP0Content } from '../src/p0/content.js';
import { refundHand } from '../src/p0/blackjack.js';
import { P0Store } from '../src/p0/store.js';

const args = process.argv.slice(2);
const file = args.find(a => !a.startsWith('--'));
const dry = args.includes('--dry-run');
if (!file || !existsSync(file)) { console.error('usage: bj_rollback_settle.ts <state.json> [--dry-run]'); process.exit(2); }
const c = loadP0Content();
if (!dry) {
  const keep = `${file}.bj-rollback-${new Date().toISOString().replace(/[:.]/g, '-')}.bak`;
  copyFileSync(file, keep);
  console.log(JSON.stringify({ backup: keep }));
}
const store = new P0Store(c, dry ? undefined : file);
if (dry) for (const s of new P0Store(c, file).all()) store.put(s);   // a copy in memory only: nothing written
let hands = 0, coins = 0;
for (const s of store.all()) {
  const done = refundHand(s);
  if (!done) continue;
  hands++; coins += done.refunded;
  store.put(s);
  console.log(JSON.stringify({ kind: 'bj_rollback_refund', ...done, coins_after: s.coins }));
}
console.log(JSON.stringify({ kind: 'bj_rollback_done', dry, players: store.size(), hands, coins }));
