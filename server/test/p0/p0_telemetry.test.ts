/** SGODOT-232 S7: the observation log (one line per command, plus reported UI moments) and the session report. */
import Fastify from 'fastify';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { describe, expect, it } from 'vitest';
import { loadP0Content } from '../../src/p0/content.js';
import { registerP0Routes } from '../../src/p0/routes.js';
import { P0Store } from '../../src/p0/store.js';
import { settleEnergy } from '../../src/p0/rules.js';
import { commandFields, P0EventLog, uiEvent, type LogRecord } from '../../src/p0/telemetry.js';
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
        { kind: 'ui', t: T0, player: 'telemetry-player', event: { kind: 'tip_shown', key: 's'.repeat(64) } },
        { kind: 'ui', t: T0, player: 'telemetry-player', event: { kind: 'card_shown' } }]);
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
      rec(21, { type: 'reel' }, [{ kind: 'level', skill: 'fishing', level: 2, energy: 50 }], [148, 198]),
      rec(27, { type: 'collect' }, [{ kind: 'level', skill: 'cooking', level: 2, energy: 0 }], [213, 213]),
      rec(28, { type: 'sell' }, [], [213, 213], 'not_sellable'),
      rec(200, { type: 'harvest' }, [], [200, 200]),   // a later session
    ];
    const [p] = sessionReport(records);
    expect(p).toMatchObject({ player: 'p1', sessions: 2, first: {
      minutes: 28, end_energy: 213, refusals: { not_sellable: 1 },
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
});
