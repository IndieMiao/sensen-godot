/** In-memory P0 state store with an optional JSON file for local / emulator playtests. */
import { copyFileSync, existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { P0Content } from './content.js';
import { freshState, SAVE_VERSION, upgradeState, type P0State } from './state.js';
import { settleParcels } from './parcels.js';

export class P0Store {
  private players = new Map<string, P0State>();
  /** Saves older than this version when the file was loaded: since v7 they are cleared, not brought up (the server logs it). */
  readonly migrated: number = 0;
  constructor(private c: P0Content, private file?: string) {
    if (file && existsSync(file)) {
      const saved = JSON.parse(readFileSync(file, 'utf8')) as Record<string, P0State>;
      const older = Object.values(saved).filter(s => (s.v as number) < SAVE_VERSION).length;
      // The next write replaces the whole file in the new shape: keep the file as it was, once per version step.
      const keep = `${file}.v${Math.min(...Object.values(saved).map(s => s.v as number))}.bak`;
      if (older && !existsSync(keep)) copyFileSync(file, keep);
      this.migrated = older;
      // v7 (SGODOT-355 first batch) clears the save (plan v4 conclusion 20, q row B): a save older than v7 is not brought
      // up — its player starts a new one on the next read. The file as it was stays in the .bak above.
      for (const [id, state] of Object.entries(saved)) if ((state.v as number) >= SAVE_VERSION) this.players.set(id, upgradeState(c, state));
    }
  }
  /** opts.pending: a new save asks to pick a home (SGODOT-303), when the creating client can offer it; opts.guide: it
   * starts the new-player guide (SGODOT-341), when the client can show it. */
  get(player: string, now: number, opts: { pending?: boolean; guide?: boolean } = {}): P0State {
    let s = this.players.get(player);
    if (!s) { s = freshState(this.c, player, now, undefined, opts); this.players.set(player, s); this.flush(); }
    // Expired parcels pay out on any read, so the coins are saved even if the next command is refused.
    if (settleParcels(this.c, s, now + s.clock_ms)) this.flush();
    return s;
  }
  size(): number { return this.players.size; }
  /** A stored player, without creating one (admin tools). */
  peek(player: string): P0State | undefined { return this.players.get(player); }
  all(): P0State[] { return [...this.players.values()]; }
  put(state: P0State): void { this.players.set(state.player, state); this.flush(); }
  reset(player: string, now: number, opts: { pending?: boolean; guide?: boolean } = {}): P0State { const s = freshState(this.c, player, now, undefined, opts); this.put(s); return s; }
  private flush(): void {
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    writeFileSync(tmp, JSON.stringify(Object.fromEntries(this.players)));
    renameSync(tmp, this.file);
  }
}
