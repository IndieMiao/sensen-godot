/**
 * SYS-UPDATE / SYS-MAINT on the server (SGODOT-232; user decision via 奕星, contract with 刘邦 who draws the two
 * full-screen cards). After the demo key (401) and before any P0 route or rate limit, in §10.7.1's order — Update
 * wins over Maintenance, so an old client sees Update once instead of being stopped again when maintenance ends:
 *  - Update: a request carrying `x-p0-version: <versionCode>` below the minimum gets HTTP 426
 *    {ok:false, code:"update_required", url}. No header (desktop, editor, test builds) always passes. Without a
 *    download url there is no minimum (q(74), 李白 / 苏烈 on #85): an Update card with nowhere to go would strand the
 *    player, so the admin route refuses a minimum without one and a start-up minimum without one only warns.
 *  - Maintenance: while on, every /v1/p0/* request (state, commands, presence, telemetry, the outpost WebSocket
 *    upgrade) gets HTTP 503 {ok:false, code:"maintenance", back_at?} — back_at is UTC ISO, absent when unknown.
 * /v1/healthz and the admin app (127.0.0.1 inside the container) are never gated.
 *
 * Settings: P0_MIN_VERSION / P0_UPDATE_URL and P0_MAINT=1 / P0_MAINT_UNTIL at start, changed at run time through the
 * admin routes (deploy-hk.sh maint-on / maint-off / min-version), which persist to <save dir>/gate.json so a restart
 * keeps them. The environment can only make things stricter: the minimum is the higher of the two, and P0_MAINT=1
 * keeps maintenance on whatever the file says.
 */
import { existsSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import type { IncomingHttpHeaders } from 'node:http';

/** update_on: a minimum is in force (min_version > 0 and a download url). */
export interface GateState { maintenance: { on: boolean; back_at?: string }; min_version: number; update_url: string; update_on: boolean }
export type GateRefusal = { status: 426 | 503; body: { ok: false; code: 'update_required' | 'maintenance'; url?: string; back_at?: string } };
interface GateFile { maintenance?: { on?: boolean; back_at?: string | null }; min_version?: number; update_url?: string }

/** "2026-10-09T06:30:00Z" for any time Date can read; undefined when empty or unreadable. */
export function isoMinute(raw: unknown): string | undefined {
  if (typeof raw !== 'string' || raw.trim() === '') return undefined;
  const t = Date.parse(raw);
  return Number.isNaN(t) ? undefined : new Date(t).toISOString().replace(/\.\d{3}Z$/, 'Z');
}

export class P0Gate {
  private file: GateFile = {};
  private readonly env: { maint: boolean; until?: string; min: number; url: string };
  /** Why gate.json could not be read (it is then ignored); tools/p0_server.ts prints it. */
  readonly loadError?: string;

  /** file: where run-time changes persist (undefined = memory only, for tests and local playtests). */
  constructor(private readonly path?: string, env: NodeJS.ProcessEnv = process.env) {
    const min = Number(env.P0_MIN_VERSION ?? 0);
    this.env = { maint: env.P0_MAINT === '1', until: isoMinute(env.P0_MAINT_UNTIL), min: Number.isInteger(min) && min > 0 ? min : 0,
      url: String(env.P0_UPDATE_URL ?? '') };
    if (path && existsSync(path)) {
      try { this.file = JSON.parse(readFileSync(path, 'utf8')) as GateFile; } catch (e) { this.file = {}; this.loadError = String(e); }
    }
  }

  state(): GateState {
    const fileMin = Number.isInteger(this.file.min_version) ? Number(this.file.min_version) : 0;
    const on = this.env.maint || this.file.maintenance?.on === true;
    const backAt = this.file.maintenance?.on === true ? isoMinute(this.file.maintenance.back_at) : this.env.until;
    const minVersion = Math.max(this.env.min, fileMin);
    const updateUrl = this.file.update_url ?? this.env.url;
    return {
      maintenance: on ? { on: true, ...(backAt ? { back_at: backAt } : {}) } : { on: false },
      min_version: minVersion,
      update_url: updateUrl,
      update_on: minVersion > 0 && updateUrl !== '',
    };
  }

  /** What the environment holds the gate to (admin answers show it: a lower minimum or maintenance off can't go under it). */
  envFloor(): { min_version: number; maintenance: boolean } { return { min_version: this.env.min, maintenance: this.env.maint }; }

  setMaintenance(on: boolean, backAt?: string): GateState {
    this.file.maintenance = on ? { on: true, back_at: isoMinute(backAt) ?? null } : { on: false, back_at: null };
    this.save();
    return this.state();
  }

  setMinVersion(version: number, url?: string): GateState {
    this.file.min_version = version;
    // An empty url clears the run-time one, so the environment's (P0_UPDATE_URL) applies again instead of being
    // overwritten with "" (苏烈 on #85).
    if (url === '') delete this.file.update_url;
    else if (url !== undefined) this.file.update_url = url;
    this.save();
    return this.state();
  }

  /** The refusal for a request with these headers, or null to let it through. Update is checked first (§10.7.1). */
  check(headers: IncomingHttpHeaders): GateRefusal | null {
    const st = this.state();
    const raw = headers['x-p0-version'];
    const sent = Array.isArray(raw) ? raw[0] : raw;
    if (st.update_on && sent !== undefined && sent !== '') {
      const v = /^\d+$/.test(sent.trim()) ? Number(sent.trim()) : 0;   // unreadable = too old
      if (v < st.min_version) return { status: 426, body: { ok: false, code: 'update_required', url: st.update_url } };
    }
    if (st.maintenance.on) {
      return { status: 503, body: { ok: false, code: 'maintenance', ...(st.maintenance.back_at ? { back_at: st.maintenance.back_at } : {}) } };
    }
    return null;
  }

  private save(): void {
    if (!this.path) return;
    const tmp = this.path + '.tmp';
    writeFileSync(tmp, JSON.stringify(this.file, null, 2));
    renameSync(tmp, this.path);
  }
}

/** The raw HTTP answer for a refused WebSocket upgrade: same status and JSON body as the routes. */
export function upgradeRefusal(r: GateRefusal): string {
  const body = JSON.stringify(r.body);
  const reason = r.status === 426 ? 'Upgrade Required' : 'Service Unavailable';
  return `HTTP/1.1 ${r.status} ${reason}\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(body)}\r\nConnection: close\r\n\r\n${body}`;
}
