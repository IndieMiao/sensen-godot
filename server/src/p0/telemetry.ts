/**
 * Observation log for playtests (plan §14.8.1 "事件最小集", §17.2.2 "操作被理解"; SGODOT-232 S7): one JSON line per
 * command — what was asked, from where and how (hold / tap), the result or refusal, every Energy change with its
 * reason, XP, levels and first-time moments — plus the few UI moments only the client sees (teaching cards, the
 * four-line cards, Today rows done). It pays nothing out and records no real-world position or account details.
 * Since C25-4 (user, 10-28) every line also carries `ip`: the address P0 takes for the request (req.ip — behind Caddy
 * with P0_TRUST_PROXY=1 the one Caddy appended, never what a client wrote into X-Forwarded-For).
 * Files: <dir>/p0-events-YYYY-MM-DD.jsonl (UTC wall-clock day); no dir = nothing written (tests pass a sink).
 * Kept: P0_EVENT_KEEP_DAYS=N removes day files older than N days when a new day's first line is written; unset keeps
 * every file, as before.
 * Client errors (SGODOT-486, kind client_error) never go into that log: its lines carry the player and the IP, and the
 * privacy policy says error reports are tied to no player. They go to their own day files, p0-errors-YYYY-MM-DD.jsonl
 * beside it, a line holding only t, version, platform, message, stack and scene (ErrorRecord), kept 30 days.
 */
import { appendFileSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import type { P0Event } from './progress.js';

/** Command fields worth keeping; anything else (free text, bulky arrays) stays out of the log. */
const CMD_FIELDS = ['type', 'plot', 'plots', 'seed', 'item', 'qty', 'shop', 'recipe', 'items', 'request', 'resident',
  'bait', 'outcome', 'key', 'keys', 'eat', 'from', 'spot', 'floor', 'rock', 'space', 'place', 'src', 'expect_seq', 'pot', 'facility',
  'op', 'step', 'bet', 'action', 'mine', 'day', 'to', 'via', 'targets', 'hurt_by', 'stunned', 'ground'] as const;
const MAX_STR = 64, MAX_LIST = 8;

/** UI moments the client may report, each with the only fields kept beside `kind` (no position, no free text). */
export const UI_FIELDS: Record<string, readonly string[]> = {
  tip_shown: ['key'], tip_hidden: ['key', 'ms', 'why'], card_shown: ['card', 'fish', 'dish', 'item'], today_done: ['row', 'key'],
  energy_card: ['need', 'refused'], gate_card: ['gate', 'need', 'level'], screen: ['name'], level_banner: ['skill', 'level'],
  session_start: [], session_end: ['ms'],
  // How long a world took to come up on this device (int9: the vivo shows no app logcat, so P0_TIMING goes here too):
  // navigation start → attach → first and second drawn frame, in ms, with the device's cores, model and GPU.
  scene_load: ['scene', 'place', 'attach_ms', 'first_ms', 'second_ms', 'cold', 'cores', 'model', 'gpu'],
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
  kind: 'command'; t: number; clock: number; player: string; ip?: string; seq: number; cmd: Record<string, unknown>;
  ok: boolean; code?: string; detail?: unknown; energy: [number, number]; events: P0Event[];
}
export interface UiRecord { kind: 'ui'; t: number; player: string; ip?: string; event: Record<string, unknown> }   // ip: C25-4; absent in lines written before it
export type LogRecord = CommandRecord | UiRecord;
/** One client error: no player, no IP, no channel, no device (奕星 / 李白 11-12; the policy's §2 / §6 list these six). */
export interface ErrorRecord { t: number; version?: string; platform?: string; message: string; stack: string; scene: string }

export const ERROR_KIND = 'client_error';
const ERR_MESSAGE = 500, ERR_STACK_LINES = 20, ERR_STACK_LINE = 200, ERR_SCENE = 64, ERR_HEADER = 16;
const ERR_PLATFORMS = new Set(['android', 'ios', 'desktop']);   // contract-accounts.md §0
// A run of 32+ hex digits (a token, a key) never reaches the file, should an error ever print one (#1013 周瑜).
const LONG_HEX = /[0-9a-fA-F]{32,}/g;
const scrub = (s: string) => s.replace(LONG_HEX, '…');

/** A reported client error as its file line: message, stack (first 20 lines, each cut to 200) and scene, cut short;
 * version and platform from the request headers when it sends them (an older client sends no platform; only android /
 * ios / desktop kept). Long hex runs are cut out of message and stack. Every other field the client sent is dropped. Null when it is not a client error or has no message. */
export function errorRecord(raw: unknown, t: number, headers: Record<string, unknown>): ErrorRecord | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const e = raw as Record<string, unknown>;
  if (e.kind !== ERROR_KIND || typeof e.message !== 'string' || e.message === '') return null;
  const stack = typeof e.stack === 'string' ? e.stack.split('\n').slice(0, ERR_STACK_LINES).map(l => scrub(l).slice(0, ERR_STACK_LINE)).join('\n') : '';
  const header = (name: string) => { const v = headers[name]; return typeof v === 'string' && v !== '' ? v.slice(0, ERR_HEADER) : undefined; };
  const version = header('x-p0-version'), platform = ERR_PLATFORMS.has(String(headers['x-p0-platform'])) ? String(headers['x-p0-platform']) : undefined;
  return { t, ...(version ? { version } : {}), ...(platform ? { platform } : {}), message: scrub(e.message).slice(0, ERR_MESSAGE), stack,
    scene: typeof e.scene === 'string' ? e.scene.slice(0, ERR_SCENE) : '' };
}

/**
 * The log never affects the game (PR #23 review): a write that fails (folder removed mid-playtest, disk full, no
 * permission) is retried once after recreating the folder, then the log warns once and stops writing.
 */
export class P0EventLog<R extends { t: number } = LogRecord> {
  private broken = false;
  private day = '';
  /** prefix: the day files' name, p0-events (the observation log) or p0-errors (client errors). */
  constructor(private dir?: string, private sink?: (r: R) => void, private warn: (msg: string) => void = m => console.warn(m),
    private keepDays?: number, private prefix = 'p0-events') {
    if (dir) {
      try { mkdirSync(dir, { recursive: true }); } catch (err) { this.stop(err); }
    }
  }
  write(record: R): void {
    try { this.sink?.(record); } catch { /* a test sink never breaks a command either */ }
    if (!this.dir || this.broken) return;
    const day = new Date(record.t).toISOString().slice(0, 10);
    if (day !== this.day) { this.day = day; this.pruneBefore(day); }
    const file = path.join(this.dir, `${this.prefix}-${day}.jsonl`);
    const line = JSON.stringify(record) + '\n';
    try { appendFileSync(file, line); return; } catch { /* the folder may be gone: recreate it once */ }
    try { mkdirSync(this.dir, { recursive: true }); appendFileSync(file, line); } catch (err) { this.stop(err); }
  }
  get stopped(): boolean { return this.broken; }
  /** Remove the day files older than keepDays as of `now`, though nothing is being written (#1013 后裔: a log with no
   * new line for weeks — client errors — must not keep files past its days). The server calls it at start and every
   * 6 hours; write() also does it on a new day's first line. */
  prune(now: number): void { this.pruneBefore(new Date(now).toISOString().slice(0, 10)); }
  /** Day files older than keepDays before `today`; never this log's other files. A failure here never stops the log. */
  private pruneBefore(today: string): void {
    if (!this.dir || !this.keepDays) return;
    const oldest = new Date(Date.parse(today + 'T00:00:00Z') - this.keepDays! * 86_400_000).toISOString().slice(0, 10);
    try {
      for (const f of readdirSync(this.dir!)) {
        const m = /^(.+)-(\d{4}-\d{2}-\d{2})\.jsonl$/.exec(f);
        if (m && m[1] === this.prefix && m[2] < oldest) rmSync(path.join(this.dir!, f), { force: true });
      }
    } catch { /* the folder may be gone: write() recreates it */ }
  }
  private stop(err: unknown): void {
    this.broken = true;
    this.warn(`[p0] ${this.prefix} log stopped (${this.dir}): ${err instanceof Error ? err.message : String(err)}`);
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
