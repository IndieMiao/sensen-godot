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
  'bait', 'outcome', 'key', 'keys', 'eat', 'from', 'spot', 'floor', 'rock', 'space', 'place', 'src', 'expect_seq'] as const;

/** UI moments the client may report (anything else is dropped). */
export const UI_KINDS = new Set(['tip_shown', 'tip_hidden', 'card_shown', 'today_done', 'energy_card', 'gate_card', 'screen',
  'level_banner', 'session_start', 'session_end']);

export interface CommandRecord {
  kind: 'command'; t: number; clock: number; player: string; seq: number; cmd: Record<string, unknown>;
  ok: boolean; code?: string; detail?: unknown; energy: [number, number]; events: P0Event[];
}
export interface UiRecord { kind: 'ui'; t: number; player: string; event: Record<string, unknown> }
export type LogRecord = CommandRecord | UiRecord;

export class P0EventLog {
  constructor(private dir?: string, private sink?: (r: LogRecord) => void) {
    if (dir) mkdirSync(dir, { recursive: true });
  }
  write(record: LogRecord): void {
    this.sink?.(record);
    if (!this.dir) return;
    const day = new Date(record.t).toISOString().slice(0, 10);
    appendFileSync(path.join(this.dir, `p0-events-${day}.jsonl`), JSON.stringify(record) + '\n');
  }
}

export function commandFields(raw: unknown): Record<string, unknown> {
  const body = (raw ?? {}) as Record<string, unknown>;
  return Object.fromEntries(CMD_FIELDS.filter(k => body[k] !== undefined).map(k => [k, body[k]]));
}

/** Keep a reported UI moment only if it is a known kind with short, flat fields. */
export function uiEvent(raw: unknown): Record<string, unknown> | null {
  if (!raw || typeof raw !== 'object') return null;
  const e = raw as Record<string, unknown>;
  if (typeof e.kind !== 'string' || !UI_KINDS.has(e.kind)) return null;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(e).slice(0, 8)) {
    if (typeof v === 'number' || typeof v === 'boolean') out[k] = v;
    else if (typeof v === 'string') out[k] = v.slice(0, 80);
  }
  return out;
}
