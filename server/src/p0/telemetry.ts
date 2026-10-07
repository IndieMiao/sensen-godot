/**
 * Observation log for playtests (plan §14.8.1 "事件最小集", §17.2.2 "操作被理解"; SGODOT-232 S7): one JSON line per
 * command — what was asked, from where and how (hold / tap), the result or refusal, every Energy change with its
 * reason, XP, levels and first-time moments — plus the few UI moments only the client sees (teaching cards, the
 * four-line cards, Today rows done). It pays nothing out and records no real-world position or account details.
 * Files: <dir>/p0-events-YYYY-MM-DD.jsonl (UTC wall-clock day); no dir = nothing written (tests pass a sink).
 */
import { appendFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import type { P0Event } from './progress.js';

/** Command fields worth keeping; anything else (free text, bulky arrays) stays out of the log. */
const CMD_FIELDS = ['type', 'plot', 'plots', 'seed', 'item', 'qty', 'shop', 'recipe', 'items', 'request', 'resident',
  'bait', 'outcome', 'key', 'keys', 'eat', 'from', 'spot', 'floor', 'rock', 'space', 'place', 'src', 'expect_seq', 'pot'] as const;
const MAX_STR = 64, MAX_LIST = 8;

/** UI moments the client may report, each with the only fields kept beside `kind` (no position, no free text). */
export const UI_FIELDS: Record<string, readonly string[]> = {
  tip_shown: ['key'], tip_hidden: ['key', 'ms', 'why'], card_shown: ['card', 'fish', 'dish', 'item'], today_done: ['row', 'key'],
  energy_card: ['need', 'refused'], gate_card: ['gate', 'need', 'level'], screen: ['name'], level_banner: ['skill', 'level'],
  session_start: [], session_end: ['ms'],
};
export const UI_KINDS = new Set(Object.keys(UI_FIELDS));

/** A short flat value: numbers and booleans as they are, strings cut to 64 characters, anything else dropped. */
function flat(v: unknown): string | number | boolean | undefined {
  if (typeof v === 'number') return Number.isFinite(v) ? v : undefined;
  if (typeof v === 'boolean') return v;
  if (typeof v === 'string') return v.slice(0, MAX_STR);
  return undefined;
}

export interface CommandRecord {
  kind: 'command'; t: number; clock: number; player: string; seq: number; cmd: Record<string, unknown>;
  ok: boolean; code?: string; detail?: unknown; energy: [number, number]; events: P0Event[];
}
export interface UiRecord { kind: 'ui'; t: number; player: string; event: Record<string, unknown> }
export type LogRecord = CommandRecord | UiRecord;

/**
 * The log never affects the game (PR #23 review): a write that fails (folder removed mid-playtest, disk full, no
 * permission) is retried once after recreating the folder, then the log warns once and stops writing.
 */
export class P0EventLog {
  private broken = false;
  constructor(private dir?: string, private sink?: (r: LogRecord) => void, private warn: (msg: string) => void = m => console.warn(m)) {
    if (dir) {
      try { mkdirSync(dir, { recursive: true }); } catch (err) { this.stop(err); }
    }
  }
  write(record: LogRecord): void {
    try { this.sink?.(record); } catch { /* a test sink never breaks a command either */ }
    if (!this.dir || this.broken) return;
    const file = path.join(this.dir, `p0-events-${new Date(record.t).toISOString().slice(0, 10)}.jsonl`);
    const line = JSON.stringify(record) + '\n';
    try { appendFileSync(file, line); return; } catch { /* the folder may be gone: recreate it once */ }
    try { mkdirSync(this.dir, { recursive: true }); appendFileSync(file, line); } catch (err) { this.stop(err); }
  }
  get stopped(): boolean { return this.broken; }
  private stop(err: unknown): void {
    this.broken = true;
    this.warn(`[p0] observation log stopped (${this.dir}): ${err instanceof Error ? err.message : String(err)}`);
  }
}

/** The kept command fields, each short: strings cut to 64 characters, lists to their first 8 flat items. */
export function commandFields(raw: unknown): Record<string, unknown> {
  const body = (raw && typeof raw === 'object' ? raw : {}) as Record<string, unknown>;
  const out: Record<string, unknown> = {};
  for (const k of CMD_FIELDS) {
    const v = body[k];
    if (Array.isArray(v)) out[k] = v.slice(0, MAX_LIST).map(flat).filter(x => x !== undefined);
    else if (flat(v) !== undefined) out[k] = flat(v);
  }
  return out;
}

/** Keep a reported UI moment only if it is a known kind; only that kind's fields, short and flat. */
export function uiEvent(raw: unknown): Record<string, unknown> | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const e = raw as Record<string, unknown>;
  if (typeof e.kind !== 'string' || !UI_KINDS.has(e.kind)) return null;
  const out: Record<string, unknown> = { kind: e.kind };
  for (const k of UI_FIELDS[e.kind]) {
    const v = flat(e[k]);
    if (v !== undefined) out[k] = v;
  }
  return out;
}
