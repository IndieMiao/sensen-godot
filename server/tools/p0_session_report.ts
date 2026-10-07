/**
 * First-session report from the P0 observation log (SGODOT-232 S7; plan §14.2 director table, §14.8.1 metrics):
 *   node --import tsx tools/p0_session_report.ts <events dir or .jsonl files…> [--json out.json]
 * For each player: sessions (a gap of 30 min starts a new one), the first session's milestones in minutes from its
 * first command, its end Energy, refusals by code, and every Energy spend with how it was pressed (hold / tap) —
 * the list an observer goes through for "did anything cost Energy the player did not mean to spend?".
 */
import { existsSync, readdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { LogRecord } from '../src/p0/telemetry.js';

type Command = Extract<LogRecord, { kind: 'command' }>;
type Ev = { kind?: string; [k: string]: unknown };

const SESSION_GAP_MS = 30 * 60_000;
/** §14.1.1 / §17.2.2 targets for the first session (minutes); slow players get 1.5×. */
const TARGETS = { loop: 20, fishing_lv2: 30, cooking_lv2: 30, end_energy: 180 };

function milestones(session: Command[], start: number) {
  const at = (r: Command) => Math.round((r.t - start) / 60_000);
  const first = (test: (r: Command, e: Ev) => boolean) => {
    for (const r of session) if (r.ok && (r.events as Ev[]).some(e => test(r, e))) return at(r);
    return null;
  };
  return {
    first_sow: first(r => r.cmd.type === 'sow'),
    first_cast: first(r => r.cmd.type === 'cast'),
    first_catch: first((_r, e) => e.kind === 'catch' && e.result === 'landed'),
    first_dish: first((_r, e) => e.kind === 'dish' && !e.mystery),
    first_meal: first((_r, e) => e.kind === 'meal' && Number(e.gain) > 0),
    fishing_lv2: first((_r, e) => e.kind === 'level' && e.skill === 'fishing' && e.level === 2),
    cooking_lv2: first((_r, e) => e.kind === 'level' && e.skill === 'cooking' && e.level === 2),
  };
}

export function sessionReport(records: LogRecord[]) {
  const byPlayer = new Map<string, Command[]>();
  const opened = new Map<string, number[]>();   // session_start moments the client reported (the app opened)
  for (const r of records) {
    if (r.kind === 'command') byPlayer.set(r.player, [...(byPlayer.get(r.player) ?? []), r]);
    else if (r.kind === 'ui' && r.event?.kind === 'session_start') opened.set(r.player, [...(opened.get(r.player) ?? []), r.t]);
  }
  return [...byPlayer.entries()].map(([player, list]) => {
    list.sort((a, b) => a.t - b.t);
    const sessions: Command[][] = [];
    for (const r of list) {
      const last = sessions.at(-1);
      if (last && r.t - last.at(-1)!.t < SESSION_GAP_MS) last.push(r); else sessions.push([r]);
    }
    // Minutes count from the app opening when the client reported it (≤ 30 min before the first command), else from it.
    const s = sessions[0];
    const start = Math.min(s[0].t, ...(opened.get(player) ?? []).filter(t => t <= s[0].t && s[0].t - t < SESSION_GAP_MS));
    const m = milestones(s, start);
    const refusals: Record<string, number> = {};
    for (const r of s) if (!r.ok) refusals[String(r.code)] = (refusals[String(r.code)] ?? 0) + 1;
    const spends = s.filter(r => r.ok).flatMap(r => (r.events as Ev[]).filter(e => e.kind === 'energy' && Number(e.delta) < 0)
      .map(e => ({ minute: Math.round((r.t - start) / 60_000), type: String(r.cmd.type), src: (r.cmd.src as string | undefined) ?? null,
        energy: -Number(e.delta) })));
    const endEnergy = s.at(-1)!.energy[1];
    const within = (v: number | null, limit: number) => v !== null && v <= limit;
    return {
      player, sessions: sessions.length,
      first: {
        minutes: Math.round((s.at(-1)!.t - start) / 60_000), commands: s.length, end_energy: endEnergy, milestones: m, refusals, spends,
        checks: {
          loop_by_20: within(m.first_meal, TARGETS.loop), fishing_lv2_by_30: within(m.fishing_lv2, TARGETS.fishing_lv2),
          cooking_lv2_by_30: within(m.cooking_lv2, TARGETS.cooking_lv2), end_energy_180: endEnergy >= TARGETS.end_energy,
        },
      },
    };
  });
}

/** Log lines → records. A half-written last line (the server was killed) or a record of a kind this script does not
 * know is skipped and counted, never fatal (PR #23 review). */
export function parseRecords(text: string): { records: LogRecord[]; skipped: number } {
  const records: LogRecord[] = [];
  let skipped = 0;
  for (const line of text.split('\n')) {
    if (!line.trim()) continue;
    let r: unknown;
    try { r = JSON.parse(line); } catch { skipped += 1; continue; }
    const rec = (r ?? {}) as Record<string, unknown>;
    const ok = typeof rec.player === 'string' && typeof rec.t === 'number'
      && ((rec.kind === 'command' && Array.isArray(rec.events) && Array.isArray(rec.energy) && !!rec.cmd)
        || (rec.kind === 'ui' && !!rec.event && typeof rec.event === 'object'));
    if (ok) records.push(rec as unknown as LogRecord); else skipped += 1;
  }
  return { records, skipped };
}

function readRecords(inputs: string[]): LogRecord[] {
  const files = inputs.flatMap(p => (statSync(p).isDirectory()
    ? readdirSync(p).filter(f => f.endsWith('.jsonl')).map(f => path.join(p, f)) : [p]));
  let skipped = 0;
  const records = files.flatMap(f => { const r = parseRecords(readFileSync(f, 'utf8')); skipped += r.skipped; return r.records; });
  if (skipped) console.error(`skipped ${skipped} unreadable line(s)`);
  return records;
}

function markdown(report: ReturnType<typeof sessionReport>): string {
  const cell = (v: number | null) => (v === null ? '—' : String(v));
  const rows = report.map(p => {
    const m = p.first.milestones;
    return `| ${p.player} | ${p.sessions} | ${cell(m.first_sow)} | ${cell(m.first_cast)} | ${cell(m.first_meal)} | ${cell(m.fishing_lv2)} | `
      + `${cell(m.cooking_lv2)} | ${p.first.end_energy} | ${p.first.spends.length} (${p.first.spends.filter(x => x.src === 'hold').length} hold) | `
      + `${Object.entries(p.first.refusals).map(([k, n]) => `${k} ×${n}`).join(', ') || '—'} |`;
  });
  return ['| player | sessions | sow | cast | meal (loop) | Fishing Lv2 | Cooking Lv2 | end Energy | spends | refusals |',
    '|---|---|---|---|---|---|---|---|---|---|', ...rows].join('\n');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const jsonAt = args.indexOf('--json');
  const out = jsonAt >= 0 ? args.splice(jsonAt, 2)[1] : null;
  const inputs = args.filter(a => existsSync(a));
  if (!inputs.length) { console.error('usage: p0_session_report.ts <events dir or .jsonl files…> [--json out.json]'); process.exit(2); }
  const report = sessionReport(readRecords(inputs));
  console.log(markdown(report));
  if (out) writeFileSync(out, JSON.stringify(report, null, 2));
}
