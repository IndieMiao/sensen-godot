/** In-memory P0 state store with an optional JSON file for local / emulator playtests. */
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { P0Content } from './content.js';
import { freshState, upgradeState, type P0State } from './state.js';

export class P0Store {
  private players = new Map<string, P0State>();
  constructor(private c: P0Content, private file?: string) {
    if (file && existsSync(file)) {
      const saved = JSON.parse(readFileSync(file, 'utf8')) as Record<string, P0State>;
      for (const [id, state] of Object.entries(saved)) this.players.set(id, upgradeState(c, state));
    }
  }
  get(player: string, now: number): P0State {
    let s = this.players.get(player);
    if (!s) { s = freshState(this.c, player, now); this.players.set(player, s); this.flush(); }
    return s;
  }
  put(state: P0State): void { this.players.set(state.player, state); this.flush(); }
  reset(player: string, now: number): P0State { const s = freshState(this.c, player, now); this.put(s); return s; }
  private flush(): void {
    if (!this.file) return;
    const tmp = `${this.file}.tmp`;
    writeFileSync(tmp, JSON.stringify(Object.fromEntries(this.players)));
    renameSync(tmp, this.file);
  }
}
