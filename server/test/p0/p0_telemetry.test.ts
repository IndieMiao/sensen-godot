/** SGODOT-232 S7: the observation log (one line per command, plus reported UI moments) and the session report. */
import Fastify from 'fastify';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { settleEnergy } from '../../src/p0/rules.js';
import { commandFields, errorRecord, P0EventLog, uiEvent, type ErrorRecord, type LogRecord } from '../../src/p0/telemetry.js';
import { trustProxyFromEnv } from '../../src/p0/guard.js';
import { parseRecords, sessionReport } from '../../tools/p0_session_report.js';

const c = loadP0Content();
const T0 = Date.UTC(2026, 9, 8, 2);
const headers = { 'x-p0-player': 'telemetry-player' };

async function withServer(fn: (app: ReturnType<typeof Fastify>, records: LogRecord[], tick: (ms: number) => void, store: P0Store) => Promise<void>,
  dir?: string, log?: P0EventLog) {
  const records: LogRecord[] = [];
  let now = T0;
  const app = Fastify();
  const store = new P0Store(c);
  registerP0Routes(app, { content: c, store, now: () => now, dev: false, log: log ?? new P0EventLog(dir, r => records.push(r)) });
  try { await fn(app, records, ms => { now += ms; }, store); } finally { await app.close(); }
}

describe('observation log (§14.8.1, §17.2.2; SGODOT-232 S7)', () => {
  it('writes one line per command with how it was pressed, the result, the Energy before and after and the events', async () => {
    await withServer(async (app, records) => {
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'sow', plot: 0, seed: 'seed_radish', src: 'hold', space: 'home', note: 'x'.repeat(500) } });
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'sow', plot: 0, seed: 'seed_radish', src: 'tap' } });
      const [sow, again] = records as Extract<LogRecord, { kind: 'command' }>[];
      expect(sow).toMatchObject({ kind: 'command', t: T0, player: 'telemetry-player', seq: 0, ok: true, energy: [200, 198],
        cmd: { type: 'sow', plot: 0, seed: 'seed_radish', src: 'hold', space: 'home' } });
      expect(sow.cmd).not.toHaveProperty('note');
      expect(sow.events).toContainEqual({ kind: 'energy', delta: -2, reason: 'sow' });
      expect(again).toMatchObject({ ok: false, code: 'wrong_state', energy: [198, 198], events: [] });
    });
  });

  it('keeps reported UI moments of known kinds only, with short flat fields, and limits them per minute', async () => {
    await withServer(async (app, records, tick) => {
      const events = [{ kind: 'tip_shown', key: 's'.repeat(200), text: 'y'.repeat(200) }, { kind: 'secret_location', lat: 31.2 },
        { kind: 'card_shown', card: { nested: 1 }, lat: 31.2 }];
      const r = await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events } });
      expect(r.json()).toEqual({ ok: true, accepted: 2 });
      // only the kind's own fields, strings cut to 64; nested values and anything like a position dropped
      expect(records).toEqual([
        { kind: 'ui', t: T0, player: 'telemetry-player', ip: '127.0.0.1', event: { kind: 'tip_shown', key: 's'.repeat(64) } },
        { kind: 'ui', t: T0, player: 'telemetry-player', ip: '127.0.0.1', event: { kind: 'card_shown' } }]);
      for (let i = 0; i < 7; i++) await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: Array(20).fill({ kind: 'screen' }) } });
      expect(records.length).toBe(120);   // 2 + 118 more this minute
      tick(60_000);
      await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: [{ kind: 'screen' }] } });
      expect(records.length).toBe(121);
      expect((await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: Array(21).fill({ kind: 'screen' }) } })).statusCode).toBe(400);
    });
  });

  it('refuses a bad player id and a batch that is not a list (PR #23 review)', async () => {
    await withServer(async app => {
      expect((await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers: { 'x-p0-player': 'x' }, payload: { events: [] } })).json())
        .toEqual({ ok: false, code: 'bad_player' });
      expect((await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: { kind: 'screen' } } })).statusCode).toBe(400);
      expect((await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: {} })).statusCode).toBe(400);
    });
  });

  it('keeps every field short: lists to 8 flat items, strings to 64; a UI kind is found wherever it sits (PR #23 review)', () => {
    expect(commandFields({ type: 'sell', items: Array.from({ length: 20 }, (_, i) => `item_${i}`), key: 'k'.repeat(500),
      outcome: { big: 'x'.repeat(1000) }, keys: [1, { a: 1 }, 'b'], plot: Number.NaN })).toEqual({
      type: 'sell', items: Array.from({ length: 8 }, (_, i) => `item_${i}`), key: 'k'.repeat(64), keys: [1, 'b'] });
    const late = Object.fromEntries([...Array.from({ length: 12 }, (_, i) => [`f${i}`, i]), ['kind', 'screen'], ['name', 'bag'],
      ['x'.repeat(300), 'long field name']]);
    expect(uiEvent(late)).toEqual({ kind: 'screen', name: 'bag' });
    expect(uiEvent([{ kind: 'screen' }])).toBeNull();
  });

  it('keeps a scene load with its timings and the device, nothing else (int9: the vivo has no app logcat)', () => {
    expect(uiEvent({ kind: 'scene_load', scene: 'P0Outpost', place: 'sh_tea_1', attach_ms: 912, first_ms: 2036, second_ms: 2287,
      cold: false, cores: 8, model: 'V2509A', gpu: 'Mali-G1-Ultra MC12', lat: 31.2, name: 'someone' })).toEqual({
      kind: 'scene_load', scene: 'P0Outpost', place: 'sh_tea_1', attach_ms: 912, first_ms: 2036, second_ms: 2287,
      cold: false, cores: 8, model: 'V2509A', gpu: 'Mali-G1-Ultra MC12' });
  });

  it('records Energy before a command with the recovery the command saw, also on a refusal (PR #23 review)', async () => {
    await withServer(async (app, records, _tick, store) => {
      const s = store.get('telemetry-player', T0);
      s.energy = { value: 150, tick_ms: T0 - 3_600_000 };
      store.put(s);
      const settled = structuredClone(s);
      settleEnergy(c, settled, T0);
      expect(settled.energy.value).toBeGreaterThan(150);
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'sow', plot: 0, seed: 'seed_radish' } });
      await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'till', plot: 999 } });
      const [sow, bad] = records as Extract<LogRecord, { kind: 'command' }>[];
      expect(sow.energy).toEqual([settled.energy.value, settled.energy.value - 2]);
      expect(bad).toMatchObject({ ok: false, energy: [settled.energy.value - 2, settled.energy.value - 2] });
    });
  });

  it('a log that cannot write never fails a command: it warns once and stops (PR #23 review)', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-events-'));
    const warnings: string[] = [];
    try {
      const log = new P0EventLog(path.join(dir, 'events'), undefined, m => warnings.push(m));
      rmSync(path.join(dir, 'events'), { recursive: true });
      writeFileSync(path.join(dir, 'events'), 'not a folder');   // the folder cannot be recreated either
      await withServer(async (app, _records, _tick, store) => {
        for (let i = 0; i < 3; i++) {
          const r = await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'read_inbox', keys: [] } });
          expect(r.json()).toMatchObject({ ok: true });
        }
        expect(store.get('telemetry-player', T0).seq).toBe(3);   // every command saved
        expect((await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: [{ kind: 'screen' }] } })).statusCode).toBe(200);
      }, undefined, log);
      expect(log.stopped).toBe(true);
      expect(warnings).toHaveLength(1);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('recreates a removed log folder once and keeps writing', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-events-'));
    try {
      const log = new P0EventLog(path.join(dir, 'events'));
      rmSync(path.join(dir, 'events'), { recursive: true });
      await withServer(async app => {
        await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'rest' } });
      }, undefined, log);
      expect(readFileSync(path.join(dir, 'events', 'p0-events-2026-10-08.jsonl'), 'utf8').trim().split('\n')).toHaveLength(1);
      expect(log.stopped).toBe(false);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('appends to a daily JSONL file', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-events-'));
    try {
      await withServer(async app => {
        await app.inject({ method: 'POST', url: '/v1/p0/commands', headers, payload: { type: 'rest' } });
      }, dir);
      const lines = readFileSync(path.join(dir, 'p0-events-2026-10-08.jsonl'), 'utf8').trim().split('\n');
      expect(lines).toHaveLength(1);
      expect(JSON.parse(lines[0])).toMatchObject({ kind: 'command', cmd: { type: 'rest' }, ok: false });
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});

describe('first-session report (§14.2 director table; SGODOT-232 S7)', () => {
  it('finds the milestones, the end Energy and every Energy spend with how it was pressed', () => {
    const rec = (min: number, cmd: Record<string, unknown>, events: unknown[], energy: [number, number], code?: string) =>
      ({ kind: 'command', t: T0 + min * 60_000, clock: T0 + min * 60_000, player: 'p1', seq: 0, cmd, ok: !code, ...(code ? { code } : {}),
        energy, events }) as LogRecord;
    const records: LogRecord[] = [
      { kind: 'ui', t: T0, player: 'p1', event: { kind: 'session_start' } },   // the app opened at minute 0
      rec(1, { type: 'sow', src: 'hold' }, [{ kind: 'energy', delta: -2, reason: 'sow' }], [200, 198]),
      rec(9, { type: 'cast', src: 'tap' }, [{ kind: 'energy', delta: -5, reason: 'cast' }], [180, 175]),
      rec(10, { type: 'reel' }, [{ kind: 'catch', fish: 'fish_crucian', result: 'landed' }], [175, 175]),
      rec(15, { type: 'collect' }, [{ kind: 'dish', dish: 'dish_grilled_crucian', quality: 1 }], [150, 150]),
      rec(16, { type: 'eat' }, [{ kind: 'meal', gain: 25 }, { kind: 'energy', delta: 25, reason: 'eat' }], [151, 176]),
      rec(21, { type: 'reel' }, [{ kind: 'level', skill: 'fishing', level: 2, energy: 0 }], [146, 146]),   // q(101)
      rec(27, { type: 'collect' }, [{ kind: 'level', skill: 'cooking', level: 2, energy: 0 }], [165, 165]),
      rec(27, { type: 'eat' }, [{ kind: 'meal', gain: 35 }, { kind: 'energy', delta: 35, reason: 'eat' }], [165, 200]),
      rec(28, { type: 'sell' }, [], [200, 200], 'not_sellable'),
      rec(200, { type: 'harvest' }, [], [200, 200]),   // a later session
    ];
    const [p] = sessionReport(records);
    expect(p).toMatchObject({ player: 'p1', sessions: 2, first: {
      minutes: 28, end_energy: 200, refusals: { not_sellable: 1 },
      milestones: { first_sow: 1, first_cast: 9, first_catch: 10, first_dish: 15, first_meal: 16, fishing_lv2: 21, cooking_lv2: 27 },
    } });
    expect(p.first.spends).toEqual([{ minute: 1, type: 'sow', src: 'hold', energy: 2 }, { minute: 9, type: 'cast', src: 'tap', energy: 5 }]);
    expect(p.first.checks).toMatchObject({ loop_by_20: true, fishing_lv2_by_30: true, cooking_lv2_by_30: true });
  });
});

describe('reading the log (PR #23 review)', () => {
  it('skips a half-written last line and records of unknown kinds instead of failing the report', () => {
    const good = JSON.stringify({ kind: 'command', t: T0, clock: T0, player: 'p-reader-01', seq: 0, cmd: { type: 'rest' }, ok: false,
      code: 'energy_full', detail: {}, energy: [200, 200], events: [] });
    const ui = JSON.stringify({ kind: 'ui', t: T0, player: 'p-reader-01', event: { kind: 'screen', name: 'bag' } });
    const { records, skipped } = parseRecords([good, ui, JSON.stringify({ kind: 'audit', t: T0 }), '{"kind":"command","t":17', ''].join('\n'));
    expect(records).toHaveLength(2);
    expect(skipped).toBe(2);
    expect(sessionReport(records)[0]).toMatchObject({ player: 'p-reader-01', first: { commands: 1 } });
  });

  // C25-4 (user, 10-28): every line carries the player's address — the one P0 takes, never what a client wrote.
  it('records ip: behind Caddy the address Caddy appended, a forged X-Forwarded-For in front ignored', async () => {
    const records: LogRecord[] = [];
    const app = Fastify({ ...trustProxyFromEnv({ P0_TRUST_PROXY: '1' }) });
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => T0, dev: false, log: new P0EventLog(undefined, r => records.push(r)) });
    try {
      const xff = { ...headers, 'x-forwarded-for': '6.6.6.6, 203.0.113.9' };
      await app.inject({ method: 'POST', url: '/v1/p0/commands', remoteAddress: '127.0.0.1', headers: xff, payload: { type: 'rest' } });
      await app.inject({ method: 'POST', url: '/v1/p0/telemetry', remoteAddress: '127.0.0.1', headers: xff, payload: { events: [{ kind: 'screen', name: 'farm' }] } });
      expect(records.map(r => [r.kind, r.ip])).toEqual([['command', '203.0.113.9'], ['ui', '203.0.113.9']]);
      expect(JSON.stringify(records)).not.toContain('6.6.6.6');
    } finally { await app.close(); }
  });

  it('records ip: on a directly published port (no P0_TRUST_PROXY) the socket address, the header ignored', async () => {
    await withServer(async (app, records) => {
      await app.inject({ method: 'POST', url: '/v1/p0/commands', remoteAddress: '192.0.2.4', headers: { ...headers, 'x-forwarded-for': '6.6.6.6' }, payload: { type: 'rest' } });
      expect(records[0]).toMatchObject({ kind: 'command', ip: '192.0.2.4' });
    });
  });

  it('the session report reads lines with and without ip (old days stay readable)', () => {
    const base = { kind: 'command', t: T0, clock: T0, player: 'p-ip-compat', seq: 0, cmd: { type: 'rest' }, ok: true, energy: [200, 200], events: [] };
    const { records, skipped } = parseRecords([JSON.stringify(base), JSON.stringify({ ...base, seq: 1, ip: '203.0.113.9' })].join('\n'));
    expect(skipped).toBe(0);
    expect(records).toHaveLength(2);
  });

  it('P0_EVENT_KEEP_DAYS: a new day removes day files older than N days; unset keeps them all', async () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-events-'));
    try {
      const events = path.join(dir, 'events');
      mkdirSync(events);
      for (const f of ['p0-events-2026-09-01.jsonl', 'p0-events-2026-09-07.jsonl', 'p0-events-2026-09-08.jsonl', 'notes.txt']) writeFileSync(path.join(events, f), '');
      new P0EventLog(events).write({ kind: 'ui', t: T0, player: 'p', event: { kind: 'screen' } });
      expect(readdirSync(events)).toHaveLength(5);   // unset: nothing removed
      new P0EventLog(events, undefined, undefined, 30).write({ kind: 'ui', t: T0, player: 'p', event: { kind: 'screen' } });   // T0 is 2026-10-08
      expect(readdirSync(events).sort()).toEqual(['notes.txt', 'p0-events-2026-09-08.jsonl', 'p0-events-2026-10-08.jsonl']);
      expect(existsSync(path.join(events, 'p0-events-2026-09-07.jsonl'))).toBe(false);
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
// SGODOT-486: client errors in their own files, tied to no player (奕星 / 李白 11-12; privacy policy §2 / §6).
describe('client errors (SGODOT-486)', () => {
  async function withErrors(fn: (app: ReturnType<typeof Fastify>, errors: ErrorRecord[], records: LogRecord[], tick: (ms: number) => void) => Promise<void>) {
    const errors: ErrorRecord[] = [], records: LogRecord[] = [];
    let now = T0;
    const app = Fastify();
    registerP0Routes(app, { content: c, store: new P0Store(c), now: () => now, dev: false,
      log: new P0EventLog(undefined, r => records.push(r)), errors: new P0EventLog<ErrorRecord>(undefined, r => errors.push(r), undefined, 30, 'p0-errors') });
    try { await fn(app, errors, records, ms => { now += ms; }); } finally { await app.close(); }
  }
  const stack = Array.from({ length: 25 }, (_, i) => `f${i} res://a.gd:${i}` + (i === 0 ? 'x'.repeat(300) : '')).join('\n');

  it('writes t, version, platform, message, stack and scene only — never the player, the IP or other fields', async () => {
    await withErrors(async (app, errors, records) => {
      const r = await app.inject({ method: 'POST', url: '/v1/p0/telemetry',
        headers: { ...headers, 'x-p0-version': '310', 'x-p0-platform': 'android', 'x-p0-channel': 'play' },
        payload: { events: [{ kind: 'client_error', message: 'm'.repeat(600), stack, scene: 's'.repeat(100), model: 'Pixel 7', player: 'x' },
          { kind: 'screen', name: 'farm' }] } });
      expect(r.json()).toEqual({ ok: true, accepted: 2 });
      expect(errors).toHaveLength(1);
      const e = errors[0];
      expect(Object.keys(e)).toEqual(['t', 'version', 'platform', 'message', 'stack', 'scene']);
      expect(e).toMatchObject({ t: T0, version: '310', platform: 'android', message: 'm'.repeat(500), scene: 's'.repeat(64) });
      const lines = e.stack.split('\n');
      expect(lines).toHaveLength(20);
      expect(lines[0]).toHaveLength(200);
      expect(lines[19]).toBe('f19 res://a.gd:19');
      expect(JSON.stringify(e)).not.toMatch(/telemetry-player|127\.0\.0\.1|play|Pixel/);
      // the observation log gets the UI moment but not the error
      expect(records.map(x => x.kind === 'ui' && x.event.kind)).toEqual(['screen']);
    });
  });

  it('no platform header (clients before PR-A): the field is left out, no error', async () => {
    await withErrors(async (app, errors) => {
      await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: [{ kind: 'client_error', message: 'boom', stack: 'f a.gd:1', scene: 'farm' }] } });
      expect(errors).toEqual([{ t: T0, message: 'boom', stack: 'f a.gd:1', scene: 'farm' }]);
    });
  });

  it('drops an error without a message; a missing stack or scene is written empty', () => {
    expect(errorRecord({ kind: 'client_error', stack: 'x' }, T0, {})).toBeNull();
    expect(errorRecord({ kind: 'client_error', message: 7 }, T0, {})).toBeNull();
    expect(errorRecord({ kind: 'screen', message: 'x' }, T0, {})).toBeNull();
    expect(errorRecord({ kind: 'client_error', message: 'x', stack: ['a'], scene: 3 }, T0, {})).toEqual({ t: T0, message: 'x', stack: '', scene: '' });
  });

  it('platform only android / ios / desktop; 32+ hex digits cut out of message and stack (#1013 周瑜)', () => {
    const hex = 'a1B2c3D4'.repeat(4);   // 32
    const e = errorRecord({ kind: 'client_error', message: `bad token ${hex}ff here, sha ${hex.slice(0, 31)}`, stack: `f a.gd:1 ${hex}` }, T0,
      { 'x-p0-platform': 'windows' });
    expect(e).toEqual({ t: T0, message: `bad token … here, sha ${hex.slice(0, 31)}`, stack: 'f a.gd:1 …', scene: '' });
    expect(errorRecord({ kind: 'client_error', message: 'x' }, T0, { 'x-p0-platform': 'ios' })?.platform).toBe('ios');
  });

  it('at most 10 a minute per player, counted apart from UI moments; a new minute starts over', async () => {
    await withErrors(async (app, errors, records, tick) => {
      const err = { kind: 'client_error', message: 'boom' };
      const r = await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: [...Array(15).fill(err), { kind: 'screen' }] } });
      expect(r.json()).toEqual({ ok: true, accepted: 11 });
      expect(errors).toHaveLength(10);
      expect(records).toHaveLength(1);
      await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers: { 'x-p0-player': 'telemetry-player-2' }, payload: { events: [err] } });
      expect(errors).toHaveLength(11);   // another player has their own 10
      tick(60_000);
      await app.inject({ method: 'POST', url: '/v1/p0/telemetry', headers, payload: { events: [err] } });
      expect(errors).toHaveLength(12);
    });
  });

  it('files: p0-errors-YYYY-MM-DD.jsonl beside the events, its own 30 days; the events files untouched', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-errors-'));
    try {
      for (const f of ['p0-errors-2026-09-07.jsonl', 'p0-errors-2026-09-08.jsonl', 'p0-events-2026-09-01.jsonl']) writeFileSync(path.join(dir, f), '');
      new P0EventLog<ErrorRecord>(dir, undefined, undefined, 30, 'p0-errors').write({ t: T0, message: 'boom', stack: '', scene: 'farm' });   // T0 is 2026-10-08
      expect(readdirSync(dir).sort()).toEqual(['p0-errors-2026-09-08.jsonl', 'p0-errors-2026-10-08.jsonl', 'p0-events-2026-09-01.jsonl']);
      expect(JSON.parse(readFileSync(path.join(dir, 'p0-errors-2026-10-08.jsonl'), 'utf8'))).toEqual({ t: T0, message: 'boom', stack: '', scene: 'farm' });
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });

  it('prune(now): with no new error a file older than 30 days still goes; without keep days nothing does (#1013 后裔)', () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'p0-errors-'));
    try {
      for (const f of ['p0-errors-2026-09-07.jsonl', 'p0-errors-2026-09-08.jsonl', 'p0-events-2026-09-01.jsonl']) writeFileSync(path.join(dir, f), '');
      new P0EventLog<ErrorRecord>(dir, undefined, undefined, undefined, 'p0-errors').prune(T0);
      expect(readdirSync(dir)).toHaveLength(3);
      const errors = new P0EventLog<ErrorRecord>(dir, undefined, undefined, 30, 'p0-errors');
      errors.prune(T0);   // 2026-10-08: 09-07 is 31 days old
      expect(readdirSync(dir).sort()).toEqual(['p0-errors-2026-09-08.jsonl', 'p0-events-2026-09-01.jsonl']);
      errors.prune(T0 + 86_400_000);
      expect(readdirSync(dir)).toEqual(['p0-events-2026-09-01.jsonl']);   // the events file is the other log's
    } finally { rmSync(dir, { recursive: true, force: true }); }
  });
});
